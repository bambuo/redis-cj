package redis.client

/// 错误类型层次单元测试
@Test
class ErrorTests {
    /// 基本 RedisError 构造
    @TestCase
    func redisError() {
        let e = RedisError("test error")
        @Expect(e.message.contains("test error"), true)
    }

    /// ConnectionError 包含主机和端口
    @TestCase
    func connectionError() {
        let e = ConnectionError("连接失败", "127.0.0.1", 6379u16)
        @Expect(e.host, "127.0.0.1")
        @Expect(e.port, 6379u16)
        @Expect(e.message.contains("127.0.0.1"), true)
        @Expect(e.message.contains("6379"), true)
    }

    /// TimeoutError 继承自 ConnectionError
    @TestCase
    func timeoutError() {
        let e = TimeoutError("127.0.0.1", 6379u16, 5000)
        @Expect(e.message.contains("5000"), true)
        // 确认类型层次
        let isConnErr = e is ConnectionError
        @Expect(isConnErr, true)
        let isRedisErr = e is RedisError
        @Expect(isRedisErr, true)
    }

    /// ProtocolError
    @TestCase
    func protocolError() {
        let e = ProtocolError("RESP 解析失败")
        @Expect(e.message.contains("RESP 解析失败"), true)
    }

    /// CommandError 从原始字符串解析前缀
    @TestCase
    func commandErrorFromRaw() {
        let e = CommandError("WRONGTYPE Operation against a key holding the wrong kind of value")
        @Expect(e.prefix, "WRONGTYPE")
        @Expect(e.rawMessage, "Operation against a key holding the wrong kind of value")
    }

    /// CommandError 直接构造
    @TestCase
    func commandErrorDirect() {
        let e = CommandError("ERR", "unknown command")
        @Expect(e.prefix, "ERR")
        @Expect(e.rawMessage, "unknown command")
    }

    /// 无空格的错误消息
    @TestCase
    func commandErrorNoSpace() {
        let e = CommandError("NOSCRIPT")
        @Expect(e.prefix, "NOSCRIPT")
        @Expect(e.rawMessage, "")
    }

    /// WrongTypeError 子类
    @TestCase
    func wrongTypeError() {
        let e = WrongTypeError("wrong kind of value")
        @Expect(e.prefix, "WRONGTYPE")
        let base: CommandError = e
        @Expect(base.prefix, "WRONGTYPE")
    }

    /// AuthError 子类
    @TestCase
    func authError() {
        let e = AuthError("invalid password")
        @Expect(e.prefix, "NOAUTH")
    }

    /// NoScriptError 子类
    @TestCase
    func noScriptError() {
        let e = NoScriptError("script not found")
        @Expect(e.prefix, "NOSCRIPT")
    }

    /// MovedError 解析槽位和地址
    @TestCase
    func movedError() {
        let e = MovedError("MOVED 1234 127.0.0.1:6380")
        @Expect(e.prefix, "MOVED")
        @Expect(e.slot, 1234)
        @Expect(e.targetHost, "127.0.0.1")
        @Expect(e.targetPort, 6380)
    }

    /// AskError 解析槽位和地址
    @TestCase
    func askError() {
        let e = AskError("ASK 5678 10.0.0.1:6379")
        @Expect(e.prefix, "ASK")
        @Expect(e.slot, 5678)
        @Expect(e.targetHost, "10.0.0.1")
        @Expect(e.targetPort, 6379)
    }

    /// createCommandError 工厂按前缀分发
    @TestCase
    func errorFactory() {
        let e1 = createCommandError("WRONGTYPE bad type")
        @Expect(e1 is WrongTypeError, true)

        let e2 = createCommandError("NOAUTH need auth")
        @Expect(e2 is AuthError, true)

        let e3 = createCommandError("MOVED 100 10.0.0.1:6379")
        @Expect(e3 is MovedError, true)

        let e4 = createCommandError("UNKNOWN some error")
        @Expect(e4 is CommandError, true)
        @Expect(e4.prefix, "UNKNOWN")
    }

    @TestCase
    func expectHelperUsesErrorFactory() {
        @ExpectThrows[MovedError](expectInt(RESPValue.Error("MOVED 100 10.0.0.1:6379"), "TEST"))
        @ExpectThrows[AskError](expectInt(RESPValue.Error("ASK 101 10.0.0.2:6380"), "TEST"))
    }

    @TestCase
    func expectDoubleAcceptsBulkString() {
        let v = expectDouble(RESPValue.BulkString(Some(Blob.fromUtf8("3.25"))), "FLOAT")
        @Expect(v > 3.24 && v < 3.26, true)
    }
}
