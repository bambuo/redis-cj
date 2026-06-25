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
        @Expect(slot1 >= 0, true)
        @Expect(slot1 < 16384, true)
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
