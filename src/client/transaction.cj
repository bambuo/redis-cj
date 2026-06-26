package redis.client
import std.collection.*

/// 事务对象（Command 模式 + 状态模式）
///
/// Redis 事务要求 WATCH 在 MULTI 之前调用，MULTI/EXEC 包裹命令队列。
///
/// # 用法
/// ```cangjie
/// let txn = Transaction(client)
/// txn.watch(["key1", "key2"])  // 先 WATCH
/// txn.multi()                   // 再 MULTI
/// txn.queue(["SET", "key", "val"])  // 入队命令
/// let results = txn.exec()
/// ```
public class Transaction {
    private let client: RedisClient
    private var commands: ArrayList<Array<Blob>>
    private var executed: Bool
    private var started: Bool

    /// 创建事务，不立即发送 MULTI
    public init(client: RedisClient) {
        this.client = client
        this.commands = ArrayList<Array<Blob>>()
        this.executed = false
        this.started = false
    }

    /// 添加 WATCH 监视（必须在 multi() 之前调用）
    public func watch(keys: Array<String>): Transaction {
        if (executed) { throw RedisError("事务已执行") }
        if (started) { throw RedisError("WATCH 必须在 MULTI 之前调用") }
        let args = ArrayList<Blob>()
        args.add(Blob.fromUtf8("WATCH"))
        for (k in keys) {
            args.add(Blob.fromUtf8(k))
        }
        let resp = client.execute(collectArray(args.iterator()))
        match (resp) {
            case RESPValue.SimpleString(_) => ()
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("WATCH 返回意外类型")
        }
        this
    }

    /// 开始事务：发送 MULTI
    public func multi(): Transaction {
        if (executed) { throw RedisError("事务已执行") }
        if (started) { throw RedisError("MULTI 已发送") }
        started = true
        let resp = client.executeString(["MULTI"])
        match (resp) {
            case RESPValue.SimpleString("OK") => ()
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("MULTI 返回意外类型")
        }
        this
    }

    /// 向事务队列中添加命令
    public func queue(args: Array<String>): Transaction {
        if (executed) { throw RedisError("事务已执行") }
        let blobArgs = ArrayList<Blob>()
        for (s in args) {
            blobArgs.add(Blob.fromUtf8(s))
        }
        commands.add(collectArray(blobArgs.iterator()))
        this
    }

    /// 执行事务（发送 QUEUED 命令 + EXEC）
    public func exec(): Array<RESPValue> {
        if (executed) { throw RedisError("事务已执行") }
        if (!started) { multi() }  // 自动发送 MULTI 如果尚未发送
        executed = true

        for (cmd in commands) {
            let resp = client.execute(cmd)
            match (resp) {
                case RESPValue.SimpleString("QUEUED") => ()
                case RESPValue.Error(e) =>
                    client.executeString(["DISCARD"])
                    throw CommandError(e)
                case _ => ()
            }
        }

        let resp = client.executeString(["EXEC"])
        match (resp) {
            case RESPValue.Array(Some(items)) => items
            case RESPValue.Array(None) => throw TransactionAbortedError()
            case RESPValue.Null => throw TransactionAbortedError()
            case RESPValue.Error(e) => throw createCommandError(e)
            case RESPValue.BulkError(e) => throw createCommandError(e.toUtf8())
            case _ => throw ProtocolError("EXEC 返回意外类型")
        }
    }

    /// 放弃事务
    public func discard(): Unit {
        if (executed) { return }
        executed = true
        if (started) {
            client.executeString(["DISCARD"])
        }
    }
}

/// 事务扩展
extend RedisClient {
    /// 创建新事务
    public func multi(): Transaction {
        Transaction(this).multi()
    }

    /// 执行简单事务
    public func execTransaction(commands: Array<Array<String>>): Array<RESPValue> {
        let txn = Transaction(this)
        for (cmd in commands) {
            txn.queue(cmd)
        }
        txn.exec()
    }

    /// 取消 WATCH 监视
    public func unwatch(): Unit {
        let resp = executeString(["UNWATCH"])
        expectOK(resp, "UNWATCH")
    }
}
