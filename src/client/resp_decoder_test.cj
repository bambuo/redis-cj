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

    /// Double 指数格式应抛异常
    @TestCase
    func decodeDoubleExponentialThrows() {
        let dec = decoderFromBytes(Blob.fromUtf8(",1e3\r\n").toBytes())
        @ExpectThrows[ProtocolError](dec.readValue())
    }

    /// Double 小数点前缺少数字应抛异常
    @TestCase
    func decodeDoubleMissingLeadingZeroThrows() {
        let dec = decoderFromBytes(Blob.fromUtf8(",.5\r\n").toBytes())
        @ExpectThrows[ProtocolError](dec.readValue())
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

    /// Big Number 含非数字字符应抛异常
    @TestCase
    func decodeBigNumberInvalidThrows() {
        let dec = decoderFromBytes(Blob.fromUtf8("(12.3\r\n").toBytes())
        @ExpectThrows[ProtocolError](dec.readValue())
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

    /// Verbatim String 缺少 ':' 分隔符应抛异常
    @TestCase
    func decodeVerbatimStringMissingColonThrows() {
        let data = Blob.fromUtf8("=5\r\ntxtx\r\n").toBytes()
        let dec = decoderFromBytes(data)
        @ExpectThrows[ProtocolError](dec.readValue())
    }

    /// Verbatim String 编码标识含非 ASCII 字节应抛异常
    @TestCase
    func decodeVerbatimStringNonAsciiEncodingThrows() {
        let data: Array<Byte> = [
            0x3D, 0x34, 0x0D, 0x0A,  // =4\r\n
            0xE4, 0xB8, 0xAD, 0x3A,  // 非 ASCII 编码标识 + ':'
            0x0D, 0x0A,
        ]
        let dec = decoderFromBytes(data)
        @ExpectThrows[ProtocolError](dec.readValue())
    }

    /// Verbatim String 编码标识含控制字符应抛异常
    @TestCase
    func decodeVerbatimStringControlEncodingThrows() {
        let data: Array<Byte> = [
            0x3D, 0x34, 0x0D, 0x0A,  // =4\r\n
            0x74, 0x0A, 0x74, 0x3A,  // t\nt:
            0x0D, 0x0A,
        ]
        let dec = decoderFromBytes(data)
        @ExpectThrows[ProtocolError](dec.readValue())
    }

    /// 顶层 Attribute 存入侧通道并返回主响应
    @TestCase
    func decodeTopLevelAttributeSideChannel() {
        let data = Blob.fromUtf8("|1\r\n+ttl\r\n:3600\r\n+OK\r\n").toBytes()
        let dec = decoderFromBytes(data)
        let val = dec.readValue()
        match (val) {
            case RESPValue.SimpleString(s) => @Expect(s, "OK")
            case _ => @Fail("期望主响应 SimpleString")
        }
        match (dec.getAttributes()) {
            case Some(attrs) => @Expect(attrs.size, 1)
            case None => @Fail("期望 Attribute 侧通道")
        }
    }

    /// 嵌套 Attribute 应跟随其增强的子响应
    @TestCase
    func decodeNestedAttributePreserved() {
        let data = Blob.fromUtf8("*1\r\n|1\r\n+ttl\r\n:3600\r\n:3\r\n").toBytes()
        let dec = decoderFromBytes(data)
        let val = dec.readValue()
        match (val) {
            case RESPValue.Array(Some(items)) =>
                match (items[0]) {
                    case RESPValue.Attributed(value, attrs) =>
                        @Expect(attrs.size, 1)
                        match (value) {
                            case RESPValue.Integer(n) => @Expect(n, 3)
                            case _ => @Fail("期望被增强的 Integer")
                        }
                    case _ => @Fail("期望嵌套 Attributed")
                }
            case _ => @Fail("期望 Array")
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

    /// 顶层 End 标记应抛异常
    @TestCase
    func decodeTopLevelEndThrows() {
        let dec = decoderFromBytes([0x2Eu8, 0x0Du8, 0x0Au8])  // .\r\n
        @ExpectThrows[ProtocolError](dec.readValue())
    }

    /// 固定 Array 内 End 标记应抛异常
    @TestCase
    func decodeFixedArrayEndThrows() {
        let dec = decoderFromBytes(Blob.fromUtf8("*1\r\n.\r\n").toBytes())
        @ExpectThrows[ProtocolError](dec.readValue())
    }

    /// 固定 Map 内 End 标记应抛异常
    @TestCase
    func decodeFixedMapEndThrows() {
        let dec = decoderFromBytes(Blob.fromUtf8("%1\r\n.\r\n:1\r\n").toBytes())
        @ExpectThrows[ProtocolError](dec.readValue())
    }

    /// 固定 Set 内 End 标记应抛异常
    @TestCase
    func decodeFixedSetEndThrows() {
        let dec = decoderFromBytes(Blob.fromUtf8("~1\r\n.\r\n").toBytes())
        @ExpectThrows[ProtocolError](dec.readValue())
    }

    /// 解码流式数组 *?\r\n...\r\n.\r\n
    @TestCase
    func decodeStreamedArray() {
        let data = Blob.fromUtf8("*?\r\n:1\r\n:2\r\n.\r\n").toBytes()
        let dec = decoderFromBytes(data)
        let val = dec.readValue()
        match (val) {
            case RESPValue.Array(Some(items)) =>
                @Expect(items.size, 2)
                match (items[0]) {
                    case RESPValue.Integer(n) => @Expect(n, 1)
                    case _ => @Fail("期望 Integer(1)")
                }
                match (items[1]) {
                    case RESPValue.Integer(n) => @Expect(n, 2)
                    case _ => @Fail("期望 Integer(2)")
                }
            case _ => @Fail("期望流式数组 → Array")
        }
    }

    /// 解码流式集合 ~?\r\n...\r\n.\r\n
    @TestCase
    func decodeStreamedSet() {
        let data = Blob.fromUtf8("~?\r\n+a\r\n+b\r\n.\r\n").toBytes()
        let dec = decoderFromBytes(data)
        let val = dec.readValue()
        match (val) {
            case RESPValue.Set(items) =>
                @Expect(items.size, 2)
            case _ => @Fail("期望流式集合 → Set")
        }
    }

    /// 解码流式映射 %?\r\n...\r\n.\r\n
    @TestCase
    func decodeStreamedMap() {
        let data = Blob.fromUtf8("%?\r\n+k1\r\n:1\r\n+k2\r\n:2\r\n.\r\n").toBytes()
        let dec = decoderFromBytes(data)
        let val = dec.readValue()
        match (val) {
            case RESPValue.Map(pairs) =>
                @Expect(pairs.size, 2)
            case _ => @Fail("期望流式映射 → Map")
        }
    }

    /// 解码流式映射元素非偶数应抛异常
    @TestCase
    func decodeStreamedMapOddElements() {
        let data = Blob.fromUtf8("%?\r\n+k1\r\n:1\r\n+k2\r\n.\r\n").toBytes()
        let dec = decoderFromBytes(data)
        @ExpectThrows[ProtocolError](dec.readValue())
    }

    /// Map 负元素数量应抛异常
    @TestCase
    func decodeNegativeMapCountThrows() {
        let dec = decoderFromBytes(Blob.fromUtf8("%-1\r\n").toBytes())
        @ExpectThrows[ProtocolError](dec.readValue())
    }

    /// Push 首元素必须为字符串
    @TestCase
    func decodePushFirstElementMustBeString() {
        let dec = decoderFromBytes(Blob.fromUtf8(">1\r\n:1\r\n").toBytes())
        @ExpectThrows[ProtocolError](dec.readValueIncludingPush())
    }

    /// Push 只能作为顶层带外数据出现
    @TestCase
    func decodeNestedPushThrows() {
        let dec = decoderFromBytes(Blob.fromUtf8("*1\r\n>3\r\n+message\r\n+ch\r\n+hello\r\n").toBytes())
        @ExpectThrows[ProtocolError](dec.readValue())
    }

    @TestCase
    func readValueSkipsPush() {
        let data = Blob.fromUtf8(">3\r\n+message\r\n+ch\r\n+hello\r\n+OK\r\n").toBytes()
        let dec = decoderFromBytes(data)
        let val = dec.readValue()
        match (val) {
            case RESPValue.SimpleString(s) => @Expect(s, "OK")
            case _ => @Fail("普通 readValue 应跳过 Push 并返回后续响应")
        }
    }

    @TestCase
    func readValueIncludingPushReturnsPush() {
        let data = Blob.fromUtf8(">3\r\n+message\r\n+ch\r\n+hello\r\n").toBytes()
        let dec = decoderFromBytes(data)
        let val = dec.readValueIncludingPush()
        match (val) {
            case RESPValue.Push(items) =>
                @Expect(items.size, 3)
                match (asString(items[0])) {
                    case Some(s) => @Expect(s, "message")
                    case None => @Fail("Push 类型应为字符串")
                }
            case _ => @Fail("期望 Push")
        }
    }

    // -------- 健壮性 --------

    /// \r 后非 \n 应抛异常（SimpleString）
    @TestCase
    func readLineEmbeddedCRThrows() {
        // +hello\rx\r\n → \r 后接 'x' 不是 \n
        let dec = decoderFromBytes(Blob.fromUtf8("+hello\rx\r\n").toBytes())
        @ExpectThrows[ProtocolError](dec.readValue())
    }

    /// 连续 \r\r\n 应抛异常（第二个 \r 后应为 \n）
    @TestCase
    func readLineDoubleCRThrows() {
        // +hello\r\r\n → 第一个 \r 后接第二个 \r
        let dec = decoderFromBytes(Blob.fromUtf8("+hello\r\r\n").toBytes())
        @ExpectThrows[ProtocolError](dec.readValue())
    }

    /// collectRestOfLine 检测到无效 CRLF 应抛异常
    @TestCase
    func bulkStringCRNotFollowedByLFThrows() {
        // $3\rX\r\nHi\r\n → \r 后接 'X' 不是 \n
        let dec = decoderFromBytes(Blob.fromUtf8("$3\rX\r\nHi\r\n").toBytes())
        @ExpectThrows[ProtocolError](dec.readValue())
    }

    /// skipCRLF 验证失败应抛异常
    @TestCase
    func skipCRLFValidation() {
        let dec = decoderFromBytes(Blob.fromUtf8("+OK\n").toBytes())  // 缺少 \r
        @ExpectThrows[ProtocolError](dec.readValue())
    }

    /// SimpleString 行内裸 LF 应抛异常
    @TestCase
    func simpleStringBareLFThrows() {
        let dec = decoderFromBytes(Blob.fromUtf8("+hello\nworld\r\n").toBytes())
        @ExpectThrows[ProtocolError](dec.readValue())
    }

    /// Error 行内裸 LF 应抛异常
    @TestCase
    func errorBareLFThrows() {
        let dec = decoderFromBytes(Blob.fromUtf8("-ERR bad\nthing\r\n").toBytes())
        @ExpectThrows[ProtocolError](dec.readValue())
    }

    /// 超大 Bulk String 应被拒绝
    @TestCase
    func maxBulkLenExceeded() {
        let transport = MockTransport(Blob.fromUtf8("$999999999\r\n").toBytes())
        let dec = RespDecoder(transport, maxBulkLen: 1024, maxDepth: 10)
        @ExpectThrows[ProtocolError](dec.readValue())
    }

    /// 流式字符串单个分块超过最大长度应被拒绝
    @TestCase
    func streamedStringChunkExceedsMaxBulkLenThrows() {
        let transport = MockTransport(Blob.fromUtf8("$?\r\n;5\r\nHello\r\n;0\r\n").toBytes())
        let dec = RespDecoder(transport, maxBulkLen: 4, maxDepth: 10)
        @ExpectThrows[ProtocolError](dec.readValue())
    }

    /// 流式字符串累计长度超过最大长度应被拒绝
    @TestCase
    func streamedStringTotalExceedsMaxBulkLenThrows() {
        let transport = MockTransport(
            Blob.fromUtf8("$?\r\n;3\r\nHel\r\n;3\r\nlo!\r\n;0\r\n").toBytes()
        )
        let dec = RespDecoder(transport, maxBulkLen: 5, maxDepth: 10)
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
