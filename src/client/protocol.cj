package redis.client

/// 协议协商扩展
///
/// 提供 HELLO 命令和 RESP3 相关功能的封装。
extend RedisClient {
    /// 手动升级连接到 RESP3 协议
    ///
    /// 通常无需手动调用（自动协商会在 connect 时完成）。
    /// 在自动协商被禁用时，可使用此方法手动升级。
    ///
    /// @return HELLO 命令返回的服务器信息
    /// @throws ProtocolError 协议升级失败时
    public func hello(): RESPValue {
        let resp = executeString(["HELLO", "3"])
        match (resp) {
            case RESPValue.Map(pairs) =>
                println("成功升级到 RESP3")
                resp
            case RESPValue.Error(msg) =>
                throw ProtocolError("HELLO 命令失败: ${msg}")
            case _ =>
                // 某些版本的 HELLO 可能返回 Array
                resp
        }
    }

    /// 使用用户名和密码进行 AUTH（Redis 6+ ACL）
    ///
    /// @param username ACL 用户名
    /// @param password ACL 密码
    /// @throws AuthError 认证失败时
    public func authWithUser(username: String, password: String): Unit {
        let resp = executeString(["AUTH", username, password])
        match (resp) {
            case RESPValue.SimpleString(_) => ()
            case RESPValue.Error(e) => throw AuthError(e)
            case _ => throw ProtocolError("AUTH 返回意外类型")
        }
    }

    /// 使用密码进行 AUTH（传统方式）
    ///
    /// @param password Redis 密码
    /// @throws AuthError 认证失败时
    public func auth(password: String): Unit {
        let resp = executeString(["AUTH", password])
        match (resp) {
            case RESPValue.SimpleString(_) => ()
            case RESPValue.Error(e) => throw AuthError(e)
            case _ => throw ProtocolError("AUTH 返回意外类型")
        }
    }

    /// 发送 PING 检测连接是否存活
    ///
    /// @return 服务器返回的字符串（通常是 "PONG"）
    /// @throws ConnectionError 连接异常时
    public func ping(): String {
        let resp = executeString(["PING"])
        match (resp) {
            case RESPValue.SimpleString(s) => s
            case RESPValue.BulkString(Some(blob)) => blob.toUtf8()
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("PING 返回意外类型")
        }
    }

    /// 选择数据库
    ///
    /// @param index 数据库编号（0-15）
    public func select(index: Int64): Unit {
        let resp = executeString(["SELECT", "${index}"])
        match (resp) {
            case RESPValue.SimpleString(_) => ()
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("SELECT 返回意外类型")
        }
    }

    /// 发送 ECHO 命令
    ///
    /// @param message 要回显的消息
    /// @return 服务器返回的相同消息
    public func echo(message: String): Blob {
        let resp = executeString(["ECHO", message])
        match (resp) {
            case RESPValue.BulkString(Some(blob)) => blob
            case RESPValue.Error(e) => throw CommandError(e)
            case _ => throw ProtocolError("ECHO 返回意外类型")
        }
    }

    /// 退出连接
    public func quit(): Unit {
        try {
            executeString(["QUIT"])
        } catch (_: Exception) {
            // 忽略关闭连接时的错误
        }
    }
}
