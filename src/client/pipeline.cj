package redis.client
import std.collection.*

/// Pipeline 流水线扩展（Command 模式）
///
/// 将多条命令批量发送到 Redis，然后批量读取响应，减少网络往返次数。
extend RedisClient {
    /// 执行 Pipeline 流水线
    ///
    /// 所有命令一次性发送，然后一次性读取所有响应。
    /// 返回的响应数组顺序与命令数组一致。
    ///
    /// @param stringCommands 字符串格式的命令数组
    /// @return 响应值数组
    public func pipeline(stringCommands: Array<Array<String>>): Array<RESPValue> {
        let blobCommands = ArrayList<Array<Blob>>()
        for (cmd in stringCommands) {
            let blobCmd = ArrayList<Blob>()
            for (arg in cmd) {
                blobCmd.add(Blob.fromUtf8(arg))
            }
            blobCommands.add(collectArray(blobCmd.iterator()))
        }
        connection.executeBatch(collectArray(blobCommands.iterator()))
    }

    /// 执行 Pipeline 流水线（Blob 版本）
    public func pipelineBlob(commands: Array<Array<Blob>>): Array<RESPValue> {
        connection.executeBatch(commands)
    }
}
