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
