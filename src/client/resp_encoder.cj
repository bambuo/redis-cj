package redis.client
import std.collection.*
import std.convert.*
import std.unicode.*

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
                validateNoCRLF(s, "SimpleString")
                append(buf, "+${s}\r\n")

            case RESPValue.Error(s) =>
                validateNoCRLF(s, "Error")
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
                let str = formatDoubleRESP(f)
                append(buf, ",${str}\r\n")

            case RESPValue.BigNumber(s) =>
                validateBigNumberText(s)
                append(buf, "(${s}\r\n")

            case RESPValue.VerbatimString(enc, blob) =>
                validateVerbatimEncoding(enc)
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
                validatePushFirstElement(items)
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

            case RESPValue.Attributed(value, pairs) =>
                appendBytes(buf, encodeValue(RESPValue.Attribute(pairs)))
                appendBytes(buf, encodeValue(value))

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

            // -------- RESP3 流式聚合 --------
            case RESPValue.StreamedArray(items) =>
                append(buf, "*?\r\n")
                for (item in items) {
                    appendBytes(buf, encodeValue(item))
                }
                append(buf, ".\r\n")

            case RESPValue.StreamedSet(items) =>
                append(buf, "~?\r\n")
                for (item in items) {
                    appendBytes(buf, encodeValue(item))
                }
                append(buf, ".\r\n")

            case RESPValue.StreamedMap(pairs) =>
                append(buf, "%?\r\n")
                for ((k, v) in pairs) {
                    appendBytes(buf, encodeValue(k))
                    appendBytes(buf, encodeValue(v))
                }
                append(buf, ".\r\n")

            case RESPValue.End =>
                throw ProtocolError("End 标记只能作为流式聚合终止符")
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

    // ====================================================================
    // 校验辅助
    // ====================================================================

    /// 校验字符串不包含 CR 或 LF 字符（SimpleString / Error 规范要求）
    private static func validateNoCRLF(s: String, typeName: String): Unit {
        if (s.contains("\r") || s.contains("\n")) {
            throw ProtocolError("${typeName} 不得包含 CR 或 LF 字符")
        }
    }

    /// 校验 BigNumber 只能包含可选符号和十进制数字
    private static func validateBigNumberText(s: String): Unit {
        if (s.size == 0) {
            throw ProtocolError("BigNumber 不能为空")
        }
        if (s.contains("\r") || s.contains("\n")) {
            throw ProtocolError("BigNumber 不得包含 CR 或 LF 字符")
        }
        var start: Int64 = 0
        if (s.startsWith("-") || s.startsWith("+")) {
            if (s.size == 1) {
                throw ProtocolError("BigNumber 符号后必须包含数字")
            }
            start = 1
        }
        let bytes = s.toArray()
        for (i in start..bytes.size) {
            if (bytes[i] < 0x30u8 || bytes[i] > 0x39u8) {
                throw ProtocolError("BigNumber 只能包含十进制数字")
            }
        }
    }

    /// 校验 VerbatimString 编码标识为 3 个非控制 ASCII 字节
    private static func validateVerbatimEncoding(enc: String): Unit {
        let bytes = enc.toArray()
        if (bytes.size != 3) {
            throw ProtocolError(
                "VerbatimString 编码标识必须恰好为 3 字节，实际为 ${bytes.size}"
            )
        }
        for (b in bytes) {
            if (b < 0x20u8 || b > 0x7Eu8) {
                throw ProtocolError("VerbatimString 编码标识必须为 3 个非控制 ASCII 字节")
            }
        }
    }

    /// 校验 Push 类型首元素为字符串（规范要求）
    private static func validatePushFirstElement(items: Array<RESPValue>): Unit {
        if (items.size == 0) {
            throw ProtocolError("Push 类型至少需要一个元素（push 类型标识）")
        }
        let firstIsString = match (items[0]) {
            case RESPValue.SimpleString(_) => true
            case RESPValue.BulkString(Some(_)) => true
            case _ => false
        }
        if (!firstIsString) {
            throw ProtocolError("Push 类型的第一个元素必须为字符串类型")
        }
    }

    // ====================================================================
    // Double 格式化
    // ====================================================================

    /// 将 Float64 格式化为 RESP 兼容的字符串表示。
    ///
    /// 遵循 RESP3 规范：
    /// - 禁止指数格式（RESP3 明确"Exponential format is invalid"）
    /// - 必须有前导零（".5" 不合法，必须为 "0.5"）
    /// - 特殊值：inf / -inf / nan
    private static func formatDoubleRESP(f: Float64): String {
        if (f.isInf()) {
            if (f > 0.0) { "inf" } else { "-inf" }
        } else if (f.isNaN()) {
            "nan"
        } else {
            let raw = "${f}"
            // 检测并展开指数格式
            let lower = raw.toLower()
            if (lower.contains("e")) {
                expandScientific(raw)
            } else {
                ensureLeadingZero(raw)
            }
        }
    }

    /// 确保小数前导零：".xxx" → "0.xxx"，"-.xxx" → "-0.xxx"
    private static func ensureLeadingZero(s: String): String {
        if (s.startsWith(".")) {
            "0${s}"
        } else if (s.startsWith("-.")) {
            "-0${s[2..]}"
        } else {
            s
        }
    }

    /// 将科学计数法字符串展开为完整小数表示
    /// 例如 "1.5e-3" → "0.0015"，"-2.5E+4" → "-25000"，"1.23e1" → "12.3"
    private static func expandScientific(s: String): String {
        let lower = s.toLower()
        let eIdx = match (lower.indexOf("e")) {
            case Some(i) => i
            case None => return s  // 不应到达此处
        }

        let mantissa = s[0..eIdx]
        let expStr = s[eIdx + 1..]
        let exp = try { Int64.parse(expStr) } catch (_) { return s }

        if (exp == 0) {
            return ensureLeadingZero(mantissa)
        }

        // 分离整数部分和小数部分
        let dotIdx = match (mantissa.indexOf(".")) {
            case Some(i) => i
            case None => mantissa.size
        }
        let negative = mantissa.startsWith("-")

        // 提取去掉符号和小数点的纯数字串
        let beforeDot = if (negative) { mantissa[1..dotIdx] } else { mantissa[0..dotIdx] }
        let afterDot = if (dotIdx < mantissa.size) { mantissa[dotIdx + 1..] } else { "" }
        let pureDigits = "${beforeDot}${afterDot}"

        let intLen = if (negative) { dotIdx - 1 } else { dotIdx }
        let prefix = if (negative) { "-" } else { "" }

        if (exp > 0) {
            // 正指数：小数点右移
            let newIntLen = intLen + exp
            let totalLen = pureDigits.size
            if (newIntLen >= totalLen) {
                // 末尾补零：如 1.5e3 → "1500"
                let zeros = buildCharString(0x30u8, newIntLen - totalLen)  // '0'
                "${prefix}${pureDigits}${zeros}"
            } else {
                // 小数点在数字中间：如 1.23e1 → "12.3"
                "${prefix}${pureDigits[0..newIntLen]}.${pureDigits[newIntLen..]}"
            }
        } else {
            // 负指数：小数点左移
            let absExp = -exp
            let leadingZeros = absExp - intLen
            if (leadingZeros >= 0) {
                // 需要前导零：如 1.5e-3 → "0.0015"
                let zeros = buildCharString(0x30u8, leadingZeros)
                "${prefix}0.${zeros}${pureDigits}"
            } else {
                // 小数点在原数字内部：如 123.4e-1 → "12.34"
                let pointPos = intLen + exp  // exp is negative
                "${prefix}${pureDigits[0..pointPos]}.${pureDigits[pointPos..]}"
            }
        }
    }

    /// 用指定字节重复构建字符串
    private static func buildCharString(ch: Byte, count: Int64): String {
        if (count <= 0) { return "" }
        let buf = ArrayList<Byte>()
        for (_ in 0..count) {
            buf.add(ch)
        }
        String.fromUtf8(collectArray(buf.iterator()))
    }
}
