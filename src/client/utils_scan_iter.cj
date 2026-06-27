package redis.client
import std.collection.*
import std.convert.*

/// SCAN 游标迭代器（Iterator 模式）
///
/// 封装 SCAN / HSCAN / SSCAN / ZSCAN 的游标状态，
/// 支持 `for (items in scanner)` 迭代方式。
///
/// # 用法
/// ```cangjie
/// let scanner = ScanIterator(client, "SCAN", 0, pattern: "user:*")
/// for (keys in scanner) {
///     for (key in keys) {
///         println("找到键: ${key}")
///     }
/// }
/// ```
public class ScanIterator {
    private let client: RedisClient
    private var cmdType: String  // "SCAN" | "HSCAN" | "SSCAN" | "ZSCAN"
    private var key: Option<String>  // HSCAN/SSCAN/ZSCAN 的键名
    private var cursor: Int64
    private let pattern: Option<String>
    private let count: Option<Int64>
    private var done: Bool

    /// 创建 SCAN 迭代器
    public init(client: RedisClient,
                cursor!: Int64 = 0,
                pattern!: Option<String> = None,
                count!: Option<Int64> = None) {
        this.client = client
        this.cmdType = "SCAN"
        this.key = None
        this.cursor = cursor
        this.pattern = pattern
        this.count = count
        this.done = cursor < 0
    }

    /// 创建迭代器（指定扫描类型和键）
    public static func forHash(client: RedisClient, key: String,
                               cursor!: Int64 = 0,
                               pattern!: Option<String> = None,
                               count!: Option<Int64> = None): ScanIterator {
        let iter = ScanIterator(client, cursor: cursor, pattern: pattern, count: count)
        iter.cmdType = "HSCAN"
        iter.key = Some(key)
        iter
    }

    public static func forSet(client: RedisClient, key: String,
                              cursor!: Int64 = 0,
                              pattern!: Option<String> = None,
                              count!: Option<Int64> = None): ScanIterator {
        let iter = ScanIterator(client, cursor: cursor, pattern: pattern, count: count)
        iter.cmdType = "SSCAN"
        iter.key = Some(key)
        iter
    }

    public static func forSortedSet(client: RedisClient, key: String,
                                    cursor!: Int64 = 0,
                                    pattern!: Option<String> = None,
                                    count!: Option<Int64> = None): ScanIterator {
        let iter = ScanIterator(client, cursor: cursor, pattern: pattern, count: count)
        iter.cmdType = "ZSCAN"
        iter.key = Some(key)
        iter
    }

    /// 获取下一批扫描结果
    /// @return Option<Array<String>> 有剩余数据时返回 Some(keys)，扫描完成返回 None
    public func next(): Option<Array<String>> {
        match (nextItems()) {
            case Some(items) =>
                let result = extractStringArray(items)
                if (result.size == 0 && done) { None } else { Some(result) }
            case None => None
        }
    }

    /// 获取下一批 HSCAN 字段和值。
    public func nextHashEntries(): Option<Array<(String, Blob)>> {
        if (cmdType != "HSCAN") {
            throw ProtocolError("nextHashEntries 仅适用于 HSCAN 迭代器")
        }
        match (nextItems()) {
            case Some(items) =>
                let result = parseHashEntries(items)
                if (result.size == 0 && done) { None } else { Some(result) }
            case None => None
        }
    }

    /// 获取下一批 ZSCAN 成员和分值。
    public func nextSortedSetEntries(): Option<Array<(Blob, Float64)>> {
        if (cmdType != "ZSCAN") {
            throw ProtocolError("nextSortedSetEntries 仅适用于 ZSCAN 迭代器")
        }
        match (nextItems()) {
            case Some(items) =>
                let result = parseSortedSetEntries(items)
                if (result.size == 0 && done) { None } else { Some(result) }
            case None => None
        }
    }

    private func nextItems(): Option<Array<RESPValue>> {
        if (done) { return None }

        let args = ArrayList<String>()
        args.add(cmdType)
        match (key) {
            case Some(k) => args.add(k)
            case None => ()
        }
        args.add("${cursor}")
        match (pattern) { case Some(p) => args.add("MATCH"); args.add(p) case None => () }
        match (count) { case Some(c) => args.add("COUNT"); args.add("${c}") case None => () }

        let resp = client.executeString(collectArray(args.iterator()))
        match (resp) {
            case RESPValue.Array(Some(items)) =>
                if (items.size >= 2) {
                    let cursorStr = asString(items[0]).getOrThrow()
                    this.cursor = Int64.parse(cursorStr)
                    if (this.cursor == 0) { this.done = true }
                    match (items[1]) {
                        case RESPValue.Array(Some(values)) =>
                            if (values.size == 0 && this.done) { None } else { Some(values) }
                        case _ => None
                    }
                } else { None }
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("${cmdType} 返回意外类型")
        }
    }

    /// 检查是否还有剩余数据
    public func hasNext(): Bool {
        !done && cursor != 0
    }

    /// 重置迭代器
    public func reset(): Unit {
        this.cursor = 0
        this.done = false
    }

    /// 获取当前游标值
    public func getCursor(): Int64 { cursor }

    /// 一次性收集所有结果（注意：可能返回大量数据）
    public func collectAll(): Array<String> {
        let all = ArrayList<String>()
        while (true) {
            match (next()) {
                case Some(items) =>
                    for (item in items) { all.add(item) }
                case None => break
            }
        }
        collectArray(all.iterator())
    }

    public func collectHashEntries(): Array<(String, Blob)> {
        if (cmdType != "HSCAN") {
            throw ProtocolError("collectHashEntries 仅适用于 HSCAN 迭代器")
        }
        let all = ArrayList<(String, Blob)>()
        while (true) {
            match (nextHashEntries()) {
                case Some(items) =>
                    for (item in items) { all.add(item) }
                case None => break
            }
        }
        collectArray(all.iterator())
    }

    public func collectSortedSetEntries(): Array<(Blob, Float64)> {
        if (cmdType != "ZSCAN") {
            throw ProtocolError("collectSortedSetEntries 仅适用于 ZSCAN 迭代器")
        }
        let all = ArrayList<(Blob, Float64)>()
        while (true) {
            match (nextSortedSetEntries()) {
                case Some(items) =>
                    for (item in items) { all.add(item) }
                case None => break
            }
        }
        collectArray(all.iterator())
    }

    private func parseHashEntries(items: Array<RESPValue>): Array<(String, Blob)> {
        let result = ArrayList<(String, Blob)>()
        var i: Int64 = 0
        while (i + 1 < items.size) {
            match ((asString(items[i]), asBlob(items[i + 1]))) {
                case (Some(field), Some(value)) => result.add((field, value))
                case _ => throw ProtocolError("HSCAN 返回字段/值格式错误")
            }
            i += 2
        }
        collectArray(result.iterator())
    }

    private func parseSortedSetEntries(items: Array<RESPValue>): Array<(Blob, Float64)> {
        let result = ArrayList<(Blob, Float64)>()
        var i: Int64 = 0
        while (i + 1 < items.size) {
            match ((asBlob(items[i]), asString(items[i + 1]))) {
                case (Some(member), Some(score)) => result.add((member, Float64.parse(score)))
                case _ => throw ProtocolError("ZSCAN 返回成员/分值格式错误")
            }
            i += 2
        }
        collectArray(result.iterator())
    }
}
