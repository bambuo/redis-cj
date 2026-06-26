package redis.client
import std.collection.*

// ====================================================================
// 字符串命令 (String Commands)
// ====================================================================

// ── Command<T> 子类 ──

/// GET 命令：获取键的值
public class GetCommand <: Command<Option<Blob>> {
    private let key: String
    public init(key: String) { this.key = key }
    public override func encode(): Array<Blob> {
        [Blob.fromUtf8("GET"), Blob.fromUtf8(key)]
    }
    public override func decode(resp: RESPValue): Option<Blob> {
        match (resp) {
            case RESPValue.BulkString(v) => v
            case RESPValue.Null => None
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("GET 返回意外类型")
        }
    }
}

/// SET 命令：设置键值对
public class SetCommand <: Command<Bool> {
    private let key: String
    private let value: Blob
    private let ex: Option<Int64>
    private let px: Option<Int64>
    private let exAt: Option<Int64>
    private let pxAt: Option<Int64>
    private let keepTtl: Bool
    private let nx: Bool
    private let xx: Bool
    private let get: Bool

    public init(key: String, value: Blob,
                ex!: Option<Int64> = None,
                px!: Option<Int64> = None,
                exAt!: Option<Int64> = None,
                pxAt!: Option<Int64> = None,
                keepTtl!: Bool = false,
                nx!: Bool = false,
                xx!: Bool = false,
                get!: Bool = false) {
        this.key = key; this.value = value
        this.ex = ex; this.px = px; this.exAt = exAt; this.pxAt = pxAt
        this.keepTtl = keepTtl; this.nx = nx; this.xx = xx; this.get = get
    }

    public override func encode(): Array<Blob> {
        let args = ArrayList<Blob>()
        args.add(Blob.fromUtf8("SET"))
        args.add(Blob.fromUtf8(key))
        args.add(value)
        match (ex) {
            case Some(t) => args.add(Blob.fromUtf8("EX")); args.add(Blob.fromUtf8("${t}"))
            case None => ()
        }
        match (px) {
            case Some(t) => args.add(Blob.fromUtf8("PX")); args.add(Blob.fromUtf8("${t}"))
            case None => ()
        }
        match (exAt) {
            case Some(t) => args.add(Blob.fromUtf8("EXAT")); args.add(Blob.fromUtf8("${t}"))
            case None => ()
        }
        match (pxAt) {
            case Some(t) => args.add(Blob.fromUtf8("PXAT")); args.add(Blob.fromUtf8("${t}"))
            case None => ()
        }
        if (keepTtl) { args.add(Blob.fromUtf8("KEEPTTL")) }
        if (nx) { args.add(Blob.fromUtf8("NX")) }
        if (xx) { args.add(Blob.fromUtf8("XX")) }
        if (get) { args.add(Blob.fromUtf8("GET")) }
        collectArray(args.iterator())
    }

    public override func decode(resp: RESPValue): Bool {
        match (resp) {
            case RESPValue.SimpleString("OK") => true
            case RESPValue.BulkString(Some(_)) => true   // GET 选项返回旧值
            case RESPValue.BulkString(None) => false      // NX 下键已存在
            case RESPValue.Null => false                  // RESP3 Null（同 RESP2 nil）
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("SET 返回意外类型")
        }
    }
}

// ── extend 便捷方法 ──
extend RedisClient {
    // -------- 基本操作 --------

    /// 获取键的值。键不存在返回 None。
    public func get(key: String): Option<Blob> {
        GetCommand(key).execute(this)
    }

    /// 设置键值对。成功返回 true。
    public func set(key: String, value: Blob,
                    ex!: Option<Int64> = None,
                    px!: Option<Int64> = None,
                    exAt!: Option<Int64> = None,
                    pxAt!: Option<Int64> = None,
                    keepTtl!: Bool = false,
                    nx!: Bool = false,
                    xx!: Bool = false,
                    get!: Bool = false): Bool {
        SetCommand(
            key,
            value,
            ex: ex,
            px: px,
            exAt: exAt,
            pxAt: pxAt,
            keepTtl: keepTtl,
            nx: nx,
            xx: xx,
            get: get
        ).execute(this)
    }

    /// SET ... GET：设置新值并返回旧值。旧值不存在或条件未满足时返回 None。
    public func setGet(key: String, value: Blob,
                       ex!: Option<Int64> = None,
                       px!: Option<Int64> = None,
                       exAt!: Option<Int64> = None,
                       pxAt!: Option<Int64> = None,
                       keepTtl!: Bool = false,
                       nx!: Bool = false,
                       xx!: Bool = false): Option<Blob> {
        let args = ArrayList<Blob>()
        args.add(Blob.fromUtf8("SET"))
        args.add(Blob.fromUtf8(key))
        args.add(value)
        match (ex) { case Some(t) => args.add(Blob.fromUtf8("EX")); args.add(Blob.fromUtf8("${t}")) case None => () }
        match (px) { case Some(t) => args.add(Blob.fromUtf8("PX")); args.add(Blob.fromUtf8("${t}")) case None => () }
        match (exAt) { case Some(t) => args.add(Blob.fromUtf8("EXAT")); args.add(Blob.fromUtf8("${t}")) case None => () }
        match (pxAt) { case Some(t) => args.add(Blob.fromUtf8("PXAT")); args.add(Blob.fromUtf8("${t}")) case None => () }
        if (keepTtl) { args.add(Blob.fromUtf8("KEEPTTL")) }
        if (nx) { args.add(Blob.fromUtf8("NX")) }
        if (xx) { args.add(Blob.fromUtf8("XX")) }
        args.add(Blob.fromUtf8("GET"))
        expectBlob(execute(collectArray(args.iterator())), "SET GET")
    }

    /// 设置字符串值并返回旧值（GET 选项）
    public func getSet(key: String, value: Blob): Option<Blob> {
        let resp = execute([Blob.fromUtf8("GETSET"), Blob.fromUtf8(key), value])
        expectBlob(resp, "GETSET")
    }

    /// 追加值到键末尾。返回追加后的字符串长度。
    public func append(key: String, value: Blob): Int64 {
        let resp = execute([Blob.fromUtf8("APPEND"), Blob.fromUtf8(key), value])
        expectInt(resp, "APPEND")
    }

    /// 获取字符串值的字节长度
    public func strlen(key: String): Int64 {
        let resp = executeString(["STRLEN", key])
        expectInt(resp, "STRLEN")
    }

    // -------- 范围操作 --------

    /// 获取字符串的子串（闭区间 [start, end]，end=-1 表示末尾）
    public func getRange(key: String, start: Int64, end: Int64): Blob {
        let resp = executeString(["GETRANGE", key, "${start}", "${end}"])
        expectBlobVal(resp, "GETRANGE")
    }

    /// 在指定偏移处覆写值
    public func setRange(key: String, offset: Int64, value: Blob): Int64 {
        let resp = execute([
            Blob.fromUtf8("SETRANGE"), Blob.fromUtf8(key),
            Blob.fromUtf8("${offset}"), value,
        ])
        expectInt(resp, "SETRANGE")
    }

    // -------- 批量操作 --------

    /// 批量获取多个键的值。顺序与 keys 一致，不存在的键返回 None。
    public func mget(keys: Array<String>): Array<Option<Blob>> {
        let args = ArrayList<Blob>()
        args.add(Blob.fromUtf8("MGET"))
        for (k in keys) { args.add(Blob.fromUtf8(k)) }
        let resp = execute(collectArray(args.iterator()))
        match (resp) {
            case RESPValue.Array(Some(items)) =>
                let result = ArrayList<Option<Blob>>()
                for (item in items) {
                    match (item) {
                        case RESPValue.BulkString(v) => result.add(v)
                        case _ => result.add(None)
                    }
                }
                collectArray(result.iterator())
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("MGET 返回意外类型")
        }
    }

    /// 批量设置多个键值对
    public func mset(pairs: Array<(String, Blob)>): Unit {
        let args = ArrayList<Blob>()
        args.add(Blob.fromUtf8("MSET"))
        for ((k, v) in pairs) {
            args.add(Blob.fromUtf8(k))
            args.add(v)
        }
        let resp = execute(collectArray(args.iterator()))
        expectOK(resp, "MSET")
    }

    // -------- 数值操作 --------

    /// 将键的值加 1。返回新值。
    public func incr(key: String): Int64 {
        let resp = executeString(["INCR", key])
        expectInt(resp, "INCR")
    }

    /// 将键的值加指定增量。返回新值。
    public func incrBy(key: String, amount: Int64): Int64 {
        let resp = executeString(["INCRBY", key, "${amount}"])
        expectInt(resp, "INCRBY")
    }

    /// 将键的值加浮点增量。返回新值。
    public func incrByFloat(key: String, amount: Float64): Float64 {
        let resp = executeString(["INCRBYFLOAT", key, "${amount}"])
        expectDouble(resp, "INCRBYFLOAT")
    }

    /// 将键的值减 1。返回新值。
    public func decr(key: String): Int64 {
        let resp = executeString(["DECR", key])
        expectInt(resp, "DECR")
    }

    /// 将键的值减指定减量。返回新值。
    public func decrBy(key: String, amount: Int64): Int64 {
        let resp = executeString(["DECRBY", key, "${amount}"])
        expectInt(resp, "DECRBY")
    }

    // -------- 位操作 --------

    /// 设置指定偏移处的位值。返回旧位值（0 或 1）。
    public func setBit(key: String, offset: Int64, value: Bool): Int64 {
        let v = if (value) { "1" } else { "0" }
        let resp = executeString(["SETBIT", key, "${offset}", v])
        expectInt(resp, "SETBIT")
    }

    /// 获取指定偏移处的位值。返回 0 或 1。
    public func getBit(key: String, offset: Int64): Int64 {
        let resp = executeString(["GETBIT", key, "${offset}"])
        expectInt(resp, "GETBIT")
    }

    /// 统计字符串中为 1 的位数
    public func bitCount(key: String, start!: Option<Int64> = None, end!: Option<Int64> = None): Int64 {
        let args = ArrayList<String>()
        args.add("BITCOUNT"); args.add(key)
        match (start) {
            case Some(s) => args.add("${s}")
            case None => ()
        }
        match (end) {
            case Some(e) => args.add("${e}")
            case None => ()
        }
        let resp = executeString(collectArray(args.iterator()))
        expectInt(resp, "BITCOUNT")
    }

    // -------- 新增 string/bitmap 命令 --------

    /// 获取键的值并删除（Redis 6.2+）
    public func getdel(key: String): Option<Blob> {
        let resp = executeString(["GETDEL", key])
        expectBlob(resp, "GETDEL")
    }

    /// 获取键的值并设置新过期时间（Redis 6.2+）
    public func getex(key: String, ex!: Option<Int64> = None, px!: Option<Int64> = None,
                      exAt!: Option<Int64> = None, pxAt!: Option<Int64> = None,
                      persist!: Bool = false): Option<Blob> {
        let args = ArrayList<String>(); args.add("GETEX"); args.add(key)
        match (ex) { case Some(t) => args.add("EX"); args.add("${t}") case None => () }
        match (px) { case Some(t) => args.add("PX"); args.add("${t}") case None => () }
        match (exAt) { case Some(t) => args.add("EXAT"); args.add("${t}") case None => () }
        match (pxAt) { case Some(t) => args.add("PXAT"); args.add("${t}") case None => () }
        if (persist) { args.add("PERSIST") }
        let resp = executeString(collectArray(args.iterator()))
        expectBlob(resp, "GETEX")
    }

    /// 设置键值并指定过期时间（秒）
    public func setex(key: String, seconds: Int64, value: Blob): Unit {
        let resp = execute([Blob.fromUtf8("SETEX"), Blob.fromUtf8(key), Blob.fromUtf8("${seconds}"), value])
        expectOK(resp, "SETEX")
    }

    /// 仅当键不存在时设置值
    public func setnx(key: String, value: Blob): Bool {
        let resp = execute([Blob.fromUtf8("SETNX"), Blob.fromUtf8(key), value])
        expectBool(resp, "SETNX")
    }

    /// 设置键值并指定过期时间（毫秒）
    public func psetex(key: String, milliseconds: Int64, value: Blob): Unit {
        let resp = execute([Blob.fromUtf8("PSETEX"), Blob.fromUtf8(key), Blob.fromUtf8("${milliseconds}"), value])
        expectOK(resp, "PSETEX")
    }

    /// 仅当键不存在时批量设置
    public func msetnx(pairs: Array<(String, Blob)>): Bool {
        let args = ArrayList<Blob>(); args.add(Blob.fromUtf8("MSETNX"))
        for ((k, v) in pairs) { args.add(Blob.fromUtf8(k)); args.add(v) }
        let resp = execute(collectArray(args.iterator()))
        expectBool(resp, "MSETNX")
    }

    // -------- 位图扩展 --------

    /// 执行 BITFIELD 命令
    public func bitfield(key: String, operations: Array<String>): Array<Option<Int64>> {
        let args = ArrayList<String>(); args.add("BITFIELD"); args.add(key)
        for (op in operations) { args.add(op) }
        let resp = executeString(collectArray(args.iterator()))
        parseBitfieldResult(resp, "BITFIELD")
    }

    /// 执行只读 BITFIELD_RO 命令
    public func bitfieldRo(key: String, operations: Array<String>): Array<Option<Int64>> {
        let args = ArrayList<String>(); args.add("BITFIELD_RO"); args.add(key)
        for (op in operations) { args.add(op) }
        let resp = executeString(collectArray(args.iterator()))
        parseBitfieldResult(resp, "BITFIELD_RO")
    }

    private func parseBitfieldResult(resp: RESPValue, cmd: String): Array<Option<Int64>> {
        match (resp) {
            case RESPValue.Array(Some(items)) =>
                let result = ArrayList<Option<Int64>>()
                for (item in items) {
                    match (item) {
                        case RESPValue.Integer(n) => result.add(Some(n))
                        case RESPValue.BulkString(None) => result.add(None)
                        case _ => result.add(None)
                    }
                }
                collectArray(result.iterator())
            case RESPValue.Error(e) => throw createCommandError(e)
            case RESPValue.BulkError(e) => throw createCommandError(e.toUtf8())
            case _ => throw ProtocolError("${cmd} 返回意外类型")
        }
    }

    /// 在多个键之间执行位运算
    public func bitop(op: String, destkey: String, keys: Array<String>): Int64 {
        let args = ArrayList<String>(); args.add("BITOP"); args.add(op); args.add(destkey)
        for (k in keys) { args.add(k) }
        let resp = executeString(collectArray(args.iterator()))
        expectInt(resp, "BITOP")
    }

    /// 查找第一个为 0 或 1 的位
    public func bitpos(key: String, bit: Bool, start!: Option<Int64> = None,
                       end!: Option<Int64> = None): Int64 {
        let args = ArrayList<String>(); args.add("BITPOS"); args.add(key)
        args.add(if (bit) { "1" } else { "0" })
        match (start) { case Some(s) => args.add("${s}") case None => () }
        match (end) { case Some(e) => args.add("${e}") case None => () }
        let resp = executeString(collectArray(args.iterator()))
        expectInt(resp, "BITPOS")
    }
}
