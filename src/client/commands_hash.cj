package redis.client
import std.collection.*

// ====================================================================
// 哈希命令 (Hash Commands)
// ====================================================================

extend RedisClient {
    // -------- 写入操作 --------

    /// 设置哈希表中字段的值。返回是否新增字段（而非更新）。
    public func hset(key: String, field: String, value: Blob): Bool {
        let resp = execute([
            Blob.fromUtf8("HSET"), Blob.fromUtf8(key),
            Blob.fromUtf8(field), value,
        ])
        match (resp) {
            case RESPValue.Integer(1) => true   // 新增
            case RESPValue.Integer(0) => false  // 更新
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("HSET 返回意外类型")
        }
    }

    /// 批量设置哈希表字段值。返回新增的字段数量。
    public func hmset(key: String, pairs: Array<(String, Blob)>): Unit {
        let args = ArrayList<Blob>()
        args.add(Blob.fromUtf8("HMSET"))
        args.add(Blob.fromUtf8(key))
        for ((f, v) in pairs) {
            args.add(Blob.fromUtf8(f))
            args.add(v)
        }
        let resp = execute(collectArray(args.iterator()))
        expectOK(resp, "HMSET")
    }

    /// 仅当字段不存在时设置值。成功返回 true。
    public func hsetnx(key: String, field: String, value: Blob): Bool {
        let resp = execute([
            Blob.fromUtf8("HSETNX"), Blob.fromUtf8(key),
            Blob.fromUtf8(field), value,
        ])
        match (resp) {
            case RESPValue.Integer(1) => true
            case RESPValue.Integer(0) => false
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("HSETNX 返回意外类型")
        }
    }

    // -------- 读取操作 --------

    /// 获取哈希表中字段的值。字段不存在返回 None。
    public func hget(key: String, field: String): Option<Blob> {
        let resp = executeString(["HGET", key, field])
        expectBlob(resp, "HGET")
    }

    /// 获取哈希表中所有字段和值
    public func hgetAll(key: String): Array<(String, Blob)> {
        let resp = executeString(["HGETALL", key])
        match (resp) {
            case RESPValue.Map(pairs) =>
                let result = ArrayList<(String, Blob)>()
                for ((k, v) in pairs) {
                    match ((asString(k), asBlob(v))) {
                        case (Some(f), Some(val)) => result.add((f, val))
                        case _ => ()
                    }
                }
                collectArray(result.iterator())
            case RESPValue.Array(Some(items)) =>
                // RESP2 兼容：HGETALL 返回扁平数组 [k1, v1, k2, v2, ...]
                let result = ArrayList<(String, Blob)>()
                var i: Int64 = 0
                while (i + 1 < items.size) {
                    match ((asString(items[i]), asBlob(items[i + 1]))) {
                        case (Some(f), Some(val)) => result.add((f, val))
                        case _ => ()
                    }
                    i += 2
                }
                collectArray(result.iterator())
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("HGETALL 返回意外类型")
        }
    }

    /// 批量获取哈希表中多个字段的值
    public func hmget(key: String, fields: Array<String>): Array<Option<Blob>> {
        let args = ArrayList<String>()
        args.add("HMGET"); args.add(key)
        for (f in fields) { args.add(f) }
        let resp = executeString(collectArray(args.iterator()))
        match (resp) {
            case RESPValue.Array(Some(items)) =>
                let result = ArrayList<Option<Blob>>()
                for (item in items) {
                    match (item) {
                        case RESPValue.BulkString(v) => result.add(v)
                        case _ => result.add(None)
                    }
                }
                collectArray(result.iterator())
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("HMGET 返回意外类型")
        }
    }

    /// 获取哈希字段值并可选更新字段过期时间（Redis 8.0+）。
    public func hgetex(key: String, fields: Array<String>,
                       ex!: Option<Int64> = None,
                       px!: Option<Int64> = None,
                       exAt!: Option<Int64> = None,
                       pxAt!: Option<Int64> = None,
                       persist!: Bool = false): Array<Option<Blob>> {
        let args = ArrayList<String>()
        args.add("HGETEX"); args.add(key)
        addHashFieldExpiration(args, ex: ex, px: px, exAt: exAt, pxAt: pxAt, persist: persist, keepTtl: false)
        addHashFields(args, fields)
        parseOptionalBlobArray(executeString(collectArray(args.iterator())), "HGETEX")
    }

    /// 获取哈希字段值并删除这些字段（Redis 8.0+）。
    public func hgetdel(key: String, fields: Array<String>): Array<Option<Blob>> {
        let args = ArrayList<String>()
        args.add("HGETDEL"); args.add(key)
        addHashFields(args, fields)
        parseOptionalBlobArray(executeString(collectArray(args.iterator())), "HGETDEL")
    }

    /// 获取哈希表中所有字段名
    public func hkeys(key: String): Array<String> {
        let resp = executeString(["HKEYS", key])
        match (resp) {
            case RESPValue.Array(Some(items)) => extractStringArray(items)
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("HKEYS 返回意外类型")
        }
    }

    /// 获取哈希表中所有值
    public func hvals(key: String): Array<Blob> {
        let resp = executeString(["HVALS", key])
        match (resp) {
            case RESPValue.Array(Some(items)) => extractBlobArray(items)
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("HVALS 返回意外类型")
        }
    }

    /// 获取哈希表中字段数量
    public func hlen(key: String): Int64 {
        let resp = executeString(["HLEN", key])
        expectInt(resp, "HLEN")
    }

    /// 检查哈希表中是否存在指定字段
    public func hexists(key: String, field: String): Bool {
        let resp = executeString(["HEXISTS", key, field])
        expectBool(resp, "HEXISTS")
    }

    // -------- 删除操作 --------

    /// 删除哈希表中一个或多个字段。返回被删除的字段数量。
    public func hdel(key: String, fields: Array<String>): Int64 {
        let args = ArrayList<String>()
        args.add("HDEL"); args.add(key)
        for (f in fields) { args.add(f) }
        let resp = executeString(collectArray(args.iterator()))
        expectInt(resp, "HDEL")
    }

    /// 设置哈希字段值并可选设置字段过期时间（Redis 8.0+）。返回条件是否满足并写入成功。
    public func hsetex(key: String, pairs: Array<(String, Blob)>,
                       fnx!: Bool = false,
                       fxx!: Bool = false,
                       ex!: Option<Int64> = None,
                       px!: Option<Int64> = None,
                       exAt!: Option<Int64> = None,
                       pxAt!: Option<Int64> = None,
                       keepTtl!: Bool = false): Bool {
        if (pairs.size == 0) {
            throw ProtocolError("HSETEX 至少需要一个字段")
        }
        let args = ArrayList<Blob>()
        args.add(Blob.fromUtf8("HSETEX"))
        args.add(Blob.fromUtf8(key))
        if (fnx) { args.add(Blob.fromUtf8("FNX")) }
        if (fxx) { args.add(Blob.fromUtf8("FXX")) }
        addHashFieldExpirationBlob(args, ex: ex, px: px, exAt: exAt, pxAt: pxAt, persist: false, keepTtl: keepTtl)
        args.add(Blob.fromUtf8("FIELDS"))
        args.add(Blob.fromUtf8("${pairs.size}"))
        for ((field, value) in pairs) {
            args.add(Blob.fromUtf8(field))
            args.add(value)
        }
        expectBool(execute(collectArray(args.iterator())), "HSETEX")
    }

    // -------- 数值操作 --------

    /// 将哈希表中字段的值增加指定增量。返回新值。
    public func hincrBy(key: String, field: String, amount: Int64): Int64 {
        let resp = executeString(["HINCRBY", key, field, "${amount}"])
        expectInt(resp, "HINCRBY")
    }

    /// 将哈希表中字段的值增加浮点增量。返回新值。
    public func hincrByFloat(key: String, field: String, amount: Float64): Float64 {
        let resp = executeString(["HINCRBYFLOAT", key, field, "${amount}"])
        expectDouble(resp, "HINCRBYFLOAT")
    }

    // -------- 字段级过期 --------

    /// 设置哈希字段的秒级相对过期时间（Redis 7.4+）。
    public func hexpire(key: String, seconds: Int64, fields: Array<String>,
                        condition!: Option<String> = None): Array<Int64> {
        hashFieldExpire("HEXPIRE", key, seconds, fields, condition: condition)
    }

    /// 设置哈希字段的毫秒级相对过期时间（Redis 7.4+）。
    public func hpexpire(key: String, milliseconds: Int64, fields: Array<String>,
                         condition!: Option<String> = None): Array<Int64> {
        hashFieldExpire("HPEXPIRE", key, milliseconds, fields, condition: condition)
    }

    /// 设置哈希字段在秒级 Unix 时间戳过期（Redis 7.4+）。
    public func hexpireat(key: String, timestamp: Int64, fields: Array<String>,
                          condition!: Option<String> = None): Array<Int64> {
        hashFieldExpire("HEXPIREAT", key, timestamp, fields, condition: condition)
    }

    /// 设置哈希字段在毫秒级 Unix 时间戳过期（Redis 7.4+）。
    public func hpexpireat(key: String, timestamp: Int64, fields: Array<String>,
                           condition!: Option<String> = None): Array<Int64> {
        hashFieldExpire("HPEXPIREAT", key, timestamp, fields, condition: condition)
    }

    /// 获取哈希字段的秒级 TTL（Redis 7.4+）。
    public func httl(key: String, fields: Array<String>): Array<Int64> {
        hashFieldQuery("HTTL", key, fields)
    }

    /// 获取哈希字段的毫秒级 TTL（Redis 7.4+）。
    public func hpttl(key: String, fields: Array<String>): Array<Int64> {
        hashFieldQuery("HPTTL", key, fields)
    }

    /// 获取哈希字段的秒级过期时间戳（Redis 7.4+）。
    public func hexpiretime(key: String, fields: Array<String>): Array<Int64> {
        hashFieldQuery("HEXPIRETIME", key, fields)
    }

    /// 获取哈希字段的毫秒级过期时间戳（Redis 7.4+）。
    public func hpexpiretime(key: String, fields: Array<String>): Array<Int64> {
        hashFieldQuery("HPEXPIRETIME", key, fields)
    }

    /// 移除哈希字段的过期时间（Redis 7.4+）。
    public func hpersist(key: String, fields: Array<String>): Array<Int64> {
        hashFieldQuery("HPERSIST", key, fields)
    }

    // -------- 新增 --------

    /// 随机获取一个哈希字段。
    public func hrandfieldOne(key: String): Option<String> {
        let resp = executeString(["HRANDFIELD", key])
        match (resp) {
            case RESPValue.BulkString(Some(blob)) => Some(blob.toUtf8())
            case RESPValue.BulkString(None) | RESPValue.Null => None
            case RESPValue.Error(e) => throw createCommandError(e)
            case RESPValue.BulkError(e) => throw createCommandError(e.toUtf8())
            case _ => throw ProtocolError("HRANDFIELD 返回意外类型")
        }
    }

    /// 随机获取哈希字段列表（不返回值）。
    public func hrandfieldValues(key: String, count: Int64): Array<String> {
        let resp = executeString(["HRANDFIELD", key, "${count}"])
        match (resp) {
            case RESPValue.Array(Some(items)) => extractStringArray(items)
            case RESPValue.Error(e) => throw createCommandError(e)
            case RESPValue.BulkError(e) => throw createCommandError(e.toUtf8())
            case _ => throw ProtocolError("HRANDFIELD 返回意外类型")
        }
    }

    /// 随机获取哈希表中的字段及值（需要 count 参数）
    public func hrandfield(key: String, count: Int64, withValues!: Bool = true): Array<(String, Blob)> {
        let args = ArrayList<String>(); args.add("HRANDFIELD"); args.add(key)
        args.add("${count}")
        if (withValues) { args.add("WITHVALUES") }
        let resp = executeString(collectArray(args.iterator()))
        match (resp) {
            case RESPValue.Array(Some(items)) =>
                parseFieldValuePairs(items)
            case RESPValue.Map(pairs) =>
                // RESP3: Map<field, value>
                let result = ArrayList<(String, Blob)>()
                for ((k, v) in pairs) {
                    match ((asString(k), asBlob(v))) {
                        case (Some(f), Some(val)) => result.add((f, val))
                        case _ => ()
                    }
                }
                collectArray(result.iterator())
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("HRANDFIELD 返回意外类型")
        }
    }

    /// 从 RESP2 扁平数组中解析字段值对 [f1, v1, f2, v2, ...]
    private func parseFieldValuePairs(items: Array<RESPValue>): Array<(String, Blob)> {
        let result = ArrayList<(String, Blob)>()
        if (items.size > 0) {
            match (items[0]) {
                case RESPValue.Array(_) =>
                    for (item in items) {
                        match (item) {
                            case RESPValue.Array(Some(pair)) =>
                                if (pair.size >= 2) {
                                    match ((asString(pair[0]), asBlob(pair[1]))) {
                                        case (Some(f), Some(v)) => result.add((f, v))
                                        case _ => ()
                                    }
                                }
                            case _ => ()
                        }
                    }
                case _ =>
                    var i: Int64 = 0
                    while (i + 1 < items.size) {
                        match ((asString(items[i]), asBlob(items[i + 1]))) {
                            case (Some(f), Some(v)) => result.add((f, v))
                            case _ => ()
                        }
                        i += 2
                    }
            }
        }
        collectArray(result.iterator())
    }

    /// 获取字段值的字节长度
    public func hstrlen(key: String, field: String): Int64 {
        let resp = executeString(["HSTRLEN", key, field])
        expectInt(resp, "HSTRLEN")
    }

    private func hashFieldExpire(command: String, key: String, timeout: Int64, fields: Array<String>,
                                 condition!: Option<String> = None): Array<Int64> {
        let args = ArrayList<String>()
        args.add(command); args.add(key); args.add("${timeout}")
        match (condition) {
            case Some(c) => args.add(c)
            case None => ()
        }
        addHashFields(args, fields)
        parseIntArray(executeString(collectArray(args.iterator())), command)
    }

    private func hashFieldQuery(command: String, key: String, fields: Array<String>): Array<Int64> {
        let args = ArrayList<String>()
        args.add(command); args.add(key)
        addHashFields(args, fields)
        parseIntArray(executeString(collectArray(args.iterator())), command)
    }

    private func addHashFields(args: ArrayList<String>, fields: Array<String>): Unit {
        if (fields.size == 0) {
            throw ProtocolError("哈希字段命令至少需要一个字段")
        }
        args.add("FIELDS")
        args.add("${fields.size}")
        for (f in fields) { args.add(f) }
    }

    private func addHashFieldExpiration(args: ArrayList<String>,
                                        ex!: Option<Int64> = None,
                                        px!: Option<Int64> = None,
                                        exAt!: Option<Int64> = None,
                                        pxAt!: Option<Int64> = None,
                                        persist!: Bool = false,
                                        keepTtl!: Bool = false): Unit {
        match (ex) { case Some(t) => args.add("EX"); args.add("${t}") case None => () }
        match (px) { case Some(t) => args.add("PX"); args.add("${t}") case None => () }
        match (exAt) { case Some(t) => args.add("EXAT"); args.add("${t}") case None => () }
        match (pxAt) { case Some(t) => args.add("PXAT"); args.add("${t}") case None => () }
        if (persist) { args.add("PERSIST") }
        if (keepTtl) { args.add("KEEPTTL") }
    }

    private func addHashFieldExpirationBlob(args: ArrayList<Blob>,
                                            ex!: Option<Int64> = None,
                                            px!: Option<Int64> = None,
                                            exAt!: Option<Int64> = None,
                                            pxAt!: Option<Int64> = None,
                                            persist!: Bool = false,
                                            keepTtl!: Bool = false): Unit {
        match (ex) { case Some(t) => args.add(Blob.fromUtf8("EX")); args.add(Blob.fromUtf8("${t}")) case None => () }
        match (px) { case Some(t) => args.add(Blob.fromUtf8("PX")); args.add(Blob.fromUtf8("${t}")) case None => () }
        match (exAt) { case Some(t) => args.add(Blob.fromUtf8("EXAT")); args.add(Blob.fromUtf8("${t}")) case None => () }
        match (pxAt) { case Some(t) => args.add(Blob.fromUtf8("PXAT")); args.add(Blob.fromUtf8("${t}")) case None => () }
        if (persist) { args.add(Blob.fromUtf8("PERSIST")) }
        if (keepTtl) { args.add(Blob.fromUtf8("KEEPTTL")) }
    }

    private func parseIntArray(resp: RESPValue, cmd: String): Array<Int64> {
        match (resp) {
            case RESPValue.Array(Some(items)) =>
                let result = ArrayList<Int64>()
                for (item in items) {
                    match (item) {
                        case RESPValue.Integer(n) => result.add(n)
                        case _ => throw ProtocolError("${cmd}: 数组元素期望 Integer，但收到 ${respValueToString(item)}")
                    }
                }
                collectArray(result.iterator())
            case RESPValue.Array(None) => []
            case RESPValue.Error(e) => throw createCommandError(e)
            case RESPValue.BulkError(e) => throw createCommandError(e.toUtf8())
            case _ => throw ProtocolError("${cmd}: 期望 Integer 数组，但收到 ${respValueToString(resp)}")
        }
    }

    private func parseOptionalBlobArray(resp: RESPValue, cmd: String): Array<Option<Blob>> {
        match (resp) {
            case RESPValue.Array(Some(items)) =>
                let result = ArrayList<Option<Blob>>()
                for (item in items) {
                    match (item) {
                        case RESPValue.BulkString(v) => result.add(v)
                        case RESPValue.Null => result.add(None)
                        case _ => throw ProtocolError("${cmd}: 数组元素期望 BulkString/Null，但收到 ${respValueToString(item)}")
                    }
                }
                collectArray(result.iterator())
            case RESPValue.Array(None) => []
            case RESPValue.Error(e) => throw createCommandError(e)
            case RESPValue.BulkError(e) => throw createCommandError(e.toUtf8())
            case _ => throw ProtocolError("${cmd}: 期望 BulkString 数组，但收到 ${respValueToString(resp)}")
        }
    }
}
