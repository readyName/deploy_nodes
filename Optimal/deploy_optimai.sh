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
echo "📋 登录说明:"
echo "• 需要 OptimAI 账户 (如果没有请先注册)"
echo "• 会话会自动保存，无需重复登录"
echo "• 登录信息存储在本地，安全加密"
echo ""
echo "🌐 账户准备:"
echo "   注册地址: https://node.optimai.network/register"
echo "   忘记密码: https://node.optimai.network/forgot-password"
echo ""

# 检查是否已登录
if optimai-cli auth status >/dev/null 2>&1; then
    echo "✅ 检测到已登录状态"
    read -p "是否重新登录? (y/n, 默认 n): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "跳过登录，使用现有会话"
        SKIP_LOGIN=true
    else
        SKIP_LOGIN=false
    fi
else
    SKIP_LOGIN=false
fi

if [ "$SKIP_LOGIN" != "true" ]; then
    read -p "按回车键开始登录 (按 Ctrl+C 取消)..."
    
    echo ""
    echo "🔐 开始登录..."
    echo "════════════════════════════════════════════"
    echo "等待输入邮箱进行登录..."
    echo ""
    
    if optimai-cli auth login; then
        echo ""
        echo "✅ 登录成功！"
    else
        echo ""
        echo "❌ 登录失败"
        echo ""
        echo "🔧 可能的原因:"
        echo "   1. 账户或密码错误"
        echo "   2. 网络连接问题"
        echo "   3. 账户未激活或验证"
        echo "   4. 服务器暂时不可用"
        echo ""
        echo "💡 解决方案:"
        echo "   1. 确认网络连接"
        echo "   2. 检查账户状态"
        echo "   3. 稍后重试"
        echo "   4. 访问: https://optimai.network/support"
        exit 1
    fi
fi

# 6. 询问是否启动节点
echo ""
echo "════════════════════════════════════════════"
echo "6. 启动节点"
echo "════════════════════════════════════════════"
echo ""
read -p "是否立即启动 OptimAI 节点? (y/n, 默认 y): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z "$REPLY" ]]; then
    echo ""
    echo "🚀 启动 OptimAI Core Node..."
    echo "════════════════════════════════════════════"
    echo ""
    
    optimai-cli node start
    
    EXIT_CODE=$?
    
    if [ $EXIT_CODE -eq 0 ]; then
        echo ""
        echo "🎉 节点启动成功！"
        echo ""
        echo "📊 节点信息:"
        echo "   名称: $(hostname)"
        echo "   类型: Core Node"
        echo ""
        echo "🎯 管理命令:"
        echo "   停止节点: optimai-cli node stop"
        echo "   查看状态: optimai-cli node status"
        echo "   查看日志: optimai-cli node logs"
        echo ""
        echo "📈 监控节点:"
        echo "   按 Ctrl+C 停止"
        echo "   保持终端窗口打开"
    else
        echo ""
        echo "❌ 节点启动失败 (退出码: $EXIT_CODE)"
        echo ""
        echo "🔧 故障排除:"
        echo "   1. 检查 Docker 是否运行: docker ps"
        echo "   2. 确保网络连接正常"
        echo "   3. 重新登录: optimai-cli auth login"
        echo ""
        echo "📞 获取帮助: https://docs.optimai.network/troubleshooting"
    fi
else
    echo ""
    echo "📝 您可以稍后手动启动节点:"
    echo "   启动节点: optimai-cli node start"
    echo "   查看状态: optimai-cli node status"
    echo "   停止节点: optimai-cli node stop"
    echo "   查看日志: optimai-cli node logs"
    echo ""
    echo "💡 提示: 节点需要保持运行才能参与网络"
fi

# 7. 完成
echo ""
echo "════════════════════════════════════════════"
echo "🏁 安装和设置流程已完成"
echo "════════════════════════════════════════════"
echo ""
echo "🚀 常用命令:"
echo "   optimai-cli node start    # 启动节点"
echo "   optimai-cli node status   # 查看状态"
echo "   optimai-cli node stop     # 停止节点"
echo "   optimai-cli node logs     # 查看日志"
echo "   optimai-cli auth login    # 重新登录"
echo "   optimai-cli --version     # 查看版本"
echo ""
echo "📞 获取帮助:"
echo "   官方文档: https://docs.optimai.network"
echo "   社区支持: https://t.me/OptimAINetwork"
echo ""
echo "🌈 感谢使用 OptimAI Network！祝您使用愉快！"
