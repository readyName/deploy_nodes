#!/bin/bash

################################################################################
# Arcium Node Automatic Installation Script
# 
# This script automates the complete setup of an Arcium testnet node:
# - Detects OS and installs prerequisites (Rust, Solana CLI, Docker)
# - Installs Arcium CLI and arcup
# - Generates all required keypairs
# - Funds accounts with devnet SOL
# - Initializes node accounts on-chain
# - Creates configuration files
# - Deploys and starts the node
# - Verifies node operation
#
# Usage: bash <(curl -fsSL https://raw.githubusercontent.com/readyName/deploy_nodes/refs/heads/main/arcium/arcium11.sh) [COMMAND]
################################################################################

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
WORKSPACE_DIR="$HOME/arcium-node-setup"
NODE_KEYPAIR="$WORKSPACE_DIR/node-keypair.json"
CALLBACK_KEYPAIR="$WORKSPACE_DIR/callback-kp.json"
IDENTITY_KEYPAIR="$WORKSPACE_DIR/identity.pem"
NODE_CONFIG="$WORKSPACE_DIR/node-config.toml"
DOCKER_CONTAINER_NAME="arx-node"
DEFAULT_RPC_URL="https://api.devnet.solana.com"
RPC_URL=""
PROGRESS_FILE="$WORKSPACE_DIR/.setup_progress"
RPC_CONFIG_FILE="$WORKSPACE_DIR/.rpc_config"
OFFSET_FILE="$WORKSPACE_DIR/.node_offset"
CLUSTER_OFFSET_FILE="$WORKSPACE_DIR/.cluster_offset"
# 代理配置（用于领取空投）
# 该代理支持自动轮换，每次访问会自动切换IP
AIRDROP_PROXY=${AIRDROP_PROXY:-"http://OTstxmpqIqnPXpQX:qS4HD86RgoaIs07L_streaming-1@geo.iproyal.com:12321"}
USE_PROXY_FOR_AIRDROP=${USE_PROXY_FOR_AIRDROP:-true}

################################################################################
# Utility Functions
################################################################################

print_header() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════════════════════════════╗"
    echo "║                                                                                      ║"
    echo "║                    🚀 Arcium Testnet Node Setup v2.0.0 🚀                           ║"
    echo "║                                                                                      ║"
    echo "║              Automatic Installation & Configuration Script                          ║"
    echo "║                                                                                      ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "${YELLOW}✨ Welcome to the Arcium Node Installation Wizard! ✨${NC}\n"
}

print_section() {
    echo -e "\n${BLUE}╭─────────────────────────────────────────────────────────────────────────────╮${NC}"
    echo -e "${BLUE}│ 🚀 $1${NC}"
    echo -e "${BLUE}╰─────────────────────────────────────────────────────────────────────────────╯${NC}\n"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ️  $1${NC}"
}

print_step() {
    echo -e "${YELLOW}🔄 $1${NC}"
}

print_progress() {
    echo -e "${BLUE}📊 $1${NC}"
}

# Progress bar function
show_progress() {
    local current=$1
    local total=$2
    local desc=$3
    local percent=$((current * 100 / total))
    local filled=$((percent / 2))
    local empty=$((50 - filled))
    
    # Clear line and show progress
    printf "\r\033[K${CYAN}🔄 $desc: ["
    printf "%${filled}s" | tr ' ' '='
    printf "%${empty}s" | tr ' ' '-'
    printf "] %d%% (%d/%d)${NC}" "$percent" "$current" "$total"
    
    if [ "$current" -eq "$total" ]; then
        printf "\n"
    fi
}

# Spinner function
show_spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# Detect OS
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        OS="linux"
        print_info "Detected OS: Linux"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
        print_info "Detected OS: macOS"
    else
        print_error "Unsupported OS: $OSTYPE"
        print_warning "This script supports Linux and macOS only"
        exit 1
    fi
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if Docker is running
is_docker_running() {
    if command_exists docker; then
        docker info >/dev/null 2>&1
        return $?
    fi
    return 1
}

# Check if node container exists
node_container_exists() {
    docker ps -a --format '{{.Names}}' | grep -q "^${DOCKER_CONTAINER_NAME}$"
}

# Check if node container is running
is_node_running() {
    docker ps --format '{{.Names}}' | grep -q "^${DOCKER_CONTAINER_NAME}$"
}

# 设置代理环境变量（用于领取空投）
setup_proxy() {
    local proxy_url=$1
    
    if [[ "$USE_PROXY_FOR_AIRDROP" != "true" ]] || [[ -z "$proxy_url" ]]; then
        return 0  # 未启用代理或代理地址为空，直接返回
    fi
    
    # 保存原始代理设置（只在第一次调用时保存）
    if [[ -z "${_ORIGINAL_HTTP_PROXY:-}" ]]; then
        export _ORIGINAL_HTTP_PROXY="${HTTP_PROXY:-}"
        export _ORIGINAL_HTTPS_PROXY="${HTTPS_PROXY:-}"
        export _ORIGINAL_http_proxy="${http_proxy:-}"
        export _ORIGINAL_https_proxy="${https_proxy:-}"
    fi
    
    # 设置代理
    export HTTP_PROXY="$proxy_url"
    export HTTPS_PROXY="$proxy_url"
    export http_proxy="$proxy_url"
    export https_proxy="$proxy_url"
    
    print_info "已设置代理用于领取空投: ${proxy_url%%@*}"
    return 0
}

# 恢复原始代理设置
restore_proxy() {
    if [[ "$USE_PROXY_FOR_AIRDROP" != "true" ]]; then
        return 0
    fi
    
    # 恢复原始代理设置
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
    
    if [[ -n "${_ORIGINAL_http_proxy:-}" ]]; then
        export http_proxy="${_ORIGINAL_http_proxy}"
    else
        unset http_proxy
    fi
    
    if [[ -n "${_ORIGINAL_https_proxy:-}" ]]; then
        export https_proxy="${_ORIGINAL_https_proxy}"
    else
        unset https_proxy
    fi
    
    # 清理临时变量
    unset _ORIGINAL_HTTP_PROXY
    unset _ORIGINAL_HTTPS_PROXY
    unset _ORIGINAL_http_proxy
    unset _ORIGINAL_https_proxy
    
    print_info "已恢复原始代理设置"
    return 0
}

# Check system requirements
check_system_requirements() {
    print_section "System Requirements Check"
    
    print_step "Analyzing system specifications..."
    
    # Check RAM
    if [[ "$OS" == "linux" ]]; then
        TOTAL_RAM=$(free -g | awk '/^Mem:/{print $2}')
        AVAILABLE_RAM=$(free -g | awk '/^Mem:/{print $7}')
    elif [[ "$OS" == "macos" ]]; then
        TOTAL_RAM=$(sysctl -n hw.memsize | awk '{print int($0/1024/1024/1024)}')
        AVAILABLE_RAM=$(vm_stat | grep "Pages free" | awk '{print $3}' | sed 's/\.//' | awk '{print int($0/1024/1024)}')
    fi
    
    print_progress "Total RAM: ${TOTAL_RAM}GB"
    print_progress "Available RAM: ${AVAILABLE_RAM}GB"
    
    # Check disk space
    DISK_SPACE=$(df -h "$HOME" | awk 'NR==2 {print $4}' | sed 's/G//')
    print_progress "Available disk space: ${DISK_SPACE}GB"
    
    # Check GLIBC version on Linux
    if [[ "$OS" == "linux" ]]; then
        GLIBC_VERSION=$(ldd --version | head -n1 | awk '{print $NF}')
        print_progress "GLIBC version: $GLIBC_VERSION"
        
        # Check if GLIBC version is sufficient (requires 2.38+)
        if ! echo "$GLIBC_VERSION" | awk -F. '{if ($1 > 2 || ($1 == 2 && $2 >= 38)) exit 0; else exit 1}'; then
            print_warning "⚠️  GLIBC version $GLIBC_VERSION detected"
            print_warning "⚠️  Anchor CLI requires GLIBC 2.38 or higher"
            print_warning "⚠️  This may cause installation issues"
            echo
            print_info "🔧 To fix this, you can:"
            print_info "  1. Update your system: sudo apt update && sudo apt upgrade"
            print_info "  2. Use a newer Linux distribution (Ubuntu 24.04+, Debian 12+)"
            print_info "  3. Install Anchor manually with a compatible version"
            echo
            print_info "🤔 Do you want to continue anyway? (y/N)"
            read -r response
            if [[ ! "$response" =~ ^[Yy]$ ]]; then
                print_info "❌ Installation cancelled. Please update your system and try again."
                exit 0
            else
                print_warning "⚠️  Continuing with potential GLIBC compatibility issues."
            fi
        else
            print_success "✅ GLIBC version is compatible ($GLIBC_VERSION >= 2.38)"
        fi
    fi
    
    # RAM check
    if [ "$TOTAL_RAM" -lt 32 ]; then
        print_warning "⚠️  Your system has less than 32GB RAM (${TOTAL_RAM}GB detected)"
        print_warning "⚠️  Arcium node requires at least 32GB RAM for optimal performance"
        echo
        print_info "🤔 Do you want to continue anyway? (y/N)"
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            print_info "❌ Installation cancelled. Please upgrade your system to at least 32GB RAM and try again."
            exit 0
        else
            print_warning "⚠️  Continuing with insufficient RAM. Performance may be degraded."
        fi
    else
        print_success "✅ System meets RAM requirements (${TOTAL_RAM}GB >= 32GB)"
    fi
    
    # Disk space check
    if [ "$DISK_SPACE" -lt 50 ]; then
        print_warning "⚠️  Low disk space detected (${DISK_SPACE}GB available)"
        print_warning "⚠️  Recommended: at least 50GB free space"
    else
        print_success "✅ Sufficient disk space available (${DISK_SPACE}GB)"
    fi
    
    echo
}

# Save progress
save_progress() {
    local step="$1"
    # Ensure workspace directory exists
    mkdir -p "$WORKSPACE_DIR"
    echo "$step" > "$PROGRESS_FILE"
    print_info "Progress saved: $step"
}

# Load progress
load_progress() {
    if [ -f "$PROGRESS_FILE" ]; then
        cat "$PROGRESS_FILE"
    else
        echo "start"
    fi
}

# Clear progress
clear_progress() {
    rm -f "$PROGRESS_FILE"
    print_info "Progress cleared"
}

# Save RPC configuration
save_rpc_config() {
    # Ensure workspace directory exists
    mkdir -p "$WORKSPACE_DIR"
    echo "$RPC_URL" > "$RPC_CONFIG_FILE"
    print_info "RPC configuration saved: $RPC_URL"
}

# Load RPC configuration
load_rpc_config() {
    if [ -f "$RPC_CONFIG_FILE" ]; then
        RPC_URL=$(cat "$RPC_CONFIG_FILE")
        print_info "Loaded RPC configuration: $RPC_URL"
    else
        RPC_URL="$DEFAULT_RPC_URL"
        print_info "Using default RPC: $RPC_URL"
    fi
}

# Clear RPC configuration
clear_rpc_config() {
    rm -f "$RPC_CONFIG_FILE"
    print_info "RPC configuration cleared"
}

# Save node offset
save_node_offset() {
    # Ensure workspace directory exists
    mkdir -p "$WORKSPACE_DIR"
    echo "$NODE_OFFSET" > "$OFFSET_FILE"
    print_info "Node offset saved: $NODE_OFFSET"
}

# Load node offset
load_node_offset() {
    if [ -f "$OFFSET_FILE" ]; then
        NODE_OFFSET=$(cat "$OFFSET_FILE")
        print_info "Loaded node offset: $NODE_OFFSET"
    else
        print_warning "No saved node offset found"
        return 1
    fi
}

# Clear node offset
clear_node_offset() {
    rm -f "$OFFSET_FILE"
    print_info "Node offset cleared"
}

# Save cluster offset
save_cluster_offset() {
    # Ensure workspace directory exists
    mkdir -p "$WORKSPACE_DIR"
    echo "$CLUSTER_OFFSET" > "$CLUSTER_OFFSET_FILE"
    print_info "Cluster offset saved: $CLUSTER_OFFSET"
}

# Load cluster offset
load_cluster_offset() {
    if [ -f "$CLUSTER_OFFSET_FILE" ]; then
        CLUSTER_OFFSET=$(cat "$CLUSTER_OFFSET_FILE")
        print_info "Loaded cluster offset: $CLUSTER_OFFSET"
    else
        print_warning "No saved cluster offset found"
        return 1
    fi
}

# Clear cluster offset
clear_cluster_offset() {
    rm -f "$CLUSTER_OFFSET_FILE"
    print_info "Cluster offset cleared"
}

# Show help
show_help() {
    echo -e "${CYAN}Arcium Node Management Script v2.0.0${NC}\n"
    echo -e "${YELLOW}Usage:${NC} bash <(curl -fsSL https://raw.githubusercontent.com/readyName/deploy_nodes/refs/heads/main/arcium/arcium11.sh) [COMMAND]\n"
    echo -e "${YELLOW}Commands:${NC}"
    echo -e "  ${GREEN}install${NC}     Install and setup a new Arcium node"
    echo -e "  ${GREEN}start${NC}       Start an existing node"
    echo -e "  ${GREEN}stop${NC}        Stop the running node"
    echo -e "  ${GREEN}restart${NC}     Restart the node"
    echo -e "  ${GREEN}status${NC}      Check node status"
    echo -e "  ${GREEN}info${NC}        Show node information"
    echo -e "  ${GREEN}active${NC}      Check if node is active on network"
    echo -e "  ${GREEN}logs${NC}        Show node logs"
    echo -e "  ${GREEN}help${NC}        Show this help message\n"
    echo -e "${YELLOW}Examples:${NC}"
    echo -e "  bash <(curl -fsSL https://raw.githubusercontent.com/readyName/deploy_nodes/refs/heads/main/arcium/arcium11.sh) install"
    echo -e "  bash <(curl -fsSL https://raw.githubusercontent.com/readyName/deploy_nodes/refs/heads/main/arcium/arcium11.sh) start"
    echo -e "  bash <(curl -fsSL https://raw.githubusercontent.com/readyName/deploy_nodes/refs/heads/main/arcium/arcium11.sh) status"
    echo -e "  bash <(curl -fsSL https://raw.githubusercontent.com/readyName/deploy_nodes/refs/heads/main/arcium/arcium11.sh) logs"
    echo -e "  bash <(curl -fsSL https://raw.githubusercontent.com/readyName/deploy_nodes/refs/heads/main/arcium/arcium11.sh) info"
    echo -e "  bash <(curl -fsSL https://raw.githubusercontent.com/readyName/deploy_nodes/refs/heads/main/arcium/arcium11.sh) active"
}

# Check if node is installed
is_node_installed() {
    [ -f "$NODE_CONFIG" ] && [ -f "$NODE_KEYPAIR" ] && [ -f "$CALLBACK_KEYPAIR" ] && [ -f "$IDENTITY_KEYPAIR" ]
}

# Start node
start_node() {
    print_section "Starting Arcium Node"
    
    if ! is_node_installed; then
        print_error "Node is not installed. Run '$0 install' first."
        exit 1
    fi
    
    if is_node_running; then
        print_warning "Node is already running"
        return 0
    fi
    
    print_info "Starting node container..."
    docker start "$DOCKER_CONTAINER_NAME"
    
    if is_node_running; then
        print_success "Node started successfully"
    else
        print_error "Failed to start node"
        exit 1
    fi
}

# Stop node
stop_node() {
    print_section "Stopping Arcium Node"
    
    if ! is_node_running; then
        print_warning "Node is not running"
        return 0
    fi
    
    print_info "Stopping node container..."
    docker stop "$DOCKER_CONTAINER_NAME"
    
    if ! is_node_running; then
        print_success "Node stopped successfully"
    else
        print_error "Failed to stop node"
        exit 1
    fi
}

# Restart node
restart_node() {
    print_section "Restarting Arcium Node"
    
    if ! is_node_installed; then
        print_error "Node is not installed. Run '$0 install' first."
        exit 1
    fi
    
    print_info "Restarting node container..."
    docker restart "$DOCKER_CONTAINER_NAME"
    
    if is_node_running; then
        print_success "Node restarted successfully"
    else
        print_error "Failed to restart node"
        exit 1
    fi
}

# Show node status
show_node_status() {
    print_section "Node Status"
    
    if ! is_node_installed; then
        print_error "Node is not installed. Run '$0 install' first."
        exit 1
    fi
    
    if is_node_running; then
        print_success "✅ Node is running"
        print_info "Container: $DOCKER_CONTAINER_NAME"
        print_info "Status: $(docker ps --format 'table {{.Status}}' --filter name=$DOCKER_CONTAINER_NAME | tail -n +2)"
    else
        print_warning "⚠️  Node is not running"
    fi
    
    # Load saved offset
    if load_node_offset; then
        print_info "Node offset: $NODE_OFFSET"
    fi
}

# Show node info
show_node_info() {
    print_section "Node Information"
    
    if ! is_node_installed; then
        print_error "Node is not installed. Run '$0 install' first."
        exit 1
    fi
    
    # Load configurations
    load_rpc_config
    load_node_offset
    load_cluster_offset
    
    print_info "Node Details:"
    print_info "  📁 Workspace: $WORKSPACE_DIR"
    print_info "  🔑 Node Pubkey: $(solana address --keypair-path "$NODE_KEYPAIR")"
    print_info "  🔢 Node Offset: $NODE_OFFSET"
    if [ -n "$CLUSTER_OFFSET" ]; then
        print_info "  🔢 Cluster Offset: $CLUSTER_OFFSET"
    fi
    print_info "  🌐 Public IP: $PUBLIC_IP"
    print_info "  🔗 RPC Endpoint: $RPC_URL"
    print_info "  📊 Container: $DOCKER_CONTAINER_NAME"
    
    if is_node_running; then
        print_success "✅ Node is running"
    else
        print_warning "⚠️  Node is not running"
    fi
}

# Check if node is active
check_node_active() {
    print_section "Checking Node Activity"
    
    if ! is_node_installed; then
        print_error "Node is not installed. Run '$0 install' first."
        exit 1
    fi
    
    if ! load_node_offset; then
        print_error "No node offset found. Run '$0 install' first."
        exit 1
    fi
    
    load_rpc_config
    
    print_info "Checking if node is active on network..."
    print_info "Node offset: $NODE_OFFSET"
    print_info "RPC URL: $RPC_URL"
    
    if arcium arx-active "$NODE_OFFSET" --rpc-url "$RPC_URL"; then
        print_success "✅ Node is active on the network"
    else
        print_warning "⚠️  Node is not active on the network"
    fi
}

# Show node logs
show_node_logs() {
    print_section "Node Logs"
    
    if ! is_node_installed; then
        print_error "Node is not installed. Run '$0 install' first."
        exit 1
    fi
    
    if ! is_node_running; then
        print_warning "Node is not running. Starting node first..."
        start_node
    fi
    
    print_info "Showing node logs (Press Ctrl+C to exit)..."
    echo
    
    # Show logs from file if available, otherwise from container
    if [ -f "$WORKSPACE_DIR/arx-node-logs/arx.log" ]; then
        tail -f "$WORKSPACE_DIR/arx-node-logs/arx.log"
    else
        docker logs -f "$DOCKER_CONTAINER_NAME"
    fi
}

# Select RPC endpoint
select_rpc() {
    print_section "RPC Endpoint Configuration"
    
    echo -e "${CYAN}🌐 Configure Solana Devnet RPC endpoint:${NC}\n"
    echo -e "${YELLOW}Default RPC:${NC} ${BLUE}$DEFAULT_RPC_URL${NC}"
    echo -e "${GREEN}✅ Press Enter to use default, or enter your custom RPC URL${NC}\n"
    
    print_info "🔗 Please enter your Solana Devnet RPC endpoint (or press Enter for default):"
    print_warning "⚠️  Make sure it's a valid Solana devnet RPC endpoint"
    echo -n -e "${CYAN}RPC URL [${DEFAULT_RPC_URL}]: ${NC}"
    read -r custom_rpc
    
    # 如果用户直接回车（不输入），使用默认值
    if [ -z "$custom_rpc" ]; then
        RPC_URL="$DEFAULT_RPC_URL"
        print_success "✅ Using default RPC endpoint: $RPC_URL"
    else
        # 去除前后空格
        custom_rpc=$(echo "$custom_rpc" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        # 基本验证
        if [[ "$custom_rpc" =~ ^https?:// ]]; then
            RPC_URL="$custom_rpc"
            print_success "✅ Custom RPC endpoint set: $RPC_URL"
        else
            print_error "❌ Invalid RPC URL format. Must start with http:// or https://"
            print_info "🔄 Using default RPC endpoint instead"
            RPC_URL="$DEFAULT_RPC_URL"
        fi
    fi
    
    # Save RPC configuration
    save_rpc_config
    echo
}

# Resume from saved progress
resume_from_progress() {
    local last_step=$(load_progress)
    
    if [ "$last_step" = "start" ]; then
        print_info "Starting fresh installation"
        return 0
    fi
    
    print_section "Resuming Installation from Previous Progress"
    print_info "Last completed step: $last_step"
    
    # Load RPC configuration
    load_rpc_config
    
    # Load offsets
    load_node_offset
    load_cluster_offset
    
    case "$last_step" in
        "funding_failed")
            print_info "Resuming from funding step..."
            fund_accounts
            initialize_node_accounts
            initialize_cluster
            propose_join_cluster
            join_cluster
            verify_node_in_cluster
            create_node_config
            deploy_node
            verify_node
            clear_progress
            ;;
        "init_failed")
            print_info "Resuming from initialization step..."
            initialize_node_accounts
            initialize_cluster
            propose_join_cluster
            join_cluster
            verify_node_in_cluster
            create_node_config
            deploy_node
            verify_node
            clear_progress
            ;;
        "cluster_init_failed")
            print_info "Resuming from cluster initialization step..."
            initialize_cluster
            propose_join_cluster
            join_cluster
            verify_node_in_cluster
            create_node_config
            deploy_node
            verify_node
            clear_progress
            ;;
        "propose_failed")
            print_info "Resuming from proposal step..."
            propose_join_cluster
            join_cluster
            verify_node_in_cluster
            create_node_config
            deploy_node
            verify_node
            clear_progress
            ;;
        "join_failed")
            print_info "Resuming from join step..."
            join_cluster
            verify_node_in_cluster
            create_node_config
            deploy_node
            verify_node
            clear_progress
            ;;
        "deploy_failed")
            print_info "Resuming from deployment step..."
            deploy_node
            verify_node
            clear_progress
            ;;
        *)
            print_warning "Unknown progress state: $last_step"
            print_info "Starting fresh installation"
            clear_progress
            return 0
            ;;
    esac
}

################################################################################
# Installation Functions
################################################################################

# Install Rust
install_rust() {
    print_section "Installing Rust"
    
    if command_exists rustc && command_exists cargo; then
        RUST_VERSION=$(rustc --version 2>/dev/null | awk '{print $2}')
        CARGO_VERSION=$(cargo --version 2>/dev/null | awk '{print $2}')
        if [ -n "$RUST_VERSION" ] && [ -n "$CARGO_VERSION" ]; then
            print_success "Rust is already installed: v$RUST_VERSION"
            print_success "Cargo is already installed: v$CARGO_VERSION"
            return 0
        fi
    fi
    
    print_info "Installing Rust via rustup..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    
    # Source cargo env
    source "$HOME/.cargo/env"
    
    if command_exists rustc && command_exists cargo; then
        print_success "Rust installed successfully: $(rustc --version)"
        print_success "Cargo installed successfully: $(cargo --version)"
    else
        print_error "Rust installation failed"
        exit 1
    fi
}

# Install Solana CLI
install_solana() {
    print_section "Installing Solana CLI"
    
    if command_exists solana; then
        SOLANA_VERSION=$(solana --version | awk '{print $2}')
        print_success "Solana CLI is already installed: v$SOLANA_VERSION"
        
        # Configure Solana CLI with RPC URL (use default if not set)
        if [ -z "$RPC_URL" ]; then
            RPC_URL="$DEFAULT_RPC_URL"
        fi
        print_info "Configuring Solana CLI with RPC URL..."
        solana config set --url "$RPC_URL"
        print_success "Solana CLI configured with RPC: $RPC_URL"
        return 0
    fi
    
    print_info "Installing Solana CLI..."
    curl --proto '=https' --tlsv1.2 -sSfL https://solana-install.solana.workers.dev | bash
    
    # Add to PATH
    export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"
    
    if command_exists solana; then
        print_success "Solana CLI installed successfully: $(solana --version)"
        
        # Configure Solana CLI with RPC URL (use default if not set)
        if [ -z "$RPC_URL" ]; then
            RPC_URL="$DEFAULT_RPC_URL"
        fi
        print_info "Configuring Solana CLI with RPC URL..."
        solana config set --url "$RPC_URL"
        print_success "Configured with RPC: $RPC_URL"
    else
        print_error "Solana CLI installation failed"
        exit 1
    fi
}

# Install Docker
install_docker() {
    print_section "Installing Docker"
    
    if command_exists docker; then
        DOCKER_VERSION=$(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',')
        if [ -n "$DOCKER_VERSION" ]; then
            print_success "Docker is already installed: v$DOCKER_VERSION"
            
            if is_docker_running; then
                print_success "Docker is running"
                return 0
            else
                print_warning "Docker is installed but not running"
                print_info "Attempting to start Docker..."
                
                if [[ "$OS" == "macos" ]]; then
                    open -a Docker
                    print_info "Waiting for Docker to start..."
                    sleep 10
                    
                    if is_docker_running; then
                        print_success "Docker started successfully"
                        return 0
                    fi
                elif [[ "$OS" == "linux" ]]; then
                    sudo systemctl start docker
                    if is_docker_running; then
                        print_success "Docker started successfully"
                        return 0
                    fi
                fi
                
                print_error "Could not start Docker. Please start it manually and run this script again."
                exit 1
            fi
        fi
    fi
    
    print_info "Installing Docker..."
    
    if [[ "$OS" == "linux" ]]; then
        # Install Docker on Linux
        sudo apt-get update
        sudo apt-get install -y docker.io
        sudo systemctl start docker
        sudo systemctl enable docker
        
        # Add user to docker group
        sudo usermod -aG docker "$USER"
        print_warning "You've been added to the docker group. You may need to log out and back in."
        
        # Try to use docker with sudo for this session
        print_info "Using sudo for Docker commands in this session..."
        
    elif [[ "$OS" == "macos" ]]; then
        print_error "Please install Docker Desktop manually from https://www.docker.com/products/docker-desktop"
        print_info "After installation, run this script again."
        exit 1
    fi
    
    if is_docker_running; then
        print_success "Docker installed and running"
    else
        print_error "Docker installation failed or not running"
        exit 1
    fi
}

# Install Arcium CLI
install_arcium() {
    print_section "Installing Arcium CLI"
    
    if command_exists arcium; then
        ARCIUM_VERSION=$(arcium --version 2>/dev/null | head -n1 || echo "unknown")
        if [ "$ARCIUM_VERSION" != "unknown" ] && [ -n "$ARCIUM_VERSION" ]; then
            print_success "Arcium CLI is already installed: $ARCIUM_VERSION"
            return 0
        fi
    fi
    
    print_info "Installing Arcium CLI via arcium-install..."
    
    # Check for GLIBC compatibility issues
    if [[ "$OS" == "linux" ]]; then
        GLIBC_VERSION=$(ldd --version | head -n1 | awk '{print $NF}')
        if ! echo "$GLIBC_VERSION" | awk -F. '{if ($1 > 2 || ($1 == 2 && $2 >= 38)) exit 0; else exit 1}'; then
            print_warning "⚠️  GLIBC compatibility issue detected"
            print_info "🔧 Attempting alternative installation method..."
            
            # Try to install from source or use alternative method
            print_info "Installing Rust toolchain first..."
            if ! command_exists cargo; then
                curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
                source "$HOME/.cargo/env"
            fi
            
            print_info "Building Arcium CLI from source..."
            if cargo install arcium-cli; then
                print_success "Arcium CLI installed from source"
                return 0
            else
                print_warning "Source installation failed, trying standard method..."
            fi
        fi
    fi
    
    # Standard installation
    curl --proto '=https' --tlsv1.2 -sSfL https://install.arcium.com/ | bash
    
    # Source the shell configuration to get arcium in PATH
    if [ -f "$HOME/.bashrc" ]; then
        source "$HOME/.bashrc"
    fi
    if [ -f "$HOME/.zshrc" ]; then
        source "$HOME/.zshrc"
    fi
    
    # Add to current session PATH
    export PATH="$HOME/.arcium/bin:$PATH"
    
    if command_exists arcium; then
        ARCIUM_VERSION=$(arcium --version 2>/dev/null | head -n1 || echo "unknown")
        print_success "Arcium CLI installed successfully: $ARCIUM_VERSION"
    else
        print_error "Arcium CLI installation failed"
        print_warning "This may be due to GLIBC compatibility issues"
        print_info "Try updating your system or using a newer Linux distribution"
        exit 1
    fi
}

################################################################################
# Node Setup Functions
################################################################################

# 备份、删除、重建目录并恢复密钥文件
backup_and_rebuild_directories() {
    print_section "Backing Up and Rebuilding Directories"
    
    local NODE_DIR="$HOME/arcium-node-setup"
    local CLUSTER_DIR="$HOME/arcium-cluster-setup"
    local BACKUP_DIR="$HOME/.arcium-backup-$(date +%s)"
    local keys_found=false
    
    # 创建备份目录
    mkdir -p "$BACKUP_DIR"
    print_info "备份目录: $BACKUP_DIR"
    
    # 检测并备份节点密钥文件
    if [ -f "$NODE_DIR/node-keypair.json" ]; then
        print_info "检测到节点密钥文件，正在备份..."
        cp "$NODE_DIR/node-keypair.json" "$BACKUP_DIR/node-keypair.json" 2>/dev/null && {
            print_success "✓ 已备份 node-keypair.json"
            keys_found=true
        } || print_warning "⚠️  备份 node-keypair.json 失败"
    fi
    
    if [ -f "$NODE_DIR/callback-kp.json" ]; then
        print_info "检测到回调密钥文件，正在备份..."
        cp "$NODE_DIR/callback-kp.json" "$BACKUP_DIR/callback-kp.json" 2>/dev/null && {
            print_success "✓ 已备份 callback-kp.json"
            keys_found=true
        } || print_warning "⚠️  备份 callback-kp.json 失败"
    fi
    
    if [ -f "$NODE_DIR/identity.pem" ]; then
        print_info "检测到身份密钥文件，正在备份..."
        cp "$NODE_DIR/identity.pem" "$BACKUP_DIR/identity.pem" 2>/dev/null && {
            print_success "✓ 已备份 identity.pem"
            keys_found=true
        } || print_warning "⚠️  备份 identity.pem 失败"
    fi
    
    # 备份集群目录中的密钥（如果存在）
    if [ -f "$CLUSTER_DIR/cluster-owner-keypair.json" ]; then
        print_info "检测到集群所有者密钥文件，正在备份..."
        mkdir -p "$BACKUP_DIR/cluster"
        cp "$CLUSTER_DIR/cluster-owner-keypair.json" "$BACKUP_DIR/cluster/cluster-owner-keypair.json" 2>/dev/null && {
            print_success "✓ 已备份 cluster-owner-keypair.json"
            keys_found=true
        } || print_warning "⚠️  备份 cluster-owner-keypair.json 失败"
        
        # 备份集群信息文件（如果存在）
        if [ -f "$CLUSTER_DIR/cluster-info.txt" ]; then
            cp "$CLUSTER_DIR/cluster-info.txt" "$BACKUP_DIR/cluster/cluster-info.txt" 2>/dev/null && {
                print_success "✓ 已备份 cluster-info.txt"
            } || print_warning "⚠️  备份 cluster-info.txt 失败"
        fi
    fi
    
    if [ "$keys_found" = true ]; then
        print_success "✅ 密钥文件备份完成"
    else
        print_info "未检测到密钥文件，跳过备份"
    fi
    
    # 删除现有目录
    print_info "删除现有目录..."
    if [ -d "$NODE_DIR" ]; then
        print_info "删除节点目录: $NODE_DIR"
        rm -rf "$NODE_DIR" && print_success "✓ 节点目录已删除" || print_warning "⚠️  删除节点目录失败"
    else
        print_info "节点目录不存在，跳过删除"
    fi
    
    if [ -d "$CLUSTER_DIR" ]; then
        print_info "删除集群目录: $CLUSTER_DIR"
        rm -rf "$CLUSTER_DIR" && print_success "✓ 集群目录已删除" || print_warning "⚠️  删除集群目录失败"
    else
        print_info "集群目录不存在，跳过删除"
    fi
    
    # 重新创建目录
    print_info "重新创建目录..."
    mkdir -p "$NODE_DIR" && print_success "✓ 节点目录已创建: $NODE_DIR" || {
        print_error "创建节点目录失败"
        return 1
    }
    
    mkdir -p "$CLUSTER_DIR" && print_success "✓ 集群目录已创建: $CLUSTER_DIR" || {
        print_error "创建集群目录失败"
        return 1
    }
    
    # 恢复备份的密钥文件
    if [ "$keys_found" = true ]; then
        print_info "恢复备份的密钥文件..."
        
        if [ -f "$BACKUP_DIR/node-keypair.json" ]; then
            cp "$BACKUP_DIR/node-keypair.json" "$NODE_DIR/node-keypair.json" 2>/dev/null && {
                print_success "✓ 已恢复 node-keypair.json"
            } || print_warning "⚠️  恢复 node-keypair.json 失败"
        fi
        
        if [ -f "$BACKUP_DIR/callback-kp.json" ]; then
            cp "$BACKUP_DIR/callback-kp.json" "$NODE_DIR/callback-kp.json" 2>/dev/null && {
                print_success "✓ 已恢复 callback-kp.json"
            } || print_warning "⚠️  恢复 callback-kp.json 失败"
        fi
        
        if [ -f "$BACKUP_DIR/identity.pem" ]; then
            cp "$BACKUP_DIR/identity.pem" "$NODE_DIR/identity.pem" 2>/dev/null && {
                print_success "✓ 已恢复 identity.pem"
            } || print_warning "⚠️  恢复 identity.pem 失败"
        fi
        
        # 恢复集群密钥文件
        if [ -f "$BACKUP_DIR/cluster/cluster-owner-keypair.json" ]; then
            cp "$BACKUP_DIR/cluster/cluster-owner-keypair.json" "$CLUSTER_DIR/cluster-owner-keypair.json" 2>/dev/null && {
                print_success "✓ 已恢复 cluster-owner-keypair.json"
            } || print_warning "⚠️  恢复 cluster-owner-keypair.json 失败"
        fi
        
        if [ -f "$BACKUP_DIR/cluster/cluster-info.txt" ]; then
            cp "$BACKUP_DIR/cluster/cluster-info.txt" "$CLUSTER_DIR/cluster-info.txt" 2>/dev/null && {
                print_success "✓ 已恢复 cluster-info.txt"
            } || print_warning "⚠️  恢复 cluster-info.txt 失败"
        fi
        
        print_success "✅ 密钥文件恢复完成"
        print_info "备份文件保存在: $BACKUP_DIR"
    else
        print_info "没有备份文件需要恢复"
    fi
    
    print_success "✅ 目录重建和密钥恢复完成"
}

# Create workspace directory
setup_workspace() {
    print_section "Setting Up Workspace"
    
    if [ -d "$WORKSPACE_DIR" ]; then
        print_warning "Workspace directory already exists: $WORKSPACE_DIR"
    else
        print_info "Creating workspace directory: $WORKSPACE_DIR"
        mkdir -p "$WORKSPACE_DIR"
        print_success "Workspace created"
    fi
    
    cd "$WORKSPACE_DIR"
}

# Get public IP
get_public_ip() {
    print_section "Detecting Public IP Address"
    
    PUBLIC_IP=$(curl -s https://ipecho.net/plain || curl -s https://api.ipify.org || curl -s https://ifconfig.me)
    
    if [ -z "$PUBLIC_IP" ]; then
        print_error "Could not detect public IP address"
        print_info "Please enter your public IP manually:"
        read -r PUBLIC_IP
    fi
    
    print_success "Public IP: $PUBLIC_IP"
}

# Generate keypairs
generate_keypairs() {
    print_section "Generating Keypairs"
    
    # 检查并验证密钥文件是否有效
    local keys_valid=true
    local node_key_valid=false
    local callback_key_valid=false
    local identity_key_valid=false
    
    # 验证节点密钥对
    if [ -f "$NODE_KEYPAIR" ]; then
        if solana address --keypair "$NODE_KEYPAIR" >/dev/null 2>&1; then
            node_key_valid=true
            print_success "✓ 检测到有效的节点密钥对: $NODE_KEYPAIR"
        else
            print_warning "⚠️  节点密钥文件存在但已损坏: $NODE_KEYPAIR"
            keys_valid=false
        fi
    else
        print_info "未找到节点密钥文件，将创建新密钥"
        keys_valid=false
    fi
    
    # 验证回调密钥对
    if [ -f "$CALLBACK_KEYPAIR" ]; then
        if solana address --keypair "$CALLBACK_KEYPAIR" >/dev/null 2>&1; then
            callback_key_valid=true
            print_success "✓ 检测到有效的回调密钥对: $CALLBACK_KEYPAIR"
        else
            print_warning "⚠️  回调密钥文件存在但已损坏: $CALLBACK_KEYPAIR"
            keys_valid=false
        fi
    else
        print_info "未找到回调密钥文件，将创建新密钥"
        keys_valid=false
    fi
    
    # 验证身份密钥对（identity.pem 是 Ed25519 格式，只需检查文件是否存在）
    if [ -f "$IDENTITY_KEYPAIR" ]; then
        # 检查文件大小，Ed25519 私钥通常至少有几个字节
        if [ -s "$IDENTITY_KEYPAIR" ]; then
            identity_key_valid=true
            print_success "✓ 检测到有效的身份密钥对: $IDENTITY_KEYPAIR"
        else
            print_warning "⚠️  身份密钥文件存在但为空: $IDENTITY_KEYPAIR"
            keys_valid=false
        fi
    else
        print_info "未找到身份密钥文件，将创建新密钥"
        keys_valid=false
    fi
    
    # 如果所有密钥都有效，跳过生成
    if [ "$node_key_valid" = true ] && [ "$callback_key_valid" = true ] && [ "$identity_key_valid" = true ]; then
        print_success "✅ 所有密钥文件已存在且有效，使用现有密钥"
    else
        # 备份损坏的文件（如果存在）
        if [ -f "$NODE_KEYPAIR" ] && [ "$node_key_valid" = false ]; then
            print_warning "备份损坏的节点密钥文件..."
            cp "$NODE_KEYPAIR" "${NODE_KEYPAIR}.backup.$(date +%s)" 2>/dev/null || true
        fi
        
        if [ -f "$CALLBACK_KEYPAIR" ] && [ "$callback_key_valid" = false ]; then
            print_warning "备份损坏的回调密钥文件..."
            cp "$CALLBACK_KEYPAIR" "${CALLBACK_KEYPAIR}.backup.$(date +%s)" 2>/dev/null || true
        fi
        
        if [ -f "$IDENTITY_KEYPAIR" ] && [ "$identity_key_valid" = false ]; then
            print_warning "备份损坏的身份密钥文件..."
            cp "$IDENTITY_KEYPAIR" "${IDENTITY_KEYPAIR}.backup.$(date +%s)" 2>/dev/null || true
        fi
        
        # 生成缺失或损坏的密钥
        if [ "$node_key_valid" = false ]; then
            print_info "生成节点密钥对..."
            if ! solana-keygen new --outfile "$NODE_KEYPAIR" --no-bip39-passphrase --force; then
                print_error "生成节点密钥对失败"
                return 1
            fi
            print_success "节点密钥对生成完成"
        fi
        
        if [ "$callback_key_valid" = false ]; then
            print_info "生成回调密钥对..."
            if ! solana-keygen new --outfile "$CALLBACK_KEYPAIR" --no-bip39-passphrase --force; then
                print_error "生成回调密钥对失败"
                return 1
            fi
            print_success "回调密钥对生成完成"
        fi
        
        if [ "$identity_key_valid" = false ]; then
            print_info "生成身份密钥对 (PKCS#8 Ed25519 格式)..."
            if ! openssl genpkey -algorithm Ed25519 -out "$IDENTITY_KEYPAIR"; then
                print_error "生成身份密钥对失败"
                return 1
            fi
            print_success "身份密钥对生成完成"
        fi
    fi
    
    # 显示公钥信息
    print_info "读取密钥对信息..."
    NODE_PUBKEY=$(solana address -k "$NODE_KEYPAIR" 2>/dev/null || solana address --keypair "$NODE_KEYPAIR" 2>/dev/null)
    CALLBACK_PUBKEY=$(solana address -k "$CALLBACK_KEYPAIR" 2>/dev/null || solana address --keypair "$CALLBACK_KEYPAIR" 2>/dev/null)
    
    if [ -n "$NODE_PUBKEY" ]; then
        print_success "节点公钥: $NODE_PUBKEY"
    else
        print_warning "无法读取节点公钥"
    fi
    
    if [ -n "$CALLBACK_PUBKEY" ]; then
        print_success "回调公钥: $CALLBACK_PUBKEY"
    else
        print_warning "无法读取回调公钥"
    fi
}

# Fund accounts with infinite retry and proxy rotation
fund_accounts() {
    print_section "Funding Accounts with Devnet SOL"
    
    NODE_PUBKEY=$(solana address -k "$NODE_KEYPAIR")
    CALLBACK_PUBKEY=$(solana address -k "$CALLBACK_KEYPAIR")
    
    # 为节点账户领水（无限重试，每次切换代理）
    print_info "Checking node account balance..."
    NODE_BALANCE=$(solana balance "$NODE_PUBKEY" -u devnet 2>/dev/null | awk '{print $1}')
    
    if (( $(echo "$NODE_BALANCE >= 2" | bc -l) )); then
        print_success "Node account has sufficient balance: $NODE_BALANCE SOL"
        # 确保代理已恢复（防止之前设置过代理）
        restore_proxy
    else
        print_warning "Node account balance insufficient ($NODE_BALANCE SOL), starting infinite retry with proxy rotation..."
        
        # 只在需要领取空投时设置代理
        if [[ "$USE_PROXY_FOR_AIRDROP" == "true" ]] && [[ -n "$AIRDROP_PROXY" ]]; then
            setup_proxy "$AIRDROP_PROXY"
        fi
        
        local attempt=0
        
        while true; do
            attempt=$((attempt + 1))
            
            # 每次重试都会使用代理，代理服务会自动切换IP
            if [[ "$USE_PROXY_FOR_AIRDROP" == "true" ]] && [[ -n "$AIRDROP_PROXY" ]]; then
                print_step "尝试为节点账户申请空投 (第 $attempt 次，使用代理，代理将自动切换IP)..."
            else
                print_step "尝试为节点账户申请空投 (第 $attempt 次，不使用代理)..."
            fi
            
            if solana airdrop 2 "$NODE_PUBKEY" -u devnet 2>/dev/null; then
                print_success "空投请求已提交，等待到账..."
                # 领取成功后立即恢复代理，后续操作不使用代理
                restore_proxy
                sleep 5
                
                # 验证余额是否到账
                NODE_BALANCE=$(solana balance "$NODE_PUBKEY" -u devnet 2>/dev/null | awk '{print $1}')
                if (( $(echo "$NODE_BALANCE >= 2" | bc -l) )); then
                    print_success "节点账户已获得注资，当前余额: $NODE_BALANCE SOL"
                    break
                else
                    print_info "等待余额到账，当前余额: $NODE_BALANCE SOL，继续重试..."
                fi
            else
                print_warning "空投失败，10秒后重试（代理将自动切换IP）..."
                sleep 10
            fi
        done
        
        # 确保恢复原始代理设置（双重保险）
        restore_proxy
    fi
    
    # 为回调账户领水（无限重试，每次切换代理）
    print_info "Checking callback account balance..."
    CALLBACK_BALANCE=$(solana balance "$CALLBACK_PUBKEY" -u devnet 2>/dev/null | awk '{print $1}')
    
    if (( $(echo "$CALLBACK_BALANCE >= 2" | bc -l) )); then
        print_success "Callback account has sufficient balance: $CALLBACK_BALANCE SOL"
        # 确保代理已恢复（防止之前设置过代理）
        restore_proxy
    else
        print_warning "Callback account balance insufficient ($CALLBACK_BALANCE SOL), starting infinite retry with proxy rotation..."
        
        # 只在需要领取空投时设置代理
        if [[ "$USE_PROXY_FOR_AIRDROP" == "true" ]] && [[ -n "$AIRDROP_PROXY" ]]; then
            setup_proxy "$AIRDROP_PROXY"
        fi
        
        local attempt=0
        
        while true; do
            attempt=$((attempt + 1))
            
            # 每次重试都会使用代理，代理服务会自动切换IP
            if [[ "$USE_PROXY_FOR_AIRDROP" == "true" ]] && [[ -n "$AIRDROP_PROXY" ]]; then
                print_step "尝试为回调账户申请空投 (第 $attempt 次，使用代理，代理将自动切换IP)..."
            else
                print_step "尝试为回调账户申请空投 (第 $attempt 次，不使用代理)..."
            fi
            
            if solana airdrop 2 "$CALLBACK_PUBKEY" -u devnet 2>/dev/null; then
                print_success "空投请求已提交，等待到账..."
                # 领取成功后立即恢复代理，后续操作不使用代理
                restore_proxy
                sleep 5
                
                # 验证余额是否到账
                CALLBACK_BALANCE=$(solana balance "$CALLBACK_PUBKEY" -u devnet 2>/dev/null | awk '{print $1}')
                if (( $(echo "$CALLBACK_BALANCE >= 2" | bc -l) )); then
                    print_success "回调账户已获得注资，当前余额: $CALLBACK_BALANCE SOL"
                    break
                else
                    print_info "等待余额到账，当前余额: $CALLBACK_BALANCE SOL，继续重试..."
                fi
            else
                print_warning "空投失败，10秒后重试（代理将自动切换IP）..."
                sleep 10
            fi
        done
        
        # 确保恢复原始代理设置（双重保险）
        restore_proxy
    fi
    
    print_success "所有账户资金准备完成！"
}

# Generate node offset
generate_node_offset() {
    # Generate a random 10-digit number
    NODE_OFFSET=$(shuf -i 1000000000-9999999999 -n 1)
    print_info "Generated node offset: $NODE_OFFSET"
    save_node_offset
}

# Initialize node accounts
initialize_node_accounts() {
    print_section "Initializing Node Accounts On-Chain"
    
    print_info "Node offset: $NODE_OFFSET"
    print_info "IP address: $PUBLIC_IP"
    print_info "Initializing accounts (this may take a moment)..."
    
    if ! arcium init-arx-accs \
        --keypair-path "$NODE_KEYPAIR" \
        --callback-keypair-path "$CALLBACK_KEYPAIR" \
        --peer-keypair-path "$IDENTITY_KEYPAIR" \
        --node-offset "$NODE_OFFSET" \
        --ip-address "$PUBLIC_IP" \
        --rpc-url "$RPC_URL"; then
        print_error "Node initialization failed"
        print_warning "This may be due to:"
        print_warning "  - Node offset already in use (try running script again)"
        print_warning "  - Insufficient SOL for transaction fees"
        print_warning "  - RPC endpoint issues"
        print_warning "  - Network connectivity problems"
        echo
        print_info "Manual recovery commands:"
        echo -e "  ${YELLOW}cd $WORKSPACE_DIR${NC}"
        echo -e "  ${YELLOW}arcium init-arx-accs --keypair-path $NODE_KEYPAIR --callback-keypair-path $CALLBACK_KEYPAIR --peer-keypair-path $IDENTITY_KEYPAIR --node-offset $NODE_OFFSET --ip-address $PUBLIC_IP --rpc-url $RPC_URL${NC}"
        echo
        print_warning "Saving progress for manual continuation..."
        save_progress "init_failed"
        exit 1
    fi
    
    print_success "Node accounts initialized on-chain"
}

# Generate cluster offset
generate_cluster_offset() {
    # Generate a random 10-digit number
    CLUSTER_OFFSET=$(shuf -i 1000000000-9999999999 -n 1)
    print_info "Generated cluster offset: $CLUSTER_OFFSET"
    save_cluster_offset
}

# Initialize cluster
initialize_cluster() {
    print_section "Initializing Cluster"
    
    print_info "Cluster offset: $CLUSTER_OFFSET"
    print_info "Initializing cluster (this may take a moment)..."
    
    if ! arcium init-cluster \
        --keypair-path "$NODE_KEYPAIR" \
        --offset "$CLUSTER_OFFSET" \
        --max-nodes 10 \
        --rpc-url "$RPC_URL"; then
        print_error "Cluster initialization failed"
        print_warning "This may be due to:"
        print_warning "  - Cluster offset already in use (try running script again)"
        print_warning "  - Insufficient SOL for transaction fees"
        print_warning "  - RPC endpoint issues"
        print_warning "  - Network connectivity problems"
        echo
        print_info "Manual recovery commands:"
        echo -e "  ${YELLOW}cd $WORKSPACE_DIR${NC}"
        echo -e "  ${YELLOW}arcium init-cluster --keypair-path $NODE_KEYPAIR --offset $CLUSTER_OFFSET --max-nodes 10 --rpc-url $RPC_URL${NC}"
        echo
        print_warning "Saving progress for manual continuation..."
        save_progress "cluster_init_failed"
        exit 1
    fi
    
    print_success "Cluster initialized successfully"
}

# Propose join cluster
propose_join_cluster() {
    print_section "Proposing to Join Cluster"
    
    if [ -z "$NODE_OFFSET" ]; then
        print_error "Node offset is not set"
        exit 1
    fi
    
    if [ -z "$CLUSTER_OFFSET" ]; then
        print_error "Cluster offset is not set"
        exit 1
    fi
    
    print_info "Node offset: $NODE_OFFSET"
    print_info "Cluster offset: $CLUSTER_OFFSET"
    print_info "Creating proposal to join cluster (this may take a moment)..."
    
    if ! arcium propose-join-cluster \
        --keypair-path "$NODE_KEYPAIR" \
        --node-offset "$NODE_OFFSET" \
        --cluster-offset "$CLUSTER_OFFSET" \
        --rpc-url "$RPC_URL"; then
        print_error "Failed to create proposal to join cluster"
        print_warning "This may be due to:"
        print_warning "  - Node not initialized"
        print_warning "  - Cluster not initialized"
        print_warning "  - Insufficient SOL for transaction fees"
        print_warning "  - RPC endpoint issues"
        echo
        print_info "Manual recovery commands:"
        echo -e "  ${YELLOW}cd $WORKSPACE_DIR${NC}"
        echo -e "  ${YELLOW}arcium propose-join-cluster --keypair-path $NODE_KEYPAIR --node-offset $NODE_OFFSET --cluster-offset $CLUSTER_OFFSET --rpc-url $RPC_URL${NC}"
        echo
        print_warning "Saving progress for manual continuation..."
        save_progress "propose_failed"
        exit 1
    fi
    
    print_success "Proposal to join cluster created successfully"
}

# Join cluster
join_cluster() {
    print_section "Joining Cluster"
    
    if [ -z "$NODE_OFFSET" ]; then
        print_error "Node offset is not set"
        exit 1
    fi
    
    if [ -z "$CLUSTER_OFFSET" ]; then
        print_error "Cluster offset is not set"
        exit 1
    fi
    
    print_info "Node offset: $NODE_OFFSET"
    print_info "Cluster offset: $CLUSTER_OFFSET"
    print_info "Joining cluster (this may take a moment)..."
    
    if ! arcium join-cluster true\
        --keypair-path "$NODE_KEYPAIR" \
        --node-offset "$NODE_OFFSET" \
        --cluster-offset "$CLUSTER_OFFSET" \
        --rpc-url "$RPC_URL"; then
        print_error "Failed to join cluster"
        print_warning "This may be due to:"
        print_warning "  - Proposal not created"
        print_warning "  - Insufficient SOL for transaction fees"
        print_warning "  - RPC endpoint issues"
        echo
        print_info "Manual recovery commands:"
        echo -e "  ${YELLOW}cd $WORKSPACE_DIR${NC}"
        echo -e "  ${YELLOW}arcium join-cluster --keypair-path $NODE_KEYPAIR --node-offset $NODE_OFFSET --cluster-offset $CLUSTER_OFFSET --rpc-url $RPC_URL${NC}"
        echo
        print_warning "Saving progress for manual continuation..."
        save_progress "join_failed"
        exit 1
    fi
    
    print_success "Successfully joined cluster"
}

# Verify node in cluster
verify_node_in_cluster() {
    print_section "Verifying Node in Cluster"
    
    if [ -z "$NODE_OFFSET" ]; then
        print_error "Node offset is not set"
        exit 1
    fi
    
    print_info "Checking node information..."
    print_info "Node offset: $NODE_OFFSET"
    
    if arcium arx-info "$NODE_OFFSET" --rpc-url "$RPC_URL"; then
        print_success "✅ Node is verified in cluster"
    else
        print_warning "⚠️  Could not verify node in cluster"
        print_info "This may be normal if the node hasn't fully synced yet"
    fi
}

# Create node configuration
create_node_config() {
    print_section "Creating Node Configuration"
    
    if [ -f "$NODE_CONFIG" ]; then
        print_warning "Node config already exists: $NODE_CONFIG"
        print_info "Backing up existing config..."
        cp "$NODE_CONFIG" "$NODE_CONFIG.backup.$(date +%s)"
    fi
    
    print_info "Creating node-config.toml..."
    
    # Generate WSS URL from RPC URL
    WSS_URL=$(echo "$RPC_URL" | sed 's/http/ws/g' | sed 's/https/wss/g')
    
    cat > "$NODE_CONFIG" <<EOF
[node]
offset = $NODE_OFFSET
hardware_claim = 0
starting_epoch = 0
ending_epoch = 9223372036854775807

[network]
address = "0.0.0.0"

[solana]
endpoint_rpc = "$RPC_URL"
endpoint_wss = "$WSS_URL"
cluster = "Devnet"
commitment.commitment = "confirmed"
EOF
    
    print_success "Node configuration created"
}

# Deploy node with Docker
deploy_node() {
    print_section "Deploying ARX Node"
    
    # Create log directory
    print_info "Creating log directory..."
    mkdir -p "$WORKSPACE_DIR/arx-node-logs"
    touch "$WORKSPACE_DIR/arx-node-logs/arx.log"
    print_success "Log directory created"
    
    # Check if container already exists
    if node_container_exists; then
        if is_node_running; then
            print_warning "Node container is already running"
            print_info "Stopping existing container..."
            docker stop "$DOCKER_CONTAINER_NAME"
        fi
        
        print_info "Removing existing container..."
        docker rm "$DOCKER_CONTAINER_NAME"
    fi
    
    print_info "Pulling latest arcium/arx-node image..."
    if ! docker pull arcium/arx-node:latest; then
        print_error "Failed to pull Docker image"
        print_warning "This may be due to network issues or Docker problems"
        print_info "Manual recovery commands:"
        echo -e "  ${YELLOW}docker pull arcium/arx-node:latest${NC}"
        echo -e "  ${YELLOW}docker run -d --name $DOCKER_CONTAINER_NAME -e NODE_IDENTITY_FILE=/usr/arx-node/node-keys/node_identity.pem -e NODE_KEYPAIR_FILE=/usr/arx-node/node-keys/node_keypair.json -e OPERATOR_KEYPAIR_FILE=/usr/arx-node/node-keys/operator_keypair.json -e CALLBACK_AUTHORITY_KEYPAIR_FILE=/usr/arx-node/node-keys/callback_authority_keypair.json -e NODE_CONFIG_PATH=/usr/arx-node/arx/node_config.toml -v $NODE_CONFIG:/usr/arx-node/arx/node_config.toml -v $NODE_KEYPAIR:/usr/arx-node/node-keys/node_keypair.json:ro -v $NODE_KEYPAIR:/usr/arx-node/node-keys/operator_keypair.json:ro -v $CALLBACK_KEYPAIR:/usr/arx-node/node-keys/callback_authority_keypair.json:ro -v $IDENTITY_KEYPAIR:/usr/arx-node/node-keys/node_identity.pem:ro -v $WORKSPACE_DIR/arx-node-logs:/usr/arx-node/logs -p 8080:8080 arcium/arx-node:latest${NC}"
        echo
        print_warning "Saving progress for manual continuation..."
        save_progress "deploy_failed"
        exit 1
    fi
    
    print_info "Starting node container..."
    if ! docker run -d \
        --name "$DOCKER_CONTAINER_NAME" \
        -e NODE_IDENTITY_FILE=/usr/arx-node/node-keys/node_identity.pem \
        -e NODE_KEYPAIR_FILE=/usr/arx-node/node-keys/node_keypair.json \
        -e OPERATOR_KEYPAIR_FILE=/usr/arx-node/node-keys/operator_keypair.json \
        -e CALLBACK_AUTHORITY_KEYPAIR_FILE=/usr/arx-node/node-keys/callback_authority_keypair.json \
        -e NODE_CONFIG_PATH=/usr/arx-node/arx/node_config.toml \
        -v "$NODE_CONFIG:/usr/arx-node/arx/node_config.toml" \
        -v "$NODE_KEYPAIR:/usr/arx-node/node-keys/node_keypair.json:ro" \
        -v "$NODE_KEYPAIR:/usr/arx-node/node-keys/operator_keypair.json:ro" \
        -v "$CALLBACK_KEYPAIR:/usr/arx-node/node-keys/callback_authority_keypair.json:ro" \
        -v "$IDENTITY_KEYPAIR:/usr/arx-node/node-keys/node_identity.pem:ro" \
        -v "$WORKSPACE_DIR/arx-node-logs:/usr/arx-node/logs" \
        -p 8080:8080 \
        arcium/arx-node:latest; then
        print_error "Failed to start node container"
        print_info "Check Docker logs and try manual recovery:"
        echo -e "  ${YELLOW}docker logs $DOCKER_CONTAINER_NAME${NC}"
        echo -e "  ${YELLOW}docker run -d --name $DOCKER_CONTAINER_NAME -e NODE_IDENTITY_FILE=/usr/arx-node/node-keys/node_identity.pem -e NODE_KEYPAIR_FILE=/usr/arx-node/node-keys/node_keypair.json -e OPERATOR_KEYPAIR_FILE=/usr/arx-node/node-keys/operator_keypair.json -e CALLBACK_AUTHORITY_KEYPAIR_FILE=/usr/arx-node/node-keys/callback_authority_keypair.json -e NODE_CONFIG_PATH=/usr/arx-node/arx/node_config.toml -v $NODE_CONFIG:/usr/arx-node/arx/node_config.toml -v $NODE_KEYPAIR:/usr/arx-node/node-keys/node_keypair.json:ro -v $NODE_KEYPAIR:/usr/arx-node/node-keys/operator_keypair.json:ro -v $CALLBACK_KEYPAIR:/usr/arx-node/node-keys/callback_authority_keypair.json:ro -v $IDENTITY_KEYPAIR:/usr/arx-node/node-keys/node_identity.pem:ro -v $WORKSPACE_DIR/arx-node-logs:/usr/arx-node/logs -p 8080:8080 arcium/arx-node:latest${NC}"
        echo
        print_warning "Saving progress for manual continuation..."
        save_progress "deploy_failed"
        exit 1
    fi
    
    if is_node_running; then
        print_success "Node deployed and running"
    else
        print_error "Node failed to start"
        print_info "Check logs with: docker logs $DOCKER_CONTAINER_NAME"
        print_warning "Saving progress for manual continuation..."
        save_progress "deploy_failed"
        exit 1
    fi
}

# Verify node operation
verify_node() {
    print_section "Verifying Node Operation"
    
    print_info "Waiting for node to initialize..."
    sleep 5
    
    if is_node_running; then
        print_success "✓ Node container is running"
        
        print_info "Checking node logs..."
        docker logs --tail 20 "$DOCKER_CONTAINER_NAME"
        
        NODE_PUBKEY=$(solana address --keypair-path "$NODE_KEYPAIR")
        
        print_info "\nNode Information:"
        print_info "  - Container: $DOCKER_CONTAINER_NAME"
        print_info "  - Public Key: $NODE_PUBKEY"
        print_info "  - Node Offset: $NODE_OFFSET"
        print_info "  - Public IP: $PUBLIC_IP"
        print_info "  - Port: 8080"
        
        print_success "\n✓ Node setup complete!"
    else
        print_error "Node is not running"
        print_info "Check logs with: docker logs $DOCKER_CONTAINER_NAME"
        exit 1
    fi
}

# Print summary
print_summary() {
    print_section "Installation Complete!"
    
    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════════════════════════════════════════════════╗"
    echo "║                                                                                      ║"
    echo "║                        🎉 SETUP COMPLETED SUCCESSFULLY! 🎉                          ║"
    echo "║                                                                                      ║"
    echo "║    Your Arcium testnet node is now running and ready to participate!                ║"
    echo "║                                                                                      ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    echo -e "\n${CYAN}🔧 Useful Commands:${NC}"
    echo -e "  ${YELLOW}📋 View logs:${NC}        docker logs -f $DOCKER_CONTAINER_NAME"
    echo -e "  ${YELLOW}⏹️  Stop node:${NC}        docker stop $DOCKER_CONTAINER_NAME"
    echo -e "  ${YELLOW}▶️  Start node:${NC}       docker start $DOCKER_CONTAINER_NAME"
    echo -e "  ${YELLOW}🔄 Restart node:${NC}      docker restart $DOCKER_CONTAINER_NAME"
    echo -e "  ${YELLOW}📊 Node status:${NC}      docker ps | grep $DOCKER_CONTAINER_NAME"
    
    # Load cluster offset if not already loaded
    if [ -z "$CLUSTER_OFFSET" ]; then
        load_cluster_offset 2>/dev/null || true
    fi
    
    echo -e "\n${CYAN}📋 Node Details:${NC}"
    echo -e "  ${YELLOW}📁 Workspace:${NC}        $WORKSPACE_DIR"
    echo -e "  ${YELLOW}🔑 Node Pubkey:${NC}      $(solana address --keypair-path "$NODE_KEYPAIR")"
    echo -e "  ${YELLOW}🔢 Node Offset:${NC}      $NODE_OFFSET"
    if [ -n "$CLUSTER_OFFSET" ]; then
        echo -e "  ${YELLOW}🔢 Cluster Offset:${NC}  $CLUSTER_OFFSET"
    fi
    echo -e "  ${YELLOW}🌐 Public IP:${NC}        $PUBLIC_IP"
    echo -e "  ${YELLOW}🔗 RPC Endpoint:${NC}     $RPC_URL"
    
    echo -e "\n${CYAN}🚀 Next Steps:${NC}"
    echo -e "  ${YELLOW}1.${NC} Monitor your node logs to ensure it's running correctly"
    echo -e "  ${YELLOW}2.${NC} Join or create a cluster to participate in testnet"
    echo -e "  ${YELLOW}3.${NC} Join Arcium Discord for updates: ${BLUE}https://discord.gg/arcium${NC}"
    
    echo -e "\n${GREEN}🙏 Thank you for running an Arcium testnet node!${NC}\n"
}

################################################################################
# Main Execution
################################################################################

# Handle command line arguments
handle_arguments() {
    case "${1:-help}" in
        "install")
            main_install
            ;;
        "start")
            start_node
            ;;
        "stop")
            stop_node
            ;;
        "restart")
            restart_node
            ;;
        "status")
            show_node_status
            ;;
        "info")
            show_node_info
            ;;
        "active")
            check_node_active
            ;;
        "logs")
            show_node_logs
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            print_error "Unknown command: $1"
            echo
            show_help
            exit 1
            ;;
    esac
}

# Main installation function
main_install() {
    print_header
    
    # Detect OS
    detect_os
    
    # Check system requirements
    check_system_requirements
    
    # Backup, delete, and rebuild directories with key restoration
    backup_and_rebuild_directories
    
    # Check if we should resume from previous progress
    if [ -f "$PROGRESS_FILE" ]; then
        local last_step=$(load_progress)
        if [ "$last_step" != "start" ]; then
            print_info "Previous installation progress detected"
            print_info "Do you want to resume from where you left off? (Y/n)"
            read -r response
            if [[ "$response" =~ ^[Nn]$ ]]; then
                clear_progress
                clear_rpc_config
                print_info "Starting fresh installation"
            else
                resume_from_progress
                print_summary
                return 0
            fi
        fi
    fi
    
    # Select RPC endpoint
    select_rpc
    
    # Load saved offsets if they exist
    load_node_offset 2>/dev/null || true
    load_cluster_offset 2>/dev/null || true
    
    # Install prerequisites
    echo -e "\n${CYAN}📦 Installing Prerequisites...${NC}\n"
    show_progress 1 4 "Installing Rust"
    install_rust
    show_progress 2 4 "Installing Solana CLI"
    install_solana
    show_progress 3 4 "Installing Docker"
    install_docker
    show_progress 4 4 "Installing Arcium CLI"
    install_arcium
    
    # Check for bc calculator
    if ! command_exists bc; then
        print_section "Installing bc calculator"
        if [[ "$OS" == "linux" ]]; then
            sudo apt-get update && sudo apt-get install -y bc
        elif [[ "$OS" == "macos" ]]; then
            if command_exists brew; then
                brew install bc
            else
                print_error "Please install bc calculator manually: brew install bc"
                exit 1
            fi
        fi
        print_success "bc calculator installed"
    else
        print_success "bc calculator is already installed"
    fi
    
    # Setup workspace
    echo -e "\n${CYAN}🏗️  Setting Up Node Environment...${NC}\n"
    show_progress 1 9 "Setting up workspace"
    setup_workspace
    
    show_progress 2 9 "Detecting public IP"
    get_public_ip
    
    show_progress 3 9 "Generating keypairs"
    generate_keypairs
    
    # Generate offsets early so they're available for manual commands if funding fails
    if [ -z "$NODE_OFFSET" ]; then
        generate_node_offset
    fi
    if [ -z "$CLUSTER_OFFSET" ]; then
        generate_cluster_offset
    fi
    
    show_progress 4 9 "Funding accounts"
    fund_accounts
    save_progress "funding_completed"
    
    show_progress 5 9 "Initializing node accounts"
    initialize_node_accounts
    save_progress "init_completed"
    
    show_progress 6 9 "Initializing cluster"
    initialize_cluster
    save_progress "cluster_init_completed"
    
    show_progress 7 9 "Proposing to join cluster"
    propose_join_cluster
    save_progress "propose_completed"
    
    show_progress 8 9 "Joining cluster"
    join_cluster
    save_progress "join_completed"
    
    show_progress 9 9 "Verifying node in cluster"
    verify_node_in_cluster
    save_progress "cluster_verify_completed"
    
    # Create configuration
    echo -e "\n${CYAN}⚙️  Creating Node Configuration...${NC}\n"
    create_node_config
    save_progress "config_completed"
    
    # Deploy node
    echo -e "\n${CYAN}🚀 Deploying Node...${NC}\n"
    deploy_node
    save_progress "deploy_completed"
    
    # Verify
    echo -e "\n${CYAN}✅ Verifying Installation...${NC}\n"
    verify_node
    
    # Clear progress on successful completion
    clear_progress
    
    # Print summary
    print_summary
}

# Main function
main() {
    handle_arguments "$@"
}

# Run main function
main "$@"

