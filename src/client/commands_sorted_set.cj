package redis.client
import std.collection.*
import std.convert.*

// ====================================================================
// 有序集合命令 (Sorted Set Commands)
// ====================================================================

extend RedisClient {
    // -------- 基本操作 --------

    public func zadd(key: String, scores: Array<(Float64, Blob)>): Int64 {
        let args = ArrayList<Blob>()
        args.add(Blob.fromUtf8("ZADD")); args.add(Blob.fromUtf8(key))
        for ((score, member) in scores) {
            args.add(Blob.fromUtf8("${score}")); args.add(member)
        }
        let resp = execute(collectArray(args.iterator()))
        expectInt(resp, "ZADD")
    }

    public func zrem(key: String, members: Array<Blob>): Int64 {
        let args = ArrayList<Blob>()
        args.add(Blob.fromUtf8("ZREM")); args.add(Blob.fromUtf8(key))
        for (m in members) { args.add(m) }
        let resp = execute(collectArray(args.iterator()))
        expectInt(resp, "ZREM")
    }

    public func zcard(key: String): Int64 {
        let resp = executeString(["ZCARD", key])
        expectInt(resp, "ZCARD")
    }

    public func zscore(key: String, member: Blob): Option<Float64> {
        let resp = execute([Blob.fromUtf8("ZSCORE"), Blob.fromUtf8(key), member])
        match (resp) {
            case RESPValue.BulkString(Some(blob)) => Some(Float64.parse(blob.toUtf8()))
            case RESPValue.BulkString(None) => None
            case RESPValue.Double(f) => Some(f)
            case RESPValue.Null => None
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("ZSCORE 返回意外类型")
        }
    }

    /// 批量获取多个成员的分值
    public func zmscore(key: String, members: Array<Blob>): Array<Option<Float64>> {
        let args = ArrayList<Blob>(); args.add(Blob.fromUtf8("ZMSCORE")); args.add(Blob.fromUtf8(key))
        for (m in members) { args.add(m) }
        let resp = execute(collectArray(args.iterator()))
        match (resp) {
            case RESPValue.Array(Some(items)) =>
                let result = ArrayList<Option<Float64>>()
                for (item in items) {
                    match (item) {
                        case RESPValue.BulkString(Some(blob)) =>
                            result.add(Some(Float64.parse(blob.toUtf8())))
                        case RESPValue.BulkString(None) => result.add(None)
                        case _ => result.add(None)
                    }
                }
                collectArray(result.iterator())
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("ZMSCORE 返回意外类型")
        }
    }

    public func zrank(key: String, member: Blob): Option<Int64> {
        let resp = execute([Blob.fromUtf8("ZRANK"), Blob.fromUtf8(key), member])
        match (resp) {
            case RESPValue.Integer(n) => if (n >= 0) { Some(n) } else { None }
            case RESPValue.BulkString(None) => None
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("ZRANK 返回意外类型")
        }
    }

    public func zrevrank(key: String, member: Blob): Option<Int64> {
        let resp = execute([Blob.fromUtf8("ZREVRANK"), Blob.fromUtf8(key), member])
        match (resp) {
            case RESPValue.Integer(n) => if (n >= 0) { Some(n) } else { None }
            case RESPValue.BulkString(None) => None
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("ZREVRANK 返回意外类型")
        }
    }

    public func zincrby(key: String, increment: Float64, member: Blob): Float64 {
        let resp = execute([Blob.fromUtf8("ZINCRBY"), Blob.fromUtf8(key), Blob.fromUtf8("${increment}"), member])
        match (resp) {
            case RESPValue.BulkString(Some(blob)) => Float64.parse(blob.toUtf8())
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("ZINCRBY 返回意外类型")
        }
    }

    // -------- 范围读取 --------

    public func zrange(key: String, start: Int64, stop: Int64): Array<Blob> {
        let resp = executeString(["ZRANGE", key, "${start}", "${stop}"])
        match (resp) {
            case RESPValue.Array(Some(items)) => extractBlobArray(items)
            case RESPValue.Set(items) => extractBlobArray(items)
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("ZRANGE 返回意外类型")
        }
    }

    public func zrangeWithScores(key: String, start: Int64, stop: Int64): Array<(Blob, Float64)> {
        let resp = executeString(["ZRANGE", key, "${start}", "${stop}", "WITHSCORES"])
        match (resp) {
            case RESPValue.Array(Some(items)) => parseScorePairsFromFlatArray(items)
            case RESPValue.Map(pairs) =>
                let result = ArrayList<(Blob, Float64)>()
                for ((k, v) in pairs) {
                    match ((asBlob(k), asString(v))) {
                        case (Some(m), Some(s)) =>
                            try { result.add((m, Float64.parse(s))) } catch (_) { () }
                        case _ => ()
                    }
                }
                collectArray(result.iterator())
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("ZRANGE WITHSCORES 返回意外类型")
        }
    }

    public func zrevrange(key: String, start: Int64, stop: Int64): Array<Blob> {
        let resp = executeString(["ZREVRANGE", key, "${start}", "${stop}"])
        match (resp) {
            case RESPValue.Array(Some(items)) => extractBlobArray(items)
            case RESPValue.Set(items) => extractBlobArray(items)
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("ZREVRANGE 返回意外类型")
        }
    }

    public func zrangeByScore(key: String, min: Float64, max: Float64): Array<Blob> {
        let resp = executeString(["ZRANGEBYSCORE", key, "${min}", "${max}"])
        match (resp) {
            case RESPValue.Array(Some(items)) => extractBlobArray(items)
            case RESPValue.Set(items) => extractBlobArray(items)
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("ZRANGEBYSCORE 返回意外类型")
        }
    }

    /// 按字典序范围获取成员
    public func zrangeByLex(key: String, min: String, max: String,
                            limit!: Option<(Int64, Int64)> = None): Array<String> {
        let args = ArrayList<String>(); args.add("ZRANGEBYLEX"); args.add(key); args.add(min); args.add(max)
        match (limit) { case Some((o, c)) => args.add("LIMIT"); args.add("${o}"); args.add("${c}") case None => () }
        let resp = executeString(collectArray(args.iterator()))
        match (resp) {
            case RESPValue.Array(Some(items)) => extractStringArray(items)
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("ZRANGEBYLEX 返回意外类型")
        }
    }

    public func zrevrangeByLex(key: String, max: String, min: String,
                               limit!: Option<(Int64, Int64)> = None): Array<String> {
        let args = ArrayList<String>(); args.add("ZREVRANGEBYLEX"); args.add(key); args.add(max); args.add(min)
        match (limit) { case Some((o, c)) => args.add("LIMIT"); args.add("${o}"); args.add("${c}") case None => () }
        let resp = executeString(collectArray(args.iterator()))
        match (resp) {
            case RESPValue.Array(Some(items)) => extractStringArray(items)
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("ZREVRANGEBYLEX 返回意外类型")
        }
    }

    // -------- 计数 --------

    public func zcount(key: String, min: Float64, max: Float64): Int64 {
        let resp = executeString(["ZCOUNT", key, "${min}", "${max}"])
        expectInt(resp, "ZCOUNT")
    }

    /// 统计字典序范围内的成员数
    public func zlexcount(key: String, min: String, max: String): Int64 {
        let resp = executeString(["ZLEXCOUNT", key, min, max])
        expectInt(resp, "ZLEXCOUNT")
    }

    // -------- 删除 --------

    public func zremrangeByRank(key: String, start: Int64, stop: Int64): Int64 {
        let resp = executeString(["ZREMRANGEBYRANK", key, "${start}", "${stop}"])
        expectInt(resp, "ZREMRANGEBYRANK")
    }

    public func zremrangeByScore(key: String, min: Float64, max: Float64): Int64 {
        let resp = executeString(["ZREMRANGEBYSCORE", key, "${min}", "${max}"])
        expectInt(resp, "ZREMRANGEBYSCORE")
    }

    /// 按字典序范围删除成员
    public func zremrangeByLex(key: String, min: String, max: String): Int64 {
        let resp = executeString(["ZREMRANGEBYLEX", key, min, max])
        expectInt(resp, "ZREMRANGEBYLEX")
    }

    // -------- 弹出 --------

    public func zpopmin(key: String, count!: Int64 = 1): Array<(Blob, Float64)> {
        let resp = executeString(["ZPOPMIN", key, "${count}"])
        parseScorePairs(resp)
    }

    public func zpopmax(key: String, count!: Int64 = 1): Array<(Blob, Float64)> {
        let resp = executeString(["ZPOPMAX", key, "${count}"])
        parseScorePairs(resp)
    }

    /// 阻塞式弹出分值最小的成员
    public func bzpopmin(keys: Array<String>, timeout!: Int64 = 0): Option<(String, Blob, Float64)> {
        let args = ArrayList<String>(); args.add("BZPOPMIN")
        for (k in keys) { args.add(k) }
        args.add("${timeout}")
        parseBlockingPopResult(executeString(collectArray(args.iterator())))
    }

    /// 阻塞式弹出分值最大的成员
    public func bzpopmax(keys: Array<String>, timeout!: Int64 = 0): Option<(String, Blob, Float64)> {
        let args = ArrayList<String>(); args.add("BZPOPMAX")
        for (k in keys) { args.add(k) }
        args.add("${timeout}")
        parseBlockingPopResult(executeString(collectArray(args.iterator())))
    }

    // -------- 集合运算 --------

    /// 计算多个有序集合的差集
    public func zdiff(keys: Array<String>, withScores!: Bool = false): Array<RESPValue> {
        let args = ArrayList<String>(); args.add("ZDIFF"); args.add("${keys.size}")
        for (k in keys) { args.add(k) }
        if (withScores) { args.add("WITHSCORES") }
        let resp = executeString(collectArray(args.iterator()))
        match (resp) {
            case RESPValue.Array(Some(items)) => items
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("ZDIFF 返回意外类型")
        }
    }

    /// 将多个有序集合的差集存储到 destination
    public func zdiffstore(destination: String, keys: Array<String>): Int64 {
        let args = ArrayList<String>(); args.add("ZDIFFSTORE"); args.add(destination); args.add("${keys.size}")
        for (k in keys) { args.add(k) }
        let resp = executeString(collectArray(args.iterator()))
        expectInt(resp, "ZDIFFSTORE")
    }

    /// 计算多个有序集合的交集
    public func zinter(keys: Array<String>, withScores!: Bool = false,
                       weights!: Array<Int64> = []): Array<RESPValue> {
        let args = ArrayList<String>(); args.add("ZINTER"); args.add("${keys.size}")
        for (k in keys) { args.add(k) }
        if (weights.size > 0) {
            args.add("WEIGHTS")
            for (w in weights) { args.add("${w}") }
        }
        if (withScores) { args.add("WITHSCORES") }
        let resp = executeString(collectArray(args.iterator()))
        match (resp) {
            case RESPValue.Array(Some(items)) => items
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("ZINTER 返回意外类型")
        }
    }

    /// 将多个有序集合的交集存储到 destination
    public func zinterstore(destination: String, keys: Array<String>,
                            weights!: Array<Int64> = [],
                            aggregate!: String = "SUM"): Int64 {
        let args = ArrayList<String>(); args.add("ZINTERSTORE"); args.add(destination); args.add("${keys.size}")
        for (k in keys) { args.add(k) }
        if (weights.size > 0) {
            args.add("WEIGHTS")
            for (w in weights) { args.add("${w}") }
        }
        args.add("AGGREGATE"); args.add(aggregate)
        let resp = executeString(collectArray(args.iterator()))
        expectInt(resp, "ZINTERSTORE")
    }

    /// 计算多个有序集合的并集
    public func zunion(keys: Array<String>, withScores!: Bool = false,
                       weights!: Array<Int64> = []): Array<RESPValue> {
        let args = ArrayList<String>(); args.add("ZUNION"); args.add("${keys.size}")
        for (k in keys) { args.add(k) }
        if (weights.size > 0) {
            args.add("WEIGHTS")
            for (w in weights) { args.add("${w}") }
        }
        if (withScores) { args.add("WITHSCORES") }
        let resp = executeString(collectArray(args.iterator()))
        match (resp) {
            case RESPValue.Array(Some(items)) => items
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("ZUNION 返回意外类型")
        }
    }

    /// 将多个有序集合的并集存储到 destination
    public func zunionstore(destination: String, keys: Array<String>,
                            weights!: Array<Int64> = [],
                            aggregate!: String = "SUM"): Int64 {
        let args = ArrayList<String>(); args.add("ZUNIONSTORE"); args.add(destination); args.add("${keys.size}")
        for (k in keys) { args.add(k) }
        if (weights.size > 0) {
            args.add("WEIGHTS")
            for (w in weights) { args.add("${w}") }
        }
        args.add("AGGREGATE"); args.add(aggregate)
        let resp = executeString(collectArray(args.iterator()))
        expectInt(resp, "ZUNIONSTORE")
    }

    /// 随机获取成员
    public func zrandmember(key: String, count!: Option<Int64> = None): Array<Blob> {
        let args = ArrayList<String>(); args.add("ZRANDMEMBER"); args.add(key)
        match (count) { case Some(n) => args.add("${n}") case None => () }
        match (executeString(collectArray(args.iterator()))) {
            case RESPValue.Array(Some(items)) => extractBlobArray(items)
            case RESPValue.Set(items) => extractBlobArray(items)
            case RESPValue.BulkString(Some(blob)) => [blob]
            case RESPValue.BulkString(None) => Array<Blob>()
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("ZRANDMEMBER 返回意外类型")
        }
    }

    /// 计算交集基数
    public func zintercard(keys: Array<String>, limit!: Option<Int64> = None): Int64 {
        let args = ArrayList<String>(); args.add("ZINTERCARD"); args.add("${keys.size}")
        for (k in keys) { args.add(k) }
        match (limit) { case Some(l) => args.add("LIMIT"); args.add("${l}") case None => () }
        let resp = executeString(collectArray(args.iterator()))
        expectInt(resp, "ZINTERCARD")
    }

    // -------- 辅助 --------

    private func parseScorePairs(resp: RESPValue): Array<(Blob, Float64)> {
        let items = match (resp) {
            case RESPValue.Array(Some(arr)) => arr
            case RESPValue.Set(arr) => arr
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("ZSET 返回意外类型")
        }
        parseScorePairsFromFlatArray(items)
    }

    private func parseScorePairsFromFlatArray(items: Array<RESPValue>): Array<(Blob, Float64)> {
        let result = ArrayList<(Blob, Float64)>()
        var i: Int64 = 0
        while (i + 1 < items.size) {
            match ((asBlob(items[i]), asString(items[i + 1]))) {
                case (Some(m), Some(s)) =>
                    try { result.add((m, Float64.parse(s))) } catch (_) { () }
                case _ => ()
            }
            i += 2
        }
        collectArray(result.iterator())
    }

    private func parseBlockingPopResult(resp: RESPValue): Option<(String, Blob, Float64)> {
        match (resp) {
            case RESPValue.Array(Some(items)) =>
                if (items.size >= 3) {
                    match ((asString(items[0]), asBlob(items[1]), asString(items[2]))) {
                        case (Some(k), Some(m), Some(s)) =>
                            try { Some((k, m, Float64.parse(s))) } catch (_) { None }
                        case _ => None
                    }
                } else { None }
            case RESPValue.Array(None) => None
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("BZPOP 返回意外类型")
        }
    }
}
