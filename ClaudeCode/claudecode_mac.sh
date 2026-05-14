#!/bin/bash

# =============================================
#  Claude Code 一键安装脚本 (macOS 专用)
#  适用: Apple Silicon (M4) / macOS 13+
# =============================================

set -e

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # 无颜色

echo -e "${BLUE}🚀 开始 Claude Code 安装流程...${NC}"

# ------------------------------------------------------------
# 第一步：检查操作系统版本
# ------------------------------------------------------------
echo -e "\n${YELLOW}[1/5] 检查系统环境...${NC}"
macos_version=$(sw_vers -productVersion)
major_version=$(echo "$macos_version" | cut -d. -f1)
# macOS 11.0 对应的 Darwin 主版本号为 20
if [ "$major_version" -lt 12 ]; then
    echo -e "${RED}❌ 您的 macOS 版本 ($macos_version) 过低。Claude Code 需要 macOS 12 (Monterey) 或更高版本。${NC}"
    # 建议用户升级或退出
fi
echo -e "${GREEN}✅ macOS 版本 ($macos_version) 符合要求。${NC}"

# ------------------------------------------------------------
# 第二步：安装或更新 Xcode Command Line Tools
# ------------------------------------------------------------
echo -e "\n${YELLOW}[2/5] 检查 Xcode Command Line Tools...${NC}"
if ! xcode-select -p &> /dev/null; then
    echo -e "${YELLOW}📥 正在安装 Xcode Command Line Tools...${NC}"
    xcode-select --install
    echo -e "${YELLOW}⏳ 请在弹出的对话框中完成安装，然后按回车键继续...${NC}"
    read -p ""
else
    echo -e "${GREEN}✅ Xcode Command Line Tools 已安装。${NC}"
fi

# ------------------------------------------------------------
# 第三步：安装 Node.js 18+ (如果缺失或版本过低)
# ------------------------------------------------------------
echo -e "\n${YELLOW}[3/5] 检查 Node.js 环境...${NC}"

install_nodejs() {
    if ! command -v brew &> /dev/null; then
        echo -e "${YELLOW}⚠️  未检测到 Homebrew，正在安装...${NC}"
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        # 将 Homebrew 添加到 PATH (适用于 Apple Silicon)
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
    echo -e "${YELLOW}📥 正在通过 Homebrew 安装 Node.js 18...${NC}"
    brew install node@18
    # 链接到系统 PATH
    brew link --overwrite --force node@18
    echo -e "${GREEN}✅ Node.js 18 安装完成。${NC}"
}

if command -v node &> /dev/null; then
    node_version=$(node -v | cut -d'v' -f2 | cut -d. -f1)
    if [ "$node_version" -ge 18 ]; then
        echo -e "${GREEN}✅ 检测到 Node.js $(node -v)，版本符合要求。${NC}"
    else
        echo -e "${YELLOW}⚠️  检测到 Node.js $(node -v) 版本过低，需要 v18+。${NC}"
        install_nodejs
    fi
else
    echo -e "${YELLOW}⚠️  未检测到 Node.js，开始安装。${NC}"
    install_nodejs
fi

# 验证 npm 可用
if ! command -v npm &> /dev/null; then
    echo -e "${RED}❌ npm 未正确安装，请检查。${NC}"
    exit 1
fi

# ------------------------------------------------------------
# 第四步：使用官方推荐的原生安装脚本 (最稳定)
# ------------------------------------------------------------
echo -e "\n${YELLOW}[4/5] 安装 Claude Code...${NC}"

# 先检查是否已安装
if command -v claude &> /dev/null; then
    echo -e "${GREEN}✅ Claude Code 已安装。版本信息：${NC}"
    claude --version
    read -p "是否要重新安装或升级？ (y/n): " reinstall_choice
    if [[ "$reinstall_choice" != "y" && "$reinstall_choice" != "Y" ]]; then
        echo -e "${BLUE}⏭️  跳过安装步骤。${NC}"
    else
        echo -e "${YELLOW}🔄 正在重新安装 Claude Code...${NC}"
        curl -fsSL https://claude.ai/install.sh | bash
    fi
else
    echo -e "${YELLOW}📥 正在通过官方脚本安装...${NC}"
    # 使用官方推荐的原生安装脚本，会自动处理 arm64 架构
    curl -fsSL https://claude.ai/install.sh | bash
    echo -e "${GREEN}✅ Claude Code 安装完成。${NC}"
fi

# ------------------------------------------------------------
# 第五步：配置环境变量 (PATH)
# ------------------------------------------------------------
echo -e "\n${YELLOW}[5/5] 配置环境变量...${NC}"

# 原生安装脚本通常会将 claude 安装到 ~/.local/bin
CLAUDE_BIN_PATH="$HOME/.local/bin"

# 检查 PATH 中是否已包含安装路径
if [[ ":$PATH:" != *":$CLAUDE_BIN_PATH:"* ]]; then
    echo -e "${YELLOW}⚙️  正在将 $CLAUDE_BIN_PATH 添加到 PATH...${NC}"
    # 添加到 zsh 配置文件 (macOS 默认 shell)
    echo "export PATH=\"$CLAUDE_BIN_PATH:\$PATH\"" >> ~/.zshrc
    # 立即生效
    export PATH="$CLAUDE_BIN_PATH:$PATH"
    echo -e "${GREEN}✅ 已更新 PATH，请重新打开终端或运行 'source ~/.zshrc' 使其生效。${NC}"
else
    echo -e "${GREEN}✅ $CLAUDE_BIN_PATH 已在 PATH 中。${NC}"
fi

# ------------------------------------------------------------
# 安装后验证
# ------------------------------------------------------------
echo -e "\n${BLUE}🔍 验证安装...${NC}"
if command -v claude &> /dev/null; then
    echo -e "${GREEN}🎉 Claude Code 安装成功！版本信息：${NC}"
    claude --version
    echo -e "\n${CYAN}现在可以在终端输入 'claude' 启动，首次使用需完成 OAuth 认证。${NC}"
else
    echo -e "${RED}❌ 安装后仍找不到 'claude' 命令。${NC}"
    echo -e "${YELLOW}请尝试以下步骤：${NC}"
    echo -e "1. 运行 'source ~/.zshrc' 刷新环境变量"
    echo -e "2. 或者关闭并重新打开终端"
    echo -e "3. 如果问题依旧，请尝试手动安装: npm install -g @anthropic-ai/claude-code"
fi

echo -e "\n${GREEN}📄 安装脚本执行完毕。${NC}"
