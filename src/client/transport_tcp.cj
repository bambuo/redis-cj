package redis.client
import std.net.*
import std.time.*

/// TCP 传输层实现
///
/// 包装了仓颉标准库的 TcpSocket，提供 Transport 接口。
/// 支持连接超时、读写超时配置。
public class TcpTransport <: Transport {
    private let host: String
    private let port: UInt16
    private var socket: Option<TcpSocket>
    private var connectTimeout: Option<Duration>

    public init(host: String, port: UInt16) {
        this.host = host
        this.port = port
        this.socket = None
        this.connectTimeout = None
    }

    /// 设置连接超时
    public func setConnectTimeout(timeout: Option<Duration>): Unit {
        connectTimeout = timeout
    }

    /// 建立 TCP 连接
    /// @throws ConnectionError 连接失败时
    public func connect(): Unit {
        if (isConnected()) { return }
        try {
            let s = TcpSocket(host, port)
            match (connectTimeout) {
                case Some(t) => s.connect(timeout: t)
                case None => s.connect()
            }
            this.socket = Some(s)
        } catch (e: Exception) {
            throw ConnectionError("TCP 连接失败: ${e.message}", host, port)
        }
    }

    public func close(): Unit {
        match (socket) {
            case Some(s) =>
                if (!s.isClosed()) { s.close() }
                socket = None
            case None => ()
        }
    }

    public func isConnected(): Bool {
        match (socket) {
            case Some(s) => !s.isClosed()
            case None => false
        }
    }

    public func read(buf: Array<Byte>): Int64 {
        match (socket) {
            case Some(s) =>
                try {
                    s.read(buf)
                } catch (e: SocketTimeoutException) {
                    throw TimeoutError(host, port, 0)
                } catch (e: Exception) {
                    throw ConnectionError("读取失败: ${e.message}", host, port)
                }
            case None =>
                throw ConnectionError("未连接", host, port)
        }
    }

    public func write(buf: Array<Byte>): Unit {
        match (socket) {
            case Some(s) =>
                try {
                    s.write(buf)
                } catch (e: Exception) {
                    throw ConnectionError("写入失败: ${e.message}", host, port)
                }
            case None =>
                throw ConnectionError("未连接", host, port)
        }
    }

    public func setReadTimeout(timeout: Option<Duration>): Unit {
        match (socket) {
            case Some(s) => s.readTimeout = timeout
            case None => ()
        }
    }

    public func setWriteTimeout(timeout: Option<Duration>): Unit {
        match (socket) {
            case Some(s) => s.writeTimeout = timeout
            case None => ()
        }
    }

    public func remoteAddress(): String {
        "${host}:${port}"
    }
}
