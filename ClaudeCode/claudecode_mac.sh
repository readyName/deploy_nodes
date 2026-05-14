#!/bin/bash

# =============================================
#  Claude Code 安装 + DeepSeek 一键接入脚本
#  适用: macOS Apple Silicon / macOS 12+
# =============================================

set -e

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}🚀 Claude Code 环境配置助手${NC}"

# ------------------------------------------------------------
# 0. 检查系统版本
# ------------------------------------------------------------
macos_version=$(sw_vers -productVersion)
major_version=$(echo "$macos_version" | cut -d. -f1)
if [ "$major_version" -lt 12 ]; then
    echo -e "${RED}❌ 需要 macOS 12 (Monterey) 或更高版本。当前版本：$macos_version${NC}"
    exit 1
fi
echo -e "${GREEN}✅ 系统版本：$macos_version${NC}"

# ------------------------------------------------------------
# 1. 确保 Xcode Command Line Tools 可用
# ------------------------------------------------------------
if ! xcode-select -p &> /dev/null; then
    echo -e "${YELLOW}📥 正在安装 Xcode Command Line Tools...${NC}"
    xcode-select --install
    echo -e "${YELLOW}⏳ 请在弹出窗口完成安装后按回车继续...${NC}"
    read -p ""
fi

# ------------------------------------------------------------
# 2. 确保 Node.js 18+ 已安装
# ------------------------------------------------------------
install_node() {
    if ! command -v brew &> /dev/null; then
        echo -e "${YELLOW}⚠️  未找到 Homebrew，正在安装...${NC}"
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
    brew install node@18
    brew link --overwrite --force node@18
}

if command -v node &> /dev/null; then
    node_version=$(node -v | cut -d'v' -f2 | cut -d. -f1)
    if [ "$node_version" -lt 18 ]; then
        echo -e "${YELLOW}⚠️  Node.js 版本过低，正在升级...${NC}"
        install_node
    else
        echo -e "${GREEN}✅ Node.js $(node -v)${NC}"
    fi
else
    install_node
fi

# ------------------------------------------------------------
# 3. 安装 Claude Code
# ------------------------------------------------------------
if command -v claude &> /dev/null; then
    echo -e "${GREEN}✅ Claude Code 已安装：$(claude --version 2>&1 | head -1)${NC}"
    read -p "是否重新安装/升级？(y/n): " re
    if [[ "$re" != "y" && "$re" != "Y" ]]; then
        echo -e "${BLUE}⏭️  跳过安装${NC}"
    else
        echo -e "${YELLOW}🔄 正在重新安装...${NC}"
        curl -fsSL https://claude.ai/install.sh | bash
    fi
else
    echo -e "${YELLOW}📥 正在安装 Claude Code...${NC}"
    curl -fsSL https://claude.ai/install.sh | bash
fi

# 确保 PATH 包含 ~/.local/bin
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
    export PATH="$HOME/.local/bin:$PATH"
fi

# ------------------------------------------------------------
# 4. 接入 DeepSeek 模型（可选）
# ------------------------------------------------------------
echo ""
echo -e "${CYAN}⚡ 是否接入 DeepSeek 模型以降低 API 成本？${NC}"
read -p "输入 y 配置，其他键跳过: " setup_deepseek

if [[ "$setup_deepseek" == "y" || "$setup_deepseek" == "Y" ]]; then
    echo -e "${YELLOW}📝 请准备你的 DeepSeek API Key${NC}"
    echo -e "${YELLOW}   获取地址：https://platform.deepseek.com/api_keys${NC}"
    read -sp "粘贴 API Key（输入不会显示）: " DS_KEY
    echo ""

    if [ -z "$DS_KEY" ]; then
        echo -e "${RED}❌ API Key 不能为空，已跳过配置${NC}"
    else
        # 写入 ~/.zshrc
        cat >> ~/.zshrc <<EOF

# === DeepSeek for Claude Code ===
export ANTHROPIC_BASE_URL="https://api.deepseek.com/anthropic"
export ANTHROPIC_AUTH_TOKEN="$DS_KEY"
export ANTHROPIC_MODEL="deepseek-v4-pro"
export ANTHROPIC_SMALL_FAST_MODEL="deepseek-v4-flash"
export ANTHROPIC_DEFAULT_SONNET_MODEL="deepseek-v4-pro"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="deepseek-v4-flash"
EOF

        # 同时生成 settings.json 备用
        mkdir -p ~/.claude
        cat > ~/.claude/settings.json <<EOF
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://api.deepseek.com/anthropic",
    "ANTHROPIC_AUTH_TOKEN": "$DS_KEY",
    "ANTHROPIC_MODEL": "deepseek-v4-pro",
    "ANTHROPIC_SMALL_FAST_MODEL": "deepseek-v4-flash",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "deepseek-v4-pro",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "deepseek-v4-flash"
  }
}
EOF

        echo -e "${GREEN}✅ DeepSeek 配置完成！${NC}"
        echo -e "${CYAN}   环境变量已写入 ~/.zshrc 和 ~/.claude/settings.json${NC}"
        echo -e "${CYAN}   请执行 source ~/.zshrc 或重新打开终端使其生效${NC}"
    fi
else
    echo -e "${BLUE}⏭️  跳过 DeepSeek 配置（后续可随时手动添加）${NC}"
fi

# ------------------------------------------------------------
# 5. 完成
# ------------------------------------------------------------
echo ""
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN}  🎉 全部完成！${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo ""
echo -e "  启动 Claude Code：${CYAN}claude${NC}"
echo -e "  首次启动需完成 OAuth 认证（若选择接入 DeepSeek，则直接用 API Key 登录）"
echo ""
if [[ "$setup_deepseek" == "y" || "$setup_deepseek" == "Y" ]]; then
    echo -e "  💡 登录时选择 ${CYAN}2. Anthropic Console account${NC} 即可使用 DeepSeek"
    echo -e "  若想切换回官方模型，请删除 ~/.zshrc 中 DeepSeek 相关环境变量"
fi
