package redis.client
import std.time.*

/// 传输层接口（策略模式）
///
/// 抽象了底层网络传输能力，支持 TCP、TLS（未来）等多种实现。
/// 所有方法可能抛出 ConnectionError。
public interface Transport {
    /// 建立连接到目标主机
    /// @throws ConnectionError 连接失败时
    func connect(): Unit

    /// 关闭连接
    func close(): Unit

    /// 是否已连接
    func isConnected(): Bool

    /// 从连接读取数据到缓冲区
    /// @param buf 接收数据的缓冲区
    /// @return 实际读取的字节数（0 = 连接关闭）
    /// @throws TimeoutError 超时时
    /// @throws ConnectionError 读取失败时
    func read(buf: Array<Byte>): Int64

    /// 向连接写入数据
    /// @param buf 待发送的数据
    /// @throws ConnectionError 写入失败时
    func write(buf: Array<Byte>): Unit

    /// 设置读超时
    /// @param timeout None 表示永不超时
    func setReadTimeout(timeout: Option<Duration>): Unit

    /// 设置写超时
    /// @param timeout None 表示永不超时
    func setWriteTimeout(timeout: Option<Duration>): Unit

    /// 获取远程地址字符串
    func remoteAddress(): String
}
