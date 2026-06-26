package redis.client
import std.collection.*
import std.convert.*

// ====================================================================
// Command<T> — 命令模式抽象基类
// ====================================================================

/// 命令模式：每个 Redis 命令封装为 Command<T> 对象。
///
/// T = 命令返回值的类型，如 Option<Blob>、Int64、Bool 等。
///
/// 子类职责：
///   1. encode() — 将参数编码为 Array<Blob>
///   2. decode() — 将 RESPValue 解析为 T
///
/// 模板方法 execute(client) 自动处理编解码流程。
///
/// 用法：
///   let cmd = GetCommand(key: "mykey")
///   let val: Option<Blob> = cmd.execute(client)
///
/// @param <T> 返回值类型
public abstract class Command<T> {
    /// 执行命令（模板方法）
    /// 自动完成编码→执行→解码的全流程
    public func execute(client: RedisClient): T {
        let resp = client.execute(encode())
        decode(resp)
    }

    /// 编码命令参数为 RESP Blob 数组
    public func encode(): Array<Blob>

    /// 解码 RESP 响应为强类型返回值
    public func decode(resp: RESPValue): T
}

// ====================================================================
// 响应解析辅助函数
// ====================================================================

/// 期望一个 SimpleString 响应，返回字符串内容
public func expectSimpleString(resp: RESPValue, cmd: String): String {
    match (resp) {
        case RESPValue.SimpleString(s) => s
        case RESPValue.Error(e) => throw createCommandError(e)
        case RESPValue.BulkError(e) => throw createCommandError(e.toUtf8())
        case _ => throw ProtocolError("${cmd}: 期望 SimpleString，但收到 ${respValueToString(resp)}")
    }
}

/// 期望 OK 响应
public func expectOK(resp: RESPValue, cmd: String): Unit {
    match (resp) {
        case RESPValue.SimpleString("OK") => ()
        case RESPValue.Error(e) => throw createCommandError(e)
        case RESPValue.BulkError(e) => throw createCommandError(e.toUtf8())
        case _ => throw ProtocolError("${cmd}: 期望 OK，但收到 ${respValueToString(resp)}")
    }
}

/// 期望 Integer 响应
public func expectInt(resp: RESPValue, cmd: String): Int64 {
    match (resp) {
        case RESPValue.Integer(n) => n
        case RESPValue.Error(e) => throw createCommandError(e)
        case RESPValue.BulkError(e) => throw createCommandError(e.toUtf8())
        case _ => throw ProtocolError("${cmd}: 期望 Integer，但收到 ${respValueToString(resp)}")
    }
}

/// 期望 Option<Blob> 响应（BulkString 或 RESP3 Null）
public func expectBlob(resp: RESPValue, cmd: String): Option<Blob> {
    match (resp) {
        case RESPValue.BulkString(v) => v
        case RESPValue.Null => None
        case RESPValue.Error(e) => throw createCommandError(e)
        case RESPValue.BulkError(e) => throw createCommandError(e.toUtf8())
        case _ => throw ProtocolError("${cmd}: 期望 BulkString，但收到 ${respValueToString(resp)}")
    }
}

/// 期望非 null 的 Blob 响应（或 RESP3 Null 时抛异常）
public func expectBlobVal(resp: RESPValue, cmd: String): Blob {
    match (resp) {
        case RESPValue.BulkString(Some(blob)) => blob
        case RESPValue.BulkString(None) =>
            throw ProtocolError("${cmd}: 收到意外的 nil BulkString")
        case RESPValue.Null =>
            throw ProtocolError("${cmd}: 收到意外的 Null")
        case RESPValue.Error(e) => throw createCommandError(e)
        case RESPValue.BulkError(e) => throw createCommandError(e.toUtf8())
        case _ => throw ProtocolError("${cmd}: 期望 BulkString，但收到 ${respValueToString(resp)}")
    }
}

/// 期望 Array<RESPValue> 响应
public func expectArray(resp: RESPValue, cmd: String): Option<Array<RESPValue>> {
    match (resp) {
        case RESPValue.Array(v) => v
        case RESPValue.Null => None
        case RESPValue.Error(e) => throw createCommandError(e)
        case RESPValue.BulkError(e) => throw createCommandError(e.toUtf8())
        case _ => throw ProtocolError("${cmd}: 期望 Array，但收到 ${respValueToString(resp)}")
    }
}

/// 期望 Map 或 Array（RESP2 兼容）响应
public func expectMapOrArray(resp: RESPValue, cmd: String): RESPValue {
    match (resp) {
        case RESPValue.Map(_) | RESPValue.Array(_) => resp
        case RESPValue.Error(e) => throw createCommandError(e)
        case RESPValue.BulkError(e) => throw createCommandError(e.toUtf8())
        case _ => throw ProtocolError("${cmd}: 期望 Map/Array，但收到 ${respValueToString(resp)}")
    }
}

/// 期望 Boolean 响应（Redis 3+ 返回 #t/#f，旧版返回 :1/:0）
public func expectBool(resp: RESPValue, cmd: String): Bool {
    match (resp) {
        case RESPValue.Boolean(b) => b
        case RESPValue.Integer(1) => true
        case RESPValue.Integer(0) => false
        case RESPValue.Error(e) => throw createCommandError(e)
        case RESPValue.BulkError(e) => throw createCommandError(e.toUtf8())
        case _ => throw ProtocolError("${cmd}: 期望 Boolean，但收到 ${respValueToString(resp)}")
    }
}

/// 期望 Double 响应
public func expectDouble(resp: RESPValue, cmd: String): Float64 {
    match (resp) {
        case RESPValue.Double(f) => f
        case RESPValue.BulkString(Some(blob)) =>
            try {
                Float64.parse(blob.toUtf8())
            } catch (e: Exception) {
                throw ProtocolError("${cmd}: 浮点数解析失败: ${e.message}")
            }
        case RESPValue.SimpleString(s) =>
            try {
                Float64.parse(s)
            } catch (e: Exception) {
                throw ProtocolError("${cmd}: 浮点数解析失败: ${e.message}")
            }
        case RESPValue.Error(e) => throw createCommandError(e)
        case RESPValue.BulkError(e) => throw createCommandError(e.toUtf8())
        case _ => throw ProtocolError("${cmd}: 期望 Double，但收到 ${respValueToString(resp)}")
    }
}

/// 将字符串数组转为 Blob 数组
public func stringsToBlobs(args: Array<String>): Array<Blob> {
    let result = ArrayList<Blob>()
    for (s in args) {
        result.add(Blob.fromUtf8(s))
    }
    collectArray(result.iterator())
}

/// 从 Array<RESPValue> 中提取字符串数组（每个元素应为 BulkString）
public func extractStringArray(items: Array<RESPValue>): Array<String> {
    let result = ArrayList<String>()
    for (item in items) {
        match (item) {
            case RESPValue.BulkString(Some(blob)) =>
                result.add(blob.toUtf8())
            case RESPValue.BulkString(None) => ()
            case RESPValue.SimpleString(s) => result.add(s)
            case _ => ()
        }
    }
    collectArray(result.iterator())
}

/// 从 Array<RESPValue> 中提取 Blob 数组
public func extractBlobArray(items: Array<RESPValue>): Array<Blob> {
    let result = ArrayList<Blob>()
    for (item in items) {
        match (item) {
            case RESPValue.BulkString(Some(blob)) => result.add(blob)
            case RESPValue.BulkString(None) => ()
            case RESPValue.SimpleString(s) => result.add(Blob.fromUtf8(s))
            case _ => ()
        }
    }
    collectArray(result.iterator())
}
