#!/bin/bash

# =============================================
#  Dria Node 一键安装、配置与启动脚本 (视觉增强版)
#  适用于 macOS Apple Silicon
# =============================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m'

# 密钥和模型文件路径
KEY_FILE="$HOME/.dria/wallet.key"
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
# 5. 生成炫酷的桌面启动脚本
# ------------------------------------------------------------
echo ""
echo -e "${BLUE}📝 正在创建炫酷的桌面启动文件...${NC}"

cat > "$HOME/Desktop/dria_start.command" <<'DESKTOPEOF'
#!/bin/bash

# ╔══════════════════════════════════════════╗
# ║     Dria Node 可视化监控启动器          ║
# ╚══════════════════════════════════════════╝

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m'

KEY_FILE="$HOME/.dria/wallet.key"
MODEL_FILE="$HOME/.dria/current_model"

# 清理屏幕
clear

# 显示炫酷标题
echo -e "${MAGENTA}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║                                                          ║"
echo "║     ██████╗ ██████╗ ██╗ █████╗                           ║"
echo "║     ██╔══██╗██╔══██╗██║██╔══██╗   Dria Compute Node      ║"
echo "║     ██║  ██║██████╔╝██║███████║                          ║"
echo "║     ██║  ██║██╔══██╗██║██╔══██║   ⚡ Edge AI Network      ║"
echo "║     ██████╔╝██║  ██║██║██║  ██║                          ║"
echo "║     ╚═════╝ ╚═╝  ╚═╝╚═╝╚═╝  ╚═╝                          ║"
echo "║                                                          ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
sleep 1

# 检查 tmux
if ! command -v tmux &> /dev/null; then
    echo -e "${RED}❌ 需要 tmux 才能使用可视化监控，正在尝试安装...${NC}"
    if command -v brew &> /dev/null; then
        brew install tmux
    else
        echo -e "${RED}未找到 Homebrew，请手动安装 tmux 后重试${NC}"
        read -p "按任意键退出..."
        exit 1
    fi
fi

# 检查必要文件
if [ ! -f "$KEY_FILE" ]; then
    echo -e "${RED}❌ 未找到私钥文件，请先运行安装脚本${NC}"
    read -p "按任意键退出..."
    exit 1
fi

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

WALLET_KEY=$(cat "$KEY_FILE")

# 结束旧会话
tmux kill-session -t dria 2>/dev/null || true

# 创建新的 tmux 会话，并运行定制的监控界面
tmux new -s dria -d bash -c "
    # 在 tmux 内部再次设置颜色
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    MAGENTA='\033[0;35m'
    WHITE='\033[1;37m'
    NC='\033[0m'
    
    # 清屏
    clear
    
    # 显示启动横幅
    echo -e \"\${MAGENTA}╔══════════════════════════════════════════════════════════╗\"
    echo -e \"║  Dria Node 正在启动...                                  ║\"
    echo -e \"║  模型: $MODEL_NAME                                      ║\"
    echo -e \"║  时间: \$(date '+%Y-%m-%d %H:%M:%S')                      ║\"
    echo -e \"╚══════════════════════════════════════════════════════════╝\${NC}\"
    echo \"\"
    
    # 启动节点，并将输出加上时间戳和颜色
    dria-node start --wallet $WALLET_KEY --model $MODEL_NAME 2>&1 | while IFS= read -r line; do
        # 获取当前时间戳
        timestamp=\$(date '+%H:%M:%S')
        
        # 根据日志级别添加颜色
        if echo \"\$line\" | grep -q 'ERROR'; then
            echo -e \"\${RED}[\$timestamp]\${NC} \$line\"
        elif echo \"\$line\" | grep -q 'WARN'; then
            echo -e \"\${YELLOW}[\$timestamp]\${NC} \$line\"
        elif echo \"\$line\" | grep -q 'INFO'; then
            echo -e \"\${GREEN}[\$timestamp]\${NC} \$line\"
        elif echo \"\$line\" | grep -q 'DEBUG'; then
            echo -e \"\${CYAN}[\$timestamp]\${NC} \$line\"
        else
            echo -e \"\${WHITE}[\$timestamp]\${NC} \$line\"
        fi
    done
"

# 自动连接至 tmux 会话，展示日志
echo -e "${GREEN}正在连接实时监控界面...${NC}"
sleep 1
tmux attach -t dria
DESKTOPEOF

chmod +x "$HOME/Desktop/dria_start.command"
echo -e "${GREEN}✅ 炫酷桌面启动文件已创建：~/Desktop/dria_start.command${NC}"

# ------------------------------------------------------------
# 6. 完成提示
# ------------------------------------------------------------
echo ""
echo -e "${GREEN}══════════════════════════════════════════════${NC}"
echo -e "${GREEN}  🎉 Dria 节点安装完成！${NC}"
echo -e "${GREEN}══════════════════════════════════════════════${NC}"
echo ""
echo -e "  🖥️  启动节点：双击桌面的 ${CYAN}dria_start.command${NC}"
echo -e "      (将自动显示彩色实时监控界面)"
echo -e "  📊 查看收益：${CYAN}https://dria.co/edge-ai${NC}"
echo -e "  🔐 私钥文件：${CYAN}$KEY_FILE${NC}"
echo -e "     ${YELLOW}请勿分享此文件！${NC}"
echo ""
echo -e "${YELLOW}  提示：在监控界面中，按 Ctrl+B 然后按 D 可以隐藏在后台运行。${NC}"
echo ""
