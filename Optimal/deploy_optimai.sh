#!/bin/bash
# OptimAI Core Node 安装脚本

echo "========================================"
echo "   OptimAI Core Node 安装"
echo "========================================"
echo ""

# 检测操作系统
if [[ "$(uname)" != "Darwin" ]]; then
    echo "❌ 此脚本仅支持 macOS 系统"
    exit 1
fi

# 1. 下载文件
echo "📥 下载 OptimAI CLI..."
curl -L https://optimai.network/download/cli-node/mac -o optimai-cli

if [ ! -f "optimai-cli" ]; then
    echo "❌ 下载失败"
    exit 1
fi

# 2. 设置权限
echo "🔧 设置权限..."
chmod +x optimai-cli

# 3. 安装到系统路径
echo "📦 安装到系统路径..."
sudo mv optimai-cli /usr/local/bin/optimai-cli

# 4. 登录
echo ""
echo "🔐 登录 OptimAI 账户..."
echo "等待输入邮箱进行登录..."
echo ""
optimai-cli auth login

# 5. 启动节点
echo ""
echo "🚀 启动节点..."
optimai-cli node start
