package redis.client
import std.collection.*

/// Push 消息观察者接口（Observer 模式）
public interface PushObserver {
    /// 收到 Push 消息时回调
    /// @param pushType Push 类型（如 "pubsub"、"monitor"）
    /// @param data Push 数据
    func onPush(pushType: String, data: Array<RESPValue>): Unit
}

/// Pub/Sub 发布订阅扩展
extend RedisClient {
    /// 订阅频道
    public func subscribe(channels: Array<String>,
                          handler: (Blob, Blob) -> Unit): Unit {
        let decoder = connection.getDecoder()
        decoder.onPush({ pushVal => handlePush(pushVal, handler) })

        let args = ArrayList<Blob>()
        args.add(Blob.fromUtf8("SUBSCRIBE"))
        for (ch in channels) {
            args.add(Blob.fromUtf8(ch))
        }
        let resp = connection.executeReturningPush(collectArray(args.iterator()))
        match (resp) {
            case RESPValue.Array(Some(items)) =>
                if (items.size >= 3) {
                    match (asString(items[0])) {
                        case Some("subscribe") =>
                            println("已订阅频道: ${asString(items[1]).getOrThrow()}")
                        case _ => ()
                    }
                }
                connection.setState(ConnectionState.Subscribed)
            case RESPValue.Push(_) =>
                connection.setState(ConnectionState.Subscribed)
            case RESPValue.Error(e) => throw createCommandError(e)
            case RESPValue.BulkError(e) => throw createCommandError(e.toUtf8())
            case _ => ()
        }
    }

    /// 退订频道
    public func unsubscribe(channels: Array<String>): Unit {
        let args = ArrayList<Blob>()
        args.add(Blob.fromUtf8("UNSUBSCRIBE"))
        for (ch in channels) {
            args.add(Blob.fromUtf8(ch))
        }
        let resp = connection.executeReturningPush(collectArray(args.iterator()))
        match (remainingSubscriptionCount(resp)) {
            case Some(0) => connection.setState(ConnectionState.Connected)
            case _ => ()
        }
    }

    /// 发布消息到频道
    public func publish(channel: String, message: Blob): Int64 {
        let resp = connection.execute([
            Blob.fromUtf8("PUBLISH"),
            Blob.fromUtf8(channel),
            message,
        ])
        match (resp) {
            case RESPValue.Integer(n) => n
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("PUBLISH 返回意外类型")
        }
    }

    /// 模式订阅
    public func psubscribe(patterns: Array<String>,
                           handler: (Blob, Blob) -> Unit): Unit {
        let decoder = connection.getDecoder()
        decoder.onPush({ pushVal => handlePush(pushVal, handler) })

        let args = ArrayList<Blob>()
        args.add(Blob.fromUtf8("PSUBSCRIBE"))
        for (p in patterns) {
            args.add(Blob.fromUtf8(p))
        }
        let resp = connection.executeReturningPush(collectArray(args.iterator()))
        match (resp) {
            case RESPValue.Error(e) => throw createCommandError(e)
            case RESPValue.BulkError(e) => throw createCommandError(e.toUtf8())
            case _ => connection.setState(ConnectionState.Subscribed)
        }
    }

    /// 模式退订
    public func punsubscribe(patterns: Array<String>): Unit {
        let args = ArrayList<Blob>()
        args.add(Blob.fromUtf8("PUNSUBSCRIBE"))
        for (p in patterns) {
            args.add(Blob.fromUtf8(p))
        }
        let resp = connection.executeReturningPush(collectArray(args.iterator()))
        match (remainingSubscriptionCount(resp)) {
            case Some(0) => connection.setState(ConnectionState.Connected)
            case _ => ()
        }
    }

    // ====================================================================
    // 内部 Push 处理
    // ====================================================================

    private func handlePush(pushVal: RESPValue,
                           handler: (Blob, Blob) -> Unit): Unit {
        match (pushVal) {
            case RESPValue.Push(items) =>
                if (items.size >= 3) {
                    match (asString(items[0])) {
                        case Some("pubsub") =>
                            match (asString(items[1])) {
                                case Some("message") =>
                                    let channel = asBlob(items[2])
                                    let optMsg: Option<Blob> = if (items.size >= 4) {
                                        asBlob(items[3])
                                    } else {
                                        None
                                    }
                                    match ((channel, optMsg)) {
                                        case (Some(ch), Some(msg)) => handler(ch, msg)
                                        case _ => ()
                                    }
                                case Some("pmessage") =>
                                    if (items.size >= 4) {
                                        let channel = asBlob(items[2])
                                        let message = asBlob(items[3])
                                        match ((channel, message)) {
                                            case (Some(ch), Some(msg)) => handler(ch, msg)
                                            case _ => ()
                                        }
                                    }
	                                case _ => ()
	                            }
                        case Some("message") | Some("smessage") =>
                            if (items.size >= 3) {
                                let channel = asBlob(items[1])
                                let message = asBlob(items[2])
                                match ((channel, message)) {
                                    case (Some(ch), Some(msg)) => handler(ch, msg)
                                    case _ => ()
                                }
                            }
                        case Some("pmessage") =>
                            if (items.size >= 4) {
                                let channel = asBlob(items[2])
                                let message = asBlob(items[3])
                                match ((channel, message)) {
                                    case (Some(ch), Some(msg)) => handler(ch, msg)
                                    case _ => ()
                                }
                            }
                        case _ => ()
                    }
                }
            case _ => ()
        }
    }

    /// 阻塞读取下一条 Pub/Sub Push 帧，并触发已注册的回调。
    public func readPubSubMessage(): RESPValue {
        connection.readNextPush()
    }

    // -------- PUBSUB 内省 --------

    /// 查看活跃频道
    public func pubsubChannels(pattern!: Option<String> = None): Array<String> {
        let args = ArrayList<String>(); args.add("PUBSUB"); args.add("CHANNELS")
        match (pattern) { case Some(p) => args.add(p) case None => () }
        match (executeString(collectArray(args.iterator()))) {
            case RESPValue.Array(Some(items)) => extractStringArray(items)
            case RESPValue.Set(items) => extractStringArray(items)
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("PUBSUB CHANNELS 返回意外类型")
        }
    }

    /// 查看频道订阅数
    public func pubsubNumsub(channels: Array<String>): Array<(String, Int64)> {
        let args = ArrayList<String>(); args.add("PUBSUB"); args.add("NUMSUB")
        for (ch in channels) { args.add(ch) }
        match (executeString(collectArray(args.iterator()))) {
            case RESPValue.Array(Some(items)) =>
                parseFlatPairs(items)
            case RESPValue.Map(pairs) =>
                // RESP3: Map<channel, count>
                let result = ArrayList<(String, Int64)>()
                for ((k, v) in pairs) {
                    match ((asString(k), asInt(v))) {
                        case (Some(ch), Some(n)) => result.add((ch, n))
                        case _ => ()
                    }
                }
                collectArray(result.iterator())
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("PUBSUB NUMSUB 返回意外类型")
        }
    }

    /// 查看模式订阅数
    public func pubsubNumpat(): Int64 {
        expectInt(executeString(["PUBSUB", "NUMPAT"]), "PUBSUB NUMPAT")
    }

    /// 查看活跃分片频道（Redis 7.0+）
    public func pubsubShardChannels(pattern!: Option<String> = None): Array<String> {
        let args = ArrayList<String>(); args.add("PUBSUB"); args.add("SHARDCHANNELS")
        match (pattern) { case Some(p) => args.add(p) case None => () }
        match (executeString(collectArray(args.iterator()))) {
            case RESPValue.Array(Some(items)) => extractStringArray(items)
            case RESPValue.Set(items) => extractStringArray(items)
            case RESPValue.Error(e) => throw createCommandError(e)
            case RESPValue.BulkError(e) => throw createCommandError(e.toUtf8())
            case _ => throw ProtocolError("PUBSUB SHARDCHANNELS 返回意外类型")
        }
    }

    /// 查看分片频道订阅数（Redis 7.0+）
    public func pubsubShardNumsub(channels: Array<String>): Array<(String, Int64)> {
        let args = ArrayList<String>(); args.add("PUBSUB"); args.add("SHARDNUMSUB")
        for (ch in channels) { args.add(ch) }
        match (executeString(collectArray(args.iterator()))) {
            case RESPValue.Array(Some(items)) => parseFlatPairs(items)
            case RESPValue.Map(pairs) =>
                let result = ArrayList<(String, Int64)>()
                for ((k, v) in pairs) {
                    match ((asString(k), asInt(v))) {
                        case (Some(ch), Some(n)) => result.add((ch, n))
                        case _ => ()
                    }
                }
                collectArray(result.iterator())
            case RESPValue.Error(e) => throw createCommandError(e)
            case RESPValue.BulkError(e) => throw createCommandError(e.toUtf8())
            case _ => throw ProtocolError("PUBSUB SHARDNUMSUB 返回意外类型")
        }
    }

    /// 从扁平数组中解析键值对 [k1, v1, k2, v2, ...]
    private func parseFlatPairs(items: Array<RESPValue>): Array<(String, Int64)> {
        let result = ArrayList<(String, Int64)>()
        var i: Int64 = 0
        while (i + 1 < items.size) {
            match ((asString(items[i]), asInt(items[i + 1]))) {
                case (Some(ch), Some(n)) => result.add((ch, n))
                case _ => ()
            }
            i += 2
        }
        collectArray(result.iterator())
    }

    private func remainingSubscriptionCount(resp: RESPValue): Option<Int64> {
        match (resp) {
            case RESPValue.Array(Some(items)) =>
                if (items.size >= 3) {
                    asInt(items[2])
                } else {
                    None
                }
            case RESPValue.Push(items) =>
                match (asString(items[0])) {
                    case Some("pubsub") =>
                        if (items.size >= 4) {
                            asInt(items[3])
                        } else {
                            None
                        }
                    case _ =>
                        if (items.size >= 3) {
                            asInt(items[2])
                        } else {
                            None
                        }
                }
            case _ => None
        }
    }

    // -------- 分片 Pub/Sub (Redis 7.0+) --------

    /// 发布消息到分片频道
    public func spublish(channel: String, message: Blob): Int64 {
        let resp = execute([Blob.fromUtf8("SPUBLISH"), Blob.fromUtf8(channel), message])
        expectInt(resp, "SPUBLISH")
    }

    /// 订阅分片频道
    public func ssubscribe(channels: Array<String>, handler: (Blob, Blob) -> Unit): Unit {
        let decoder = connection.getDecoder()
        decoder.onPush({ pushVal => handlePush(pushVal, handler) })

        let args = ArrayList<Blob>(); args.add(Blob.fromUtf8("SSUBSCRIBE"))
        for (ch in channels) { args.add(Blob.fromUtf8(ch)) }
        let resp = connection.executeReturningPush(collectArray(args.iterator()))
        match (resp) {
            case RESPValue.Error(e) => throw createCommandError(e)
            case RESPValue.BulkError(e) => throw createCommandError(e.toUtf8())
            case _ => connection.setState(ConnectionState.Subscribed)
        }
    }

    /// 退订分片频道
    public func sunsubscribe(channels: Array<String>): Unit {
        let args = ArrayList<Blob>(); args.add(Blob.fromUtf8("SUNSUBSCRIBE"))
        for (ch in channels) { args.add(Blob.fromUtf8(ch)) }
        let resp = connection.executeReturningPush(collectArray(args.iterator()))
        match (remainingSubscriptionCount(resp)) {
            case Some(0) => connection.setState(ConnectionState.Connected)
            case _ => ()
        }
    }
}
