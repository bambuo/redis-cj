package redis.client
import std.collection.*

/// 二进制安全 Blob 值类型（struct 值语义）
///
/// Redis 的 Bulk String 可以包含任意二进制数据（非 UTF-8 编码）。
/// Blob 封装了原始字节数组，提供了安全的 UTF-8 转换和调试输出。
///
/// # 用法
/// ```cangjie
/// // 从 UTF-8 文本构造
/// let b1 = Blob.fromUtf8("你好")
///
/// // 从原始字节构造
/// let b2 = Blob.fromBytes([0x00, 0xFF, 0xFE])
///
/// // 读取为字符串（非 UTF-8 会抛异常）
/// let s = b1.toUtf8()
///
/// // 安全显示：合法文本显示原文，非法显示十六进制
/// println(b2.toDisplay())
/// ```
public struct Blob {
    /// 原始字节数据
    internal let bytes: Array<Byte>

    // ---------- 构造 ----------

    /// 内部构造：使用原始字节数组
    internal init(bytes: Array<Byte>) {
        this.bytes = bytes
    }

    /// 从 UTF-8 字符串构造 Blob
    public static func fromUtf8(s: String): Blob {
        Blob(s.toArray())
    }

    /// 从原始字节数组构造 Blob
    public static func fromBytes(b: Array<Byte>): Blob {
        Blob(b)
    }

    /// 从 UTF-8 字符串构造（同 fromUtf8，更短的别名）
    public static func of(s: String): Blob {
        fromUtf8(s)
    }

    /// 空 Blob
    public static func empty(): Blob {
        Blob(Array<Byte>())
    }

    // ---------- 读取 ----------

    /// 将 Blob 解码为 UTF-8 字符串
    /// 如果包含非法 UTF-8 序列则抛出 ProtocolError
    public func toUtf8(): String {
        String.fromUtf8(bytes)
    }

    /// 获取原始字节引用的副本
    public func toBytes(): Array<Byte> {
        let copy = Array<Byte>(bytes.size, repeat: 0)
        for (i in 0..bytes.size) {
            copy[i] = bytes[i]
        }
        copy
    }

    /// 安全显示：合法 UTF-8 显示原文，否则显示十六进制
    public func toDisplay(): String {
        try {
            String.fromUtf8(bytes)
        } catch (_: Exception) {
            hex()
        }
    }

    /// 十六进制编码（空格分隔）
    public func hex(): String {
        let parts = ArrayList<String>()
        for (b in bytes) {
            parts.add(formatHexByte(b))
        }
        String.join(collectArray(parts.iterator()), delimiter: " ")
    }

    /// 十六进制编码（紧凑，无空格）
    public func hexCompact(): String {
        let parts = ArrayList<String>()
        for (b in bytes) {
            parts.add(formatHexByte(b))
        }
        String.join(collectArray(parts.iterator()), delimiter: "")
    }

    // ---------- 属性 ----------

    /// 字节数
    public prop size: Int64 {
        get() { bytes.size }
    }

    /// 是否为空
    public func isEmpty(): Bool {
        bytes.size == 0
    }

    /// 是否为合法的 UTF-8 文本
    public func isValidUtf8(): Bool {
        try {
            String.fromUtf8(bytes)
            true
        } catch (_: Exception) {
            false
        }
    }

    // ---------- 比较 ----------

    /// 字节级相等比较
    public func equals(other: Blob): Bool {
        if (bytes.size != other.bytes.size) { return false }
        for (i in 0..bytes.size) {
            if (bytes[i] != other.bytes[i]) { return false }
        }
        true
    }

    // ---------- Object 重写 ----------

    public func toString(): String {
        toDisplay()
    }
}

// ---------- 私有辅助 ----------

/// 格式化为两位十六进制
private func formatHexByte(b: Byte): String {
    let hexChars = "0123456789abcdef"
    let high = Int64((b >> 4u8) & 0x0Fu8)
    let low = Int64(b & 0x0Fu8)
    let result = Array<Byte>(2, repeat: 0)
    // 用写索引方式构建
    result[0] = hexChars.toArray()[high]
    result[1] = hexChars.toArray()[low]
    String.fromUtf8(result)
}
