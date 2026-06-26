package redis.client
import std.collection.*

// ====================================================================
// 列表命令 (List Commands)
// ====================================================================

extend RedisClient {
    // -------- 写入操作 --------

    /// 向列表头部插入一个或多个值。返回列表长度。
    public func lpush(key: String, values: Array<Blob>): Int64 {
        let args = ArrayList<Blob>()
        args.add(Blob.fromUtf8("LPUSH"))
        args.add(Blob.fromUtf8(key))
        for (v in values) { args.add(v) }
        let resp = execute(collectArray(args.iterator()))
        expectInt(resp, "LPUSH")
    }

    /// 向列表尾部插入一个或多个值。返回列表长度。
    public func rpush(key: String, values: Array<Blob>): Int64 {
        let args = ArrayList<Blob>()
        args.add(Blob.fromUtf8("RPUSH"))
        args.add(Blob.fromUtf8(key))
        for (v in values) { args.add(v) }
        let resp = execute(collectArray(args.iterator()))
        expectInt(resp, "RPUSH")
    }

    /// 仅当键已存在时向头部插入。返回列表长度。
    public func lpushx(key: String, value: Blob): Int64 {
        let resp = execute([Blob.fromUtf8("LPUSHX"), Blob.fromUtf8(key), value])
        expectInt(resp, "LPUSHX")
    }

    /// 仅当键已存在时向尾部插入。返回列表长度。
    public func rpushx(key: String, value: Blob): Int64 {
        let resp = execute([Blob.fromUtf8("RPUSHX"), Blob.fromUtf8(key), value])
        expectInt(resp, "RPUSHX")
    }

    // -------- 读取操作 --------

    /// 获取列表长度
    public func llen(key: String): Int64 {
        let resp = executeString(["LLEN", key])
        expectInt(resp, "LLEN")
    }

    /// 获取列表中指定范围的值（闭区间 [start, stop]）
    public func lrange(key: String, start: Int64, stop: Int64): Array<Blob> {
        let resp = executeString(["LRANGE", key, "${start}", "${stop}"])
        match (resp) {
            case RESPValue.Array(Some(items)) => extractBlobArray(items)
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("LRANGE 返回意外类型")
        }
    }

    /// 获取列表中指定索引的值
    public func lindex(key: String, index: Int64): Option<Blob> {
        let resp = executeString(["LINDEX", key, "${index}"])
        expectBlob(resp, "LINDEX")
    }

    // -------- 移除操作 --------

    /// 移除并返回列表头部元素
    public func lpop(key: String): Option<Blob> {
        let resp = executeString(["LPOP", key])
        expectBlob(resp, "LPOP")
    }

    /// 移除并返回列表头部 count 个元素。
    public func lpopCount(key: String, count: Int64): Array<Blob> {
        parseListPopCount(executeString(["LPOP", key, "${count}"]), "LPOP count")
    }

    /// 移除并返回列表尾部元素
    public func rpop(key: String): Option<Blob> {
        let resp = executeString(["RPOP", key])
        expectBlob(resp, "RPOP")
    }

    /// 移除并返回列表尾部 count 个元素。
    public func rpopCount(key: String, count: Int64): Array<Blob> {
        parseListPopCount(executeString(["RPOP", key, "${count}"]), "RPOP count")
    }

    /// 从列表中移除 count 个等于 value 的元素
    public func lrem(key: String, count: Int64, value: Blob): Int64 {
        let resp = execute([
            Blob.fromUtf8("LREM"), Blob.fromUtf8(key),
            Blob.fromUtf8("${count}"), value,
        ])
        expectInt(resp, "LREM")
    }

    /// 修剪列表，只保留指定范围内的元素
    public func ltrim(key: String, start: Int64, stop: Int64): Unit {
        let resp = executeString(["LTRIM", key, "${start}", "${stop}"])
        expectOK(resp, "LTRIM")
    }

    // -------- 阻塞操作 --------

    /// 阻塞式弹出列表头部元素。timeout=0 表示无限等待。
    public func blpop(keys: Array<String>, timeout!: Int64 = 0): Option<(String, Blob)> {
        let args = ArrayList<String>()
        args.add("BLPOP")
        for (k in keys) { args.add(k) }
        args.add("${timeout}")
        let resp = executeString(collectArray(args.iterator()))
        match (resp) {
            case RESPValue.Array(Some(items)) =>
                if (items.size >= 2) {
                    match ((asString(items[0]), asBlob(items[1]))) {
                        case (Some(k), Some(v)) => Some((k, v))
                        case _ => None
                    }
                } else { None }
            case RESPValue.Array(None) => None
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("BLPOP 返回意外类型")
        }
    }

    /// 阻塞式弹出列表尾部元素。timeout=0 表示无限等待。
    public func brpop(keys: Array<String>, timeout!: Int64 = 0): Option<(String, Blob)> {
        let args = ArrayList<String>()
        args.add("BRPOP")
        for (k in keys) { args.add(k) }
        args.add("${timeout}")
        let resp = executeString(collectArray(args.iterator()))
        match (resp) {
            case RESPValue.Array(Some(items)) =>
                if (items.size >= 2) {
                    match ((asString(items[0]), asBlob(items[1]))) {
                        case (Some(k), Some(v)) => Some((k, v))
                        case _ => None
                    }
                } else { None }
            case RESPValue.Array(None) => None
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("BRPOP 返回意外类型")
        }
    }

    // -------- 新增命令 --------

    public func linsert(key: String, before: Bool, pivot: Blob, value: Blob): Int64 {
        let resp = execute([
            Blob.fromUtf8("LINSERT"), Blob.fromUtf8(key),
            Blob.fromUtf8(if (before) { "BEFORE" } else { "AFTER" }),
            pivot, value,
        ])
        expectInt(resp, "LINSERT")
    }

    public func lset(key: String, index: Int64, value: Blob): Unit {
        let resp = execute([
            Blob.fromUtf8("LSET"), Blob.fromUtf8(key),
            Blob.fromUtf8("${index}"), value,
        ])
        expectOK(resp, "LSET")
    }

    public func lpos(key: String, value: Blob, rank!: Option<Int64> = None,
                     count!: Option<Int64> = None, maxLen!: Option<Int64> = None): RESPValue {
        let args = ArrayList<Blob>()
        args.add(Blob.fromUtf8("LPOS")); args.add(Blob.fromUtf8(key)); args.add(value)
        match (rank) { case Some(r) => args.add(Blob.fromUtf8("RANK")); args.add(Blob.fromUtf8("${r}")) case None => () }
        match (count) { case Some(c) => args.add(Blob.fromUtf8("COUNT")); args.add(Blob.fromUtf8("${c}")) case None => () }
        match (maxLen) { case Some(m) => args.add(Blob.fromUtf8("MAXLEN")); args.add(Blob.fromUtf8("${m}")) case None => () }
        let resp = execute(collectArray(args.iterator()))
        match (resp) {
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => resp  // 返回原始 RESPValue，调用方根据 count 自行解析
        }
    }

    public func rpoplpush(source: String, destination: String): Option<Blob> {
        let resp = executeString(["RPOPLPUSH", source, destination])
        expectBlob(resp, "RPOPLPUSH")
    }

    public func lmove(source: String, destination: String, whereFrom!: String = "LEFT",
                      whereTo!: String = "RIGHT"): Option<Blob> {
        let resp = executeString(["LMOVE", source, destination, whereFrom, whereTo])
        expectBlob(resp, "LMOVE")
    }

    public func blmove(source: String, destination: String, whereFrom!: String = "LEFT",
                       whereTo!: String = "RIGHT", timeout!: Int64 = 0): Option<Blob> {
        let resp = executeString(["BLMOVE", source, destination, whereFrom, whereTo, "${timeout}"])
        expectBlob(resp, "BLMOVE")
    }

    public func brpoplpush(source: String, destination: String, timeout!: Int64 = 0): Option<Blob> {
        let resp = executeString(["BRPOPLPUSH", source, destination, "${timeout}"])
        expectBlob(resp, "BRPOPLPUSH")
    }

    /// 从多个列表弹出元素（Redis 7.0+）。
    public func lmpop(keys: Array<String>, side!: String = "LEFT",
                      count!: Option<Int64> = None): Option<(String, Array<Blob>)> {
        let args = ArrayList<String>(); args.add("LMPOP"); args.add("${keys.size}")
        for (k in keys) { args.add(k) }
        args.add(side)
        match (count) { case Some(c) => args.add("COUNT"); args.add("${c}") case None => () }
        parseMultiPopResult(executeString(collectArray(args.iterator())), "LMPOP")
    }

    /// 阻塞式从多个列表弹出元素（Redis 7.0+）。
    public func blmpop(timeout: Float64, keys: Array<String>, side!: String = "LEFT",
                       count!: Option<Int64> = None): Option<(String, Array<Blob>)> {
        let args = ArrayList<String>(); args.add("BLMPOP"); args.add("${timeout}"); args.add("${keys.size}")
        for (k in keys) { args.add(k) }
        args.add(side)
        match (count) { case Some(c) => args.add("COUNT"); args.add("${c}") case None => () }
        parseMultiPopResult(executeString(collectArray(args.iterator())), "BLMPOP")
    }

    private func parseListPopCount(resp: RESPValue, cmd: String): Array<Blob> {
        match (resp) {
            case RESPValue.Array(Some(items)) => extractBlobArray(items)
            case RESPValue.Null | RESPValue.Array(None) => Array<Blob>()
            case RESPValue.Error(e) => throw createCommandError(e)
            case RESPValue.BulkError(e) => throw createCommandError(e.toUtf8())
            case _ => throw ProtocolError("${cmd} 返回意外类型")
        }
    }

    private func parseMultiPopResult(resp: RESPValue, cmd: String): Option<(String, Array<Blob>)> {
        match (resp) {
            case RESPValue.Array(Some(items)) =>
                if (items.size >= 2) {
                    let key = asString(items[0])
                    let values = match (items[1]) {
                        case RESPValue.Array(Some(vs)) => extractBlobArray(vs)
                        case _ => Array<Blob>()
                    }
                    match (key) {
                        case Some(k) => Some((k, values))
                        case None => None
                    }
                } else {
                    None
                }
            case RESPValue.Null | RESPValue.Array(None) => None
            case RESPValue.Error(e) => throw createCommandError(e)
            case RESPValue.BulkError(e) => throw createCommandError(e.toUtf8())
            case _ => throw ProtocolError("${cmd} 返回意外类型")
        }
    }
}
