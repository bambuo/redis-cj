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

    public func clientList(typeFilter!: Option<String> = None, ids!: Array<Int64> = []): String {
        let args = ArrayList<String>(); args.add("CLIENT"); args.add("LIST")
        match (typeFilter) {
            case Some(t) =>
                args.add("TYPE")
                args.add(t)
            case None => ()
        }
        if (ids.size > 0) {
            args.add("ID")
            for (id in ids) { args.add("${id}") }
        }
        expectText(executeString(collectArray(args.iterator())), "CLIENT LIST")
    }

    public func clientHelp(): Array<String> {
        expectStringArray(executeString(["CLIENT", "HELP"]), "CLIENT HELP")
    }

    public func clientSetName(name: String): Unit {
        expectOK(executeString(["CLIENT", "SETNAME", name]), "CLIENT SETNAME")
    }

    public func clientGetName(): Option<String> {
        match (executeString(["CLIENT", "GETNAME"])) {
            case RESPValue.BulkString(Some(blob)) => Some(blob.toUtf8())
            case RESPValue.BulkString(None) => None
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
        configGetMany([pattern])
    }

    public func configHelp(): Array<String> {
        expectStringArray(executeString(["CONFIG", "HELP"]), "CONFIG HELP")
    }

    /// 获取多个配置项（Redis 7.0+ 支持多参数）
    public func configGetMany(parameters: Array<String>): Array<(String, String)> {
        if (parameters.size == 0) {
            throw ProtocolError("CONFIG GET 至少需要一个参数")
        }
        let args = ArrayList<String>(); args.add("CONFIG"); args.add("GET")
        for (p in parameters) { args.add(p) }
        parseConfigGetResult(executeString(collectArray(args.iterator())))
    }

    private func parseConfigGetResult(resp: RESPValue): Array<(String, String)> {
        match (resp) {
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
            case RESPValue.Array(None) => []
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
            case RESPValue.Error(e) => throw createCommandError(e)
            case RESPValue.BulkError(e) => throw createCommandError(e.toUtf8())
            case _ => throw ProtocolError("CONFIG GET: 期望 Array/Map，但收到 ${respValueToString(resp)}")
        }
    }

    private func expectText(resp: RESPValue, cmd: String): String {
        match (resp) {
            case RESPValue.BulkString(Some(blob)) => blob.toUtf8()
            case RESPValue.SimpleString(s) => s
            case RESPValue.VerbatimString(_, blob) => blob.toUtf8()
            case RESPValue.Error(e) => throw createCommandError(e)
            case RESPValue.BulkError(e) => throw createCommandError(e.toUtf8())
            case _ => throw ProtocolError("${cmd}: 期望文本响应，但收到 ${respValueToString(resp)}")
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

    public func slowLogHelp(): Array<String> {
        expectStringArray(executeString(["SLOWLOG", "HELP"]), "SLOWLOG HELP")
    }

    // -------- LATENCY --------

    public func latencyLatest(): Array<RESPValue> {
        match (executeString(["LATENCY", "LATEST"])) {
            case RESPValue.Array(Some(items)) => items
            case RESPValue.Array(None) => []
            case RESPValue.Error(e) => throw createCommandError(e)
            case RESPValue.BulkError(e) => throw createCommandError(e.toUtf8())
            case _ => throw ProtocolError("LATENCY LATEST 返回意外类型")
        }
    }

    public func latencyHistory(event: String): Array<RESPValue> {
        match (executeString(["LATENCY", "HISTORY", event])) {
            case RESPValue.Array(Some(items)) => items
            case RESPValue.Array(None) => []
            case RESPValue.Error(e) => throw createCommandError(e)
            case RESPValue.BulkError(e) => throw createCommandError(e.toUtf8())
            case _ => throw ProtocolError("LATENCY HISTORY 返回意外类型")
        }
    }

    public func latencyDoctor(): String {
        expectText(executeString(["LATENCY", "DOCTOR"]), "LATENCY DOCTOR")
    }

    public func latencyGraph(event: String): String {
        expectText(executeString(["LATENCY", "GRAPH", event]), "LATENCY GRAPH")
    }

    public func latencyHistogram(commands!: Array<String> = []): RESPValue {
        let args = ArrayList<String>(); args.add("LATENCY"); args.add("HISTOGRAM")
        for (c in commands) { args.add(c) }
        let resp = executeString(collectArray(args.iterator()))
        match (resp) {
            case RESPValue.Array(_) | RESPValue.Map(_) => resp
            case RESPValue.Error(e) => throw createCommandError(e)
            case RESPValue.BulkError(e) => throw createCommandError(e.toUtf8())
            case _ => throw ProtocolError("LATENCY HISTOGRAM 返回意外类型")
        }
    }

    public func latencyReset(events!: Array<String> = []): Int64 {
        let args = ArrayList<String>(); args.add("LATENCY"); args.add("RESET")
        for (e in events) { args.add(e) }
        expectInt(executeString(collectArray(args.iterator())), "LATENCY RESET")
    }

    public func latencyHelp(): Array<String> {
        expectStringArray(executeString(["LATENCY", "HELP"]), "LATENCY HELP")
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

    public func commandHelp(): Array<String> {
        expectStringArray(executeString(["COMMAND", "HELP"]), "COMMAND HELP")
    }

    /// 获取命令文档（Redis 7.0+）
    public func commandDocs(commandNames!: Array<String> = []): RESPValue {
        let args = ArrayList<String>(); args.add("COMMAND"); args.add("DOCS")
        for (n in commandNames) { args.add(n) }
        let resp = executeString(collectArray(args.iterator()))
        match (resp) {
            case RESPValue.Error(e) => throw createCommandError(e)
            case RESPValue.BulkError(e) => throw createCommandError(e.toUtf8())
            case _ => resp
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

    /// 获取命令名称列表（Redis 7.0+ COMMAND LIST）
    public func commandListNames(filterBy!: Option<(String, String)> = None): Array<String> {
        let args = ArrayList<String>(); args.add("COMMAND"); args.add("LIST")
        match (filterBy) {
            case Some((filter, value)) =>
                args.add("FILTERBY")
                args.add(filter)
                args.add(value)
            case None => ()
        }
        let resp = executeString(collectArray(args.iterator()))
        match (resp) {
            case RESPValue.Array(Some(items)) => extractStringArray(items)
            case RESPValue.Set(items) => extractStringArray(items)
            case RESPValue.Error(e) => throw createCommandError(e)
            case RESPValue.BulkError(e) => throw createCommandError(e.toUtf8())
            case _ => throw ProtocolError("COMMAND LIST: 期望 Array/Set，但收到 ${respValueToString(resp)}")
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

    /// 获取命令涉及的键及访问标志（Redis 7.0+）
    public func commandGetKeysAndFlags(command: Array<String>): Array<RESPValue> {
        let args = ArrayList<String>(); args.add("COMMAND"); args.add("GETKEYSANDFLAGS")
        for (a in command) { args.add(a) }
        match (executeString(collectArray(args.iterator()))) {
            case RESPValue.Array(Some(items)) => items
            case RESPValue.Error(e) => throw createCommandError(e)
            case RESPValue.BulkError(e) => throw createCommandError(e.toUtf8())
            case _ => throw ProtocolError("COMMAND GETKEYSANDFLAGS 返回意外类型")
        }
    }

    // -------- CLUSTER 查询 --------

    public func clusterShards(): Array<RESPValue> {
        match (executeString(["CLUSTER", "SHARDS"])) {
            case RESPValue.Array(Some(items)) => items
            case RESPValue.Array(None) => []
            case RESPValue.Error(e) => throw createCommandError(e)
            case RESPValue.BulkError(e) => throw createCommandError(e.toUtf8())
            case _ => throw ProtocolError("CLUSTER SHARDS 返回意外类型")
        }
    }

    public func clusterHelp(): Array<String> {
        expectStringArray(executeString(["CLUSTER", "HELP"]), "CLUSTER HELP")
    }

    public func clusterSlots(): Array<RESPValue> {
        match (executeString(["CLUSTER", "SLOTS"])) {
            case RESPValue.Array(Some(items)) => items
            case RESPValue.Array(None) => []
            case RESPValue.Error(e) => throw createCommandError(e)
            case RESPValue.BulkError(e) => throw createCommandError(e.toUtf8())
            case _ => throw ProtocolError("CLUSTER SLOTS 返回意外类型")
        }
    }

    public func clusterNodes(): String {
        expectText(executeString(["CLUSTER", "NODES"]), "CLUSTER NODES")
    }

    public func clusterInfo(): String {
        expectText(executeString(["CLUSTER", "INFO"]), "CLUSTER INFO")
    }

    public func clusterKeyslot(key: String): Int64 {
        expectInt(executeString(["CLUSTER", "KEYSLOT", key]), "CLUSTER KEYSLOT")
    }

    public func clusterCountKeysinslot(slot: Int64): Int64 {
        expectInt(executeString(["CLUSTER", "COUNTKEYSINSLOT", "${slot}"]), "CLUSTER COUNTKEYSINSLOT")
    }

    public func clusterGetkeysinslot(slot: Int64, count: Int64): Array<String> {
        match (executeString(["CLUSTER", "GETKEYSINSLOT", "${slot}", "${count}"])) {
            case RESPValue.Array(Some(items)) => extractStringArray(items)
            case RESPValue.Array(None) => []
            case RESPValue.Error(e) => throw createCommandError(e)
            case RESPValue.BulkError(e) => throw createCommandError(e.toUtf8())
            case _ => throw ProtocolError("CLUSTER GETKEYSINSLOT 返回意外类型")
        }
    }

    public func clusterMyId(): String {
        expectText(executeString(["CLUSTER", "MYID"]), "CLUSTER MYID")
    }

    public func clusterMyShardId(): String {
        expectText(executeString(["CLUSTER", "MYSHARDID"]), "CLUSTER MYSHARDID")
    }

    public func clusterLinks(): Array<RESPValue> {
        match (executeString(["CLUSTER", "LINKS"])) {
            case RESPValue.Array(Some(items)) => items
            case RESPValue.Array(None) => []
            case RESPValue.Error(e) => throw createCommandError(e)
            case RESPValue.BulkError(e) => throw createCommandError(e.toUtf8())
            case _ => throw ProtocolError("CLUSTER LINKS 返回意外类型")
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
            case RESPValue.Error(e) => throw createCommandError(e)
            case RESPValue.BulkError(e) => throw createCommandError(e.toUtf8())
            case _ => resp
        }
    }

    public func memoryDoctor(): String {
        expectBlobVal(executeString(["MEMORY", "DOCTOR"]), "MEMORY DOCTOR").toUtf8()
    }

    public func memoryMallocStats(): String {
        expectBlobVal(executeString(["MEMORY", "MALLOC-STATS"]), "MEMORY MALLOC-STATS").toUtf8()
    }

    public func memoryPurge(): Unit {
        expectOK(executeString(["MEMORY", "PURGE"]), "MEMORY PURGE")
    }

    public func memoryHelp(): Array<String> {
        expectStringArray(executeString(["MEMORY", "HELP"]), "MEMORY HELP")
    }

    // -------- MODULE --------

    public func moduleList(): Array<RESPValue> {
        match (executeString(["MODULE", "LIST"])) {
            case RESPValue.Array(Some(items)) => items
            case RESPValue.Array(None) => []
            case RESPValue.Error(e) => throw createCommandError(e)
            case RESPValue.BulkError(e) => throw createCommandError(e.toUtf8())
            case _ => throw ProtocolError("MODULE LIST 返回意外类型")
        }
    }

    public func moduleHelp(): Array<String> {
        expectStringArray(executeString(["MODULE", "HELP"]), "MODULE HELP")
    }

    // -------- ACL --------

    /// 列出 ACL 规则
    public func aclList(): Array<String> {
        match (executeString(["ACL", "LIST"])) {
            case RESPValue.Array(Some(items)) => extractStringArray(items)
            case RESPValue.Error(e) => throw createCommandError(e)
            case RESPValue.BulkError(e) => throw createCommandError(e.toUtf8())
            case _ => throw ProtocolError("ACL LIST 返回意外类型")
        }
    }

    public func aclHelp(): Array<String> {
        expectStringArray(executeString(["ACL", "HELP"]), "ACL HELP")
    }

    /// 列出 ACL 用户
    public func aclUsers(): Array<String> {
        match (executeString(["ACL", "USERS"])) {
            case RESPValue.Array(Some(items)) => extractStringArray(items)
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("ACL USERS 返回意外类型")
        }
    }

    /// 返回当前认证用户
    public func aclWhoami(): String {
        expectBlobVal(executeString(["ACL", "WHOAMI"]), "ACL WHOAMI").toUtf8()
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

    /// 试运行指定用户执行命令的 ACL 权限
    public func aclDryRun(username: String, command: Array<String>): Unit {
        if (command.size == 0) {
            throw ProtocolError("ACL DRYRUN 至少需要一个命令")
        }
        let args = ArrayList<String>(); args.add("ACL"); args.add("DRYRUN"); args.add(username)
        for (a in command) { args.add(a) }
        expectOK(executeString(collectArray(args.iterator())), "ACL DRYRUN")
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

    public func flushDb(mode!: Option<String> = None): Unit {
        let args = ArrayList<String>(); args.add("FLUSHDB")
        match (mode) { case Some(m) => args.add(m) case None => () }
        expectOK(executeString(collectArray(args.iterator())), "FLUSHDB")
    }

    public func flushAll(mode!: Option<String> = None): Unit {
        let args = ArrayList<String>(); args.add("FLUSHALL")
        match (mode) { case Some(m) => args.add(m) case None => () }
        expectOK(executeString(collectArray(args.iterator())), "FLUSHALL")
    }
}
