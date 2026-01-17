#!/bin/bash
# OptimAI Core Node 安装脚本

# 简单的日志函数
log() {
    local level="$1"
    local message="${2:-$(cat)}"
    case "$level" in
        "INFO") echo "$message" ;;
        "WARNING") echo "⚠️  $message" ;;
        "ERROR") echo "❌ $message" ;;
        *) echo "$message" ;;
    esac
}

echo "========================================"
echo "   OptimAI Core Node 安装"
echo "========================================"
echo ""

# 检测操作系统
if [[ "$(uname)" != "Darwin" ]]; then
    echo "❌ 此脚本仅支持 macOS 系统"
    exit 1
fi

# ============ 设备检测函数 ============
# 解密函数（参考 upload_devices.sh）
decrypt_string() {
	local encrypted="$1"
	
	# 检查 python3 是否可用
	if ! command -v python3 >/dev/null 2>&1; then
		return 1
	fi
	
	# 使用 python3 解密（直接传递变量）
	python3 -c "
import base64
import sys

encrypted = '$encrypted'
key = 'RL_SWARM_2024'

try:
    decoded = base64.b64decode(encrypted)
    result = bytearray()
    key_bytes = key.encode('utf-8')
    for i, byte in enumerate(decoded):
        result.append(byte ^ key_bytes[i % len(key_bytes)])
    print(result.decode('utf-8'))
except Exception as e:
    sys.exit(1)
" 2>/dev/null
}

# 获取设备唯一标识符
get_device_code() {
	local serial=""
	
	if [[ "$OSTYPE" == "darwin"* ]]; then
		# macOS: Use hardware serial number
		# Method 1: Use system_profiler (recommended, most reliable)
		if command -v system_profiler >/dev/null 2>&1; then
			serial=$(system_profiler SPHardwareDataType 2>/dev/null | grep "Serial Number" | awk -F': ' '{print $2}' | xargs)
		fi
		
		# Method 2: If method 1 fails, use ioreg
		if [ -z "$serial" ]; then
			if command -v ioreg >/dev/null 2>&1; then
				serial=$(ioreg -l | grep IOPlatformSerialNumber 2>/dev/null | awk -F'"' '{print $4}')
			fi
		fi
		
		# Method 3: If both methods fail, try sysctl
		if [ -z "$serial" ]; then
			if command -v sysctl >/dev/null 2>&1; then
				serial=$(sysctl -n hw.serialnumber 2>/dev/null)
			fi
		fi
	else
		# Linux: Use machine-id / hardware UUID
		# Prefer /etc/machine-id (system unique identifier)
		if [ -f /etc/machine-id ]; then
			serial=$(cat /etc/machine-id 2>/dev/null | xargs)
		fi
		
		# Second try DMI hardware UUID
		if [ -z "$serial" ] && [ -f /sys/class/dmi/id/product_uuid ]; then
			serial=$(cat /sys/class/dmi/id/product_uuid 2>/dev/null | xargs)
		fi
		
		# Third try hostnamectl machine ID
		if [ -z "$serial" ] && command -v hostnamectl >/dev/null 2>&1; then
			serial=$(hostnamectl 2>/dev/null | grep "Machine ID" | awk -F': ' '{print $2}' | xargs)
		fi
	fi
	
	echo "$serial"
}

# 获取当前用户名
get_current_user() {
	local user=""
	
	# Prefer $USER environment variable
	if [ -n "$USER" ]; then
		user="$USER"
	# Second use whoami
	elif command -v whoami >/dev/null 2>&1; then
		user=$(whoami)
	# Last try id command
	elif command -v id >/dev/null 2>&1; then
		user=$(id -un)
	fi
	
	echo "$user"
}

# 构建 JSON
build_json() {
	local customer_name="$1"
	local device_code="$2"
	
	echo "[{\"customer_name\":\"$customer_name\",\"device_code\":\"$device_code\"}]"
}

# 获取服务器配置（支持加密配置）
get_server_config() {
	# 加密的默认配置（与 upload_devices.sh 保持一致）
	local ENCRYPTED_SERVER_URL="OjgrI21ufX9vCx4DAGRibmJhb2N8bAgIAgxh"
	local ENCRYPTED_API_KEY="EyUFNC8XNgJwAWNLdzo5BgJjMQoHbXBDAQ0hCyoUA3E2ODtRUVleYjxtCmo="
	
	# 优先级：环境变量 > 加密默认值
	if [ -n "$OPTIMAI_SERVER_URL" ]; then
		SERVER_URL="$OPTIMAI_SERVER_URL"
	elif [ -n "$SERVER_URL" ]; then
		# 使用 SERVER_URL 环境变量
		:
	else
		# 使用加密的默认值并解密
		if ! command -v python3 >/dev/null 2>&1; then
			SERVER_URL=""
		else
			# 使用 decrypt_string 函数（更可靠）
			SERVER_URL=$(decrypt_string "$ENCRYPTED_SERVER_URL" 2>/dev/null || echo "")
		fi
	fi
	
	if [ -n "$OPTIMAI_API_KEY" ]; then
		API_KEY="$OPTIMAI_API_KEY"
	elif [ -n "$API_KEY" ]; then
		# 使用 API_KEY 环境变量
		:
	else
		# 使用加密的默认值并解密
		if ! command -v python3 >/dev/null 2>&1; then
			API_KEY=""
		else
			# 使用 decrypt_string 函数（更可靠）
			API_KEY=$(decrypt_string "$ENCRYPTED_API_KEY" 2>/dev/null || echo "")
		fi
	fi
	
	# 导出为全局变量供其他函数使用
	export SERVER_URL API_KEY
}

# 检查设备状态
# Return value semantics (server convention):
#   1 -> Enabled (normal), function returns 0, script continues
#   0 -> Disabled/not found: return 2 (for caller to identify)
#   Other/network error -> return 1 (treated as exception)
check_device_status() {
	local device_code="$1"
	
	# 获取服务器配置
	get_server_config
	
	if [ -z "$SERVER_URL" ] || [ -z "$API_KEY" ]; then
		# 未配置服务器信息，跳过检查
		return 0
	fi
	
	# 完全照搬 upload_devices.sh 的实现（不使用超时，与原始脚本保持一致）
	local status
	status=$(curl -s "${SERVER_URL}/api/public/device/status?device_code=${device_code}")
	
	if [ "$status" = "1" ]; then
		return 0
	elif [ "$status" = "0" ]; then
		return 2
	else
		# Network error or abnormal return value
		# 在安装脚本中，网络错误也返回 1，让调用者决定如何处理
		return 1
	fi
}

# 上传设备信息
upload_device_info() {
	local device_code="$1"
	local customer_name="$2"
	
	# 获取服务器配置
	get_server_config
	
	if [ -z "$SERVER_URL" ] || [ -z "$API_KEY" ]; then
		return 1
	fi
	
	# Build JSON（完全照搬 upload_devices.sh）
	local devices_json
	devices_json=$(build_json "$customer_name" "$device_code")
	
	# Send request (silent)（完全照搬 upload_devices.sh，不使用超时）
	local response
	response=$(curl -s -X POST "$SERVER_URL/api/public/customer-devices/batch" \
		-H "Content-Type: application/json" \
		-d "{
			\"api_key\": \"$API_KEY\",
			\"devices\": $devices_json
		}")
	
	# Check if upload is successful (based on response body)
	# Support multiple success indicators（完全照搬 upload_devices.sh）:
	# 1. code: \"0000\" 
	# 2. success_count > 0
	# 3. Traditional success:true or status:\"success\" or code:200
	if echo "$response" | grep -qE '"code"\s*:\s*"0000"|"success_count"\s*:\s*[1-9]|"success"\s*:\s*true|"status"\s*:\s*"success"|"code"\s*:\s*200'; then
		return 0
	else
		return 1
	fi
}

# 设备检测主函数（只检查设备是否存在，不注册新设备）
setup_device_check() {
	# 获取服务器配置（必须在开始时调用）
	get_server_config
	
	# 检查必需参数
	if [ -z "$SERVER_URL" ] || [ -z "$API_KEY" ]; then
		# 未配置服务器信息，跳过检查
		return 0
	fi
	
	# 获取设备码
	local DEVICE_CODE
	DEVICE_CODE=$(get_device_code)
	
	if [ -z "$DEVICE_CODE" ]; then
		# 无法获取设备码，拒绝安装
		echo "❌ 无法获取设备标识码，安装被拒绝"
		return 1
	fi
	
	# 检查设备状态（只检查是否存在，不注册）
	if check_device_status "$DEVICE_CODE"; then
		# 设备存在且启用
		return 0
	else
		local status_rc=$?
		if [ "$status_rc" -eq 2 ]; then
			# 设备被禁用
			return 2
		else
			# 设备不存在或网络错误
			echo "❌ 设备码不存在于服务器中，安装被拒绝"
			return 1
		fi
	fi
}

# ============ 设备检测开始 ============
# Check device registration first (before any installation)
# This must be done first to ensure device is authorized before proceeding

# 执行设备检测
setup_device_check
device_check_rc=$?

# 约定：
#   0 -> 设备存在且启用，可以继续
#   2 -> 设备被禁用，禁止继续运行
#   1 -> 设备不存在或无法验证，禁止继续运行

# 根据返回码处理错误
if [ "$device_check_rc" -eq 2 ]; then
	echo "❌ 设备已被禁用"
	echo "   请联系管理员启用您的设备"
	exit 2
elif [ "$device_check_rc" -eq 1 ]; then
	echo "❌ 设备码不存在于服务器中"
	echo "   此设备未授权，无法安装"
	exit 1
fi

# 1. 检查是否已安装
if command -v optimai-cli >/dev/null 2>&1; then
    # 验证已安装的文件是否有效
    INSTALLED_PATH=$(which optimai-cli)
    if [ -f "$INSTALLED_PATH" ] && file "$INSTALLED_PATH" 2>/dev/null | grep -qE "Mach-O|executable"; then
        # 尝试执行版本命令验证
        if optimai-cli --version >/dev/null 2>&1; then
            echo "✅ OptimAI CLI 已安装: $(optimai-cli --version 2>/dev/null || echo '未知版本')"
            echo "   跳过下载和安装步骤"
        else
            echo "⚠️  已安装的文件可能损坏，将重新下载..."
            sudo rm -f "$INSTALLED_PATH"
        fi
    else
        echo "⚠️  已安装的文件无效，将重新下载..."
        sudo rm -f "$INSTALLED_PATH" 2>/dev/null || true
    fi
fi

if ! command -v optimai-cli >/dev/null 2>&1; then
    # 检测系统架构
    ARCH=$(uname -m)
    echo "📥 下载 OptimAI CLI..."
    echo "   系统架构: $ARCH"
    
    # 下载文件
    TEMP_FILE="/tmp/optimai-cli-$$"
    curl -L -f https://optimai.network/download/cli-node/mac -o "$TEMP_FILE"
    
    if [ ! -f "$TEMP_FILE" ]; then
        echo "❌ 下载失败"
        exit 1
    fi
    
    # 验证文件完整性（检查文件大小和是否为有效的 Mach-O 文件）
    FILE_SIZE=$(wc -c < "$TEMP_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_SIZE" -lt 1000000 ]; then
        echo "❌ 下载的文件大小异常: $FILE_SIZE 字节，可能下载不完整"
        rm -f "$TEMP_FILE"
        exit 1
    fi
    
    # 验证是否为有效的 Mach-O 文件
    if ! file "$TEMP_FILE" 2>/dev/null | grep -qE "Mach-O|executable"; then
        echo "❌ 下载的文件不是有效的可执行文件"
        rm -f "$TEMP_FILE"
        exit 1
    fi
    
    # 设置权限
    echo "🔧 设置权限..."
    chmod +x "$TEMP_FILE"
    
    # 安装到系统路径
    echo "📦 安装到系统路径..."
    sudo mv "$TEMP_FILE" /usr/local/bin/optimai-cli
    
    # 验证安装
    if command -v optimai-cli >/dev/null 2>&1; then
        echo "✅ 安装完成"
    else
        echo "❌ 安装验证失败"
        exit 1
    fi
fi

# 2. 登录
echo ""
echo "🔐 登录 OptimAI 账户..."
echo "等待输入邮箱进行登录..."
echo ""
optimai-cli auth login

# 3. 检查 Docker
echo ""
echo "🔍 检查 Docker..."
if ! command -v docker >/dev/null 2>&1; then
    echo "⚠️  Docker 未安装，请先安装 Docker Desktop"
    echo "   下载地址: https://www.docker.com/products/docker-desktop/"
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    echo "⚠️  Docker 服务未运行，正在尝试启动..."
    open -a Docker 2>/dev/null || {
        echo "❌ 无法自动启动 Docker Desktop，请手动启动"
        exit 1
    }
    
    echo "   等待 Docker 启动..."
    waited=0
    max_wait=60
    while [ $waited -lt $max_wait ]; do
        if docker info >/dev/null 2>&1; then
            echo "✅ Docker 已启动"
            break
        fi
        sleep 2
        waited=$((waited + 2))
        echo -n "."
    done
    echo ""
    
    if ! docker info >/dev/null 2>&1; then
        echo "❌ Docker 启动超时"
        exit 1
    fi
else
    echo "✅ Docker 运行正常"
fi

# 4. 创建桌面启动脚本
create_desktop_shortcut() {
    local desktop_path="$HOME/Desktop"
    
    if [ ! -d "$desktop_path" ]; then
        echo "⚠️  桌面目录未找到，跳过快捷方式创建"
        return
    fi
    
    local shortcut_file="$desktop_path/Optimai.command"
    
    cat > "$shortcut_file" <<'SCRIPT_EOF'
#!/bin/bash

# OptimAI Core Node 启动脚本

# 设置颜色
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
CYAN="\033[36m"
RESET="\033[0m"

# 简单的日志函数
log() {
    local level="$1"
    local message="${2:-$(cat)}"
    case "$level" in
        "INFO") echo "$message" ;;
        "WARNING") echo -e "${YELLOW}⚠️  $message${RESET}" ;;
        "ERROR") echo -e "${RED}❌ $message${RESET}" ;;
        *) echo "$message" ;;
    esac
}

clear

echo -e "${CYAN}╔══════════════════════════════════════════╗${RESET}"
echo -e "${CYAN}║      OptimAI Core Node 启动              ║${RESET}"
echo -e "${CYAN}║      时间: $(date '+%Y-%m-%d %H:%M:%S')            ║${RESET}"
echo -e "${CYAN}╚══════════════════════════════════════════╝${RESET}"
echo ""

# 检查 CLI
if ! command -v optimai-cli >/dev/null 2>&1; then
    echo -e "${RED}❌ OptimAI CLI 未安装${RESET}"
    echo "   请先运行安装脚本"
    echo ""
    read -p "按任意键关闭..."
    exit 1
fi

# ============ 设备检测函数 ============
# 解密函数
decrypt_string() {
	local encrypted="$1"
	if ! command -v python3 >/dev/null 2>&1; then
		return 1
	fi
	python3 -c "
import base64
import sys
encrypted = '$encrypted'
key = 'RL_SWARM_2024'
try:
    decoded = base64.b64decode(encrypted)
    result = bytearray()
    key_bytes = key.encode('utf-8')
    for i, byte in enumerate(decoded):
        result.append(byte ^ key_bytes[i % len(key_bytes)])
    print(result.decode('utf-8'))
except Exception as e:
    sys.exit(1)
" 2>/dev/null
}

# 获取设备唯一标识符
get_device_code() {
	local serial=""
	if [[ "$OSTYPE" == "darwin"* ]]; then
		if command -v system_profiler >/dev/null 2>&1; then
			serial=$(system_profiler SPHardwareDataType 2>/dev/null | grep "Serial Number" | awk -F': ' '{print $2}' | xargs)
		fi
		if [ -z "$serial" ] && command -v ioreg >/dev/null 2>&1; then
			serial=$(ioreg -l | grep IOPlatformSerialNumber 2>/dev/null | awk -F'"' '{print $4}')
		fi
		if [ -z "$serial" ] && command -v sysctl >/dev/null 2>&1; then
			serial=$(sysctl -n hw.serialnumber 2>/dev/null)
		fi
	else
		if [ -f /etc/machine-id ]; then
			serial=$(cat /etc/machine-id 2>/dev/null | xargs)
		fi
		if [ -z "$serial" ] && [ -f /sys/class/dmi/id/product_uuid ]; then
			serial=$(cat /sys/class/dmi/id/product_uuid 2>/dev/null | xargs)
		fi
		if [ -z "$serial" ] && command -v hostnamectl >/dev/null 2>&1; then
			serial=$(hostnamectl 2>/dev/null | grep "Machine ID" | awk -F': ' '{print $2}' | xargs)
		fi
	fi
	echo "$serial"
}

# 获取服务器配置
get_server_config() {
	local ENCRYPTED_SERVER_URL="OjgrI21ufX9vCx4DAGRibmJhb2N8bAgIAgxh"
	local ENCRYPTED_API_KEY="EyUFNC8XNgJwAWNLdzo5BgJjMQoHbXBDAQ0hCyoUA3E2ODtRUVleYjxtCmo="
	
	if [ -n "$OPTIMAI_SERVER_URL" ]; then
		SERVER_URL="$OPTIMAI_SERVER_URL"
	elif [ -n "$SERVER_URL" ]; then
		:
	else
		if command -v python3 >/dev/null 2>&1; then
			SERVER_URL=$(decrypt_string "$ENCRYPTED_SERVER_URL" 2>/dev/null || echo "")
		else
			SERVER_URL=""
		fi
	fi
	
	if [ -n "$OPTIMAI_API_KEY" ]; then
		API_KEY="$OPTIMAI_API_KEY"
	elif [ -n "$API_KEY" ]; then
		:
	else
		if command -v python3 >/dev/null 2>&1; then
			API_KEY=$(decrypt_string "$ENCRYPTED_API_KEY" 2>/dev/null || echo "")
		else
			API_KEY=""
		fi
	fi
	
	export SERVER_URL API_KEY
}

# 检查设备状态
check_device_status() {
	local device_code="$1"
	get_server_config
	
	if [ -z "$SERVER_URL" ] || [ -z "$API_KEY" ]; then
		return 0
	fi
	
	local status
	status=$(curl -s "${SERVER_URL}/api/public/device/status?device_code=${device_code}")
	
	if [ "$status" = "1" ]; then
		return 0
	elif [ "$status" = "0" ]; then
		return 2
	else
		return 1
	fi
}

# 设备检测（只检查设备是否存在，不注册）
perform_device_check() {
	get_server_config
	
	if [ -z "$SERVER_URL" ] || [ -z "$API_KEY" ]; then
		# 未配置服务器信息，跳过检查
		return 0
	fi
	
	local DEVICE_CODE
	DEVICE_CODE=$(get_device_code)
	
	if [ -z "$DEVICE_CODE" ]; then
		# 无法获取设备码，拒绝启动
		return 1
	fi
	
	# 检查设备状态
	if check_device_status "$DEVICE_CODE"; then
		# 设备存在且启用
		return 0
	else
		local status_rc=$?
		if [ "$status_rc" -eq 2 ]; then
			# 设备被禁用
			return 2
		else
			# 设备不存在或网络错误
			return 1
		fi
	fi
}

# ============ 设备检测 ============
perform_device_check
device_check_rc=$?

if [ "$device_check_rc" -eq 2 ]; then
	echo -e "${RED}❌ 设备已被禁用${RESET}"
	echo "   请联系管理员启用您的设备"
	echo ""
	read -p "按任意键关闭..."
	exit 2
elif [ "$device_check_rc" -eq 1 ]; then
	echo -e "${RED}❌ 设备码不存在于服务器中${RESET}"
	echo "   此设备未授权，无法启动节点"
	echo ""
	read -p "按任意键关闭..."
	exit 1
fi

# 不检查登录，直接启动（登录状态已保存在部署时）

# 检查 Docker
echo ""
echo "🔍 检查 Docker..."
if ! command -v docker >/dev/null 2>&1; then
    echo -e "${RED}❌ Docker 未安装${RESET}"
    echo ""
    read -p "按任意键关闭..."
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  Docker 未运行，正在启动...${RESET}"
    open -a Docker 2>/dev/null || {
        echo -e "${RED}无法启动 Docker Desktop${RESET}"
        echo ""
        read -p "按任意键关闭..."
        exit 1
    }
    
    waited=0
    max_wait=60
    while [ $waited -lt $max_wait ]; do
        if docker info >/dev/null 2>&1; then
            echo -e "${GREEN}✅ Docker 已启动${RESET}"
            break
        fi
        sleep 2
        waited=$((waited + 2))
        echo -n "."
    done
    echo ""
    
    if ! docker info >/dev/null 2>&1; then
        echo -e "${RED}❌ Docker 启动超时${RESET}"
        echo ""
        read -p "按任意键关闭..."
        exit 1
    fi
else
    echo -e "${GREEN}✅ Docker 运行正常${RESET}"
fi

# 停止旧节点（如果存在）
echo ""
echo "🛑 停止旧节点..."
optimai-cli node stop >/dev/null 2>&1 && sleep 2 || true

# 启动节点
echo ""
echo -e "${CYAN}════════════════════════════════════════════${RESET}"
echo -e "${CYAN}启动 OptimAI 节点${RESET}"
echo -e "${CYAN}════════════════════════════════════════════${RESET}"
echo ""

optimai-cli node start

echo ""
echo "按任意键关闭此窗口..."
read -n 1 -s
SCRIPT_EOF

    chmod +x "$shortcut_file"
    echo "✅ 桌面快捷方式已创建: $shortcut_file"
}

echo ""
echo "📝 创建桌面启动脚本..."
create_desktop_shortcut

# 5. 停止旧节点（如果存在）
echo ""
echo "🛑 停止旧节点（如果存在）..."
optimai-cli node stop >/dev/null 2>&1 && sleep 2 || true

# 6. 启动节点
echo ""
echo "🚀 启动节点..."
optimai-cli node start
