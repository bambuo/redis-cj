package redis.client
import std.time.*
import stdx.net.tls.*

/// TlsTransport 单元测试
///
/// 覆盖构造、属性、错误处理等可脱离真实 TLS 服务器验证的逻辑。
/// 实际 TLS 握手行为需配合 Redis TLS 服务器进行集成测试。
@Test
class TlsTransportTests {

    // ====================================================================
    // 构造与属性
    // ====================================================================

    /// 构造时正确保存 host / port
    @TestCase
    func constructHostPort() {
        let t = TlsTransport("redis.example.com", 6380u16)
        @Expect(t.remoteAddress(), "redis.example.com:6380")
    }

    /// 构造时正确保存 port（非默认端口）
    @TestCase
    func constructCustomPort() {
        let t = TlsTransport("10.0.0.1", 16380u16)
        @Expect(t.remoteAddress(), "10.0.0.1:16380")
    }

    /// remoteAddress 格式始终为 host:port
    @TestCase
    func remoteAddressFormat() {
        let t = TlsTransport("my-redis.local", 6380u16)
        let addr = t.remoteAddress()
        @Expect(addr.contains(":"), true)
        @Expect(addr.startsWith("my-redis.local"), true)
    }

    // ====================================================================
    // 连接状态
    // ====================================================================

    /// 未连接时 isConnected 返回 false
    @TestCase
    func isConnectedBeforeConnect() {
        let t = TlsTransport("127.0.0.1", 6380u16)
        @Expect(t.isConnected(), false)
    }

    /// 未连接时 read 抛出 ConnectionError
    @TestCase
    func readWhenNotConnected() {
        let t = TlsTransport("127.0.0.1", 6380u16)
        let buf = Array<Byte>(128, repeat: 0)
        @ExpectThrows[ConnectionError](t.read(buf))
    }

    /// 未连接时 write 抛出 ConnectionError
    @TestCase
    func writeWhenNotConnected() {
        let t = TlsTransport("127.0.0.1", 6380u16)
        let buf = Array<Byte>(4, repeat: 0)
        @ExpectThrows[ConnectionError](t.write(buf))
    }

    // ====================================================================
    // close 幂等性
    // ====================================================================

    /// 未连接时 close 不抛异常
    @TestCase
    func closeBeforeConnect() {
        let t = TlsTransport("127.0.0.1", 6380u16)
        t.close()  // 不应抛异常
        @Expect(t.isConnected(), false)
    }

    /// 重复 close 不抛异常
    @TestCase
    func closeMultipleTimes() {
        let t = TlsTransport("127.0.0.1", 6380u16)
        t.close()
        t.close()
        t.close()
        @Expect(t.isConnected(), false)
    }

    // ====================================================================
    // 超时配置
    // ====================================================================

    /// 设置连接超时
    @TestCase
    func setConnectTimeout() {
        let t = TlsTransport("127.0.0.1", 6380u16)
        t.setConnectTimeout(Some(Duration.second * 3))
        // 无异常即通过 — setConnectTimeout 本身不应抛异常
        @Expect(true, true)
    }

    /// 未连接时设置读超时不抛异常
    @TestCase
    func setReadTimeoutBeforeConnect() {
        let t = TlsTransport("127.0.0.1", 6380u16)
        t.setReadTimeout(Some(Duration.second * 5))
        @Expect(true, true)
    }

    /// 未连接时设置写超时不抛异常
    @TestCase
    func setWriteTimeoutBeforeConnect() {
        let t = TlsTransport("127.0.0.1", 6380u16)
        t.setWriteTimeout(Some(Duration.second * 5))
        @Expect(true, true)
    }

    /// 设置 None 超时（永不超时）
    @TestCase
    func setTimeoutNone() {
        let t = TlsTransport("127.0.0.1", 6380u16)
        t.setReadTimeout(None)
        t.setWriteTimeout(None)
        t.setConnectTimeout(None)
        @Expect(true, true)
    }

    // ====================================================================
    // 连接失败（无效地址）
    // ====================================================================

    /// 连接不可达地址抛 ConnectionError（含 host/port 信息）
    @TestCase
    func connectInvalidHost() {
        let t = TlsTransport("invalid.host.invalid", 6380u16)
        t.setConnectTimeout(Some(Duration.millisecond * 200))
        @ExpectThrows[ConnectionError](t.connect())
    }

    /// 连接失败后的 ConnectionError 包含 host/port 信息
    @TestCase
    func connectErrorContainsHost() {
        let t = TlsTransport("invalid.host.invalid", 6380u16)
        t.setConnectTimeout(Some(Duration.millisecond * 500))
        try {
            t.connect()
            @Expect(false, true) // 不应到达此处
        } catch (e: ConnectionError) {
            @Expect(e.host, "invalid.host.invalid")
            @Expect(e.port, 6380u16)
        }
    }

    // ====================================================================
    // TlsClientConfig 自定义
    // ====================================================================

    /// 传入默认 TlsClientConfig 构造不抛异常
    @TestCase
    func defaultTlsConfig() {
        let config = TlsClientConfig()
        let t = TlsTransport("127.0.0.1", 6380u16, tlsConfig: config)
        @Expect(t.remoteAddress(), "127.0.0.1:6380")
    }

    /// 省略 tlsConfig 参数使用默认值不抛异常
    @TestCase
    func omittedTlsConfig() {
        let t = TlsTransport("127.0.0.1", 6380u16)
        @Expect(t.isConnected(), false)
    }
}
