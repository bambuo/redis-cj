package redis.client
import std.collection.*

/// RESP 编码器（纯函数设计）
///
/// 提供 RESP2/RESP3 协议的编码能力，无内部状态。
public class RespEncoder {
    // ====================================================================
    // 命令编码
    // ====================================================================

    /// 将命令参数编码为 RESP2 Array of Bulk Strings
    public static func encodeCommand(args: Array<Blob>): Array<Byte> {
        let buf = ArrayList<Byte>()
        append(buf, "*${args.size}\r\n")
        for (arg in args) {
            buf.add(0x24u8)  // '$'
            append(buf, "${arg.size}\r\n")
            appendBytes(buf, arg.bytes)
            append(buf, "\r\n")
        }
        collectArray(buf.iterator())
    }

    /// 将字符串命令编码为 RESP2 Array of Bulk Strings（便捷方法）
    public static func encodeStringCommand(args: Array<String>): Array<Byte> {
        let blobArgs = ArrayList<Blob>()
        for (s in args) {
            blobArgs.add(Blob.fromUtf8(s))
        }
        encodeCommand(collectArray(blobArgs.iterator()))
    }

    // ====================================================================
    // 单值编码
    // ====================================================================

    /// 将单个 RESPValue 编码为 RESP 线缆格式
    public static func encodeValue(val: RESPValue): Array<Byte> {
        let buf = ArrayList<Byte>()

        match (val) {
            case RESPValue.SimpleString(s) =>
                append(buf, "+${s}\r\n")

            case RESPValue.Error(s) =>
                append(buf, "-${s}\r\n")

            case RESPValue.Integer(n) =>
                append(buf, ":${n}\r\n")

            case RESPValue.BulkString(None) =>
                buf.add(0x24u8)  // '$'
                buf.add(0x2Du8)  // '-'
                buf.add(0x31u8)  // '1'
                append(buf, "\r\n")

            case RESPValue.BulkString(Some(blob)) =>
                append(buf, "$${blob.size}\r\n")
                appendBytes(buf, blob.bytes)
                append(buf, "\r\n")

            case RESPValue.Array(None) =>
                append(buf, "*-1\r\n")

            case RESPValue.Array(Some(items)) =>
                append(buf, "*${items.size}\r\n")
                for (item in items) {
                    appendBytes(buf, encodeValue(item))
                }

            case RESPValue.Null =>
                append(buf, "_\r\n")

            case RESPValue.Boolean(b) =>
                if (b) { append(buf, "#t\r\n") } else { append(buf, "#f\r\n") }

            case RESPValue.Double(f) =>
                let str = formatDouble(f)
                append(buf, ",${str}\r\n")

            case RESPValue.BigNumber(s) =>
                append(buf, "(${s}\r\n")

            case RESPValue.VerbatimString(enc, blob) =>
                let totalLen = 4 + blob.size  // 3 (enc) + 1 (:) + data
                append(buf, "=${totalLen}\r\n")
                append(buf, enc)
                buf.add(0x3Au8)  // ':'
                appendBytes(buf, blob.bytes)
                append(buf, "\r\n")

            case RESPValue.BulkError(blob) =>
                append(buf, "!${blob.size}\r\n")
                appendBytes(buf, blob.bytes)
                append(buf, "\r\n")

            case RESPValue.Map(pairs) =>
                append(buf, "%${pairs.size}\r\n")
                for ((k, v) in pairs) {
                    appendBytes(buf, encodeValue(k))
                    appendBytes(buf, encodeValue(v))
                }

            case RESPValue.Set(items) =>
                append(buf, "~${items.size}\r\n")
                for (item in items) {
                    appendBytes(buf, encodeValue(item))
                }

            case RESPValue.Push(items) =>
                append(buf, ">${items.size}\r\n")
                for (item in items) {
                    appendBytes(buf, encodeValue(item))
                }

            case RESPValue.Attribute(pairs) =>
                append(buf, "|${pairs.size}\r\n")
                for ((k, v) in pairs) {
                    appendBytes(buf, encodeValue(k))
                    appendBytes(buf, encodeValue(v))
                }

            case RESPValue.StreamedString(blob) =>
                // 流式字符串编码：$? + 分块
                append(buf, "$?\r\n")
                let maxChunkSize: Int64 = 8192
                var offset: Int64 = 0
                while (offset < blob.size) {
                    let chunkSize = if (offset + maxChunkSize <= blob.size) {
                        maxChunkSize
                    } else {
                        blob.size - offset
                    }
                    append(buf, ";${chunkSize}\r\n")
                    for (i in 0..chunkSize) {
                        buf.add(blob.bytes[offset + i])
                    }
                    append(buf, "\r\n")
                    offset += chunkSize
                }
                append(buf, ";0\r\n")

            case RESPValue.End =>
                buf.add(0x2Eu8)  // '.'
                buf.add(0x0Du8)  // '\r'
                buf.add(0x0Au8)  // '\n'
        }

        collectArray(buf.iterator())
    }

    // ====================================================================
    // 内部辅助
    // ====================================================================

    /// 追加字符串的 UTF-8 字节到缓冲区
    private static func append(buf: ArrayList<Byte>, s: String): Unit {
        for (b in s) {
            buf.add(b)
        }
    }

    /// 追加字节数组到缓冲区
    private static func appendBytes(buf: ArrayList<Byte>, bytes: Array<Byte>): Unit {
        for (b in bytes) {
            buf.add(b)
        }
    }

    /// 格式化双精度值为 RESP 标准格式
    private static func formatDouble(f: Float64): String {
        if (f.isInf()) {
            if (f > 0.0) { "inf" } else { "-inf" }
        } else if (f.isNaN()) {
            "nan"
        } else {
            "${f}"
        }
    }
}
