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

PROJECT_DIR="$HOME/OptimAI-Core-Node"
BIN_DIR="$PROJECT_DIR/bin"

echo "📁 项目目录: $PROJECT_DIR"
echo "🖥️  系统检测: macOS $(sw_vers -productVersion)"

# 0. 检查 Homebrew（推荐但不必须）
echo ""
echo "0. 检查系统环境..."
if ! command -v brew &> /dev/null; then
    echo "⚠️  Homebrew 未安装"
    echo "   建议安装 Homebrew 以便管理依赖"
    echo "   安装命令: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    echo ""
fi

# 1. 验证下载的文件
echo ""
echo "1. 验证文件..."
if [ -f "$BIN_DIR/optimai-cli" ]; then
    FILE_SIZE=$(wc -c < "$BIN_DIR/optimai-cli")
    if [ $FILE_SIZE -gt 10000000 ]; then  # 大于10MB
        FILE_SIZE_MB=$(echo "scale=2; $FILE_SIZE/1048576" | bc)
        echo "✅ 文件存在且大小正常 (${FILE_SIZE_MB} MB)"
    else
        echo "⚠️  文件大小异常: $FILE_SIZE 字节"
        echo "   文件可能不完整，请重新下载"
    fi
else
    echo "❌ 文件不存在: $BIN_DIR/optimai-cli"
    echo "   请确保已经下载了 optimai-cli 文件到 bin/ 目录"
    exit 1
fi

# 2. 设置权限
echo ""
echo "2. 设置权限..."
chmod +x "$BIN_DIR/optimai-cli"
if [ -x "$BIN_DIR/optimai-cli" ]; then
    echo "✅ 执行权限已设置"
    
    # 测试版本
    echo "   版本信息: $("$BIN_DIR/optimai-cli" --version 2>/dev/null || echo "无法获取版本")"
else
    echo "❌ 权限设置失败"
    exit 1
fi

# 3. 创建必要目录
echo ""
echo "3. 创建目录结构..."
mkdir -p "$PROJECT_DIR/config" || { echo "❌ 创建 config/ 目录失败"; exit 1; }
mkdir -p "$PROJECT_DIR/data" || { echo "❌ 创建 data/ 目录失败"; exit 1; }
mkdir -p "$PROJECT_DIR/logs" || { echo "❌ 创建 logs/ 目录失败"; exit 1; }
mkdir -p "$PROJECT_DIR/.sessions" || { echo "❌ 创建 .sessions/ 目录失败"; exit 1; }
echo "✅ 目录创建完成:"
echo "   ├── config/     - 配置文件"
echo "   ├── data/       - 节点数据"
echo "   ├── logs/       - 运行日志"
echo "   └── .sessions/  - 会话存储"

# 4. 创建环境配置文件
echo ""
echo "4. 创建配置文件..."
cat > "$PROJECT_DIR/.env" << 'EOF'
#!/bin/bash
# OptimAI Core Node 环境配置
export OPTIMAI_HOME="$HOME/OptimAI-Core-Node"
export OPTIMAI_BIN="$HOME/OptimAI-Core-Node/bin"
export OPTIMAI_DATA="$HOME/OptimAI-Core-Node/data"
export OPTIMAI_LOGS="$HOME/OptimAI-Core-Node/logs"
export OPTIMAI_SESSIONS="$HOME/OptimAI-Core-Node/.sessions"

# Docker 设置
export DOCKER_SOCKET="/var/run/docker.sock"

# 添加到 PATH
export PATH="$HOME/OptimAI-Core-Node/bin:$PATH"

# macOS 特定设置
export OPTIMAI_OS="macOS"
EOF
echo "✅ 环境配置文件创建完成"

# 5. 创建主配置文件
cat > "$PROJECT_DIR/config/node-config.yaml" << 'EOF'
# OptimAI Node 配置 (macOS)
node:
  name: "$(hostname)-mac-node"
  type: core
  version: "1.0"

network:
  mode: mainnet
  endpoint: "https://network.optimai.network"
  region: "auto"

resources:
  cpu_limit: 75  # 百分比 (macOS 建议)
  memory_limit_mb: 4096
  storage_limit_gb: 50
  gpu_enabled: false

logging:
  level: info
  file: "$OPTIMAI_LOGS/node.log"
  max_size_mb: 100
  retention_days: 7

security:
  auto_update: true
  firewall_compatible: true
EOF
echo "✅ 节点配置文件创建完成: $PROJECT_DIR/config/node-config.yaml"

# 6. 创建管理脚本
echo ""
echo "5. 创建管理脚本..."

# 启动脚本
cat > "$PROJECT_DIR/start.sh" << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"

# 加载环境变量
if [ -f .env ]; then
    source .env
else
    echo "❌ 找不到 .env 文件"
    exit 1
fi

clear
echo "╔══════════════════════════════════════════╗"
echo "║      OptimAI Core Node 启动 (macOS)     ║"
echo "║      时间: $(date '+%Y-%m-%d %H:%M:%S')            ║"
echo "╚══════════════════════════════════════════╝"

echo ""
echo "🔍 系统检查..."
echo "主机: $(hostname)"
echo "用户: $(whoami)"
echo "目录: $(pwd)"
echo "系统: $(sw_vers -productName) $(sw_vers -productVersion)"
echo "架构: $(uname -m)"

# 检查 Docker
echo ""
echo "🐳 检查 Docker..."
if ! command -v docker &> /dev/null; then
    echo "❌ Docker 未安装"
    echo ""
    echo "📦 安装 Docker Desktop for macOS:"
    echo "   1. 下载: https://www.docker.com/products/docker-desktop/"
    echo "   2. 双击 Docker.dmg 文件安装"
    echo "   3. 将 Docker 拖到 Applications 文件夹"
    echo "   4. 启动 Docker Desktop"
    echo "   5. 同意服务条款并完成设置"
    exit 1
fi

if ! docker info &> /dev/null; then
    echo "❌ Docker 服务未运行"
    echo ""
    echo "🚀 启动 Docker Desktop..."
    echo "   请执行以下操作:"
    echo "   1. 按 Cmd + Space 打开 Spotlight"
    echo "   2. 搜索 'Docker' 并启动"
    echo "   3. 等待 Docker 图标出现在菜单栏"
    echo "   4. 确认 Docker 正在运行"
    echo ""
    echo "💡 或运行: open -a Docker"
    read -p "按回车键继续 (确认 Docker 已启动)..." 
    
    # 再次检查
    if ! docker info &> /dev/null; then
        echo "❌ Docker 仍未运行，请手动启动后重试"
        exit 1
    fi
fi

DOCKER_VERSION=$(docker --version | cut -d' ' -f3 | tr -d ',')
echo "✅ Docker 运行正常 (版本: $DOCKER_VERSION)"

# 检查是否登录
echo ""
echo "🔐 检查登录状态..."
if [ -f "$OPTIMAI_SESSIONS/token" ] || [ -f "$OPTIMAI_SESSIONS/session.json" ]; then
    echo "✅ 检测到会话文件，跳过登录"
else
    echo "⚠️  未找到会话文件"
    echo "   需要先登录: ./login.sh"
    read -p "是否现在登录? (y/n): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        ./login.sh
        if [ $? -ne 0 ]; then
            exit 1
        fi
    else
        echo "❌ 需要登录后才能启动节点"
        exit 1
    fi
fi

# 启动节点
echo ""
echo "🚀 启动 OptimAI Core Node..."
echo "════════════════════════════════════════════"

# 确保日志目录存在
mkdir -p "$OPTIMAI_LOGS"

# 启动命令
echo "正在启动 OptimAI 节点..."
"$OPTIMAI_BIN/optimai-cli" node start

EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo ""
    echo "🎉 节点启动成功！"
    echo ""
    echo "📊 节点信息:"
    echo "   名称: $(hostname)-mac-node"
    echo "   类型: Core Node"
    echo "   网络: Mainnet"
    echo "   日志: $OPTIMAI_LOGS/node.log"
    echo "   数据: $OPTIMAI_DATA"
    echo ""
    echo "🎯 管理命令:"
    echo "   停止节点: ./stop.sh"
    echo "   查看状态: ./status.sh"
    echo "   查看日志: tail -f logs/node.log"
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
    echo "   2. 查看详细日志: tail -f logs/node.log"
    echo "   3. 确保网络连接正常"
    echo "   4. 重新登录: ./login.sh"
    echo ""
    echo "📞 获取帮助: https://docs.optimai.network/troubleshooting"
fi
EOF

chmod +x "$PROJECT_DIR/start.sh"
echo "✅ 启动脚本创建完成: $PROJECT_DIR/start.sh"

# 登录脚本
cat > "$PROJECT_DIR/login.sh" << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"

# 加载环境变量
if [ -f .env ]; then
    source .env
else
    echo "❌ 找不到 .env 文件"
    exit 1
fi

clear
echo "╔══════════════════════════════════════════╗"
echo "║      OptimAI 账户登录 (macOS)           ║"
echo "║      时间: $(date '+%Y-%m-%d %H:%M:%S')            ║"
echo "╚══════════════════════════════════════════╝"

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

read -p "按回车键开始登录 (按 Ctrl+C 取消)..."

echo ""
echo "🔐 开始登录..."
echo "════════════════════════════════════════════"

# 确保会话目录存在
mkdir -p "$OPTIMAI_SESSIONS"

# 执行登录
echo "正在打开浏览器进行登录..."
"$OPTIMAI_BIN/optimai-cli" auth login

LOGIN_CODE=$?

if [ $LOGIN_CODE -eq 0 ]; then
    echo ""
    echo "🎉 登录成功！"
    echo ""
    echo "✅ 会话信息已保存到: $OPTIMAI_SESSIONS/"
    echo ""
    echo "🚀 现在可以启动节点:"
    echo "   ./start.sh"
    echo ""
    echo "📝 其他选项:"
    echo "   ./status.sh  - 查看系统状态"
    echo "   ls -la .sessions/ - 查看会话文件"
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
fi

exit $LOGIN_CODE
EOF

chmod +x "$PROJECT_DIR/login.sh"
echo "✅ 登录脚本创建完成: $PROJECT_DIR/login.sh"

# 状态检查脚本
cat > "$PROJECT_DIR/status.sh" << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"

# 加载环境变量
if [ -f .env ]; then
    source .env
else
    echo "❌ 找不到 .env 文件"
    exit 1
fi

clear
echo "╔══════════════════════════════════════════╗"
echo "║      OptimAI 节点状态 (macOS)           ║"
echo "║      时间: $(date '+%Y-%m-%d %H:%M:%S')            ║"
echo "╚══════════════════════════════════════════╝"

echo ""
echo "🔍 系统状态:"
echo "════════════════════════════════════════════"
echo "主机名: $(hostname)"
echo "系统: $(sw_vers -productName) $(sw_vers -productVersion)"
echo "架构: $(uname -m)"
UPTIME=$(uptime | sed -E 's/.*up ([^,]*), .*/\1/')
echo "运行时间: $UPTIME"

echo ""
echo "🐳 Docker 状态:"
echo "════════════════════════════════════════════"
if command -v docker &> /dev/null && docker info &> /dev/null; then
    DOCKER_VERSION=$(docker --version | cut -d' ' -f3 | tr -d ',')
    echo "✅ 状态: 运行中"
    echo "版本: $DOCKER_VERSION"
    
    # 容器统计
    RUNNING_CONTAINERS=$(docker ps -q 2>/dev/null | wc -l)
    TOTAL_CONTAINERS=$(docker ps -a -q 2>/dev/null | wc -l)
    echo "容器: $RUNNING_CONTAINERS 运行中 / $TOTAL_CONTAINERS 总计"
    
    # 检查 OptimAI 容器
    OPTIMAI_CONTAINERS=$(docker ps --filter "name=optimai" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null)
    if [ -n "$OPTIMAI_CONTAINERS" ]; then
        echo "OptimAI 容器:"
        echo "$OPTIMAI_CONTAINERS"
    fi
else
    echo "❌ 状态: 未运行"
    echo "💡 启动 Docker: open -a Docker"
fi

echo ""
echo "📊 系统资源:"
echo "════════════════════════════════════════════"
# CPU 使用率
CPU_USAGE=$(top -l 1 | grep "CPU usage" | sed 's/.*: //')
echo "CPU: $CPU_USAGE"

# 内存信息
MEMORY_INFO=$(memory_pressure 2>/dev/null)
if [ $? -eq 0 ]; then
    MEMORY_FREE=$(echo "$MEMORY_INFO" | grep "System-wide memory free percentage" | cut -d: -f2)
    echo "内存:${MEMORY_FREE} 可用"
else
    MEMORY_FREE=$(vm_stat | grep "free" | awk '{print $3}' | sed 's/\.//')
    MEMORY_INACTIVE=$(vm_stat | grep "inactive" | awk '{print $3}' | sed 's/\.//')
    MEMORY_TOTAL=$((($MEMORY_FREE + $MEMORY_INACTIVE) * 4096 / 1048576))
    echo "内存: 约 $MEMORY_TOTAL MB 可用"
fi

# 磁盘空间
DISK_INFO=$(df -h . | tail -1)
DISK_TOTAL=$(echo $DISK_INFO | awk '{print $2}')
DISK_USED=$(echo $DISK_INFO | awk '{print $3}')
DISK_AVAIL=$(echo $DISK_INFO | awk '{print $4}')
DISK_PERCENT=$(echo $DISK_INFO | awk '{print $5}')
echo "磁盘: $DISK_AVAIL 可用 / $DISK_TOTAL 总计 ($DISK_PERCENT 使用)"

echo ""
echo "🔐 OptimAI 状态:"
echo "════════════════════════════════════════════"
# 检查会话文件
SESSION_FILES=$(find "$OPTIMAI_SESSIONS" -type f -name "*.json" -o -name "token" 2>/dev/null | wc -l)
if [ $SESSION_FILES -gt 0 ]; then
    echo "✅ 登录状态: 已登录 ($SESSION_FILES 个会话文件)"
else
    echo "❌ 登录状态: 未登录"
fi

# 检查节点进程
NODE_PID=$(ps aux | grep -v grep | grep "[o]ptimai-cli" | grep -v "status.sh" | awk '{print $2}')
if [ -n "$NODE_PID" ]; then
    echo "✅ 节点进程: 运行中 (PID: $NODE_PID)"
    
    # 获取进程详情
    PROCESS_INFO=$(ps -p $NODE_PID -o %cpu,%mem,etime,command 2>/dev/null | tail -1)
    if [ -n "$PROCESS_INFO" ]; then
        CPU_PERCENT=$(echo $PROCESS_INFO | awk '{print $1}')
        MEM_PERCENT=$(echo $PROCESS_INFO | awk '{print $2}')
        ELAPSED_TIME=$(echo $PROCESS_INFO | awk '{print $3}')
        echo "   资源: CPU $CPU_PERCENT%, 内存 $MEM_PERCENT%"
        echo "   运行时间: $ELAPSED_TIME"
    fi
else
    echo "❌ 节点进程: 未运行"
fi

echo ""
echo "🗂️  项目信息:"
echo "════════════════════════════════════════════"
echo "位置: $OPTIMAI_HOME"
echo "版本: $("$OPTIMAI_BIN/optimai-cli" --version 2>/dev/null || echo "未知")"
echo "数据: $(du -sh data/ 2>/dev/null | cut -f1 || echo "0B")"
echo "日志: $(du -sh logs/ 2>/dev/null | cut -f1 || echo "0B")"
echo "配置: $(du -sh config/ 2>/dev/null | cut -f1 || echo "0B")"

echo ""
echo "🚀 快速命令:"
echo "════════════════════════════════════════════"
echo "启动节点: ./start.sh"
echo "重新登录: ./login.sh"
echo "停止节点: ./stop.sh"
echo "查看日志: tail -f logs/node.log"
echo "清空日志: > logs/node.log"
echo "查看版本: ./bin/optimai-cli --version"
echo ""
echo "🌐 获取帮助: https://docs.optimai.network"
EOF

chmod +x "$PROJECT_DIR/status.sh"
echo "✅ 状态脚本创建完成: $PROJECT_DIR/status.sh"

# 停止脚本
cat > "$PROJECT_DIR/stop.sh" << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"

# 加载环境变量
if [ -f .env ]; then
    source .env
else
    echo "❌ 找不到 .env 文件"
    exit 1
fi

echo "╔══════════════════════════════════════════╗"
echo "║      OptimAI 节点停止 (macOS)           ║"
echo "║      时间: $(date '+%Y-%m-%d %H:%M:%S')            ║"
echo "╚══════════════════════════════════════════╝"

echo ""
echo "🛑 停止 OptimAI 节点..."
echo "════════════════════════════════════════════"

# 方法1: 使用 CLI 停止
echo "1. 使用 CLI 停止命令..."
if [ -f "$OPTIMAI_BIN/optimai-cli" ]; then
    "$OPTIMAI_BIN/optimai-cli" node stop 2>/dev/null
    sleep 3
fi

# 方法2: 停止进程
echo "2. 查找运行中的节点进程..."
NODE_PID=$(ps aux | grep -v grep | grep "[o]ptimai-cli" | grep -v "stop.sh" | awk '{print $2}')

if [ -n "$NODE_PID" ]; then
    echo "   发现进程 PID: $NODE_PID"
    
    # 优雅停止
    echo "   发送停止信号..."
    kill -TERM $NODE_PID 2>/dev/null
    sleep 5
    
    # 检查是否仍在运行
    if ps -p $NODE_PID > /dev/null 2>&1; then
        echo "   进程仍在运行，强制停止..."
        kill -9 $NODE_PID 2>/dev/null
        sleep 2
    fi
    
    echo "   ✅ 进程已停止"
else
    echo "   ℹ️  未找到运行中的节点进程"
fi

# 方法3: 停止 Docker 容器
echo "3. 检查 OptimAI Docker 容器..."
OPTIMAI_CONTAINERS=$(docker ps -q --filter "name=optimai" 2>/dev/null)

if [ -n "$OPTIMAI_CONTAINERS" ]; then
    echo "   停止 Docker 容器..."
    docker stop $OPTIMAI_CONTAINERS 2>/dev/null
    
    # 检查并清理
    STOPPED_CONTAINERS=$(docker ps -a -q --filter "name=optimai" --filter "status=exited" 2>/dev/null)
    if [ -n "$STOPPED_CONTAINERS" ]; then
        echo "   清理已停止的容器..."
        docker rm $STOPPED_CONTAINERS 2>/dev/null
    fi
    echo "   ✅ Docker 容器已停止"
else
    echo "   ℹ️  未找到 OptimAI Docker 容器"
fi

echo ""
echo "✅ 节点停止完成"
echo ""
echo "📊 验证停止状态:"
echo "   运行: ./status.sh"
echo "   或: ps aux | grep optimai"
echo ""
echo "🚀 重新启动:"
echo "   登录: ./login.sh"
echo "   启动: ./start.sh"
EOF

chmod +x "$PROJECT_DIR/stop.sh"
echo "✅ 停止脚本创建完成: $PROJECT_DIR/stop.sh"

# 7. 创建 macOS 优化 README
cat > "$PROJECT_DIR/README.macOS.md" << 'README_EOF'
# OptimAI Core Node (macOS 版)

✅ 安装和设置已完成，可以开始使用！

## 🍎 macOS 系统要求

### 最低要求
- macOS 11.0 (Big Sur) 或更高版本
- 8 GB RAM (推荐 16 GB)
- 50 GB 可用磁盘空间
- Docker Desktop 4.0+

### 推荐配置
- macOS 12.0+ (Monterey 或更高)
- Apple Silicon (M1/M2/M3) 或 Intel Core i5+
- 16 GB RAM
- 100 GB SSD 空间
- 稳定的网络连接

## 🚀 快速开始

### 1. 安装 Docker (如果未安装)
\`\`\`bash
# 方式1: 手动下载
# 访问: https://www.docker.com/products/docker-desktop/
# 下载 Docker.dmg，安装并启动

# 方式2: 使用 Homebrew (推荐)
brew install --cask docker
open -a Docker  # 启动 Docker
\`\`\`

### 2. 登录账户
\`\`\`bash
./login.sh
\`\`\`
> **注意**: 如果没有账户，请先访问 https://node.optimai.network/register 注册

### 3. 启动节点
\`\`\`bash
./start.sh
\`\`\`

### 4. 查看状态
\`\`\`bash
./status.sh
\`\`\`

## 📁 项目结构
\`\`\`
OptimAI-Core-Node/
├── bin/
│   └── optimai-cli              # 主程序 (macOS 版)
├── config/
│   └── node-config.yaml         # macOS 优化配置
├── data/                        # 节点数据 (加密存储)
├── logs/                        # 运行日志
├── .sessions/                   # 会话文件 (自动保存)
├── .env                         # 环境变量 (macOS 优化)
├── start.sh                     # 启动脚本
├── login.sh                     # 登录脚本
├── status.sh                    # 状态检查 (macOS 版)
├── stop.sh                      # 停止脚本
└── README.macOS.md              # 本文件
\`\`\`

## 🛠️ 常用命令

### 节点管理
\`\`\`bash
# 启动节点 (前台运行)
./start.sh

# 停止节点
./stop.sh

# 查看实时状态
./status.sh

# 查看实时日志
tail -f logs/node.log

# 查看版本信息
./bin/optimai-cli --version
\`\`\`

### Docker 管理
\`\`\`bash
# 检查 Docker 状态
docker ps
docker info

# 查看 OptimAI 容器
docker ps --filter "name=optimai"

# 查看容器日志
docker logs <container_name>
\`\`\`

### 系统监控
\`\`\`bash
# 查看资源使用
top
htop  # 需安装: brew install htop

# 查看网络连接
netstat -an | grep LISTEN
lsof -i :<port>

# 查看磁盘空间
df -h
du -sh data/
\`\`\`

## 🔧 故障排除

### Docker 相关问题
\`\`\`bash
# 1. Docker 未运行
open -a Docker

# 2. Docker 权限问题
sudo chmod 666 /var/run/docker.sock

# 3. 重启 Docker
osascript -e 'quit app "Docker"'
sleep 3
open -a Docker
\`\`\`

### 节点启动失败
1. **检查 Docker**: \`docker ps\`
2. **查看日志**: \`tail -f logs/node.log\`
3. **检查网络**: \`ping network.optimai.network\`
4. **重新登录**: \`./login.sh\`
5. **清理后重试**: \`./stop.sh && ./start.sh\`

### 登录问题
1. **确认账户已注册**: https://optimai.network
2. **检查网络连接**: 确保可以访问外网
3. **清除会话文件**: \`rm -rf .sessions/*\`
4. **重新登录**: \`./login.sh\`

### 性能优化 (macOS)
\`\`\`bash
# 增加 Docker 资源限制 (Docker Desktop 设置)
# 1. 点击菜单栏 Docker 图标
# 2. 选择 Preferences → Resources
# 3. 建议设置:
#    - CPUs: 4+ cores
#    - Memory: 8+ GB
#    - Swap: 2 GB
#    - Disk image size: 64+ GB

# 启用 Docker 缓存 (优化性能)
# 在 Docker Desktop → Preferences → Docker Engine 添加:
#   "builder": {
#     "gc": {
#       "enabled": true,
#       "defaultKeepStorage": "20GB"
#     }
#   }
\`\`\`

## 📊 监控和日志

### 日志文件位置
\`\`\`bash
# 主要日志
logs/node.log

# Docker 日志
~/Library/Containers/com.docker.docker/Data/log/vm/*.log

# 系统日志
console.app  # 查看系统日志
\`\`\`

### 自动清理日志
\`\`\`bash
# 手动清理旧日志
find logs/ -name "*.log" -type f -mtime +7 -delete

# 清空当前日志
> logs/node.log
\`\`\`

## 🔒 安全注意事项

### 文件权限
\`\`\`bash
# 建议的权限设置
chmod 700 .sessions/       # 会话文件仅自己可访问
chmod 600 .sessions/*.json # 会话数据加密
chmod 644 config/*.yaml    # 配置文件只读
\`\`\`

### 数据备份
\`\`\`bash
# 备份重要数据
tar -czf backup-$(date +%Y%m%d).tar.gz config/ .env .sessions/
\`\`\`

## 📞 获取帮助

### 官方渠道
- **文档**: https://docs.optimai.network
- **官网**: https://optimai.network
- **GitHub**: https://github.com/optimainetwork
- **社区支持**: https://t.me/OptimAINetwork

### 常见问题
- [macOS 安装问题](https://docs.optimai.network/installation/macos)
- [Docker 配置指南](https://docs.optimai.network/docker-setup)
- [网络故障排除](https://docs.optimai.network/troubleshooting/network)

### 联系支持
1. 查看日志文件: \`cat logs/node.log | tail -50\`
2. 提供系统信息: \`./status.sh\`
3. 访问支持页面: https://optimai.network/support

---
**版本**: 1.0 (macOS 优化版)  
**更新日期**: $(date +%Y-%m-%d)  
**适用于**: macOS 11.0+ (Intel & Apple Silicon)
README_EOF

echo "✅ macOS 专属文档创建完成: $PROJECT_DIR/README.macOS.md"

# 8. 创建简化的 README.md (兼容原有)
cat > "$PROJECT_DIR/README.md" << 'EOF'
# OptimAI Core Node

欢迎使用 OptimAI Core Node！本项目已针对 macOS 系统进行优化。

## 🍎 macOS 用户
请查看详细指南: [README.macOS.md](README.macOS.md)

## 快速开始
1. 确保 Docker Desktop 已安装并运行
2. 登录账户: `./login.sh`
3. 启动节点: `./start.sh`

## 获取帮助
- 官方文档: https://docs.optimai.network
- macOS 专用指南: https://docs.optimai.network/installation/macos
- 社区支持: https://t.me/OptimAINetwork
EOF

echo "✅ 通用 README 创建完成"

# 9. 最终验证
echo ""
echo "6. 最终验证..."
echo "════════════════════════════════════════════"

# 验证所有文件
echo "📋 验证所有文件..."
FILES_TO_CHECK=(
    "$BIN_DIR/optimai-cli"
    "$PROJECT_DIR/.env"
    "$PROJECT_DIR/config/node-config.yaml"
    "$PROJECT_DIR/start.sh"
    "$PROJECT_DIR/login.sh"
    "$PROJECT_DIR/status.sh"
    "$PROJECT_DIR/stop.sh"
    "$PROJECT_DIR/README.macOS.md"
)

ALL_OK=true
for file in "${FILES_TO_CHECK[@]}"; do
    if [ -f "$file" ]; then
        if [[ "$file" == *.sh ]] && [ -x "$file" ]; then
            echo "✅ $file (可执行)"
        elif [ -r "$file" ]; then
            echo "✅ $file"
        else
            echo "❌ $file (权限问题)"
            ALL_OK=false
        fi
    else
        echo "❌ $file (不存在)"
        ALL_OK=false
    fi
done

# 验证目录
echo ""
echo "📁 验证目录..."
DIRS_TO_CHECK=(
    "$PROJECT_DIR"
    "$PROJECT_DIR/bin"
    "$PROJECT_DIR/config"
    "$PROJECT_DIR/data"
    "$PROJECT_DIR/logs"
    "$PROJECT_DIR/.sessions"
)

for dir in "${DIRS_TO_CHECK[@]}"; do
    if [ -d "$dir" ]; then
        echo "✅ $dir"
    else
        echo "❌ $dir"
        ALL_OK=false
    fi
done

# 验证 Docker 访问
echo ""
echo "🐳 验证 Docker 访问..."
if command -v docker &> /dev/null; then
    if docker info &> /dev/null; then
        echo "✅ Docker 可访问"
    else
        echo "⚠️  Docker 已安装但服务未运行"
        echo "   运行: open -a Docker"
        echo "   然后重新验证"
    fi
else
    echo "❌ Docker 未安装"
    echo "   请安装 Docker Desktop for macOS"
    ALL_OK=false
fi

# 10. 安装完成 - 自动化流程版本
echo ""
echo -e "╔══════════════════════════════════════════╗"
echo -e "║          🎉 设置完成！                  ║"
echo -e "║          🍎 macOS 优化版                ║"
echo -e "╚══════════════════════════════════════════╝"

if [ "$ALL_OK" = true ]; then
    echo ""
    echo "✅ 所有检查通过！"
else
    echo ""
    echo "⚠️  部分检查未通过，请查看上方提示"
fi

echo ""
echo "📁 项目目录: $PROJECT_DIR"
echo ""
echo "📚 重要文件已创建:"
echo "   ✅ 配置文件: config/node-config.yaml"
echo "   ✅ 环境变量: .env"
echo "   ✅ 启动脚本: start.sh"
echo "   ✅ 详细文档: README.macOS.md"

# 自动进入目录并开始登录流程
echo ""
echo "🚀 自动进入项目目录并开始登录流程..."
cd "$PROJECT_DIR"
echo "📂 当前目录: $(pwd)"

echo ""
echo "🔐 准备登录 OptimAI 账户"
echo "════════════════════════════════════════════"
echo "📋 登录须知:"
echo "   1. 需要 OptimAI 账户"
echo "   2. 如果没有账户，请先注册"
echo "   3. 登录信息会安全保存在本地"
echo ""
echo "🌐 注册地址: https://node.optimai.network/register"
echo "🔑 密码重置: https://optimai.network/reset-password"
echo "════════════════════════════════════════════"

# 检查 Docker 状态
echo ""
echo "🐳 检查 Docker 状态..."
if command -v docker &> /dev/null && docker info &> /dev/null; then
    echo "✅ Docker 运行正常"
else
    echo "❌ Docker 未运行或未安装"
    echo "   请先启动 Docker Desktop 后再继续"
    echo "   启动命令: open -a Docker"
    echo ""
    echo "⏳ 等待 5 秒，请确认 Docker 已启动..."
    sleep 5
    
    # 再次检查
    if ! command -v docker &> /dev/null || ! docker info &> /dev/null; then
        echo "❌ Docker 仍未运行"
        echo "   请手动启动 Docker Desktop 后运行:"
        echo "   cd \"$PROJECT_DIR\" && ./login.sh"
        exit 1
    fi
    echo "✅ Docker 现在运行正常"
fi

# 开始登录
echo ""
echo "⏳ 3秒后开始登录..."
sleep 3

clear
echo "╔══════════════════════════════════════════╗"
echo "║      OptimAI 账户登录 (macOS)           ║"
echo "║      时间: $(date '+%Y-%m-%d %H:%M:%S')            ║"
echo "╚══════════════════════════════════════════╝"

# 执行登录脚本
./login.sh

LOGIN_RESULT=$?

echo ""
echo "════════════════════════════════════════════"

if [ $LOGIN_RESULT -eq 0 ]; then
    echo ""
    echo "🎉 登录成功！准备启动节点..."
    echo ""
    
    # 询问是否立即启动节点
    read -p "是否立即启动 OptimAI 节点? (y/n): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "🚀 启动 OptimAI Core Node..."
        echo "════════════════════════════════════════════"
        ./start.sh
    else
        echo ""
        echo "📝 您可以稍后手动启动节点:"
        echo "   启动节点: ./start.sh"
        echo "   查看状态: ./status.sh"
        echo "   停止节点: ./stop.sh"
        echo ""
        echo "💡 提示: 节点需要保持运行才能参与网络"
    fi
else
    echo ""
    echo "❌ 登录失败或取消"
    echo ""
    echo "📝 您可以稍后重新登录:"
    echo "   cd \"$(pwd)\""
    echo "   ./login.sh"
    echo ""
    echo "🔧 故障排除:"
    echo "   1. 确认网络连接正常"
    echo "   2. 确认账户已注册"
    echo "   3. 检查账户密码是否正确"
    echo "   4. 访问: https://optimai.network/support"
fi

echo ""
echo "════════════════════════════════════════════"
echo "🏁 安装和设置流程已完成"
echo ""
echo "📁 项目位置: $(pwd)"
echo "📖 详细指南: 查看 README.macOS.md 文件"
echo ""
echo "🚀 常用命令:"
echo "   ./start.sh    # 启动节点"
echo "   ./status.sh   # 查看状态"
echo "   ./stop.sh     # 停止节点"
echo "   ./login.sh    # 重新登录"
echo ""
echo "📞 获取帮助: https://docs.optimai.network"
echo "👥 加入社区: https://t.me/OptimAINetwork"
echo ""
echo "🌈 感谢使用 OptimAI Network！祝您使用愉快！"