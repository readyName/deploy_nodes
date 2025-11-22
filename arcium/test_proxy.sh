#!/bin/bash

# 测试代理是否生效

# 代理配置
AIRDROP_PROXY="http://OTstxmpqIqnPXpQX:qS4HD86RgoaIs07L_streaming-1@geo.iproyal.com:12321"

echo "=== 代理测试脚本 ==="
echo

# 测试1: 不使用代理获取IP
echo "1. 测试不使用代理获取IP:"
ORIGINAL_IP=$(curl -s --max-time 5 https://ipv4.icanhazip.com 2>/dev/null || echo "失败")
echo "   原始IP: $ORIGINAL_IP"
echo

# 测试2: 使用代理获取IP
echo "2. 测试使用代理获取IP:"
export HTTP_PROXY="$AIRDROP_PROXY"
export HTTPS_PROXY="$AIRDROP_PROXY"
export http_proxy="$AIRDROP_PROXY"
export https_proxy="$AIRDROP_PROXY"

PROXY_IP=$(curl -s --max-time 10 https://ipv4.icanhazip.com 2>/dev/null || echo "失败")
echo "   代理IP: $PROXY_IP"
echo

# 测试3: 测试代理连接Solana RPC
echo "3. 测试通过代理连接Solana RPC:"
if curl -s --max-time 10 --proxy "$AIRDROP_PROXY" -X POST \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","id":1,"method":"getHealth"}' \
    https://api.devnet.solana.com 2>/dev/null | grep -q "result"; then
    echo "   ✓ Solana RPC 连接成功（通过代理）"
else
    echo "   ✗ Solana RPC 连接失败"
fi
echo

# 恢复环境
unset HTTP_PROXY
unset HTTPS_PROXY
unset http_proxy
unset https_proxy

# 测试4: 测试solana命令是否支持代理
echo "4. 测试 solana 命令是否可用:"
if command -v solana >/dev/null 2>&1; then
    echo "   ✓ solana 命令已安装"
    echo "   版本: $(solana --version 2>/dev/null || echo '未知')"
else
    echo "   ✗ solana 命令未安装"
fi
echo

# 测试5: 模拟代理设置和恢复
echo "5. 测试代理设置和恢复函数:"
source arcium.sh 2>/dev/null || true

# 保存原始设置
export _ORIGINAL_HTTP_PROXY="${HTTP_PROXY:-}"
export _ORIGINAL_HTTPS_PROXY="${HTTPS_PROXY:-}"

# 设置代理
export HTTP_PROXY="$AIRDROP_PROXY"
export HTTPS_PROXY="$AIRDROP_PROXY"
echo "   设置代理后 HTTP_PROXY: ${HTTP_PROXY%%@*}"
echo "   设置代理后 HTTPS_PROXY: ${HTTPS_PROXY%%@*}"

# 恢复代理
if [[ -n "${_ORIGINAL_HTTP_PROXY:-}" ]]; then
    export HTTP_PROXY="${_ORIGINAL_HTTP_PROXY}"
else
    unset HTTP_PROXY
fi
if [[ -n "${_ORIGINAL_HTTPS_PROXY:-}" ]]; then
    export HTTPS_PROXY="${_ORIGINAL_HTTPS_PROXY}"
else
    unset HTTPS_PROXY
fi
echo "   恢复代理后 HTTP_PROXY: ${HTTP_PROXY:-未设置}"
echo "   恢复代理后 HTTPS_PROXY: ${HTTPS_PROXY:-未设置}"
echo

echo "=== 测试完成 ==="
echo
echo "总结:"
if [[ "$PROXY_IP" != "失败" ]] && [[ "$PROXY_IP" != "$ORIGINAL_IP" ]]; then
    echo "✓ 代理工作正常，IP已改变"
    echo "  原始IP: $ORIGINAL_IP"
    echo "  代理IP: $PROXY_IP"
else
    echo "⚠ 代理可能未生效或IP未改变"
fi

