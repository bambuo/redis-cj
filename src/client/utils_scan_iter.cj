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
                        case RESPValue.Array(Some(keys)) =>
                            let result = extractStringArray(keys)
                            if (result.size == 0 && this.done) { None } else { Some(result) }
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
}
