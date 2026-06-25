package redis.client

/// 连接状态机单元测试
@Test
class StateMachineTests {
    /// 合法转换：New → Connecting
    @TestCase
    func newToConnecting() {
        @Expect(canTransition(ConnectionState.New, ConnectionState.Connecting), true)
    }

    /// 合法转换：Connecting → Connected
    @TestCase
    func connectingToConnected() {
        @Expect(canTransition(ConnectionState.Connecting, ConnectionState.Connected), true)
    }

    /// 合法转换：任意 → Closed
    @TestCase
    func anyToClosed() {
        let states: Array<ConnectionState> = [
            ConnectionState.New, ConnectionState.Connecting, ConnectionState.Connected,
            ConnectionState.Subscribed, ConnectionState.InTransaction, ConnectionState.Pipelining,
        ]
        for (s in states) {
            @Expect(canTransition(s, ConnectionState.Closed), true)
        }
    }

    /// 合法转换：Connected → Subscribed
    @TestCase
    func connectedToSubscribed() {
        @Expect(canTransition(ConnectionState.Connected, ConnectionState.Subscribed), true)
    }

    /// 合法转换：Connected → InTransaction
    @TestCase
    func connectedToInTransaction() {
        @Expect(canTransition(ConnectionState.Connected, ConnectionState.InTransaction), true)
    }

    /// 合法转换：Connected → Pipelining
    @TestCase
    func connectedToPipelining() {
        @Expect(canTransition(ConnectionState.Connected, ConnectionState.Pipelining), true)
    }

    /// 合法转换：Subscribed → Connected
    @TestCase
    func subscribedToConnected() {
        @Expect(canTransition(ConnectionState.Subscribed, ConnectionState.Connected), true)
    }

    /// 合法转换：InTransaction → Connected
    @TestCase
    func inTransactionToConnected() {
        @Expect(canTransition(ConnectionState.InTransaction, ConnectionState.Connected), true)
    }

    /// 合法转换：Pipelining → Connected
    @TestCase
    func pipeliningToConnected() {
        @Expect(canTransition(ConnectionState.Pipelining, ConnectionState.Connected), true)
    }

    /// 非法转换：New → Connected（跳过 Connecting）
    @TestCase
    func newToConnectedInvalid() {
        @Expect(canTransition(ConnectionState.New, ConnectionState.Connected), false)
    }

    /// 非法转换：Closed → Connected（应走 Closed → Connecting → Connected）
    @TestCase
    func closedToConnectedInvalid() {
        @Expect(canTransition(ConnectionState.Closed, ConnectionState.Connected), false)
    }

    /// 非法转换：Subscribed → Pipelining（应先回到 Connected）
    @TestCase
    func subscribedToPipeliningInvalid() {
        @Expect(canTransition(ConnectionState.Subscribed, ConnectionState.Pipelining), false)
    }

    /// 非法转换：InTransaction → Subscribed
    @TestCase
    func inTransactionToSubscribedInvalid() {
        @Expect(canTransition(ConnectionState.InTransaction, ConnectionState.Subscribed), false)
    }

    /// 非法转换：Pipelining → Subscribed
    @TestCase
    func pipeliningToSubscribedInvalid() {
        @Expect(canTransition(ConnectionState.Pipelining, ConnectionState.Subscribed), false)
    }

    /// stateDescription 中文描述
    @TestCase
    func stateDescriptions() {
        @Expect(stateDescription(ConnectionState.New), "新建")
        @Expect(stateDescription(ConnectionState.Connecting), "连接中")
        @Expect(stateDescription(ConnectionState.Connected), "已连接")
        @Expect(stateDescription(ConnectionState.Subscribed), "订阅中")
        @Expect(stateDescription(ConnectionState.InTransaction), "事务中")
        @Expect(stateDescription(ConnectionState.Pipelining), "流水线中")
        @Expect(stateDescription(ConnectionState.Closed), "已关闭")
    }
}
