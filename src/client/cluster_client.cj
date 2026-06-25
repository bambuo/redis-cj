package redis.client
import std.collection.*
import std.convert.*

/// Redis 集群客户端
///
/// 自动发现集群拓扑，处理 MOVED/ASK 重定向。
/// 支持跨节点的命令执行和槽位感知路由。
///
/// # 用法
/// ```cangjie
/// let cluster = ClusterClient(["127.0.0.1:7000", "127.0.0.1:7001"])
/// cluster.connect()
/// let val = cluster.get("mykey")
/// ```
public class ClusterClient <: Resource {
    private let seedNodes: Array<String>
    private var connections: HashMap<String, RedisConnection>  // "host:port" → connection
    private var slotMap: SlotMap
    private var connected: Bool
    private var maxRedirects: Int64

    /// 创建集群客户端
    /// @param seedNodes 种子节点地址列表，如 ["127.0.0.1:7000"]
    /// @param maxRedirects 最大 MOVED/ASK 重定向次数（默认 5）
    public init(seedNodes: Array<String>, maxRedirects!: Int64 = 5) {
        this.seedNodes = seedNodes
        this.connections = HashMap<String, RedisConnection>()
        this.slotMap = SlotMap()
        this.connected = false
        this.maxRedirects = maxRedirects
    }

    /// 连接到集群并发现拓扑
    public func connect(): Unit {
        for (addr in seedNodes) {
            let (host, port) = parseAddress(addr)
            try {
                let conn = createConnection(host, port)
                let key = "${host}:${port}"
                connections[key] = conn

                // 获取集群槽位信息
                let resp = conn.execute(stringsToBlobs(["CLUSTER", "SLOTS"]))
                slotMap.refresh(resp)
                connected = true
                println("集群连接成功，发现 ${slotMap.mappedSlotCount()} 个槽位映射")
                return
            } catch (e: Exception) {
                println("连接种子节点 ${addr} 失败: ${e.message}")
            }
        }

        if (!connected) {
            throw ConnectionError("无法连接到任何集群种子节点", "", 0u16)
        }
    }

    /// 执行命令（自动处理重定向）
    public func execute(args: Array<Blob>): RESPValue {
        if (!connected) { throw ConnectionError("集群未连接", "", 0u16) }

        // 尝试在合适节点上执行
        var redirects: Int64 = 0
        var lastNode: Option<String> = None

        while (redirects <= maxRedirects) {
            // 确定目标节点
            let targetNode = match (lastNode) {
                case Some(n) => n
                case None => selectNode(args)
            }

            match (connections.get(targetNode)) {
                case Some(conn) =>
                    try {
                        let resp = conn.execute(args)
                        return resp
                    } catch (e: MovedError) {
                        // MOVED 重定向：更新槽位映射并重试
                        redirects++
                        let targetAddr = "${e.targetHost}:${e.targetPort}"
                        ensureConnection(targetAddr)
                        // 更新槽位映射，避免后续命令再次触发 MOVED
                        slotMap.refresh(conn.execute(stringsToBlobs(["CLUSTER", "SLOTS"])))
                        lastNode = Some(targetAddr)
                    } catch (e: AskError) {
                        // ASK 重定向
                        redirects++
                        let targetAddr = "${e.targetHost}:${e.targetPort}"
                        ensureConnection(targetAddr)
                        // 发送 ASKING 命令
                        match (connections.get(targetAddr)) {
                            case Some(c) => c.execute(stringsToBlobs(["ASKING"]))
                            case None => ()
                        }
                        lastNode = Some(targetAddr)
                    }
                case None =>
                    throw ConnectionError("未找到指定节点的连接: ${targetNode}", "", 0u16)
            }
        }

        throw ProtocolError("集群命令重定向次数超过限制 (${maxRedirects})")
    }

    // -------- Resource 接口 --------

    public func close(): Unit {
        for ((_, conn) in connections) {
            try { conn.close() } catch (_) { /* 忽略单个节点关闭错误 */ }
        }
        connections.clear()
        slotMap.clear()
        connected = false
    }

    public func isClosed(): Bool {
        !connected
    }

    // -------- 集群管理 --------

    /// 刷新集群拓扑
    public func refreshSlots(): Unit {
        for ((_, conn) in connections) {
            try {
                let resp = conn.execute(stringsToBlobs(["CLUSTER", "SLOTS"]))
                slotMap.refresh(resp)
                return
            } catch (_) { () }
        }
    }

    /// 获取当前槽位映射
    public func getSlotMap(): SlotMap { slotMap }

    /// 获取所有连接节点
    public func getNodes(): Array<String> {
        let result = ArrayList<String>()
        for ((addr, _) in connections) { result.add(addr) }
        collectArray(result.iterator())
    }

    // -------- 辅助 --------

    /// 根据命令参数选择目标节点
    private func selectNode(args: Array<Blob>): String {
        // 提取键名（大多数命令的第一个参数是键）
        if (args.size >= 2) {
            let keyBytes = args[1].toUtf8()
            match (slotMap.getNode(keyBytes)) {
                case Some(node) => "${node.host}:${node.port}"
                case None =>
                    // 槽位未映射，使用第一个连接
                    for ((addr, _) in connections) { return addr }
                    throw ConnectionError("无可用集群节点", "", 0u16)
            }
        }
        // 没有键参数的命令（如 PING, INFO），使用第一个节点
        for ((addr, _) in connections) { return addr }
        throw ConnectionError("无可用集群节点", "", 0u16)
    }

    /// 确保到指定地址的连接存在
    private func ensureConnection(addr: String): Unit {
        if (!connections.contains(addr)) {
            let (host, port) = parseAddress(addr)
            let conn = createConnection(host, port)
            connections[addr] = conn
        }
    }

    /// 创建到节点的连接
    private func createConnection(host: String, port: String): RedisConnection {
        let portNum = UInt16(Int64.parse(port))
        let transport = TcpTransport(host, portNum)
        let conn = RedisConnection(transport, autoHello: true)
        conn.connect()
        conn
    }

    /// 解析 "host:port" 格式的地址
    private func parseAddress(addr: String): (String, String) {
        match (addr.indexOf(":")) {
            case Some(idx) =>
                (addr[0..idx], addr[idx + 1..])
            case None =>
                (addr, "6379")
        }
    }
}

// -------- ClusterClient 便捷方法（扩展）--------

extend ClusterClient {
    /// 获取键的值
    public func get(key: String): Option<Blob> {
        let resp = execute(stringsToBlobs(["GET", key]))
        match (resp) {
            case RESPValue.BulkString(v) => v
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("GET 返回意外类型")
        }
    }

    /// 设置键值对
    public func set(key: String, value: Blob): Bool {
        let resp = execute([Blob.fromUtf8("SET"), Blob.fromUtf8(key), value])
        match (resp) {
            case RESPValue.SimpleString("OK") => true
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("SET 返回意外类型")
        }
    }

    /// 发送 PING
    public func ping(): String {
        let resp = execute(stringsToBlobs(["PING"]))
        match (resp) {
            case RESPValue.SimpleString(s) => s
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("PING 返回意外类型")
        }
    }

    /// 标记为只读模式（集群从节点）
    public func readonly(): Unit {
        let resp = execute(stringsToBlobs(["READONLY"]))
        match (resp) {
            case RESPValue.SimpleString(_) => ()
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("READONLY 返回意外类型")
        }
    }

    /// 标记为读写模式
    public func readwrite(): Unit {
        let resp = execute(stringsToBlobs(["READWRITE"]))
        match (resp) {
            case RESPValue.SimpleString(_) => ()
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("READWRITE 返回意外类型")
        }
    }

    // -------- 集群内省 --------

    /// 获取键的槽位号
    public func clusterKeyslot(key: String): Int64 {
        let resp = execute(stringsToBlobs(["CLUSTER", "KEYSLOT", key]))
        match (resp) {
            case RESPValue.Integer(n) => n
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("CLUSTER KEYSLOT 返回意外类型")
        }
    }

    /// 获取集群节点信息
    public func clusterNodes(): String {
        let resp = execute(stringsToBlobs(["CLUSTER", "NODES"]))
        expectBlobVal(resp, "CLUSTER NODES").toUtf8()
    }

    /// 获取集群信息
    public func clusterInfo(): String {
        let resp = execute(stringsToBlobs(["CLUSTER", "INFO"]))
        expectBlobVal(resp, "CLUSTER INFO").toUtf8()
    }

    /// 获取指定槽位中的键数量
    public func clusterCountKeysinslot(slot: Int64): Int64 {
        let resp = execute(stringsToBlobs(["CLUSTER", "COUNTKEYSINSLOT", "${slot}"]))
        match (resp) {
            case RESPValue.Integer(n) => n
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("CLUSTER COUNTKEYSINSLOT 返回意外类型")
        }
    }

    /// 获取指定槽位中的键列表
    public func clusterGetkeysinslot(slot: Int64, count: Int64): Array<String> {
        let resp = execute(stringsToBlobs(["CLUSTER", "GETKEYSINSLOT", "${slot}", "${count}"]))
        match (resp) {
            case RESPValue.Array(Some(items)) => extractStringArray(items)
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("CLUSTER GETKEYSINSLOT 返回意外类型")
        }
    }

    // -------- 便捷数据操作 --------

    public func del(key: String): Int64 {
        let resp = execute(stringsToBlobs(["DEL", key]))
        match (resp) {
            case RESPValue.Integer(n) => n
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("DEL 返回意外类型")
        }
    }

    public func exists(key: String): Bool {
        let resp = execute(stringsToBlobs(["EXISTS", key]))
        match (resp) {
            case RESPValue.Integer(n) => n > 0
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("EXISTS 返回意外类型")
        }
    }

    public func expire(key: String, seconds: Int64): Bool {
        let resp = execute(stringsToBlobs(["EXPIRE", key, "${seconds}"]))
        match (resp) {
            case RESPValue.Integer(1) => true
            case RESPValue.Integer(0) => false
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("EXPIRE 返回意外类型")
        }
    }

    public func ttl(key: String): Int64 {
        let resp = execute(stringsToBlobs(["TTL", key]))
        match (resp) {
            case RESPValue.Integer(n) => n
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("TTL 返回意外类型")
        }
    }

    public func incr(key: String): Int64 {
        let resp = execute(stringsToBlobs(["INCR", key]))
        match (resp) {
            case RESPValue.Integer(n) => n
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("INCR 返回意外类型")
        }
    }

    public func lpush(key: String, values: Array<Blob>): Int64 {
        let args = ArrayList<Blob>(); args.add(Blob.fromUtf8("LPUSH")); args.add(Blob.fromUtf8(key))
        for (v in values) { args.add(v) }
        let resp = execute(collectArray(args.iterator()))
        match (resp) {
            case RESPValue.Integer(n) => n
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("LPUSH 返回意外类型")
        }
    }

    public func hset(key: String, field: String, value: Blob): Bool {
        let resp = execute([Blob.fromUtf8("HSET"), Blob.fromUtf8(key), Blob.fromUtf8(field), value])
        match (resp) {
            case RESPValue.Integer(1) => true
            case RESPValue.Integer(0) => false
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("HSET 返回意外类型")
        }
    }

    public func sadd(key: String, members: Array<Blob>): Int64 {
        let args = ArrayList<Blob>(); args.add(Blob.fromUtf8("SADD")); args.add(Blob.fromUtf8(key))
        for (m in members) { args.add(m) }
        let resp = execute(collectArray(args.iterator()))
        match (resp) {
            case RESPValue.Integer(n) => n
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("SADD 返回意外类型")
        }
    }

    public func typeOf(key: String): String {
        let resp = execute(stringsToBlobs(["TYPE", key]))
        match (resp) {
            case RESPValue.SimpleString(s) => s
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("TYPE 返回意外类型")
        }
    }
}
