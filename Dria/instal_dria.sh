#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 开始安装 Dria 节点（新版 dria-node）...${NC}"

# ------------------------------------------------------------
# 1. 清理旧版本（如果存在）
# ------------------------------------------------------------
if [ -d "$HOME/.dria" ] || [ -f "$HOME/Desktop/dria_start.command" ]; then
    echo -e "${YELLOW}⚠️  检测到旧版 Dria 文件，正在清理...${NC}"
    rm -rf "$HOME/.dria"
    rm -f "$HOME/Desktop/dria_start.command"
    echo -e "${GREEN}✅ 旧版文件已清理。${NC}"
fi

# ------------------------------------------------------------
# 2. 系统环境建议（证书问题通常由时间引起）
# ------------------------------------------------------------
echo -e "${BLUE}🕒 请确保系统时间已设为自动同步，以避免 SSL 证书错误。${NC}"
echo -e "${BLUE}   如遇证书问题，请前往：系统设置 > 通用 > 日期与时间，开启自动设置。${NC}"

# ------------------------------------------------------------
# 3. 安装新版 dria-node
# ------------------------------------------------------------
if command -v dria-node &> /dev/null; then
    echo -e "${GREEN}✅ dria-node 已安装，跳过安装步骤。${NC}"
else
    echo -e "${BLUE}📥 正在下载并安装 dria-node...${NC}"
    curl -fsSL https://raw.githubusercontent.com/firstbatchxyz/dkn-compute-node/master/install.sh | bash
    
    if [ $? -eq 0 ]; then
        # 将安装路径加入 PATH（某些 shell 可能需要）
        export PATH="$HOME/.dria/bin:$PATH"
        echo -e "${GREEN}✅ dria-node 安装完成！${NC}"
    else
        echo -e "${RED}❌ dria-node 安装失败，请检查网络后重试。${NC}"
        exit 1
    fi
fi

# ------------------------------------------------------------
# 4. 后续设置指引
# ------------------------------------------------------------
echo ""
echo -e "${YELLOW}🔰 接下来请完成节点初始化设置：${NC}"
echo -e "   在新的终端窗口中运行以下命令："
echo -e "   ${GREEN}dria-node setup${NC}"
echo -e "   根据提示输入你的钱包私钥、选择模型并设置参数。"
echo ""
echo -e "   完成设置后，可以用以下命令启动节点："
echo -e "   ${GREEN}dria-node start${NC}"
echo ""

# 等待用户按回车继续
read -p "📝 完成上述 setup 步骤后，按回车键继续生成桌面启动文件... "

# ------------------------------------------------------------
# 5. 生成桌面一键启动脚本
# ------------------------------------------------------------
echo -e "${BLUE}📝 正在生成桌面启动文件...${NC}"
cat > "$HOME/Desktop/dria_start.command" <<'EOF'
#!/bin/bash

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}🚀 启动 Dria 计算节点...${NC}"

# 检查 dria-node 是否可用
if ! command -v dria-node &> /dev/null; then
    # 尝试补全路径
    if [ -f "$HOME/.dria/bin/dria-node" ]; then
        export PATH="$HOME/.dria/bin:$PATH"
    else
        echo -e "${RED}❌ 找不到 dria-node 命令，请确认安装是否成功。${NC}"
        read -p "按任意键退出..."
        exit 1
    fi
fi

# 检查是否已完成 setup（配置文件是否存在）
if [ ! -f "$HOME/.dria/config.toml" ] && [ ! -f "$HOME/.dria/config.json" ]; then
    echo -e "${YELLOW}⚠️  未检测到节点配置文件，请先运行 'dria-node setup' 完成初始化。${NC}"
    read -p "按任意键退出..."
    exit 1
fi

# 启动节点
echo -e "${BLUE}📡 正在启动节点...${NC}"
dria-node start

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ 节点启动失败，请检查之前的错误信息。${NC}"
    read -p "按任意键退出..."
fi
EOF

chmod +x "$HOME/Desktop/dria_start.command"
echo -e "${GREEN}✅ 桌面启动文件已创建：~/Desktop/dria_start.command${NC}"

# ------------------------------------------------------------
# 6. 安装完成提示
# ------------------------------------------------------------
echo ""
echo -e "${GREEN}🎉 安装和配置全部完成！${NC}"
echo -e "   现在你可以："
echo -e "   1. 双击桌面上的 ${GREEN}dria_start.command${NC} 启动节点。"
echo -e "   2. 或在终端随时运行 ${GREEN}dria-node start${NC}。"
echo -e "   如需查看节点状态，请访问：https://dria.co/edge-ai"
echo ""
