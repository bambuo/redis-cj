package redis.client
import std.collection.*
import std.convert.*

// ====================================================================
// RESP 解码器
// ====================================================================

/// RESP 解码器 — 从传输层读取并解析 RESP 协议数据。
///
/// # 设计
/// - 内部维护 `ArrayList<Byte>` 读缓冲区，处理 TCP 粘包/半包
/// - 使用 `readPos` 游标跟踪已读位置，避免数据拷贝
/// - 支持流式字符串 `$?` 和流式聚合 `*?`/`~?`/`%?` 的透明拼接
/// - 支持 Push 类型拦截（观察者模式）
/// - 支持 Attribute 类型分离
///
/// # 线程安全
/// 本类非线程安全。在同一连接上应串行调用。
public class RespDecoder {
    private let transport: Transport
    private var buf: ArrayList<Byte>
    private var readPos: Int64
    private var maxBulkLen: Int64
    private var maxDepth: Int64

    /// 创建解码器
    /// @param transport 传输层实例
    /// @param maxBulkLen 最大 Bulk String 长度（默认 512MB）
    /// @param maxDepth 最大嵌套深度（默认 10）
    public init(transport: Transport,
                maxBulkLen!: Int64 = 512 * 1024 * 1024,
                maxDepth!: Int64 = 10) {
        this.transport = transport
        this.buf = ArrayList<Byte>()
        this.readPos = 0
        this.maxBulkLen = maxBulkLen
        this.maxDepth = maxDepth
    }

    // ====================================================================
    // 底层缓冲区管理
    // ====================================================================

    /// 确保缓冲区中至少有 n 个未读字节
    private func ensure(n: Int64): Unit {
        while (buf.size - readPos < n) {
            let tmp = Array<Byte>(4096, repeat: 0)
            let count = transport.read(tmp)
            if (count <= 0) {
                throw ProtocolError("连接已关闭，无法继续读取")
            }
            for (i in 0..count) {
                buf.add(tmp[i])
            }
        }
    }

    /// 读取一个字节
    private func readByte(): Byte {
        ensure(1)
        let b = buf[readPos]
        readPos++
        return b
    }

    /// 读取直到 CRLF（\r\n），返回行内容（不含 CRLF）
    ///
    /// 注意：只应在预期有 CRLF 终止的行数据时调用
    /// （SimpleString、Error、Integer 的数值部分、长度前缀等）
    /// 如果 \r 后不是 \n，视为协议错误。
    private func readLine(): Array<Byte> {
        let result = ArrayList<Byte>()
        while (true) {
            let b = readByte()
            if (b == 0x0Du8) {
                let next = readByte()
                if (next == 0x0Au8) {
                    break
                }
                throw ProtocolError(
                    "无效的 RESP 行终止：期望 \\r\\n，但 \\r 后接 0x${Int64(next)}"
                )
            } else if (b == 0x0Au8) {
                throw ProtocolError("无效的 RESP 行终止：裸 \\n 不允许出现在行内")
            } else {
                result.add(b)
            }
        }
        collectArray(result.iterator())
    }

    /// 读取精确 n 个字节
    private func readExact(n: Int64): Array<Byte> {
        ensure(n)
        let result = Array<Byte>(n, repeat: 0)
        for (i in 0..n) {
            result[i] = buf[readPos + i]
        }
        readPos += n
        result
    }

    /// 解析一行整数（用于 : $ * % ~ > | 等类型的长度/计数行）
    private func parseLineInt(): Int64 {
        let line = readLine()
        let str = String.fromUtf8(line)
        try {
            Int64.parse(str)
        } catch (e: Exception) {
            throw ProtocolError("整数解析失败: '${str}' - ${e.message}")
        }
    }

    /// 跳过 2 字节 CRLF
    private func skipCRLF(): Unit {
        let cr = readByte()
        let lf = readByte()
        if (cr != 0x0Du8 || lf != 0x0Au8) {
            throw ProtocolError("期望 CRLF 终止符，但收到 0x${Int64(cr)} 0x${Int64(lf)}")
        }
    }

    // ====================================================================
    // 值读取（核心入口）
    // ====================================================================

    /// 读取下一个完整 RESP 值（无深度参数版本，从 0 开始）
    public func readValue(): RESPValue {
        readValue(0)
    }

    /// 读取下一个完整 RESP 值，并允许顶层 Push 作为返回值。
    ///
    /// 普通命令应继续使用 readValue()，让 out-of-band Push 触发回调后被跳过。
    /// Pub/Sub、MONITOR 等 push-mode 命令需要读取订阅确认帧，因此使用此入口。
    public func readValueIncludingPush(): RESPValue {
        readValue(0, includePush: true, allowEnd: false)
    }

    /// 读取下一个完整 RESP 值（带深度跟踪）
    ///
    /// 这是高层读取方法，自动处理：
    /// - Push 类型：触发 pushCallbacks 后继续读取
    /// - Attribute 类型：保存到 lastAttributes 后继续读取
    /// - 流式拼接：透明拼接 $? / *? / ~? / %? 为最终数据
    ///
    /// @param depth 当前递归深度（内部使用）
    /// @return 第一个非 Push、非 Attribute 的 RESP 值
    public func readValue(depth: Int64): RESPValue {
        readValue(depth, includePush: false, allowEnd: false)
    }

    private func readValue(depth: Int64, includePush!: Bool, allowEnd!: Bool): RESPValue {
        if (depth > maxDepth) {
            throw ProtocolError("RESP 嵌套超过最大深度 ${maxDepth}")
        }

        let firstByte = readByte()

        return match (firstByte) {
            // -------- RESP2 --------
            case b'+' =>  // Simple String
                let line = readLine()
                RESPValue.SimpleString(String.fromUtf8(line))

            case b'-' =>  // Error
                let line = readLine()
                RESPValue.Error(String.fromUtf8(line))

            case b':' =>  // Integer
                let n = parseLineInt()
                RESPValue.Integer(n)

            case b'$' =>  // Bulk String or Streamed String
                // 预读：检查是数字还是 '?'
                let ch = readByte()
                if (ch == 0x3Fu8) {  // '?' → 流式字符串
                    skipCRLF()
                    readStreamedString()
                } else {
                    // 已读取了第一个数字字符，需要组装回长度行
                    // 用回退方式：把字符放回不可行，直接继续读取数字直到 CRLF
                    let lenBytes = ArrayList<Byte>()
                    lenBytes.add(ch)
                    collectRestOfLine(lenBytes)
                    let lineStr = String.fromUtf8(collectArray(lenBytes.iterator()))
                    let len = parseIntText(lineStr)
                    if (len == -1) {
                        RESPValue.BulkString(None)
                    } else if (len < -1) {
                        throw ProtocolError("Bulk String 长度 ${len} 无效")
                    } else {
                        if (len > maxBulkLen) {
                            throw ProtocolError(
                                "Bulk String 长度 ${len} 超过最大限制 ${maxBulkLen}"
                            )
                        }
                        let data = readExact(len)
                        skipCRLF()
                        RESPValue.BulkString(Some(Blob.fromBytes(data)))
                    }
                }

            case b'*' =>  // Array or Null Array or Streamed Array
                let ch = readByte()
                if (ch == 0x3Fu8) {  // '?' → 流式数组
                    skipCRLF()
                    readStreamedArray(depth)
                } else {
                    let countBytes = ArrayList<Byte>()
                    countBytes.add(ch)
                    collectRestOfLine(countBytes)
                    let lineStr = String.fromUtf8(collectArray(countBytes.iterator()))
                    let count = parseIntText(lineStr)
                    if (count == -1) {
                        RESPValue.Array(None)
                    } else if (count < -1) {
                        throw ProtocolError("Array 元素数量 ${count} 无效")
                    } else {
                        let items = ArrayList<RESPValue>()
                        for (_ in 0..count) {
                            items.add(readValue(depth + 1))
                        }
                        RESPValue.Array(Some(collectArray(items.iterator())))
                    }
                }

            // -------- RESP3 --------
            case b'_' =>  // Null
                skipCRLF()
                RESPValue.Null

            case b'#' =>  // Boolean
                let b = readByte()
                skipCRLF()
                if (b == 0x74u8) {      // 't'
                    RESPValue.Boolean(true)
                } else if (b == 0x66u8) {  // 'f'
                    RESPValue.Boolean(false)
                } else {
                    throw ProtocolError("无效的 Boolean 值字节: ${Int64(b)}，期望 't' 或 'f'")
                }

            case b',' =>  // Double
                let line = readLine()
                let str = String.fromUtf8(line)
                let val = parseDouble(str)
                RESPValue.Double(val)

            case b'(' =>  // Big Number
                let line = readLine()
                let str = String.fromUtf8(line)
                validateBigNumber(str)
                RESPValue.BigNumber(str)

            case b'=' =>  // Verbatim String
                let len = parseLineInt()
                if (len < 4) {
                    throw ProtocolError("Verbatim String 长度 ${len} 至少需要 4 字节")
                }
                if (len > maxBulkLen) {
                    throw ProtocolError(
                        "Verbatim String 长度 ${len} 超过最大限制 ${maxBulkLen}"
                    )
                }
                let allData = readExact(len)
                skipCRLF()
                // 格式: <3-byte-encoding>:<data>
                if (allData[3] != 0x3Au8) {
                    throw ProtocolError("Verbatim String 编码标识后必须为 ':' 分隔符")
                }
                let encBytes = Array<Byte>(3, repeat: 0)
                for (i in 0..3) { encBytes[i] = allData[i] }
                validateVerbatimEncodingBytes(encBytes)
                let encoding = String.fromUtf8(encBytes)
                let textLen = len - 4
                let textBytes = Array<Byte>(textLen, repeat: 0)
                for (i in 0..textLen) { textBytes[i] = allData[4 + i] }
                RESPValue.VerbatimString(encoding, Blob.fromBytes(textBytes))

            case b'!' =>  // Bulk Error
                let len = parseLineInt()
                if (len < 0) {
                    throw ProtocolError("Bulk Error 长度 ${len} 无效")
                }
                if (len > maxBulkLen) {
                    throw ProtocolError(
                        "Bulk Error 长度 ${len} 超过最大限制 ${maxBulkLen}"
                    )
                }
                let data = readExact(len)
                skipCRLF()
                RESPValue.BulkError(Blob.fromBytes(data))

            case b'%' =>  // Map
                let ch = readByte()
                if (ch == 0x3Fu8) {  // '?' → 流式 Map
                    skipCRLF()
                    readStreamedMap(depth)
                } else {
                    let countBytes = ArrayList<Byte>()
                    countBytes.add(ch)
                    collectRestOfLine(countBytes)
                    let count = parseCount(
                        String.fromUtf8(collectArray(countBytes.iterator())),
                        "Map"
                    )
                    let pairs = ArrayList<(RESPValue, RESPValue)>()
                    for (_ in 0..count) {
                        let k = readValue(depth + 1)
                        let v = readValue(depth + 1)
                        pairs.add((k, v))
                    }
                    RESPValue.Map(collectArray(pairs.iterator()))
                }

            case b'~' =>  // Set
                let ch = readByte()
                if (ch == 0x3Fu8) {  // '?' → 流式 Set
                    skipCRLF()
                    // 流式 Set 同流式 Array 处理
                    let items = readStreamedItems(depth)
                    RESPValue.Set(items)
                } else {
                    let countBytes = ArrayList<Byte>()
                    countBytes.add(ch)
                    collectRestOfLine(countBytes)
                    let count = parseCount(
                        String.fromUtf8(collectArray(countBytes.iterator())),
                        "Set"
                    )
                    let items = ArrayList<RESPValue>()
                    for (_ in 0..count) {
                        items.add(readValue(depth + 1))
                    }
                    RESPValue.Set(collectArray(items.iterator()))
                }

            case b'>' =>  // Push
                if (depth > 0) {
                    throw ProtocolError("Push 类型只能出现在顶层")
                }
                let ch = readByte()
                let countBytes = ArrayList<Byte>()
                countBytes.add(ch)
                collectRestOfLine(countBytes)
                let count = parseCount(
                    String.fromUtf8(collectArray(countBytes.iterator())),
                    "Push"
                )
                let items = ArrayList<RESPValue>()
                for (_ in 0..count) {
                    items.add(readValue(depth + 1))
                }
                let pushVal = RESPValue.Push(collectArray(items.iterator()))
                validateDecodedPush(pushVal)
                dispatchPush(pushVal)
                if (includePush) {
                    pushVal
                } else {
                    readValue(depth)  // 在同一深度读取真正的响应
                }

            case b'|' =>  // Attribute
                let ch = readByte()
                let countBytes = ArrayList<Byte>()
                countBytes.add(ch)
                collectRestOfLine(countBytes)
                let count = parseCount(
                    String.fromUtf8(collectArray(countBytes.iterator())),
                    "Attribute"
                )
                let pairs = ArrayList<(RESPValue, RESPValue)>()
                for (_ in 0..count) {
                    let k = readValue(depth + 1)
                    let v = readValue(depth + 1)
                    pairs.add((k, v))
                }
                let attrPairs = collectArray(pairs.iterator())
                if (depth == 0) {
                    // 顶层 Attribute 是命令主响应的侧通道元数据。
                    saveAttributes(attrPairs)
                    readValue(depth)
                } else {
                    // 嵌套 Attribute 只增强紧随其后的子响应，不能丢到全局侧通道。
                    let value = readValue(depth)
                    RESPValue.Attributed(value, attrPairs)
                }

            case b'.' =>  // End (流式终止符)
                skipCRLF()
                if (allowEnd) {
                    RESPValue.End
                } else {
                    throw ProtocolError("End 标记只能作为流式聚合终止符")
                }

            case _ =>
                throw ProtocolError("未知 RESP 类型首字节: ${Int64(firstByte)}")
        }
    }

    // ====================================================================
    // 流式类型处理
    // ====================================================================

    /// 读取流式字符串（$? ... ;0\r\n）
    private func readStreamedString(): RESPValue {
        let chunks = ArrayList<Array<Byte>>()
        while (true) {
            let b = readByte()
            if (b == 0x3Bu8) {  // ';'
                let lenStr = String.fromUtf8(readLine())
                let len = parseIntText(lenStr)
                if (len < 0) {
                    throw ProtocolError("流式字符串分块长度 ${len} 无效")
                }
                if (len > maxBulkLen) {
                    throw ProtocolError(
                        "流式字符串分块长度 ${len} 超过最大限制 ${maxBulkLen}"
                    )
                }
                if (len == 0) {
                    break  // ;0\r\n → 传输结束
                }
                var nextTotal: Int64 = len
                for (c in chunks) { nextTotal += c.size }
                if (nextTotal > maxBulkLen) {
                    throw ProtocolError(
                        "流式字符串总长度 ${nextTotal} 超过最大限制 ${maxBulkLen}"
                    )
                }
                let chunk = readExact(len)
                skipCRLF()
                chunks.add(chunk)
            } else {
                throw ProtocolError("流式字符串格式错误: 期望 ';' 但得到 ${Int64(b)}")
            }
        }
        // 合并所有块
        var totalSize: Int64 = 0
        for (c in chunks) { totalSize += c.size }
        let merged = Array<Byte>(totalSize, repeat: 0)
        var offset: Int64 = 0
        for (c in chunks) {
            for (i in 0..c.size) {
                merged[offset + i] = c[i]
            }
            offset += c.size
        }
        RESPValue.StreamedString(Blob.fromBytes(merged))
    }

    /// 读取流式数组（*? ... .）
    private func readStreamedArray(depth: Int64): RESPValue {
        let items = readStreamedItems(depth)
        RESPValue.Array(Some(items))
    }

    /// 读取流式 Map（%? ... .）
    private func readStreamedMap(depth: Int64): RESPValue {
        let items = ArrayList<RESPValue>()
        while (true) {
            let val = readValue(depth + 1, includePush: false, allowEnd: true)
            match (val) {
                case RESPValue.End => break
                case _ => items.add(val)
            }
        }
        // Map 需要偶数个元素组成键值对
        let arr = collectArray(items.iterator())
        if (arr.size % 2 != 0) {
            throw ProtocolError("流式 Map 元素数量 ${arr.size} 不是偶数")
        }
        let pairs = ArrayList<(RESPValue, RESPValue)>()
        var i: Int64 = 0
        while (i < arr.size) {
            pairs.add((arr[i], arr[i + 1]))
            i += 2
        }
        RESPValue.Map(collectArray(pairs.iterator()))
    }

    /// 读取流式聚合的通用项列表
    private func readStreamedItems(depth: Int64): Array<RESPValue> {
        let items = ArrayList<RESPValue>()
        while (true) {
            let val = readValue(depth + 1, includePush: false, allowEnd: true)
            match (val) {
                case RESPValue.End => break
                case _ => items.add(val)
            }
        }
        collectArray(items.iterator())
    }

    // ====================================================================
    // Push 回调管理
    // ====================================================================

    /// Push 数据回调（函数类型）
    private var pushCallbacks: ArrayList<(RESPValue) -> Unit> = ArrayList<(RESPValue) -> Unit>()

    /// 注册 Push 数据回调
    /// 当解码器读取到 Push 类型时，会触发所有已注册的回调
    public func onPush(callback: (RESPValue) -> Unit): Unit {
        pushCallbacks.add(callback)
    }

    /// 分发 Push 数据到所有注册的回调
    private func dispatchPush(pushVal: RESPValue): Unit {
        for (cb in pushCallbacks) {
            cb(pushVal)
        }
    }

    // ====================================================================
    // Attribute 侧通道
    // ====================================================================

    private var lastAttributes: Option<Array<(RESPValue, RESPValue)>> = None

    /// 保存属性数据到侧通道
    private func saveAttributes(pairs: Array<(RESPValue, RESPValue)>): Unit {
        match (lastAttributes) {
            case Some(existing) =>
                let merged = ArrayList<(RESPValue, RESPValue)>()
                for (pair in existing) { merged.add(pair) }
                for (pair in pairs) { merged.add(pair) }
                lastAttributes = Some(collectArray(merged.iterator()))
            case None =>
                lastAttributes = Some(pairs)
        }
    }

    /// 获取最后一次读取中分离的属性数据
    /// 如果没有属性，返回 None
    public func getAttributes(): Option<Array<(RESPValue, RESPValue)>> {
        lastAttributes
    }

    /// 清除属性缓存
    public func clearAttributes(): Unit {
        lastAttributes = None
    }

    // ====================================================================
    // 缓冲区管理
    // ====================================================================

    /// 丢弃已读数据，压缩缓冲区
    public func compact(): Unit {
        if (readPos > 0) {
            let remaining = buf.size - readPos
            if (remaining > 0) {
                let newBuf = ArrayList<Byte>()
                for (i in readPos..buf.size) {
                    newBuf.add(buf[i])
                }
                buf = newBuf
            } else {
                buf = ArrayList<Byte>()
            }
            readPos = 0
        }
    }

    // ====================================================================
    // 内部辅助
    // ====================================================================

    /// 收集行的剩余部分（已读取第一个字符后继续读取直到 CRLF）
    /// 如果 \r 后不是 \n，视为协议错误。
    private func collectRestOfLine(acc: ArrayList<Byte>): Unit {
        while (true) {
            let b = readByte()
            if (b == 0x0Du8) {
                let next = readByte()
                if (next == 0x0Au8) {
                    break
                }
                throw ProtocolError(
                    "无效的 RESP 行终止：期望 \\r\\n，但 \\r 后接 0x${Int64(next)}"
                )
            } else {
                acc.add(b)
            }
        }
    }

    /// 解析特殊浮点值
    private func parseDouble(str: String): Float64 {
        match (str) {
            case "inf" | "+inf" => Float64.Inf
            case "-inf" => -Float64.Inf
            case "nan" => Float64.NaN
            case _ =>
                if (str.contains("e") || str.contains("E")) {
                    throw ProtocolError("浮点数禁止使用指数格式: '${str}'")
                }
                if (str.startsWith(".") || str.startsWith("-.") || str.startsWith("+.")) {
                    throw ProtocolError("浮点数小数点前必须包含数字: '${str}'")
                }
                try {
                    Float64.parse(str)
                } catch (e: Exception) {
                    throw ProtocolError("浮点数解析失败: '${str}'")
                }
        }
    }

    private func validateBigNumber(str: String): Unit {
        if (str.size == 0) {
            throw ProtocolError("Big Number 不能为空")
        }
        var start: Int64 = 0
        if (str.startsWith("-") || str.startsWith("+")) {
            if (str.size == 1) {
                throw ProtocolError("Big Number 符号后必须包含数字")
            }
            start = 1
        }
        let bytes = str.toArray()
        for (i in start..bytes.size) {
            if (bytes[i] < 0x30u8 || bytes[i] > 0x39u8) {
                throw ProtocolError("Big Number 只能包含十进制数字: '${str}'")
            }
        }
    }

    private func validateVerbatimEncodingBytes(bytes: Array<Byte>): Unit {
        if (bytes.size != 3) {
            throw ProtocolError("Verbatim String 编码标识必须恰好为 3 字节")
        }
        for (b in bytes) {
            if (b < 0x20u8 || b > 0x7Eu8) {
                throw ProtocolError("Verbatim String 编码标识必须为 3 个非控制 ASCII 字节")
            }
        }
    }

    private func parseIntText(str: String): Int64 {
        try {
            Int64.parse(str)
        } catch (e: Exception) {
            throw ProtocolError("整数解析失败: '${str}' - ${e.message}")
        }
    }

    private func parseCount(str: String, typeName: String): Int64 {
        let count = parseIntText(str)
        if (count < 0) {
            throw ProtocolError("${typeName} 元素数量 ${count} 无效")
        }
        count
    }

    private func validateDecodedPush(pushVal: RESPValue): Unit {
        match (pushVal) {
            case RESPValue.Push(items) =>
                if (items.size == 0) {
                    throw ProtocolError("Push 类型至少需要一个元素（push 类型标识）")
                }
                match (items[0]) {
                    case RESPValue.SimpleString(_) => ()
                    case RESPValue.BulkString(Some(_)) => ()
                    case _ => throw ProtocolError("Push 类型的第一个元素必须为字符串类型")
                }
            case _ => ()
        }
    }
}
