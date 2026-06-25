package redis
import redis.client.*

main(): Int64 {
    println("╔══════════════════════════════════════════╗")
    println("║    Redis 仓颉客户端 — 综合演示          ║")
    println("╚══════════════════════════════════════════╝")
    println("")

    try (client = RedisClient("127.0.0.1", 6379u16)) {
        demoBasic(client)
        demoStringValues(client)
        demoNumericValues(client)
        demoArrayValues(client)
        demoTransaction(client)
        demoErrorHandling(client)
        println("")
        println("所有演示执行成功！")
    } catch (e: RedisError) {
        println("Redis 错误: ${e.message}")
        return 1
    } catch (e: Exception) {
        println("一般错误: ${e.message}")
        return 1
    }
    return 0
}

func demoBasic(client: RedisClient): Unit {
    println("── 基础命令 ──────────────────────────────")
    let pong = client.ping()
    println("PING → ${pong}")
    client.select(0)
    println("SELECT 0 → OK")
}

func demoStringValues(client: RedisClient): Unit {
    println("")
    println("── 字符串值 ──────────────────────────────")
    client.executeString(["DEL", "cj_demo_key", "cj_demo_key2"])
    let r1 = client.executeString(["SET", "cj_demo_key", "你好，仓颉！Hello from Cangjie!"])
    println("SET → ${respValueToString(r1)}")
    let r2 = client.executeString(["GET", "cj_demo_key"])
    match (r2) {
        case RESPValue.BulkString(Some(blob)) => println("GET → \"${blob.toUtf8()}\"")
        case RESPValue.BulkString(None) => println("GET → (nil)")
        case other => println("GET → ${respValueToString(other)}")
    }
    let r3 = client.executeString(["GET", "nonexistent"])
    match (r3) {
        case RESPValue.BulkString(None) => println("GET nonexistent → (nil) ✓")
        case _ => println("GET nonexistent → 意外: ${respValueToString(r3)}")
    }
    let r4 = client.executeString(["TYPE", "cj_demo_key"])
    println("TYPE → ${respValueToString(r4)}")
    let r5 = client.executeString(["EXISTS", "cj_demo_key", "nonexistent"])
    match (r5) { case RESPValue.Integer(n) => println("EXISTS (2个键) → ${n}") case _ => println("EXISTS → ${respValueToString(r5)}") }
    client.executeString(["SET", "cj_demo_key2", "待删除"])
    let r6 = client.executeString(["DEL", "cj_demo_key2"])
    match (r6) { case RESPValue.Integer(n) => println("DEL → ${n} 个键已删除") case _ => println("DEL → ${respValueToString(r6)}") }
}

func demoNumericValues(client: RedisClient): Unit {
    println("")
    println("── 数值命令 ──────────────────────────────")
    client.executeString(["DEL", "counter"])
    for (r in [client.executeString(["INCR", "counter"]), client.executeString(["INCR", "counter"]), client.executeString(["DECR", "counter"])]) {
        match (r) { case RESPValue.Integer(n) => () case _ => () }
    }
    println("INCR/DECR 完成")
    let r4 = client.executeString(["TTL", "counter"])
    match (r4) { case RESPValue.Integer(n) => println("TTL counter → ${n}") case _ => () }
    let r5 = client.executeString(["SET", "temp_key", "将在10秒后过期", "EX", "10"])
    println("SET temp_key EX 10 → ${respValueToString(r5)}")
}

func demoArrayValues(client: RedisClient): Unit {
    println("")
    println("── 数组响应 ──────────────────────────────")
    let r1 = client.executeString(["KEYS", "cj_*"])
    match (r1) { case RESPValue.Array(Some(items)) => println("KEYS cj_* → ${items.size} 个键") case _ => () }
    let r2 = client.executeString(["MGET", "cj_demo_key", "counter", "nonexistent"])
    match (r2) {
        case RESPValue.Array(Some(items)) =>
            println("MGET (3个键) → ${items.size} 个结果:")
            for (i in 0..items.size) { println("  [${i}] ${respValueToString(items[i])}") }
        case other => println("MGET → ${respValueToString(other)}")
    }
}

func demoTransaction(client: RedisClient): Unit {
    println("")
    println("── 事务 (MULTI/EXEC) ─────────────────────")
    client.executeString(["DEL", "txn_key1", "txn_key2"])
    let txn = Transaction(client)
    txn.watch(["txn_key1"])
    txn.multi()
    txn.queue(["SET", "txn_key1", "事务值1"])
    txn.queue(["SET", "txn_key2", "事务值2"])
    txn.queue(["INCR", "txn_counter"])
    txn.queue(["GET", "txn_key1"])
    let results = txn.exec()
    println("事务 (4条命令) → ${results.size} 个结果:")
    for (i in 0..results.size) { println("  [${i}] ${respValueToString(results[i])}") }
}

func demoErrorHandling(client: RedisClient): Unit {
    println("")
    println("── 错误处理 ──────────────────────────────")
    let r1 = client.executeString(["这不是一个有效的命令"])
    match (r1) { case RESPValue.Error(msg) => println("无效命令 → Error: ${msg} ✓") case other => println("无效命令 → 意外: ${respValueToString(other)}") }
    client.executeString(["SET", "str_key", "我是字符串"])
    let r2 = client.executeString(["LPUSH", "str_key", "value"])
    match (r2) { case RESPValue.Error(msg) => println("WRONGTYPE → Error: ${msg} ✓") case other => println("WRONGTYPE → 意外: ${respValueToString(other)}") }
}
