#!/bin/bash

set -e
set -o pipefail

# 密码验证函数
verify_password() {
    local auth_file="$HOME/.gensyn_auth"
    local max_attempts=3
    local attempt=1
    
    # 检查是否已经验证过
    if [[ -f "$auth_file" ]]; then
        local stored_hash=$(cat "$auth_file")
        local machine_id=$(uname -m)-$(hostname)-$(whoami)
        local expected_hash=$(echo "$machine_id" | openssl dgst -sha256 | cut -d' ' -f2)
        
        if [[ "$stored_hash" == "$expected_hash" ]]; then
            echo "✅ 身份验证通过，跳过密码验证"
            # 从验证文件中读取权限级别
            if [[ -f "$HOME/.gensyn_permission" ]]; then
                export GENSYN_PERMISSION=$(cat "$HOME/.gensyn_permission")
            else
                export GENSYN_PERMISSION="full"
            fi
            return 0
        else
            echo "⚠️ 检测到环境变化，需要重新验证"
            rm -f "$auth_file"
            rm -f "$HOME/.gensyn_permission"
        fi
    fi
    
    # 首次运行或需要重新验证
    echo "🔐 首次部署需要验证身份"
    echo "请输入部署密码（最多尝试 $max_attempts 次）"
    
    while [[ $attempt -le $max_attempts ]]; do
        echo -n "密码 (尝试 $attempt/$max_attempts): "
        read -s password
        echo
        
        # 这里设置你的实际密码，建议使用强密码
        local password1_encoded="YW56aHVhbmcwMDE="
        local password2_encoded="YW56aHVhbmcwMDI="
        
        # 计算输入密码的base64编码
        local input_encoded=$(echo -n "$password" | base64)
        
        if [[ "$input_encoded" == "$password1_encoded" ]]; then
            echo "✅ 密码验证成功！权限级别：完整权限"
            export GENSYN_PERMISSION="full"
            
            # 生成并保存验证文件
            local machine_id=$(uname -m)-$(hostname)-$(whoami)
            local auth_hash=$(echo "$machine_id" | openssl dgst -sha256 | cut -d' ' -f2)
            echo "$auth_hash" > "$auth_file"
            echo "full" > "$HOME/.gensyn_permission"
            chmod 600 "$auth_file"
            chmod 600 "$HOME/.gensyn_permission"
            
            echo "✅ 身份验证信息已保存，后续部署无需再次输入密码"
            return 0
        elif [[ "$input_encoded" == "$password2_encoded" ]]; then
            echo "✅ 密码验证成功！权限级别：仅限 gensyn"
            export GENSYN_PERMISSION="gensyn_only"
            
            # 生成并保存验证文件
            local machine_id=$(uname -m)-$(hostname)-$(whoami)
            local auth_hash=$(echo "$machine_id" | openssl dgst -sha256 | cut -d' ' -f2)
            echo "$auth_hash" > "$auth_file"
            echo "gensyn_only" > "$HOME/.gensyn_permission"
            chmod 600 "$auth_file"
            chmod 600 "$HOME/.gensyn_permission"
            
            echo "✅ 身份验证信息已保存，后续部署无需再次输入密码"
            return 0
        else
            echo "❌ 密码错误"
            if [[ $attempt -lt $max_attempts ]]; then
                echo "⚠️ 还有 $((max_attempts - attempt)) 次机会"
            fi
            attempt=$((attempt + 1))
        fi
    done
    
    echo "❌ 密码验证失败，已达到最大尝试次数"
    exit 1
}

echo "🚀 Starting one-click RL-Swarm environment deployment..."

# 首先进行密码验证
verify_password

# ----------- 检测操作系统 -----------
OS_TYPE="unknown"
if [[ "$(uname -s)" == "Darwin" ]]; then
  OS_TYPE="macos"
elif [[ -f /etc/os-release ]]; then
  . /etc/os-release
  if [[ "$ID" == "ubuntu" ]]; then
    OS_TYPE="ubuntu"
  fi
fi

if [[ "$OS_TYPE" == "unknown" ]]; then
  echo "❌ 不支持的操作系统。仅支持 macOS 和 Ubuntu。"
  exit 1
fi

# ----------- /etc/hosts Patch ----------- 
echo "🔧 Checking /etc/hosts configuration..."
if ! grep -q "raw.githubusercontent.com" /etc/hosts; then
  echo "📝 Writing GitHub accelerated Hosts entries..."
  sudo tee -a /etc/hosts > /dev/null <<EOL
199.232.68.133 raw.githubusercontent.com
199.232.68.133 user-images.githubusercontent.com
199.232.68.133 avatars2.githubusercontent.com
199.232.68.133 avatars1.githubusercontent.com
EOL
else
  echo "✅ Hosts are already configured."
fi

# ----------- 安装依赖 -----------
if [[ "$OS_TYPE" == "macos" ]]; then
  echo "🍺 Checking Homebrew..."
  if ! command -v brew &>/dev/null; then
    echo "📥 Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  else
    echo "✅ Homebrew 已安装，跳过安装。"
  fi
  # 配置 Brew 环境变量
  BREW_ENV='eval "$(/opt/homebrew/bin/brew shellenv)"'
  if ! grep -q "$BREW_ENV" ~/.zshrc; then
    echo "$BREW_ENV" >> ~/.zshrc
  fi
  eval "$(/opt/homebrew/bin/brew shellenv)"
  # 安装依赖
  echo "📦 检查并安装 Node.js, Python@3.10, curl, screen, git, yarn..."
  deps=(node python3.10 curl screen git yarn)
  brew_names=(node python@3.10 curl screen git yarn)
  for i in "${!deps[@]}"; do
    dep="${deps[$i]}"
    brew_name="${brew_names[$i]}"
    if ! command -v $dep &>/dev/null; then
      echo "📥 安装 $brew_name..."
      while true; do
        if brew install $brew_name; then
          echo "✅ $brew_name 安装成功。"
          break
        else
          echo "⚠️ $brew_name 安装失败，3秒后重试..."
          sleep 3
        fi
      done
    else
      echo "✅ $dep 已安装，跳过安装。"
    fi
  done
  # 自动清理.zshrc中python3.12配置，并写入3.10配置
  if grep -q "# Python3.12 Environment Setup" ~/.zshrc; then
    echo "🧹 清理旧的 Python3.12 配置..."
    sed -i '' '/# Python3.12 Environment Setup/,/^fi$/d' ~/.zshrc
  fi
  PYTHON_ALIAS="# Python3.10 Environment Setup"
  if ! grep -q "$PYTHON_ALIAS" ~/.zshrc; then
    cat << 'EOF' >> ~/.zshrc

# Python3.10 Environment Setup
if [[ $- == *i* ]]; then
  alias python="/opt/homebrew/bin/python3.10"
  alias python3="/opt/homebrew/bin/python3.10"
  alias pip="/opt/homebrew/bin/pip3.10"
  alias pip3="/opt/homebrew/bin/pip3.10"
fi
EOF
  fi
  source ~/.zshrc || true
else
  # Ubuntu
  echo "📦 检查并安装 Node.js (最新LTS), Python3, curl, screen, git, yarn..."
  # 检查当前Node.js版本
  if command -v node &>/dev/null; then
    CURRENT_NODE_VERSION=$(node --version 2>/dev/null | sed 's/v//')
    echo "🔍 当前 Node.js 版本: $CURRENT_NODE_VERSION"
    # 获取最新LTS版本
    LATEST_LTS_VERSION=$(curl -s https://nodejs.org/dist/index.json | jq -r '.[0].version' 2>/dev/null | sed 's/v//')
    echo "🔍 最新 LTS 版本: $LATEST_LTS_VERSION"
    
    if [[ "$CURRENT_NODE_VERSION" != "$LATEST_LTS_VERSION" ]]; then
      echo "🔄 检测到版本不匹配，正在更新到最新 LTS 版本..."
      # 卸载旧版本
      sudo apt remove -y nodejs npm || true
      sudo apt autoremove -y || true
      # 清理可能的残留
      sudo rm -rf /usr/local/bin/npm /usr/local/bin/node || true
      sudo rm -rf ~/.npm || true
      # 安装最新LTS版本
      curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
      sudo apt-get install -y nodejs
      echo "✅ Node.js 已更新到最新 LTS 版本"
    else
      echo "✅ Node.js 已是最新 LTS 版本，跳过更新"
    fi
  else
    echo "📥 未检测到 Node.js，正在安装最新 LTS 版本..."
    # 安装最新Node.js（LTS）
    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
    sudo apt-get install -y nodejs
    echo "✅ Node.js 安装完成"
  fi
  # 其余依赖
  sudo apt update && sudo apt install -y python3 python3-venv python3-pip curl screen git gnupg jq
  # 官方推荐方式，若失败则用npm镜像
  if curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | gpg --dearmor | sudo tee /usr/share/keyrings/yarnkey.gpg > /dev/null \
    && echo "deb [signed-by=/usr/share/keyrings/yarnkey.gpg] https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list \
    && sudo apt update && sudo apt install -y yarn; then
    echo "✅ yarn 安装成功（官方源）"
    # 升级到最新版yarn（Berry）
    yarn set version stable
    yarn -v
  else
    echo "⚠️ 官方源安装 yarn 失败，尝试用 npm 镜像安装..."
    if ! command -v npm &>/dev/null; then
      sudo apt install -y npm
    fi
    npm config set registry https://registry.npmmirror.com
    npm install -g yarn
    # 升级到最新版yarn（Berry）
    yarn set version stable
    yarn -v
  fi
  # Python alias 写入 bashrc
  PYTHON_ALIAS="# Python3.12 Environment Setup"
  if ! grep -q "$PYTHON_ALIAS" ~/.bashrc; then
    cat << 'EOF' >> ~/.bashrc

# Python3.12 Environment Setup
if [[ $- == *i* ]]; then
  alias python="/usr/bin/python3"
  alias python3="/usr/bin/python3"
  alias pip="/usr/bin/pip3"
  alias pip3="/usr/bin/pip3"
fi
EOF
  fi
  source ~/.bashrc || true
fi

# ----------- 克隆前备份关键文件（优先$HOME/rl-swarm-0.5.3，其次$HOME/rl-swarm-0.5，最后$HOME/rl-swarm） -----------
TMP_USER_FILES="$HOME/rl-swarm-user-files"
mkdir -p "$TMP_USER_FILES"

# swarm.pem
if [ -f "$HOME/rl-swarm-0.5.3/swarm.pem" ]; then
  cp "$HOME/rl-swarm-0.5.3/swarm.pem" "$TMP_USER_FILES/swarm.pem" && echo "✅ 已备份 rl-swarm-0.5.3/swarm.pem"
elif [ -f "$HOME/rl-swarm-0.5.3/user/keys/swarm.pem" ]; then
  cp "$HOME/rl-swarm-0.5.3/user/keys/swarm.pem" "$TMP_USER_FILES/swarm.pem" && echo "✅ 已备份 rl-swarm-0.5.3/user/keys/swarm.pem"
elif [ -f "$HOME/rl-swarm-0.5/user/keys/swarm.pem" ]; then
  cp "$HOME/rl-swarm-0.5/user/keys/swarm.pem" "$TMP_USER_FILES/swarm.pem" && echo "✅ 已备份 0.5/user/keys/swarm.pem"
elif [ -f "$HOME/rl-swarm/swarm.pem" ]; then
  cp "$HOME/rl-swarm/swarm.pem" "$TMP_USER_FILES/swarm.pem" && echo "✅ 已备份 rl-swarm/swarm.pem"
else
  echo "⚠️ 未检测到 swarm.pem，如有需要请手动补齐。"
fi

# userApiKey.json
if [ -f "$HOME/rl-swarm-0.5.3/modal-login/temp-data/userApiKey.json" ]; then
  cp "$HOME/rl-swarm-0.5.3/modal-login/temp-data/userApiKey.json" "$TMP_USER_FILES/userApiKey.json" && echo "✅ 已备份 rl-swarm-0.5.3/modal-login/temp-data/userApiKey.json"
elif [ -f "$HOME/rl-swarm-0.5.3/user/modal-login/userApiKey.json" ]; then
  cp "$HOME/rl-swarm-0.5.3/user/modal-login/userApiKey.json" "$TMP_USER_FILES/userApiKey.json" && echo "✅ 已备份 rl-swarm-0.5.3/user/modal-login/userApiKey.json"
elif [ -f "$HOME/rl-swarm-0.5/user/modal-login/userApiKey.json" ]; then
  cp "$HOME/rl-swarm-0.5/user/modal-login/userApiKey.json" "$TMP_USER_FILES/userApiKey.json" && echo "✅ 已备份 0.5/user/modal-login/userApiKey.json"
elif [ -f "$HOME/rl-swarm/modal-login/temp-data/userApiKey.json" ]; then
  cp "$HOME/rl-swarm/modal-login/temp-data/userApiKey.json" "$TMP_USER_FILES/userApiKey.json" && echo "✅ 已备份 rl-swarm/modal-login/temp-data/userApiKey.json"
else
  echo "⚠️ 未检测到 userApiKey.json，如有需要请手动补齐。"
fi

# userData.json
if [ -f "$HOME/rl-swarm-0.5.3/modal-login/temp-data/userData.json" ]; then
  cp "$HOME/rl-swarm-0.5.3/modal-login/temp-data/userData.json" "$TMP_USER_FILES/userData.json" && echo "✅ 已备份 rl-swarm-0.5.3/modal-login/temp-data/userData.json"
elif [ -f "$HOME/rl-swarm-0.5.3/user/modal-login/userData.json" ]; then
  cp "$HOME/rl-swarm-0.5.3/user/modal-login/userData.json" "$TMP_USER_FILES/userData.json" && echo "✅ 已备份 rl-swarm-0.5.3/user/modal-login/userData.json"
elif [ -f "$HOME/rl-swarm-0.5/user/modal-login/userData.json" ]; then
  cp "$HOME/rl-swarm-0.5/user/modal-login/userData.json" "$TMP_USER_FILES/userData.json" && echo "✅ 已备份 0.5/user/modal-login/userData.json"
elif [ -f "$HOME/rl-swarm/modal-login/temp-data/userData.json" ]; then
  cp "$HOME/rl-swarm/modal-login/temp-data/userData.json" "$TMP_USER_FILES/userData.json" && echo "✅ 已备份 rl-swarm/modal-login/temp-data/userData.json"
else
  echo "⚠️ 未检测到 userData.json，如有需要请手动补齐。"
fi

# ----------- Clone Repo ----------- 
if [[ -d "rl-swarm" ]]; then
  echo "⚠️ 检测到已存在目录 'rl-swarm'。"
  read -p "是否覆盖（删除后重新克隆）该目录？(y/n): " confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    echo "🗑️ 正在删除旧目录..."
    rm -rf rl-swarm
    echo "📥 正在克隆 rl-swarm 仓库 (v0.5.8.1 分支)..."
    git clone -b v0.5.8.1 https://github.com/readyName/rl-swarm.git
  else
    echo "❌ 跳过克隆，继续后续流程。"
  fi
else
  echo "📥 正在克隆 rl-swarm 仓库 (v0.5.8.1 分支)..."
  git clone -b v0.5.8.1 https://github.com/readyName/rl-swarm.git
fi

# ----------- 复制临时目录中的 user 关键文件 -----------
KEY_DST="rl-swarm/swarm.pem"
MODAL_DST="rl-swarm/modal-login/temp-data"
mkdir -p "$MODAL_DST"

if [ -f "$TMP_USER_FILES/swarm.pem" ]; then
  cp "$TMP_USER_FILES/swarm.pem" "$KEY_DST" && echo "✅ 恢复 swarm.pem 到新目录" || echo "⚠️ 恢复 swarm.pem 失败"
else
  echo "⚠️ 临时目录缺少 swarm.pem，如有需要请手动补齐。"
fi

for fname in userApiKey.json userData.json; do
  if [ -f "$TMP_USER_FILES/$fname" ]; then
    cp "$TMP_USER_FILES/$fname" "$MODAL_DST/$fname" && echo "✅ 恢复 $fname 到新目录" || echo "⚠️ 恢复 $fname 失败"
  else
    echo "⚠️ 临时目录缺少 $fname，如有需要请手动补齐。"
  fi
  
done

# ----------- 生成桌面可双击运行的 .command 文件 -----------
if [[ "$OS_TYPE" == "macos" ]]; then
  CURRENT_USER=$(whoami)
  PROJECT_DIR="/Users/$CURRENT_USER/rl-swarm"
  DESKTOP_DIR="/Users/$CURRENT_USER/Desktop"
  mkdir -p "$DESKTOP_DIR"
  
  # 根据权限级别决定生成哪些文件
  if [[ "$GENSYN_PERMISSION" == "full" ]]; then
    echo "🔐 权限级别：完整权限 - 生成所有 command 文件"
    for script in gensyn.sh nexus.sh ritual.sh startAll.sh; do
      cmd_name="${script%.sh}.command"
      cat > "$DESKTOP_DIR/$cmd_name" <<EOF
#!/bin/bash

# 设置错误处理
set -e

# 捕获中断信号
trap 'echo -e "\n\\033[33m⚠️ 脚本被中断，但终端将继续运行...\\033[0m"; exit 0' INT TERM

# 进入项目目录
cd "$PROJECT_DIR" || { echo "❌ 无法进入项目目录"; exit 1; }

# 执行脚本
echo "🚀 正在执行 $script..."
./$script

# 脚本执行完成后的提示
echo -e "\\n\\033[32m✅ $script 执行完成\\033[0m"
echo "按任意键关闭此窗口..."
read -n 1 -s
EOF
      chmod +x "$DESKTOP_DIR/$cmd_name"
    done
    
    # 生成 dria.command 文件
    cat > "$DESKTOP_DIR/dria.command" <<EOF
#!/bin/bash

# 设置错误处理
set -e

# 捕获中断信号
trap 'echo -e "\n\\033[33m⚠️ 脚本被中断，但终端将继续运行...\\033[0m"; exit 0' INT TERM

# 执行 Dria Compute Launcher
echo "🚀 正在启动 Dria Compute Launcher..."
dkn-compute-launcher start

# 脚本执行完成后的提示
echo -e "\\n\\033[32m✅ Dria Compute Launcher 执行完成\\033[0m"
echo "按任意键关闭此窗口..."
read -n 1 -s
EOF
    chmod +x "$DESKTOP_DIR/dria.command"
    
    # 生成 clean_spotlight.command 文件（所有权限级别都生成）
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
    chmod +x "$DESKTOP_DIR/clean_spotlight.command"
    
    echo "✅ 已在桌面生成所有可双击运行的 .command 文件（包括 dria.command 和 clean_spotlight.command）。"
  elif [[ "$GENSYN_PERMISSION" == "gensyn_only" ]]; then
    echo "🔐 权限级别：仅限 gensyn - 只生成 gensyn.command 文件"
    cmd_name="gensyn.command"
    cat > "$DESKTOP_DIR/$cmd_name" <<EOF
#!/bin/bash

# 设置错误处理
set -e

# 捕获中断信号
trap 'echo -e "\n\\033[33m⚠️ 脚本被中断，但终端将继续运行...\\033[0m"; exit 0' INT TERM

# 进入项目目录
cd "$PROJECT_DIR" || { echo "❌ 无法进入项目目录"; exit 1; }

# 执行脚本
echo "🚀 正在执行 gensyn.sh..."
./gensyn.sh

# 脚本执行完成后的提示
echo -e "\\n\\033[32m✅ gensyn.sh 执行完成\\033[0m"
echo "按任意键关闭此窗口..."
read -n 1 -s
EOF
    chmod +x "$DESKTOP_DIR/$cmd_name"
    
    # 生成 clean_spotlight.command 文件（所有权限级别都生成）
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
    chmod +x "$DESKTOP_DIR/clean_spotlight.command"
    
    echo "✅ 已在桌面生成 gensyn.command 和 clean_spotlight.command 文件。"
  else
    echo "❌ 未知权限级别：$GENSYN_PERMISSION"
    echo "⚠️ 无法确定应生成哪些文件，跳过桌面文件生成"
    echo "请联系管理员检查权限配置"
  fi
fi

# ----------- Clean Port 3000 ----------- 
echo "🧹 Cleaning up port 3000..."
pid=$(lsof -ti:3000) && [ -n "$pid" ] && kill -9 $pid && echo "✅ Killed: $pid" || echo "✅ Port 3000 is free."

# ----------- 进入rl-swarm目录并执行-----------
cd rl-swarm || { echo "❌ 进入 rl-swarm 目录失败"; exit 1; }
chmod +x gensyn.sh
./gensyn.sh                     