package redis.client

/// 辅助函数：从 RESP 字符串创建解码器
private func decoderFromBytes(data: Array<Byte>): RespDecoder {
    let transport = MockTransport(data)
    RespDecoder(transport, maxBulkLen: 1024 * 1024, maxDepth: 10)
}

/// RESP 解码器单元测试
@Test
class DecoderTests {
    // -------- RESP2 --------

    /// 解码 Simple String
    @TestCase
    func decodeSimpleString() {
        let dec = decoderFromBytes(Blob.fromUtf8("+OK\r\n").toBytes())
        let val = dec.readValue()
        match (val) {
            case RESPValue.SimpleString(s) => @Expect(s, "OK")
            case _ => @Fail("期望 SimpleString，得到 ${val}")
        }
    }

    /// 解码 Error
    @TestCase
    func decodeError() {
        let dec = decoderFromBytes(Blob.fromUtf8("-ERR unknown command\r\n").toBytes())
        let val = dec.readValue()
        match (val) {
            case RESPValue.Error(s) => @Expect(s, "ERR unknown command")
            case _ => @Fail("期望 Error，得到 ${val}")
        }
    }

    /// 解码 Integer
    @TestCase
    func decodeInteger() {
        let dec = decoderFromBytes(Blob.fromUtf8(":42\r\n").toBytes())
        let val = dec.readValue()
        match (val) {
            case RESPValue.Integer(n) => @Expect(n, 42)
            case _ => @Fail("期望 Integer，得到 ${val}")
        }
    }

    /// 解码 Bulk String
    @TestCase
    func decodeBulkString() {
        let dec = decoderFromBytes(Blob.fromUtf8("$5\r\nhello\r\n").toBytes())
        let val = dec.readValue()
        match (val) {
            case RESPValue.BulkString(Some(blob)) =>
                @Expect(blob.toUtf8(), "hello")
            case _ => @Fail("期望 BulkString，得到 ${val}")
        }
    }

    /// 解码 Null Bulk String
    @TestCase
    func decodeNullBulkString() {
        let dec = decoderFromBytes(Blob.fromUtf8("$-1\r\n").toBytes())
        let val = dec.readValue()
        match (val) {
            case RESPValue.BulkString(None) => @Expect(true, true)
            case _ => @Fail("期望 BulkString(None)，得到 ${val}")
        }
    }

    /// 解码 Null Bulk String via Option
    @TestCase
    func decodeNullBulkStringOption() {
        let dec = decoderFromBytes(Blob.fromUtf8("$-1\r\n").toBytes())
        let val = dec.readValue()
        match (val) {
            case RESPValue.BulkString(None) => ()
            case _ => @Fail("期望 Null Bulk String")
        }
    }

    /// 解码 Array
    @TestCase
    func decodeArray() {
        let data = Blob.fromUtf8("*2\r\n$3\r\nfoo\r\n$3\r\nbar\r\n").toBytes()
        let dec = decoderFromBytes(data)
        let val = dec.readValue()
        match (val) {
            case RESPValue.Array(Some(items)) =>
                @Expect(items.size, 2)
                match (items[0]) {
                    case RESPValue.BulkString(Some(b)) => @Expect(b.toUtf8(), "foo")
                    case _ => @Fail("期望 BulkString")
                }
                match (items[1]) {
                    case RESPValue.BulkString(Some(b)) => @Expect(b.toUtf8(), "bar")
                    case _ => @Fail("期望 BulkString")
                }
            case _ => @Fail("期望 Array，得到 ${val}")
        }
    }

    /// 解码 Null Array
    @TestCase
    func decodeNullArray() {
        let dec = decoderFromBytes(Blob.fromUtf8("*-1\r\n").toBytes())
        let val = dec.readValue()
        match (val) {
            case RESPValue.Array(None) => ()
            case _ => @Fail("期望 Array(None)")
        }
    }

    /// 解码嵌套 Array
    @TestCase
    func decodeNestedArray() {
        let data = Blob.fromUtf8("*2\r\n*2\r\n:1\r\n:2\r\n*2\r\n+Hello\r\n-World\r\n").toBytes()
        let dec = decoderFromBytes(data)
        let val = dec.readValue()
        match (val) {
            case RESPValue.Array(Some(items)) =>
                @Expect(items.size, 2)
            case _ => @Fail("期望嵌套 Array")
        }
    }

    // -------- RESP3 --------

    /// 解码 Null (RESP3)
    @TestCase
    func decodeNull() {
        let dec = decoderFromBytes(Blob.fromUtf8("_\r\n").toBytes())
        let val = dec.readValue()
        match (val) {
            case RESPValue.Null => ()
            case _ => @Fail("期望 Null")
        }
    }

    /// 解码 Boolean true
    @TestCase
    func decodeBooleanTrue() {
        let dec = decoderFromBytes(Blob.fromUtf8("#t\r\n").toBytes())
        let val = dec.readValue()
        match (val) {
            case RESPValue.Boolean(b) => @Expect(b, true)
            case _ => @Fail("期望 Boolean(true)")
        }
    }

    /// 解码 Boolean false
    @TestCase
    func decodeBooleanFalse() {
        let dec = decoderFromBytes(Blob.fromUtf8("#f\r\n").toBytes())
        let val = dec.readValue()
        match (val) {
            case RESPValue.Boolean(b) => @Expect(b, false)
            case _ => @Fail("期望 Boolean(false)")
        }
    }

    /// 解码 Boolean 非法字节应抛异常
    @TestCase
    func decodeBooleanInvalid() {
        let dec = decoderFromBytes(Blob.fromUtf8("#x\r\n").toBytes())
        @ExpectThrows[ProtocolError](dec.readValue())
    }

    /// 解码 Double
    @TestCase
    func decodeDouble() {
        let dec = decoderFromBytes(Blob.fromUtf8(",3.14\r\n").toBytes())
        let val = dec.readValue()
        match (val) {
            case RESPValue.Double(f) => @Expect(f > 3.13 && f < 3.15, true)
            case _ => @Fail("期望 Double")
        }
    }

    /// 解码 +inf
    @TestCase
    func decodeDoubleInf() {
        let dec = decoderFromBytes(Blob.fromUtf8(",inf\r\n").toBytes())
        let val = dec.readValue()
        match (val) {
            case RESPValue.Double(f) => @Expect(f.isInf(), true)
            case _ => @Fail("期望 Double(inf)")
        }
    }

    /// 解码 -inf
    @TestCase
    func decodeDoubleNegInf() {
        let dec = decoderFromBytes(Blob.fromUtf8(",-inf\r\n").toBytes())
        let val = dec.readValue()
        match (val) {
            case RESPValue.Double(f) => @Expect(f < 0.0, true)
            case _ => @Fail("期望 Double(-inf)")
        }
    }

    /// 解码 +inf (带加号)
    @TestCase
    func decodeDoublePlusInf() {
        let dec = decoderFromBytes(Blob.fromUtf8(",+inf\r\n").toBytes())
        let val = dec.readValue()
        match (val) {
            case RESPValue.Double(f) => @Expect(f.isInf(), true)
            case _ => @Fail("期望 Double(+inf)")
        }
    }

    /// 解码 nan
    @TestCase
    func decodeDoubleNan() {
        let dec = decoderFromBytes(Blob.fromUtf8(",nan\r\n").toBytes())
        let val = dec.readValue()
        match (val) {
            case RESPValue.Double(f) => @Expect(f.isNaN(), true)
            case _ => @Fail("期望 Double(nan)")
        }
    }

    /// 解码 Big Number
    @TestCase
    func decodeBigNumber() {
        let dec = decoderFromBytes(Blob.fromUtf8("(3492890328409238509324850943850943825024385\r\n").toBytes())
        let val = dec.readValue()
        match (val) {
            case RESPValue.BigNumber(s) => @Expect(s.startsWith("34928903284"), true)
            case _ => @Fail("期望 BigNumber")
        }
    }

    /// 解码 Bulk Error
    @TestCase
    func decodeBulkError() {
        let dec = decoderFromBytes(Blob.fromUtf8("!21\r\nSYNTAX invalid syntax\r\n").toBytes())
        let val = dec.readValue()
        match (val) {
            case RESPValue.BulkError(blob) =>
                @Expect(blob.toUtf8(), "SYNTAX invalid syntax")
            case _ => @Fail("期望 BulkError")
        }
    }

    /// 解码 Verbatim String
    @TestCase
    func decodeVerbatimString() {
        let data = Blob.fromUtf8("=15\r\ntxt:Some string\r\n").toBytes()
        let dec = decoderFromBytes(data)
        let val = dec.readValue()
        match (val) {
            case RESPValue.VerbatimString(enc, blob) =>
                @Expect(enc, "txt")
                @Expect(blob.toUtf8(), "Some string")
            case _ => @Fail("期望 VerbatimString")
        }
    }

    // -------- 流式类型 --------

    /// 解码流式字符串 $?...;0\r\n
    @TestCase
    func decodeStreamedString() {
        let data = Blob.fromUtf8("$?\r\n;5\r\nHello\r\n;0\r\n").toBytes()
        let dec = decoderFromBytes(data)
        let val = dec.readValue()
        match (val) {
            case RESPValue.BulkString(Some(blob)) =>
                @Expect(blob.toUtf8(), "Hello")
            case RESPValue.StreamedString(blob) =>
                @Expect(blob.toUtf8(), "Hello")
            case _ => @Fail("期望 StreamedString")
        }
    }

    /// 解码 End 标记
    @TestCase
    func decodeEnd() {
        let dec = decoderFromBytes([0x2Eu8, 0x0Du8, 0x0Au8])  // .\r\n
        let val = dec.readValue()
        match (val) {
            case RESPValue.End => ()
            case _ => @Fail("期望 End")
        }
    }

    // -------- 健壮性 --------

    /// skipCRLF 验证失败应抛异常
    @TestCase
    func skipCRLFValidation() {
        let dec = decoderFromBytes(Blob.fromUtf8("+OK\n").toBytes())  // 缺少 \r
        @ExpectThrows[ProtocolError](dec.readValue())
    }

    /// 超大 Bulk String 应被拒绝
    @TestCase
    func maxBulkLenExceeded() {
        let transport = MockTransport(Blob.fromUtf8("$999999999\r\n").toBytes())
        let dec = RespDecoder(transport, maxBulkLen: 1024, maxDepth: 10)
        @ExpectThrows[ProtocolError](dec.readValue())
    }

    /// 多层嵌套应触发深度限制
    @TestCase
    func maxDepthExceeded() {
        // 构造一个深度 3 的嵌套数组
        let data = Blob.fromUtf8("*1\r\n*1\r\n*1\r\n:1\r\n").toBytes()
        let transport = MockTransport(data)
        let dec = RespDecoder(transport, maxBulkLen: 1024, maxDepth: 2)
        @ExpectThrows[ProtocolError](dec.readValue())
    }

    /// 空数据应抛异常
    @TestCase
    func emptyData() {
        let dec = decoderFromBytes(Array<Byte>())
        @ExpectThrows[ProtocolError](dec.readValue())
    }
}
