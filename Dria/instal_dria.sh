#!/bin/bash

# =============================================
#  Dria Node 一键安装、配置与启动脚本（智能版）
#  自动检查并创建 /usr/local/bin，全程交互
# =============================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

KEY_FILE="$HOME/.dria/wallet.key"
MODEL_FILE="$HOME/.dria/current_model"

# ------------------------------------------------------------
# 0. 检查并创建 /usr/local/bin
# ------------------------------------------------------------
if [ ! -d "/usr/local/bin" ]; then
    echo -e "${YELLOW}⚠️  目录 /usr/local/bin 不存在，正在创建...${NC}"
    sudo mkdir -p /usr/local/bin
    echo -e "${GREEN}✅ 目录已创建${NC}"
else
    echo -e "${GREEN}✅ /usr/local/bin 目录已存在，无需创建${NC}"
fi

# ------------------------------------------------------------
# 1. 清理旧版本
# ------------------------------------------------------------
echo -e "${BLUE}🧹 检查并清理旧版文件...${NC}"
if [ -d "$HOME/.dria" ] || [ -f "$HOME/Desktop/dria_start.command" ]; then
    echo -e "${YELLOW}⚠️  发现旧版 Dria 残留，正在移除...${NC}"
    rm -rf "$HOME/.dria"
    rm -f "$HOME/Desktop/dria_start.command"
    echo -e "${GREEN}✅ 清理完毕${NC}"
fi

# ------------------------------------------------------------
# 2. 安装 dria-node
# ------------------------------------------------------------
if command -v dria-node &> /dev/null; then
    echo -e "${GREEN}✅ dria-node 已安装，跳过安装步骤${NC}"
else
    echo -e "${BLUE}📥 正在安装 dria-node ...${NC}"
    curl -fsSL https://raw.githubusercontent.com/firstbatchxyz/dkn-compute-node/master/install.sh | bash
    # 确保 PATH 包含安装路径
    export PATH="$HOME/.dria/bin:$PATH"
    echo -e "${GREEN}✅ dria-node 安装完成${NC}"
fi

# ------------------------------------------------------------
# 3. 运行 setup（如果尚未完成）
# ------------------------------------------------------------
echo ""
echo -e "${BLUE}🔧 检查节点环境...${NC}"

NEED_SETUP=true
if [ -f "$HOME/.dria/config.json" ] || [ -f "$HOME/.dria/config.toml" ]; then
    read -p "$(echo -e ${YELLOW}"检测到可能已完成 setup，是否重新配置？(y/n): "${NC})" reconfirm
    if [[ "$reconfirm" != "y" && "$reconfirm" != "Y" ]]; then
        NEED_SETUP=false
    fi
fi

if $NEED_SETUP; then
    echo -e "${CYAN}📋 现在将进入模型选择界面，请根据你的内存选择合适模型${NC}"
    echo -e "${CYAN}   推荐：16GB 内存选择 qwen3.5:2b 或 lfm2.5:1.2b${NC}"
    echo ""
    dria-node setup
    echo ""
    read -p "$(echo -e ${YELLOW}"请输入你刚才选择的模型名称 (例如：lfm2.5:1.2b): "${NC})" MODEL_NAME
    echo "$MODEL_NAME" > "$MODEL_FILE"
else
    if [ -f "$MODEL_FILE" ]; then
        MODEL_NAME=$(cat "$MODEL_FILE")
        echo -e "${GREEN}📌 将使用之前选择的模型：$MODEL_NAME${NC}"
    else
        read -p "$(echo -e ${YELLOW}"请输入要运行的模型名称 (例如：lfm2.5:1.2b): "${NC})" MODEL_NAME
        echo "$MODEL_NAME" > "$MODEL_FILE"
    fi
fi

# ------------------------------------------------------------
# 4. 输入钱包私钥并安全保存
# ------------------------------------------------------------
echo ""
echo -e "${BLUE}🔑 配置钱包私钥...${NC}"
echo -e "${YELLOW}⚠️  请使用一个专用的以太坊钱包私钥（64位十六进制字符）${NC}"
echo -e "${YELLOW}   不要使用存有大量资产的钱包！${NC}"

if [ -f "$KEY_FILE" ]; then
    read -p "$(echo -e ${YELLOW}"检测到已保存的私钥，是否使用现有私钥？(y/n): "${NC})" use_existing
    if [[ "$use_existing" == "n" || "$use_existing" == "N" ]]; then
        rm -f "$KEY_FILE"
    fi
fi

if [ ! -f "$KEY_FILE" ]; then
    read -sp "请输入你的钱包私钥 (输入不会显示): " WALLET_KEY
    echo ""
    # 去掉可选的 0x 前缀，并验证长度
    clean_key=$(echo "$WALLET_KEY" | sed 's/^0x//')
    if [[ ! "$clean_key" =~ ^[a-fA-F0-9]{64}$ ]]; then
        echo -e "${RED}❌ 私钥格式不正确！必须是 64 位十六进制字符串${NC}"
        echo -e "${RED}   已取消，请重新运行脚本${NC}"
        exit 1
    fi
    mkdir -p "$HOME/.dria"
    echo "$clean_key" > "$KEY_FILE"
    chmod 600 "$KEY_FILE"
    echo -e "${GREEN}✅ 私钥已安全保存至 $KEY_FILE${NC}"
else
    echo -e "${GREEN}✅ 将使用已有私钥${NC}"
fi

# ------------------------------------------------------------
# 5. 生成简洁的桌面启动脚本（直接运行，无 tmux）
# ------------------------------------------------------------
echo ""
echo -e "${BLUE}📝 正在创建桌面启动文件...${NC}"

cat > "$HOME/Desktop/dria_start.command" <<'DESKTOPEOF'
#!/bin/bash

# Dria Node 一键启动
# 关闭此窗口即可停止节点

KEY_FILE="$HOME/.dria/wallet.key"
MODEL_FILE="$HOME/.dria/current_model"

if [ ! -f "$KEY_FILE" ]; then
    echo "❌ 未找到私钥文件，请先运行安装脚本"
    read -p "按任意键退出..."
    exit 1
fi

if [ ! -f "$MODEL_FILE" ]; then
    echo "⚠️  未找到模型记录，请输入要运行的模型名称："
    read MODEL_NAME
    echo "$MODEL_NAME" > "$MODEL_FILE"
else
    MODEL_NAME=$(cat "$MODEL_FILE")
fi

# 确保 dria-node 可用
if ! command -v dria-node &> /dev/null; then
    if [ -f "$HOME/.dria/bin/dria-node" ]; then
        export PATH="$HOME/.dria/bin:$PATH"
    else
        echo "❌ 找不到 dria-node，请确认安装完成"
        read -p "按任意键退出..."
        exit 1
    fi
fi

WALLET_KEY=$(cat "$KEY_FILE")

echo "🚀 正在启动 Dria 节点（模型：$MODEL_NAME）..."
echo "📡 日志将实时显示在此窗口，按 Ctrl+C 可停止节点"
echo "----------------------------------------"

dria-node start --wallet "$WALLET_KEY" --model "$MODEL_NAME"
DESKTOPEOF

chmod +x "$HOME/Desktop/dria_start.command"
echo -e "${GREEN}✅ 桌面启动文件已创建：~/Desktop/dria_start.command${NC}"

# ------------------------------------------------------------
# 6. 完成提示
# ------------------------------------------------------------
echo ""
echo -e "${GREEN}══════════════════════════════════════════════${NC}"
echo -e "${GREEN}  🎉 Dria 节点安装完成！${NC}"
echo -e "${GREEN}══════════════════════════════════════════════${NC}"
echo ""
echo -e "  🖥️  启动节点：双击桌面的 ${CYAN}dria_start.command${NC}"
echo -e "      (日志会直接显示在当前终端窗口，关闭窗口则停止节点)"
echo -e "  📊 查看收益：${CYAN}https://dria.co/edge-ai${NC}"
echo -e "  🔐 私钥文件：${CYAN}$KEY_FILE${NC} (请勿分享)"
echo ""
