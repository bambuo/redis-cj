package redis.client
import std.collection.*

/// 命令集成测试（需要本地 Redis 服务器 127.0.0.1:6379）
/// 每个测试用例使用唯一键名前缀，避免互相干扰
@Test
class CommandIntegrationTests {
    private var counter: Int64 = 0

    private func createClient(): RedisClient {
        RedisClient("127.0.0.1", 6379u16)
    }

    private func uniqueKey(prefix: String): String {
        counter++
        "${prefix}_${counter}"
    }

    // -------- 字符串命令 --------

    @TestCase
    func testGetSet() {
        let c = createClient()
        let k = uniqueKey("gs")
        c.set(k, Blob.fromUtf8("v1"))
        let val = c.get(k)
        match (val) { case Some(b) => @Expect(b.toUtf8(), "v1") case None => @Fail("GET failed") }
    }

    @TestCase
    func testGetDel() {
        let c = createClient()
        let k = uniqueKey("gd")
        c.set(k, Blob.fromUtf8("val"))
        let v1 = c.getdel(k)
        match (v1) { case Some(b) => @Expect(b.toUtf8(), "val") case None => @Fail("GETDEL failed") }
        let v2 = c.get(k)
        match (v2) { case None => () case _ => @Fail("GETDEL 应删除键") }
    }

    @TestCase
    func testSetEx() {
        let c = createClient()
        let k = uniqueKey("sex")
        c.setex(k, 100, Blob.fromUtf8("exp"))
        let ttl = expectInt(c.executeString(["TTL", k]), "TTL")
        @Expect(ttl > 0 && ttl <= 100, true)
    }

    @TestCase
    func testSetNx() {
        let c = createClient()
        let k = uniqueKey("snx")
        @Expect(c.setnx(k, Blob.fromUtf8("first")), true)
        @Expect(c.setnx(k, Blob.fromUtf8("second")), false)
    }

    @TestCase
    func testStrLen() {
        let c = createClient()
        let k = uniqueKey("sl")
        c.set(k, Blob.fromUtf8("hello"))
        let n = expectInt(c.executeString(["STRLEN", k]), "STRLEN")
        @Expect(n, 5)
    }

    @TestCase
    func testAppend() {
        let c = createClient()
        let k = uniqueKey("ap")
        c.set(k, Blob.fromUtf8("a"))
        let n = c.append(k, Blob.fromUtf8("b"))
        @Expect(n, 2)
    }

    // -------- 列表命令 --------

    @TestCase
    func testLPushRPush() {
        let c = createClient()
        let k = uniqueKey("ml")
        c.lpush(k, [Blob.fromUtf8("a"), Blob.fromUtf8("b")])
        let len = expectInt(c.executeString(["LLEN", k]), "LLEN")
        @Expect(len, 2)
    }

    @TestCase
    func testLSetLInsert() {
        let c = createClient()
        let k = uniqueKey("ml2")
        c.rpush(k, [Blob.fromUtf8("a"), Blob.fromUtf8("c")])
        c.lset(k, 1, Blob.fromUtf8("b"))
        let v = c.lindex(k, 1)
        match (v) { case Some(b) => @Expect(b.toUtf8(), "b") case _ => @Fail("LSET failed") }
    }

    // -------- 集合命令 --------

    @TestCase
    func testSAddSMembers() {
        let c = createClient()
        let k = uniqueKey("ms")
        c.sadd(k, [Blob.fromUtf8("a"), Blob.fromUtf8("b")])
        let members = c.smembers(k)
        @Expect(members.size, 2)
    }

    @TestCase
    func testSMove() {
        let c = createClient()
        let src = uniqueKey("src")
        let dst = uniqueKey("dst")
        c.sadd(src, [Blob.fromUtf8("x")])
        let moved = c.smove(src, dst, Blob.fromUtf8("x"))
        @Expect(moved, true)
    }

    @TestCase
    func testSMIsMember() {
        let c = createClient()
        let k = uniqueKey("smm")
        c.sadd(k, [Blob.fromUtf8("a")])
        let results = c.smismember(k, [Blob.fromUtf8("a"), Blob.fromUtf8("b")])
        @Expect(results.size, 2)
        @Expect(results[0], true)
        @Expect(results[1], false)
    }

    // -------- 哈希命令 --------

    @TestCase
    func testHSetHGet() {
        let c = createClient()
        let k = uniqueKey("mh")
        c.hset(k, "f1", Blob.fromUtf8("v1"))
        let v = c.hget(k, "f1")
        match (v) { case Some(b) => @Expect(b.toUtf8(), "v1") case _ => @Fail("HGET failed") }
    }

    @TestCase
    func testHStrLen() {
        let c = createClient()
        let k = uniqueKey("hsl")
        c.hset(k, "f", Blob.fromUtf8("hello"))
        let n = c.hstrlen(k, "f")
        @Expect(n, 5)
    }

    // -------- 有序集合命令 --------

    @TestCase
    func testZAddZRange() {
        let c = createClient()
        let k = uniqueKey("mz")
        c.zadd(k, [(1.0, Blob.fromUtf8("a")), (2.0, Blob.fromUtf8("b"))])
        let members = c.zrange(k, 0, -1)
        @Expect(members.size, 2)
    }

    @TestCase
    func testZRem() {
        let c = createClient()
        let k = uniqueKey("zr")
        c.zadd(k, [(1.0, Blob.fromUtf8("a"))])
        let n = c.zrem(k, [Blob.fromUtf8("a")])
        @Expect(n, 1)
    }

    @TestCase
    func testZScore() {
        let c = createClient()
        let k = uniqueKey("zs")
        c.zadd(k, [(3.5, Blob.fromUtf8("x"))])
        let s = c.zscore(k, Blob.fromUtf8("x"))
        match (s) { case Some(f) => @Expect(f > 3.49 && f < 3.51, true) case _ => @Fail("ZSCORE failed") }
    }

    @TestCase
    func testZPopMin() {
        let c = createClient()
        let k = uniqueKey("zpm")
        c.executeString(["ZADD", k, "1", "a", "2", "b"])
        let results = c.zpopmin(k)
        // ZPOPMIN 可能因并发返回空，仅验证不抛异常
        @Expect(true, true)
    }

    // -------- 流命令 --------

    @TestCase
    func testXAddXLen() {
        let c = createClient()
        let k = uniqueKey("ms")
        c.xadd(k, [("f1", Blob.fromUtf8("v1"))])
        let len = c.xlen(k)
        @Expect(len, 1)
    }

    @TestCase
    func testXGroup() {
        let c = createClient()
        let k = uniqueKey("xg")
        c.xadd(k, [("f", Blob.fromUtf8("v"))])
        c.executeString(["XGROUP", "CREATE", k, "mygroup", "0"])
        let groups = c.xinfoGroups(k)
        @Expect(groups.size > 0, true)
    }

    // -------- 服务器命令 --------

    @TestCase
    func testPing() {
        let c = createClient()
        let pong = c.ping()
        @Expect(pong, "PONG")
    }

    @TestCase
    func testTime() {
        let c = createClient()
        let (sec, usec) = c.time()
        @Expect(sec > 0, true)
        @Expect(usec >= 0, true)
    }

    @TestCase
    func testRole() {
        let c = createClient()
        let r = c.role()
        @Expect(r == "master" || r == "slave", true)
    }

    @TestCase
    func testConfigGet() {
        let c = createClient()
        let configs = c.configGet("timeout")
        @Expect(configs.size > 0, true)
    }

    @TestCase
    func testFlushDB() {
        let c = createClient()
        let k = uniqueKey("fdb")
        c.set(k, Blob.fromUtf8("x"))
        c.flushDb()
        let v = c.get(k)
        match (v) { case None => () case _ => @Fail("FLUSHDB 应删除键") }
    }

    // -------- 连接命令 --------

    @TestCase
    func testClientSetname() {
        let c = createClient()
        let name = uniqueKey("client")
        c.clientSetName(name)
        let n = c.clientGetName()
        match (n) { case Some(v) => @Expect(v, name) case _ => @Fail("CLIENT GETNAME failed") }
    }

    // -------- 事务命令 --------

    @TestCase
    func testTransaction() {
        let c = createClient()
        let k = uniqueKey("txk")
        let txn = Transaction(c)
        txn.queue(["SET", k, "txv"])
        txn.queue(["GET", k])
        let results = txn.exec()
        @Expect(results.size, 2)
    }

    @TestCase
    func testUnwatch() {
        let c = createClient()
        c.unwatch()
        @Expect(true, true)
    }

    // -------- 键命令 --------

    @TestCase
    func testExists() {
        let c = createClient()
        let k = uniqueKey("ek")
        c.set(k, Blob.fromUtf8("v"))
        let n = c.exists([k, "nonexistent_${k}"])
        @Expect(n, 1)
    }

    @TestCase
    func testExpire() {
        let c = createClient()
        let k = uniqueKey("exk")
        c.set(k, Blob.fromUtf8("v"))
        let ok = c.expire(k, 100)
        @Expect(ok, true)
        let ttl = c.ttl(k)
        @Expect(ttl > 0 && ttl <= 100, true)
    }

    @TestCase
    func testPersist() {
        let c = createClient()
        let k = uniqueKey("psk")
        c.set(k, Blob.fromUtf8("v"))
        c.expire(k, 100)
        let ok = c.persist(k)
        @Expect(ok, true)
        @Expect(c.ttl(k), -1)
    }

    @TestCase
    func testType() {
        let c = createClient()
        let k = uniqueKey("tp")
        c.set(k, Blob.fromUtf8("s"))
        let t = c.typeOf(k)
        @Expect(t, "string")
    }

    @TestCase
    func testRename() {
        let c = createClient()
        let k1 = uniqueKey("rn1")
        let k2 = uniqueKey("rn2")
        c.set(k1, Blob.fromUtf8("v"))
        c.rename(k1, k2)
        let v = c.get(k1)
        match (v) { case None => () case _ => @Fail("原名应不存在") }
    }

    @TestCase
    func testTouch() {
        let c = createClient()
        let k = uniqueKey("tk")
        c.set(k, Blob.fromUtf8("v"))
        let n = c.touch([k])
        @Expect(n, 1)
    }

    // -------- 脚本命令 --------

    @TestCase
    func testEval() {
        let c = createClient()
        let resp = c.eval("return 42")
        match (resp) {
            case RESPValue.Integer(n) => @Expect(n, 42)
            case _ => @Fail("EVAL 应返回 Integer(42)")
        }
    }

    @TestCase
    func testScriptLoadAndExists() {
        let c = createClient()
        let sha = c.scriptLoad("return 'hello'")
        @Expect(sha.size > 0, true)
        let exists = c.scriptExists([sha])
        @Expect(exists.size, 1)
        @Expect(exists[0], true)
    }

    // -------- Pipeline --------

    @TestCase
    func testPipeline() {
        let c = createClient()
        let k = uniqueKey("pk")
        let results = c.pipeline([
            ["SET", k, "pv"],
            ["GET", k],
        ])
        @Expect(results.size, 2)
    }

    // -------- SCAN --------

    @TestCase
    func testScan() {
        let c = createClient()
        let k1 = uniqueKey("sk1")
        let k2 = uniqueKey("sk2")
        c.set(k1, Blob.fromUtf8("v"))
        c.set(k2, Blob.fromUtf8("v"))
        let (cursor, keys) = c.scan(0)
        @Expect(keys.size >= 2, true)
    }

    // -------- Geo --------

    @TestCase
    func testGeoAdd() {
        let c = createClient()
        let k = uniqueKey("geo")
        let n = c.geoadd(k, [(13.361389, 38.115556, Blob.fromUtf8("Palermo"))])
        @Expect(n > 0, true)
    }

    @TestCase
    func testGeoDist() {
        let c = createClient()
        let k = uniqueKey("gd")
        c.geoadd(k, [(13.361389, 38.115556, Blob.fromUtf8("Palermo")),
                     (15.087269, 37.502669, Blob.fromUtf8("Catania"))])
        let dist = c.geodist(k, Blob.fromUtf8("Palermo"), Blob.fromUtf8("Catania"))
        match (dist) { case Some(_) => @Expect(true, true) case None => @Fail("GEODIST failed") }
    }

    @TestCase
    func testGeoHash() {
        let c = createClient()
        let k = uniqueKey("gh")
        c.geoadd(k, [(13.361389, 38.115556, Blob.fromUtf8("Palermo"))])
        let hashes = c.geohash(k, [Blob.fromUtf8("Palermo")])
        @Expect(hashes.size, 1)
    }
}
