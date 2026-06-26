package redis.client
import std.collection.*
import std.convert.*

// ====================================================================
// 地理 (Geo) / 位图 (Bitmap) / HyperLogLog 命令
// ====================================================================

// ── 地理命令 (Geo) ──

extend RedisClient {
    /// 添加地理坐标
    public func geoadd(key: String, members: Array<(Float64, Float64, Blob)>): Int64 {
        let args = ArrayList<Blob>()
        args.add(Blob.fromUtf8("GEOADD")); args.add(Blob.fromUtf8(key))
        for ((lon, lat, member) in members) {
            args.add(Blob.fromUtf8("${lon}")); args.add(Blob.fromUtf8("${lat}")); args.add(member)
        }
        let resp = execute(collectArray(args.iterator()))
        expectInt(resp, "GEOADD")
    }

    /// 获取地理坐标
    public func geopos(key: String, members: Array<Blob>): Array<Option<(Float64, Float64)>> {
        let args = ArrayList<Blob>()
        args.add(Blob.fromUtf8("GEOPOS")); args.add(Blob.fromUtf8(key))
        for (m in members) { args.add(m) }
        let resp = execute(collectArray(args.iterator()))
        match (resp) {
            case RESPValue.Array(Some(items)) =>
                let result = ArrayList<Option<(Float64, Float64)>>()
                for (item in items) {
                    match (item) {
                        case RESPValue.Array(Some(coords)) =>
                            if (coords.size >= 2) {
                                match ((asString(coords[0]), asString(coords[1]))) {
                                    case (Some(lon), Some(lat)) =>
                                        try { result.add(Some((Float64.parse(lon), Float64.parse(lat)))) }
                                        catch (_) { result.add(None) }
                                    case _ => result.add(None)
                                }
                            } else { result.add(None) }
                        case RESPValue.BulkString(None) => result.add(None)
                        case _ => result.add(None)
                    }
                }
                collectArray(result.iterator())
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("GEOPOS 返回意外类型")
        }
    }

    /// 计算两个成员之间的距离
    public func geodist(key: String, member1: Blob, member2: Blob,
                        unit!: String = "m"): Option<Float64> {
        let resp = execute([
            Blob.fromUtf8("GEODIST"), Blob.fromUtf8(key),
            member1, member2, Blob.fromUtf8(unit),
        ])
        match (resp) {
            case RESPValue.BulkString(Some(blob)) =>
                Some(Float64.parse(blob.toUtf8()))
            case RESPValue.BulkString(None) => None
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("GEODIST 返回意外类型")
        }
    }

    /// 获取地理坐标的 Geohash 字符串
    public func geohash(key: String, members: Array<Blob>): Array<Option<String>> {
        let args = ArrayList<Blob>(); args.add(Blob.fromUtf8("GEOHASH")); args.add(Blob.fromUtf8(key))
        for (m in members) { args.add(m) }
        let resp = execute(collectArray(args.iterator()))
        match (resp) {
            case RESPValue.Array(Some(items)) =>
                let result = ArrayList<Option<String>>()
                for (item in items) {
                    match (item) {
                        case RESPValue.BulkString(Some(blob)) => result.add(Some(blob.toUtf8()))
                        case RESPValue.BulkString(None) => result.add(None)
                        case _ => result.add(None)
                    }
                }
                collectArray(result.iterator())
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("GEOHASH 返回意外类型")
        }
    }

    /// 搜索地理坐标范围内的成员（Redis 6.2+）
    public func geosearch(key: String, fromMember!: Option<String> = None,
                          fromLonLat!: Option<(Float64, Float64)> = None,
                          radius!: Option<Float64> = None, unit!: String = "m",
                          box!: Option<(Float64, Float64)> = None,
                          order!: Option<String> = None,
                          count!: Option<Int64> = None, any!: Bool = false,
                          withDist!: Bool = false, withCoord!: Bool = false): Array<RESPValue> {
        let args = ArrayList<String>(); args.add("GEOSEARCH"); args.add(key)
        match (fromMember) {
            case Some(m) => args.add("FROMMEMBER"); args.add(m)
            case None => ()
        }
        match (fromLonLat) {
            case Some((lon, lat)) =>
                args.add("FROMLONLAT"); args.add("${lon}"); args.add("${lat}")
            case None => ()
        }
        match (radius) { case Some(r) => args.add("BYRADIUS"); args.add("${r}"); args.add(unit) case None => () }
        match (box) {
            case Some((width, height)) =>
                args.add("BYBOX"); args.add("${width}"); args.add("${height}"); args.add(unit)
            case None => ()
        }
        match (order) { case Some(o) => args.add(o) case None => () }
        match (count) {
            case Some(c) =>
                args.add("COUNT"); args.add("${c}")
                if (any) { args.add("ANY") }
            case None => ()
        }
        if (withDist) { args.add("WITHDIST") }
        if (withCoord) { args.add("WITHCOORD") }
        let resp = executeString(collectArray(args.iterator()))
        match (resp) {
            case RESPValue.Array(Some(items)) => items
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("GEOSEARCH 返回意外类型")
        }
    }

    /// 以指定经纬度为中心查找成员（Redis 6.2+，使用 GEOSEARCH）
    public func georadius(key: String, longitude: Float64, latitude: Float64,
                          radius: Float64, unit!: String = "m",
                          withDist!: Bool = false, withCoord!: Bool = false,
                          count!: Option<Int64> = None,
                          order!: Option<String> = None,
                          any!: Bool = false): Array<RESPValue> {
        let args = ArrayList<String>(); args.add("GEORADIUS"); args.add(key)
        args.add("${longitude}"); args.add("${latitude}")
        args.add("${radius}"); args.add(unit)
        match (count) {
            case Some(c) =>
                args.add("COUNT"); args.add("${c}")
                if (any) { args.add("ANY") }
            case None => ()
        }
        match (order) { case Some(o) => args.add(o) case None => () }
        if (withDist) { args.add("WITHDIST") }
        if (withCoord) { args.add("WITHCOORD") }
        let resp = executeString(collectArray(args.iterator()))
        match (resp) {
            case RESPValue.Array(Some(items)) => items
            case RESPValue.Set(items) => items
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("GEORADIUS 返回意外类型")
        }
    }

    /// 以指定经纬度为中心只读查找成员
    public func georadiusRo(key: String, longitude: Float64, latitude: Float64,
                            radius: Float64, unit!: String = "m",
                            withDist!: Bool = false, withCoord!: Bool = false,
                            count!: Option<Int64> = None,
                            order!: Option<String> = None,
                            any!: Bool = false): Array<RESPValue> {
        let args = ArrayList<String>(); args.add("GEORADIUS_RO"); args.add(key)
        args.add("${longitude}"); args.add("${latitude}")
        args.add("${radius}"); args.add(unit)
        match (count) {
            case Some(c) =>
                args.add("COUNT"); args.add("${c}")
                if (any) { args.add("ANY") }
            case None => ()
        }
        match (order) { case Some(o) => args.add(o) case None => () }
        if (withDist) { args.add("WITHDIST") }
        if (withCoord) { args.add("WITHCOORD") }
        let resp = executeString(collectArray(args.iterator()))
        match (resp) {
            case RESPValue.Array(Some(items)) => items
            case RESPValue.Set(items) => items
            case RESPValue.Error(e) => throw createCommandError(e)
            case RESPValue.BulkError(e) => throw createCommandError(e.toUtf8())
            case _ => throw ProtocolError("GEORADIUS_RO 返回意外类型")
        }
    }

    /// 以指定成员为中心查找附近成员
    public func georadiusbymember(key: String, member: String, radius: Float64,
                                  unit!: String = "m",
                                  withDist!: Bool = false, withCoord!: Bool = false,
                                  count!: Option<Int64> = None,
                                  order!: Option<String> = None,
                                  any!: Bool = false): Array<RESPValue> {
        let args = ArrayList<String>(); args.add("GEORADIUSBYMEMBER"); args.add(key)
        args.add(member); args.add("${radius}"); args.add(unit)
        match (count) {
            case Some(c) =>
                args.add("COUNT"); args.add("${c}")
                if (any) { args.add("ANY") }
            case None => ()
        }
        match (order) { case Some(o) => args.add(o) case None => () }
        if (withDist) { args.add("WITHDIST") }
        if (withCoord) { args.add("WITHCOORD") }
        let resp = executeString(collectArray(args.iterator()))
        match (resp) {
            case RESPValue.Array(Some(items)) => items
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("GEORADIUSBYMEMBER 返回意外类型")
        }
    }

    /// 以指定成员为中心只读查找附近成员
    public func georadiusbymemberRo(key: String, member: String, radius: Float64,
                                    unit!: String = "m",
                                    withDist!: Bool = false, withCoord!: Bool = false,
                                    count!: Option<Int64> = None,
                                    order!: Option<String> = None,
                                    any!: Bool = false): Array<RESPValue> {
        let args = ArrayList<String>(); args.add("GEORADIUSBYMEMBER_RO"); args.add(key)
        args.add(member); args.add("${radius}"); args.add(unit)
        match (count) {
            case Some(c) =>
                args.add("COUNT"); args.add("${c}")
                if (any) { args.add("ANY") }
            case None => ()
        }
        match (order) { case Some(o) => args.add(o) case None => () }
        if (withDist) { args.add("WITHDIST") }
        if (withCoord) { args.add("WITHCOORD") }
        let resp = executeString(collectArray(args.iterator()))
        match (resp) {
            case RESPValue.Array(Some(items)) => items
            case RESPValue.Set(items) => items
            case RESPValue.Error(e) => throw createCommandError(e)
            case RESPValue.BulkError(e) => throw createCommandError(e.toUtf8())
            case _ => throw ProtocolError("GEORADIUSBYMEMBER_RO 返回意外类型")
        }
    }

    /// 将 GEOSEARCH 结果存储到新键
    public func geosearchstore(destination: String, source: String,
                               fromMember!: Option<String> = None,
                               fromLonLat!: Option<(Float64, Float64)> = None,
                               radius!: Option<Float64> = None, unit!: String = "m",
                               box!: Option<(Float64, Float64)> = None,
                               count!: Option<Int64> = None, any!: Bool = false,
                               storedist!: Bool = false): Int64 {
        let args = ArrayList<String>(); args.add("GEOSEARCHSTORE"); args.add(destination); args.add(source)
        match (fromMember) {
            case Some(m) => args.add("FROMMEMBER"); args.add(m)
            case None => ()
        }
        match (fromLonLat) {
            case Some((lon, lat)) =>
                args.add("FROMLONLAT"); args.add("${lon}"); args.add("${lat}")
            case None => ()
        }
        match (radius) { case Some(r) => args.add("BYRADIUS"); args.add("${r}"); args.add(unit) case None => () }
        match (box) {
            case Some((width, height)) =>
                args.add("BYBOX"); args.add("${width}"); args.add("${height}"); args.add(unit)
            case None => ()
        }
        match (count) {
            case Some(c) =>
                args.add("COUNT"); args.add("${c}")
                if (any) { args.add("ANY") }
            case None => ()
        }
        if (storedist) { args.add("STOREDIST") }
        let resp = executeString(collectArray(args.iterator()))
        expectInt(resp, "GEOSEARCHSTORE")
    }
}

// ── HyperLogLog 命令 ──

extend RedisClient {
    /// 添加元素到 HyperLogLog 数据结构
    public func pfadd(key: String, elements: Array<Blob>): Bool {
        let args = ArrayList<Blob>()
        args.add(Blob.fromUtf8("PFADD")); args.add(Blob.fromUtf8(key))
        for (e in elements) { args.add(e) }
        let resp = execute(collectArray(args.iterator()))
        expectBool(resp, "PFADD")
    }

    /// 返回 HyperLogLog 的基数估算值
    public func pfcount(keys: Array<String>): Int64 {
        let args = ArrayList<String>(); args.add("PFCOUNT")
        for (k in keys) { args.add(k) }
        let resp = executeString(collectArray(args.iterator()))
        expectInt(resp, "PFCOUNT")
    }

    /// 合并多个 HyperLogLog
    public func pfmerge(destkey: String, sourcekeys: Array<String>): Unit {
        let args = ArrayList<String>(); args.add("PFMERGE"); args.add(destkey)
        for (k in sourcekeys) { args.add(k) }
        let resp = executeString(collectArray(args.iterator()))
        expectOK(resp, "PFMERGE")
    }
}
