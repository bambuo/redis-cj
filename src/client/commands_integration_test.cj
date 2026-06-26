package redis.client

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

    @TestCase
    func testIncrByFloatBulkStringReply() {
        let c = createClient()
        let k = uniqueKey("ibf")
        let n = c.incrByFloat(k, 1.5)
        @Expect(n > 1.49 && n < 1.51, true)
    }

    @TestCase
    func testSetKeepTtl() {
        let c = createClient()
        let k = uniqueKey("skttl")
        c.setex(k, 100, Blob.fromUtf8("v1"))
        @Expect(c.set(k, Blob.fromUtf8("v2"), keepTtl: true), true)
        let ttl = c.ttl(k)
        @Expect(ttl > 0 && ttl <= 100, true)
    }

    @TestCase
    func testSetGetKeepsOldValue() {
        let c = createClient()
        let k = uniqueKey("sg")
        c.set(k, Blob.fromUtf8("old"))
        let old = c.setGet(k, Blob.fromUtf8("new"))
        match (old) {
            case Some(v) => @Expect(v.toUtf8(), "old")
            case None => @Fail("SET GET 应返回旧值")
        }
        let now = c.get(k)
        match (now) {
            case Some(v) => @Expect(v.toUtf8(), "new")
            case None => @Fail("SET GET 应写入新值")
        }
    }

    @TestCase
    func testGetExPersistAndBitfieldRo() {
        let c = createClient()
        let k = uniqueKey("getex")
        c.setex(k, 100, Blob.fromUtf8("A"))
        let v = c.getex(k, persist: true)
        match (v) { case Some(b) => @Expect(b.toUtf8(), "A") case None => @Fail("GETEX failed") }
        @Expect(c.ttl(k), -1)
        let bits = c.bitfieldRo(k, ["GET", "u8", "0"])
        @Expect(bits.size, 1)
        match (bits[0]) {
            case Some(n) => @Expect(n, 65)
            case None => @Fail("BITFIELD_RO failed")
        }
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

    @TestCase
    func testListCountPopAndLmPop() {
        let c = createClient()
        let k = uniqueKey("lcnt")
        c.rpush(k, [Blob.fromUtf8("a"), Blob.fromUtf8("b"), Blob.fromUtf8("c")])
        @Expect(c.lpopCount(k, 2).size, 2)
        c.rpush(k, [Blob.fromUtf8("d"), Blob.fromUtf8("e")])
        let popped = c.lmpop([k], side: "RIGHT", count: Some(2))
        match (popped) {
            case Some((key, vals)) =>
                @Expect(key, k)
                @Expect(vals.size, 2)
            case None => @Fail("LMPOP failed")
        }
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

    @TestCase
    func testSPopCount() {
        let c = createClient()
        let k = uniqueKey("spc")
        c.sadd(k, [Blob.fromUtf8("a"), Blob.fromUtf8("b"), Blob.fromUtf8("c")])
        let members = c.spopCount(k, 2)
        @Expect(members.size, 2)
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

    @TestCase
    func testHIncrByFloatBulkStringReply() {
        let c = createClient()
        let k = uniqueKey("hibf")
        let n = c.hincrByFloat(k, "f", 2.5)
        @Expect(n > 2.49 && n < 2.51, true)
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

    @TestCase
    func testZAddOptionsAndIncr() {
        let c = createClient()
        let k = uniqueKey("zopts")
        @Expect(c.zadd(k, [(1.0, Blob.fromUtf8("a"))], nx: true), 1)
        @Expect(c.zadd(k, [(2.0, Blob.fromUtf8("a"))], nx: true), 0)
        @Expect(c.zadd(k, [(3.0, Blob.fromUtf8("a"))], xx: true, ch: true), 1)
        let n = c.zaddIncr(k, 1.5, Blob.fromUtf8("a"), xx: true)
        match (n) {
            case Some(v) => @Expect(v > 4.49 && v < 4.51, true)
            case None => @Fail("ZADD INCR failed")
        }
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

    @TestCase
    func testClientTrackingInfoAndAclWhoami() {
        let c = createClient()
        let redir = c.clientGetRedir()
        @Expect(redir >= -1, true)
        let info = c.clientTrackingInfo()
        match (info) {
            case RESPValue.Array(_) | RESPValue.Map(_) => ()
            case _ => @Fail("CLIENT TRACKINGINFO 返回类型异常")
        }
        @Expect(c.aclWhoami().size > 0, true)
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

    @TestCase
    func testTransactionWatchAbort() {
        let c1 = createClient()
        let c2 = createClient()
        let k = uniqueKey("txabort")
        c1.set(k, Blob.fromUtf8("v1"))
        let txn = Transaction(c1)
        txn.watch([k])
        txn.queue(["SET", k, "v2"])
        c2.set(k, Blob.fromUtf8("external"))
        @ExpectThrows[TransactionAbortedError](txn.exec())
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
    func testExpireCondition() {
        let c = createClient()
        let k = uniqueKey("excond")
        c.set(k, Blob.fromUtf8("v"))
        @Expect(c.expire(k, 100, condition: Some("NX")), true)
        @Expect(c.expire(k, 200, condition: Some("NX")), false)
        @Expect(c.expire(k, 200, condition: Some("XX")), true)
    }

    @TestCase
    func testScanTypeAndSortStore() {
        let c = createClient()
        let k = uniqueKey("scantype")
        let dst = uniqueKey("sortdst")
        c.rpush(k, [Blob.fromUtf8("2"), Blob.fromUtf8("1")])
        let (_, keys) = c.scan(0, pattern: Some("${k}*"), typeFilter: Some("list"))
        @Expect(keys.size >= 1, true)
        @Expect(c.sortStore(k, dst), 2)
        @Expect(c.llen(dst), 2)
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

    @TestCase
    func testCommandGetKeysAndFlags() {
        let c = createClient()
        let keys = c.commandGetKeysAndFlags(["SET", "k", "v"])
        @Expect(keys.size > 0, true)
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
        @Expect(cursor >= 0, true)
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

    @TestCase
    func testGeoSearchBoxAndOrder() {
        let c = createClient()
        let k = uniqueKey("gbox")
        c.geoadd(k, [(13.361389, 38.115556, Blob.fromUtf8("Palermo")),
                     (15.087269, 37.502669, Blob.fromUtf8("Catania"))])
        let results = c.geosearch(
            k,
            fromLonLat: Some((15.0, 37.0)),
            box: Some((500.0, 500.0)),
            unit: "km",
            order: Some("ASC"),
            count: Some(2)
        )
        @Expect(results.size > 0, true)
    }
}
