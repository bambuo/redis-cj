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

    // -------- 新增 --------

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
        var i: Int64 = 0
        while (i + 1 < items.size) {
            match ((asString(items[i]), asBlob(items[i + 1]))) {
                case (Some(f), Some(v)) => result.add((f, v))
                case _ => ()
            }
            i += 2
        }
        collectArray(result.iterator())
    }

    /// 获取字段值的字节长度
    public func hstrlen(key: String, field: String): Int64 {
        let resp = executeString(["HSTRLEN", key, field])
        expectInt(resp, "HSTRLEN")
    }
}
