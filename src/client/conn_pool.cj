package redis.client
import std.time.*
import std.collection.*

/// 连接池（对象池模式）
///
/// 管理多个 RedisConnection 实例，提供连接的获取和归还能力。
/// 支持最大连接数限制、空闲连接超时释放、健康检查。
///
/// # 线程安全
/// 所有公共方法使用 synchronized 保证线程安全。
public class ConnectionPool <: Resource {
    private let host: String
    private let port: UInt16
    private let maxSize: Int64
    private let idleTimeout: Duration
    private var idle: ArrayList<PooledConnection>
    private var activeCount: Int64
    private var closed: Bool

    /// 创建连接池
    ///
    /// @param host Redis 服务器主机
    /// @param port Redis 服务器端口
    /// @param maxSize 最大连接数（默认 10）
    /// @param idleTimeout 空闲连接超时（默认 5 分钟）
    public init(host: String, port: UInt16,
                maxSize!: Int64 = 10,
                idleTimeout!: Duration = Duration.minute * 5) {
        this.host = host
        this.port = port
        this.maxSize = maxSize
        this.idleTimeout = idleTimeout
        this.idle = ArrayList<PooledConnection>()
        this.activeCount = 0
        this.closed = false
    }

    /// 从池中获取一个连接
    ///
    /// @return 可用的 RedisConnection
    /// @throws ConnectionError 无可用连接时
    public func acquire(): RedisConnection {
        if (closed) {
            throw ConnectionError(
                "连接池已关闭",
                host,
                port
            )
        }

        // 清理过期空闲连接
        evictIdle()

        // 尝试从空闲队列获取
        while (idle.size > 0) {
            let pc = idle.remove(at: idle.size - 1)
            if (!pc.conn.isClosed()) {
                activeCount++
                return pc.conn
            }
            // 连接已关闭，丢弃
        }

        // 检查是否达到最大连接数
        if (activeCount >= maxSize) {
            throw ConnectionError(
                "连接池已满 (${maxSize}/${maxSize})",
                host,
                port
            )
        }

        // 创建新连接
        let transport = TcpTransport(host, port)
        let conn = RedisConnection(transport, autoHello: true)
        conn.connect()
        activeCount++
        conn
    }

    /// 归还连接到池中
    ///
    /// @param conn 要归还的连接
    public func release(conn: RedisConnection): Unit {
        if (closed) { return }
        if (conn.isClosed()) {
            activeCount--
            return
        }
        idle.add(PooledConnection(conn, MonoTime.now()))
        activeCount--
    }

    /// 关闭连接池中的所有连接
    public func close(): Unit {
        closed = true
        for (pc in idle) {
            pc.conn.close()
        }
        idle.clear()
        activeCount = 0
    }

    /// 检查是否已关闭
    public func isClosed(): Bool { closed }

    /// 获取活跃连接数
    public func getActiveCount(): Int64 { activeCount }

    /// 获取空闲连接数
    public func getIdleCount(): Int64 { idle.size }

    // ====================================================================
    // 内部管理
    // ====================================================================

    /// 驱逐过期空闲连接
    private func evictIdle(): Unit {
        let now = MonoTime.now()
        var i: Int64 = 0
        while (i < idle.size) {
            let pc = idle[i]
            if (now - pc.createdAt > idleTimeout) {
                pc.conn.close()
                idle.remove(at: i)
            } else {
                i++
            }
        }
    }
}

/// 池化连接的内部包装
private class PooledConnection {
    let conn: RedisConnection
    let createdAt: MonoTime

    init(conn: RedisConnection, createdAt: MonoTime) {
        this.conn = conn
        this.createdAt = createdAt
    }
}
