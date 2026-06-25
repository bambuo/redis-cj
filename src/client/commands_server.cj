package redis.client
import std.convert.*
import std.collection.*

// ====================================================================
// 服务器命令 (Server Commands)
// ====================================================================

extend RedisClient {
    // -------- 信息 --------

    public func info(section!: String = "default"): String {
        expectBlobVal(executeString(["INFO", section]), "INFO").toUtf8()
    }

    public func dbsize(): Int64 {
        expectInt(executeString(["DBSIZE"]), "DBSIZE")
    }

    public func time(): (Int64, Int64) {
        match (executeString(["TIME"])) {
            case RESPValue.Array(Some(items)) =>
                if (items.size >= 2) {
                    let sec = Int64.parse(asString(items[0]).getOrThrow())
                    let usec = Int64.parse(asString(items[1]).getOrThrow())
                    (sec, usec)
                } else { throw ProtocolError("TIME 返回格式错误") }
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("TIME 返回意外类型")
        }
    }

    public func role(): String {
        match (executeString(["ROLE"])) {
            case RESPValue.Array(Some(items)) => asString(items[0]).getOrThrow()
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("ROLE 返回意外类型")
        }
    }

    /// 返回最近一次保存的时间戳
    public func lastsave(): Int64 {
        expectInt(executeString(["LASTSAVE"]), "LASTSAVE")
    }

    // -------- CLIENT 管理 --------

    public func clientList(): String {
        expectBlobVal(executeString(["CLIENT", "LIST"]), "CLIENT LIST").toUtf8()
    }

    public func clientSetName(name: String): Unit {
        expectOK(executeString(["CLIENT", "SETNAME", name]), "CLIENT SETNAME")
    }

    public func clientGetName(): Option<String> {
        match (executeString(["CLIENT", "GETNAME"])) {
            case RESPValue.BulkString(Some(blob)) => Some(blob.toUtf8())
            case RESPValue.BulkString(None) => None
            case RESPValue.Null => None
            case RESPValue.Null => None
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("CLIENT GETNAME 返回意外类型")
        }
    }

    public func clientPause(timeoutMs: Int64): Unit {
        expectOK(executeString(["CLIENT", "PAUSE", "${timeoutMs}"]), "CLIENT PAUSE")
    }

    /// 阻塞客户端连接
    public func clientUnblock(clientId: Int64, error!: Bool = false): Bool {
        let args = ArrayList<String>(); args.add("CLIENT"); args.add("UNBLOCK"); args.add("${clientId}")
        if (error) { args.add("ERROR") }
        let resp = executeString(collectArray(args.iterator()))
        match (resp) {
            case RESPValue.Integer(1) => true
            case RESPValue.Integer(0) => false
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("CLIENT UNBLOCK 返回意外类型")
        }
    }

    // -------- CONFIG 管理 --------

    public func configGet(pattern: String): Array<(String, String)> {
        match (executeString(["CONFIG", "GET", pattern])) {
            case RESPValue.Array(Some(items)) =>
                let result = ArrayList<(String, String)>()
                var i: Int64 = 0
                while (i + 1 < items.size) {
                    match ((asString(items[i]), asString(items[i + 1]))) {
                        case (Some(k), Some(v)) => result.add((k, v))
                        case _ => ()
                    }
                    i += 2
                }
                collectArray(result.iterator())
            case RESPValue.Map(pairs) =>
                // RESP3: Map 类型
                let result = ArrayList<(String, String)>()
                for ((k, v) in pairs) {
                    match ((asString(k), asString(v))) {
                        case (Some(key), Some(val)) => result.add((key, val))
                        case _ => ()
                    }
                }
                collectArray(result.iterator())
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("CONFIG GET 返回意外类型")
        }
    }

    public func configSet(parameter: String, value: String): Unit {
        expectOK(executeString(["CONFIG", "SET", parameter, value]), "CONFIG SET")
    }

    public func configResetStat(): Unit {
        expectOK(executeString(["CONFIG", "RESETSTAT"]), "CONFIG RESETSTAT")
    }

    /// 重写配置文件
    public func configRewrite(): Unit {
        expectOK(executeString(["CONFIG", "REWRITE"]), "CONFIG REWRITE")
    }

    // -------- SLOWLOG --------

    public func slowLogGet(count!: Int64 = -1): Array<RESPValue> {
        match (executeString(["SLOWLOG", "GET", "${count}"])) {
            case RESPValue.Array(Some(items)) => items
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("SLOWLOG GET 返回意外类型")
        }
    }

    public func slowLogLen(): Int64 {
        expectInt(executeString(["SLOWLOG", "LEN"]), "SLOWLOG LEN")
    }

    public func slowLogReset(): Unit {
        expectOK(executeString(["SLOWLOG", "RESET"]), "SLOWLOG RESET")
    }

    // -------- COMMAND --------

    /// 获取命令信息
    public func commandInfo(commandNames: Array<String>): Array<RESPValue> {
        let args = ArrayList<String>(); args.add("COMMAND"); args.add("INFO")
        for (n in commandNames) { args.add(n) }
        match (executeString(collectArray(args.iterator()))) {
            case RESPValue.Array(Some(items)) => items
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("COMMAND INFO 返回意外类型")
        }
    }

    public func commandStats(): Array<RESPValue> {
        match (executeString(["COMMAND", "STATS"])) {
            case RESPValue.Array(Some(items)) => items
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("COMMAND STATS 返回意外类型")
        }
    }

    public func commandCount(): Int64 {
        expectInt(executeString(["COMMAND", "COUNT"]), "COMMAND COUNT")
    }

    /// 获取命令列表
    public func commandList(): Array<RESPValue> {
        match (executeString(["COMMAND"])) {
            case RESPValue.Array(Some(items)) => items
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("COMMAND 返回意外类型")
        }
    }

    /// 获取命令对应的键（用于集群路由）
    public func commandGetKeys(command: Array<String>): Array<String> {
        let args = ArrayList<String>(); args.add("COMMAND"); args.add("GETKEYS")
        for (a in command) { args.add(a) }
        match (executeString(collectArray(args.iterator()))) {
            case RESPValue.Array(Some(items)) => extractStringArray(items)
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("COMMAND GETKEYS 返回意外类型")
        }
    }

    // -------- MEMORY --------

    /// 获取键的内存使用量（字节）
    public func memoryUsage(key: String, samples!: Option<Int64> = None): Option<Int64> {
        let args = ArrayList<String>(); args.add("MEMORY"); args.add("USAGE"); args.add(key)
        match (samples) { case Some(n) => args.add("SAMPLES"); args.add("${n}") case None => () }
        match (executeString(collectArray(args.iterator()))) {
            case RESPValue.Integer(n) => Some(n)
            case RESPValue.BulkString(None) => None
            case RESPValue.Null => None
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("MEMORY USAGE 返回意外类型")
        }
    }

    /// 获取内存统计信息
    public func memoryStats(): RESPValue {
        let resp = executeString(["MEMORY", "STATS"])
        match (resp) {
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => resp
        }
    }

    // -------- ACL --------

    /// 列出 ACL 用户
    public func aclUsers(): Array<String> {
        match (executeString(["ACL", "USERS"])) {
            case RESPValue.Array(Some(items)) => extractStringArray(items)
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("ACL USERS 返回意外类型")
        }
    }

    /// 获取 ACL 用户信息
    public func aclGetuser(username: String): RESPValue {
        let resp = executeString(["ACL", "GETUSER", username])
        match (resp) {
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => resp
        }
    }

    /// 创建/修改 ACL 用户
    public func aclSetuser(username: String, rules: Array<String>): Unit {
        let args = ArrayList<String>(); args.add("ACL"); args.add("SETUSER"); args.add(username)
        for (r in rules) { args.add(r) }
        expectOK(executeString(collectArray(args.iterator())), "ACL SETUSER")
    }

    /// 删除 ACL 用户
    public func aclDeluser(usernames: Array<String>): Int64 {
        let args = ArrayList<String>(); args.add("ACL"); args.add("DELUSER")
        for (u in usernames) { args.add(u) }
        expectInt(executeString(collectArray(args.iterator())), "ACL DELUSER")
    }

    /// 生成密码
    public func aclGenpass(bits!: Int64 = 256): String {
        let resp = executeString(["ACL", "GENPASS", "${bits}"])
        expectBlobVal(resp, "ACL GENPASS").toUtf8()
    }

    /// 查看 ACL 类别
    public func aclCat(category!: Option<String> = None): Array<String> {
        let args = ArrayList<String>(); args.add("ACL"); args.add("CAT")
        match (category) { case Some(c) => args.add(c) case None => () }
        match (executeString(collectArray(args.iterator()))) {
            case RESPValue.Array(Some(items)) => extractStringArray(items)
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("ACL CAT 返回意外类型")
        }
    }

    /// 获取 ACL 日志
    public func aclLog(count!: Option<Int64> = None): Array<RESPValue> {
        let args = ArrayList<String>(); args.add("ACL"); args.add("LOG")
        match (count) { case Some(n) => args.add("${n}") case None => () }
        match (executeString(collectArray(args.iterator()))) {
            case RESPValue.Array(Some(items)) => items
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("ACL LOG 返回意外类型")
        }
    }

    // -------- 持久化 --------

    /// 同步保存到磁盘
    public func save(): Unit {
        expectOK(executeString(["SAVE"]), "SAVE")
    }

    /// 后台保存到磁盘
    public func bgsave(): Unit {
        let _ = expectSimpleString(executeString(["BGSAVE"]), "BGSAVE")
    }

    /// 后台重写 AOF
    public func bgrewriteaof(): Unit {
        let _ = expectSimpleString(executeString(["BGREWRITEAOF"]), "BGREWRITEAOF")
    }

    /// 设置复制角色
    public func replicaof(host!: Option<String> = None, port!: Option<Int64> = None): Unit {
        match (host) {
            case Some(h) =>
                expectOK(executeString(["REPLICAOF", h, "${port.getOrThrow()}"]), "REPLICAOF")
            case None =>
                expectOK(executeString(["REPLICAOF", "NO", "ONE"]), "REPLICAOF")
        }
    }

    /// 优雅关闭服务器
    public func shutdown(modifier!: Option<String> = None): Unit {
        let args = ArrayList<String>(); args.add("SHUTDOWN")
        match (modifier) { case Some(m) => args.add(m) case None => () }
        try { executeString(collectArray(args.iterator())) } catch (_: Exception) { /* 关闭时忽略连接中断 */ }
    }

    /// 交换两个数据库
    public func swapdb(db1: Int64, db2: Int64): Unit {
        expectOK(executeString(["SWAPDB", "${db1}", "${db2}"]), "SWAPDB")
    }

    /// LOLWUT（趣味命令）
    public func lolwut(version!: Option<Int64> = None): String {
        let args = ArrayList<String>(); args.add("LOLWUT")
        match (version) { case Some(v) => args.add("${v}") case None => () }
        expectBlobVal(executeString(collectArray(args.iterator())), "LOLWUT").toUtf8()
    }

    // -------- 数据库管理 --------

    public func flushDb(): Unit { expectOK(executeString(["FLUSHDB"]), "FLUSHDB") }
    public func flushAll(): Unit { expectOK(executeString(["FLUSHALL"]), "FLUSHALL") }
}
