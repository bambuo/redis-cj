package redis.client

/// CRC16 和 SlotMap 单元测试
@Test
class SlotMapTests {
    /// CRC16 已知值验证
    /// Redis 官方测试向量："123456789" 的 CRC16 应为 0x31C3
    @TestCase
    func crc16KnownValue() {
        // crc16 是私有函数，通 SlotMap.getSlot 间接测试
        let slot1 = SlotMap.getSlot("123456789")
        @Expect(slot1, 12739)
    }

    /// 相同 key 的槽位一致
    @TestCase
    func sameKeySameSlot() {
        let slot1 = SlotMap.getSlot("mykey")
        let slot2 = SlotMap.getSlot("mykey")
        @Expect(slot1, slot2)
    }

    /// 不同 key 可能不同槽位
    @TestCase
    func differentKeysDifferentSlots() {
        let slot1 = SlotMap.getSlot("key1")
        let slot2 = SlotMap.getSlot("key2")
        // 理论上可能碰撞，但概率极低
        // 至少验证它们都在范围内
        @Expect(slot1 >= 0 && slot1 < 16384, true)
        @Expect(slot2 >= 0 && slot2 < 16384, true)
    }

    /// 槽位在 0-16383 范围内
    @TestCase
    func slotRange() {
        for (i in 0..100) {
            let slot = SlotMap.getSlot("test_key_${i}")
            @Expect(slot >= 0, true)
            @Expect(slot < 16384, true)
        }
    }

    /// 哈希标签 {} 内的内容用于槽位计算
    @TestCase
    func hashTagConsistency() {
        // Redis 集群使用 {} 内的内容计算槽位
        // 例如 {user123}.key1 和 {user123}.key2 应在同一槽位
        let slot1 = SlotMap.getSlot("{user123}.key1")
        let slot2 = SlotMap.getSlot("{user123}.key2")
        let slot3 = SlotMap.getSlot("{user456}.key1")
        @Expect(slot1, slot2)  // 相同 hash tag
        // user123 和 user456 可能不同槽位
        // 无法断言不等，但可断言两者有效
        @Expect(slot3 >= 0 && slot3 < 16384, true)
    }

    /// 空 hash tag 回退整 key，右括号在左括号前时继续寻找合法 tag
    @TestCase
    func hashTagBoundaryCases() {
        @Expect(SlotMap.getSlot("foo{}{bar}"), 8363)
        @Expect(SlotMap.getSlot("foo}bar{zap}"), SlotMap.getSlot("zap"))
    }

    /// 集群路由抽取覆盖集合 store 命令
    @TestCase
    func clusterRoutingKeysForSetStoreCommands() {
        let keys = extractClusterRoutingKeys(stringsToBlobs(["SINTERSTORE", "{u}:dst", "{u}:a", "{u}:b"]))
        @Expect(keys.size, 3)
        @Expect(keys[0], "{u}:dst")
        @Expect(keys[1], "{u}:a")
        @Expect(keys[2], "{u}:b")
    }

    /// 集群路由抽取覆盖 SINTERCARD numkeys 形态
    @TestCase
    func clusterRoutingKeysForSInterCard() {
        let keys = extractClusterRoutingKeys(stringsToBlobs(["SINTERCARD", "2", "{u}:a", "{u}:b", "LIMIT", "1"]))
        @Expect(keys.size, 2)
        @Expect(keys[0], "{u}:a")
        @Expect(keys[1], "{u}:b")
    }

    /// 集群路由抽取覆盖 BITOP destination + source keys
    @TestCase
    func clusterRoutingKeysForBitop() {
        let keys = extractClusterRoutingKeys(stringsToBlobs(["BITOP", "AND", "{u}:dst", "{u}:a", "{u}:b"]))
        @Expect(keys.size, 3)
        @Expect(keys[0], "{u}:dst")
        @Expect(keys[1], "{u}:a")
        @Expect(keys[2], "{u}:b")
    }

    /// 集群路由抽取覆盖 store/source 双 key 形态
    @TestCase
    func clusterRoutingKeysForStoreSourceCommands() {
        let zkeys = extractClusterRoutingKeys(stringsToBlobs(["ZRANGESTORE", "{u}:dst", "{u}:src", "0", "1"]))
        @Expect(zkeys.size, 2)
        @Expect(zkeys[0], "{u}:dst")
        @Expect(zkeys[1], "{u}:src")

        let geokeys = extractClusterRoutingKeys(
            stringsToBlobs(["GEOSEARCHSTORE", "{u}:dst", "{u}:src", "FROMLONLAT", "0", "0", "BYRADIUS", "1", "km"])
        )
        @Expect(geokeys.size, 2)
        @Expect(geokeys[0], "{u}:dst")
        @Expect(geokeys[1], "{u}:src")
    }

    /// 集群路由抽取覆盖 LCS 双 key
    @TestCase
    func clusterRoutingKeysForLcs() {
        let keys = extractClusterRoutingKeys(stringsToBlobs(["LCS", "{u}:a", "{u}:b", "LEN"]))
        @Expect(keys.size, 2)
        @Expect(keys[0], "{u}:a")
        @Expect(keys[1], "{u}:b")
    }

    /// 集群路由抽取覆盖 OBJECT 子命令 key，HELP 无 key
    @TestCase
    func clusterRoutingKeysForObjectCommands() {
        let keys = extractClusterRoutingKeys(stringsToBlobs(["OBJECT", "ENCODING", "{u}:key"]))
        @Expect(keys.size, 1)
        @Expect(keys[0], "{u}:key")

        let helpKeys = extractClusterRoutingKeys(stringsToBlobs(["OBJECT", "HELP"]))
        @Expect(helpKeys.size, 0)
    }

    /// 集群路由抽取覆盖 MEMORY USAGE key，其它 MEMORY 管理命令无 key
    @TestCase
    func clusterRoutingKeysForMemoryCommands() {
        let keys = extractClusterRoutingKeys(stringsToBlobs(["MEMORY", "USAGE", "{u}:key", "SAMPLES", "0"]))
        @Expect(keys.size, 1)
        @Expect(keys[0], "{u}:key")

        let statsKeys = extractClusterRoutingKeys(stringsToBlobs(["MEMORY", "STATS"]))
        @Expect(statsKeys.size, 0)
    }

    /// 集群路由抽取覆盖 SORT source + STORE destination
    @TestCase
    func clusterRoutingKeysForSortStore() {
        let keys = extractClusterRoutingKeys(
            stringsToBlobs(["SORT", "{u}:src", "BY", "weight_*", "GET", "#", "STORE", "{u}:dst"])
        )
        @Expect(keys.size, 2)
        @Expect(keys[0], "{u}:src")
        @Expect(keys[1], "{u}:dst")
    }

    /// 集群路由抽取覆盖 MIGRATE 单 key 和 KEYS 列表
    @TestCase
    func clusterRoutingKeysForMigrate() {
        let single = extractClusterRoutingKeys(
            stringsToBlobs(["MIGRATE", "127.0.0.1", "6380", "{u}:key", "0", "5000", "COPY"])
        )
        @Expect(single.size, 1)
        @Expect(single[0], "{u}:key")

        let keys = extractClusterRoutingKeys(
            stringsToBlobs(["MIGRATE", "127.0.0.1", "6380", "", "0", "5000", "KEYS", "{u}:a", "{u}:b"])
        )
        @Expect(keys.size, 2)
        @Expect(keys[0], "{u}:a")
        @Expect(keys[1], "{u}:b")
    }

    /// 集群路由抽取覆盖 SCRIPT/FUNCTION 管理子命令无 key
    @TestCase
    func clusterRoutingKeysForScriptAndFunctionManagement() {
        let scriptKeys = extractClusterRoutingKeys(stringsToBlobs(["SCRIPT", "LOAD", "return 1"]))
        @Expect(scriptKeys.size, 0)

        let functionKeys = extractClusterRoutingKeys(stringsToBlobs(["FUNCTION", "DELETE", "libname"]))
        @Expect(functionKeys.size, 0)
    }

    /// CRC16 算法在 Redis 集群中的已知值
    /// "aaaaaaaaaaaaaaa" 的 CRC16 已知为特定值
    @TestCase
    func crc16KnownRedisKeys() {
        // 验证常见 Redis 集群键的槽位在有效范围
        let keys = ["", "a", "ab", "abc", "redis", "cluster", "test", "user:1001", "order:2024001"]
        for (key in keys) {
            let slot = SlotMap.getSlot(key)
            @Expect(slot >= 0 && slot < 16384, true)
        }
    }

    /// NodeAddress 构造
    @TestCase
    func nodeAddress() {
        let addr = NodeAddress("127.0.0.1", 6379)
        @Expect(addr.toKey(), "127.0.0.1:6379")
        @Expect(addr.toString(), "127.0.0.1:6379")
    }

    /// NodeAddress 空字符串
    @TestCase
    func nodeAddressEmpty() {
        let addr = NodeAddress("", 0)
        @Expect(addr.toKey(), ":0")
    }
}
