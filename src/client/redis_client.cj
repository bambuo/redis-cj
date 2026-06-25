package redis.client
import std.collection.*

/// Redis 客户端门面（Facade 模式）
///
/// 提供统一的 Redis 操作入口，隐藏底层连接池、协议协商、编解码等复杂细节。
/// 实现 Resource 接口，支持 try-with-resource 自动回收。
///
/// # 用法
/// ```cangjie
/// try (client = RedisClient("127.0.0.1", 6379u16)) {
///     client.set("key", Blob.fromUtf8("value"))
///     let val = client.get("key")
///     println(val.getOrThrow())
/// }
/// ```
public class RedisClient <: Resource {
    internal let connection: RedisConnection

    // ====================================================================
    // 构造
    // ====================================================================

    /// 创建到单台 Redis 服务器的连接
    ///
    /// @param host 服务器主机
    /// @param port 服务器端口
    /// @param autoHello 是否自动 HELLO 协商
    /// @param connectTimeout 连接超时
    public init(host: String, port: UInt16,
                autoHello!: Bool = true,
                connectTimeout!: Option<Duration> = None) {
        let transport = TcpTransport(host, port)
        this.connection = RedisConnection(
            transport,
            autoHello: autoHello,
            connectTimeout: connectTimeout
        )
        this.connection.connect()
    }

    /// 使用已有的连接池创建客户端
    public init(pool: ConnectionPool) {
        this.connection = pool.acquire()
    }

    /// 使用已有的连接创建客户端
    public init(connection: RedisConnection) {
        this.connection = connection
    }

    // ====================================================================
    // Resource 接口实现
    // ====================================================================

    /// 关闭客户端连接
    public func close(): Unit {
        if (!connection.isClosed()) {
            connection.close()
        }
    }

    /// 检查是否已关闭
    public func isClosed(): Bool {
        connection.isClosed()
    }

    // ====================================================================
    // 核心执行方法
    // ====================================================================

    /// 执行命令（低级 API）
    ///
    /// @param args 命令参数（Blob 数组）
    /// @return 解码后的 RESP 值
    public func execute(args: Array<Blob>): RESPValue {
        connection.execute(args)
    }

    /// 执行字符串命令（便捷方法）
    ///
    /// 自动将字符串参数转换为 Blob。
    ///
    /// @param args 字符串参数
    /// @return 解码后的 RESP 值
    public func executeString(args: Array<String>): RESPValue {
        let blobArgs = ArrayList<Blob>()
        for (s in args) {
            blobArgs.add(Blob.fromUtf8(s))
        }
        execute(collectArray(blobArgs.iterator()))
    }

    /// 批量执行命令（Pipeline）
    ///
    /// @param commands 多条命令
    /// @return 响应值数组
    public func executeBatch(commands: Array<Array<Blob>>): Array<RESPValue> {
        connection.executeBatch(commands)
    }

    // ====================================================================
    // 连接管理
    // ====================================================================

    /// 重新连接
    public func reconnect(): Unit {
        connection.reconnect()
    }

    /// 获取连接状态描述
    public func getState(): ConnectionState {
        connection.getState()
    }

    /// 获取协议版本
    public func getProtocolVersion(): Int64 {
        connection.getProtocolVersion()
    }
}
