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
    public func setReadTimeout(_timeout: Option<Duration>): Unit {}
    public func setWriteTimeout(_timeout: Option<Duration>): Unit {}

    public func read(buf: Array<Byte>): Int64 {
        var count: Int64 = 0
        while (readPos < data.size && count < buf.size) {
            buf[count] = data[readPos]
            readPos++
            count++
        }
        count
    }

    public func write(_buf: Array<Byte>): Unit {}
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

    /// 编码 Double 前导零：0.5 → ",0.5\r\n"（非 ",.5\r\n"）
    @TestCase
    func encodeDoubleLeadingZero() {
        let val = RESPValue.Double(0.5)
        let encoded = RespEncoder.encodeValue(val)
        let str = String.fromUtf8(encoded)
        @Expect(str.startsWith(",0.5"), true)
        // 负小数同理
        let neg = RESPValue.Double(-0.5)
        let negStr = String.fromUtf8(RespEncoder.encodeValue(neg))
        @Expect(negStr.startsWith(",-0.5"), true)
    }

    /// 编码 Double 特殊值：inf / -inf / nan
    @TestCase
    func encodeDoubleSpecialValues() {
        let infEncoded = String.fromUtf8(RespEncoder.encodeValue(RESPValue.Double(Float64.Inf)))
        @Expect(infEncoded, ",inf\r\n")

        let negInfEncoded = String.fromUtf8(RespEncoder.encodeValue(RESPValue.Double(-Float64.Inf)))
        @Expect(negInfEncoded, ",-inf\r\n")

        let nanEncoded = String.fromUtf8(RespEncoder.encodeValue(RESPValue.Double(Float64.NaN)))
        @Expect(nanEncoded, ",nan\r\n")
    }

    /// 编码 Double 不产生指数格式（RESP3 禁止）
    @TestCase
    func encodeDoubleNoExponential() {
        // 极小值
        let tiny = RESPValue.Double(0.000000000000001)
        let tinyStr = String.fromUtf8(RespEncoder.encodeValue(tiny))
        @Expect(tinyStr.contains("e") || tinyStr.contains("E"), false)

        // 极大值
        let huge = RESPValue.Double(1000000000000000.0)
        let hugeStr = String.fromUtf8(RespEncoder.encodeValue(huge))
        @Expect(hugeStr.contains("e") || hugeStr.contains("E"), false)
    }

    // -------- 校验测试 --------

    /// 编码 SimpleString 含 CR 应抛异常
    @TestCase
    func encodeSimpleStringWithCRThrows() {
        let val = RESPValue.SimpleString("hello\rworld")
        @ExpectThrows[ProtocolError](RespEncoder.encodeValue(val))
    }

    /// 编码 SimpleString 含 LF 应抛异常
    @TestCase
    func encodeSimpleStringWithLFThrows() {
        let val = RESPValue.SimpleString("hello\nworld")
        @ExpectThrows[ProtocolError](RespEncoder.encodeValue(val))
    }

    /// 编码 Error 含 CRLF 应抛异常
    @TestCase
    func encodeErrorWithCRLFThrows() {
        let val = RESPValue.Error("ERR bad\r\nthing")
        @ExpectThrows[ProtocolError](RespEncoder.encodeValue(val))
    }

    /// 编码 VerbatimString 编码标识不足 3 字节应抛异常
    @TestCase
    func encodeVerbatimStringInvalidEncodingThrows() {
        let val = RESPValue.VerbatimString("ab", Blob.fromUtf8("data"))
        @ExpectThrows[ProtocolError](RespEncoder.encodeValue(val))
    }

    /// 编码 VerbatimString 编码标识超过 3 字节应抛异常
    @TestCase
    func encodeVerbatimStringEncodingTooLong() {
        let val = RESPValue.VerbatimString("text", Blob.fromUtf8("data"))
        @ExpectThrows[ProtocolError](RespEncoder.encodeValue(val))
    }

    /// 编码 Push 首元素非字符串应抛异常
    @TestCase
    func encodePushInvalidFirstElementThrows() {
        // 首元素为 Integer（应抛异常）
        let val = RESPValue.Push([
            RESPValue.Integer(1),
            RESPValue.SimpleString("hello"),
        ])
        @ExpectThrows[ProtocolError](RespEncoder.encodeValue(val))
    }

    /// 编码空 Push 应抛异常
    @TestCase
    func encodeEmptyPushThrows() {
        let val = RESPValue.Push([])
        @ExpectThrows[ProtocolError](RespEncoder.encodeValue(val))
    }

    // -------- 流式聚合编码 --------

    /// 编码流式数组
    @TestCase
    func encodeStreamedArray() {
        let val = RESPValue.StreamedArray([
            RESPValue.SimpleString("a"),
            RESPValue.SimpleString("b"),
        ])
        let encoded = String.fromUtf8(RespEncoder.encodeValue(val))
        @Expect(encoded.startsWith("*?\r\n"), true)
        @Expect(encoded.endsWith(".\r\n"), true)
        @Expect(encoded.contains("+a\r\n"), true)
        @Expect(encoded.contains("+b\r\n"), true)
    }

    /// 编码流式集合
    @TestCase
    func encodeStreamedSet() {
        let val = RESPValue.StreamedSet([
            RESPValue.SimpleString("x"),
            RESPValue.SimpleString("y"),
        ])
        let encoded = String.fromUtf8(RespEncoder.encodeValue(val))
        @Expect(encoded.startsWith("~?\r\n"), true)
        @Expect(encoded.endsWith(".\r\n"), true)
    }

    /// 编码流式映射
    @TestCase
    func encodeStreamedMap() {
        let val = RESPValue.StreamedMap([
            (RESPValue.SimpleString("key"), RESPValue.Integer(1)),
        ])
        let encoded = String.fromUtf8(RespEncoder.encodeValue(val))
        @Expect(encoded.startsWith("%?\r\n"), true)
        @Expect(encoded.endsWith(".\r\n"), true)
    }

    /// 编码常规 VerbatimString（正常情况）
    @TestCase
    func encodeVerbatimString() {
        let val = RESPValue.VerbatimString("txt", Blob.fromUtf8("Some string"))
        let encoded = RespEncoder.encodeValue(val)
        let expected = Blob.fromUtf8("=15\r\ntxt:Some string\r\n").toBytes()
        @Expect(encoded.size, expected.size)
        for (i in 0..encoded.size) {
            @Expect(encoded[i], expected[i])
        }
    }
}
