package redis.client
import std.collection.*

// ====================================================================
// Lua 脚本命令 (Scripting Commands)
// ====================================================================

extend RedisClient {
    /// 执行 Lua 脚本
    public func eval(script: String, keys!: Array<String> = [],
                     args!: Array<String> = []): RESPValue {
        let cmd = ArrayList<String>()
        cmd.add("EVAL"); cmd.add(script); cmd.add("${keys.size}")
        for (k in keys) { cmd.add(k) }
        for (a in args) { cmd.add(a) }
        executeString(collectArray(cmd.iterator()))
    }

    /// 执行已缓存的脚本
    public func evalsha(sha1: String, keys!: Array<String> = [],
                        args!: Array<String> = []): RESPValue {
        let cmd = ArrayList<String>()
        cmd.add("EVALSHA"); cmd.add(sha1); cmd.add("${keys.size}")
        for (k in keys) { cmd.add(k) }
        for (a in args) { cmd.add(a) }
        executeString(collectArray(cmd.iterator()))
    }

    /// 加载脚本到缓存。返回 SHA1 校验和。
    public func scriptLoad(script: String): String {
        let resp = executeString(["SCRIPT", "LOAD", script])
        expectBlobVal(resp, "SCRIPT LOAD").toUtf8()
    }

    public func scriptHelp(): Array<String> {
        expectStringArray(executeString(["SCRIPT", "HELP"]), "SCRIPT HELP")
    }

    /// 检查脚本是否已缓存
    public func scriptExists(sha1s: Array<String>): Array<Bool> {
        let args = ArrayList<String>(); args.add("SCRIPT"); args.add("EXISTS")
        for (s in sha1s) { args.add(s) }
        let resp = executeString(collectArray(args.iterator()))
        match (resp) {
            case RESPValue.Array(Some(items)) =>
                let result = ArrayList<Bool>()
                for (item in items) {
                    match (item) {
                        case RESPValue.Integer(1) => result.add(true)
                        case _ => result.add(false)
                    }
                }
                collectArray(result.iterator())
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("SCRIPT EXISTS 返回意外类型")
        }
    }

    /// 清空脚本缓存
    public func scriptFlush(mode!: Option<String> = None): Unit {
        let args = ArrayList<String>(); args.add("SCRIPT"); args.add("FLUSH")
        match (mode) { case Some(m) => args.add(m) case None => () }
        let resp = executeString(collectArray(args.iterator()))
        expectOK(resp, "SCRIPT FLUSH")
    }

    /// 终止正在执行的脚本
    public func scriptKill(): Unit {
        let resp = executeString(["SCRIPT", "KILL"])
        let _ = expectSimpleString(resp, "SCRIPT KILL")
        ()
    }

    /// 只读方式执行 Lua 脚本（Redis 7.0+）
    public func evalRo(script: String, keys!: Array<String> = [], args!: Array<String> = []): RESPValue {
        let cmd = ArrayList<String>()
        cmd.add("EVAL_RO"); cmd.add(script); cmd.add("${keys.size}")
        for (k in keys) { cmd.add(k) }
        for (a in args) { cmd.add(a) }
        executeString(collectArray(cmd.iterator()))
    }

    /// 只读方式执行已缓存脚本（Redis 7.0+）
    public func evalshaRo(sha1: String, keys!: Array<String> = [], args!: Array<String> = []): RESPValue {
        let cmd = ArrayList<String>()
        cmd.add("EVALSHA_RO"); cmd.add(sha1); cmd.add("${keys.size}")
        for (k in keys) { cmd.add(k) }
        for (a in args) { cmd.add(a) }
        executeString(collectArray(cmd.iterator()))
    }

    /// 调用函数（Redis 7.0+）
    public func fcall(function: String, keys!: Array<String> = [], args!: Array<String> = []): RESPValue {
        let cmd = ArrayList<String>()
        cmd.add("FCALL"); cmd.add(function); cmd.add("${keys.size}")
        for (k in keys) { cmd.add(k) }
        for (a in args) { cmd.add(a) }
        executeString(collectArray(cmd.iterator()))
    }

    /// 只读方式调用函数（Redis 7.0+）
    public func fcallRo(function: String, keys!: Array<String> = [], args!: Array<String> = []): RESPValue {
        let cmd = ArrayList<String>()
        cmd.add("FCALL_RO"); cmd.add(function); cmd.add("${keys.size}")
        for (k in keys) { cmd.add(k) }
        for (a in args) { cmd.add(a) }
        executeString(collectArray(cmd.iterator()))
    }

    /// 加载函数库（Redis 7.0+），返回库名称。
    public func functionLoad(libraryCode: String, replace!: Bool = false): String {
        let args = ArrayList<String>(); args.add("FUNCTION"); args.add("LOAD")
        if (replace) { args.add("REPLACE") }
        args.add(libraryCode)
        match (executeString(collectArray(args.iterator()))) {
            case RESPValue.SimpleString(name) => name
            case RESPValue.BulkString(Some(blob)) => blob.toUtf8()
            case RESPValue.Error(e) => throw createCommandError(e)
            case RESPValue.BulkError(e) => throw createCommandError(e.toUtf8())
            case resp => throw ProtocolError("FUNCTION LOAD 返回意外类型: ${respValueToString(resp)}")
        }
    }

    public func functionHelp(): Array<String> {
        expectStringArray(executeString(["FUNCTION", "HELP"]), "FUNCTION HELP")
    }

    /// 列出函数库（Redis 7.0+）。
    public func functionList(libraryNamePattern!: Option<String> = None,
                             withCode!: Bool = false): Array<RESPValue> {
        let args = ArrayList<String>(); args.add("FUNCTION"); args.add("LIST")
        match (libraryNamePattern) {
            case Some(pattern) => args.add("LIBRARYNAME"); args.add(pattern)
            case None => ()
        }
        if (withCode) { args.add("WITHCODE") }
        match (executeString(collectArray(args.iterator()))) {
            case RESPValue.Array(Some(items)) => items
            case RESPValue.Error(e) => throw createCommandError(e)
            case RESPValue.BulkError(e) => throw createCommandError(e.toUtf8())
            case _ => throw ProtocolError("FUNCTION LIST 返回意外类型")
        }
    }

    /// 删除函数库（Redis 7.0+）。
    public func functionDelete(libraryName: String): Unit {
        expectOK(executeString(["FUNCTION", "DELETE", libraryName]), "FUNCTION DELETE")
    }

    /// 清空函数库（Redis 7.0+）。
    public func functionFlush(mode!: Option<String> = None): Unit {
        let args = ArrayList<String>(); args.add("FUNCTION"); args.add("FLUSH")
        match (mode) { case Some(m) => args.add(m) case None => () }
        expectOK(executeString(collectArray(args.iterator())), "FUNCTION FLUSH")
    }

    /// 返回函数运行状态统计（Redis 7.0+）。
    public func functionStats(): RESPValue {
        let resp = executeString(["FUNCTION", "STATS"])
        match (resp) {
            case RESPValue.Array(_) | RESPValue.Map(_) => resp
            case RESPValue.Error(e) => throw createCommandError(e)
            case RESPValue.BulkError(e) => throw createCommandError(e.toUtf8())
            case _ => throw ProtocolError("FUNCTION STATS 返回意外类型")
        }
    }

    /// 导出所有函数库（Redis 7.0+）。
    public func functionDump(): Blob {
        expectBlobVal(executeString(["FUNCTION", "DUMP"]), "FUNCTION DUMP")
    }

    /// 从 DUMP 结果恢复函数库（Redis 7.0+）。
    public func functionRestore(serialized: Blob, policy!: Option<String> = None): Unit {
        let args = ArrayList<Blob>()
        args.add(Blob.fromUtf8("FUNCTION")); args.add(Blob.fromUtf8("RESTORE")); args.add(serialized)
        match (policy) {
            case Some(p) => args.add(Blob.fromUtf8(p))
            case None => ()
        }
        expectOK(execute(collectArray(args.iterator())), "FUNCTION RESTORE")
    }

    /// 终止正在运行的函数（Redis 7.0+）。
    public func functionKill(): Unit {
        expectOK(executeString(["FUNCTION", "KILL"]), "FUNCTION KILL")
    }
}
