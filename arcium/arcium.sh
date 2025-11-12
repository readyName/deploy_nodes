#!/bin/bash

# Arcium 节点部署脚本
# 专注运行 Arx 验证节点

set -e

# 颜色定义 - 修复版本
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 修复的日志函数 - 使用 printf 确保兼容性
log() { 
    printf "${BLUE}[%s]${NC} %s\n" "$(date +'%H:%M:%S')" "$1" >&2
}
success() { 
    printf "${GREEN}✓${NC} %s\n" "$1" >&2
}
warning() { 
    printf "${YELLOW}⚠${NC} %s\n" "$1" >&2
}
error() { 
    printf "${RED}✗${NC} %s\n" "$1" >&2
}
info() { 
    printf "${CYAN}ℹ${NC} %s\n" "$1" >&2
}

# 配置变量
RPC_ENDPOINT=${RPC_ENDPOINT:-"https://api.devnet.solana.com"}
WSS_ENDPOINT=${WSS_ENDPOINT:-"wss://api.devnet.solana.com"}
NODE_PORT=${NODE_PORT:-8080}
CLUSTER_OFFSET=${CLUSTER_OFFSET:-""}
NODE_DIR="$HOME/arcium-node-setup"
CLUSTER_DIR="$HOME/arcium-cluster-setup"

# 检查命令是否存在
check_cmd() {
    if command -v "$1" > /dev/null 2>&1; then
        success "找到 $1"
        return 0
    else
        warning "未找到 $1"
        return 1
    fi
}

# 检查端口可用性
check_port_availability() {
    local port=$1
    if command -v lsof >/dev/null 2>&1; then
        if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null ; then
            warning "端口 $port 已被占用"
            return 1
        fi
    elif command -v netstat >/dev/null 2>&1; then
        if netstat -tuln | grep -q ":$port "; then
            warning "端口 $port 已被占用"
            return 1
        fi
    fi
    success "端口 $port 可用"
    return 0
}

# 安装依赖
install_dependencies() {
    log "安装系统依赖..."
    
    # 检测系统类型
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux - 根据 README 补充完整依赖
        sudo apt update && sudo apt upgrade -y
        sudo apt install curl iptables build-essential git wget lz4 jq make gcc nano automake autoconf tmux htop nvme-cli pkg-config libssl-dev libleveldb-dev tar clang bsdmainutils ncdu unzip libleveldb-dev libudev-dev protobuf-compiler bc -y
        
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # Mac OSX
        if ! check_cmd "brew"; then
            log "安装 Homebrew..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        fi
        brew update || true
        brew install curl git wget jq make gcc automake autoconf tmux htop pkg-config openssl protobuf bc || {
            warning "部分包安装失败，尝试继续执行..."
            brew install bc || warning "bc 安装失败，脚本将继续运行但可能影响功能"
        }
    fi
    # === 在这里添加 bc 命令检查 ===
    if ! command -v bc >/dev/null 2>&1; then
        warning "bc 命令未安装，尝试安装..."
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            sudo apt install -y bc
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            brew install bc
        fi
    fi
    
    if command -v bc >/dev/null 2>&1; then
        success "bc 命令已就绪"
    else
        warning "bc 命令安装失败，浮点数比较功能可能受影响"
    fi
    # === 添加结束 ===
}

# 安装 Rust
install_rust() {
    if ! check_cmd "cargo"; then
        log "安装 Rust..."
        # 使用 README 中的安装命令
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        
        # 设置环境变量 (README 中强调)
        source "$HOME/.cargo/env"
        export PATH="$HOME/.cargo/bin:$PATH"
        
        # 更新 Rust
        rustup update
        success "Rust 安装完成: $(rustc --version)"
    fi
    
    # 设置 Rust 镜像
    log "设置 Rust 镜像..."
    mkdir -p ~/.cargo
    cat > ~/.cargo/config.toml << 'EOF'
[source.crates-io]
replace-with = 'ustc'

[source.ustc]
registry = "git://mirrors.ustc.edu.cn/crates.io-index"

[net]
git-fetch-with-cli = true
EOF
    success "Rust 镜像设置完成"
}

# 安装 Solana CLI
install_solana() {
    if ! check_cmd "solana"; then
        log "安装 Solana CLI..."
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            sh -c "$(curl -sSfL https://release.solana.com/v1.18.18/install)"
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            brew install solana
        fi
        
        # 添加到 PATH
        echo 'export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"' >> ~/.bashrc
        echo 'export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"' >> ~/.zshrc
        export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"
        
        success "Solana 安装完成"
    fi
    
    # 配置 Solana
    log "配置 Solana Devnet..."
    solana config set --url "$RPC_ENDPOINT"
    success "Solana 配置完成"
}

# 安装 Docker
install_docker() {
    # 先检查 Docker 是否已经安装
    if check_cmd "docker"; then
        success "Docker 已安装: $(docker --version)"
        
        # 检查 Docker 是否在运行 (macOS)
        if [[ "$OSTYPE" == "darwin"* ]]; then
            if ! docker info > /dev/null 2>&1; then
                warning "Docker 已安装但未运行"
                info "请启动 Docker Desktop 后继续"
                return 1
            fi
        fi
        return 0
    fi
    
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        log "安装 Docker..."
        sudo apt install -y ca-certificates curl gnupg software-properties-common
        sudo install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        sudo chmod a+r /etc/apt/keyrings/docker.gpg
        
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        sudo apt update
        sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        
        sudo systemctl start docker
        sudo systemctl enable docker
        sudo usermod -aG docker $USER
        
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        log "请手动安装 Docker Desktop for Mac"
        info "访问: https://docs.docker.com/desktop/setup/install/mac-install/"
        info "安装后重新运行此脚本"
        return 1
    fi
    
    success "Docker 安装完成"
}

# 安装 Anchor 框架
install_anchor() {
    if ! check_cmd "anchor"; then
        log "安装 Anchor 框架..."
        
        # 确保 Rust 环境变量已设置
        source "$HOME/.cargo/env" 2>/dev/null || true
        export PATH="$HOME/.cargo/bin:$PATH"
        
        # 安装 avm
        log "安装 avm..."
        if ! cargo install --git https://github.com/coral-xyz/anchor avm --locked --force; then
            error "avm 安装失败"
            return 1
        fi
        
        # 设置环境变量
        export PATH="$HOME/.cargo/bin:$PATH"
        
        # 安装并使用最新版 Anchor
        log "安装最新版 Anchor..."
        if ! avm install latest; then
            error "Anchor 安装失败"
            return 1
        fi
        
        if ! avm use latest; then
            error "Anchor 切换版本失败"
            return 1
        fi
        
        # 验证安装
        if check_cmd "anchor"; then
            success "Anchor 安装完成: $(anchor --version)"
        else
            error "Anchor 安装后仍不可用，请手动安装"
            return 1
        fi
    else
        # 如果 anchor 已存在但版本未设置，设置版本
        if ! anchor --version >/dev/null 2>&1; then
            log "设置 Anchor 版本..."
            source "$HOME/.cargo/env" 2>/dev/null || true
            export PATH="$HOME/.cargo/bin:$PATH"
            avm use latest
        fi
        success "Anchor 已安装: $(anchor --version)"
    fi
}

# 安装 Arcium - 修改为带重试的版本
install_arcium() {
    if ! check_cmd "arcium"; then
        log "安装 Arcium..."
        
        # 创建目录 (README 中强调)
        mkdir -p "$HOME/arcium-node-setup"
        cd "$HOME/arcium-node-setup"
        
        # 使用 README 中的安装命令
        local max_retries=3
        local retry_count=0
        
        while [ $retry_count -lt $max_retries ]; do
            if curl --proto '=https' --tlsv1.2 -sSfL https://arcium-install.arcium.workers.dev/ | bash; then
                success "Arcium 安装完成"
                success "Arcium 版本: $(arcium --version)"
                success "Arcup 版本: $(arcup --version 2>/dev/null || echo '未安装')"
                return 0
            else
                retry_count=$((retry_count + 1))
                warning "安装失败，第 $retry_count 次重试..."
                sleep 5
            fi
        done
        
        error "Arcium 安装失败，请检查网络连接"
        return 1
    fi
}

# ========== 新的集群管理函数 ==========

# 修复的集群存在检查函数
check_cluster_exists() {
    local cluster_offset=$1
    # 完全静默检查，不显示任何错误信息
    if arcium fee-proposals $cluster_offset --rpc-url "$RPC_ENDPOINT" >/dev/null 2>&1; then
        return 0  # 集群存在
    else
        return 1  # 集群不存在
    fi
}


# 创建集群所有者密钥
create_cluster_owner_keypair() {
    log "创建集群所有者密钥..."
    
    if [[ -f "cluster-owner-keypair.json" ]]; then
        if solana address --keypair cluster-owner-keypair.json >/dev/null 2>&1; then
            local owner_address=$(solana address --keypair cluster-owner-keypair.json)
            success "使用现有集群所有者密钥"
            success "集群所有者地址: $owner_address"
            return 0
        else
            warning "现有密钥文件损坏，创建新密钥..."
            rm -f cluster-owner-keypair.json
        fi
    fi
    
    # 创建新密钥
    if solana-keygen new --outfile cluster-owner-keypair.json --no-bip39-passphrase --silent --force; then
        local owner_address=$(solana address --keypair cluster-owner-keypair.json)
        success "创建集群所有者密钥成功"
        success "集群所有者地址: $owner_address"
    else
        error "创建集群所有者密钥失败"
        return 1
    fi
}

# 检查并获取空投
check_and_airdrop() {
    log "检查集群所有者余额..."
    
    local owner_address=$(solana address --keypair cluster-owner-keypair.json)
    local balance_output=$(solana balance $owner_address --url "$RPC_ENDPOINT" 2>/dev/null || echo "0 SOL")
    local balance=$(echo "$balance_output" | cut -d' ' -f1)
    
    success "当前余额: $balance SOL"
    
    # 简化余额检查（避免依赖 bc）
    if [[ "$balance" == "0" ]] || [[ "$balance" == "0.0" ]] || [[ "$balance_output" == *"error"* ]]; then
        log "余额不足或无法获取，获取空投..."
        if solana airdrop 5 $owner_address -u devnet 2>/dev/null; then
            success "空投请求已提交，等待到账..."
            
            # 等待余额到账
            local max_checks=8
            local check_count=0
            
            while [ $check_count -lt $max_checks ]; do
                sleep 8
                balance_output=$(solana balance $owner_address --url "$RPC_ENDPOINT" 2>/dev/null || echo "0 SOL")
                balance=$(echo "$balance_output" | cut -d' ' -f1)
                check_count=$((check_count + 1))
                
                if [[ "$balance" != "0" ]] && [[ "$balance" != "0.0" ]]; then
                    success "余额到账: $balance SOL"
                    break
                else
                    info "等待余额到账... ($check_count/$max_checks)"
                fi
            done
            
            if [[ "$balance" == "0" ]] || [[ "$balance" == "0.0" ]]; then
                warning "空投可能未到账，当前余额: $balance SOL"
                info "请手动获取空投: https://faucet.solana.com/"
                info "地址: $owner_address"
                read -p "获取空投后按回车键继续..."
            fi
        else
            warning "自动空投失败，请手动获取空投"
            info "集群所有者地址: $owner_address"
            info "请访问: https://faucet.solana.com/"
            read -p "获取空投后按回车键继续..."
        fi
    else
        success "余额充足，跳过空投"
    fi
}

# 生成集群偏移量
generate_cluster_offset() {
    log "生成集群偏移量..."
    
    # 使用大范围随机数减少冲突概率
    local cluster_offset=$(( RANDOM % 90000000 + 10000000 ))
    
    success "生成集群偏移量: $cluster_offset"
    echo "$cluster_offset"
    return 0
}

# 创建集群
create_cluster() {
    local cluster_offset=$1
    local max_nodes=${2:-20}
    
    log "创建新集群..."
    info "集群偏移量: $cluster_offset"
    info "最大节点数: $max_nodes"
    info "RPC 端点: $RPC_ENDPOINT"
    
    # 确保在集群目录中
    local CLUSTER_DIR="$HOME/arcium-cluster-setup"
    cd "$CLUSTER_DIR"
    
    # 显示所有者地址用于验证
    local owner_address=$(solana address --keypair cluster-owner-keypair.json)
    info "集群所有者: $owner_address"
    
    log "执行集群创建命令..."
    if arcium init-cluster \
        --keypair-path cluster-owner-keypair.json \
        --offset $cluster_offset \
        --max-nodes $max_nodes \
        --rpc-url "$RPC_ENDPOINT"; then
        success "集群创建命令执行成功"
        return 0
    else
        error "集群创建命令执行失败"
        return 1
    fi
}

# 验证集群创建
verify_cluster_creation() {
    local cluster_offset=$1
    
    log "验证集群创建..."
    info "等待集群上链确认..."
    
    local max_checks=15  # 增加检查次数
    local check_count=0
    
    while [ $check_count -lt $max_checks ]; do
        sleep 8  # 减少等待时间
        check_count=$((check_count + 1))
        
        log "检查集群状态... ($check_count/$max_checks)"
        
        # 使用更可靠的检查方法
        if arcium fee-proposals $cluster_offset --rpc-url "$RPC_ENDPOINT" 2>/dev/null; then
            success "✅ 集群创建验证成功！"
            success "集群偏移量: $cluster_offset"
            return 0
        else
            # 也尝试其他检查方法
            if arcium cluster-info $cluster_offset --rpc-url "$RPC_ENDPOINT" 2>/dev/null; then
                success "✅ 通过 cluster-info 验证集群创建成功！"
                return 0
            fi
            
            info "集群尚未完全确认，继续等待..."
        fi
    done
    
    warning "⚠️ 集群创建验证超时，但可能已成功创建"
    info "可以手动验证: arcium fee-proposals $cluster_offset --rpc-url \"$RPC_ENDPOINT\""
    
    # 即使超时也返回成功，让用户手动验证
    return 0
}

# 创建集群目录
create_cluster_directory() {
    log "创建集群目录..."
    local CLUSTER_DIR="$HOME/arcium-cluster-setup"
    mkdir -p "$CLUSTER_DIR"
    cd "$CLUSTER_DIR"
    success "集群目录: $CLUSTER_DIR"
}
# 统一的集群管理函数
manage_cluster() {
    local cluster_offset=$1
    local create_if_missing=${2:-false}
    local max_nodes=${3:-20}
    
    log "管理集群: $cluster_offset (自动创建: $create_if_missing)"
    
    # 使用专用集群目录
    local CLUSTER_DIR="$HOME/arcium-cluster-setup"
    mkdir -p "$CLUSTER_DIR"
    cd "$CLUSTER_DIR"
    
    # 检查集群是否已存在
    if check_cluster_exists "$cluster_offset"; then
        success "✅ 集群 $cluster_offset 已存在"
        
        # 检查本地是否有密钥文件
        if [[ ! -f "cluster-owner-keypair.json" ]]; then
            warning "⚠️ 集群在链上存在，但本地缺少所有者密钥文件"
            log "自动重新创建集群以生成新的所有者密钥..."
            
            # 执行完整的集群创建流程
            create_cluster_directory
            create_cluster_owner_keypair
            check_and_airdrop
            
            if create_cluster "$cluster_offset" "$max_nodes"; then
                if verify_cluster_creation "$cluster_offset"; then
                    success "✅ 集群重新创建成功: $cluster_offset"
                    return 0
                else
                    error "❌ 集群重新创建验证失败"
                    return 1
                fi
            else
                error "❌ 集群重新创建失败"
                return 1
            fi
        fi
        
        return 0
    fi
    
    # 原有的创建流程保持不变...
    if [[ "$create_if_missing" == "true" ]]; then
        log "集群不存在，开始自动创建..."
        create_cluster_directory
        create_cluster_owner_keypair
        check_and_airdrop
        
        if create_cluster "$cluster_offset" "$max_nodes"; then
            if verify_cluster_creation "$cluster_offset"; then
                success "✅ 集群创建成功: $cluster_offset"
                return 0
            else
                error "❌ 集群创建验证失败"
                return 1
            fi
        else
            error "❌ 集群创建失败"
            return 1
        fi
    else
        warning "⚠️ 集群 $cluster_offset 不存在且未启用自动创建"
        return 1
    fi
}



# 保存集群信息
save_cluster_info() {
    local cluster_offset=$1
    local max_nodes=$2
    
    log "保存集群信息..."
    
    local CLUSTER_DIR="$HOME/arcium-cluster-setup"
    cd "$CLUSTER_DIR"
    
    local owner_address=$(solana address --keypair cluster-owner-keypair.json)
    
    cat > "cluster-info.txt" << EOF
# Arcium 集群信息
CLUSTER_OFFSET=$cluster_offset
MAX_NODES=$max_nodes
OWNER_ADDRESS=$owner_address
CREATED_AT="$(date +"%Y-%m-%d %H:%M:%S")"
RPC_ENDPOINT=$RPC_ENDPOINT
CLUSTER_DIR=$CLUSTER_DIR

# 管理命令
# 查看集群信息: arcium fee-proposals $cluster_offset --rpc-url "$RPC_ENDPOINT"
# 邀请节点: arcium propose-join-cluster --keypair-path cluster-owner-keypair.json --cluster-offset $cluster_offset --node-offset <NODE_OFFSET> --rpc-url "$RPC_ENDPOINT"
EOF

    success "集群信息已保存到: $CLUSTER_DIR/cluster-info.txt"
}

# 显示集群信息
show_cluster_info() {
    local cluster_offset=$1
    local max_nodes=$2
    
    local owner_address=$(solana address --keypair cluster-owner-keypair.json)
    
    echo
    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════╗"
    echo "║          Arcium 集群创建完成！          ║"
    echo "╚══════════════════════════════════════════╝"
    echo -e "${NC}"
    echo
    info "📋 集群配置信息:"
    echo "   ┌─ 集群偏移量: $cluster_offset"
    echo "   ├─ 最大节点数: $max_nodes"
    echo "   ├─ 集群所有者: $owner_address"
    echo "   ├─ RPC 端点: $RPC_ENDPOINT"
    echo "   └─ 集群目录: $CLUSTER_DIR"
    echo
    info "🚀 下一步操作:"
    echo "   1. 将集群偏移量 '$cluster_offset' 分享给节点运营者"
    echo "   2. 节点运营者运行节点初始化脚本"
    echo "   3. 使用邀请脚本邀请节点加入集群"
    echo
    info "🔧 管理命令:"
    echo "   - 查看集群信息: arcium fee-proposals $cluster_offset --rpc-url \"$RPC_ENDPOINT\""
    echo "   - 邀请节点加入: arcium propose-join-cluster --keypair-path cluster-owner-keypair.json --cluster-offset $cluster_offset --node-offset <节点偏移量> --rpc-url \"$RPC_ENDPOINT\""
    echo
    info "📁 文件位置:"
    echo "   - 集群所有者密钥: $CLUSTER_DIR/cluster-owner-keypair.json"
    echo "   - 集群信息文件: $CLUSTER_DIR/cluster-info.txt"
    echo
    warning "⚠️  请妥善保管 cluster-owner-keypair.json 文件！"
    echo
}

# ========== 原有的节点相关函数保持不变 ==========

verify_node_account_status() {
    local node_offset=$1
    local max_wait_seconds=300  # 5分钟
    local check_interval=20     # 20秒检查一次
    local elapsed_time=0
    
    log "开始验证节点账户状态，节点 Offset: $node_offset"
    log "检查间隔: ${check_interval}秒，最大等待: ${max_wait_seconds}秒"
    
    while [ $elapsed_time -lt $max_wait_seconds ]; do
        log "检查节点账户状态... (已等待 ${elapsed_time}秒)"
        
        if arcium arx-info $node_offset --rpc-url "$RPC_ENDPOINT" 2>/dev/null; then
            success "✅ 节点账户已成功上链，Offset: $node_offset"
            return 0
        else
            info "节点账户尚未在链上确认，继续等待..."
        fi
        
        # 等待并更新计时
        sleep $check_interval
        elapsed_time=$((elapsed_time + check_interval))
        
        # 每1分钟显示一次进度
        if [ $((elapsed_time % 60)) -eq 0 ]; then
            info "已等待 $((elapsed_time / 60)) 分钟，继续验证节点账户..."
        fi
    done
    
    error "❌ 节点账户状态验证超时（${max_wait_seconds}秒），账户可能初始化失败"
    return 1
}
# ========== 修复的集群成员身份检查函数 ==========
check_node_in_cluster() {
    local node_offset=$1
    local cluster_offset=$2
    
    log "详细检查节点 $node_offset 是否在集群 $cluster_offset 中..."
    
    local node_info
    node_info=$(arcium arx-info $node_offset --rpc-url "$RPC_ENDPOINT" 2>/dev/null)
    local check_rc=$?
    
    if [ $check_rc -ne 0 ]; then
        error "无法获取节点信息，命令执行失败"
        return 1
    fi
    
    # 调试信息：显示完整节点信息
    log "=== 节点信息调试 ==="
    echo "$node_info"
    log "=== 信息结束 ==="
    
    # 方法1: 检查 Cluster memberships 部分是否包含集群偏移量
    if echo "$node_info" | grep -A 10 "Cluster memberships:" | grep -q "Offset: $cluster_offset"; then
        success "✅ 节点确认在集群 $cluster_offset 中 (方法1)"
        return 0
    fi
    
    # 方法2: 检查整个输出中是否包含集群偏移量
    if echo "$node_info" | grep -q "Offset: $cluster_offset"; then
        success "✅ 节点确认在集群 $cluster_offset 中 (方法2)"
        return 0
    fi
    
    # 方法3: 检查是否有任何集群成员关系
    local memberships_section=$(echo "$node_info" | grep -A 10 "Cluster memberships:")
    if [[ -n "$memberships_section" ]]; then
        # 提取所有偏移量
        local found_offsets=$(echo "$memberships_section" | grep -o "Offset: [0-9]*" | cut -d' ' -f2)
        if [[ -n "$found_offsets" ]]; then
            log "节点当前在以下集群中: $found_offsets"
            # 检查目标集群是否在列表中
            for offset in $found_offsets; do
                if [[ "$offset" == "$cluster_offset" ]]; then
                    success "✅ 节点确认在集群 $cluster_offset 中 (方法3)"
                    return 0
                fi
            done
            warning "节点在其他集群中，但不在目标集群 $cluster_offset"
            return 1
        else
            log "节点尚未加入任何集群 (Cluster memberships 为空)"
            return 1
        fi
    fi
    
    # 如果都没匹配到，默认认为不在集群中
    log "节点不在目标集群 $cluster_offset 中"
    return 1
}

# 设置 Arx 节点
setup_arx_node() {
    # 检查集群目录是否存在
    local CLUSTER_DIR="$HOME/arcium-cluster-setup"
    if [[ ! -d "$CLUSTER_DIR" ]]; then
        error "❌ 集群目录不存在: $CLUSTER_DIR"
        error "请先创建集群或确保集群目录存在"
        return 1
    fi
    
    # 如果未提供集群偏移量，尝试从集群目录读取
    if [[ -z "$cluster_offset" ]]; then
        if [[ -f "$CLUSTER_DIR/cluster-info.txt" ]]; then
            # 安全地读取集群信息文件
            local cluster_offset_found=""
            while IFS='=' read -r key value; do
                # 跳过空行和注释行
                [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
                
                # 去除值的前后空格
                value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                
                if [[ "$key" == "CLUSTER_OFFSET" ]]; then
                    cluster_offset_found="$value"
                    break
                fi
            done < "$CLUSTER_DIR/cluster-info.txt"
            
            if [[ -n "$cluster_offset_found" ]]; then
                cluster_offset="$cluster_offset_found"
                success "从集群目录读取集群 Offset: $cluster_offset"
            else
                error "❌ 集群信息文件中未找到 CLUSTER_OFFSET"
                return 1
            fi
        else
            error "❌ 未找到集群信息文件"
            return 1
        fi
    fi
    
    # 验证集群是否存在
    log "验证集群状态: $cluster_offset"
    if ! arcium fee-proposals $cluster_offset --rpc-url "$RPC_ENDPOINT" 2>/dev/null; then
        error "❌ 集群 $cluster_offset 在区块链上不存在"
        error "请先创建集群或检查集群偏移量是否正确"
        return 1
    fi
    
    # 原有的变量声明保持不变
    local node_pubkey=""
    local callback_pubkey=""
    local skip_offset_generation=false
    local offset_file="$NODE_DIR/.current_offset"
    local node_offset=""
    local actual_port_used=$NODE_PORT
    local public_ip=""
    local final_port=$NODE_PORT
    
    # 在网络检查之前添加这个函数定义
    check_network_connectivity() {
        log "检查网络连通性..."
        if ! curl -s --max-time 5 ipv4.icanhazip.com >/dev/null; then
            error "网络连接检查失败，请检查网络"
            return 1
        fi
        success "网络连通性正常"
        return 0
    }

    # 检查节点状态函数 - 修复版本
    check_node_status() {
        local node_offset=$1
        
        echo
        info "=== 节点状态检查 ==="
        
        log "检查容器状态..."
        if docker ps | grep -q arx-node; then
            success "节点容器正在运行"
            
            log "检查最近日志..."
            docker compose logs --tail=20
            
            # 检查日志文件是否存在
            log "检查文件日志..."
            if ls ./arx-node-logs/*.log 2>/dev/null; then
                log "显示最新日志文件内容:"
                for log_file in ./arx-node-logs/*.log; do
                    if [[ -f "$log_file" ]]; then
                        log "=== $log_file 最后10行 ==="
                        tail -10 "$log_file"
                    fi
                done
            else
                warning "未找到日志文件，节点可能还在启动中"
            fi
            
            # 等待容器完全启动
            sleep 5
            
            log "检查节点信息..."
            if arcium arx-info $node_offset --rpc-url "$RPC_ENDPOINT" 2>/dev/null; then
                success "节点信息查询成功"
            else
                warning "节点信息查询失败（可能还在启动中）"
            fi
            
            log "检查节点活跃状态..."
            if arcium arx-active $node_offset --rpc-url "$RPC_ENDPOINT" 2>/dev/null; then
                success "节点活跃状态查询成功"
            else
                warning "节点活跃状态查询失败（可能还在启动中）"
            fi
            
            # 检查容器健康状态
            log "检查容器详细状态..."
            docker compose ps
            
        else
            error "节点容器未运行"
            log "尝试查看所有容器状态:"
            docker ps -a
            return 1
        fi
    }
    
    echo "=== DEBUG: 进入 setup_arx_node 函数 ===" >&2
    # 检查是否有保存的 Offset
    if [[ -f "$offset_file" ]]; then
        source "$offset_file"
        if [[ -n "$node_offset" ]]; then
            echo "DEBUG: 从文件恢复节点 Offset: $node_offset" >&2
            success "使用之前生成的节点 Offset: $node_offset"
            # 设置标志跳过 Offset 生成
            skip_offset_generation=true
        fi
    fi
    echo "DEBUG: 参数 cluster_offset = $cluster_offset" >&2
    echo "DEBUG: 当前工作目录: $(pwd)" >&2
    echo "DEBUG: 用户: $(whoami)" >&2
    
    # 强制刷新输出
    sync
    
    log "=== 开始设置 Arx 节点 ==="
    echo "DEBUG: 第一行日志输出完成" >&2
    log "函数开始执行，集群 Offset: $cluster_offset"
    echo "DEBUG: 第二行日志输出完成" >&2
    # 添加网络检查调用
    log "执行网络连通性检查..."
    if ! check_network_connectivity; then
        return 1
    fi
    # 在这里添加端口变量
    echo "DEBUG: 设置 actual_port_used = $actual_port_used" >&2
    log "初始化端口变量: actual_port_used=$actual_port_used"
    
    # 获取公网IP并检查网络
    log "获取公网IP地址..."
    echo "DEBUG: 准备获取公网IP" >&2
    local public_ip=$(curl -s ipv4.icanhazip.com)
    echo "DEBUG: 公网IP获取结果: $public_ip" >&2
    if [[ -z "$public_ip" ]]; then
        error "无法获取公网IP地址，请检查网络连接"
        return 1
    fi
    success "公网IP: $public_ip"
    echo "DEBUG: 公网IP检查完成" >&2
    
    log "步骤 1/9: 创建节点目录"
    echo "DEBUG: 准备创建节点目录" >&2
    # 创建节点目录
    log "创建节点目录: $NODE_DIR"
    mkdir -p "$NODE_DIR"
    echo "DEBUG: 目录创建完成，准备切换目录" >&2
    cd "$NODE_DIR"
    echo "DEBUG: 当前目录: $(pwd)" >&2
    success "节点目录创建完成: $(pwd)"
    echo "DEBUG: 步骤1完成" >&2
    
    # 检查端口可用性
    log "步骤 2/9: 检查端口可用性"
    echo "DEBUG: 准备检查端口可用性" >&2
    log "检查端口 $final_port 是否可用..."
    if ! check_port_availability $final_port; then
        final_port=$((final_port + 1))
        warning "端口 $NODE_PORT 被占用，使用端口: $final_port"
    else
        success "端口 $final_port 可用"
    fi
    # 在这里更新实际使用的端口
    actual_port_used=$final_port
    log "实际使用端口更新为: actual_port_used=$actual_port_used"
    echo "DEBUG: 步骤2完成，最终端口: $actual_port_used" >&2
    
    # 节点 Offset 生成和冲突检测
    echo "DEBUG: 准备执行步骤3" >&2
    log "步骤 3/9: 生成节点 Offset"

    # 检查是否有保存的 Offset
    if [[ -f "$offset_file" ]]; then
        source "$offset_file"
        if [[ -n "$node_offset" ]]; then
            echo "DEBUG: 从文件恢复节点 Offset: $node_offset" >&2
            success "使用之前生成的节点 Offset: $node_offset"
            skip_offset_generation=true
        fi
    fi

    if [[ "$skip_offset_generation" != "true" ]]; then
        local max_retries=10
        local retry_count=0
        
        echo "开始生成节点 Offset，最大重试次数: $max_retries" >&2
        
        while [ $retry_count -lt $max_retries ]; do
            # 生成随机 Offset
            node_offset=$(( RANDOM % 9000000000 + 1000000000 ))
            echo "DEBUG: 生成节点 Offset: $node_offset (尝试 $((retry_count+1))/$max_retries)" >&2
            
            # 检查 Offset 是否已被占用
            echo "DEBUG: 检查 Offset 是否可用..." >&2
            local check_output
            check_output=$(arcium arx-info $node_offset --rpc-url "$RPC_ENDPOINT" 2>&1)
            local exit_code=$?
            echo "DEBUG: arx-info 退出码: $exit_code" >&2
            echo "DEBUG: arx-info 输出: $check_output" >&2
            
            # 判断逻辑：如果输出包含 "not found"，说明 Offset 可用
            if [[ "$check_output" == *"not found"* ]]; then
                echo "DEBUG: Offset $node_offset 可用" >&2
                success "生成可用节点 Offset: $node_offset"
                
                # 保存 Offset 到文件
                echo "node_offset=$node_offset" > "$offset_file"
                break
            else
                # 其他情况说明 Offset 可能已被占用或有其他错误
                echo "DEBUG: Offset $node_offset 可能已被占用，重新生成..." >&2
                warning "节点 Offset $node_offset 可能已被占用，重新生成..."
                retry_count=$((retry_count + 1))
                sleep 1
            fi
        done
        
        if [ $retry_count -eq $max_retries ]; then
            error "无法生成可用节点 Offset，已达最大重试次数"
            return 1
        fi
    fi
    echo "步骤 4/9: 生成密钥对" >&2
    echo "节点 Offset: $node_offset" >&2
    echo "集群 Offset: $cluster_offset" >&2
    echo "RPC 端点: $RPC_ENDPOINT" >&2
    echo "节点端口: $final_port" >&2
    
    # 生成密钥对
    echo "生成节点密钥对..." >&2
    # 检查密钥是否已存在，如果存在则跳过生成
    echo "DEBUG: 检查密钥文件是否存在且格式正确..." >&2
    
    local keys_valid=true
    
    if [[ -f "node-keypair.json" ]]; then
        if ! solana address --keypair node-keypair.json >/dev/null 2>&1; then
            echo "DEBUG: node-keypair.json 文件损坏" >&2
            keys_valid=false
        fi
    else
        echo "DEBUG: node-keypair.json 文件不存在" >&2
        keys_valid=false
    fi
    
    if [[ -f "callback-kp.json" ]]; then
        if ! solana address --keypair callback-kp.json >/dev/null 2>&1; then
            echo "DEBUG: callback-kp.json 文件损坏" >&2
            keys_valid=false
        fi
    else
        echo "DEBUG: callback-kp.json 文件不存在" >&2
        keys_valid=false
    fi
    
    if [[ ! -f "identity.pem" ]]; then
        echo "DEBUG: identity.pem 文件不存在" >&2
        keys_valid=false
    fi
    
    echo "DEBUG: 所有密钥文件是否有效: $keys_valid" >&2
    
    if [ "$keys_valid" = true ]; then
        echo "DEBUG: 所有密钥文件有效，跳过生成" >&2
        log "检测到现有密钥文件，跳过生成..."
        node_pubkey=$(solana-keygen pubkey node-keypair.json)
        callback_pubkey=$(solana-keygen pubkey callback-kp.json)
    else
        echo "DEBUG: 有密钥文件缺失或损坏，进入生成分支" >&2
        echo "DEBUG: 有密钥文件缺失，进入生成分支" >&2
        
        # 检查文件是否已存在，如果存在则备份
        if [[ -f "node-keypair.json" ]]; then
            warning "node-keypair.json 已存在，创建备份..."
            cp node-keypair.json node-keypair.json.backup
        fi
        
        if [[ -f "callback-kp.json" ]]; then
            warning "callback-kp.json 已存在，创建备份..."
            cp callback-kp.json callback-kp.json.backup
        fi
        
        if [[ -f "identity.pem" ]]; then
            warning "identity.pem 已存在，创建备份..."
            cp identity.pem identity.pem.backup
        fi
        
        # 使用 --force 标志生成密钥
        log "生成 node-keypair.json..."
        log "生成 node-keypair.json..."
        echo "DEBUG: 开始生成 node-keypair.json" >&2
        if ! solana-keygen new --outfile node-keypair.json --no-bip39-passphrase --silent --force; then
            error "生成 node-keypair.json 失败"
            return 1
        fi
        echo "DEBUG: node-keypair.json 生成完成" >&2

        log "生成 callback-kp.json..." 
        echo "DEBUG: 开始生成 callback-kp.json" >&2
        if ! solana-keygen new --outfile callback-kp.json --no-bip39-passphrase --silent --force; then
            error "生成 callback-kp.json 失败"
            return 1
        fi
        echo "DEBUG: callback-kp.json 生成完成" >&2

        log "生成 identity.pem..."
        echo "DEBUG: 开始生成 identity.pem" >&2
        if ! openssl genpkey -algorithm Ed25519 -out identity.pem; then
            error "生成 identity.pem 失败"
            return 1
        fi
        echo "DEBUG: identity.pem 生成完成" >&2
        
        echo "密钥对生成完成" >&2
        
        # 获取公钥
        echo "获取节点地址..." >&2
        node_pubkey=$(solana-keygen pubkey node-keypair.json)
        echo "节点地址: $node_pubkey" >&2
        
        echo "获取回调地址..." >&2
        callback_pubkey=$(solana-keygen pubkey callback-kp.json)
        echo "回调地址: $callback_pubkey" >&2
        
        echo "✓ 新生成的节点地址: $node_pubkey" >&2
        echo "✓ 新生成的回调地址: $callback_pubkey" >&2
    fi
    
    # 检查节点地址余额，决定是否需要领水
    # 步骤 5/9: 检查余额和领水
    log "步骤 5/9: 检查余额和领水"
    log "检查节点地址余额..."
    local node_balance=$(solana balance $node_pubkey --url "$RPC_ENDPOINT" 2>/dev/null | cut -d' ' -f1 || echo "0")
    success "节点地址当前余额: $node_balance SOL"
    
    # 如果节点地址余额小于 2.5 SOL，则尝试多种方式获取资金
    if (( $(echo "$node_balance < 2.5" | bc -l) )); then
        log "节点地址余额不足，开始获取资金..."
        local funding_success=false
        
        # 方法1: 尝试官方领水
        log "尝试官方领水..."
        if solana airdrop 5 $node_pubkey -u devnet 2>/dev/null; then
            success "官方领水成功，等待到账..."
            funding_success=true
        else
            warning "官方领水失败，尝试集群转账..."
            
            # 方法2: 从集群所有者转账
            local CLUSTER_DIR="$HOME/arcium-cluster-setup"
            if [[ -f "$CLUSTER_DIR/cluster-owner-keypair.json" ]]; then
                log "从集群所有者给节点转账 4 SOL..."
                
                # 检查集群所有者余额
                local cluster_owner_address=$(solana address --keypair "$CLUSTER_DIR/cluster-owner-keypair.json")
                local cluster_balance=$(solana balance $cluster_owner_address --url "$RPC_ENDPOINT" 2>/dev/null | cut -d' ' -f1 || echo "0")
                success "集群所有者余额: $cluster_balance SOL"
                
                if (( $(echo "$cluster_balance >= 4.5" | bc -l) )); then
                    if solana transfer $node_pubkey 4 --keypair "$CLUSTER_DIR/cluster-owner-keypair.json" --url "$RPC_ENDPOINT" --allow-unfunded-recipient 2>/dev/null; then
                        success "集群转账成功！"
                        funding_success=true
                    else
                        error "集群转账失败"
                    fi
                else
                    warning "集群所有者余额不足 ($cluster_balance SOL)，无法转账"
                fi
            else
                warning "未找到集群所有者密钥文件"
            fi
        fi
        
        # 等待资金到账
        if [ "$funding_success" = true ]; then
            success "资金请求已提交，等待到账..."
            
            # 等待并检查余额
            local max_checks=15
            local check_count=0
            
            while [ $check_count -lt $max_checks ]; do
                sleep 10
                node_balance=$(solana balance $node_pubkey --url "$RPC_ENDPOINT" 2>/dev/null | cut -d' ' -f1 || echo "0")
                check_count=$((check_count + 1))
                
                if (( $(echo "$node_balance >= 3.5" | bc -l) )); then
                    success "节点地址资金到账: $node_balance SOL"
                    break
                else
                    info "等待资金到账... ($check_count/$max_checks) 当前余额: $node_balance SOL"
                fi
            done
            
            if (( $(echo "$node_balance < 3.5" | bc -l) )); then
                warning "资金未完全到账，当前余额: $node_balance SOL"
                info "可能因网络延迟，继续等待或需要手动处理"
            fi
        else
            # 所有自动方法都失败，提示手动领水
            warning "所有自动获取资金方法都失败了"
            info "请手动访问以下网站领水:"
            info "https://faucet.solana.com"
            info "节点地址: $node_pubkey"
            info "领取至少 5 SOL 后按回车键继续..."
            read -r </dev/tty
            
            # 手动领水后等待余额到账
            log "等待手动领水到账..."
            local max_waits=30
            local wait_count=0
            
            while [ $wait_count -lt $max_waits ]; do
                sleep 20
                node_balance=$(solana balance $node_pubkey --url "$RPC_ENDPOINT" 2>/dev/null | cut -d' ' -f1 || echo "0")
                wait_count=$((wait_count + 1))
                
                echo "检查余额... ($wait_count/$max_waits) 当前余额: $node_balance SOL" >&2
                
                if (( $(echo "$node_balance >= 3.5" | bc -l) )); then
                    success "领水到账: $node_balance SOL"
                    break
                fi
            done
            
            if (( $(echo "$node_balance < 3.5" | bc -l) )); then
                warning "领水未到账，当前余额: $node_balance SOL"
                info "请确认已成功领水，按回车键强制继续..."
                read -r </dev/tty
            fi
        fi
    else
        success "节点地址余额充足，跳过领水"
    fi
    
    # === 重新检查余额（领水后可能发生变化）===
    node_balance=$(solana balance $node_pubkey --url "$RPC_ENDPOINT" 2>/dev/null | cut -d' ' -f1 || echo "0")
    success "领水后节点地址最终余额: $node_balance SOL"
    
    # 如果节点余额仍然不足，给出警告但继续
    if (( $(echo "$node_balance < 3.5" | bc -l) )); then
        warning "节点地址余额仍然不足 ($node_balance SOL)，可能影响节点运行"
        info "建议手动补充资金或联系集群所有者"
    fi
    
    # 检查回调地址余额，决定是否需要转账
    log "检查回调地址余额..."
    local callback_balance=$(solana balance $callback_pubkey --url "$RPC_ENDPOINT" 2>/dev/null | cut -d' ' -f1 || echo "0")
    success "回调地址当前余额: $callback_balance SOL"
    
    # 如果回调地址余额小于 0.5 SOL，且节点地址有足够余额，则转账
    if (( $(echo "$callback_balance < 0.5" | bc -l) )); then
        # 调整判断条件：节点余额至少需要 1 SOL（转账 1 SOL + gas 费）
        if (( $(echo "$node_balance >= 1.1" | bc -l) )); then
            log "回调地址余额不足，从节点地址转账 1 SOL..."
            if solana transfer $callback_pubkey 1 --keypair node-keypair.json --url "$RPC_ENDPOINT" --allow-unfunded-recipient 2>/dev/null; then
                success "转账成功，等待回调地址到账..."
                
                # 等待回调地址到账
                local callback_checks=0
                log "开始等待回调地址到账，最大检查次数: 5"
                while [ $callback_checks -lt 5 ]; do
                    sleep 5
                    callback_balance=$(solana balance $callback_pubkey --url "$RPC_ENDPOINT" 2>/dev/null | cut -d' ' -f1 || echo "0")
                    callback_checks=$((callback_checks + 1))
                    
                    if (( $(echo "$callback_balance >= 0.5" | bc -l) )); then
                        success "回调地址资金到位: $callback_balance SOL"
                        break
                    else
                        info "等待回调地址到账... ($callback_checks/5) 当前余额: $callback_balance SOL"
                    fi
                done
            else
                warning "转账失败，请手动处理"
                info "手动执行: solana transfer $callback_pubkey 1 --keypair node-keypair.json --url \"$RPC_ENDPOINT\" --allow-unfunded-recipient"
                info "按回车键继续..."
                read -r
            fi
        else
            warning "节点地址余额不足 ($node_balance SOL)，无法给回调地址转账"
            info "回调地址需要至少 0.5 SOL 才能运行节点"
            # 这里不返回错误，让用户决定是否继续
            info "按回车键继续（节点可能无法正常运行）..."
            read -r
        fi
    else
        success "回调地址余额充足，跳过转账"
    fi
    
    # 最终检查回调地址余额
    local final_callback_balance=$(solana balance $callback_pubkey --url "$RPC_ENDPOINT" 2>/dev/null | cut -d' ' -f1 || echo "0")
    if (( $(echo "$final_callback_balance < 0.5" | bc -l) )); then
        error "回调地址余额不足 ($final_callback_balance SOL)，无法运行节点"
        return 1
    fi
    # ========== 步骤 6/9: 初始化节点账户 ==========
    log "步骤 6/9: 初始化节点账户"
    
    # 首先检查节点是否已经初始化
    log "检查节点 $node_offset 是否已初始化..."
    local check_output
    check_output=$(arcium arx-info $node_offset --rpc-url "$RPC_ENDPOINT" 2>&1)
    local check_rc=$?

    if [ $check_rc -eq 0 ] && [[ ! "$check_output" =~ "not found" ]] && [[ ! "$check_output" =~ "AccountNotFound" ]]; then
        # 命令执行成功，说明节点已存在
        success "✅ 节点 $node_offset 已经初始化，跳过初始化步骤"
        log "节点账户状态正常，继续后续流程"
    elif [[ "$check_output" == *"not found"* ]] || [[ "$check_output" == *"Account info not found"* ]]; then
        # 明确显示账户不存在
        log "节点 $node_offset 未初始化，开始初始化流程..."
        log "使用公网 IP 地址: $public_ip"

        # 改进的错误处理和重试逻辑
        local max_retries=3
        local retry_count=0
        local init_success=false

        log "开始初始化节点账户，最大重试次数: $max_retries"

        while [ $retry_count -lt $max_retries ]; do
            log "执行 arcium init-arx-accs 命令 (尝试 $((retry_count+1))/$max_retries)..."
            info "📝 正在将节点账户信息上链，请稍候..."

            # 使用 --skip-steps 参数跳过已存在的步骤
            init_output=$(arcium init-arx-accs \
                --keypair-path node-keypair.json \
                --callback-keypair-path callback-kp.json \
                --peer-keypair-path identity.pem \
                --node-offset $node_offset \
                --ip-address $public_ip \
                --rpc-url "$RPC_ENDPOINT" 2>&1)
            init_rc=$?
            
            echo "$init_output"

            if [ $init_rc -eq 0 ]; then
                success "节点账户初始化成功"
                # 验证节点账户状态
                log "等待节点账户上链确认..."
                info "⏳ 正在等待区块链确认节点账户，这可能需要几分钟..."
                info "🔍 每20秒检查一次状态，最多等待5分钟"
                if verify_node_account_status $node_offset; then
                    success "✅ 节点账户状态验证通过"
                    init_success=true
                    break
                else
                    error "❌ 节点账户状态验证失败"
                    return 1
                fi
            else
                # 若报错包含 already in use，视为账户已存在，继续后续步骤
                if [[ "$init_output" == *"already in use"* ]] || [[ "$init_output" == *"already exists"* ]]; then
                    warning "检测到账户地址已存在，视为已初始化，继续..."
                    init_success=true
                    break
                fi
                
                retry_count=$((retry_count + 1))
                if [ $retry_count -eq $max_retries ]; then
                    error "节点账户初始化失败，已达最大重试次数"
                    return 1
                else
                    warning "节点账户初始化失败，第 $retry_count 次重试..."
                    info "🔄 5秒后重新尝试..."
                    sleep 5
                fi
            fi
        done

        if [ "$init_success" = false ]; then
            error "节点账户初始化失败"
            return 1
        fi
        success "🎉 节点账户初始化完成！"
    else
        # 其他错误情况，保守起见尝试初始化
        warning "节点状态检查不确定: $check_output"
        log "尝试继续初始化流程..."
        # 这里可以添加初始化代码，或者直接跳过
        warning "由于状态不确定，跳过初始化步骤，继续后续流程"
    fi
    # 在 setup_arx_node 函数中，找到步骤7的加入集群部分，替换为以下代码：

    # ========== 步骤 7/9: 加入集群 ==========
    # ========== 步骤 7/9: 加入集群 ==========
    log "步骤 7/9: 加入集群"
    if [[ -z "$cluster_offset" ]]; then
        error "未提供集群 Offset，无法加入现有集群。"
        return 1
    fi

    # 首先检查节点是否已经在目标集群中
    log "详细检查节点 $node_offset 是否在集群 $cluster_offset 中..."

    if check_node_in_cluster "$node_offset" "$cluster_offset"; then
        success "✅ 节点已在集群 $cluster_offset 中，跳过邀请和加入步骤"
    else
        log "节点不在目标集群中，需要执行邀请和加入流程..."
        
        # === 新增：自动邀请步骤 ===
        log "执行集群所有者邀请节点..."
        local CLUSTER_DIR="$HOME/arcium-cluster-setup"
        
        if [[ -f "$CLUSTER_DIR/cluster-owner-keypair.json" ]]; then
            log "使用集群所有者密钥邀请节点 $node_offset 加入集群 $cluster_offset..."
            
            if arcium propose-join-cluster \
                --keypair-path "$CLUSTER_DIR/cluster-owner-keypair.json" \
                --cluster-offset $cluster_offset \
                --node-offset $node_offset \
                --rpc-url "$RPC_ENDPOINT" 2>&1; then
                success "✅ 集群所有者邀请节点成功"
            else
                warning "⚠️ 自动邀请失败，可能原因："
                warning "  - 集群所有者密钥不匹配"
                warning "  - 节点已被邀请"
                warning "  - 集群已满"
                info "尝试继续执行加入流程..."
            fi
        else
            warning "⚠️ 未找到集群所有者密钥，无法自动邀请"
            info "请手动执行邀请命令："
            info "cd $CLUSTER_DIR && arcium propose-join-cluster --keypair-path cluster-owner-keypair.json --cluster-offset $cluster_offset --node-offset $node_offset --rpc-url \"$RPC_ENDPOINT\""
            info "按回车键继续..."
            read -r </dev/tty
        fi
        # === 邀请步骤结束 ===
        
        # 执行加入集群操作
        log "执行加入集群命令..."
        local max_join_retries=8
        local join_retry=0
        local join_success=false

        while [ $join_retry -lt $max_join_retries ]; do
            log "尝试加入集群 (尝试 $((join_retry+1))/$max_join_retries)..."
                    # 每次重试前都检查一次状态
            if check_node_in_cluster "$node_offset" "$cluster_offset"; then
                success "✅ 节点已在集群中，跳过本次加入尝试"
                join_success=true
                break
            fi
            if arcium join-cluster true \
                --keypair-path node-keypair.json \
                --node-offset $node_offset \
                --cluster-offset $cluster_offset \
                --rpc-url "$RPC_ENDPOINT" 2>&1 | grep -q "success\|already"; then
                join_success=true
                success "✅ 成功加入集群 $cluster_offset"
                break
            else
                join_retry=$((join_retry + 1))
                if [ $join_retry -eq $max_join_retries ]; then
                    error "❌ 加入集群失败，已达最大重试次数"
                    error "可能的原因："
                    error "1. 集群管理者尚未邀请本节点"
                    error "2. 集群已满员"
                    error "3. 网络连接问题"
                    info "请让集群管理者执行以下邀请命令："
                    info "arcium propose-join-cluster --keypair-path <集群管理者密钥> --cluster-offset $cluster_offset --node-offset $node_offset --rpc-url \"$RPC_ENDPOINT\""
                    return 1
                else
                    warning "加入集群失败，第 $join_retry 次重试..."
                    sleep 15
                fi
            fi
        done
        
        # 验证加入结果
        if [ "$join_success" = true ]; then
            log "验证节点是否成功加入集群..."
            local max_status_checks=10
            local status_check=0
            local status_verified=false

            while [ $status_check -lt $max_status_checks ]; do
                if check_node_in_cluster "$node_offset" "$cluster_offset"; then
                    status_verified=true
                    success "✅ 节点状态验证成功，已在集群 $cluster_offset 中"
                    break
                else
                    status_check=$((status_check + 1))
                    info "等待节点状态更新... ($status_check/$max_status_checks)"
                    sleep 10
                fi
            done

            if [ "$status_verified" = false ]; then
                warning "⚠️ 节点状态验证超时，但节点可能已成功加入"
                info "可以手动检查：arcium arx-info $node_offset --rpc-url \"$RPC_ENDPOINT\""
            fi
        fi
    fi
    # === 加入集群代码结束 ===
    # ========== 步骤 8/9: 创建配置和启动节点 ==========
    log "步骤 8/9: 创建配置和启动节点"
    # 创建节点配置
    log "创建节点配置文件..."
cat > node-config.toml << EOF
[node]
offset = $node_offset
hardware_claim = 0
starting_epoch = 0
ending_epoch = 9223372036854775807

[network]
address = "0.0.0.0"

[solana]
endpoint_rpc = "$RPC_ENDPOINT"
endpoint_wss = "$WSS_ENDPOINT"
cluster = "Devnet"
commitment.commitment = "confirmed"
EOF
    success "节点配置文件创建完成"
    
    # 创建 Docker Compose 配置
    log "创建 Docker Compose 配置..."
    cat > docker-compose.yml << EOF
version: '3.8'

services:
  arx-node:
    image: arcium/arx-node
    container_name: arx-node
    platform: linux/amd64  # 添加这一行强制使用 AMD64 架构
    environment:
      - NODE_IDENTITY_FILE=/usr/arx-node/node-keys/node_identity.pem
      - NODE_KEYPAIR_FILE=/usr/arx-node/node-keys/node_keypair.json
      - CALLBACK_AUTHORITY_KEYPAIR_FILE=/usr/arx-node/node-keys/callback_authority_keypair.json
      - NODE_CONFIG_PATH=/usr/arx-node/arx/node_config.toml
    volumes:
      - ./node-config.toml:/usr/arx-node/arx/node_config.toml
      - ./node-keypair.json:/usr/arx-node/node-keys/node_keypair.json:ro
      - ./callback-kp.json:/usr/arx-node/node-keys/callback_authority_keypair.json:ro
      - ./identity.pem:/usr/arx-node/node-keys/node_identity.pem:ro
      - ./arx-node-logs:/usr/arx-node/logs
    ports:
      - "$final_port:8080"
    restart: unless-stopped
EOF
    success "Docker Compose 配置创建完成"
    
    # 创建日志目录
    log "创建日志目录..."
    mkdir -p ./arx-node-logs
    success "日志目录创建完成"
    
    # 启动节点
    log "启动节点容器..."
    log "执行 docker compose up -d 命令..."
    if docker compose up -d; then
        success "节点容器启动命令执行完成"
    else
        error "节点容器启动失败"
        return 1
    fi
    
    # 检查节点状态
    log "等待节点启动..."
    sleep 5
    log "检查容器是否运行..."
    if docker ps | grep -q arx-node; then
        success "Arx 节点容器已启动"
        # 添加容器健康状态检查
        log "检查容器详细状态..."
        if docker compose ps | grep -q "Up"; then
            success "节点容器运行正常"
        else
            warning "节点容器已启动但可能有问题，请检查日志"
        fi
        success "Arx 节点启动成功！"
        success "节点 Offset: $node_offset"
        success "节点地址: $node_pubkey"
        success "回调地址: $callback_pubkey"
        success "运行端口: $final_port"
        success "集群 Offset: $cluster_offset"
        log "函数执行完成，返回结果: $node_offset:$actual_port_used"
        echo "$node_offset:$actual_port_used"
        return 0
    else
        error "节点启动失败，请检查日志"
        log "检查容器状态: docker ps -a"
        log "查看容器日志: docker compose logs"
        return 1
    fi
}

# 验证安装
verify_installation() {
    log "验证节点运行环境..."
    
    local all_success=true
    
    if check_cmd "solana"; then
        success "Solana CLI: $(solana --version)"
    else
        error "Solana CLI: 未安装"
        all_success=false
    fi
    
    if check_cmd "arcium"; then
        success "Arcium: $(arcium --version)"
    else
        error "Arcium: 未安装"
        all_success=false
    fi
    
    if docker info > /dev/null 2>&1; then
        success "Docker: 正在运行"
    else
        error "Docker: 未运行"
        all_success=false
    fi
    
    if [ "$all_success" = true ]; then
        success "🎉 节点环境准备完成！"
    else
        error "❌ 节点环境配置失败"
        exit 1
    fi
}

# 显示节点信息
show_node_info() {
    local node_offset=$1
    local node_pubkey=$2
    local callback_pubkey=$3
    local final_port=$4
    
    echo
    info "=== Arcium 节点部署完成 ==="
    echo
    info "节点配置信息:"
    echo "  - 节点 Offset: $node_offset"
    echo "  - 节点地址: $node_pubkey"
    echo "  - 回调地址: $callback_pubkey"
    echo "  - 公网 IP: $(curl -s ipv4.icanhazip.com)"
    echo "  - 运行端口: $final_port"
    echo "  - RPC 端点: $RPC_ENDPOINT"
    echo
    info "节点管理命令:"
    echo "  - 查看节点日志: docker compose logs -f"
    echo "  - 查看文件日志: tail -f ./arx-node-logs/*.log"
    echo "  - 停止节点: docker compose down"
    echo "  - 重启节点: docker compose restart"
    echo "  - 查看容器状态: docker ps"
    echo
    info "节点状态检查:"
    echo "  - 检查节点信息: arcium arx-info $node_offset --rpc-url \"$RPC_ENDPOINT\""
    echo "  - 检查节点活跃: arcium arx-active $node_offset --rpc-url \"$RPC_ENDPOINT\""
    echo
    info "重要提醒:"
    echo "  - 保持 Docker 持续运行"
    echo "  - 确保端口 $final_port 对外开放"
    echo "  - 监控节点日志确保正常运行"
    echo "  - 节点需要持续在线以获得奖励"
    echo
    warning "请妥善保存生成的密钥文件！"
}

# 显示使用说明
show_usage() {
    echo
    info "使用方法:"
    echo "  $0 [选项]"
    echo
    info "选项:"
    echo "  -c, --cluster-offset CLUSTER_OFFSET  指定集群 Offset (加入模式使用)"
    echo "  -p, --port NODE_PORT                 指定节点端口 (默认: 8080)"
    echo "  -r, --rpc RPC_ENDPOINT              指定 RPC 端点"
    echo "  -w, --wss WSS_ENDPOINT              指定 WebSocket 端点"
    echo "  -h, --help                         显示此帮助信息"
    echo
    info "交互模式:"
    echo "  运行脚本时会提示选择部署模式:"
    echo "  开始部署节点"
    echo
}

# 主函数
# 主函数
main() {
    # 设置环境变量 - 修复版本
    export PATH="$HOME/.cargo/bin:$PATH"
    export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"
    
    local create_new_cluster=true
    local custom_cluster_offset=""
    log "使用模式: 创建新集群并自己加入"
    echo
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--cluster-offset)
                if [[ -n "$2" && "$2" =~ ^[0-9]+$ ]]; then
                    CLUSTER_OFFSET="$2"
                    shift 2
                else
                    error "集群 Offset 必须是数字"
                    exit 1
                fi
                ;;
            -p|--port)
                if [[ -n "$2" && "$2" =~ ^[0-9]+$ ]]; then
                    NODE_PORT="$2"
                    shift 2
                else
                    error "端口必须是数字"
                    exit 1
                fi
                ;;
            -r|--rpc)
                if [[ -n "$2" ]]; then
                    RPC_ENDPOINT="$2"
                    shift 2
                else
                    error "请提供 RPC 端点"
                    exit 1
                fi
                ;;
            -w|--wss)
                if [[ -n "$2" ]]; then
                    WSS_ENDPOINT="$2"
                    shift 2
                else
                    error "请提供 WSS 端点"
                    exit 1
                fi
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                error "未知参数: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    echo
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════╗"
    echo "║          Arcium 节点部署脚本         ║"
    echo "║          专注节点运行                ║"
    echo "╚══════════════════════════════════════╝"
    echo -e "${NC}"
    
    # ========== 新的集群管理逻辑 ==========
    CLUSTER_DIR="$HOME/arcium-cluster-setup"
    
    # 检查集群目录是否存在
    if [[ ! -d "$CLUSTER_DIR" ]]; then
        log "未找到集群目录，将创建新集群..."
        create_new_cluster=true
    else
        log "找到现有集群目录: $CLUSTER_DIR"
        create_new_cluster=false
        
        # 尝试从集群目录读取集群信息
        if [[ -f "$CLUSTER_DIR/cluster-info.txt" ]]; then
            log "读取集群配置信息..."
            
            # 安全地读取集群信息文件，避免时间格式被解析
            while IFS='=' read -r key value; do
                # 跳过空行和注释行
                [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
                
                # 去除值的前后空格
                value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                
                case "$key" in
                    CLUSTER_OFFSET)
                        CLUSTER_OFFSET="$value"
                        ;;
                    MAX_NODES)
                        # 这个变量可能在其他地方使用
                        ;;
                    OWNER_ADDRESS)
                        # 这个变量可能在其他地方使用
                        ;;
                    RPC_ENDPOINT)
                        # 可选：如果需要覆盖RPC端点
                        ;;
                esac
            done < "$CLUSTER_DIR/cluster-info.txt"
            
            if [[ -n "$CLUSTER_OFFSET" ]]; then
                success "从集群目录读取集群 Offset: $CLUSTER_OFFSET"
                # 验证集群在区块链上的状态
                log "验证集群状态..."
                if arcium fee-proposals $CLUSTER_OFFSET --rpc-url "$RPC_ENDPOINT" 2>/dev/null; then
                    success "✅ 集群状态验证通过"
                else
                    warning "⚠️ 集群在区块链上未找到，将创建新集群"
                    create_new_cluster=true
                fi
            else
                warning "集群信息文件中未找到 CLUSTER_OFFSET，将创建新集群"
                create_new_cluster=true
            fi
        else
            warning "未找到集群信息文件，将创建新集群"
            create_new_cluster=true
        fi
    fi
    # 显示配置信息
    info "当前配置:"
    echo "  - 集群 Offset: $CLUSTER_OFFSET"
    echo "  - 节点端口: $NODE_PORT"
    echo "  - RPC 端点: $RPC_ENDPOINT"
    echo "  - WSS 端点: $WSS_ENDPOINT"
    echo "  - 集群目录: $CLUSTER_DIR"
    echo
    
    # 先检查和安装组件
    info "检查节点运行所需组件..."
    local skip_install=false
    if check_cmd "solana" && check_cmd "arcium" && check_cmd "docker" && check_cmd "anchor"; then
        success "所有必需组件已安装，跳过安装步骤"
        skip_install=true
    fi

    if [ "$skip_install" = false ]; then
        install_dependencies
        install_rust
        install_solana
        install_docker
        install_anchor
        install_arcium
        verify_installation
    fi
    
    # 显示系统信息
    log "系统信息: $(uname -s) $(uname -m)"
    log "工作目录: $NODE_DIR"
    
    # 如果用户选择了创建集群
    if [ "$create_new_cluster" = true ]; then
        # 生成或使用指定的集群 Offset
        if [[ -n "$CLUSTER_OFFSET" ]]; then
            log "使用指定的集群 Offset: $CLUSTER_OFFSET"
        else
            CLUSTER_OFFSET=$(( RANDOM % 90000000 + 10000000 ))
            log "生成随机集群 Offset: $CLUSTER_OFFSET"
        fi
        
        log "创建新集群: $CLUSTER_OFFSET"
        
        # 使用新的集群管理函数
        if manage_cluster "$CLUSTER_OFFSET" "true" "20"; then
            success "✅ 新集群创建成功！集群ID: $CLUSTER_OFFSET"
            save_cluster_info "$CLUSTER_OFFSET" "20"
            show_cluster_info "$CLUSTER_OFFSET" "20"
        else
            error "❌ 集群创建失败"
            return 1
        fi
    else
        success "使用现有集群: $CLUSTER_OFFSET"
        log "集群目录: $CLUSTER_DIR"
        log "集群所有者密钥: $CLUSTER_DIR/cluster-owner-keypair.json"
    fi
    
    # 直接设置节点
    log "开始部署 Arx 节点..."
    
    # 检查函数是否存在
    if type setup_arx_node >/dev/null 2>&1; then
        log "调用 setup_arx_node 函数，集群 Offset: $CLUSTER_OFFSET"

        # 执行函数
        if node_offset_result=$(setup_arx_node "$CLUSTER_OFFSET"); then
            log "✅ setup_arx_node 函数执行成功"
            log "解析返回结果: $node_offset_result"

            # 解析返回的节点 Offset 和端口
            IFS=':' read -r node_offset actual_port <<< "$node_offset_result"
            log "解析得到 - 节点 Offset: $node_offset, 实际端口: $actual_port"
            
            log "获取节点公钥..."
            local node_pubkey=$(solana-keygen pubkey node-keypair.json)
            log "节点地址: $node_pubkey"
            
            log "获取回调地址公钥..."
            local callback_pubkey=$(solana-keygen pubkey callback-kp.json)
            log "回调地址: $callback_pubkey"
            
            log "调用 show_node_info 显示节点信息..."
            show_node_info "$node_offset" "$node_pubkey" "$callback_pubkey" "$actual_port"
            
            log "🎉 节点部署流程全部完成！"
        else
            local exit_code=$?
            error "❌ 节点部署失败，setup_arx_node 函数返回非零状态"
            error "请检查上面的错误信息"
            exit 1
        fi
    else
        error "❌ setup_arx_node 函数不存在"
        exit 1
    fi
}

# 运行主函数
main "$@"