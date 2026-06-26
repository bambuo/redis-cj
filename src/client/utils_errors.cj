package redis.client
import std.convert.*

// ====================================================================
// Redis 错误类型层次（继承 + 多态）
// ====================================================================

/// Redis 基础异常。所有 Redis 相关异常的基类。
public open class RedisError <: Exception {
    /// 错误详情消息
    public open prop msg: String {
        get() { message }
    }

    /// 使用消息创建 Redis 错误
    public init(msg: String) {
        super(msg)
    }

    public open func toString(): String {
        "RedisError: ${message}"
    }
}

// ---------- 连接层错误 ----------

/// 连接错误：网络中断、连接失败等
public open class ConnectionError <: RedisError {
    /// 目标主机
    public let host: String
    /// 目标端口
    public let port: UInt16

    public init(msg: String, host: String, port: UInt16) {
        super("连接 [${host}:${port}] 失败: ${msg}")
        this.host = host
        this.port = port
    }

    public open func toString(): String {
        "ConnectionError: ${message}"
    }
}

/// 连接超时错误
public class TimeoutError <: ConnectionError {
    public init(host: String, port: UInt16, timeoutMs: Int64) {
        super("操作超时 (${timeoutMs}ms)", host, port)
    }

    public func toString(): String {
        "TimeoutError: ${message}"
    }
}

// ---------- 协议层错误 ----------

/// 协议错误：RESP 解析失败、协议版本不匹配等
public class ProtocolError <: RedisError {
    public init(msg: String) {
        super("协议错误: ${msg}")
    }

    public func toString(): String {
        "ProtocolError: ${message}"
    }
}

// ---------- 命令执行错误 ----------

/// 命令执行错误：由 Redis 服务器返回的 `-ERR` 类型响应
///
/// 根据 Redis 错误规范，错误消息以大写字母前缀开始（如 "WRONGTYPE"）。
/// 本类保留错误前缀以便精确处理。
public open class CommandError <: RedisError {
    /// 错误类型前缀，如 "ERR"、"WRONGTYPE"、"NOSCRIPT"
    public var prefix: String = ""
    /// Redis 返回的原始错误消息（不含前缀）
    public var rawMessage: String = ""

    /// 从 Redis 错误字符串解析创建
    public init(raw: String) {
        super("[${raw}] 命令错误")
        let (p, msg) = parseErrorPrefix(raw)
        this.prefix = p
        this.rawMessage = msg
    }

    /// 直接构造
    public init(prefix: String, msg: String) {
        super("[${prefix}] ${msg}")
        this.prefix = prefix
        this.rawMessage = msg
    }

    public open func toString(): String {
        "CommandError(${prefix}): ${rawMessage}"
    }
}

/// 类型错误（WRONGTYPE）
public class WrongTypeError <: CommandError {
    public init(msg: String) {
        super("WRONGTYPE", msg)
    }

    public func toString(): String {
        "WrongTypeError: ${rawMessage}"
    }
}

/// 认证错误（NOAUTH / AUTH）
public class AuthError <: CommandError {
    public init(msg: String) {
        super("NOAUTH", msg)
    }

    public func toString(): String {
        "AuthError: ${rawMessage}"
    }
}

/// 脚本不存在（NOSCRIPT）
public class NoScriptError <: CommandError {
    public init(msg: String) {
        super("NOSCRIPT", msg)
    }

    public func toString(): String {
        "NoScriptError: ${rawMessage}"
    }
}

/// 事务因 WATCH 冲突等原因被 Redis 放弃执行
public class TransactionAbortedError <: RedisError {
    public init() {
        super("事务未执行：EXEC 返回 null（通常是 WATCH 监视的键被修改）")
    }

    public func toString(): String {
        "TransactionAbortedError: ${message}"
    }
}

/// 集群 MOVED 重定向
public class MovedError <: CommandError {
    public var slot: Int64 = -1
    public var targetHost: String = ""
    public var targetPort: Int64 = -1

    public init(msg: String) {
        super("MOVED", msg)
        let parts = msg.split(" ")
        if (parts.size >= 3) {
            this.slot = Int64.parse(parts[1])
            let addr = parts[2].split(":")
            this.targetHost = addr[0]
            this.targetPort = Int64.parse(addr[1])
        }
    }

    public func toString(): String {
        "MovedError: 槽 ${slot} → ${targetHost}:${targetPort}"
    }
}

/// 集群 ASK 重定向
public class AskError <: CommandError {
    public var slot: Int64 = -1
    public var targetHost: String = ""
    public var targetPort: Int64 = -1

    public init(msg: String) {
        super("ASK", msg)
        let parts = msg.split(" ")
        if (parts.size >= 3) {
            this.slot = Int64.parse(parts[1])
            let addr = parts[2].split(":")
            this.targetHost = addr[0]
            this.targetPort = Int64.parse(addr[1])
        }
    }
}

// ---------- 工具函数 ----------

/// 错误前缀工厂：根据错误前缀创建对应的 CommandError 子类
public func createCommandError(raw: String): CommandError {
    let spaceIdx = raw.indexOf(" ")
    let prefix = match (spaceIdx) {
        case Some(i) => raw[0..i]
        case None => raw
    }
    let message = match (spaceIdx) {
        case Some(i) => if (i + 1 < raw.size) { raw[i + 1..] } else { "" }
        case None => ""
    }

    match (prefix) {
        case "WRONGTYPE" => WrongTypeError(message)
        case "NOAUTH" => AuthError(message)
        case "NOSCRIPT" => NoScriptError(message)
        case "MOVED" => MovedError(raw)
        case "ASK" => AskError(raw)
        case _ => CommandError(prefix, message)
    }
}

// ---------- 内部辅助 ----------

/// 解析 "PREFIX message" 格式的 Redis 错误字符串
private func parseErrorPrefix(raw: String): (String, String) {
    let spaceIdx = match (raw.indexOf(" ")) {
        case Some(i) => i
        case None => raw.size
    }
    let prefix = raw[0..spaceIdx]
    let message = if (spaceIdx < raw.size) {
        raw[spaceIdx + 1..]
    } else {
        ""
    }
    (prefix, message)
}
