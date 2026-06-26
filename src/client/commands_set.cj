package redis.client
import std.collection.*

// ====================================================================
// 集合命令 (Set Commands)
// ====================================================================

extend RedisClient {
    /// 向集合添加一个或多个成员。返回新增成员数。
    public func sadd(key: String, members: Array<Blob>): Int64 {
        let args = ArrayList<Blob>()
        args.add(Blob.fromUtf8("SADD"))
        args.add(Blob.fromUtf8(key))
        for (m in members) { args.add(m) }
        let resp = execute(collectArray(args.iterator()))
        expectInt(resp, "SADD")
    }

    /// 从集合中移除一个或多个成员。返回移除的成员数。
    public func srem(key: String, members: Array<Blob>): Int64 {
        let args = ArrayList<Blob>()
        args.add(Blob.fromUtf8("SREM"))
        args.add(Blob.fromUtf8(key))
        for (m in members) { args.add(m) }
        let resp = execute(collectArray(args.iterator()))
        expectInt(resp, "SREM")
    }

    /// 获取集合中的所有成员
    public func smembers(key: String): Array<Blob> {
        let resp = executeString(["SMEMBERS", key])
        match (resp) {
            case RESPValue.Set(items) => extractBlobArray(items)     // RESP3
            case RESPValue.Array(Some(items)) => extractBlobArray(items) // RESP2
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("SMEMBERS 返回意外类型")
        }
    }

    /// 检查成员是否存在于集合中
    public func sismember(key: String, member: Blob): Bool {
        let resp = execute([Blob.fromUtf8("SISMEMBER"), Blob.fromUtf8(key), member])
        expectBool(resp, "SISMEMBER")
    }

    /// 获取集合的成员数
    public func scard(key: String): Int64 {
        let resp = executeString(["SCARD", key])
        expectInt(resp, "SCARD")
    }

    /// 移除并返回集合中的一个随机成员
    public func spop(key: String): Option<Blob> {
        let resp = executeString(["SPOP", key])
        expectBlob(resp, "SPOP")
    }

    /// 移除并返回集合中的 count 个随机成员
    public func spopCount(key: String, count: Int64): Array<Blob> {
        let resp = executeString(["SPOP", key, "${count}"])
        match (resp) {
            case RESPValue.Array(Some(items)) => extractBlobArray(items)
            case RESPValue.Set(items) => extractBlobArray(items)
            case RESPValue.Error(e) => throw createCommandError(e)
            case RESPValue.BulkError(e) => throw createCommandError(e.toUtf8())
            case _ => throw ProtocolError("SPOP count 返回意外类型")
        }
    }

    /// 从集合中获取 count 个随机成员（不移除）
    public func srandmember(key: String, count!: Int64 = 1): Array<Blob> {
        let resp = executeString(["SRANDMEMBER", key, "${count}"])
        match (resp) {
            case RESPValue.Array(Some(items)) => extractBlobArray(items)
            case RESPValue.Set(items) => extractBlobArray(items)
            case RESPValue.BulkString(Some(blob)) => [blob]  // count=1 时可能直接返回字符串
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("SRANDMEMBER 返回意外类型")
        }
    }

    /// 从集合中获取一个随机成员（不移除）。
    public func srandmemberOne(key: String): Option<Blob> {
        expectBlob(executeString(["SRANDMEMBER", key]), "SRANDMEMBER")
    }

    // -------- 集合运算 --------

    /// 返回多个集合的差集
    public func sdiff(keys: Array<String>): Array<Blob> {
        let args = ArrayList<String>(); args.add("SDIFF")
        for (k in keys) { args.add(k) }
        let resp = executeString(collectArray(args.iterator()))
        match (resp) {
            case RESPValue.Set(it) => extractBlobArray(it)
            case RESPValue.Array(Some(it)) => extractBlobArray(it)
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("SDIFF 返回意外类型")
        }
    }

    /// 返回多个集合的交集
    public func sinter(keys: Array<String>): Array<Blob> {
        let args = ArrayList<String>(); args.add("SINTER")
        for (k in keys) { args.add(k) }
        let resp = executeString(collectArray(args.iterator()))
        match (resp) {
            case RESPValue.Set(it) => extractBlobArray(it)
            case RESPValue.Array(Some(it)) => extractBlobArray(it)
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("SINTER 返回意外类型")
        }
    }

    /// 返回多个集合的并集
    public func sunion(keys: Array<String>): Array<Blob> {
        let args = ArrayList<String>(); args.add("SUNION")
        for (k in keys) { args.add(k) }
        let resp = executeString(collectArray(args.iterator()))
        match (resp) {
            case RESPValue.Set(it) => extractBlobArray(it)
            case RESPValue.Array(Some(it)) => extractBlobArray(it)
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("SUNION 返回意外类型")
        }
    }

    /// 将多个集合的差集存储到 destination。返回结果集大小。
    public func sdiffstore(destination: String, keys: Array<String>): Int64 {
        let args = ArrayList<String>(); args.add("SDIFFSTORE"); args.add(destination)
        for (k in keys) { args.add(k) }
        let resp = executeString(collectArray(args.iterator()))
        expectInt(resp, "SDIFFSTORE")
    }

    /// 将多个集合的交集存储到 destination。返回结果集大小。
    public func sinterstore(destination: String, keys: Array<String>): Int64 {
        let args = ArrayList<String>(); args.add("SINTERSTORE"); args.add(destination)
        for (k in keys) { args.add(k) }
        let resp = executeString(collectArray(args.iterator()))
        expectInt(resp, "SINTERSTORE")
    }

    /// 将多个集合的并集存储到 destination。返回结果集大小。
    public func sunionstore(destination: String, keys: Array<String>): Int64 {
        let args = ArrayList<String>(); args.add("SUNIONSTORE"); args.add(destination)
        for (k in keys) { args.add(k) }
        let resp = executeString(collectArray(args.iterator()))
        expectInt(resp, "SUNIONSTORE")
    }

    // -------- 新增 --------

    /// 将成员从一个集合原子移动到另一个集合
    public func smove(source: String, destination: String, member: Blob): Bool {
        let resp = execute([Blob.fromUtf8("SMOVE"), Blob.fromUtf8(source), Blob.fromUtf8(destination), member])
        expectBool(resp, "SMOVE")
    }

    /// 批量检查成员是否存在
    public func smismember(key: String, members: Array<Blob>): Array<Bool> {
        let args = ArrayList<Blob>(); args.add(Blob.fromUtf8("SMISMEMBER")); args.add(Blob.fromUtf8(key))
        for (m in members) { args.add(m) }
        let resp = execute(collectArray(args.iterator()))
        match (resp) {
            case RESPValue.Array(Some(items)) =>
                let result = ArrayList<Bool>()
                for (item in items) {
                    match (item) {
                        case RESPValue.Integer(1) => result.add(true)
                        case RESPValue.Integer(0) => result.add(false)
                        case RESPValue.Boolean(b) => result.add(b)
                        case _ => result.add(false)
                    }
                }
                collectArray(result.iterator())
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("SMISMEMBER 返回意外类型")
        }
    }

    /// 计算多个集合的交集基数
    public func sintercard(keys: Array<String>, limit!: Option<Int64> = None): Int64 {
        let args = ArrayList<String>(); args.add("SINTERCARD"); args.add("${keys.size}")
        for (k in keys) { args.add(k) }
        match (limit) { case Some(l) => args.add("LIMIT"); args.add("${l}") case None => () }
        let resp = executeString(collectArray(args.iterator()))
        expectInt(resp, "SINTERCARD")
    }
}
