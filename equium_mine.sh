#!/bin/bash

#======================== 柔和色彩与基础配置 ========================#
GREEN='\033[1;32m'
BLUE='\033[1;36m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

LOG_FILE="$HOME/equium_miner.log"
MAX_LOG_SIZE=10485760 # 10 MB

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

#======================== 修复 Cargo 镜像协议 ========================#
fix_cargo_registry_protocol() {
    local cargo_config="$HOME/.cargo/config.toml"
    if [[ -f "$cargo_config" ]]; then
        # 检查文件中是否有 git:// 协议（只针对镜像地址）
        if grep -q 'git://' "$cargo_config"; then
            log "检测到 Cargo 配置中包含旧版 git:// 协议，正在自动替换为 https://..."
            # 使用 macOS 的 sed -i '' 时，注意转义
            sed -i '' 's|git://|https://|g' "$cargo_config"
            log "已将 git:// 替换为 https://。"
        else
            log "Cargo 配置未使用 git:// 协议，跳过修复。"
        fi
    else
        log "未发现自定义 Cargo 配置文件，将使用默认源。"
    fi
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
    source "$HOME/.cargo/env"
    log "Rust 安装完成，版本：$(rustc --version 2>/dev/null)"
}

install_solana_cli() {
    if check_command solana; then
        return 0
    fi
    log "正在安装 Solana CLI（需要生成钱包）..."
    sh -c "$(curl -sSfL https://release.solana.com/stable/install)"
    if [[ $? -ne 0 ]]; then
        log "${RED}Solana CLI 安装失败。请手动安装：https://docs.solanalabs.com/cli/install${NC}"
        exit 1
    fi
    export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"
    log "Solana CLI 安装完成。"
}

#======================== 项目编译 ========================#
build_equium() {
    local project_dir="$HOME/equium"
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

    cd "$project_dir/clients/cli-miner" || { log "${RED}目录不存在，请检查仓库结构。${NC}"; exit 1; }
    log "开始编译（可能需要几分钟）..."
    cargo build --release
    if [[ $? -ne 0 ]]; then
        log "${RED}编译失败！请检查上方错误信息。如果提示网络错误，可能是 Cargo 源不稳定，尝试更换镜像或使用代理。${NC}"
        exit 1
    fi
    log "编译成功！二进制文件位于：$project_dir/clients/cli-miner/target/release/equium-miner"
}

#======================== 用户交互配置 ========================#
configure_rpc() {
    echo -e "${BLUE}请输入 Solana RPC 端点 URL（建议使用 Helius 以获得稳定连接）${NC}"
    echo -e "如果你没有，可以输入 'default' 使用公共端点（仅适合测试）。"
    read -rp "RPC URL [default]: " rpc_url
    if [[ -z "$rpc_url" || "$rpc_url" == "default" ]]; then
        rpc_url="https://api.mainnet-beta.solana.com"
        log "使用公共 RPC 端点。"
    else
        # 简单验证 URL 格式
        if [[ ! "$rpc_url" =~ ^https?:// ]]; then
            log "${RED}RPC URL 必须以 http:// 或 https:// 开头。${NC}"
            exit 1
        fi
    fi
    echo -e "${GREEN}RPC 设置为：$rpc_url${NC}"
}

prepare_keypair() {
    local keypair_path=""
    echo -e "${BLUE}你是否有现成的 Solana 密钥对文件（JSON 格式）？${NC}"
    echo -e "通常路径为：~/.config/solana/id.json"
    echo -e "如果是，请输入完整路径；如果否，直接按回车，我们将为你生成一个新钱包。"
    read -rp "密钥文件路径（留空生成新钱包）: " keypair_input

    if [[ -n "$keypair_input" ]]; then
        # 用户提供了路径
        keypair_path="${keypair_input/#\~/$HOME}" # 展开 ~
        if [[ ! -f "$keypair_path" ]]; then
            log "${RED}文件 $keypair_path 不存在。请检查路径后重试。${NC}"
            exit 1
        fi
        log "使用现有密钥文件：$keypair_path"
    else
        # 生成新钱包
        log "开始生成新 Solana 钱包..."
        install_solana_cli  # 确保 solana-keygen 可用
        local wallet_dir="$HOME/.config/solana"
        mkdir -p "$wallet_dir"
        keypair_path="$wallet_dir/id.json"
        # 如果已存在，询问是否覆盖
        if [[ -f "$keypair_path" ]]; then
            read -rp "文件 $keypair_path 已存在，是否覆盖？(y/n) [n]: " overwrite
            if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
                log "请备份旧钱包后重试，或选择使用现有文件。"
                exit 1
            fi
        fi
        solana-keygen new --outfile "$keypair_path" --no-bip39-passphrase
        if [[ $? -ne 0 ]]; then
            log "${RED}钱包生成失败。${NC}"
            exit 1
        fi
        log "新钱包已生成。请务必保管好你的助记词！"
    fi

    # 提取公钥
    local pubkey
    pubkey=$(solana-keygen pubkey "$keypair_path" 2>/dev/null)
    if [[ -z "$pubkey" ]]; then
        log "${RED}无法从密钥文件读取公钥，文件可能损坏。${NC}"
        exit 1
    fi
    log "你的 Solana 地址（公钥）：$pubkey"
    echo -e "${YELLOW}⚠️  警告：请确保该地址已转入至少 0.005 SOL 作为手续费！${NC}"
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
    local project_dir="$HOME/equium/clients/cli-miner"
    local cmd="$project_dir/target/release/equium-miner --rpc-url $rpc_url --keypair $KEYPAIR_PATH $MAX_BLOCKS"
    
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
    # 安装编译可能需要的基本工具（如果未安装）
    for tool in cmake protobuf; do
        if ! check_command $tool; then
            log "正在安装 $tool..."
            brew install $tool 2>/dev/null || {
                log "${RED}无法通过 Homebrew 安装 $tool，请手动安装。${NC}"
                exit 1
            }
        fi
    done

    # 1.5 修复 Cargo 镜像协议（关键修复）
    print_header "检查 Cargo 源配置"
    fix_cargo_registry_protocol

    # 2. 编译 Equium miner
    print_header "编译 Equium 挖矿程序"
    build_equium

    # 3. 用户配置
    print_header "配置挖矿参数"
    configure_rpc
    prepare_keypair
    set_mining_params
    select_run_mode

    # 4. 显示摘要并确认
    echo -e "\n${YELLOW}===== 配置摘要 =====${NC}"
    echo -e "RPC 地址：${GREEN}$rpc_url${NC}"
    echo -e "钱包公钥：${GREEN}$PUBKEY${NC}"
    echo -e "密钥文件：${GREEN}$KEYPAIR_PATH${NC}"
    echo -e "额外参数：${GREEN}${MAX_BLOCKS:-无}${NC}"
    echo -e "运行模式：${GREEN}$RUN_MODE${NC}"
    read -rp "确认无误后按 Enter 开始挖矿，或按 Ctrl+C 退出..."

    # 5. 启动！
    print_header "启动挖矿"
    start_mining
}

main "$@"
