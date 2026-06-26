package redis.client
import std.collection.*

// ====================================================================
// 流命令 (Stream Commands)
// ====================================================================

extend RedisClient {
    // -------- 基础操作 --------

    /// 向流追加一条消息。返回消息 ID。
    public func xadd(key: String, fields: Array<(String, Blob)>,
                     id!: String = "*",
                     maxLen!: Option<Int64> = None,
                     minId!: Option<String> = None,
                     approx!: Bool = false,
                     nomkstream!: Bool = false,
                     limit!: Option<Int64> = None): Blob {
        let args = ArrayList<Blob>()
        args.add(Blob.fromUtf8("XADD")); args.add(Blob.fromUtf8(key))
        if (nomkstream) { args.add(Blob.fromUtf8("NOMKSTREAM")) }
        match (minId) {
            case Some(idVal) =>
                args.add(Blob.fromUtf8("MINID"))
                args.add(Blob.fromUtf8(if (approx) { "~" } else { "=" }))
                args.add(Blob.fromUtf8(idVal))
                match (limit) { case Some(l) => args.add(Blob.fromUtf8("LIMIT")); args.add(Blob.fromUtf8("${l}")) case None => () }
            case None =>
                match (maxLen) {
                    case Some(n) =>
                        args.add(Blob.fromUtf8("MAXLEN"))
                        args.add(Blob.fromUtf8(if (approx) { "~" } else { "=" }))
                        args.add(Blob.fromUtf8("${n}"))
                        match (limit) { case Some(l) => args.add(Blob.fromUtf8("LIMIT")); args.add(Blob.fromUtf8("${l}")) case None => () }
                    case None => ()
                }
        }
        args.add(Blob.fromUtf8(id))
        for ((f, v) in fields) { args.add(Blob.fromUtf8(f)); args.add(v) }
        let resp = execute(collectArray(args.iterator()))
        expectBlobVal(resp, "XADD")
    }

    /// 获取流的长度
    public func xlen(key: String): Int64 {
        let resp = executeString(["XLEN", key])
        expectInt(resp, "XLEN")
    }

    /// 删除流中一个或多个消息
    public func xdel(key: String, ids: Array<String>): Int64 {
        let args = ArrayList<String>(); args.add("XDEL"); args.add(key)
        for (id in ids) { args.add(id) }
        let resp = executeString(collectArray(args.iterator()))
        expectInt(resp, "XDEL")
    }

    /// 设置流的最后交付 ID
    public func xsetid(key: String, id: String, entriesAdded!: Option<Int64> = None): Unit {
        let args = ArrayList<Blob>()
        args.add(Blob.fromUtf8("XSETID")); args.add(Blob.fromUtf8(key)); args.add(Blob.fromUtf8(id))
        match (entriesAdded) {
            case Some(n) => args.add(Blob.fromUtf8("ENTRIESADDED")); args.add(Blob.fromUtf8("${n}"))
            case None => ()
        }
        let resp = execute(collectArray(args.iterator()))
        expectOK(resp, "XSETID")
    }

    /// 修剪流到指定长度
    public func xtrim(key: String, maxLen: Int64, approx!: Bool = false,
                      minId!: Option<String> = None, limit!: Option<Int64> = None): Int64 {
        let args = ArrayList<String>(); args.add("XTRIM"); args.add(key)
        match (minId) {
            case Some(idVal) =>
                args.add("MINID")
                if (approx) { args.add("~") }
                args.add(idVal)
            case None =>
                args.add("MAXLEN")
                if (approx) { args.add("~") }
                args.add("${maxLen}")
        }
        match (limit) { case Some(l) => args.add("LIMIT"); args.add("${l}") case None => () }
        let resp = executeString(collectArray(args.iterator()))
        expectInt(resp, "XTRIM")
    }

    // -------- 范围读取 --------

    /// 读取流中的消息范围
    public func xrange(key: String, start!: String = "-", end!: String = "+",
                       count!: Option<Int64> = None): Array<(String, Array<(String, Blob)>)> {
        let args = ArrayList<String>(); args.add("XRANGE"); args.add(key); args.add(start); args.add(end)
        match (count) { case Some(n) => args.add("COUNT"); args.add("${n}") case None => () }
        parseStreamEntries(executeString(collectArray(args.iterator())))
    }

    /// 反向读取流中的消息范围
    public func xrevrange(key: String, end!: String = "+", start!: String = "-",
                          count!: Option<Int64> = None): Array<(String, Array<(String, Blob)>)> {
        let args = ArrayList<String>(); args.add("XREVRANGE"); args.add(key); args.add(end); args.add(start)
        match (count) { case Some(n) => args.add("COUNT"); args.add("${n}") case None => () }
        parseStreamEntries(executeString(collectArray(args.iterator())))
    }

    // -------- 非阻塞/阻塞读取 --------

    /// 读取流
    public func xread(streams: Array<(String, String)>,
                      count!: Option<Int64> = None,
                      block!: Option<Int64> = None): Array<(String, Array<(String, Array<(String, Blob)>)>)> {
        let args = ArrayList<String>(); args.add("XREAD")
        match (count) { case Some(n) => args.add("COUNT"); args.add("${n}") case None => () }
        match (block) { case Some(ms) => args.add("BLOCK"); args.add("${ms}") case None => () }
        args.add("STREAMS")
        let keys = ArrayList<String>(); let ids = ArrayList<String>()
        for ((k, id) in streams) { keys.add(k); ids.add(id) }
        for (k in keys) { args.add(k) }
        for (id in ids) { args.add(id) }
        let resp = executeString(collectArray(args.iterator()))
        parseXReadResult(resp)
    }

    // ====================================================================
    // 消费者组 (Consumer Group) 命令
    // ====================================================================

    /// 使用消费者组读取流
    public func xreadgroup(group: String, consumer: String, streams: Array<(String, String)>,
                           count!: Option<Int64> = None, block!: Option<Int64> = None,
                           noack!: Bool = false): Array<(String, Array<(String, Array<(String, Blob)>)>)> {
        let args = ArrayList<String>()
        args.add("XREADGROUP"); args.add("GROUP"); args.add(group); args.add(consumer)
        match (count) { case Some(n) => args.add("COUNT"); args.add("${n}") case None => () }
        match (block) { case Some(ms) => args.add("BLOCK"); args.add("${ms}") case None => () }
        if (noack) { args.add("NOACK") }
        args.add("STREAMS")
        let keys = ArrayList<String>(); let ids = ArrayList<String>()
        for ((k, id) in streams) { keys.add(k); ids.add(id) }
        for (k in keys) { args.add(k) }
        for (id in ids) { args.add(id) }
        let resp = executeString(collectArray(args.iterator()))
        parseXReadResult(resp)
    }

    /// 确认消息已处理
    public func xack(key: String, group: String, ids: Array<String>): Int64 {
        let args = ArrayList<String>(); args.add("XACK"); args.add(key); args.add(group)
        for (id in ids) { args.add(id) }
        let resp = executeString(collectArray(args.iterator()))
        expectInt(resp, "XACK")
    }

    // -------- 消费者组管理 --------

    /// 创建消费者组
    public func xgroupCreate(key: String, group: String, id!: String = "$",
                             mkstream!: Bool = false): Unit {
        let args = ArrayList<String>(); args.add("XGROUP"); args.add("CREATE")
        args.add(key); args.add(group); args.add(id)
        if (mkstream) { args.add("MKSTREAM") }
        let resp = executeString(collectArray(args.iterator()))
        expectOK(resp, "XGROUP CREATE")
    }

    /// 创建消费者
    public func xgroupCreateConsumer(key: String, group: String, consumer: String): Bool {
        let resp = executeString(["XGROUP", "CREATECONSUMER", key, group, consumer])
        match (resp) {
            case RESPValue.Integer(1) => true
            case RESPValue.Integer(0) => false
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("XGROUP CREATECONSUMER 返回意外类型")
        }
    }

    /// 删除消费者
    public func xgroupDelConsumer(key: String, group: String, consumer: String): Int64 {
        let resp = executeString(["XGROUP", "DELCONSUMER", key, group, consumer])
        expectInt(resp, "XGROUP DELCONSUMER")
    }

    /// 销毁消费者组
    public func xgroupDestroy(key: String, group: String): Bool {
        let resp = executeString(["XGROUP", "DESTROY", key, group])
        match (resp) {
            case RESPValue.Integer(1) => true
            case RESPValue.Integer(0) => false
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("XGROUP DESTROY 返回意外类型")
        }
    }

    /// 设置消费者组的最后交付 ID
    public func xgroupSetId(key: String, group: String, id: String,
                            entriesRead!: Option<Int64> = None): Unit {
        let args = ArrayList<String>(); args.add("XGROUP"); args.add("SETID")
        args.add(key); args.add(group); args.add(id)
        match (entriesRead) { case Some(n) => args.add("ENTRIESREAD"); args.add("${n}") case None => () }
        let resp = executeString(collectArray(args.iterator()))
        expectOK(resp, "XGROUP SETID")
    }

    // -------- 流信息 --------

    /// 获取流信息
    public func xinfoStream(key: String): HashMap<String, RESPValue> {
        let resp = executeString(["XINFO", "STREAM", key])
        parseMapResp(resp)
    }

    /// 获取完整流信息（Redis 6.0+ FULL，COUNT 用于限制返回的 PEL/entries 数量）。
    public func xinfoStreamFull(key: String, count!: Option<Int64> = None): HashMap<String, RESPValue> {
        let args = ArrayList<String>(); args.add("XINFO"); args.add("STREAM"); args.add(key); args.add("FULL")
        match (count) { case Some(n) => args.add("COUNT"); args.add("${n}") case None => () }
        parseMapResp(executeString(collectArray(args.iterator())))
    }

    /// 获取消费者组列表
    public func xinfoGroups(key: String): Array<HashMap<String, RESPValue>> {
        let resp = executeString(["XINFO", "GROUPS", key])
        parseArrayOfMaps(resp)
    }

    /// 获取消费者列表
    public func xinfoConsumers(key: String, group: String): Array<HashMap<String, RESPValue>> {
        let resp = executeString(["XINFO", "CONSUMERS", key, group])
        parseArrayOfMaps(resp)
    }

    // -------- 待处理消息 --------

    /// 获取待处理消息列表
    public func xpending(key: String, group: String, start!: String = "-", end!: String = "+",
                         count!: Int64 = 10, consumer!: Option<String> = None,
                         idle!: Option<Int64> = None): Array<RESPValue> {
        let args = ArrayList<String>(); args.add("XPENDING"); args.add(key); args.add(group)
        // 详细模式需要 start/end/count
        match (idle) { case Some(ms) => args.add("IDLE"); args.add("${ms}") case None => () }
        args.add(start); args.add(end); args.add("${count}")
        match (consumer) { case Some(c) => args.add(c) case None => () }
        let resp = executeString(collectArray(args.iterator()))
        match (resp) {
            case RESPValue.Array(Some(items)) => items
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("XPENDING 返回意外类型")
        }
    }

    /// 获取待处理消息摘要
    public func xpendingSummary(key: String, group: String): (Int64, String, String, Array<RESPValue>) {
        let resp = executeString(["XPENDING", key, group])
        match (resp) {
            case RESPValue.Array(Some(items)) =>
                let total = expectInt(RESPValue.Integer(asInt(items[0]).getOrThrow()), "XPENDING")
                let start = asString(items[1]).getOrThrow()
                let end = asString(items[2]).getOrThrow()
                let consumers = if (items.size >= 4) {
                    match (items[3]) {
                        case RESPValue.Array(Some(c)) => c
                        case _ => Array<RESPValue>()
                    }
                } else { Array<RESPValue>() }
                (total, start, end, consumers)
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("XPENDING 返回意外类型")
        }
    }

    // -------- 消息认领 --------

    /// 认领超时的待处理消息
    public func xclaim(key: String, group: String, consumer: String, minIdleTime: Int64,
                       ids: Array<String>, idle!: Option<Int64> = None,
                       retryCount!: Option<Int64> = None, force!: Bool = false,
                       justId!: Bool = false): Array<(String, Array<(String, Blob)>)> {
        let args = ArrayList<Blob>()
        args.add(Blob.fromUtf8("XCLAIM")); args.add(Blob.fromUtf8(key))
        args.add(Blob.fromUtf8(group)); args.add(Blob.fromUtf8(consumer))
        args.add(Blob.fromUtf8("${minIdleTime}"))
        for (id in ids) { args.add(Blob.fromUtf8(id)) }
        match (idle) { case Some(t) => args.add(Blob.fromUtf8("IDLE")); args.add(Blob.fromUtf8("${t}")) case None => () }
        match (retryCount) { case Some(n) => args.add(Blob.fromUtf8("RETRYCOUNT")); args.add(Blob.fromUtf8("${n}")) case None => () }
        if (force) { args.add(Blob.fromUtf8("FORCE")) }
        if (justId) { args.add(Blob.fromUtf8("JUSTID")) }
        let resp = execute(collectArray(args.iterator()))
        if (justId) {
            match (resp) {
                case RESPValue.Array(Some(items)) =>
                    let result = ArrayList<(String, Array<(String, Blob)>)>()
                    for (item in items) {
                        match (item) {
                            case RESPValue.BulkString(Some(blob)) =>
                                result.add((blob.toUtf8(), Array<(String, Blob)>()))
                            case _ => ()
                        }
                    }
                    collectArray(result.iterator())
                case RESPValue.Error(e) => throw CommandError(e)
                case _ => throw ProtocolError("XCLAIM JUSTID 返回意外类型")
            }
        } else {
            parseStreamEntries(resp)
        }
    }

    /// 自动认领超时的待处理消息
    public func xautoclaim(key: String, group: String, consumer: String,
                           minIdleTime: Int64, start!: String = "0-0",
                           count!: Option<Int64> = None, justId!: Bool = false): (String, Array<RESPValue>) {
        let (nextStart, messages, _) = xautoclaimWithDeleted(
            key,
            group,
            consumer,
            minIdleTime,
            start: start,
            count: count,
            justId: justId
        )
        (nextStart, messages)
    }

    /// 自动认领超时消息，并返回 Redis 7.0+ 的已删除消息 ID 列表。
    public func xautoclaimWithDeleted(key: String, group: String, consumer: String,
                                      minIdleTime: Int64, start!: String = "0-0",
                                      count!: Option<Int64> = None,
                                      justId!: Bool = false): (String, Array<RESPValue>, Array<String>) {
        let args = ArrayList<Blob>()
        args.add(Blob.fromUtf8("XAUTOCLAIM")); args.add(Blob.fromUtf8(key))
        args.add(Blob.fromUtf8(group)); args.add(Blob.fromUtf8(consumer))
        args.add(Blob.fromUtf8("${minIdleTime}")); args.add(Blob.fromUtf8(start))
        match (count) { case Some(n) => args.add(Blob.fromUtf8("COUNT")); args.add(Blob.fromUtf8("${n}")) case None => () }
        if (justId) { args.add(Blob.fromUtf8("JUSTID")) }
        let resp = execute(collectArray(args.iterator()))
        match (resp) {
            case RESPValue.Array(Some(items)) =>
                if (items.size >= 2) {
                    let nextStart = asString(items[0]).getOrThrow()
                    let messages = items[1]
                    let msgs = match (messages) {
                        case RESPValue.Array(Some(m)) => m
                        case _ => Array<RESPValue>()
                    }
                    let deletedIds = if (items.size >= 3) {
                        match (items[2]) {
                            case RESPValue.Array(Some(ids)) => extractStringArray(ids)
                            case _ => Array<String>()
                        }
                    } else {
                        Array<String>()
                    }
                    (nextStart, msgs, deletedIds)
                } else { ("0-0", Array<RESPValue>(), Array<String>()) }
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("XAUTOCLAIM 返回意外类型")
        }
    }

    // ====================================================================
    // 内部辅助
    // ====================================================================

    private func parseStreamEntries(resp: RESPValue): Array<(String, Array<(String, Blob)>)> {
        match (resp) {
            case RESPValue.Array(Some(entries)) =>
                let result = ArrayList<(String, Array<(String, Blob)>)>()
                for (entry in entries) {
                    match (entry) {
                        case RESPValue.Array(Some(items)) =>
                            if (items.size >= 2) {
                                let id = asString(items[0]).getOrThrow()
                                match (items[1]) {
                                    case RESPValue.Array(Some(fields)) =>
                                        let pairs = ArrayList<(String, Blob)>()
                                        var i: Int64 = 0
                                        while (i + 1 < fields.size) {
                                            match ((asString(fields[i]), asBlob(fields[i + 1]))) {
                                                case (Some(f), Some(v)) => pairs.add((f, v))
                                                case _ => ()
                                            }
                                            i += 2
                                        }
                                        result.add((id, collectArray(pairs.iterator())))
                                    case _ => ()
                                }
                            }
                        case _ => ()
                    }
                }
                collectArray(result.iterator())
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("流命令返回意外类型")
        }
    }

    private func parseXReadResult(resp: RESPValue): Array<(String, Array<(String, Array<(String, Blob)>)>)> {
        match (resp) {
            case RESPValue.Array(Some(streams)) =>
                let result = ArrayList<(String, Array<(String, Array<(String, Blob)>)>)>()
                for (stream in streams) {
                    match (stream) {
                        case RESPValue.Array(Some(items)) =>
                            if (items.size >= 2) {
                                let name = asString(items[0]).getOrThrow()
                                let entries = parseStreamEntries(items[1])
                                result.add((name, entries))
                            }
                        case _ => ()
                    }
                }
                collectArray(result.iterator())
            case RESPValue.Map(pairs) =>
                // RESP3: Map<streamName, entries>
                let result = ArrayList<(String, Array<(String, Array<(String, Blob)>)>)>()
                for ((k, v) in pairs) {
                    match (asString(k)) {
                        case Some(name) =>
                            let entries = parseStreamEntries(v)
                            result.add((name, entries))
                        case None => ()
                    }
                }
                collectArray(result.iterator())
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("XREAD 返回意外类型")
        }
    }

    /// 将 Map RESP 响应解析为 HashMap
    private func parseMapResp(resp: RESPValue): HashMap<String, RESPValue> {
        let result = HashMap<String, RESPValue>()
        match (resp) {
            case RESPValue.Map(pairs) =>
                for ((k, v) in pairs) {
                    match (asString(k)) {
                        case Some(key) => result[key] = v
                        case None => ()
                    }
                }
            case RESPValue.Array(Some(items)) =>
                // RESP2 兼容：扁平数组 [k1, v1, k2, v2, ...]
                var i: Int64 = 0
                while (i + 1 < items.size) {
                    match (asString(items[i])) {
                        case Some(key) => result[key] = items[i + 1]
                        case None => ()
                    }
                    i += 2
                }
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("Map 响应解析失败")
        }
        result
    }

    /// 将 Array of Map 响应解析为数组
    private func parseArrayOfMaps(resp: RESPValue): Array<HashMap<String, RESPValue>> {
        let result = ArrayList<HashMap<String, RESPValue>>()
        match (resp) {
            case RESPValue.Array(Some(items)) =>
                for (item in items) {
                    result.add(parseMapResp(item))
                }
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("Array of Map 响应解析失败")
        }
        collectArray(result.iterator())
    }
}
