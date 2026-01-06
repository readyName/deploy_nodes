#!/bin/bash

# 柔和色彩设置
GREEN='\033[1;32m'      # 柔和绿色
BLUE='\033[1;36m'       # 柔和蓝色
RED='\033[1;31m'        # 柔和红色
YELLOW='\033[1;33m'     # 柔和黄色
NC='\033[0m'            # 无颜色

# 日志文件设置
LOG_FILE="$HOME/nexus.log"
MAX_LOG_SIZE=10485760 # 10MB，日志大小限制

# 检测操作系统
OS=$(uname -s)
case "$OS" in
  Darwin) OS_TYPE="macOS" ;;
  Linux)
    if [[ -f /etc/os-release ]]; then
      . /etc/os-release
      if [[ "$ID" == "ubuntu" ]]; then
        OS_TYPE="Ubuntu"
      else
        OS_TYPE="Linux"
      fi
    else
      OS_TYPE="Linux"
    fi
    ;;
  *) echo -e "${RED}不支持的操作系统: $OS。本脚本仅支持 macOS 和 Ubuntu。${NC}" ; exit 1 ;;
esac

# 检测 shell 并设置配置文件
if [[ -n "$ZSH_VERSION" ]]; then
  SHELL_TYPE="zsh"
  CONFIG_FILE="$HOME/.zshrc"
elif [[ -n "$BASH_VERSION" ]]; then
  SHELL_TYPE="bash"
  CONFIG_FILE="$HOME/.bashrc"
else
  echo -e "${RED}不支持的 shell。本脚本仅支持 bash 和 zsh。${NC}"
  exit 1
fi

# 打印标题
print_header() {
  echo -e "${BLUE}=====================================${NC}"
  echo -e "${BLUE}$1${NC}"
  echo -e "${BLUE}=====================================${NC}"
}

# 检查命令是否存在
check_command() {
  if command -v "$1" &> /dev/null; then
    echo -e "${GREEN}$1 已安装，跳过安装步骤。${NC}"
    return 0
  else
    echo -e "${RED}$1 未安装，开始安装...${NC}"
    return 1
  fi
}

# 配置 shell 环境变量，避免重复写入
configure_shell() {
  local env_path="$1"
  local env_var="export PATH=$env_path:\$PATH"
  if [[ -f "$CONFIG_FILE" ]] && grep -Fx "$env_var" "$CONFIG_FILE" > /dev/null; then
    echo -e "${GREEN}环境变量已在 $CONFIG_FILE 中配置。${NC}"
  else
    echo -e "${BLUE}正在将环境变量添加到 $CONFIG_FILE...${NC}"
    echo "$env_var" >> "$CONFIG_FILE"
    echo -e "${GREEN}环境变量已添加到 $CONFIG_FILE。${NC}"
    # 应用当前会话的更改
    source "$CONFIG_FILE" 2>/dev/null || echo -e "${RED}无法加载 $CONFIG_FILE，请手动运行 'source $CONFIG_FILE'。${NC}"
  fi
}

# 日志轮转
rotate_log() {
  if [[ -f "$LOG_FILE" ]]; then
    if [[ "$OS_TYPE" == "macOS" ]]; then
      FILE_SIZE=$(stat -f %z "$LOG_FILE" 2>/dev/null)
    else
      FILE_SIZE=$(stat -c %s "$LOG_FILE" 2>/dev/null)
    fi
    if [[ $FILE_SIZE -ge $MAX_LOG_SIZE ]]; then
      mv "$LOG_FILE" "${LOG_FILE}.$(date +%F_%H-%M-%S).bak"
      echo -e "${YELLOW}日志文件已轮转，新日志将写入 $LOG_FILE${NC}"
    fi
  fi
}

# 安装 Homebrew（macOS 和非 Ubuntu Linux）
install_homebrew() {
  print_header "检查 Homebrew 安装"
  if check_command brew; then
    return
  fi
  echo -e "${BLUE}在 $OS_TYPE 上安装 Homebrew...${NC}"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
    echo -e "${RED}安装 Homebrew 失败，请检查网络连接或权限。${NC}"
    exit 1
  }
  if [[ "$OS_TYPE" == "macOS" ]]; then
    configure_shell "/opt/homebrew/bin"
  else
    configure_shell "$HOME/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/bin"
    if ! check_command gcc; then
      echo -e "${BLUE}在 Linux 上安装 gcc（Homebrew 依赖）...${NC}"
      if command -v yum &> /dev/null; then
        sudo yum groupinstall 'Development Tools' || {
          echo -e "${RED}安装 gcc 失败，请手动安装 Development Tools。${NC}"
          exit 1
        }
      else
        echo -e "${RED}不支持的包管理器，请手动安装 gcc。${NC}"
        exit 1
      fi
    fi
  fi
}

# 安装基础依赖（仅 Ubuntu）
install_dependencies() {
  if [[ "$OS_TYPE" == "Ubuntu" ]]; then
    print_header "安装基础依赖工具"
    echo -e "${BLUE}更新 apt 包索引并安装必要工具...${NC}"
    sudo apt-get update -y
    sudo apt-get install -y curl jq screen build-essential || {
      echo -e "${RED}安装依赖工具失败，请检查网络连接或权限。${NC}"
      exit 1
    }
  fi
}

# 安装 CMake
install_cmake() {
  print_header "检查 CMake 安装"
  if check_command cmake; then
    return
  fi
  echo -e "${BLUE}正在安装 CMake...${NC}"
  if [[ "$OS_TYPE" == "Ubuntu" ]]; then
    sudo apt-get install -y cmake || {
      echo -e "${RED}安装 CMake 失败，请检查网络连接或权限。${NC}"
      exit 1
    }
  else
    brew install cmake || {
      echo -e "${RED}安装 CMake 失败，请检查 Homebrew 安装。${NC}"
      exit 1
    }
  fi
}

# 安装 Protobuf
install_protobuf() {
  print_header "检查 Protobuf 安装"
  if check_command protoc; then
    return
  fi
  echo -e "${BLUE}正在安装 Protobuf...${NC}"
  if [[ "$OS_TYPE" == "Ubuntu" ]]; then
    sudo apt-get install -y protobuf-compiler || {
      echo -e "${RED}安装 Protobuf 失败，请检查网络连接或权限。${NC}"
      exit 1
    }
  else
    brew install protobuf || {
      echo -e "${RED}安装 Protobuf 失败，请检查 Homebrew 安装。${NC}"
      exit 1
    }
  fi
}

# 安装 Rust
install_rust() {
  print_header "检查 Rust 安装"
  if check_command rustc; then
    return
  fi
  echo -e "${BLUE}正在安装 Rust...${NC}"
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y || {
    echo -e "${RED}安装 Rust 失败，请检查网络连接。${NC}"
    exit 1
  }
  source "$HOME/.cargo/env" 2>/dev/null || echo -e "${RED}无法加载 Rust 环境，请手动运行 'source ~/.cargo/env'。${NC}"
  configure_shell "$HOME/.cargo/bin"
}

# 配置 Rust RISC-V 目标
configure_rust_target() {
  print_header "检查 Rust RISC-V 目标"
  if rustup target list --installed | grep -q "riscv32i-unknown-none-elf"; then
    echo -e "${GREEN}RISC-V 目标 (riscv32i-unknown-none-elf) 已安装，跳过。${NC}"
    return
  fi
  echo -e "${BLUE}为 Rust 添加 RISC-V 目标...${NC}"
  rustup target add riscv32i-unknown-none-elf || {
    echo -e "${RED}添加 RISC-V 目标失败，请检查 Rust 安装。${NC}"
    exit 1
  }
}

# 日志函数
log() {
  echo -e "[$(date '+%Y-%m-%d %H:%M:%S %Z')] $1" | tee -a "$LOG_FILE"
  rotate_log
}

# 退出时的清理函数
cleanup_exit() {
  log "${YELLOW}收到退出信号，正在清理 Nexus 节点进程...${NC}"
  
  if [[ "$OS_TYPE" == "macOS" ]]; then
    # macOS: 先获取窗口信息，再终止进程，最后关闭窗口
    log "${BLUE}正在获取 Nexus 相关窗口信息...${NC}"
    
    # 获取包含nexus的窗口ID
    nexus_window_id=$(osascript -e 'tell app "Terminal" to id of first window whose name contains "node-id"' 2>/dev/null || echo "")
    if [[ -n "$nexus_window_id" ]]; then
      log "${BLUE}发现 Nexus 窗口ID: $nexus_window_id，准备关闭...${NC}"
    else
      log "${YELLOW}未找到 Nexus 窗口，第一次启动，跳过关闭操作${NC}"
    fi
    
    # 现在终止进程
    log "${BLUE}正在终止 Nexus 节点进程...${NC}"
    
    # 查找并终止 nexus-network 和 nexus-cli 进程
    local pids=$(pgrep -f "nexus-cli\|nexus-network" | tr '\n' ' ')
    if [[ -n "$pids" ]]; then
      log "${BLUE}发现进程: $pids，正在终止...${NC}"
      for pid in $pids; do
        kill -TERM "$pid" 2>/dev/null || true
        sleep 1
        # 如果进程还在运行，强制终止
        if ps -p "$pid" > /dev/null 2>&1; then
          kill -KILL "$pid" 2>/dev/null || true
        fi
      done
    fi
    
    # 等待进程完全终止
    sleep 2
    
    # 清理 screen 会话（如果存在）
    if screen -list | grep -q "nexus_node"; then
      log "${BLUE}正在终止 nexus_node screen 会话...${NC}"
      screen -S nexus_node -X quit 2>/dev/null || log "${RED}无法终止 screen 会话，请检查权限或会话状态。${NC}"
    fi
  else
    # 非 macOS: 清理 screen 会话
    if screen -list | grep -q "nexus_node"; then
      log "${BLUE}正在终止 nexus_node screen 会话...${NC}"
      screen -S nexus_node -X quit 2>/dev/null || log "${RED}无法终止 screen 会话，请检查权限或会话状态。${NC}"
    fi
  fi
  
  # 查找并终止 nexus-network 和 nexus-cli 进程
  log "${BLUE}正在查找并清理残留的 Nexus 进程...${NC}"
  PIDS=$(ps aux | grep -E "nexus-cli|nexus-network" | grep -v grep | awk '{print $2}' | tr '\n' ' ' | xargs echo -n)
  log "${BLUE}ps 找到的进程: '$PIDS'${NC}"
  
  if [[ -z "$PIDS" ]]; then
    log "${YELLOW}ps 未找到进程，尝试 pgrep...${NC}"
    PIDS=$(pgrep -f "nexus-cli\|nexus-network" | tr '\n' ' ' | xargs echo -n)
    log "${BLUE}pgrep 找到的进程: '$PIDS'${NC}"
  fi
  
  if [[ -n "$PIDS" ]]; then
    for pid in $PIDS; do
      if ps -p "$pid" > /dev/null 2>&1; then
        log "${BLUE}正在终止 Nexus 节点进程 (PID: $pid)...${NC}"
        kill -9 "$pid" 2>/dev/null || log "${RED}无法终止 PID $pid 的进程，请检查进程状态。${NC}"
      fi
    done
  else
    log "${GREEN}未找到残留的 nexus-network 或 nexus-cli 进程。${NC}"
  fi
  
  # 额外清理：查找可能的子进程
  log "${BLUE}检查是否有子进程残留...${NC}"
  local child_pids=$(pgrep -P $(pgrep -f "nexus-cli\|nexus-network" | tr '\n' ' ') 2>/dev/null | tr '\n' ' ')
  if [[ -n "$child_pids" ]]; then
    log "${BLUE}发现子进程: $child_pids，正在清理...${NC}"
    for pid in $child_pids; do
      kill -9 "$pid" 2>/dev/null || true
    done
  fi
  
  # 等待所有进程完全清理
  sleep 5
  
  # 最后才关闭窗口（确保所有进程都已终止）
  if [[ "$OS_TYPE" == "macOS" ]]; then
    log "${BLUE}正在关闭 Nexus 节点终端窗口...${NC}"
    
    if [[ -n "$nexus_window_id" ]]; then
      # 直接关闭找到的nexus窗口
      log "${BLUE}关闭 Nexus 窗口 (ID: $nexus_window_id)...${NC}"
      osascript -e "tell application \"Terminal\" to close window id $nexus_window_id saving no" 2>/dev/null || true
      sleep 2
      log "${BLUE}窗口关闭完成${NC}"
    else
      log "${YELLOW}没有找到 Nexus 窗口，跳过关闭操作${NC}"
    fi
  fi
  
  log "${GREEN}清理完成，脚本退出。${NC}"
  exit 0
}

# 重启时的清理函数
cleanup_restart() {
  # 重启前清理日志
  if [[ -f "$LOG_FILE" ]]; then
    rm -f "$LOG_FILE"
    echo -e "${YELLOW}已清理旧日志文件 $LOG_FILE${NC}"
  fi
  log "${YELLOW}准备重启节点，开始清理流程...${NC}"
  
  if [[ "$OS_TYPE" == "macOS" ]]; then
    # macOS: 先获取窗口信息，再终止进程，最后关闭窗口
    log "${BLUE}正在获取 Nexus 相关窗口信息...${NC}"
    
    # 获取包含nexus的窗口ID
    nexus_window_id=$(osascript -e 'tell app "Terminal" to id of first window whose name contains "node-id"' 2>/dev/null || echo "")
    if [[ -n "$nexus_window_id" ]]; then
      log "${BLUE}发现 Nexus 窗口ID: $nexus_window_id，准备关闭...${NC}"
    else
      log "${YELLOW}未找到 Nexus 窗口，第一次启动，跳过关闭操作${NC}"
    fi
    
    # 现在终止进程
    log "${BLUE}正在终止 Nexus 节点进程...${NC}"
    
    # 查找并终止 nexus-network 和 nexus-cli 进程
    local pids=$(pgrep -f "nexus-cli\|nexus-network" | tr '\n' ' ')
    if [[ -n "$pids" ]]; then
      log "${BLUE}发现进程: $pids，正在终止...${NC}"
      for pid in $pids; do
        kill -TERM "$pid" 2>/dev/null || true
        sleep 1
        # 如果进程还在运行，强制终止
        if ps -p "$pid" > /dev/null 2>&1; then
          kill -KILL "$pid" 2>/dev/null || true
        fi
      done
    fi
    
    # 等待进程完全终止
    sleep 2
    
    # 清理 screen 会话（如果存在）
    if screen -list | grep -q "nexus_node"; then
      log "${BLUE}正在终止 nexus_node screen 会话...${NC}"
      screen -S nexus_node -X quit 2>/dev/null || log "${RED}无法终止 screen 会话，请检查权限或会话状态。${NC}"
    fi
  else
    # 非 macOS: 清理 screen 会话
    if screen -list | grep -q "nexus_node"; then
      log "${BLUE}正在终止 nexus_node screen 会话...${NC}"
      screen -S nexus_node -X quit 2>/dev/null || log "${RED}无法终止 screen 会话，请检查权限或会话状态。${NC}"
    fi
  fi
  
  # 查找并终止 nexus-network 和 nexus-cli 进程
  log "${BLUE}正在查找并清理残留的 Nexus 进程...${NC}"
  PIDS=$(ps aux | grep -E "nexus-cli|nexus-network" | grep -v grep | awk '{print $2}' | tr '\n' ' ' | xargs echo -n)
  log "${BLUE}ps 找到的进程: '$PIDS'${NC}"
  
  if [[ -z "$PIDS" ]]; then
    log "${YELLOW}ps 未找到进程，尝试 pgrep...${NC}"
    PIDS=$(pgrep -f "nexus-cli\|nexus-network" | tr '\n' ' ' | xargs echo -n)
    log "${BLUE}pgrep 找到的进程: '$PIDS'${NC}"
  fi
  
  if [[ -n "$PIDS" ]]; then
    for pid in $PIDS; do
      if ps -p "$pid" > /dev/null 2>&1; then
        log "${BLUE}正在终止 Nexus 节点进程 (PID: $pid)...${NC}"
        kill -9 "$pid" 2>/dev/null || log "${RED}无法终止 PID $pid 的进程，请检查进程状态。${NC}"
      fi
    done
  else
    log "${GREEN}未找到残留的 nexus-network 或 nexus-cli 进程。${NC}"
  fi
  
  # 额外清理：查找可能的子进程
  log "${BLUE}检查是否有子进程残留...${NC}"
  local child_pids=$(pgrep -P $(pgrep -f "nexus-cli\|nexus-network" | tr '\n' ' ') 2>/dev/null | tr '\n' ' ')
  if [[ -n "$child_pids" ]]; then
    log "${BLUE}发现子进程: $child_pids，正在清理...${NC}"
    for pid in $child_pids; do
      kill -9 "$pid" 2>/dev/null || true
    done
  fi
  
  # 等待所有进程完全清理
  sleep 5
  
  # 最后才关闭窗口（确保所有进程都已终止）
  if [[ "$OS_TYPE" == "macOS" ]]; then
    log "${BLUE}正在关闭 Nexus 节点终端窗口...${NC}"
    
    if [[ -n "$nexus_window_id" ]]; then
      # 直接关闭找到的nexus窗口
      log "${BLUE}关闭 Nexus 窗口 (ID: $nexus_window_id)...${NC}"
      osascript -e "tell application \"Terminal\" to close window id $nexus_window_id saving no" 2>/dev/null || true
      sleep 2
      log "${BLUE}窗口关闭完成${NC}"
    else
      log "${YELLOW}没有找到 Nexus 窗口，跳过关闭操作${NC}"
    fi
  fi
  
  log "${GREEN}清理完成，准备重启节点。${NC}"
}

trap 'cleanup_exit' SIGINT SIGTERM SIGHUP

# 安装或更新 Nexus CLI
install_nexus_cli() {
  local attempt=1
  local max_attempts=3
  local success=false
  while [[ $attempt -le $max_attempts ]]; do
    log "${BLUE}正在安装/更新 Nexus CLI（第 $attempt/$max_attempts 次）...${NC}"
    if curl -s https://cli.nexus.xyz/ | sh &>/dev/null; then
      log "${GREEN}Nexus CLI 安装/更新成功！${NC}"
      success=true
      break
    else
      log "${YELLOW}第 $attempt 次安装/更新 Nexus CLI 失败。${NC}"
      ((attempt++))
      sleep 2
    fi
  done
  # 确保配置文件存在，如果没有就生成并写入 PATH 变量
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "export PATH=\"$HOME/.cargo/bin:\$PATH\"" > "$CONFIG_FILE"
    log "${YELLOW}未检测到 $CONFIG_FILE，已自动生成并写入 PATH 变量。${NC}"
  fi
  # 更新CLI后加载环境变量
  source "$CONFIG_FILE" 2>/dev/null && log "${GREEN}已自动加载 $CONFIG_FILE 环境变量。${NC}" || log "${YELLOW}未能自动加载 $CONFIG_FILE，请手动执行 source $CONFIG_FILE。${NC}"
  # 额外加载.zshrc确保环境变量生效
  if [[ -f "$HOME/.zshrc" ]]; then
    source "$HOME/.zshrc" 2>/dev/null && log "${GREEN}已额外加载 ~/.zshrc 环境变量。${NC}" || log "${YELLOW}未能加载 ~/.zshrc，请手动执行 source ~/.zshrc。${NC}"
  fi
  if [[ "$success" == false ]]; then
    log "${RED}Nexus CLI 安装/更新失败 $max_attempts 次，将尝试使用当前版本运行节点。${NC}"
  fi
  
  # 等待一下确保安装完成
  sleep 3
  
  # 验证安装结果
  if command -v nexus-network &>/dev/null; then
    log "${GREEN}nexus-network 版本：$(nexus-network --version 2>/dev/null)${NC}"
  elif command -v nexus-cli &>/dev/null; then
    log "${GREEN}nexus-cli 版本：$(nexus-cli --version 2>/dev/null)${NC}"
  else
    log "${RED}未找到 nexus-network 或 nexus-cli，无法运行节点。${NC}"
    log "${YELLOW}尝试重新安装...${NC}"
    # 再次尝试安装
    if curl -s https://cli.nexus.xyz/ | sh; then
      log "${GREEN}重新安装成功！${NC}"
      sleep 2
      # 重新验证
      if command -v nexus-network &>/dev/null || command -v nexus-cli &>/dev/null; then
        log "${GREEN}验证通过，可以继续运行节点${NC}"
      else
        log "${RED}重新安装后仍然无法找到命令，退出脚本${NC}"
        exit 1
      fi
    else
      log "${RED}重新安装失败，退出脚本${NC}"
      exit 1
    fi
  fi
  
  # 首次安装后生成仓库hash，避免首次运行时等待
  if [[ ! -f "$HOME/.nexus/last_commit" ]]; then
    log "${BLUE}首次安装，正在生成仓库hash记录...${NC}"
    local repo_url="https://github.com/nexus-xyz/nexus-cli.git"
    local current_commit=$(git ls-remote --heads "$repo_url" main 2>/dev/null | cut -f1)
    
    if [[ -n "$current_commit" ]]; then
      mkdir -p "$HOME/.nexus"
      echo "$current_commit" > "$HOME/.nexus/last_commit"
      log "${GREEN}已记录当前仓库版本: ${current_commit:0:8}${NC}"
    else
      log "${YELLOW}无法获取仓库信息，将在后续检测时创建${NC}"
    fi
  fi
}

# 读取或设置 Node ID，添加 5 秒超时
get_node_id() {
  CONFIG_PATH="$HOME/.nexus/config.json"
  if [[ -f "$CONFIG_PATH" ]]; then
    CURRENT_NODE_ID=$(jq -r .node_id "$CONFIG_PATH" 2>/dev/null)
    if [[ -n "$CURRENT_NODE_ID" && "$CURRENT_NODE_ID" != "null" ]]; then
      log "${GREEN}检测到配置文件中的 Node ID：$CURRENT_NODE_ID${NC}"
      # 使用 read -t 5 实现 5 秒超时，默认选择 y
      echo -e "${BLUE}是否使用此 Node ID? (y/n, 默认 y，5 秒后自动继续): ${NC}"
      use_old_id=""
      read -t 5 -r use_old_id
      use_old_id=${use_old_id:-y} # 默认 y
      if [[ "$use_old_id" =~ ^[Nn]$ ]]; then
        read -rp "请输入新的 Node ID: " NODE_ID_TO_USE
        # 验证 Node ID（假设需要非空且只包含字母、数字、连字符）
        if [[ -z "$NODE_ID_TO_USE" || ! "$NODE_ID_TO_USE" =~ ^[a-zA-Z0-9-]+$ ]]; then
          log "${RED}无效的 Node ID，请输入只包含字母、数字或连字符的 ID。${NC}"
          exit 1
        fi
        jq --arg id "$NODE_ID_TO_USE" '.node_id = $id' "$CONFIG_PATH" > "$CONFIG_PATH.tmp" && mv "$CONFIG_PATH.tmp" "$CONFIG_PATH"
        log "${GREEN}已更新 Node ID: $NODE_ID_TO_USE${NC}"
      else
        NODE_ID_TO_USE="$CURRENT_NODE_ID"
      fi
    else
      log "${YELLOW}未检测到有效 Node ID，请输入新的 Node ID。${NC}"
      read -rp "请输入新的 Node ID: " NODE_ID_TO_USE
      if [[ -z "$NODE_ID_TO_USE" || ! "$NODE_ID_TO_USE" =~ ^[a-zA-Z0-9-]+$ ]]; then
        log "${RED}无效的 Node ID，请输入只包含字母、数字或连字符的 ID。${NC}"
        exit 1
      fi
      mkdir -p "$HOME/.nexus"
      echo "{\"node_id\": \"${NODE_ID_TO_USE}\"}" > "$CONFIG_PATH"
      log "${GREEN}已写入 Node ID: $NODE_ID_TO_USE 到 $CONFIG_PATH${NC}"
    fi
  else
    log "${YELLOW}未找到配置文件 $CONFIG_PATH，请输入 Node ID。${NC}"
    read -rp "请输入新的 Node ID: " NODE_ID_TO_USE
    if [[ -z "$NODE_ID_TO_USE" || ! "$NODE_ID_TO_USE" =~ ^[a-zA-Z0-9-]+$ ]]; then
      log "${RED}无效的 Node ID，请输入只包含字母、数字或连字符的 ID。${NC}"
      exit 1
    fi
    mkdir -p "$HOME/.nexus"
    echo "{\"node_id\": \"${NODE_ID_TO_USE}\"}" > "$CONFIG_PATH"
    log "${GREEN}已写入 Node ID: $NODE_ID_TO_USE 到 $CONFIG_PATH${NC}"
  fi
}

# 检测 GitHub 仓库更新
check_github_updates() {
  local repo_url="https://github.com/nexus-xyz/nexus-cli.git"
  log "${BLUE}检查 Nexus CLI 仓库更新...${NC}"
  
  # 获取远程仓库最新提交
  local current_commit=$(git ls-remote --heads "$repo_url" main 2>/dev/null | cut -f1)
  
  if [[ -z "$current_commit" ]]; then
    log "${YELLOW}无法获取远程仓库信息，跳过更新检测${NC}"
    return 1
  fi
  
  if [[ -f "$HOME/.nexus/last_commit" ]]; then
    local last_commit=$(cat "$HOME/.nexus/last_commit")
    if [[ "$current_commit" != "$last_commit" ]]; then
      log "${GREEN}检测到仓库更新！${NC}"
      log "${BLUE}上次提交: ${last_commit:0:8}${NC}"
      log "${BLUE}最新提交: ${current_commit:0:8}${NC}"
      echo "$current_commit" > "$HOME/.nexus/last_commit"
      return 0  # 有更新
    else
      log "${GREEN}仓库无更新，当前版本: ${current_commit:0:8}${NC}"
      return 1  # 无更新
    fi
  else
    log "${BLUE}首次运行，记录当前提交: ${current_commit:0:8}${NC}"
    echo "$current_commit" > "$HOME/.nexus/last_commit"
    return 0  # 首次运行
  fi
}

# 启动节点
start_node() {
  log "${BLUE}正在启动 Nexus 节点 (Node ID: $NODE_ID_TO_USE)...${NC}"
  rotate_log
  
     if [[ "$OS_TYPE" == "macOS" ]]; then
     # macOS: 新开终端窗口启动节点，并设置到指定位置
     log "${BLUE}在 macOS 中打开新终端窗口启动节点...${NC}"
     
     # 获取屏幕尺寸
     screen_info=$(system_profiler SPDisplaysDataType | grep Resolution | head -1 | awk '{print $2, $4}' | tr 'x' ' ')
     if [[ -n "$screen_info" ]]; then
       read -r screen_width screen_height <<< "$screen_info"
     else
       screen_width=1920
       screen_height=1080
     fi
     
           # 计算窗口位置（与 startAll.sh 中 nexus 位置完全一致）
      spacing=20
      upper_height=$(((screen_height/2) - (2*spacing)))
      lower_height=$(((screen_height/2) - (2*spacing)))
      lower_y=$((upper_height + (2*spacing)))
      
      # 设置窗口位置：距离左边界30px
      lower_item_width=$(((screen_width - spacing) / 2))  # 窗口宽度
      nexus_ritual_height=$((lower_height - 30))
      nexus_ritual_y=$((lower_y + 5))
      nexus_x=30  # 距离左边界30px
      
      # 启动节点并设置窗口位置和大小（103x31）
      osascript <<EOF
tell application "Terminal"
  set newWindow to do script "cd ~ && echo \"🚀 正在启动 Nexus 节点...\" && nexus-network start --node-id $NODE_ID_TO_USE && echo \"✅ 节点已启动，按任意键关闭窗口...\" && read -n 1"
  tell front window
    set number of columns to 103
    set number of rows to 31
    set bounds to {$nexus_x, $nexus_ritual_y, $((nexus_x + lower_item_width)), $((nexus_ritual_y + nexus_ritual_height))}
  end tell
end tell
EOF
    
    # 等待一下确保窗口打开
    sleep 3
    
    # 检查是否有新终端窗口打开
    if pgrep -f "nexus-network start" > /dev/null; then
      log "${GREEN}Nexus 节点已在新终端窗口中启动${NC}"
    else
             log "${YELLOW}nexus-network 启动失败，尝试用 nexus-cli 启动...${NC}"
       # 使用相同的窗口位置和大小设置（103x31）
       osascript <<EOF
tell application "Terminal"
  set newWindow to do script "cd ~ && echo \"🚀 正在启动 Nexus 节点...\" && nexus-cli start --node-id $NODE_ID_TO_USE && echo \"✅ 节点已启动，按任意键关闭窗口...\" && read -n 1"
  tell front window
    set number of columns to 103
    set number of rows to 31
    set bounds to {$nexus_x, $nexus_ritual_y, $((nexus_x + lower_item_width)), $((nexus_ritual_y + nexus_ritual_height))}
  end tell
end tell
EOF
      sleep 3
      
      if pgrep -f "nexus-cli start" > /dev/null; then
        log "${GREEN}Nexus 节点已通过 nexus-cli 在新终端窗口中启动${NC}"
      else
        log "${RED}启动失败，将在下次更新检测时重试${NC}"
        return 1
      fi
    fi
  else
    # 非 macOS: 使用 screen 启动（保持原有逻辑）
    log "${BLUE}在 $OS_TYPE 中使用 screen 启动节点...${NC}"
    screen -dmS nexus_node bash -c "nexus-network start --node-id '${NODE_ID_TO_USE}' >> $LOG_FILE 2>&1"
    sleep 2
    if screen -list | grep -q "nexus_node"; then
      log "${GREEN}Nexus 节点已在 screen 会话（nexus_node）中启动，日志输出到 $LOG_FILE${NC}"
    else
      log "${YELLOW}nexus-network 启动失败，尝试用 nexus-cli 启动...${NC}"
      screen -dmS nexus_node bash -c "nexus-cli start --node-id '${NODE_ID_TO_USE}' >> $LOG_FILE 2>&1"
      sleep 2
      if screen -list | grep -q "nexus_node"; then
        log "${GREEN}Nexus 节点已通过 nexus-cli 启动，日志输出到 $LOG_FILE${NC}"
      else
        log "${RED}启动失败，将在下次更新检测时重试${NC}"
        return 1
      fi
    fi
  fi
  
  return 0
}

# 创建桌面快捷方式（参考 install_gensyn.sh）
create_desktop_shortcuts() {
  if [[ "$OS_TYPE" != "macOS" ]]; then
    return 0
  fi
  
  log "${BLUE}正在创建桌面快捷方式...${NC}"
  
  CURRENT_USER=$(whoami)
  PROJECT_DIR="/Users/$CURRENT_USER/rl-swarm"
  DESKTOP_DIR="/Users/$CURRENT_USER/Desktop"
  mkdir -p "$DESKTOP_DIR"
  
  # 检查 rl-swarm 目录是否存在
  HAS_RL_SWARM=false
  if [[ -d "$PROJECT_DIR" ]] && [[ -f "$PROJECT_DIR/nexus.sh" ]]; then
    HAS_RL_SWARM=true
    log "${GREEN}检测到 rl-swarm 目录，将使用 .sh 文件启动${NC}"
  else
    log "${YELLOW}未检测到 rl-swarm 目录，将直接执行命令启动${NC}"
  fi
  
  # 创建 nexus.command
  if [[ "$HAS_RL_SWARM" == true ]]; then
    # 使用 rl-swarm 中的 nexus.sh
    cat > "$DESKTOP_DIR/nexus.command" <<EOF
#!/bin/bash

# 设置错误处理
set -e

# 捕获中断信号
trap 'echo -e "\n\\033[33m⚠️ 脚本被中断，但终端将继续运行...\\033[0m"; exit 0' INT TERM

# 进入项目目录
cd "$PROJECT_DIR" || { echo "❌ 无法进入项目目录"; exit 1; }

# 执行脚本
echo "🚀 正在执行 nexus.sh..."
./nexus.sh

# 脚本执行完成后的提示
echo -e "\\n\\033[32m✅ nexus.sh 执行完成\\033[0m"
echo "按任意键关闭此窗口..."
read -n 1 -s
EOF
  else
    # 直接执行 nexus.sh 的完整逻辑（内嵌脚本内容）
    cat > "$DESKTOP_DIR/nexus.command" <<'NEXUS_DIRECT_EOF'
#!/bin/bash

# 柔和色彩设置
GREEN='\033[1;32m'
BLUE='\033[1;36m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 日志文件设置
LOG_FILE="$HOME/nexus.log"
MAX_LOG_SIZE=10485760

# 检测操作系统
OS=$(uname -s)
case "$OS" in
  Darwin) OS_TYPE="macOS" ;;
  Linux)
    if [[ -f /etc/os-release ]]; then
      . /etc/os-release
      if [[ "$ID" == "ubuntu" ]]; then
        OS_TYPE="Ubuntu"
      else
        OS_TYPE="Linux"
      fi
    else
      OS_TYPE="Linux"
    fi
    ;;
  *) echo -e "${RED}不支持的操作系统: $OS${NC}" ; exit 1 ;;
esac

# 检测 shell 并设置配置文件
if [[ -n "$ZSH_VERSION" ]]; then
  CONFIG_FILE="$HOME/.zshrc"
elif [[ -n "$BASH_VERSION" ]]; then
  CONFIG_FILE="$HOME/.bashrc"
else
  echo -e "${RED}不支持的 shell${NC}"
  exit 1
fi

# 日志函数
log() {
  echo -e "[$(date '+%Y-%m-%d %H:%M:%S %Z')] $1" | tee -a "$LOG_FILE"
}

# 安装或更新 Nexus CLI
install_nexus_cli() {
  local attempt=1
  local max_attempts=3
  while [[ $attempt -le $max_attempts ]]; do
    log "${BLUE}正在安装/更新 Nexus CLI（第 $attempt/$max_attempts 次）...${NC}"
    if curl -s https://cli.nexus.xyz/ | sh &>/dev/null; then
      log "${GREEN}Nexus CLI 安装/更新成功！${NC}"
      break
    else
      log "${YELLOW}第 $attempt 次安装/更新失败${NC}"
      ((attempt++))
      sleep 2
    fi
  done
  
  source "$CONFIG_FILE" 2>/dev/null || true
  if [[ -f "$HOME/.zshrc" ]]; then
    source "$HOME/.zshrc" 2>/dev/null || true
  fi
}

# 读取 Node ID
get_node_id() {
  CONFIG_PATH="$HOME/.nexus/config.json"
  if [[ -f "$CONFIG_PATH" ]]; then
    NODE_ID=$(jq -r .node_id "$CONFIG_PATH" 2>/dev/null)
    if [[ -z "$NODE_ID" || "$NODE_ID" == "null" ]]; then
      echo -e "${RED}未找到 Node ID，请先运行部署脚本配置${NC}"
      read -n 1 -s
      exit 1
    fi
  else
    echo -e "${RED}未找到配置文件，请先运行部署脚本配置${NC}"
    read -n 1 -s
    exit 1
  fi
}

# 启动节点
start_nexus() {
  log "${BLUE}正在启动 Nexus 节点 (Node ID: $NODE_ID)...${NC}"
  
  if [[ "$OS_TYPE" == "macOS" ]]; then
    # macOS: 在新终端窗口启动
    osascript <<EOF
tell application "Terminal"
  do script "cd ~ && nexus-network start --node-id $NODE_ID || nexus-cli start --node-id $NODE_ID"
end tell
EOF
  else
    # Linux: 使用 screen
    screen -dmS nexus_node bash -c "nexus-network start --node-id '$NODE_ID' || nexus-cli start --node-id '$NODE_ID'"
  fi
}

# 主流程
install_nexus_cli
get_node_id
start_nexus

echo -e "\n${GREEN}✅ Nexus 节点已启动${NC}"
echo "按任意键关闭此窗口..."
read -n 1 -s
NEXUS_DIRECT_EOF
  fi
  chmod +x "$DESKTOP_DIR/nexus.command"
  log "${GREEN}已创建 nexus.command${NC}"
  
  # 不再创建 ritual.command（已删除 Ritual 功能）
  
  # 创建 tashi.command（参考 tashi_install.sh）
  cat > "$DESKTOP_DIR/tashi.command" <<'TASHI_EOF'
#!/bin/bash

# Tashi DePIN Worker restart script

# 设置颜色
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"

# 配置
CONTAINER_NAME="tashi-depin-worker"
AUTH_VOLUME="tashi-depin-worker-auth"
AUTH_DIR="/home/worker/auth"
AGENT_PORT=39065
IMAGE_TAG="ghcr.io/tashigg/tashi-depin-worker:0"
PLATFORM_ARG="--platform linux/amd64"
RUST_LOG="info,tashi_depin_worker=debug,tashi_depin_common=debug"

# ============ 设备检测函数 ============
# 获取设备唯一标识
get_device_code() {
	local device_code=""
	
	if [[ "$OSTYPE" == "darwin"* ]]; then
		if command -v system_profiler >/dev/null 2>&1; then
			device_code=$(system_profiler SPHardwareDataType 2>/dev/null | grep "Serial Number" | awk -F': ' '{print $2}' | xargs)
		fi
		if [ -z "$device_code" ] && command -v ioreg >/dev/null 2>&1; then
			device_code=$(ioreg -l | grep IOPlatformSerialNumber 2>/dev/null | awk -F'"' '{print $4}')
		fi
		if [ -z "$device_code" ] && command -v sysctl >/dev/null 2>&1; then
			device_code=$(sysctl -n hw.serialnumber 2>/dev/null)
		fi
	else
		if [ -f /etc/machine-id ]; then
			device_code=$(cat /etc/machine-id 2>/dev/null | xargs)
		fi
		if [ -z "$device_code" ] && [ -f /sys/class/dmi/id/product_uuid ]; then
			device_code=$(cat /sys/class/dmi/id/product_uuid 2>/dev/null | xargs)
		fi
	fi
	
	echo "$device_code"
}

# 检查设备状态
check_device_status() {
	local device_code="$1"
	local server_url="${TASHI_SERVER_URL:-}"
	local api_key="${TASHI_API_KEY:-}"
	
	if [ -z "$server_url" ] || [ -z "$api_key" ]; then
		# 尝试使用外部脚本
		local upload_script=""
		if [ -f "./upload_devices.sh" ] && [ -x "./upload_devices.sh" ]; then
			upload_script="./upload_devices.sh"
		elif [ -f "$HOME/rl-swarm/upload_devices.sh" ] && [ -x "$HOME/rl-swarm/upload_devices.sh" ]; then
			upload_script="$HOME/rl-swarm/upload_devices.sh"
		fi
		
		if [ -n "$upload_script" ]; then
			# 使用外部脚本检查（静默模式）
			if CHECK_ONLY=true "$upload_script" >/dev/null 2>&1; then
				return 0
			else
				local rc=$?
				if [ "$rc" -eq 2 ]; then
					return 2  # 设备被禁用
				else
					return 0  # 网络错误，允许继续
				fi
			fi
		else
			# 未配置，允许继续
			return 0
		fi
	fi
	
	local status
	status=$(curl -s "${server_url}/api/public/device/status?device_code=${device_code}" 2>/dev/null)
	
	if [ "$status" = "1" ]; then
		return 0
	elif [ "$status" = "0" ]; then
		return 2
	else
		return 0  # 网络错误，允许继续
	fi
}

perform_device_check() {
	local upload_script=""
	if [ -f "./upload_devices.sh" ] && [ -x "./upload_devices.sh" ]; then
		upload_script="./upload_devices.sh"
	elif [ -f "$HOME/rl-swarm/upload_devices.sh" ] && [ -x "$HOME/rl-swarm/upload_devices.sh" ]; then
		upload_script="$HOME/rl-swarm/upload_devices.sh"
	fi
	
	if [ -n "$upload_script" ]; then
		if CHECK_ONLY=true "$upload_script" >/dev/null 2>&1; then
			return 0
		else
			local rc=$?
			if [ "$rc" -eq 2 ]; then
				exit 2
			else
				return 0
			fi
		fi
	fi
	
	local device_code=$(get_device_code)
	if [ -z "$device_code" ]; then
		return 0
	fi
	
	if check_device_status "$device_code"; then
		return 0
	else
		local status_rc=$?
		if [ "$status_rc" -eq 2 ]; then
			exit 2
		else
			return 0
		fi
	fi
}

# 切换到脚本所在目录
cd "$(dirname "$0")" || exit 1

# 清屏
clear

perform_device_check >/dev/null 2>&1

if docker stop "$CONTAINER_NAME" >/dev/null 2>&1; then
    docker rm "$CONTAINER_NAME" >/dev/null 2>&1
fi

if docker run -d \
    -p "$AGENT_PORT:$AGENT_PORT" \
    -p 127.0.0.1:9000:9000 \
    --mount type=volume,src="$AUTH_VOLUME",dst="$AUTH_DIR" \
    --name "$CONTAINER_NAME" \
    -e RUST_LOG="$RUST_LOG" \
    --health-cmd='pgrep -f tashi-depin-worker || exit 1' \
    --health-interval=30s \
    --health-timeout=10s \
    --health-retries=3 \
    --restart=unless-stopped \
    --pull=always \
    $PLATFORM_ARG \
    "$IMAGE_TAG" \
    run "$AUTH_DIR" \
    --unstable-update-download-path /tmp/tashi-depin-worker; then
    :
else
    exit 1
fi

docker logs -f "$CONTAINER_NAME"
TASHI_EOF
  chmod +x "$DESKTOP_DIR/tashi.command"
  log "${GREEN}已创建 tashi.command${NC}"
  
  # 创建 startAll.command
  if [[ "$HAS_RL_SWARM" == true ]] && [[ -f "$PROJECT_DIR/startAll.sh" ]]; then
    # 使用 rl-swarm 中的 startAll.sh
    cat > "$DESKTOP_DIR/startAll.command" <<EOF
#!/bin/bash

# 设置错误处理
set -e

# 捕获中断信号
trap 'echo -e "\n\\033[33m⚠️ 脚本被中断，但终端将继续运行...\\033[0m"; exit 0' INT TERM

# 进入项目目录
cd "$PROJECT_DIR" || { echo "❌ 无法进入项目目录"; exit 1; }

# 执行脚本
echo "🚀 正在执行 startAll.sh..."
./startAll.sh

# 脚本执行完成后的提示
echo -e "\\n\\033[32m✅ startAll.sh 执行完成\\033[0m"
echo "按任意键关闭此窗口..."
read -n 1 -s
EOF
  else
    # 创建独立的 startAll 逻辑（基于 startAll.sh，但替换 gensyn 为 Tashi）
    cat > "$DESKTOP_DIR/startAll.command" <<'STARTALL_DIRECT_EOF'
#!/bin/bash

# 1. 获取当前终端的窗口ID并关闭其他终端窗口（排除当前终端）
current_window_id=$(osascript -e 'tell app "Terminal" to id of front window')
echo "当前终端窗口ID: $current_window_id，正在保护此终端不被关闭..."

osascript <<EOF
tell application "Terminal"
    activate
    set windowList to every window
    repeat with theWindow in windowList
        if id of theWindow is not ${current_window_id} then
            try
                close theWindow saving no
            end try
        end if
    end repeat
end tell
EOF
sleep 2

# 获取屏幕尺寸
echo "正在获取屏幕尺寸..."
if command -v system_profiler >/dev/null 2>&1; then
    screen_info=$(system_profiler SPDisplaysDataType | grep Resolution | head -1 | awk '{print $2, $4}' | tr 'x' ' ')
    if [[ -n "$screen_info" ]]; then
        read -r width height <<< "$screen_info"
        x1=0
        y1=0
        x2=$width
        y2=$height
        echo "检测到屏幕尺寸: ${width}x${height}"
    else
        width=1920
        height=1080
        x1=0
        y1=0
        x2=1920
        y2=1080
        echo "使用默认屏幕尺寸: ${width}x${height}"
    fi
else
    width=1920
    height=1080
    x1=0
    y1=0
    x2=1920
    y2=1080
    echo "使用默认屏幕尺寸: ${width}x${height}"
fi

# 窗口排列函数
function arrange_window {
    local title=$1
    local x=$2
    local y=$3
    local w=$4
    local h=$5
    
    local right_x=$((x + w))
    local bottom_y=$((y + h))
    
    echo "排列窗口 '$title': 位置($x, $y), 大小(${w}x${h}), 边界(${right_x}x${bottom_y})"
    
    if osascript -e "tell application \"Terminal\" to set bounds of first window whose name contains \"$title\" to {$x, $y, $right_x, $bottom_y}" 2>/dev/null; then
        echo "✅ 窗口 '$title' 排列成功"
    else
        echo "⚠️ 窗口 '$title' 排列失败，尝试备用方法..."
        local window_id=$(osascript -e "tell application \"Terminal\" to id of first window whose name contains \"$title\"" 2>/dev/null)
        if [[ -n "$window_id" ]]; then
            osascript -e "tell application \"Terminal\" to set bounds of window id $window_id to {$x, $y, $right_x, $bottom_y}" 2>/dev/null
            echo "✅ 窗口 '$title' (ID: $window_id) 排列成功"
        else
            echo "❌ 无法找到窗口 '$title'"
        fi
    fi
}

# 布局参数
spacing=20
upper_height=$((height/2-2*spacing))
lower_height=$((height/2-2*spacing))
lower_y=$((y1+upper_height+2*spacing))

# 上层布局
upper_item_width=$(( (width-spacing)/2 ))

# 下层布局（nexus、Ritual）
lower_item_width=$(( (width-spacing)/2 ))
nexus_ritual_height=$((lower_height-30))
nexus_ritual_y=$((lower_y+5))

# wai宽度缩小1/2
wai_width=$((upper_item_width/2))
wai_height=$upper_height

# 3. 启动Docker（不新建终端窗口）
echo "✅ 正在后台启动Docker..."
open -a Docker --background

# 等待Docker完全启动
echo "⏳ 等待Docker服务就绪..."
until docker info >/dev/null 2>&1; do sleep 1; done
sleep 30

# 4. 启动 Tashi（上层左侧，距离左边界30px，替换原来的 gensyn）
echo "📦 启动 Tashi 节点..."
osascript <<TASHI_SCRIPT
tell application "Terminal"
    do script "cd ~ && docker stop tashi-depin-worker 2>/dev/null; docker rm tashi-depin-worker 2>/dev/null; docker run -d -p 39065:39065 -p 127.0.0.1:9000:9000 --mount type=volume,src=tashi-depin-worker-auth,dst=/home/worker/auth --name tashi-depin-worker -e RUST_LOG='info,tashi_depin_worker=debug,tashi_depin_common=debug' --health-cmd='pgrep -f tashi-depin-worker || exit 1' --health-interval=30s --health-timeout=10s --health-retries=3 --restart=unless-stopped --pull=always --platform linux/amd64 ghcr.io/tashigg/tashi-depin-worker:0 run /home/worker/auth --unstable-update-download-path /tmp/tashi-depin-worker && docker logs -f tashi-depin-worker"
end tell
TASHI_SCRIPT
sleep 1
arrange_window "tashi" $((x1+30)) $y1 $upper_item_width $upper_height

# 5. 启动dria（上层右侧，向右偏移半个身位，宽度缩小1/2，高度不变）
echo "📦 启动 Dria 节点..."
osascript -e 'tell app "Terminal" to do script "cd ~ && dkn-compute-launcher start"'
sleep 1
arrange_window "dkn-compute-launcher" $((x1+upper_item_width+spacing+upper_item_width/2)) $y1 $wai_width $wai_height

# 6. 启动nexus（下层左侧，高度减小30px，向下移动5px）
echo "📦 启动 Nexus 节点..."
NEXUS_CONFIG="$HOME/.nexus/config.json"
if [[ -f "$NEXUS_CONFIG" ]]; then
    NODE_ID=$(jq -r .node_id "$NEXUS_CONFIG" 2>/dev/null)
    if [[ -n "$NODE_ID" && "$NODE_ID" != "null" ]]; then
        osascript -e "tell app \"Terminal\" to do script \"cd ~ && nexus-network start --node-id $NODE_ID || nexus-cli start --node-id $NODE_ID\""
        sleep 1
        arrange_window "nexus" $x1 $nexus_ritual_y $lower_item_width $nexus_ritual_height
    else
        echo "⚠️ 未找到 Nexus Node ID"
    fi
else
    echo "⚠️ 未找到 Nexus 配置文件"
fi

# Ritual 已删除，不再启动

echo "✅ 所有项目已启动完成！"
echo "   - Docker已在后台运行"
echo "   - Tashi 节点（替换 gensyn）"
echo "   - Dria 节点"
echo "   - Nexus 节点"
STARTALL_DIRECT_EOF
  fi
  chmod +x "$DESKTOP_DIR/startAll.command"
  log "${GREEN}已创建 startAll.command${NC}"
  
  # 创建 clean_spotlight.command
  if [[ "$HAS_RL_SWARM" == true ]] && [[ -f "$PROJECT_DIR/clean_spotlight.sh" ]]; then
    # 使用 rl-swarm 中的 clean_spotlight.sh
    cat > "$DESKTOP_DIR/clean_spotlight.command" <<EOF
#!/bin/bash

# 设置错误处理
set -e

# 捕获中断信号
trap 'echo -e "\n\\033[33m⚠️ 脚本被中断，但终端将继续运行...\\033[0m"; exit 0' INT TERM

# 进入项目目录
cd "$PROJECT_DIR" || { echo "❌ 无法进入项目目录"; exit 1; }

# 执行脚本
echo "🚀 正在执行 clean_spotlight.sh..."
./clean_spotlight.sh

# 脚本执行完成后的提示
echo -e "\\n\\033[32m✅ clean_spotlight.sh 执行完成\\033[0m"
echo "按任意键关闭此窗口..."
read -n 1 -s
EOF
  else
    # 创建独立的 clean_spotlight 逻辑
    cat > "$DESKTOP_DIR/clean_spotlight.command" <<'CLEAN_DIRECT_EOF'
#!/bin/bash

# 设置错误处理
set -e

# 捕获中断信号
trap 'echo -e "\n\033[33m⚠️ 脚本被中断，但终端将继续运行...\033[0m"; exit 0' INT TERM

echo "🧹 正在清理 Spotlight 索引..."

# macOS 清理 Spotlight 索引
if [[ "$OSTYPE" == "darwin"* ]]; then
  echo "停止 Spotlight 索引..."
  sudo mdutil -a -i off
  
  echo "删除 Spotlight 索引文件..."
  sudo rm -rf /.Spotlight-V100
  
  echo "重建 Spotlight 索引..."
  sudo mdutil -a -i on
  
  echo "✅ Spotlight 索引清理完成"
else
  echo "⚠️  此脚本仅适用于 macOS"
fi

echo "按任意键关闭此窗口..."
read -n 1 -s
CLEAN_DIRECT_EOF
  fi
  chmod +x "$DESKTOP_DIR/clean_spotlight.command"
  log "${GREEN}已创建 clean_spotlight.command${NC}"
  
  log "${GREEN}所有桌面快捷方式已创建完成！${NC}"
  
  if [[ "$HAS_RL_SWARM" == false ]]; then
    log "${YELLOW}提示：未检测到 rl-swarm 目录，快捷方式使用直接命令启动${NC}"
  fi
}

# Ritual 功能已删除，不再需要配置函数

# 更新 startAll.sh 以包含 Tashi 启动逻辑
update_startall_script() {
  if [[ "$OS_TYPE" != "macOS" ]]; then
    return 0
  fi
  
  CURRENT_USER=$(whoami)
  PROJECT_DIR="/Users/$CURRENT_USER/rl-swarm"
  STARTALL_FILE="$PROJECT_DIR/startAll.sh"
  
  # 检查 rl-swarm 目录和 startAll.sh 是否存在
  if [[ ! -d "$PROJECT_DIR" ]]; then
    log "${YELLOW}未找到 rl-swarm 目录: $PROJECT_DIR${NC}"
    log "${YELLOW}startAll.command 已创建独立版本，不依赖 rl-swarm${NC}"
    return 0
  fi
  
  if [[ ! -f "$STARTALL_FILE" ]]; then
    log "${YELLOW}未找到 startAll.sh 文件: $STARTALL_FILE${NC}"
    log "${YELLOW}startAll.command 已创建独立版本，不依赖 startAll.sh${NC}"
    return 0
  fi
  
  log "${BLUE}正在更新 startAll.sh 以添加 Tashi 启动逻辑...${NC}"
  
  # 检查是否已经包含 Tashi
  if grep -q "tashi\|Tashi\|TASHI" "$STARTALL_FILE"; then
    log "${GREEN}startAll.sh 已包含 Tashi 启动逻辑，跳过更新${NC}"
    return 0
  fi
  
  # 创建备份
  cp "$STARTALL_FILE" "${STARTALL_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
  log "${GREEN}已创建 startAll.sh 备份${NC}"
  
  # 查找 gensyn 相关代码并替换为 Tashi
  # 根据 startAll.sh，gensyn 在 #4 位置（上层左侧，距离左边界30px）
  
  if grep -q "gensyn\|Gensyn\|GENSYN" "$STARTALL_FILE"; then
    log "${BLUE}检测到 gensyn 代码，将替换为 Tashi...${NC}"
    
    # 使用 Python 或 awk 进行更安全的替换（避免 sed 引号问题）
    python3 <<PYTHON_REPLACE_EOF
import re
import sys

file_path = "$STARTALL_FILE"

try:
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # 替换 gensyn.sh 启动命令为 Tashi Docker 命令
    tashi_cmd = 'docker stop tashi-depin-worker 2>/dev/null; docker rm tashi-depin-worker 2>/dev/null; docker run -d -p 39065:39065 -p 127.0.0.1:9000:9000 --mount type=volume,src=tashi-depin-worker-auth,dst=/home/worker/auth --name tashi-depin-worker -e RUST_LOG="info,tashi_depin_worker=debug,tashi_depin_common=debug" --health-cmd="pgrep -f tashi-depin-worker || exit 1" --health-interval=30s --health-timeout=10s --health-retries=3 --restart=unless-stopped --pull=always --platform linux/amd64 ghcr.io/tashigg/tashi-depin-worker:0 run /home/worker/auth --unstable-update-download-path /tmp/tashi-depin-worker && docker logs -f tashi-depin-worker'
    
    # 替换包含 gensyn.sh 的 osascript 命令为 Tashi 命令
    gensyn_pattern = r"osascript -e 'tell app \"Terminal\" to do script \".*gensyn\.sh.*\"'"
    tashi_osascript = "osascript -e 'tell app \"Terminal\" to do script \"cd ~ && " + tashi_cmd.replace('"', '\\"') + "\"'"
    content = re.sub(gensyn_pattern, tashi_osascript, content)
    
    # 也替换简单的 ./gensyn.sh
    content = re.sub(r'\./gensyn\.sh', tashi_cmd, content)
    
    # 替换 arrange_window "gensyn" 为 arrange_window "tashi"
    content = re.sub(r'arrange_window "gensyn"', 'arrange_window "tashi"', content)
    
    # 替换注释
    content = re.sub(r'# 4\.\s*启动gensyn', '# 4. 启动 Tashi（替换原来的 gensyn）', content, flags=re.IGNORECASE)
    
    # 替换 echo 输出
    content = re.sub(r'启动gensyn', '启动 Tashi 节点', content, flags=re.IGNORECASE)
    content = re.sub(r'- gensyn', '- Tashi 节点（替换 gensyn）', content, flags=re.IGNORECASE)
    
    # 删除 Ritual 相关代码
    # 删除 # 7. 启动Ritual 部分（包括后续的 osascript 和 arrange_window）
    content = re.sub(r'# 7\.\s*启动Ritual.*?arrange_window "Ritual".*?\n', '', content, flags=re.DOTALL | re.IGNORECASE)
    # 删除 echo 中的 Ritual
    content = re.sub(r'\s*- Ritual.*?\n', '', content, flags=re.IGNORECASE)
    
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(content)
    
    print("替换完成")
    sys.exit(0)
except Exception as e:
    print(f"替换失败: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_REPLACE_EOF
    
    if [[ $? -eq 0 ]]; then
      log "${GREEN}已替换 gensyn 为 Tashi${NC}"
    else
      log "${YELLOW}Python 替换失败，尝试使用 sed...${NC}"
      # 备用方案：使用 sed（简单替换）
      if [[ "$OS_TYPE" == "macOS" ]]; then
        sed -i '' 's|./gensyn.sh|docker stop tashi-depin-worker 2>/dev/null; docker rm tashi-depin-worker 2>/dev/null; docker run -d -p 39065:39065 -p 127.0.0.1:9000:9000 --mount type=volume,src=tashi-depin-worker-auth,dst=/home/worker/auth --name tashi-depin-worker -e RUST_LOG="info,tashi_depin_worker=debug,tashi_depin_common=debug" --health-cmd="pgrep -f tashi-depin-worker || exit 1" --health-interval=30s --health-timeout=10s --health-retries=3 --restart=unless-stopped --pull=always --platform linux/amd64 ghcr.io/tashigg/tashi-depin-worker:0 run /home/worker/auth --unstable-update-download-path /tmp/tashi-depin-worker \&\& docker logs -f tashi-depin-worker|g' "$STARTALL_FILE"
      sed -i '' 's/arrange_window "gensyn"/arrange_window "tashi"/g' "$STARTALL_FILE"
      sed -i '' 's/# 4\. 启动gensyn/# 4. 启动 Tashi（替换原来的 gensyn）/g' "$STARTALL_FILE"
      # 删除 Ritual 相关代码
      sed -i '' '/# 7\. 启动Ritual/,/arrange_window "Ritual"/d' "$STARTALL_FILE"
      sed -i '' '/- Ritual/d' "$STARTALL_FILE"
      else
        sed -i 's|./gensyn.sh|docker stop tashi-depin-worker 2>/dev/null; docker rm tashi-depin-worker 2>/dev/null; docker run -d -p 39065:39065 -p 127.0.0.1:9000:9000 --mount type=volume,src=tashi-depin-worker-auth,dst=/home/worker/auth --name tashi-depin-worker -e RUST_LOG="info,tashi_depin_worker=debug,tashi_depin_common=debug" --health-cmd="pgrep -f tashi-depin-worker || exit 1" --health-interval=30s --health-timeout=10s --health-retries=3 --restart=unless-stopped --pull=always --platform linux/amd64 ghcr.io/tashigg/tashi-depin-worker:0 run /home/worker/auth --unstable-update-download-path /tmp/tashi-depin-worker \&\& docker logs -f tashi-depin-worker|g' "$STARTALL_FILE"
        sed -i 's/arrange_window "gensyn"/arrange_window "tashi"/g' "$STARTALL_FILE"
        sed -i 's/# 4\. 启动gensyn/# 4. 启动 Tashi（替换原来的 gensyn）/g' "$STARTALL_FILE"
        # 删除 Ritual 相关代码
        sed -i '/# 7\. 启动Ritual/,/arrange_window "Ritual"/d' "$STARTALL_FILE"
        sed -i '/- Ritual/d' "$STARTALL_FILE"
      fi
      log "${GREEN}已使用 sed 替换 gensyn 为 Tashi${NC}"
    fi
  else
    log "${BLUE}未找到 gensyn 代码，将在 #4 位置添加 Tashi 启动逻辑...${NC}"
    
    # 使用 Python 在 #4 位置插入 Tashi 代码
    python3 <<PYTHON_INSERT_EOF
import sys

file_path = "$STARTALL_FILE"
tashi_code = '''# 4. 启动 Tashi（替换原来的 gensyn，上层左侧，距离左边界30px）
osascript -e 'tell app "Terminal" to do script "cd ~ && docker stop tashi-depin-worker 2>/dev/null; docker rm tashi-depin-worker 2>/dev/null; docker run -d -p 39065:39065 -p 127.0.0.1:9000:9000 --mount type=volume,src=tashi-depin-worker-auth,dst=/home/worker/auth --name tashi-depin-worker -e RUST_LOG=\\"info,tashi_depin_worker=debug,tashi_depin_common=debug\\" --health-cmd=\\"pgrep -f tashi-depin-worker || exit 1\\" --health-interval=30s --health-timeout=10s --health-retries=3 --restart=unless-stopped --pull=always --platform linux/amd64 ghcr.io/tashigg/tashi-depin-worker:0 run /home/worker/auth --unstable-update-download-path /tmp/tashi-depin-worker && docker logs -f tashi-depin-worker"'
sleep 1
arrange_window "tashi" \$((x1+30)) \$y1 \$upper_item_width \$upper_height
'''

try:
    with open(file_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    # 删除 Ritual 相关代码
    new_lines = []
    skip_ritual = False
    for i, line in enumerate(lines):
        if '# 7.' in line and '启动Ritual' in line:
            skip_ritual = True
            continue
        if skip_ritual and 'arrange_window "Ritual"' in line:
            skip_ritual = False
            continue
        if skip_ritual:
            continue
        if '- Ritual' in line:
            continue
        new_lines.append(line)
    lines = new_lines
    
    # 查找 #4 或 # 4. 的位置
    insert_pos = -1
    for i, line in enumerate(lines):
        if '# 4.' in line or '#4.' in line:
            insert_pos = i + 1
            break
    
    # 如果找不到 #4，查找 # 6. 启动nexus 之前
    if insert_pos == -1:
        for i, line in enumerate(lines):
            if '# 6.' in line and '启动nexus' in line:
                insert_pos = i
                break
    
    # 如果还是找不到，在文件末尾添加
    if insert_pos == -1:
        insert_pos = len(lines)
    
    # 插入 Tashi 代码
    lines.insert(insert_pos, tashi_code + '\n')
    
    with open(file_path, 'w', encoding='utf-8') as f:
        f.writelines(lines)
    
    print("插入完成")
    sys.exit(0)
except Exception as e:
    print(f"插入失败: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_INSERT_EOF
    
    if [[ $? -eq 0 ]]; then
      log "${GREEN}已在 startAll.sh 中添加 Tashi 启动逻辑${NC}"
    else
      log "${YELLOW}Python 插入失败，请手动编辑 startAll.sh${NC}"
    fi
  fi
  
  log "${GREEN}已更新 startAll.sh${NC}"
  log "${YELLOW}请检查 startAll.sh 文件，确保 Tashi 窗口位置和配置正确${NC}"
}

# 主循环
main() {
  if [[ "$OS_TYPE" == "Ubuntu" ]]; then
    install_dependencies
  fi
  if [[ "$OS_TYPE" == "macOS" || "$OS_TYPE" == "Linux" ]]; then
    install_homebrew
  fi
  install_cmake
  install_protobuf
  install_rust
  configure_rust_target
  get_node_id
  
  # 创建桌面快捷方式（仅在 macOS 上）
  if [[ "$OS_TYPE" == "macOS" ]]; then
    create_desktop_shortcuts
    
  # Ritual 功能已删除，不再需要配置
    
    # 更新 startAll.sh 以包含 Tashi 启动逻辑
    update_startall_script
  fi
  
  # 首次启动节点
  log "${BLUE}首次启动 Nexus 节点...${NC}"
  install_nexus_cli
  cleanup_restart
  if start_node; then
    log "${GREEN}节点启动成功！${NC}"
  else
    log "${YELLOW}节点启动失败，将在下次更新检测时重试${NC}"
  fi
  
  log "${BLUE}开始监控 GitHub 仓库更新...${NC}"
  log "${BLUE}检测频率：每30分钟检查一次${NC}"
  log "${BLUE}重启条件：仅在检测到仓库更新时重启${NC}"
  
  while true; do
    # 每30分钟检查一次更新
    sleep 1800
    
    if check_github_updates; then
      log "${BLUE}检测到更新，准备重启节点...${NC}"
      install_nexus_cli
      cleanup_restart
      if start_node; then
        log "${GREEN}节点已成功重启！${NC}"
      else
        log "${YELLOW}节点重启失败，将在下次更新检测时重试${NC}"
      fi
    else
      log "${BLUE}无更新，节点继续运行...${NC}"
    fi
  done
}

main