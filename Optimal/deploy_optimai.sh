#!/bin/bash
# optimai-final-setup-mac.sh - macOS 优化版最终设置脚本

echo "========================================"
echo "   OptimAI Core Node macOS 最终设置"
echo "========================================"

# 检测操作系统
if [[ "$(uname)" != "Darwin" ]]; then
    echo "❌ 此脚本仅支持 macOS 系统"
    echo "检测到的系统: $(uname)"
    exit 1
fi

echo "🖥️  系统检测: macOS $(sw_vers -productVersion)"
echo ""

# 1. 检查是否已安装
echo "1. 检查 OptimAI CLI 安装状态..."
if command -v optimai-cli >/dev/null 2>&1; then
    INSTALLED_VERSION=$(optimai-cli --version 2>/dev/null || echo "未知版本")
    echo "✅ OptimAI CLI 已安装: $INSTALLED_VERSION"
    echo "   安装路径: $(which optimai-cli)"
    
    read -p "是否重新安装? (y/n, 默认 n): " -n 1 -r
echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "跳过安装，使用现有版本"
        SKIP_INSTALL=true
    else
        echo "将重新安装..."
        SKIP_INSTALL=false
    fi
else
    echo "ℹ️  OptimAI CLI 未安装，将进行安装"
    SKIP_INSTALL=false
fi

# 2. 下载并安装 CLI
if [ "$SKIP_INSTALL" != "true" ]; then
echo ""
    echo "2. 下载 OptimAI CLI..."
    
    DOWNLOAD_URL="https://optimai.network/download/cli-node/mac"
    TEMP_FILE="/tmp/optimai-cli-$$"
    
    echo "   下载地址: $DOWNLOAD_URL"
    echo "   临时文件: $TEMP_FILE"
    
    # 下载文件
    if command -v curl >/dev/null 2>&1; then
        echo "   使用 curl 下载中..."
        if curl -L -f --progress-bar -o "$TEMP_FILE" "$DOWNLOAD_URL"; then
            echo "✅ 下载完成"
        else
            echo "❌ 下载失败，请检查网络连接"
            echo "   手动下载命令: curl -L $DOWNLOAD_URL -o optimai-cli"
            exit 1
        fi
    elif command -v wget >/dev/null 2>&1; then
        echo "   使用 wget 下载中..."
        if wget --progress=bar:force -O "$TEMP_FILE" "$DOWNLOAD_URL" 2>&1; then
            echo "✅ 下载完成"
        else
            echo "❌ 下载失败，请检查网络连接"
            echo "   手动下载命令: wget -O optimai-cli $DOWNLOAD_URL"
            exit 1
        fi
    else
        echo "❌ 未找到 curl 或 wget，无法自动下载"
        echo "   请手动下载: curl -L $DOWNLOAD_URL -o optimai-cli"
    exit 1
fi

    # 验证下载的文件
    if [ -f "$TEMP_FILE" ]; then
        FILE_SIZE=$(wc -c < "$TEMP_FILE" 2>/dev/null || echo "0")
        if [ "$FILE_SIZE" -gt 10000000 ]; then  # 大于10MB
            FILE_SIZE_MB=$(echo "scale=2; $FILE_SIZE/1048576" | bc 2>/dev/null || echo "未知")
            echo "✅ 文件下载成功，大小: ${FILE_SIZE_MB} MB"
        else
            echo "⚠️  下载的文件大小异常: $FILE_SIZE 字节"
            echo "   文件可能不完整，请重新运行脚本"
            rm -f "$TEMP_FILE"
            exit 1
        fi
    else
        echo "❌ 下载失败，文件不存在"
    exit 1
fi

    # 3. 设置权限并安装到系统路径
echo ""
    echo "3. 安装到系统路径..."
    
    # 设置执行权限
    chmod +x "$TEMP_FILE"
    
    # 检查是否有 sudo 权限
    if [ -w "/usr/local/bin" ]; then
        INSTALL_CMD="mv"
        INSTALL_PATH="/usr/local/bin/optimai-cli"
        SUDO_NEEDED=false
    else
        INSTALL_CMD="sudo mv"
        INSTALL_PATH="/usr/local/bin/optimai-cli"
        SUDO_NEEDED=true
    fi
    
    echo "   设置执行权限: ✅"
    echo "   安装路径: $INSTALL_PATH"
    
    if [ "$SUDO_NEEDED" = true ]; then
        echo "   需要管理员权限，请输入密码..."
        if sudo mv "$TEMP_FILE" "$INSTALL_PATH"; then
            echo "✅ 安装成功"
        else
            echo "❌ 安装失败，权限不足"
            rm -f "$TEMP_FILE"
    exit 1
fi
    else
        if mv "$TEMP_FILE" "$INSTALL_PATH"; then
            echo "✅ 安装成功"
        else
            echo "❌ 安装失败"
            rm -f "$TEMP_FILE"
    exit 1
        fi
    fi
    
    # 验证安装
    if command -v optimai-cli >/dev/null 2>&1; then
        INSTALLED_VERSION=$(optimai-cli --version 2>/dev/null || echo "未知版本")
        echo "✅ OptimAI CLI 安装成功"
        echo "   版本: $INSTALLED_VERSION"
        echo "   路径: $(which optimai-cli)"
    else
        echo "❌ 安装验证失败，请检查 PATH 环境变量"
        exit 1
    fi
fi

# 4. 检查 Docker
echo ""
echo "4. 检查 Docker..."
if command -v docker >/dev/null 2>&1; then
    if docker info >/dev/null 2>&1; then
DOCKER_VERSION=$(docker --version | cut -d' ' -f3 | tr -d ',')
echo "✅ Docker 运行正常 (版本: $DOCKER_VERSION)"
    else
        echo "⚠️  Docker 已安装但服务未运行"
        echo "   正在尝试启动 Docker Desktop..."

        if [[ "$(uname)" == "Darwin" ]]; then
            open -a Docker 2>/dev/null || {
                echo "   无法自动启动 Docker Desktop"
                echo "   请手动启动: open -a Docker"
echo ""
                read -p "按回车键继续（确认 Docker 已启动）..."
            }
            
            # 等待 Docker 启动
            echo "   等待 Docker Desktop 启动..."
            waited=0
            max_wait=60
            while [ $waited -lt $max_wait ]; do
                if docker info >/dev/null 2>&1; then
                    echo "✅ Docker 现在运行正常"
                    break
                fi
                sleep 2
                waited=$((waited + 2))
                echo -n "."
            done
    echo ""
            
            if ! docker info >/dev/null 2>&1; then
                echo "❌ Docker 启动失败，请手动启动后重试"
            exit 1
        fi
    else
            echo "   请手动启动 Docker 服务"
        exit 1
    fi
fi
else
    echo "❌ Docker 未安装"
    echo ""
    echo "📦 请安装 Docker Desktop for macOS:"
    echo "   1. 下载: https://www.docker.com/products/docker-desktop/"
    echo "   2. 双击 Docker.dmg 文件安装"
    echo "   3. 将 Docker 拖到 Applications 文件夹"
    echo "   4. 启动 Docker Desktop"
    echo "   5. 同意服务条款并完成设置"
    echo ""
    echo "   或使用 Homebrew 安装:"
    echo "   brew install --cask docker"
    exit 1
fi

# 5. 登录
echo ""
echo "════════════════════════════════════════════"
echo "5. OptimAI 账户登录"
echo "════════════════════════════════════════════"
echo ""

# 检查是否已登录
if optimai-cli auth status >/dev/null 2>&1; then
    echo "✅ 检测到已登录状态，跳过登录步骤"
    echo "   会话已保存，下次启动节点无需重新登录"
else
    echo "📋 登录说明:"
    echo "• 需要 OptimAI 账户 (如果没有请先注册)"
    echo "• 会话会自动保存，下次启动节点无需重新登录"
    echo ""
    echo "🌐 账户准备:"
    echo "   注册地址: https://node.optimai.network/register"
    echo "   忘记密码: https://node.optimai.network/forgot-password"
    echo ""
    
    read -p "按回车键开始登录 (按 Ctrl+C 取消)..."
    
    echo ""
    echo "🔐 开始登录..."
    echo "════════════════════════════════════════════"
    echo "等待输入邮箱进行登录..."
    echo ""
    
    optimai-cli auth login
    
    # 验证登录是否成功
    if ! optimai-cli auth status >/dev/null 2>&1; then
        echo ""
        echo "❌ 登录验证失败，请重新运行脚本或手动登录"
        exit 1
    fi
    
    echo ""
    echo "✅ 登录成功！会话已保存"
fi

# 6. 启动节点（在创建快捷方式后统一启动）

# 7. 创建桌面快捷方式
create_desktop_shortcut() {
    local desktop_path=""
    
    # 检测桌面路径
    if [[ -n "$HOME" ]]; then
        if [[ "$(uname)" == "Darwin" ]]; then
            desktop_path="$HOME/Desktop"
        elif [[ -d "$HOME/Desktop" ]]; then
            desktop_path="$HOME/Desktop"
        elif [[ -d "$HOME/桌面" ]]; then
            desktop_path="$HOME/桌面"
        fi
    fi
    
    if [[ -z "$desktop_path" || ! -d "$desktop_path" ]]; then
        echo "⚠️  桌面目录未找到，跳过快捷方式创建"
        return
    fi
    
    local shortcut_file="$desktop_path/Optimai.command"
    
    # 创建快捷方式文件 - 直接启动/重启节点
    cat > "$shortcut_file" <<'SCRIPT_EOF'
#!/bin/bash

# OptimAI Core Node 启动/重启脚本

# 设置颜色
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
CYAN="\033[36m"
RESET="\033[0m"

# 清屏
clear

# 显示标题
echo -e "${CYAN}╔══════════════════════════════════════════╗${RESET}"
echo -e "${CYAN}║      OptimAI Core Node 启动/重启          ║${RESET}"
echo -e "${CYAN}║      时间: $(date '+%Y-%m-%d %H:%M:%S')            ║${RESET}"
echo -e "${CYAN}╚══════════════════════════════════════════╝${RESET}"
echo ""

# 检查 optimai-cli 是否安装
if ! command -v optimai-cli >/dev/null 2>&1; then
    echo -e "${RED}❌ OptimAI CLI 未安装${RESET}"
    echo "   请先运行安装脚本安装 OptimAI CLI"
    echo ""
    read -p "按任意键关闭此窗口..."
    exit 1
fi

# 检查 Docker
echo "🔍 检查 Docker..."
if ! command -v docker >/dev/null 2>&1; then
    echo -e "${RED}❌ Docker 未安装${RESET}"
    echo "   请先安装 Docker Desktop for macOS"
    echo ""
    read -p "按任意键关闭此窗口..."
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  Docker 服务未运行${RESET}"
    echo "   正在尝试启动 Docker Desktop..."
    open -a Docker 2>/dev/null || {
        echo -e "${RED}无法自动启动 Docker Desktop${RESET}"
        echo "   请手动启动: open -a Docker"
        echo ""
        read -p "按任意键关闭此窗口..."
        exit 1
    }
    
    echo "   等待 Docker 启动..."
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
        read -p "按任意键关闭此窗口..."
        exit 1
    fi
else
    echo -e "${GREEN}✅ Docker 运行正常${RESET}"
fi

# 检查登录状态
echo ""
echo "🔍 检查登录状态..."
if ! optimai-cli auth status >/dev/null 2>&1; then
    echo -e "${RED}❌ 未登录${RESET}"
    echo ""
    echo "需要先登录才能启动节点"
    echo "等待输入邮箱进行登录..."
    echo ""
    
    if ! optimai-cli auth login; then
        echo ""
        echo -e "${RED}❌ 登录失败${RESET}"
        echo ""
        read -p "按任意键关闭此窗口..."
        exit 1
    fi
    
    echo ""
    echo -e "${GREEN}✅ 登录成功！${RESET}"
else
    echo -e "${GREEN}✅ 已登录（会话已保存）${RESET}"
fi

# 停止旧节点（如果存在）
echo ""
echo "🛑 检查并停止旧节点..."
if optimai-cli node stop >/dev/null 2>&1; then
    echo -e "${GREEN}✅ 已停止旧节点${RESET}"
    sleep 2
else
    echo -e "${YELLOW}ℹ️  未发现运行中的节点${RESET}"
fi

# 启动节点
echo ""
echo -e "${CYAN}════════════════════════════════════════════${RESET}"
echo -e "${CYAN}启动 OptimAI 节点${RESET}"
echo -e "${CYAN}════════════════════════════════════════════${RESET}"
echo ""

if optimai-cli node start; then
    echo ""
    echo -e "${GREEN}✅ 节点启动成功！${RESET}"
    echo ""
    echo "📊 节点信息:"
    echo "   名称: $(hostname)"
    echo "   类型: Core Node"
    echo ""
    echo "💡 提示:"
    echo "   • 节点正在运行中"
    echo "   • 关闭此窗口不会停止节点"
    echo "   • 如需停止节点，请运行: optimai-cli node stop"
    echo "   • 查看日志: optimai-cli node logs"
    echo ""
else
    echo ""
    echo -e "${RED}❌ 节点启动失败${RESET}"
    echo ""
    echo "🔧 故障排除:"
    echo "   1. 检查 Docker 是否运行: docker ps"
    echo "   2. 确保网络连接正常"
    echo "   3. 重新登录: optimai-cli auth login"
    echo ""
fi

echo "按任意键关闭此窗口..."
read -n 1 -s
SCRIPT_EOF

    # 设置执行权限
    chmod +x "$shortcut_file"
    
    echo "✅ 桌面快捷方式已创建: $shortcut_file"
}

# 创建桌面快捷方式
echo ""
echo "7. 创建桌面快捷方式..."
create_desktop_shortcut

# 8. 直接启动节点
echo ""
echo "🚀 启动节点..."
optimai-cli node start
