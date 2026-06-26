package redis.client
import std.collection.*

// ====================================================================
// 连接命令 (Connection Commands) — 补充
// ====================================================================

extend RedisClient {
    /// 获取当前连接 ID
    public func clientId(): Int64 {
        let resp = executeString(["CLIENT", "ID"])
        expectInt(resp, "CLIENT ID")
    }

    /// 获取当前连接的客户端缓存失效重定向目标
    public func clientGetRedir(): Int64 {
        let resp = executeString(["CLIENT", "GETREDIR"])
        expectInt(resp, "CLIENT GETREDIR")
    }

    /// 追踪客户端（用于缓存失效通知）
    public func clientTracking(on: Bool, redirect!: Option<Int64> = None,
                               prefixes!: Array<String> = []): Unit {
        let args = ArrayList<String>(); args.add("CLIENT"); args.add("TRACKING")
        args.add(if (on) { "ON" } else { "OFF" })
        match (redirect) { case Some(id) => args.add("REDIRECT"); args.add("${id}") case None => () }
        for (p in prefixes) { args.add("PREFIX"); args.add(p) }
        let resp = executeString(collectArray(args.iterator()))
        expectOK(resp, "CLIENT TRACKING")
    }

    /// 获取客户端缓存追踪状态
    public func clientTrackingInfo(): RESPValue {
        let resp = executeString(["CLIENT", "TRACKINGINFO"])
        match (resp) {
            case RESPValue.Error(e) => throw createCommandError(e)
            case RESPValue.BulkError(e) => throw createCommandError(e.toUtf8())
            case _ => resp
        }
    }

    /// 上报客户端库名称（Redis 7.2+）
    public func clientSetInfoLibName(name: String): Unit {
        expectOK(executeString(["CLIENT", "SETINFO", "LIB-NAME", name]), "CLIENT SETINFO LIB-NAME")
    }

    /// 上报客户端库版本（Redis 7.2+）
    public func clientSetInfoLibVer(version: String): Unit {
        expectOK(executeString(["CLIENT", "SETINFO", "LIB-VER", version]), "CLIENT SETINFO LIB-VER")
    }

    /// 杀死客户端连接
    public func clientKill(addr!: Option<String> = None,
                          id!: Option<Int64> = None,
                          skipme!: Option<Bool> = None): Int64 {
        let args = ArrayList<String>(); args.add("CLIENT"); args.add("KILL")
        match (addr) { case Some(a) => args.add(a) case None => () }
        match (id) { case Some(i) => args.add("ID"); args.add("${i}") case None => () }
        match (skipme) {
            case Some(true) => args.add("SKIPME"); args.add("YES")
            case Some(false) => args.add("SKIPME"); args.add("NO")
            case None => ()
        }
        let resp = executeString(collectArray(args.iterator()))
        expectInt(resp, "CLIENT KILL")
    }

    /// 重置连接状态
    public func reset(): Unit {
        let resp = executeString(["RESET"])
        match (resp) {
            case RESPValue.SimpleString("RESET") => ()
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("RESET 返回意外类型")
        }
    }
}
