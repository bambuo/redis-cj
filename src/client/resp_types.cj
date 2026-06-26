package redis.client
import std.collection.*
import std.convert.*

// ====================================================================
// RESP (Redis Serialization Protocol) 值类型
// ====================================================================

/// RESP 协议值类型枚举。
public enum RESPValue <: ToString {
    // -------- RESP2 --------
    /// 简单字符串，如 `+OK\r\n`
    | SimpleString(String)
    /// 简单错误，如 `-ERR unknown command\r\n`
    | Error(String)
    /// 整数，如 `:42\r\n`
    | Integer(Int64)
    /// 批量字符串（二进制安全），`$5\r\nhello\r\n`，`$-1\r\n` 为 null
    | BulkString(Option<Blob>)
    /// 数组，`*2\r\n...\r\n`，`*-1\r\n` 为 null
    | Array(Option<Array<RESPValue>>)

    // -------- RESP3 --------
    /// 空值，`_\r\n`
    | Null
    /// 布尔值，`#t\r\n` 或 `#f\r\n`
    | Boolean(Bool)
    /// 双精度浮点数，`,3.14\r\n`，`,inf\r\n` 等
    | Double(Float64)
    /// 大整数，`(349289032840923850932\r\n`
    | BigNumber(String)
    /// 格式化文本，`=15\r\ntxt:Some string\r\n`
    | VerbatimString(String, Blob)
    /// 批量错误，`!21\r\nSYNTAX invalid syntax\r\n`
    | BulkError(Blob)
    /// 键值对映射，`%2\r\n+first\r\n:1\r\n+second\r\n:2\r\n`
    | Map(Array<(RESPValue, RESPValue)>)
    /// 无序集合，`~3\r\n+a\r\n+b\r\n+c\r\n`
    | Set(Array<RESPValue>)
    /// 推送数据，`>3\r\n+pubsub\r\n+message\r\n+channel\r\n`
    | Push(Array<RESPValue>)
    /// 响应属性元数据，`|1\r\n+ttl\r\n:3600\r\n`
    | Attribute(Array<(RESPValue, RESPValue)>)

    // -------- RESP3 流式扩展 --------
    /// 流式字符串（分块传输后拼接的完整数据）
    | StreamedString(Blob)
    /// 流式数组，`*?\r\n...\r\n.\r\n`
    | StreamedArray(Array<RESPValue>)
    /// 流式集合，`~?\r\n...\r\n.\r\n`
    | StreamedSet(Array<RESPValue>)
    /// 流式映射，`%?\r\n...\r\n.\r\n`
    | StreamedMap(Array<(RESPValue, RESPValue)>)
    /// 流式聚合终止符 `.`
    | End

    /// 转换为可读字符串（实现 ToString 接口）
    public func toString(): String {
        respValueToString(this)
    }
}

// ====================================================================
// 工具方法
// ====================================================================

/// 判断 RESPValue 是否为错误类型
public func isError(val: RESPValue): Bool {
    match (val) {
        case RESPValue.Error(_) => true
        case RESPValue.BulkError(_) => true
        case _ => false
    }
}

/// 从 RESPValue 中提取错误消息（如果是错误类型）
public func getErrorMsg(val: RESPValue): Option<String> {
    match (val) {
        case RESPValue.Error(msg) => Some(msg)
        case RESPValue.BulkError(blob) => Some(blob.toDisplay())
        case _ => None
    }
}

/// 将 RESPValue 转换为可读的调试字符串
public func respValueToString(val: RESPValue): String {
    match (val) {
        case RESPValue.SimpleString(s) => "+${s}"
        case RESPValue.Error(s) => "-${s}"
        case RESPValue.Integer(n) => ":${n}"
        case RESPValue.BulkString(None) => "$-1 (nil)"
        case RESPValue.BulkString(Some(blob)) =>
            "$${blob.size} \"${blob.toDisplay()}\""
        case RESPValue.Array(None) => "*-1 (nil)"
        case RESPValue.Array(Some(arr)) =>
            formatArray(arr)
        case RESPValue.Null => "_(null)"
        case RESPValue.Boolean(b) =>
            if (b) { "#t" } else { "#f" }
        case RESPValue.Double(f) => ",${f}"
        case RESPValue.BigNumber(s) => "(${s}"
        case RESPValue.VerbatimString(enc, blob) =>
            "=${blob.size} ${enc}:${blob.toDisplay()}"
        case RESPValue.BulkError(blob) => "!${blob.toDisplay()}"
        case RESPValue.Map(pairs) =>
            formatMap(pairs)
        case RESPValue.Set(items) =>
            formatSet(items)
        case RESPValue.Push(items) =>
            formatPush(items)
        case RESPValue.Attribute(pairs) =>
            formatAttr(pairs)
        case RESPValue.StreamedString(blob) =>
            "流式字符串(${blob.size} 字节): ${blob.toDisplay()}"
        case RESPValue.StreamedArray(items) =>
            "流式数组(${items.size} 项)"
        case RESPValue.StreamedSet(items) =>
            "流式集合(${items.size} 项)"
        case RESPValue.StreamedMap(pairs) =>
            "流式映射(${pairs.size} 对)"
        case RESPValue.End => "."
    }
}

// ====================================================================
// Blob 扩展 — 从 RESPValue 提取数据
// ====================================================================

/// 从 RESPValue 安全提取 Option<Blob>
public func asBlob(val: RESPValue): Option<Blob> {
    match (val) {
        case RESPValue.BulkString(v) => v
        case RESPValue.SimpleString(s) => Some(Blob.fromUtf8(s))
        case RESPValue.VerbatimString(_, blob) => Some(blob)
        case _ => None
    }
}

/// 从 RESPValue 安全提取字符串
public func asString(val: RESPValue): Option<String> {
    match (val) {
        case RESPValue.SimpleString(s) => Some(s)
        case RESPValue.BulkString(Some(blob)) =>
            try { Some(blob.toUtf8()) } catch (_) { None }
        case RESPValue.Integer(n) => Some("${n}")
        case _ => None
    }
}

/// 从 RESPValue 安全提取 Int64
public func asInt(val: RESPValue): Option<Int64> {
    match (val) {
        case RESPValue.Integer(n) => Some(n)
        case RESPValue.BulkString(Some(blob)) =>
            try { Some(Int64.parse(blob.toUtf8())) } catch (_) { None }
        case _ => None
    }
}

// ====================================================================
// 格式化辅助
// ====================================================================

private func formatArray(arr: Array<RESPValue>): String {
    let parts = ArrayList<String>()
    parts.add("*${arr.size} [")
    for (v in arr) {
        parts.add("  ${respValueToString(v)}")
    }
    parts.add("]")
    String.join(collectArray(parts.iterator()), delimiter: "\n")
}

private func formatMap(pairs: Array<(RESPValue, RESPValue)>): String {
    let parts = ArrayList<String>()
    parts.add("%${pairs.size} {")
    for ((k, v) in pairs) {
        parts.add("  ${respValueToString(k)} => ${respValueToString(v)}")
    }
    parts.add("}")
    String.join(collectArray(parts.iterator()), delimiter: "\n")
}

private func formatSet(items: Array<RESPValue>): String {
    let parts = ArrayList<String>()
    parts.add("~${items.size} {")
    for (item in items) {
        parts.add("  ${respValueToString(item)}")
    }
    parts.add("}")
    String.join(collectArray(parts.iterator()), delimiter: "\n")
}

private func formatPush(items: Array<RESPValue>): String {
    let parts = ArrayList<String>()
    parts.add(">${items.size} (推送)")
    for (item in items) {
        parts.add("  ${respValueToString(item)}")
    }
    parts.add("")
    String.join(collectArray(parts.iterator()), delimiter: "\n")
}

private func formatAttr(pairs: Array<(RESPValue, RESPValue)>): String {
    let parts = ArrayList<String>()
    parts.add("|${pairs.size} (属性)")
    for ((k, v) in pairs) {
        parts.add("  ${respValueToString(k)} => ${respValueToString(v)}")
    }
    parts.add("}")
    String.join(collectArray(parts.iterator()), delimiter: "\n")
}
