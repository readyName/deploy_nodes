#!/bin/bash

#======================== 柔和色彩与基础配置 ========================#
GREEN='\033[1;32m'
BLUE='\033[1;36m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

LOG_FILE="$HOME/equium_miner.log"
MAX_LOG_SIZE=10485760 # 10 MB
CONFIG_FILE="$HOME/.equium_config"   # 记忆配置文件

#======================== 日志与工具函数 ========================#
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

rotate_log() {
    if [[ -f "$LOG_FILE" ]]; then
        local size
        if [[ "$(uname)" == "Darwin" ]]; then
            size=$(stat -f%z "$LOG_FILE")
        else
            size=$(stat -c%s "$LOG_FILE")
        fi
        if [[ $size -ge $MAX_LOG_SIZE ]]; then
            mv "$LOG_FILE" "${LOG_FILE}.$(date +%F_%H-%M-%S).bak"
            log "⚠️  日志文件已轮转。"
        fi
    fi
}

check_command() {
    if command -v "$1" &> /dev/null; then
        log "✅ $1 已存在，跳过安装。"
        return 0
    else
        log "❌ $1 未找到。"
        return 1
    fi
}

print_header() {
    echo -e "${BLUE}=====================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}=====================================${NC}"
}

#======================== 环境检测 ========================#
detect_os() {
    if [[ "$(uname)" != "Darwin" ]]; then
        echo -e "${RED}本脚本仅支持 macOS。请在 macOS 上运行。${NC}"
        exit 1
    fi
    log "macOS 环境检测通过。"
}

#======================== 依赖安装 ========================#
install_rust() {
    if check_command rustc; then
        return 0
    fi
    log "正在安装 Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    if [[ $? -ne 0 ]]; then
        log "${RED}Rust 安装失败，请检查网络后重试。${NC}"
        exit 1
    fi
    
    if [[ -f "$HOME/.cargo/env" ]]; then
        source "$HOME/.cargo/env"
    fi
    
    if ! command -v rustc &> /dev/null; then
        export PATH="$HOME/.cargo/bin:$PATH"
    fi
    
    log "Rust 安装完成，版本：$(rustc --version 2>/dev/null)"
}

install_solana_cli() {
    if check_command solana; then
        return 0
    fi
    log "正在安装 Solana CLI（需要生成钱包）..."
    
    # 重试 3 次，应对间歇性网络问题
    for i in 1 2 3; do
        log "第 $i 次尝试下载 Solana CLI 安装脚本..."
        sh -c "$(curl -sSfL https://release.solana.com/stable/install)" && break
        if [[ $i -lt 3 ]]; then
            log "下载失败，等待 5 秒后重试..."
            sleep 5
        else
            log "${RED}Solana CLI 安装脚本下载失败（网络错误）。${NC}"
            log "${YELLOW}建议手动安装：https://docs.solanalabs.com/cli/install${NC}"
            log "${YELLOW}或者从 GitHub 直接下载二进制：https://github.com/solana-labs/solana/releases${NC}"
            exit 1
        fi
    done

    # 确保 PATH 正确
    export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"
    
    # 最终验证
    if ! command -v solana-keygen &> /dev/null; then
        log "${RED}安装后仍找不到 solana-keygen，可能是 PATH 未生效。请打开新终端或手动执行 source ~/.profile。${NC}"
        exit 1
    fi
    log "Solana CLI 安装完成，版本：$(solana --version 2>/dev/null)"
}

#======================== 临时切换 Cargo 源（解决网络超时） ========================#
setup_cargo_mirror() {
    local cargo_home="${CARGO_HOME:-$HOME/.cargo}"
    local config_file="$cargo_home/config.toml"
    local backup_file="$cargo_home/config.toml.equium_backup"

    log "为编译临时启用清华镜像源并延长超时..."

    if [[ -f "$config_file" ]] && [[ ! -f "$backup_file" ]]; then
        cp "$config_file" "$backup_file"
    fi

    mkdir -p "$cargo_home"
    cat > "$config_file" <<'EOF'
[source.crates-io]
replace-with = 'tuna'

[source.tuna]
registry = "https://mirrors.tuna.tsinghua.edu.cn/git/crates.io-index.git"

[net]
retry = 5
git-fetch-with-cli = true
EOF

    export CARGO_NET_TIMEOUT=120
    export CARGO_HTTP_TIMEOUT=120
}

restore_cargo_mirror() {
    local cargo_home="${CARGO_HOME:-$HOME/.cargo}"
    local config_file="$cargo_home/config.toml"
    local backup_file="$cargo_home/config.toml.equium_backup"

    if [[ -f "$backup_file" ]]; then
        mv "$backup_file" "$config_file"
        log "已恢复原始 Cargo 配置。"
    else
        if [[ -f "$config_file" ]]; then
            grep -q "replace-with = 'tuna'" "$config_file" && rm -f "$config_file"
        fi
    fi
}

#======================== 项目编译（官方 workspace 方式） ========================#
build_equium() {
    local project_dir="$HOME/equium"
    local binary_path="$project_dir/target/release/equium-miner"
    
    if [[ -d "$project_dir" ]]; then
        if [[ ! -f "$binary_path" ]]; then
            log "${YELLOW}检测到未成功的克隆记录，正在清理并重新克隆...${NC}"
            rm -rf "$project_dir"
        fi
    fi

    if [[ ! -d "$project_dir" ]]; then
        log "克隆 Equium 仓库..."
        git clone https://github.com/HannaPrints/equium "$project_dir"
        if [[ $? -ne 0 ]]; then
            log "${RED}克隆失败，请检查网络或仓库地址。${NC}"
            exit 1
        fi
    else
        log "仓库已存在，尝试 git pull 更新..."
        cd "$project_dir" || exit 1
        git pull origin main 2>/dev/null || log "${YELLOW}更新失败，将使用现有代码。${NC}"
    fi

    cd "$project_dir" || { log "${RED}无法进入项目目录。${NC}"; exit 1; }
    log "开始编译（官方 workspace 方式，可能需要几分钟）..."
    
    if [[ -f "$HOME/.cargo/env" ]]; then
        source "$HOME/.cargo/env"
    fi
    export PATH="$HOME/.cargo/bin:$PATH"
    
    if ! command -v cargo &> /dev/null; then
        log "${RED}严重错误：cargo 命令不可用。请尝试重启终端后手动运行：source ~/.cargo/env && cd ~/equium && cargo build -p equium-cli-miner --release${NC}"
        exit 1
    fi

    setup_cargo_mirror
    trap restore_cargo_mirror EXIT

    cargo build -p equium-cli-miner --release
    if [[ $? -ne 0 ]]; then
        log "${RED}编译失败！常见原因：网络不稳定、镜像失效。若反复失败，可尝试手动编译：source ~/.cargo/env && cd ~/equium && cargo build -p equium-cli-miner --release${NC}"
        exit 1
    fi

    restore_cargo_mirror
    trap - EXIT
    log "编译成功！二进制文件位于：$binary_path"
}

#======================== 配置记忆功能 ========================#
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        log "已加载上次配置。"
        return 0
    else
        return 1
    fi
}

save_config() {
    cat > "$CONFIG_FILE" <<EOF
RPC_URL="$rpc_url"
KEYPAIR_PATH="$KEYPAIR_PATH"
EOF
    log "配置已保存。"
}

#======================== 用户交互配置（带记忆） ========================#
configure_rpc() {
    local use_old="n"
    if [[ -n "${RPC_URL}" ]]; then
        echo -e "${BLUE}检测到上次使用的 RPC 地址：${GREEN}${RPC_URL}${NC}"
        read -rp "是否更改？(y/n，默认 n): " use_old
        use_old=${use_old:-n}
        if [[ "$use_old" != "y" ]]; then
            rpc_url="$RPC_URL"
            log "沿用上次 RPC 地址。"
            return 0
        fi
    fi

    echo -e "${BLUE}请输入 Solana RPC 端点 URL（建议使用 Helius 获得稳定连接）${NC}"
    echo -e "如果你没有，可以输入 'default' 使用公共端点（仅适合测试）。"
    read -rp "RPC URL [default]: " rpc_url
    if [[ -z "$rpc_url" || "$rpc_url" == "default" ]]; then
        rpc_url="https://api.mainnet-beta.solana.com"
        log "使用公共 RPC 端点。"
    else
        if [[ ! "$rpc_url" =~ ^https?:// ]]; then
            log "${RED}RPC URL 必须以 http:// 或 https:// 开头。${NC}"
            exit 1
        fi
    fi
    echo -e "${GREEN}RPC 设置为：$rpc_url${NC}"
}

prepare_keypair() {
    if [[ -n "${KEYPAIR_PATH}" && -f "${KEYPAIR_PATH}" ]]; then
        echo -e "${BLUE}检测到上次使用的钱包密钥文件：${GREEN}${KEYPAIR_PATH}${NC}"
        local pubkey
        pubkey=$(solana-keygen pubkey "$KEYPAIR_PATH" 2>/dev/null)
        if [[ -n "$pubkey" ]]; then
            echo -e "${BLUE}对应公钥：${GREEN}${pubkey}${NC}"
            read -rp "是否更改？(y/n，默认 n): " use_old
            use_old=${use_old:-n}
            if [[ "$use_old" != "y" ]]; then
                keypair_path="$KEYPAIR_PATH"
                PUBKEY="$pubkey"
                log "沿用上次钱包。地址：$PUBKEY"
                KEYPAIR_PATH="$keypair_path"
                return 0
            fi
        else
            log "${YELLOW}无法从记忆文件读取公钥，将强制重新配置钱包。${NC}"
        fi
    elif [[ -n "${KEYPAIR_PATH}" && ! -f "${KEYPAIR_PATH}" ]]; then
        log "${RED}上次保存的密钥文件 ${KEYPAIR_PATH} 不存在，请重新配置钱包。${NC}"
    fi

    echo -e "${BLUE}未找到有效的记忆钱包，请配置 Solana 密钥对。${NC}"
    guide_keypair_setup
}

guide_keypair_setup() {
    local keypair_input
    echo -e "${BLUE}你是否有现成的 Solana 密钥对文件（JSON 格式）？${NC}"
    echo -e "通常路径为：~/.config/solana/id.json"
    echo -e "如果是，请输入完整路径；如果否，直接按回车，我们将为你生成一个新钱包。"
    read -rp "密钥文件路径（留空生成新钱包）: " keypair_input

    if [[ -n "$keypair_input" ]]; then
        keypair_path="${keypair_input/#\~/$HOME}"
        if [[ ! -f "$keypair_path" ]]; then
            log "${RED}文件 $keypair_path 不存在。请检查路径后重试。${NC}"
            exit 1
        fi
        log "使用现有密钥文件：$keypair_path"
    else
        log "开始生成新 Solana 钱包..."
        install_solana_cli
        local wallet_dir="$HOME/.config/solana"
        mkdir -p "$wallet_dir"
        keypair_path="$wallet_dir/id.json"
        if [[ -f "$keypair_path" ]]; then
            echo -e "${YELLOW}文件 $keypair_path 已存在。${NC}"
            echo -e "  - 输入 y 覆盖并生成新钱包（旧钱包将被替换）"
            echo -e "  - 输入 n 或直接回车，使用现有文件"
            read -rp "是否覆盖？(y/n，默认 n): " overwrite
            overwrite=${overwrite:-n}
            if [[ "$overwrite" =~ ^[Yy]$ ]]; then
                solana-keygen new --outfile "$keypair_path" --no-bip39-passphrase
                if [[ $? -ne 0 ]]; then
                    log "${RED}钱包生成失败。${NC}"
                    exit 1
                fi
                log "新钱包已生成。请务必保管好你的助记词！"
            else
                log "使用现有钱包文件。"
            fi
        else
            solana-keygen new --outfile "$keypair_path" --no-bip39-passphrase
            if [[ $? -ne 0 ]]; then
                log "${RED}钱包生成失败。${NC}"
                exit 1
            fi
            log "新钱包已生成。请务必保管好你的助记词！"
        fi
    fi

    local pubkey
    pubkey=$(solana-keygen pubkey "$keypair_path" 2>/dev/null)
    if [[ -z "$pubkey" ]]; then
        log "${RED}无法从密钥文件读取公钥，文件可能损坏。${NC}"
        exit 1
    fi
    log "你的 Solana 地址（公钥）：$pubkey"
    echo -e "${YELLOW}⚠️  警告：每次挖矿交易费用低于 0.001 SOL，建议转入 0.005 SOL 以确保稳定运行。${NC}"
    echo -e "挖出的 EQM 会自动存入该钱包关联的 EQM 代币账户，无需额外操作。"
    echo -e "你可以使用任何 Solana 钱包向此地址转账。完成后按回车继续。"
    read -r
    KEYPAIR_PATH="$keypair_path"
    PUBKEY="$pubkey"
}

set_mining_params() {
    echo -e "${BLUE}是否限制挖矿区块数量？${NC}"
    echo -e "输入数字 N 表示挖到 N 个区块后自动停止；直接回车表示无限挖矿。"
    read -rp "最大区块数（留空为无限）: " max_blocks
    if [[ -n "$max_blocks" ]]; then
        if [[ ! "$max_blocks" =~ ^[0-9]+$ ]]; then
            log "${RED}请输入一个正整数。${NC}"
            exit 1
        fi
        MAX_BLOCKS="--max-blocks $max_blocks"
    else
        MAX_BLOCKS=""
    fi
}

select_run_mode() {
    echo -e "${BLUE}请选择运行模式：${NC}"
    echo "  1) 前台运行（终端显示实时日志，Ctrl+C 停止）"
    echo "  2) 后台运行（使用 screen，断开 SSH 也不会停止）"
    read -rp "请输入选项 (1/2) [1]: " mode
    mode=${mode:-1}
    if [[ "$mode" == "2" ]]; then
        RUN_MODE="screen"
    else
        RUN_MODE="foreground"
    fi
}

#======================== 启动挖矿 ========================#
start_mining() {
    local project_dir="$HOME/equium"
    local cmd="$project_dir/target/release/equium-miner --rpc-url $rpc_url --keypair $KEYPAIR_PATH $MAX_BLOCKS"
    
    if [[ ! -f "$project_dir/target/release/equium-miner" ]]; then
        log "${RED}找不到挖矿程序，编译可能失败。请重新运行脚本。${NC}"
        exit 1
    fi
    
    if [[ "$RUN_MODE" == "screen" ]]; then
        if ! check_command screen; then
            log "screen 未安装，尝试安装..."
            brew install screen 2>/dev/null || { log "${RED}请手动安装 screen 后重试。${NC}"; exit 1; }
        fi
        log "后台启动挖矿（screen 会话名：equium_mine）"
        screen -dmS equium_mine bash -c "$cmd 2>&1 | tee -a $LOG_FILE"
        echo -e "${GREEN}挖矿已在后台启动。查看日志：screen -r equium_mine${NC}"
        echo -e "停止挖矿：screen -S equium_mine -X quit"
    else
        log "前台启动挖矿，按 Ctrl+C 停止。"
        $cmd 2>&1 | tee -a "$LOG_FILE"
    fi
}

#======================== 主流程 ========================#
main() {
    rotate_log
    print_header "Equium CPU Miner - macOS 一键部署与运行脚本"
    detect_os

    # 1. 环境依赖
    print_header "环境检测与安装"
    install_rust
    
    if [[ -f "$HOME/.cargo/env" ]]; then
        source "$HOME/.cargo/env"
    fi
    export PATH="$HOME/.cargo/bin:$PATH"
    
    for tool in cmake protobuf; do
        if ! check_command $tool; then
            log "正在安装 $tool..."
            brew install $tool 2>/dev/null || {
                log "${RED}无法通过 Homebrew 安装 $tool，请手动安装。${NC}"
                exit 1
            }
        fi
    done

    # 2. 编译 Equium miner
    print_header "编译 Equium 挖矿程序"
    build_equium

    # 3. 用户配置（带记忆）
    print_header "配置挖矿参数"
    load_config
    configure_rpc
    prepare_keypair
    set_mining_params
    select_run_mode

    save_config

    # 4. 显示摘要并确认
    echo -e "\n${YELLOW}===== 配置摘要 =====${NC}"
    echo -e "RPC 地址：${GREEN}$rpc_url${NC}"
    echo -e "钱包公钥：${GREEN}$PUBKEY${NC}"
    echo -e "密钥文件：${GREEN}$KEYPAIR_PATH${NC}"
    echo -e "额外参数：${GREEN}${MAX_BLOCKS:-无}${NC}"
    echo -e "运行模式：${GREEN}$RUN_MODE${NC}"
    read -rp "确认无误后按 Enter 开始挖矿，或按 Ctrl+C 退出..."

    # 5. 启动挖矿
    print_header "启动挖矿"
    start_mining
}

main "$@"
