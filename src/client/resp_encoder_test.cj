package redis.client
import std.collection.*

/// Mock 传输层（用于测试解码器）
public class MockTransport <: Transport {
    private var data: ArrayList<Byte>
    private var readPos: Int64

    public init(data: Array<Byte>) {
        this.data = ArrayList<Byte>()
        for (b in data) { this.data.add(b) }
        this.readPos = 0
    }

    public func connect(): Unit {}
    public func close(): Unit {}
    public func isConnected(): Bool { true }
    public func remoteAddress(): String { "mock:0" }
    public func setReadTimeout(timeout: Option<Duration>): Unit {}
    public func setWriteTimeout(timeout: Option<Duration>): Unit {}

    public func read(buf: Array<Byte>): Int64 {
        var count: Int64 = 0
        while (readPos < data.size && count < buf.size) {
            buf[count] = data[readPos]
            readPos++
            count++
        }
        count
    }

    public func write(buf: Array<Byte>): Unit {}
}

/// RESP 编码器单元测试
@Test
class EncoderTests {
    /// 编码命令：SET key value
    @TestCase
    func encodeSetCommand() {
        let args: Array<Blob> = [
            Blob.fromUtf8("SET"),
            Blob.fromUtf8("mykey"),
            Blob.fromUtf8("myvalue"),
        ]
        let encoded = RespEncoder.encodeCommand(args)
        let expected: Array<Byte> = [
            0x2A, 0x33, 0x0D, 0x0A,  // *3\r\n
            0x24, 0x33, 0x0D, 0x0A,  // $3\r\n
            0x53, 0x45, 0x54, 0x0D, 0x0A,  // SET\r\n
            0x24, 0x35, 0x0D, 0x0A,  // $5\r\n
            0x6D, 0x79, 0x6B, 0x65, 0x79, 0x0D, 0x0A,  // mykey\r\n
            0x24, 0x37, 0x0D, 0x0A,  // $7\r\n
            0x6D, 0x79, 0x76, 0x61, 0x6C, 0x75, 0x65, 0x0D, 0x0A,  // myvalue\r\n
        ]
        @Expect(encoded.size, expected.size)
        for (i in 0..encoded.size) {
            @Expect(encoded[i], expected[i])
        }
    }

    /// 编码 GET 命令
    @TestCase
    func encodeGetCommand() {
        let args: Array<Blob> = [Blob.fromUtf8("GET"), Blob.fromUtf8("key")]
        let encoded = RespEncoder.encodeCommand(args)
        // 验证格式：*2\r\n$3\r\nGET\r\n$3\r\nkey\r\n
        @Expect(encoded[0], 0x2Au8)  // *
        @Expect(encoded[1], 0x32u8)  // 2
        @Expect(encoded[2], 0x0Du8)  // \r
        @Expect(encoded[3], 0x0Au8)  // \n
    }

    /// 编码 SimpleString
    @TestCase
    func encodeSimpleString() {
        let val = RESPValue.SimpleString("OK")
        let encoded = RespEncoder.encodeValue(val)
        let expected = Blob.fromUtf8("+OK\r\n").toBytes()
        @Expect(encoded.size, expected.size)
        for (i in 0..encoded.size) {
            @Expect(encoded[i], expected[i])
        }
    }

    /// 编码 Error
    @TestCase
    func encodeError() {
        let val = RESPValue.Error("ERR test")
        let encoded = RespEncoder.encodeValue(val)
        let expected = Blob.fromUtf8("-ERR test\r\n").toBytes()
        @Expect(encoded.size, expected.size)
        for (i in 0..encoded.size) {
            @Expect(encoded[i], expected[i])
        }
    }

    /// 编码 Integer
    @TestCase
    func encodeInteger() {
        let val = RESPValue.Integer(42)
        let encoded = RespEncoder.encodeValue(val)
        let expected = Blob.fromUtf8(":42\r\n").toBytes()
        @Expect(encoded.size, expected.size)
        for (i in 0..encoded.size) {
            @Expect(encoded[i], expected[i])
        }
    }

    /// 编码 Null Bulk String
    @TestCase
    func encodeNullBulkString() {
        let val = RESPValue.BulkString(None)
        let encoded = RespEncoder.encodeValue(val)
        let expected = Blob.fromUtf8("$-1\r\n").toBytes()
        @Expect(encoded.size, expected.size)
        for (i in 0..encoded.size) {
            @Expect(encoded[i], expected[i])
        }
    }

    /// 编码 Bulk String
    @TestCase
    func encodeBulkString() {
        let val = RESPValue.BulkString(Some(Blob.fromUtf8("hello")))
        let encoded = RespEncoder.encodeValue(val)
        let expected = Blob.fromUtf8("$5\r\nhello\r\n").toBytes()
        @Expect(encoded.size, expected.size)
        for (i in 0..encoded.size) {
            @Expect(encoded[i], expected[i])
        }
    }

    /// 编码 Null Array
    @TestCase
    func encodeNullArray() {
        let val = RESPValue.Array(None)
        let encoded = RespEncoder.encodeValue(val)
        let expected = Blob.fromUtf8("*-1\r\n").toBytes()
        @Expect(encoded.size, expected.size)
        for (i in 0..encoded.size) {
            @Expect(encoded[i], expected[i])
        }
    }

    /// 编码 Array with items
    @TestCase
    func encodeArray() {
        let val = RESPValue.Array(Some([
            RESPValue.BulkString(Some(Blob.fromUtf8("foo"))),
            RESPValue.BulkString(Some(Blob.fromUtf8("bar"))),
        ]))
        let encoded = RespEncoder.encodeValue(val)
        let expected = Blob.fromUtf8("*2\r\n$3\r\nfoo\r\n$3\r\nbar\r\n").toBytes()
        @Expect(encoded.size, expected.size)
        for (i in 0..encoded.size) {
            @Expect(encoded[i], expected[i])
        }
    }

    /// 编码 Null (RESP3)
    @TestCase
    func encodeNull() {
        let val = RESPValue.Null
        let encoded = RespEncoder.encodeValue(val)
        let expected = Blob.fromUtf8("_\r\n").toBytes()
        @Expect(encoded.size, expected.size)
        for (i in 0..encoded.size) {
            @Expect(encoded[i], expected[i])
        }
    }

    /// 编码 Boolean (RESP3)
    @TestCase
    func encodeBoolean() {
        let t = RespEncoder.encodeValue(RESPValue.Boolean(true))
        @Expect(t[0], 0x23u8)  // '#'
        @Expect(t[1], 0x74u8)  // 't'
        @Expect(t[2], 0x0Du8)  // '\r'
        @Expect(t[3], 0x0Au8)  // '\n'

        let f = RespEncoder.encodeValue(RESPValue.Boolean(false))
        @Expect(f[0], 0x23u8)  // '#'
        @Expect(f[1], 0x66u8)  // 'f'
    }

    /// 编码 End 标记
    @TestCase
    func encodeEnd() {
        let val = RESPValue.End
        let encoded = RespEncoder.encodeValue(val)
        @Expect(encoded.size, 3)
        @Expect(encoded[0], 0x2Eu8)  // '.'
        @Expect(encoded[1], 0x0Du8)  // '\r'
        @Expect(encoded[2], 0x0Au8)  // '\n'
    }

    /// 编码 Double (RESP3)
    @TestCase
    func encodeDouble() {
        let val = RESPValue.Double(3.14)
        let encoded = RespEncoder.encodeValue(val)
        let str = String.fromUtf8(encoded)
        @Expect(str.startsWith(","), true)
        @Expect(str.endsWith("\r\n"), true)
        @Expect(str.contains("3.14"), true)
    }
}
