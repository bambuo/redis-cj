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

    /// 获取当前连接的 CLIENT INFO 文本（Redis 6.2+）
    public func clientInfo(): String {
        let resp = executeString(["CLIENT", "INFO"])
        match (resp) {
            case RESPValue.BulkString(Some(blob)) => blob.toUtf8()
            case RESPValue.SimpleString(s) => s
            case RESPValue.VerbatimString(_, blob) => blob.toUtf8()
            case RESPValue.Error(e) => throw createCommandError(e)
            case RESPValue.BulkError(e) => throw createCommandError(e.toUtf8())
            case _ => throw ProtocolError("CLIENT INFO 返回意外类型")
        }
    }

    /// 获取当前连接的客户端缓存失效重定向目标
    public func clientGetRedir(): Int64 {
        let resp = executeString(["CLIENT", "GETREDIR"])
        expectInt(resp, "CLIENT GETREDIR")
    }

    /// 追踪客户端（用于缓存失效通知）
    public func clientTracking(on: Bool, redirect!: Option<Int64> = None,
                               prefixes!: Array<String> = [],
                               bcast!: Bool = false,
                               optin!: Bool = false,
                               optout!: Bool = false,
                               noloop!: Bool = false): Unit {
        let args = ArrayList<String>(); args.add("CLIENT"); args.add("TRACKING")
        args.add(if (on) { "ON" } else { "OFF" })
        match (redirect) { case Some(id) => args.add("REDIRECT"); args.add("${id}") case None => () }
        if (bcast) { args.add("BCAST") }
        if (optin) { args.add("OPTIN") }
        if (optout) { args.add("OPTOUT") }
        if (noloop) { args.add("NOLOOP") }
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

    /// 设置当前连接的下一条命令是否用于客户端缓存追踪
    public func clientCaching(enabled: Bool): Unit {
        expectOK(executeString(["CLIENT", "CACHING", if (enabled) { "YES" } else { "NO" }]), "CLIENT CACHING")
    }

    /// 取消 CLIENT PAUSE
    public func clientUnpause(): Unit {
        expectOK(executeString(["CLIENT", "UNPAUSE"]), "CLIENT UNPAUSE")
    }

    /// 设置当前连接是否禁止被淘汰（Redis 7.0+）
    public func clientNoEvict(enabled: Bool): Unit {
        expectOK(executeString(["CLIENT", "NO-EVICT", if (enabled) { "ON" } else { "OFF" }]), "CLIENT NO-EVICT")
    }

    /// 设置当前连接是否不刷新键空闲时间（Redis 7.2+）
    public func clientNoTouch(enabled: Bool): Unit {
        expectOK(executeString(["CLIENT", "NO-TOUCH", if (enabled) { "ON" } else { "OFF" }]), "CLIENT NO-TOUCH")
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
                          laddr!: Option<String> = None,
                          typeFilter!: Option<String> = None,
                          user!: Option<String> = None,
                          skipme!: Option<Bool> = None): Int64 {
        let args = ArrayList<String>(); args.add("CLIENT"); args.add("KILL")
        let useFilterSyntax = id.isSome() || laddr.isSome() || typeFilter.isSome() || user.isSome() || skipme.isSome()
        match (addr) {
            case Some(a) =>
                if (useFilterSyntax) {
                    args.add("ADDR"); args.add(a)
                } else {
                    args.add(a)
                }
            case None => ()
        }
        match (id) { case Some(i) => args.add("ID"); args.add("${i}") case None => () }
        match (laddr) { case Some(a) => args.add("LADDR"); args.add(a) case None => () }
        match (typeFilter) { case Some(t) => args.add("TYPE"); args.add(t) case None => () }
        match (user) { case Some(u) => args.add("USER"); args.add(u) case None => () }
        match (skipme) {
            case Some(true) => args.add("SKIPME"); args.add("YES")
            case Some(false) => args.add("SKIPME"); args.add("NO")
            case None => ()
        }
        let resp = executeString(collectArray(args.iterator()))
        match (resp) {
            case RESPValue.Integer(n) => n
            case RESPValue.SimpleString("OK") => 1
            case RESPValue.Error(e) => throw createCommandError(e)
            case RESPValue.BulkError(e) => throw createCommandError(e.toUtf8())
            case _ => throw ProtocolError("CLIENT KILL 返回意外类型")
        }
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
