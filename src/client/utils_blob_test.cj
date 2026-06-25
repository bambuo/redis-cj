package redis.client

/// Blob 类型单元测试
@Test
class BlobTests {
    /// 从 UTF-8 字符串构造
    @TestCase
    func fromUtf8Construct() {
        let b = Blob.fromUtf8("Hello")
        @Expect(b.size, 5)
        @Expect(b.toUtf8(), "Hello")
    }

    /// 从 UTF-8 字符串构造（中文）
    @TestCase
    func fromUtf8Chinese() {
        let b = Blob.fromUtf8("你好")
        @Expect(b.size, 6)  // 每个汉字 3 字节
        @Expect(b.toUtf8(), "你好")
    }

    /// 从原始字节构造
    @TestCase
    func fromBytesConstruct() {
        let bytes: Array<Byte> = [0x00, 0xFF, 0xFE, 0x7F]
        let b = Blob.fromBytes(bytes)
        @Expect(b.size, 4)
        let result = b.toBytes()
        @Expect(result[0], 0x00u8)
        @Expect(result[1], 0xFFu8)
        @Expect(result[2], 0xFEu8)
        @Expect(result[3], 0x7Fu8)
    }

    /// 空 Blob
    @TestCase
    func emptyBlob() {
        let b = Blob.empty()
        @Expect(b.size, 0)
        @Expect(b.isEmpty(), true)
    }

    /// 二进制数据安全显示（非法 UTF-8 显示十六进制）
    @TestCase
    func displayBinaryData() {
        let bytes: Array<Byte> = [0x00, 0xFF]
        let b = Blob.fromBytes(bytes)
        let display = b.toDisplay()
        // 非法 UTF-8 应显示十六进制
        @Expect(display.contains("00"), true)
        @Expect(display.contains("ff"), true)
    }

    /// 合法 UTF-8 显示原文
    @TestCase
    func displayUtf8Data() {
        let b = Blob.fromUtf8("Hello")
        @Expect(b.toDisplay(), "Hello")
    }

    /// 十六进制编码
    @TestCase
    func hexEncoding() {
        let bytes: Array<Byte> = [0x48, 0x65, 0x6C, 0x6C, 0x6F]  // "Hello"
        let b = Blob.fromBytes(bytes)
        let hex = b.hex()
        @Expect(hex.contains("48"), true)
        @Expect(hex.contains("65"), true)
    }

    /// 二进制数据调用 toUtf8 应抛异常
    @TestCase
    func toUtf8OnBinaryData() {
        let bytes: Array<Byte> = [0x00, 0xFF, 0xFE]
        let b = Blob.fromBytes(bytes)
        @ExpectThrows[Exception](b.toUtf8())
    }

    /// isValidUtf8 检查
    @TestCase
    func isValidUtf8Check() {
        let valid = Blob.fromUtf8("Hello")
        @Expect(valid.isValidUtf8(), true)

        let bytes: Array<Byte> = [0xFF, 0xFE]
        let invalid = Blob.fromBytes(bytes)
        @Expect(invalid.isValidUtf8(), false)
    }

    /// 字节级相等比较
    @TestCase
    func equals() {
        let a = Blob.fromUtf8("Hello")
        let b = Blob.fromUtf8("Hello")
        let c = Blob.fromUtf8("World")
        @Expect(a.equals(b), true)
        @Expect(a.equals(c), false)
    }

    /// of 别名
    @TestCase
    func ofAlias() {
        let b = Blob.of("test")
        @Expect(b.toUtf8(), "test")
    }
}
