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

# 1. 检查是否已安装
if command -v optimai-cli >/dev/null 2>&1; then
    echo "✅ OptimAI CLI 已安装: $(optimai-cli --version 2>/dev/null || echo '未知版本')"
    echo "   跳过下载和安装步骤"
else
    # 下载文件
    echo "📥 下载 OptimAI CLI..."
    curl -L https://optimai.network/download/cli-node/mac -o optimai-cli
    
    if [ ! -f "optimai-cli" ]; then
        echo "❌ 下载失败"
        exit 1
    fi
    
    # 设置权限
    echo "🔧 设置权限..."
    chmod +x optimai-cli
    
    # 安装到系统路径
    echo "📦 安装到系统路径..."
    sudo mv optimai-cli /usr/local/bin/optimai-cli
    
    echo "✅ 安装完成"
fi

# 2. 登录
echo ""
echo "🔐 登录 OptimAI 账户..."
echo "等待输入邮箱进行登录..."
echo ""
optimai-cli auth login

# 3. 检查 Docker
echo ""
echo "🔍 检查 Docker..."
if ! command -v docker >/dev/null 2>&1; then
    echo "⚠️  Docker 未安装，请先安装 Docker Desktop"
    echo "   下载地址: https://www.docker.com/products/docker-desktop/"
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    echo "⚠️  Docker 服务未运行，正在尝试启动..."
    open -a Docker 2>/dev/null || {
        echo "❌ 无法自动启动 Docker Desktop，请手动启动"
        exit 1
    }
    
    echo "   等待 Docker 启动..."
    waited=0
    max_wait=60
    while [ $waited -lt $max_wait ]; do
        if docker info >/dev/null 2>&1; then
            echo "✅ Docker 已启动"
            break
        fi
        sleep 2
        waited=$((waited + 2))
        echo -n "."
    done
    echo ""
    
    if ! docker info >/dev/null 2>&1; then
        echo "❌ Docker 启动超时"
        exit 1
    fi
else
    echo "✅ Docker 运行正常"
fi

# 4. 创建桌面启动脚本
create_desktop_shortcut() {
    local desktop_path="$HOME/Desktop"
    
    if [ ! -d "$desktop_path" ]; then
        echo "⚠️  桌面目录未找到，跳过快捷方式创建"
        return
    fi
    
    local shortcut_file="$desktop_path/Optimai.command"
    
    cat > "$shortcut_file" <<'SCRIPT_EOF'
#!/bin/bash

# OptimAI Core Node 启动脚本

# 设置颜色
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
CYAN="\033[36m"
RESET="\033[0m"

clear

echo -e "${CYAN}╔══════════════════════════════════════════╗${RESET}"
echo -e "${CYAN}║      OptimAI Core Node 启动              ║${RESET}"
echo -e "${CYAN}║      时间: $(date '+%Y-%m-%d %H:%M:%S')            ║${RESET}"
echo -e "${CYAN}╚══════════════════════════════════════════╝${RESET}"
echo ""

# 检查 CLI
if ! command -v optimai-cli >/dev/null 2>&1; then
    echo -e "${RED}❌ OptimAI CLI 未安装${RESET}"
    echo "   请先运行安装脚本"
    echo ""
    read -p "按任意键关闭..."
    exit 1
fi

# 不检查登录，直接启动（登录状态已保存在部署时）

# 检查 Docker
echo ""
echo "🔍 检查 Docker..."
if ! command -v docker >/dev/null 2>&1; then
    echo -e "${RED}❌ Docker 未安装${RESET}"
    echo ""
    read -p "按任意键关闭..."
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  Docker 未运行，正在启动...${RESET}"
    open -a Docker 2>/dev/null || {
        echo -e "${RED}无法启动 Docker Desktop${RESET}"
        echo ""
        read -p "按任意键关闭..."
        exit 1
    }
    
    waited=0
    max_wait=60
    while [ $waited -lt $max_wait ]; do
        if docker info >/dev/null 2>&1; then
            echo -e "${GREEN}✅ Docker 已启动${RESET}"
            break
        fi
        sleep 2
        waited=$((waited + 2))
        echo -n "."
    done
    echo ""
    
    if ! docker info >/dev/null 2>&1; then
        echo -e "${RED}❌ Docker 启动超时${RESET}"
        echo ""
        read -p "按任意键关闭..."
        exit 1
    fi
else
    echo -e "${GREEN}✅ Docker 运行正常${RESET}"
fi

# 停止旧节点（如果存在）
echo ""
echo "🛑 停止旧节点..."
optimai-cli node stop >/dev/null 2>&1 && sleep 2 || true

# 启动节点
echo ""
echo -e "${CYAN}════════════════════════════════════════════${RESET}"
echo -e "${CYAN}启动 OptimAI 节点${RESET}"
echo -e "${CYAN}════════════════════════════════════════════${RESET}"
echo ""

optimai-cli node start

echo ""
echo "按任意键关闭此窗口..."
read -n 1 -s
SCRIPT_EOF

    chmod +x "$shortcut_file"
    echo "✅ 桌面快捷方式已创建: $shortcut_file"
}

echo ""
echo "📝 创建桌面启动脚本..."
create_desktop_shortcut

# 5. 停止旧节点（如果存在）
echo ""
echo "🛑 停止旧节点（如果存在）..."
optimai-cli node stop >/dev/null 2>&1 && sleep 2 || true

# 6. 启动节点
echo ""
echo "🚀 启动节点..."
optimai-cli node start
