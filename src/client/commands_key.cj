package redis.client
import std.convert.*
import std.collection.*

// ====================================================================
// 通用键命令 (Key Commands)
// ====================================================================

extend RedisClient {
    // -------- 查询 --------

    /// 检查键是否存在。返回存在的键个数。
    public func exists(keys: Array<String>): Int64 {
        let args = ArrayList<String>(); args.add("EXISTS")
        for (k in keys) { args.add(k) }
        let resp = executeString(collectArray(args.iterator()))
        expectInt(resp, "EXISTS")
    }

    /// 获取键的类型
    public func typeOf(key: String): String {
        let resp = executeString(["TYPE", key])
        asString(resp).getOrThrow()
    }

    /// 获取键的 TTL（秒），-1 无过期，-2 不存在
    public func ttl(key: String): Int64 {
        let resp = executeString(["TTL", key])
        expectInt(resp, "TTL")
    }

    /// 获取键的 TTL（毫秒）
    public func pttl(key: String): Int64 {
        let resp = executeString(["PTTL", key])
        expectInt(resp, "PTTL")
    }

    /// 查找符合模式的键（生产环境慎用，推荐 SCAN）
    public func keys(pattern: String): Array<String> {
        let resp = executeString(["KEYS", pattern])
        match (resp) {
            case RESPValue.Array(Some(items)) => extractStringArray(items)
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("KEYS 返回意外类型")
        }
    }

    // -------- 删除 --------

    /// 删除一个或多个键。返回被删除的键数。
    public func del(keys: Array<String>): Int64 {
        let args = ArrayList<String>(); args.add("DEL")
        for (k in keys) { args.add(k) }
        let resp = executeString(collectArray(args.iterator()))
        expectInt(resp, "DEL")
    }

    /// 非阻塞删除（在后台线程回收内存）。返回取消链接的键数。
    public func unlink(keys: Array<String>): Int64 {
        let args = ArrayList<String>(); args.add("UNLINK")
        for (k in keys) { args.add(k) }
        let resp = executeString(collectArray(args.iterator()))
        expectInt(resp, "UNLINK")
    }

    // -------- 过期 --------

    /// 设置键的过期时间（秒）
    public func expire(key: String, seconds: Int64, condition!: Option<String> = None): Bool {
        let args = ArrayList<String>(); args.add("EXPIRE"); args.add(key); args.add("${seconds}")
        match (condition) { case Some(c) => args.add(c) case None => () }
        let resp = executeString(collectArray(args.iterator()))
        expectBool(resp, "EXPIRE")
    }

    /// 设置键的过期时间（毫秒）
    public func pexpire(key: String, milliseconds: Int64, condition!: Option<String> = None): Bool {
        let args = ArrayList<String>(); args.add("PEXPIRE"); args.add(key); args.add("${milliseconds}")
        match (condition) { case Some(c) => args.add(c) case None => () }
        let resp = executeString(collectArray(args.iterator()))
        expectBool(resp, "PEXPIRE")
    }

    /// 设置键在指定时间戳过期（秒级时间戳）
    public func expireAt(key: String, timestamp: Int64, condition!: Option<String> = None): Bool {
        let args = ArrayList<String>(); args.add("EXPIREAT"); args.add(key); args.add("${timestamp}")
        match (condition) { case Some(c) => args.add(c) case None => () }
        let resp = executeString(collectArray(args.iterator()))
        expectBool(resp, "EXPIREAT")
    }

    /// 移除键的过期时间
    public func persist(key: String): Bool {
        let resp = executeString(["PERSIST", key])
        expectBool(resp, "PERSIST")
    }

    // -------- 重命名 --------

    /// 重命名键
    public func rename(key: String, newKey: String): Unit {
        let resp = executeString(["RENAME", key, newKey])
        expectOK(resp, "RENAME")
    }

    /// 仅在 newKey 不存在时重命名
    public func renamenx(key: String, newKey: String): Bool {
        let resp = executeString(["RENAMENX", key, newKey])
        expectBool(resp, "RENAMENX")
    }

    /// 复制键到目标数据库
    public func copyKeys(key: String, newKey: String, db!: Option<Int64> = None, replace!: Bool = false): Bool {
        let args = ArrayList<String>(); args.add("COPY"); args.add(key); args.add(newKey)
        match (db) { case Some(n) => args.add("DB"); args.add("${n}") case None => () }
        if (replace) { args.add("REPLACE") }
        let resp = executeString(collectArray(args.iterator()))
        expectBool(resp, "COPY")
    }

    /// 移动键到另一个数据库
    public func move(key: String, db: Int64): Bool {
        let resp = executeString(["MOVE", key, "${db}"])
        expectBool(resp, "MOVE")
    }

    // -------- 序列化 --------

    /// 序列化键的值。返回二进制安全的字符串。
    public func dump(key: String): Option<Blob> {
        let resp = executeString(["DUMP", key])
        expectBlob(resp, "DUMP")
    }

    /// 反序列化并恢复键的值
    public func restore(key: String, ttl: Int64, serializedValue: Blob,
                        replace!: Bool = false,
                        absTtl!: Bool = false,
                        idleTime!: Option<Int64> = None,
                        freq!: Option<Int64> = None,
                        asking!: Bool = false): Unit {
        let args = ArrayList<Blob>()
        args.add(Blob.fromUtf8(if (asking) { "RESTORE-ASKING" } else { "RESTORE" }))
        args.add(Blob.fromUtf8(key))
        args.add(Blob.fromUtf8("${ttl}")); args.add(serializedValue)
        if (replace) { args.add(Blob.fromUtf8("REPLACE")) }
        if (absTtl) { args.add(Blob.fromUtf8("ABSTTL")) }
        match (idleTime) {
            case Some(t) => args.add(Blob.fromUtf8("IDLETIME")); args.add(Blob.fromUtf8("${t}"))
            case None => ()
        }
        match (freq) {
            case Some(f) => args.add(Blob.fromUtf8("FREQ")); args.add(Blob.fromUtf8("${f}"))
            case None => ()
        }
        let resp = execute(collectArray(args.iterator()))
        expectOK(resp, "RESTORE")
    }

    public func restoreAsking(key: String, ttl: Int64, serializedValue: Blob,
                              replace!: Bool = false,
                              absTtl!: Bool = false,
                              idleTime!: Option<Int64> = None,
                              freq!: Option<Int64> = None): Unit {
        restore(key, ttl, serializedValue, replace: replace, absTtl: absTtl, idleTime: idleTime, freq: freq, asking: true)
    }

    // -------- 排序 --------

    /// 对列表/集合/有序集合进行排序
    public func sort(key: String, by!: Option<String> = None, limit!: Option<(Int64, Int64)> = None,
                     get!: Array<String> = [], order!: Option<String> = None,
                     alpha!: Bool = false, store!: Option<String> = None): Array<Blob> {
        let args = ArrayList<String>(); args.add("SORT"); args.add(key)
        match (by) { case Some(b) => args.add("BY"); args.add(b) case None => () }
        match (limit) { case Some((o, c)) => args.add("LIMIT"); args.add("${o}"); args.add("${c}") case None => () }
        for (g in get) { args.add("GET"); args.add(g) }
        match (order) { case Some(o) => args.add(o) case None => () }
        if (alpha) { args.add("ALPHA") }
        match (store) { case Some(s) => args.add("STORE"); args.add(s) case None => () }
        let resp = executeString(collectArray(args.iterator()))
        match (resp) {
            case RESPValue.Array(Some(items)) => extractBlobArray(items)
            case RESPValue.Integer(n) => Array<Blob>()  // STORE 选项返回整数
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("SORT 返回意外类型")
        }
    }

    /// SORT_RO：只读排序，不支持 STORE。
    public func sortRo(key: String, by!: Option<String> = None, limit!: Option<(Int64, Int64)> = None,
                       get!: Array<String> = [], order!: Option<String> = None,
                       alpha!: Bool = false): Array<Blob> {
        let args = ArrayList<String>(); args.add("SORT_RO"); args.add(key)
        match (by) { case Some(b) => args.add("BY"); args.add(b) case None => () }
        match (limit) { case Some((o, c)) => args.add("LIMIT"); args.add("${o}"); args.add("${c}") case None => () }
        for (g in get) { args.add("GET"); args.add(g) }
        match (order) { case Some(o) => args.add(o) case None => () }
        if (alpha) { args.add("ALPHA") }
        match (executeString(collectArray(args.iterator()))) {
            case RESPValue.Array(Some(items)) => extractBlobArray(items)
            case RESPValue.Error(e) => throw createCommandError(e)
            case RESPValue.BulkError(e) => throw createCommandError(e.toUtf8())
            case _ => throw ProtocolError("SORT_RO 返回意外类型")
        }
    }

    /// SORT ... STORE：返回存储到目标键的元素个数。
    public func sortStore(key: String, destination: String,
                          by!: Option<String> = None,
                          limit!: Option<(Int64, Int64)> = None,
                          get!: Array<String> = [],
                          order!: Option<String> = None,
                          alpha!: Bool = false): Int64 {
        let args = ArrayList<String>(); args.add("SORT"); args.add(key)
        match (by) { case Some(b) => args.add("BY"); args.add(b) case None => () }
        match (limit) { case Some((o, c)) => args.add("LIMIT"); args.add("${o}"); args.add("${c}") case None => () }
        for (g in get) { args.add("GET"); args.add(g) }
        match (order) { case Some(o) => args.add(o) case None => () }
        if (alpha) { args.add("ALPHA") }
        args.add("STORE"); args.add(destination)
        expectInt(executeString(collectArray(args.iterator())), "SORT STORE")
    }

    // -------- SCAN 迭代 --------

    /// 渐进式扫描键空间（返回游标和键列表）
    public func scan(cursor: Int64, pattern!: Option<String> = None,
                     count!: Option<Int64> = None,
                     typeFilter!: Option<String> = None): (Int64, Array<String>) {
        let args = ArrayList<String>(); args.add("SCAN"); args.add("${cursor}")
        match (pattern) { case Some(p) => args.add("MATCH"); args.add(p) case None => () }
        match (count) { case Some(c) => args.add("COUNT"); args.add("${c}") case None => () }
        match (typeFilter) { case Some(t) => args.add("TYPE"); args.add(t) case None => () }
        parseScanResult(executeString(collectArray(args.iterator())))
    }

    /// 渐进式扫描哈希表字段
    public func hscan(key: String, cursor: Int64, pattern!: Option<String> = None,
                      count!: Option<Int64> = None): (Int64, Array<String>) {
        let args = ArrayList<String>(); args.add("HSCAN"); args.add(key); args.add("${cursor}")
        match (pattern) { case Some(p) => args.add("MATCH"); args.add(p) case None => () }
        match (count) { case Some(c) => args.add("COUNT"); args.add("${c}") case None => () }
        parseScanResult(executeString(collectArray(args.iterator())))
    }

    /// 渐进式扫描哈希表字段和值，返回结构化 field/value 对。
    public func hscanEntries(key: String, cursor: Int64, pattern!: Option<String> = None,
                             count!: Option<Int64> = None): (Int64, Array<(String, Blob)>) {
        let args = ArrayList<String>(); args.add("HSCAN"); args.add(key); args.add("${cursor}")
        match (pattern) { case Some(p) => args.add("MATCH"); args.add(p) case None => () }
        match (count) { case Some(c) => args.add("COUNT"); args.add("${c}") case None => () }
        let (nextCursor, items) = parseScanItems(executeString(collectArray(args.iterator())), "HSCAN")
        (nextCursor, parseHashScanEntries(items))
    }

    /// 渐进式扫描集合成员
    public func sscan(key: String, cursor: Int64, pattern!: Option<String> = None,
                      count!: Option<Int64> = None): (Int64, Array<String>) {
        let args = ArrayList<String>(); args.add("SSCAN"); args.add(key); args.add("${cursor}")
        match (pattern) { case Some(p) => args.add("MATCH"); args.add(p) case None => () }
        match (count) { case Some(c) => args.add("COUNT"); args.add("${c}") case None => () }
        parseScanResult(executeString(collectArray(args.iterator())))
    }

    /// 渐进式扫描有序集合成员
    public func zscan(key: String, cursor: Int64, pattern!: Option<String> = None,
                      count!: Option<Int64> = None): (Int64, Array<String>) {
        let args = ArrayList<String>(); args.add("ZSCAN"); args.add(key); args.add("${cursor}")
        match (pattern) { case Some(p) => args.add("MATCH"); args.add(p) case None => () }
        match (count) { case Some(c) => args.add("COUNT"); args.add("${c}") case None => () }
        parseScanResult(executeString(collectArray(args.iterator())))
    }

    /// 渐进式扫描有序集合成员和分值，返回结构化 member/score 对。
    public func zscanWithScores(key: String, cursor: Int64, pattern!: Option<String> = None,
                                count!: Option<Int64> = None): (Int64, Array<(Blob, Float64)>) {
        let args = ArrayList<String>(); args.add("ZSCAN"); args.add(key); args.add("${cursor}")
        match (pattern) { case Some(p) => args.add("MATCH"); args.add(p) case None => () }
        match (count) { case Some(c) => args.add("COUNT"); args.add("${c}") case None => () }
        let (nextCursor, items) = parseScanItems(executeString(collectArray(args.iterator())), "ZSCAN")
        (nextCursor, parseZSetScanEntries(items))
    }

    // -------- 随机与杂项 --------

    /// 返回一个随机键
    public func randomKey(): Option<Blob> {
        let resp = executeString(["RANDOMKEY"])
        expectBlob(resp, "RANDOMKEY")
    }

    /// 触摸键（更新 LRU 时间）。返回触摸的键数。
    public func touch(keys: Array<String>): Int64 {
        let args = ArrayList<String>(); args.add("TOUCH")
        for (k in keys) { args.add(k) }
        let resp = executeString(collectArray(args.iterator()))
        expectInt(resp, "TOUCH")
    }

    // -------- 辅助 --------

    private func parseScanResult(resp: RESPValue): (Int64, Array<String>) {
        let (cursor, items) = parseScanItems(resp, "SCAN")
        (cursor, extractStringArray(items))
    }

    private func parseScanItems(resp: RESPValue, cmd: String): (Int64, Array<RESPValue>) {
        match (resp) {
            case RESPValue.Array(Some(items)) =>
                if (items.size >= 2) {
                    let cursorStr = asString(items[0]).getOrThrow()
                    let newCursor = Int64.parse(cursorStr)
                    let values = match (items[1]) {
                        case RESPValue.Array(Some(k)) => k
                        case _ => Array<RESPValue>()
                    }
                    (newCursor, values)
                } else { (0, Array<RESPValue>()) }
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("${cmd} 返回意外类型")
        }
    }

    private func parseHashScanEntries(items: Array<RESPValue>): Array<(String, Blob)> {
        let result = ArrayList<(String, Blob)>()
        var i: Int64 = 0
        while (i + 1 < items.size) {
            match ((asString(items[i]), asBlob(items[i + 1]))) {
                case (Some(field), Some(value)) => result.add((field, value))
                case _ => throw ProtocolError("HSCAN 返回字段/值格式错误")
            }
            i += 2
        }
        collectArray(result.iterator())
    }

    private func parseZSetScanEntries(items: Array<RESPValue>): Array<(Blob, Float64)> {
        let result = ArrayList<(Blob, Float64)>()
        var i: Int64 = 0
        while (i + 1 < items.size) {
            match ((asBlob(items[i]), asString(items[i + 1]))) {
                case (Some(member), Some(score)) => result.add((member, Float64.parse(score)))
                case _ => throw ProtocolError("ZSCAN 返回成员/分值格式错误")
            }
            i += 2
        }
        collectArray(result.iterator())
    }
// removed premature close

    // -------- 新增键命令 --------

    public func expiretime(key: String): Int64 {
        expectInt(executeString(["EXPIRETIME", key]), "EXPIRETIME")
    }

    public func pexpireat(key: String, millisecondsTimestamp: Int64,
                          condition!: Option<String> = None): Bool {
        let args = ArrayList<String>(); args.add("PEXPIREAT"); args.add(key); args.add("${millisecondsTimestamp}")
        match (condition) { case Some(c) => args.add(c) case None => () }
        expectBool(executeString(collectArray(args.iterator())), "PEXPIREAT")
    }

    public func pexpiretime(key: String): Int64 {
        expectInt(executeString(["PEXPIRETIME", key]), "PEXPIRETIME")
    }

    public func wait(numreplicas: Int64, timeout: Int64): Int64 {
        expectInt(executeString(["WAIT", "${numreplicas}", "${timeout}"]), "WAIT")
    }

    public func objectEncode(key: String): String {
        expectBlobVal(executeString(["OBJECT", "ENCODING", key]), "OBJECT ENCODING").toUtf8()
    }

    public func objectHelp(): Array<String> {
        expectStringArray(executeString(["OBJECT", "HELP"]), "OBJECT HELP")
    }

    public func objectIdletime(key: String): Int64 {
        expectInt(executeString(["OBJECT", "IDLETIME", key]), "OBJECT IDLETIME")
    }

    public func objectFreq(key: String): Int64 {
        expectInt(executeString(["OBJECT", "FREQ", key]), "OBJECT FREQ")
    }

    public func objectRefcount(key: String): Int64 {
        expectInt(executeString(["OBJECT", "REFCOUNT", key]), "OBJECT REFCOUNT")
    }

    public func migrate(host: String, port: Int64, key: String, destinationDb: Int64,
                        timeout: Int64, copy!: Bool = false, replace!: Bool = false,
                        keys!: Array<String> = []): Unit {
        let args = ArrayList<String>(); args.add("MIGRATE"); args.add(host); args.add("${port}")
        if (keys.size > 0) {
            args.add(""); args.add("${destinationDb}"); args.add("${timeout}")
            args.add("KEYS"); for (k in keys) { args.add(k) }
        } else {
            args.add(key); args.add("${destinationDb}"); args.add("${timeout}")
        }
        if (copy) { args.add("COPY") }
        if (replace) { args.add("REPLACE") }
        expectOK(executeString(collectArray(args.iterator())), "MIGRATE")
    }
}
