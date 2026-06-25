package redis.client

/// 连接状态枚举（状态模式）
///
/// 定义 RedisConnection 的完整生命周期状态，保证状态转换的合法性。
///
/// # 状态转换图
/// ```text
/// NEW ──connect()──► CONNECTING ──onConnected()──► CONNECTED
///  │                                                  │
///  └──close()──► CLOSED ◄─────────────────────────────┘
///                      │
///                      └──reconnect()──► CONNECTING
/// ```
public enum ConnectionState {
    /// 初始状态：尚未发起连接
    | New
    /// 正在连接中：TCP 握手 + HELLO 协商进行中
    | Connecting
    /// 已连接：可以执行命令
    | Connected
    /// 发布订阅模式：后台线程读取 Push 数据
    | Subscribed
    /// 事务模式：MULTI 已发送，等待 EXEC/DISCARD
    | InTransaction
    /// 流水线模式：批量命令已写入，等待读取响应
    | Pipelining
    /// 已关闭：连接已终止
    | Closed
}

// ====================================================================
// 状态转换辅助
// ====================================================================

/// 检查状态转换是否合法
public func canTransition(from: ConnectionState, to: ConnectionState): Bool {
    match ((from, to)) {
        // 正常连接流程
        case (ConnectionState.New, ConnectionState.Connecting) => true
        case (ConnectionState.Connecting, ConnectionState.Connected) => true

        // 关闭（任何时候都可关闭）
        case (_, ConnectionState.Closed) => true

        // 模式切换（从 Connected 出发）
        case (ConnectionState.Connected, ConnectionState.Subscribed) => true
        case (ConnectionState.Connected, ConnectionState.InTransaction) => true
        case (ConnectionState.Connected, ConnectionState.Pipelining) => true

        // 模式恢复
        case (ConnectionState.Subscribed, ConnectionState.Connected) => true
        case (ConnectionState.InTransaction, ConnectionState.Connected) => true
        case (ConnectionState.Pipelining, ConnectionState.Connected) => true

        // 重连
        case (ConnectionState.Closed, ConnectionState.Connecting) => true

        case _ => false
    }
}

/// 获取状态的中文描述
public func stateDescription(state: ConnectionState): String {
    match (state) {
        case ConnectionState.New => "新建"
        case ConnectionState.Connecting => "连接中"
        case ConnectionState.Connected => "已连接"
        case ConnectionState.Subscribed => "订阅中"
        case ConnectionState.InTransaction => "事务中"
        case ConnectionState.Pipelining => "流水线中"
        case ConnectionState.Closed => "已关闭"
    }
}
