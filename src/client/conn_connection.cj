package redis.client
import std.collection.*
import std.sync.*

/// Redis 连接（核心类，状态模式 + 策略模式）
///
/// 封装了传输层、协议层、解码器，提供命令执行能力。
/// 通过状态机管理连接生命周期，支持线程安全操作。
///
/// # 线程安全
/// 使用 Mutex 保证状态变更和命令执行的线程安全。
/// 所有公共方法在关键路径上使用 `synchronized (lock)` 保护。
public class RedisConnection <: Resource {
    private let transport: Transport
    private let decoder: RespDecoder
    private var state: ConnectionState
    private var protoVersion: Int64
    private var connectTimeout: Option<Duration>
    private var autoHello: Bool
    private var authUsername: Option<String>
    private var authPassword: Option<String>
    private var lastAttributes: Option<Array<(RESPValue, RESPValue)>>
    private let lock: Mutex

    public init(transport: Transport,
                autoHello!: Bool = true,
                connectTimeout!: Option<Duration> = None,
                authUsername!: Option<String> = None,
                authPassword!: Option<String> = None) {
        this.transport = transport
        this.decoder = RespDecoder(transport)
        this.state = ConnectionState.New
        this.protoVersion = 2
        this.autoHello = autoHello
        this.connectTimeout = connectTimeout
        this.authUsername = authUsername
        this.authPassword = authPassword
        this.lastAttributes = None
        this.lock = Mutex()
    }

    // ====================================================================
    // 状态管理（整合 canTransition 验证）
    // ====================================================================

    /// 安全的状态转换，使用 canTransition 验证合法性
    private func transitionState(newState: ConnectionState): Unit {
        if (!canTransition(state, newState)) {
            throw ProtocolError(
                "非法状态转换: ${stateDescription(state)} → ${stateDescription(newState)}"
            )
        }
        state = newState
    }

    // ====================================================================
    // 连接生命周期
    // ====================================================================

    public func connect(): Unit {
        synchronized (lock) {
            match (state) {
                case ConnectionState.Closed | ConnectionState.New => ()
                case _ => return
            }

            transitionState(ConnectionState.Connecting)

            try {
                // 配置连接超时
                match (transport as TcpTransport) {
                    case Some(tcp) => tcp.setConnectTimeout(connectTimeout)
                    case None => ()
                }

                transport.connect()

                if (autoHello) {
                    negotiateProtocol()
                }

                transitionState(ConnectionState.Connected)
            } catch (e: Exception) {
                state = ConnectionState.Closed
                throw e
            }
        }
    }

    public func reconnect(): Unit {
        synchronized (lock) {
            close()
            connect()
        }
    }

    public func close(): Unit {
        synchronized (lock) {
            match (state) {
                case ConnectionState.Closed => ()
                case _ =>
                    transport.close()
                    state = ConnectionState.Closed
            }
        }
    }

    public func isClosed(): Bool {
        synchronized (lock) {
            match (state) {
                case ConnectionState.Closed => true
                case _ => !transport.isConnected()
            }
        }
    }

    // ====================================================================
    // 协议协商
    // ====================================================================

    private func negotiateProtocol(): Unit {
        let args = ArrayList<Blob>()
        args.add(Blob.fromUtf8("HELLO"))
        args.add(Blob.fromUtf8("3"))
        match (authPassword) {
            case Some(password) =>
                args.add(Blob.fromUtf8("AUTH"))
                args.add(Blob.fromUtf8(match (authUsername) {
                    case Some(username) => username
                    case None => "default"
                }))
                args.add(Blob.fromUtf8(password))
            case None => ()
        }
        let helloArgs = collectArray(args.iterator())

        try {
            let resp = sendRawCommand(helloArgs)
            match (resp) {
                case RESPValue.Map(_) | RESPValue.Array(Some(_)) =>
                    protoVersion = 3
                    println("协议协商成功: RESP3")
                case RESPValue.Error(msg) =>
                    if (msg.startsWith("NOPROTO")) {
                        protoVersion = 2
                        authenticateResp2Fallback()
                        println("协议协商: 服务器不支持 RESP3，使用 RESP2")
                    } else if (msg.contains("unknown command")) {
                        protoVersion = 2
                        authenticateResp2Fallback()
                        println("协议协商: 旧版 Redis，使用 RESP2")
                    } else {
                        throw ProtocolError("HELLO 协商失败: ${msg}")
                    }
                case _ =>
                    protoVersion = 2
            }
        } catch (e: ConnectionError) {
            protoVersion = 2
            println("协议协商: HELLO 不可用，使用 RESP2")
        }
    }

    private func authenticateResp2Fallback(): Unit {
        match (authPassword) {
            case Some(password) =>
                let args = ArrayList<Blob>()
                args.add(Blob.fromUtf8("AUTH"))
                match (authUsername) {
                    case Some(username) =>
                        args.add(Blob.fromUtf8(username))
                        args.add(Blob.fromUtf8(password))
                    case None =>
                        args.add(Blob.fromUtf8(password))
                }
                let resp = sendRawCommand(collectArray(args.iterator()))
                match (resp) {
                    case RESPValue.SimpleString(_) => ()
                    case RESPValue.Error(msg) => throw createCommandError(msg)
                    case RESPValue.BulkError(blob) => throw createCommandError(blob.toUtf8())
                    case _ => throw ProtocolError("AUTH 返回意外类型")
                }
            case None => ()
        }
    }

    public func getProtocolVersion(): Int64 {
        protoVersion
    }

    // ====================================================================
    // 命令执行
    // ====================================================================

    public func execute(args: Array<Blob>): RESPValue {
        synchronized (lock) {
            match (state) {
                case ConnectionState.Connected
                   | ConnectionState.Subscribed
                   | ConnectionState.InTransaction => ()
                case ConnectionState.Closed =>
                    throw ConnectionError("连接已关闭", transport.remoteAddress(), 0u16)
                case _ =>
                    throw ConnectionError(
                        "连接未就绪（状态: ${stateDescription(state)}）",
                        transport.remoteAddress(), 0u16
                    )
            }
            sendRawCommand(args)
        }
    }

    private func sendRawCommand(args: Array<Blob>): RESPValue {
        sendRawCommand(args, includePush: false)
    }

    private func sendRawCommand(args: Array<Blob>, includePush!: Bool): RESPValue {
        let data = RespEncoder.encodeCommand(args)
        transport.write(data)
        let resp = if (includePush) {
            decoder.readValueIncludingPush()
        } else {
            decoder.readValue()
        }
        decoder.compact()
        // 保存并清除属性，确保未丢失 RESP3 属性数据
        lastAttributes = decoder.getAttributes()
        decoder.clearAttributes()
        resp
    }

    internal func executeReturningPush(args: Array<Blob>): RESPValue {
        synchronized (lock) {
            match (state) {
                case ConnectionState.Connected
                   | ConnectionState.Subscribed => ()
                case ConnectionState.Closed =>
                    throw ConnectionError("连接已关闭", transport.remoteAddress(), 0u16)
                case _ =>
                    throw ConnectionError(
                        "连接未就绪（状态: ${stateDescription(state)}）",
                        transport.remoteAddress(), 0u16
                    )
            }
            sendRawCommand(args, includePush: true)
        }
    }

    internal func readNextPush(): RESPValue {
        synchronized (lock) {
            match (state) {
                case ConnectionState.Subscribed => ()
                case ConnectionState.Closed =>
                    throw ConnectionError("连接已关闭", transport.remoteAddress(), 0u16)
                case _ =>
                    throw ConnectionError(
                        "连接未处于订阅状态（状态: ${stateDescription(state)}）",
                        transport.remoteAddress(), 0u16
                    )
            }
            let resp = decoder.readValueIncludingPush()
            decoder.compact()
            lastAttributes = decoder.getAttributes()
            decoder.clearAttributes()
            resp
        }
    }

    public func executeBatch(commands: Array<Array<Blob>>): Array<RESPValue> {
        synchronized (lock) {
            match (state) {
                case ConnectionState.Connected => ()
                case ConnectionState.Closed =>
                    throw ConnectionError("连接已关闭", transport.remoteAddress(), 0u16)
                case _ =>
                    throw ConnectionError(
                        "Pipeline 不允许在 ${stateDescription(state)} 状态下执行",
                        transport.remoteAddress(), 0u16
                    )
            }

            transitionState(ConnectionState.Pipelining)

            try {
                for (cmd in commands) {
                    let data = RespEncoder.encodeCommand(cmd)
                    transport.write(data)
                }

                let responses = ArrayList<RESPValue>()
                for (_ in commands) {
                    let resp = decoder.readValue()
                    decoder.compact()
                    // Pipeline 中每个命令的独立属性（覆盖前一个）
                    lastAttributes = decoder.getAttributes()
                    decoder.clearAttributes()
                    responses.add(resp)
                }

                transitionState(ConnectionState.Connected)
                collectArray(responses.iterator())
            } catch (e: Exception) {
                state = ConnectionState.Connected
                throw e
            }
        }
    }

    // ====================================================================
    // 配置方法
    // ====================================================================

    public func setReadTimeout(timeout: Option<Duration>): Unit {
        transport.setReadTimeout(timeout)
    }

    public func setWriteTimeout(timeout: Option<Duration>): Unit {
        transport.setWriteTimeout(timeout)
    }

    // ====================================================================
    // 属性（供包内扩展使用）
    // ====================================================================

    public func getState(): ConnectionState { state }
    internal func setState(s: ConnectionState): Unit { state = s }
    internal func getDecoder(): RespDecoder { decoder }
    internal func getTransport(): Transport { transport }

    /// 获取最后一次命令执行的 RESP3 属性数据
    public func getAttributes(): Option<Array<(RESPValue, RESPValue)>> {
        lastAttributes
    }
}
