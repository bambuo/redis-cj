package redis.client
import std.collection.*

/// 记录写入命令的 Mock 传输层（用于协议握手测试）
public class RecordingTransport <: Transport {
    private var data: ArrayList<Byte>
    private var readPos: Int64
    private var writes: ArrayList<String>
    private var connected: Bool

    public init(data: Array<Byte>) {
        this.data = ArrayList<Byte>()
        for (b in data) { this.data.add(b) }
        this.readPos = 0
        this.writes = ArrayList<String>()
        this.connected = false
    }

    public func connect(): Unit { connected = true }
    public func close(): Unit { connected = false }
    public func isConnected(): Bool { connected }
    public func remoteAddress(): String { "recording:0" }
    public func setReadTimeout(timeout: Option<Duration>): Unit {} // cjlint-ignore !G.FUN.02 模拟实现
    public func setWriteTimeout(timeout: Option<Duration>): Unit {} // cjlint-ignore !G.FUN.02 模拟实现

    public func read(buf: Array<Byte>): Int64 {
        var count: Int64 = 0
        while (readPos < data.size && count < buf.size) {
            buf[count] = data[readPos]
            readPos++
            count++
        }
        count
    }

    public func write(buf: Array<Byte>): Unit {
        writes.add(Blob.fromBytes(buf).toUtf8())
    }

    public func getWriteCount(): Int64 {
        writes.size
    }

    public func getWrite(index: Int64): String {
        writes[index]
    }
}

class PubSubCapture {
    public var channel: String
    public var message: String

    public init() {
        this.channel = ""
        this.message = ""
    }
}

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

    /// HELLO 不可用时应回退 RESP2 并发送 AUTH
    @TestCase
    func helloUnknownFallsBackToAuth() {
        let data = Blob.fromUtf8("-ERR unknown command 'HELLO'\r\n+OK\r\n").toBytes()
        let conn = RedisConnection(MockTransport(data), authPassword: Some("secret"))
        conn.connect()
        @Expect(conn.getProtocolVersion(), 2)
        @Expect(stateDescription(conn.getState()), "已连接")
        conn.close()
    }

    /// HELLO 返回 NOPROTO 时应回退 RESP2 并发送独立 AUTH
    @TestCase
    func helloNoProtoFallsBackToAuth() {
        let data = Blob.fromUtf8("-NOPROTO unsupported protocol version\r\n+OK\r\n").toBytes()
        let transport = RecordingTransport(data)
        let conn = RedisConnection(transport, authPassword: Some("secret"))
        conn.connect()
        @Expect(conn.getProtocolVersion(), 2)
        @Expect(stateDescription(conn.getState()), "已连接")
        @Expect(transport.getWriteCount(), 2)
        @Expect(transport.getWrite(1), "*2\r\n$4\r\nAUTH\r\n$6\r\nsecret\r\n")
        conn.close()
    }

    /// 多频道订阅应消费全部订阅确认帧，下一次读取直接得到业务消息
    @TestCase
    func subscribeConsumesAllAcks() {
        let data = Blob.fromUtf8(
            "*3\r\n$9\r\nsubscribe\r\n$2\r\nc1\r\n:1\r\n" +
            "*3\r\n$9\r\nsubscribe\r\n$2\r\nc2\r\n:2\r\n" +
            ">3\r\n$7\r\nmessage\r\n$2\r\nc2\r\n$2\r\nm2\r\n"
        ).toBytes()
        let conn = RedisConnection(MockTransport(data), autoHello: false)
        conn.connect()
        let client = RedisClient(conn)
        let captured = PubSubCapture()

        client.subscribe(["c1", "c2"], { ch, msg =>
            captured.channel = ch.toUtf8()
            captured.message = msg.toUtf8()
        })
        let msg = client.readPubSubMessage()

        match (msg) {
            case RESPValue.Push(items) =>
                @Expect(items.size, 3)
                @Expect(asString(items[0]).getOrThrow(), "message")
            case _ => @Fail("应读取到业务 Push 消息")
        }
        @Expect(captured.channel, "c2")
        @Expect(captured.message, "m2")
        client.close()
    }

    /// RESP3 pubsub pmessage 的 channel/message 索引应跳过 pattern
    @TestCase
    func resp3PmessageUsesChannelAndMessageIndexes() {
        let data = Blob.fromUtf8(
            ">4\r\n$6\r\npubsub\r\n$10\r\npsubscribe\r\n$2\r\nc*\r\n:1\r\n" +
            ">5\r\n$6\r\npubsub\r\n$8\r\npmessage\r\n$2\r\nc*\r\n$2\r\nc1\r\n$2\r\nm1\r\n"
        ).toBytes()
        let conn = RedisConnection(MockTransport(data), autoHello: false)
        conn.connect()
        let client = RedisClient(conn)
        let captured = PubSubCapture()

        client.psubscribe(["c*"], { ch, msg =>
            captured.channel = ch.toUtf8()
            captured.message = msg.toUtf8()
        })
        client.readPubSubMessage()

        @Expect(captured.channel, "c1")
        @Expect(captured.message, "m1")
        client.close()
    }

    /// MONITOR 可读取 RESP3 Push 形式的监控消息
    @TestCase
    func monitorReadsPushMessage() {
        let data = Blob.fromUtf8(
            "+OK\r\n" +
            ">2\r\n$7\r\nmonitor\r\n$38\r\n1750000000.000000 [0 127.0.0.1:1] PING\r\n"
        ).toBytes()
        let conn = RedisConnection(MockTransport(data), autoHello: false)
        conn.connect()
        let client = RedisClient(conn)

        client.monitor()
        @Expect(client.readMonitorMessage(), "1750000000.000000 [0 127.0.0.1:1] PING")
        client.close()
    }
}
