package redis.client
import std.net.*
import stdx.net.tls.*

/// TLS 加密传输层实现（Strategy 模式）
///
/// 在 TCP 连接之上建立 TLS 加密通道，支持 TLS 1.2/1.3。
/// 基于仓颉扩展标准库 stdx.net.tls，底层依赖 OpenSSL 3。
///
/// # 用法
/// ```cangjie
/// let config = TlsClientConfig()
/// config.verifyMode = CertificateVerifyMode.Default  // 生产环境：系统 CA 验证
/// let transport = TlsTransport("redis.example.com", 6380, tlsConfig: config)
/// let conn = RedisConnection(transport)
/// let client = RedisClient(conn)
/// ```
///
/// # 证书验证
/// - 默认使用系统 CA 验证（CertificateVerifyMode.Default）
/// - 测试环境可设置 `TrustAll` 跳过验证
/// - 自签名证书使用 `CustomCA(certs)` 指定自定义 CA
public class TlsTransport <: Transport {
    private let host: String
    private let port: UInt16
    private var tlsSocket: Option<TlsSocket>
    private var tcpSocket: Option<TcpSocket>
    private var connectTimeout: Option<Duration>
    private let tlsConfig: TlsClientConfig

    /// 创建 TLS 传输层
    ///
    /// @param host Redis 服务器主机名
    /// @param port Redis TLS 端口（通常为 6380）
    /// @param tlsConfig TLS 客户端配置（默认使用系统 CA 验证）
    public init(host: String, port: UInt16,
                tlsConfig!: TlsClientConfig = TlsClientConfig()) {
        this.host = host
        this.port = port
        this.tlsSocket = None
        this.tcpSocket = None
        this.connectTimeout = None
        this.tlsConfig = tlsConfig
    }

    /// 设置连接超时
    public func setConnectTimeout(timeout: Option<Duration>): Unit {
        connectTimeout = timeout
    }

    /// 建立 TLS 加密连接
    ///
    /// 先建立 TCP 连接，再执行 TLS 握手。
    /// @throws ConnectionError 连接或 TLS 握手失败时
    public func connect(): Unit {
        if (isConnected()) { return }

        try {
            // 1. 建立 TCP 连接
            let s = TcpSocket(host, port)
            match (connectTimeout) {
                case Some(t) => s.connect(timeout: t)
                case None => s.connect()
            }
            tcpSocket = Some(s)

            // 2. TLS 握手
            let tls = TlsSocket.client(s, clientConfig: tlsConfig)
            tls.handshake()
            tlsSocket = Some(tls)
        } catch (e: Exception) {
            // 握手失败时清理 TCP 连接
            match (tcpSocket) {
                case Some(s) =>
                    try { s.close() } catch (_) { () }
                    tcpSocket = None
                case None => ()
            }
            throw ConnectionError("TLS 连接失败: ${e.message}", host, port)
        }
    }

    /// 关闭 TLS 连接（先关闭 TLS 层，再关闭 TCP 层）
    public func close(): Unit {
        match (tlsSocket) {
            case Some(tls) =>
                if (!tls.isClosed()) {
                    tls.close()
                }
                tlsSocket = None
            case None => ()
        }
        match (tcpSocket) {
            case Some(s) =>
                if (!s.isClosed()) {
                    s.close()
                }
                tcpSocket = None
            case None => ()
        }
    }

    public func isConnected(): Bool {
        match (tlsSocket) {
            case Some(tls) => !tls.isClosed()
            case None => false
        }
    }

    /// 从 TLS 加密通道读取数据
    /// @param buf 接收缓冲区
    /// @return 实际读取字节数
    public func read(buf: Array<Byte>): Int64 {
        match (tlsSocket) {
            case Some(tls) =>
                try {
                    tls.read(buf)
                } catch (e: SocketTimeoutException) {
                    throw TimeoutError(host, port, 0)
                } catch (e: Exception) {
                    throw ConnectionError("TLS 读取失败: ${e.message}", host, port)
                }
            case None =>
                throw ConnectionError("未连接", host, port)
        }
    }

    /// 向 TLS 加密通道写入数据
    /// @param buf 待发送数据
    public func write(buf: Array<Byte>): Unit {
        match (tlsSocket) {
            case Some(tls) =>
                try {
                    tls.write(buf)
                } catch (e: Exception) {
                    throw ConnectionError("TLS 写入失败: ${e.message}", host, port)
                }
            case None =>
                throw ConnectionError("未连接", host, port)
        }
    }

    /// 设置读超时
    public func setReadTimeout(timeout: Option<Duration>): Unit {
        match (tlsSocket) {
            case Some(tls) => tls.readTimeout = timeout
            case None => ()
        }
    }

    /// 设置写超时
    public func setWriteTimeout(timeout: Option<Duration>): Unit {
        match (tlsSocket) {
            case Some(tls) => tls.writeTimeout = timeout
            case None => ()
        }
    }

    public func remoteAddress(): String {
        "${host}:${port}"
    }
}
