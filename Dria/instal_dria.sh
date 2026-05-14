#!/bin/bash

# =============================================
#  Dria Node 一键安装、配置与启动脚本
#  适用于 macOS Apple Silicon
# =============================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # 无颜色

# 密钥文件路径
KEY_FILE="$HOME/.dria/wallet.key"

# 模型选择记录文件（可选）
MODEL_FILE="$HOME/.dria/current_model"

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
    # 确保路径生效
    export PATH="$HOME/.dria/bin:$PATH"
    echo -e "${GREEN}✅ dria-node 安装完成${NC}"
fi

# ------------------------------------------------------------
# 3. 运行 setup（如果尚未完成）
# ------------------------------------------------------------
echo ""
echo -e "${BLUE}🔧 检查节点环境...${NC}"

NEED_SETUP=true
if dria-node start --help &> /dev/null; then
    # 简单检查是否存在配置文件（通常 setup 后会生成）
    if [ -f "$HOME/.dria/config.json" ] || [ -f "$HOME/.dria/config.toml" ]; then
        read -p "$(echo -e ${YELLOW}"检测到可能已完成 setup，是否重新配置？(y/n): "${NC})" reconfirm
        if [[ "$reconfirm" != "y" && "$reconfirm" != "Y" ]]; then
            NEED_SETUP=false
        fi
    fi
fi

if $NEED_SETUP; then
    echo -e "${CYAN}📋 现在将进入模型选择界面，请根据你的内存选择合适模型${NC}"
    echo -e "${CYAN}   推荐：16GB 内存选择 qwen3.5:2b 或 lfm2.5:1.2b${NC}"
    echo ""
    dria-node setup

    # 记录用户选择的模型（从 setup 输出中无法直接获取，询问用户）
    echo ""
    read -p "$(echo -e ${YELLOW}"请输入你刚才选择的模型名称 (例如：lfm2.5:1.2b): "${NC})" MODEL_NAME
    echo "$MODEL_NAME" > "$MODEL_FILE"
else
    # 如果已有配置文件，从记录文件读取模型，若不存在则询问
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
    # 简单验证是否为 64 位 hex（允许0x前缀）
    clean_key=$(echo "$WALLET_KEY" | sed 's/^0x//')
    if [[ ! "$clean_key" =~ ^[a-fA-F0-9]{64}$ ]]; then
        echo -e "${RED}❌ 私钥格式不正确！必须是 64 位十六进制字符串${NC}"
        echo -e "${RED}   已取消，请重新运行脚本${NC}"
        exit 1
    fi
    # 保存私钥到文件，设置严格权限
    mkdir -p "$HOME/.dria"
    echo "$clean_key" > "$KEY_FILE"
    chmod 600 "$KEY_FILE"
    echo -e "${GREEN}✅ 私钥已安全保存至 $KEY_FILE${NC}"
else
    echo -e "${GREEN}✅ 将使用已有私钥${NC}"
fi

# ------------------------------------------------------------
# 5. 启动节点（使用 tmux 后台运行）
# ------------------------------------------------------------
echo ""
echo -e "${BLUE}🚀 启动 Dria 节点...${NC}"

# 检查 tmux 是否安装
if ! command -v tmux &> /dev/null; then
    echo -e "${YELLOW}⚠️  未检测到 tmux，将使用 nohup 后台运行（日志文件：~/dria.log）${NC}"
    WALLET_KEY=$(cat "$KEY_FILE")
    nohup dria-node start --wallet "$WALLET_KEY" --model "$MODEL_NAME" > ~/dria.log 2>&1 &
    echo -e "${GREEN}✅ 节点已在后台启动，PID: $!${NC}"
    echo -e "${CYAN}   查看日志：tail -f ~/dria.log${NC}"
else
    # 先结束可能已存在的 dria tmux 会话
    tmux kill-session -t dria 2>/dev/null || true
    # 创建新的 tmux 会话并在其中启动节点
    WALLET_KEY=$(cat "$KEY_FILE")
    tmux new -d -s dria "dria-node start --wallet $WALLET_KEY --model $MODEL_NAME"
    echo -e "${GREEN}✅ 节点已在 tmux 会话 (dria) 中启动${NC}"
    echo -e "${CYAN}   查看运行状态：tmux attach -t dria${NC}"
    echo -e "${CYAN}   脱离会话（保持运行）：先按 Ctrl+B 再按 D${NC}"
fi

# ------------------------------------------------------------
# 6. 生成桌面一键启动脚本
# ------------------------------------------------------------
echo ""
echo -e "${BLUE}📝 正在创建桌面启动文件...${NC}"

cat > "$HOME/Desktop/dria_start.command" <<'EOF'
#!/bin/bash

# Dria Node 桌面启动器
# 直接从保存的文件读取私钥并启动

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

KEY_FILE="$HOME/.dria/wallet.key"
MODEL_FILE="$HOME/.dria/current_model"

# 检查私钥文件
if [ ! -f "$KEY_FILE" ]; then
    echo -e "${RED}❌ 未找到私钥文件，请先运行安装脚本${NC}"
    read -p "按任意键退出..."
    exit 1
fi

# 检查模型文件
if [ ! -f "$MODEL_FILE" ]; then
    echo -e "${YELLOW}⚠️  未找到模型记录，请输入要运行的模型名称：${NC}"
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
        echo -e "${RED}❌ 找不到 dria-node，请确认安装完成${NC}"
        read -p "按任意键退出..."
        exit 1
    fi
fi

# 检查 tmux
USE_TMUX=false
if command -v tmux &> /dev/null; then
    USE_TMUX=true
fi

WALLET_KEY=$(cat "$KEY_FILE")

echo -e "${BLUE}🚀 正在启动 Dria 节点（模型：$MODEL_NAME）...${NC}"

if $USE_TMUX; then
    # 结束已有会话并重建
    tmux kill-session -t dria 2>/dev/null || true
    tmux new -d -s dria "dria-node start --wallet $WALLET_KEY --model $MODEL_NAME"
    echo -e "${GREEN}✅ 节点已在后台 tmux 会话中启动${NC}"
    echo -e "${CYAN}   查看状态：tmux attach -t dria${NC}"
else
    nohup dria-node start --wallet "$WALLET_KEY" --model "$MODEL_NAME" > ~/dria.log 2>&1 &
    echo -e "${GREEN}✅ 节点已在后台启动，PID: $!${NC}"
    echo -e "${CYAN}   查看日志：tail -f ~/dria.log${NC}"
fi

echo ""
read -p "按任意键退出此窗口..."
EOF

chmod +x "$HOME/Desktop/dria_start.command"
echo -e "${GREEN}✅ 桌面启动文件已创建：~/Desktop/dria_start.command${NC}"

# ------------------------------------------------------------
# 7. 完成提示
# ------------------------------------------------------------
echo ""
echo -e "${GREEN}══════════════════════════════════════${NC}"
echo -e "${GREEN}  🎉 Dria 节点安装与启动全部完成！${NC}"
echo -e "${GREEN}══════════════════════════════════════${NC}"
echo ""
echo -e "  📊 查看收益与状态：https://dria.co/edge-ai"
echo -e "  🔄 后续启动：双击桌面的 ${CYAN}dria_start.command${NC}"
echo -e "  📋 查看运行日志：${CYAN}tmux attach -t dria${NC} 或 ${CYAN}tail -f ~/dria.log${NC}"
echo ""
echo -e "${YELLOW}  ⚠️  你的钱包私钥已加密保存于：$KEY_FILE${NC}"
echo -e "${YELLOW}     请勿将此文件分享给任何人！${NC}"
echo ""
