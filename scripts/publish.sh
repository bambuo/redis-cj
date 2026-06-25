#!/bin/bash
# 发布脚本 — 临时替代 cjpm publish
set -e

cd "$(dirname "$0")/.."

CJP_FILE="target/redis-1.0.0.cjp"
META_FILE="target/meta-data.json"
TOKEN_FILE="$HOME/.cjpm/cangjie-repo.toml"

# 读取 token
if [ ! -f "$TOKEN_FILE" ]; then
    echo "错误: 未找到 $TOKEN_FILE"
    echo "请先配置: mkdir -p ~/.cjpm && cat > ~/.cjpm/cangjie-repo.toml << EOF"
    echo '[repository.home]'
    echo '    registry = "https://pkg.cangjie-lang.cn/registry"'
    echo '    token = "你的token"'
    echo 'EOF'
    exit 1
fi

TOKEN=$(grep 'token' "$TOKEN_FILE" | sed 's/.*= "\(.*\)"/\1/')
if [ -z "$TOKEN" ]; then echo "错误: token 为空"; exit 1; fi

echo "🔑 Token: ${TOKEN:0:8}... (已隐藏)"

# 清理重建
echo "🔨 构建..."
source ~/Library/Cangjie/1.1.3/envsetup.sh 2>/dev/null || true
rm -rf target
cjpm build 2>&1 | tail -1

echo "📦 打包..."
cjpm bundle --skip-lint --skip-test 2>&1 | tail -1

# 生成元数据
echo "📋 生成元数据..."
CHECKSUM=$(shasum -a 256 "$CJP_FILE" | cut -d' ' -f1)
SIZE=$(stat -f%z "$CJP_FILE")
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

cat > "$META_FILE" << METAEOF
{
    "name": "redis",
    "version": "1.0.0",
    "organization": "",
    "checksum": "${CHECKSUM}",
    "size": ${SIZE},
    "timestamp": "${TIMESTAMP}",
    "cjc-version": "1.1.3",
    "description": "A Redis client library in Cangjie, supporting RESP2/RESP3, Pipeline, Pub/Sub, Cluster",
    "license": ["MIT"],
    "output-type": "static"
}
METAEOF

echo "  制品包: $(ls -lh $CJP_FILE | awk '{print $5}')"
echo "  SHA256: ${CHECKSUM:0:16}..."

# 构建请求体（API 自定义二进制格式）
echo "🌐 上传中..."
python3 -c "
import struct, os

meta_path = '${META_FILE}'
pkg_path  = '${CJP_FILE}'

with open(meta_path, 'rb') as f:
    meta_data = f.read()
with open(pkg_path, 'rb') as f:
    pkg_data = f.read()

# 格式: [meta_ver:1B][meta_len:4B][meta_data][pkg_ver:1B][pkg_len:4B][pkg_data]
body = b'\\x01' + struct.pack('<I', len(meta_data)) + meta_data
body += b'\\x01' + struct.pack('<I', len(pkg_data)) + pkg_data

with open('/tmp/upload_payload.bin', 'wb') as f:
    f.write(body)
print(f'Payload: {len(body)} bytes')
"

# 上传
UPLOAD_URL="https://pkg.cangjie-lang.cn/pkg/redis"
RESPONSE=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: ${TOKEN}" \
    --data-binary @/tmp/upload_payload.bin \
    "$UPLOAD_URL")

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')
rm -f /tmp/upload_payload.bin

echo "  HTTP $HTTP_CODE"
echo "  响应: $BODY"

if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ 发布成功!"
elif [ "$HTTP_CODE" = "409" ]; then
    echo "⚠️  版本冲突: redis-1.0.0 已存在，请更新版本号"
elif [ "$HTTP_CODE" = "401" ]; then
    echo "❌ 认证失败，请检查 token"
else
    echo "❌ 发布失败 (HTTP $HTTP_CODE)"
fi
