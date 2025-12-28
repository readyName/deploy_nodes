#!/usr/bin/env bash
# shellcheck disable=SC2155,SC2181

IMAGE_TAG='ghcr.io/tashigg/tashi-depin-worker:0'

TROUBLESHOOT_LINK='https://docs.tashi.network/nodes/node-installation/important-notes#troubleshooting'
MANUAL_UPDATE_LINK='https://docs.tashi.network/nodes/node-installation/important-notes#manual-update'

DOCKER_ROOTLESS_LINK='https://docs.docker.com/engine/install/linux-postinstall/'
PODMAN_ROOTLESS_LINK='https://github.com/containers/podman/blob/main/docs/tutorials/rootless_tutorial.md'

RUST_LOG='info,tashi_depin_worker=debug,tashi_depin_common=debug'

AGENT_PORT=39065

# Color codes
GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
RESET="\e[0m"
CHECKMARK="${GREEN}✓${RESET}"
CROSSMARK="${RED}✗${RESET}"
WARNING="${YELLOW}⚠${RESET}"

STYLE_BOLD=$(tput bold)
STYLE_NORMAL=$(tput sgr0)

WARNINGS=0
ERRORS=0

# Logging function (with level and timestamps if `LOG_EXPANDED` is set to a truthy value)
log() {
	# Allow the message to be piped for heredocs
	local message="${2:-$(cat)}"

	if [[ "${LOG_EXPANDED:-0}" -ne 0 ]]; then
		local level="$1"
		local timestamp=$(date +"%Y-%m-%d %H:%M:%S")

		printf "[%s] [%s] %b\n" "${timestamp}" "${level}" "${message}" 1>&2
	else
		printf "%b\n" "$message"
	fi
}

make_bold() {
	# Allows heredoc expansion with pipes
	local s="${1:-$(cat)}"

	printf "%s%s%s" "$STYLE_BOLD" "${s}" "$STYLE_NORMAL"
}

# Print a blank line for visual separation.
horizontal_line() {
	WIDTH=${COLUMNS:-$(tput cols)}
	FILL_CHAR='-'

	# Prints a zero-length string but specifies it should be `$COLUMNS` wide, so the `printf` command pads it with blanks.
	# We then use `tr` to replace those blanks with our padding character of choice.
	printf '\n%*s\n\n' "$WIDTH" '' | tr ' ' "$FILL_CHAR"
}

# munch args
POSITIONAL_ARGS=()

SUBCOMMAND=install

while [[ $# -gt 0 ]]; do
	case $1 in
		--ignore-warnings)
			IGNORE_WARNINGS=y
			;;
		-y | --yes)
			YES=1
			;;
		--auto-update)
			AUTO_UPDATE=y
			;;
		--image-tag=*)
			IMAGE_TAG="${1#"--image-tag="}"
			;;
		--install)
			SUBCOMMAND=install
			;;
		--update)
			SUBCOMMAND=update
			;;
		-*)
			echo "Unknown option $1"
			exit 1
			;;
		*)
			POSITIONAL_ARGS+=("$1")
			;;
	esac

	shift
done

set -- "${POSITIONAL_ARGS[@]}" # restore positional parameters

# Detect OS safely
detect_os() {
	OS=$(
		# shellcheck disable=SC1091
		source /etc/os-release >/dev/null 2>&1
		echo "${ID:-unknown}"
	)
	if [[ "$OS" == "unknown" && "$(uname -s)" == "Darwin" ]]; then
		OS="macos"
	fi
}

# Suggest package installation securely
suggest_install() {
	local package=$1
	case "$OS" in
		debian | ubuntu) echo "    sudo apt update && sudo apt install -y $package" ;;
		fedora) echo "    sudo dnf install -y $package" ;;
		arch) echo "    sudo pacman -S --noconfirm $package" ;;
		opensuse) echo "    sudo zypper install -y $package" ;;
		macos) echo "    brew install $package" ;;
		*) echo "    Please install '$package' manually for your OS." ;;
	esac
}

# Resolve commands dynamically
NPROC_CMD=$(command -v nproc || echo "")
GREP_CMD=$(command -v grep || echo "")
DF_CMD=$(command -v df || echo "")

# Check if a command exists
check_command() {
	command -v "$1" >/dev/null 2>&1
}

# Platform Check
check_platform() {
	PLATFORM_ARG=''

	local arch=$(uname -m)

	# Bash on MacOS doesn't support `@(pattern-list)` apparently?
	if [[ "$arch" == "amd64" || "$arch" == "x86_64" ]]; then
		log "INFO" "Platform Check: ${CHECKMARK} supported platform $arch"
	elif [[ "$OS" == "macos" && "$arch" == arm64 ]]; then
		# Ensure Apple Silicon runs the container as x86_64 using Rosetta
		PLATFORM_ARG='--platform linux/amd64'

		log "WARNING" "Platform Check: ${WARNING} unsupported platform $arch"
		log "INFO" <<-EOF
			MacOS Apple Silicon is not currently supported, but the worker can still run through the Rosetta compatibility layer.
			Performance and earnings will be less than a native node.
			You may be prompted to install Rosetta when the worker node starts.
		EOF
		((WARNINGS++))
	else
		log "ERROR" "Platform Check: ${CROSSMARK} unsupported platform $arch"
		log "INFO" "Join the Tashi Discord to request support for your system."
		((ERRORS++))
		return
	fi
}

# CPU Check
check_cpu() {
	case "$OS" in
		"macos")
			threads=$(sysctl -n hw.ncpu)
			;;
		*)
			if [[ -z "$NPROC_CMD" ]]; then
				log "WARNING" "'nproc' not found. Install coreutils:"
				suggest_install "coreutils"
				((ERRORS++))
				return
			fi
			threads=$("$NPROC_CMD")
			;;
	esac

	if [[ "$threads" -ge 4 ]]; then
		log "INFO" "CPU Check: ${CHECKMARK} Found $threads threads (>= 4 recommended)"
	elif [[ "$threads" -ge 2 ]]; then
		log "WARNING" "CPU Check: ${WARNING} Found $threads threads (>= 2 required, 4 recommended)"
		((WARNINGS++))
	else
		log "ERROR" "CPU Check: ${CROSSMARK} Only $threads threads found (Minimum: 2 required)"
		((ERRORS++))
	fi
}

# Memory Check
check_memory() {
	if [[ -z "$GREP_CMD" ]]; then
		log "ERROR" "Memory Check: ${WARNING} 'grep' not found. Install grep:"
		suggest_install "grep"
		((ERRORS++))
		return
	fi

	case "$OS" in
		"macos")
			total_mem_bytes=$(sysctl -n hw.memsize)
			total_mem_kb=$((total_mem_bytes / 1024))
			;;
		*)
			total_mem_kb=$("$GREP_CMD" MemTotal /proc/meminfo | awk '{print $2}')
			;;
	esac

	total_mem_gb=$((total_mem_kb / 1024 / 1024))

	if [[ "$total_mem_gb" -ge 4 ]]; then
		log "INFO" "Memory Check: ${CHECKMARK} Found ${total_mem_gb}GB RAM (>= 4GB recommended)"
	elif [[ "$total_mem_gb" -ge 2 ]]; then
		log "WARNING" "Memory Check: ${WARNING} Found ${total_mem_gb}GB RAM (>= 2GB required, 4GB recommended)"
		((WARNINGS++))
	else
		log "ERROR" "Memory Check: ${CROSSMARK} Only ${total_mem_gb}GB RAM found (Minimum: 2GB required)"
		((ERRORS++))
	fi
}

# Disk Space Check
check_disk() {
	case "$OS" in
		"macos")
			available_disk_kb=$(
				"$DF_CMD" -kcI 2>/dev/null |
					tail -1 |
					awk '{print $4}'
			)
			total_mem_bytes=$(sysctl -n hw.memsize)
			;;
		*)
			available_disk_kb=$(
				"$DF_CMD" -kx tmpfs --total 2>/dev/null |
					tail -1 |
					awk '{print $4}'
			)
			;;
	esac

	available_disk_gb=$((available_disk_kb / 1024 / 1024))

	if [[ "$available_disk_gb" -ge 20 ]]; then
		log "INFO" "Disk Space Check: ${CHECKMARK} Found ${available_disk_gb}GB free (>= 20GB required)"
	else
		log "ERROR" "Disk Space Check: ${CROSSMARK} Only ${available_disk_gb}GB free space (Minimum: 20GB required)"
		((ERRORS++))
	fi
}

# Docker or Podman Check
check_container_runtime() {
	# 首先检测操作系统
	detect_os
	
	if check_command "docker"; then
		log "INFO" "Container Runtime Check: ${CHECKMARK} Docker is installed"
		CONTAINER_RT=docker
		
		# 检查 Docker 是否运行
		if docker info >/dev/null 2>&1; then
			log "INFO" "Docker Runtime Check: ${CHECKMARK} Docker is running"
		else
			log "WARNING" "Docker Runtime Check: ${WARNING} Docker is installed but not running"
			
			# 根据操作系统启动 Docker
			if [[ "$OS" == "macos" ]]; then
				log "INFO" "Attempting to start Docker Desktop..."
				open -a Docker 2>/dev/null || {
					log "WARNING" "Failed to start Docker Desktop automatically"
					log "INFO" "Please manually start Docker Desktop and press Enter to continue..."
					read -r
				}
				
				# 等待 Docker 启动
				log "INFO" "Waiting for Docker Desktop to start..."
				local waited=0
				local max_wait=60
				while [ $waited -lt $max_wait ]; do
					if docker info >/dev/null 2>&1; then
						log "INFO" "Docker Runtime Check: ${CHECKMARK} Docker is now running"
						break
					fi
					sleep 2
					waited=$((waited + 2))
					echo -n "."
				done
				echo ""
				
				if ! docker info >/dev/null 2>&1; then
					log "ERROR" "Docker Runtime Check: ${CROSSMARK} Docker failed to start after ${max_wait} seconds"
					log "INFO" "Please ensure Docker Desktop is running and try again"
					((ERRORS++))
				fi
			else
				# Linux 系统尝试启动 Docker 服务
				if command -v systemctl >/dev/null 2>&1; then
					log "INFO" "Attempting to start Docker service..."
					if sudo systemctl start docker 2>/dev/null; then
						sleep 3
						if docker info >/dev/null 2>&1; then
							log "INFO" "Docker Runtime Check: ${CHECKMARK} Docker is now running"
						else
							log "ERROR" "Docker Runtime Check: ${CROSSMARK} Docker service failed to start"
							((ERRORS++))
						fi
					else
						log "ERROR" "Docker Runtime Check: ${CROSSMARK} Failed to start Docker service"
						log "INFO" "Please manually start Docker service: sudo systemctl start docker"
						((ERRORS++))
					fi
				else
					log "ERROR" "Docker Runtime Check: ${CROSSMARK} Docker is not running and cannot be started automatically"
					((ERRORS++))
				fi
			fi
		fi
	elif check_command "podman"; then
		log "INFO" "Container Runtime Check: ${CHECKMARK} Podman is installed"
		CONTAINER_RT=podman
	else
		log "WARNING" "Container Runtime Check: ${WARNING} Neither Docker nor Podman is installed."
		
		# 尝试安装 Docker
		if [[ "$OS" == "macos" ]]; then
			# 检查 Homebrew 是否安装
			if ! check_command "brew"; then
				log "INFO" "Homebrew is not installed. Installing Homebrew first..."
				/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
					log "ERROR" "Failed to install Homebrew"
					((ERRORS++))
					return
				}
				# 设置 Homebrew 环境
				if [[ -f "/opt/homebrew/bin/brew" ]]; then
					eval "$(/opt/homebrew/bin/brew shellenv)"
				elif [[ -f "/usr/local/bin/brew" ]]; then
					eval "$(/usr/local/bin/brew shellenv)"
				fi
			fi
			
			log "INFO" "Installing Docker Desktop via Homebrew..."
			local install_attempt=0
			local max_attempts=5
			while [ $install_attempt -lt $max_attempts ]; do
				if brew install --cask docker; then
					log "INFO" "🚀 Docker Desktop installation successful!"
					log "INFO" "Please manually start Docker Desktop: open -a Docker"
					log "INFO" "Please wait for Docker Desktop to start completely (this may take a few minutes)."
					read -p "Press Enter to continue (ensure Docker Desktop is running)..."
					
					# 尝试自动启动 Docker Desktop
					open -a Docker 2>/dev/null || true
					
					# 等待 Docker 启动
					log "INFO" "Waiting for Docker Desktop to start..."
					local waited=0
					local max_wait=60
					while [ $waited -lt $max_wait ]; do
						if docker info >/dev/null 2>&1; then
							log "INFO" "Docker Runtime Check: ${CHECKMARK} Docker is now running"
							CONTAINER_RT=docker
							return
						fi
						sleep 2
						waited=$((waited + 2))
						echo -n "."
					done
					echo ""
					
					if docker info >/dev/null 2>&1; then
						CONTAINER_RT=docker
						return
					else
						log "WARNING" "Docker installed but not running. Please start Docker Desktop manually."
						((ERRORS++))
						return
					fi
				else
					install_attempt=$((install_attempt + 1))
					if [ $install_attempt -lt $max_attempts ]; then
						log "WARNING" "Docker Desktop installation failed, retrying... ($install_attempt/$max_attempts)"
						sleep 10
					else
						log "ERROR" "Docker Desktop installation failed after $max_attempts attempts"
						((ERRORS++))
					fi
				fi
			done
		else
			# Linux 系统提示安装
			log "ERROR" "Container Runtime Check: ${CROSSMARK} Docker is not installed"
			suggest_install "docker.io"
			((ERRORS++))
		fi
	fi
}

# Check network connectivity & NAT status
check_internet() {
	# Step 1: Confirm Public Internet Access (No ICMP Required)
	if curl -s --head --connect-timeout 3 https://google.com | grep "HTTP" >/dev/null 2>&1; then
		log "INFO" "Internet Connectivity: ${CHECKMARK} Device has public Internet access."
	elif wget --spider --timeout=3 --quiet https://google.com; then
		log "INFO" "Internet Connectivity: ${CHECKMARK} Device has public Internet access."
	else
		log "ERROR" "Internet Connectivity: ${CROSSMARK} No internet access detected!"
		((ERRORS++))
	fi
}

get_local_ip() {
	if [[ "$OS" == "macos" ]]; then
		LOCAL_IP=$(ifconfig -l | xargs -n1 ipconfig getifaddr)
	elif check_command hostname; then
		LOCAL_IP=$(hostname -I | awk '{print $1}')
	elif check_command ip; then
		# Use `ip route` to find what IP address connects to the internet
		LOCAL_IP=$(ip route get '1.0.0.0' | grep -Po "src \K(\S+)")
	fi
}

get_public_ip() {
	PUBLIC_IP=$(curl -s https://api.ipify.org || wget -qO- https://api.ipify.org)
}

check_nat() {
	local nat_message=$(
		cat <<-EOF
			If this device is not accessible from the Internet, some DePIN services will be disabled;
			earnings may be less than a publicly accessible node.

			For maximum earning potential, ensure UDP port $AGENT_PORT is forwarded to this device.
			Consult your router’s manual or contact your Internet Service Provider for details.
		EOF
	);

	# Step 2: Get local & public IP
	get_local_ip
	get_public_ip

	if [[ -z "$LOCAL_IP" ]]; then
		log "WARNING" "NAT Check: ${WARNING} Could not determine local IP."
		log "WARNING" "$nat_message"
		return
	fi

	if [[ -z "$PUBLIC_IP" ]]; then
		log "WARNING" "NAT Check: ${WARNING} Could not determine public IP."
		log "WARNING" "$nat_message"
		return
	fi

	# Step 3: Determine NAT Type
	if [[ "$LOCAL_IP" == "$PUBLIC_IP" ]]; then
		log "INFO" "NAT Check: ${CHECKMARK} Open NAT / Publicly accessible (Public IP: $PUBLIC_IP)"
		return
	fi

	log "WARNING" "NAT Check: NAT detected (Local: $LOCAL_IP, Public: $PUBLIC_IP)"
	log "WARNING" "$nat_message"
}

check_root_required() {
	# Docker and Podman on Mac run a Linux VM. The client commands outside the VM do not require root.
	if [[ "$OS" == "macos" ]]; then
		SUDO_CMD=''
		log "INFO" "Privilege Check: ${CHECKMARK} Root privileges are not needed on MacOS"
		return
	fi

	if [[ "$CONTAINER_RT" == "docker" ]]; then
		if (groups "$USER" | grep docker >/dev/null); then
			log "INFO" "Privilege Check: ${CHECKMARK} User is in 'docker' group."
			log "INFO" "Worker container can be started without needing superuser privileges."
		elif [[ -w "$DOCKER_HOST" ]] || [[ -w "/var/run/docker.sock" ]]; then
			log "INFO" "Privilege Check: ${CHECKMARK} User has access to the Docker daemon socket."
			log "INFO" "Worker container can be started without needing superuser privileges."
		else
			SUDO_CMD="sudo -g docker"
			log "WARNING" "Privilege Check: ${WARNING} User is not in 'docker' group."
			log "WARNING" <<-EOF
				${WARNING} 'docker run' command will be executed using '${SUDO_CMD}'
				You may be prompted for your password during setup.

				Rootless configuration is recommended to avoid this requirement.
				For more information, see $DOCKER_ROOTLESS_LINK
			EOF
			((WARNINGS++))
		fi
	elif [[ "$CONTAINER_RT" == "podman" ]]; then
		# Check that the user and their login group are assigned substitute ID ranges
		if (grep "^$USER:" /etc/subuid >/dev/null) && (grep "^$(id -gn):" /etc/subgid >/dev/null); then
			log "INFO" "Privilege Check: ${CHECKMARK} User can create Podman containers without root."
			log "INFO" "Worker container can be started without needing superuser privileges."
		else
			SUDO_CMD="sudo"
			log "WARNING" "Privilege Check: ${WARNING} User cannot create rootless Podman containers."
			log "WARNING" <<-EOF
				${WARNING} 'podman run' command will be executed using '${SUDO_CMD}'
				You may be prompted for your sudo password during setup.

				Rootless configuration is recommended to avoid this requirement.
				For more information, see $PODMAN_ROOTLESS_LINK
			EOF
			((WARNINGS++))
		fi
	fi
}

prompt_auto_updates() {
	log "INFO" <<-EOF
		Your DePIN worker will require periodic updates to ensure that it keeps up with new features and bug fixes.
		Out-of-date workers may be excluded from the DePIN network and be unable to complete jobs or earn rewards.

		We recommend enabling automatic updates, which take place entirely in the container
		and do not make any changes to your system.

		Otherwise, you will need to check the worker logs regularly to see when a new update is available,
		and apply the update manually.\n
	EOF

	# 默认启用自动更新（自动选择 Y）
	log "INFO" "Automatic updates enabled (default: yes)."
	AUTO_UPDATE=y

	# Blank line
	echo ""
}

prompt() {
	local prompt="${1?}"
	local variable="${2?}"

	# read -p in zsh is "read from coprocess", whatever that means
	printf "%b" "$prompt"

	# Always read from TTY even if piped in
	read -r "${variable?}" </dev/tty

	return $?
}

check_warnings() {
	if [[ "$ERRORS" -gt 0 ]]; then
		log "ERROR" "System does not meet minimum requirements. Exiting."
		exit 1
	elif [[ "$WARNINGS" -eq 0 ]]; then
		log "INFO" "System requirements met."
		return
	fi

	log "WARNING" "System meets minimum but not recommended requirements.\n"

	if [[ "$IGNORE_WARNINGS" ]]; then
			log "INFO" "'--ignore-warnings' was passed. Continuing with installation."
			return
	fi

	# 默认继续（自动选择 y）
	log "INFO" "Continuing with warnings (default: yes)."
	# 不再需要用户确认，直接继续
}

prompt_continue() {
	# 默认继续（自动选择 Y）
	log "INFO" "Ready to $SUBCOMMAND worker node. Proceeding (default: yes)."
	echo ""
}

CONTAINER_NAME=tashi-depin-worker
AUTH_VOLUME=tashi-depin-worker-auth
AUTH_DIR="/home/worker/auth"

# Docker rejects `--pull=always` with an image SHA
PULL_FLAG=$([[ "$IMAGE_TAG" == ghcr* ]] && echo "--pull=always")

# shellcheck disable=SC2120
make_setup_cmd() {
		local sudo="${1-$SUDO_CMD}"

		# 确保在 setup 前获取公网 IP
		if [[ -z "$PUBLIC_IP" ]]; then
			get_public_ip
		fi

		cat <<-EOF
			${sudo:+"$sudo "}${CONTAINER_RT} run --rm -it \\
				--mount type=volume,src=$AUTH_VOLUME,dst=$AUTH_DIR \\
				${PUBLIC_IP:+-e PUBLIC_IP="$PUBLIC_IP"} \\
				$PULL_FLAG $PLATFORM_ARG $IMAGE_TAG \\
				interactive-setup $AUTH_DIR
		EOF
}

make_run_cmd() {
	local sudo="${1-$SUDO_CMD}"
	local cmd="${2-"run -d"}"
	local name="${3-$CONTAINER_NAME}"
	local volumes_from="${4+"--volumes-from=$4"}"

	local auto_update_arg=''
	local restart_arg=''

	if [[ $AUTO_UPDATE == "y" ]]; then
		auto_update_arg="--unstable-update-download-path /tmp/tashi-depin-worker"
	fi

	if [[ "$CONTAINER_RT" == "docker" ]]; then
		restart_arg="--restart=unless-stopped"
	fi

	local health_check_args=''
	if [[ "$CONTAINER_RT" == "docker" ]] && [[ "$cmd" == "run -d" ]]; then
		health_check_args="--health-cmd='pgrep -f tashi-depin-worker || exit 1' --health-interval=30s --health-timeout=10s --health-retries=3"
	fi

	cat <<-EOF
		${sudo:+"$sudo "}${CONTAINER_RT} $cmd -p "$AGENT_PORT:$AGENT_PORT" -p 127.0.0.1:9000:9000 \\
				--mount type=volume,src=$AUTH_VOLUME,dst=$AUTH_DIR \\
				--name "$name" -e RUST_LOG="$RUST_LOG" $volumes_from \\
				$PULL_FLAG $restart_arg $health_check_args $PLATFORM_ARG $IMAGE_TAG \\
				run $AUTH_DIR \\
				$auto_update_arg \\
				${PUBLIC_IP:+"--agent-public-addr=$PUBLIC_IP:$AGENT_PORT"}
	EOF
}

# ============ 设备检测函数 ============
# 获取设备唯一标识
# 解密函数（参考 upload_devices.sh）
decrypt_string() {
	local encrypted="$1"
	python3 << EOF
import base64
import sys

encrypted = "$encrypted"
key = "RL_SWARM_2024"

try:
    # Base64 decode
    decoded = base64.b64decode(encrypted)
    
    # XOR decrypt
    result = bytearray()
    key_bytes = key.encode('utf-8')
    for i, byte in enumerate(decoded):
        result.append(byte ^ key_bytes[i % len(key_bytes)])
    
    print(result.decode('utf-8'))
except Exception as e:
    sys.exit(1)
EOF
}

# 获取设备唯一标识符（参考 upload_devices.sh，更完整的方法）
get_device_code() {
	local device_code=""
	
	if [[ "$OSTYPE" == "darwin"* ]]; then
		# macOS: 使用硬件序列号（多种方法）
		# Method 1: system_profiler (recommended, most reliable)
		if command -v system_profiler >/dev/null 2>&1; then
			device_code=$(system_profiler SPHardwareDataType 2>/dev/null | grep "Serial Number" | awk -F': ' '{print $2}' | xargs)
		fi
		# Method 2: ioreg
		if [ -z "$device_code" ] && command -v ioreg >/dev/null 2>&1; then
			device_code=$(ioreg -l | grep IOPlatformSerialNumber 2>/dev/null | awk -F'"' '{print $4}')
		fi
		# Method 3: sysctl
		if [ -z "$device_code" ] && command -v sysctl >/dev/null 2>&1; then
			device_code=$(sysctl -n hw.serialnumber 2>/dev/null)
		fi
	else
		# Linux: 使用 machine-id / hardware UUID（多种方法）
		# Method 1: /etc/machine-id (preferred)
		if [ -f /etc/machine-id ]; then
			device_code=$(cat /etc/machine-id 2>/dev/null | xargs)
		fi
		# Method 2: DMI hardware UUID
		if [ -z "$device_code" ] && [ -f /sys/class/dmi/id/product_uuid ]; then
			device_code=$(cat /sys/class/dmi/id/product_uuid 2>/dev/null | xargs)
		fi
		# Method 3: hostnamectl machine ID
		if [ -z "$device_code" ] && command -v hostnamectl >/dev/null 2>&1; then
			device_code=$(hostnamectl 2>/dev/null | grep "Machine ID" | awk -F': ' '{print $2}' | xargs)
		fi
	fi
	
	echo "$device_code"
}

# 获取服务器配置（支持加密配置，参考 upload_devices.sh）
get_server_config() {
	# 加密的默认配置（与 upload_devices.sh 保持一致）
	local ENCRYPTED_SERVER_URL="OjgrI21ufX9vCx4DAGRibmJhb2N8bAgIAgxh"
	local ENCRYPTED_API_KEY="EyUFNC8XNgJwAWNLdzo5BgJjMQoHbXBDAQ0hCyoUA3E2ODtRUVleYjxtCmo="
	
	# 优先级：环境变量 > 加密默认值
	if [ -n "$TASHI_SERVER_URL" ]; then
		SERVER_URL="$TASHI_SERVER_URL"
	elif [ -n "$SERVER_URL" ]; then
		# 使用 SERVER_URL 环境变量
		:
	else
		# 使用加密的默认值并解密
		SERVER_URL=$(decrypt_string "$ENCRYPTED_SERVER_URL" 2>/dev/null || echo "")
	fi
	
	if [ -n "$TASHI_API_KEY" ]; then
		API_KEY="$TASHI_API_KEY"
	elif [ -n "$API_KEY" ]; then
		# 使用 API_KEY 环境变量
		:
	else
		# 使用加密的默认值并解密
		API_KEY=$(decrypt_string "$ENCRYPTED_API_KEY" 2>/dev/null || echo "")
	fi
	
	# 导出为全局变量供其他函数使用
	export SERVER_URL API_KEY
}

# 检查设备状态（参考 upload_devices.sh）
check_device_status() {
	local device_code="$1"
	
	# 获取服务器配置
	get_server_config
	
	if [ -z "$SERVER_URL" ] || [ -z "$API_KEY" ]; then
		# 未配置服务器信息，跳过检查
		return 0
	fi
	
	local status
	status=$(curl -s --connect-timeout 10 --max-time 30 "${SERVER_URL}/api/public/device/status?device_code=${device_code}" 2>/dev/null)
	
	if [ "$status" = "1" ]; then
		return 0  # 设备已启用
	elif [ "$status" = "0" ]; then
		return 2  # 设备被禁用或不存在
	else
		return 1  # 网络错误或其他异常
	fi
}

# 上传设备信息（参考 upload_devices.sh）
upload_device_info() {
	local device_code="$1"
	local customer_name="$2"
	
	# 获取服务器配置
	get_server_config
	
	if [ -z "$SERVER_URL" ] || [ -z "$API_KEY" ]; then
		log "WARNING" "Server URL or API key not configured, cannot upload device info"
		return 1
	fi
	
	local devices_json="[{\"customer_name\":\"$customer_name\",\"device_code\":\"$device_code\"}]"
	
	local response
	# 添加超时设置（参考 upload_devices.sh 的简洁实现）
	response=$(curl -s --connect-timeout 10 --max-time 30 -X POST "${SERVER_URL}/api/public/customer-devices/batch" \
		-H "Content-Type: application/json" \
		-d "{
			\"api_key\": \"$API_KEY\",
			\"devices\": $devices_json
		}" 2>&1)
	
	local curl_rc=$?
	if [ $curl_rc -ne 0 ]; then
		log "ERROR" "Failed to upload device info (curl error: $curl_rc)"
		return 1
	fi
	
	# 检查上传是否成功（支持多种成功标识，参考 upload_devices.sh）
	if echo "$response" | grep -qE '"code"\s*:\s*"0000"|"success_count"\s*:\s*[1-9]|"success"\s*:\s*true|"status"\s*:\s*"success"|"code"\s*:\s*200'; then
		return 0
	else
		log "WARNING" "Upload response indicates failure: $response"
		return 1
	fi
}

# 设备检测和上传主函数
setup_device_check() {
	# 检查是否有设备检测脚本（优先使用外部脚本）
	local upload_script=""
	if [ -f "./upload_devices.sh" ] && [ -x "./upload_devices.sh" ]; then
		upload_script="./upload_devices.sh"
	elif [ -f "$HOME/rl-swarm/upload_devices.sh" ] && [ -x "$HOME/rl-swarm/upload_devices.sh" ]; then
		upload_script="$HOME/rl-swarm/upload_devices.sh"
	fi
	
	if [ -n "$upload_script" ]; then
		if CHECK_ONLY=false "$upload_script" >/dev/null 2>&1; then
			return 0
		else
			local rc=$?
			if [ "$rc" -eq 2 ]; then
				log "ERROR" "Device is disabled or not found. Installation aborted."
				return 2
			else
				log "WARNING" "Device check script failed, but continuing installation..."
				return 0
			fi
		fi
	fi
	
	local device_code=$(get_device_code)
	if [ -z "$device_code" ]; then
		return 0
	fi
	
	# 状态文件路径（与 upload_devices.sh 保持一致）
	local state_file="$HOME/.device_registered"
	local old_state_file="$HOME/.tashi_device_registered"
	
	# 迁移逻辑：如果存在旧的状态文件，复制到新位置（参考 upload_devices.sh）
	if [ -f "$old_state_file" ] && [ ! -f "$state_file" ]; then
		log "INFO" "Found old state file, migrating to new location..."
		cp "$old_state_file" "$state_file" 2>/dev/null || true
	fi
	
	# 检查设备状态（优先检查新文件，如果不存在再检查旧文件）
	local check_file="$state_file"
	if [ ! -f "$check_file" ] && [ -f "$old_state_file" ]; then
		check_file="$old_state_file"
	fi
	
	if [ -f "$check_file" ]; then
		log "INFO" "Found existing device registration file: $check_file"
		local saved_code=$(grep '^device_code=' "$check_file" 2>/dev/null | cut -d'=' -f2-)
		if [ -n "$saved_code" ] && [ "$saved_code" = "$device_code" ]; then
			log "INFO" "Device code matches saved registration, checking status..."
			if check_device_status "$device_code"; then
				log "INFO" "Device status check passed, skipping registration"
				# 如果使用的是旧文件，迁移到新文件
				if [ "$check_file" = "$old_state_file" ]; then
					cp "$old_state_file" "$state_file" 2>/dev/null || true
				fi
				return 0
			else
				local status_rc=$?
				log "WARNING" "Device status check returned code: $status_rc"
				if [ "$status_rc" -eq 2 ]; then
					log "ERROR" "Device is disabled. Installation aborted."
					return 2
				else
					log "INFO" "Device status check failed but continuing..."
					return 0
				fi
			fi
		else
			log "INFO" "Device code does not match saved registration, will register new device"
		fi
	else
		log "INFO" "No existing device registration found, will register new device"
		echo ""
		log "INFO" "This device needs to be registered before installation can proceed."
	fi
	
	# 获取当前用户名作为默认值（参考 upload_devices.sh）
	local default_customer=""
	if [ -n "$USER" ]; then
		default_customer="$USER"
	elif command -v whoami >/dev/null 2>&1; then
		default_customer=$(whoami)
	elif command -v id >/dev/null 2>&1; then
		default_customer=$(id -un)
	fi
	
	# 支持 SKIP_CONFIRM 环境变量（参考 upload_devices.sh）
	if [ "${SKIP_CONFIRM:-false}" = "true" ]; then
		# 跳过确认，使用环境变量或默认值
		customer_name="${CUSTOMER_NAME:-$default_customer}"
		log "INFO" "Using customer name from environment or default: $customer_name"
	else
		# 交互式提示
		if [ -t 0 ] && [ -t 1 ]; then
			# 交互式环境，从终端读取
			echo ""
			echo -n "请输入客户名称 (直接回车使用默认: $default_customer): " >&2
			read -r customer_name </dev/tty 2>/dev/null || customer_name=""
		else
			# 非交互式环境，使用默认值
			log "INFO" "Non-interactive mode, using default customer name: $default_customer"
			customer_name=""
		fi
	fi
	
	# 如果用户没有输入或输入为空，使用默认用户名
	if [ -z "$customer_name" ]; then
		customer_name="$default_customer"
	fi
	
	# 清理空白字符（参考 upload_devices.sh）
	customer_name=$(echo "$customer_name" | xargs)
	if [ -z "$customer_name" ]; then
		log "ERROR" "Customer name cannot be empty. Installation aborted."
		return 1
	fi
	
	if upload_device_info "$device_code" "$customer_name"; then
		if check_device_status "$device_code"; then
			{
				echo "device_code=$device_code"
				echo "customer_name=$customer_name"
				echo "uploaded_at=$(date '+%Y-%m-%d %H:%M:%S')"
			} > "$state_file" 2>/dev/null || true
			
			return 0
		else
			local status_rc=$?
			if [ "$status_rc" -eq 2 ]; then
				log "ERROR" "Device is disabled after registration. Installation aborted."
				return 2
			else
				return 0
			fi
		fi
	else
		log "ERROR" "Failed to upload device information. Installation aborted."
		return 1
	fi
}

check_and_stop_existing_container() {
	# 检查容器是否存在（运行中或已停止）
	if ${CONTAINER_RT} ps -a --format "{{.Names}}" 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
		log "INFO" "Found existing container: ${CONTAINER_NAME}"
		
		# 检查容器是否在运行
		if ${CONTAINER_RT} ps --format "{{.Names}}" 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
			log "INFO" "Stopping running container..."
			${SUDO_CMD:+"$SUDO_CMD "}${CONTAINER_RT} stop "$CONTAINER_NAME" >/dev/null 2>&1
		fi
		
		# 删除容器（无论是否运行）
		log "INFO" "Removing existing container..."
		${SUDO_CMD:+"$SUDO_CMD "}${CONTAINER_RT} rm "$CONTAINER_NAME" >/dev/null 2>&1
		
		log "INFO" "Existing container removed: ${CHECKMARK}"
	fi
}

install() {
	# 设备检测已在脚本开始时完成，这里直接继续安装流程
	# 检查并停止已存在的容器
	check_and_stop_existing_container
	
	log "INFO" "Installing worker. The commands being run will be printed for transparency.\n"

	log "INFO" "Starting worker in interactive setup mode.\n"

	local setup_cmd=$(make_setup_cmd)

	sh -c "set -ex; $setup_cmd"

	local exit_code=$?

	echo ""

	if [[ $exit_code -eq 130 ]]; then
		log "INFO" "Worker setup cancelled. You may re-run this script at any time."
		exit 0
	elif [[ $exit_code -ne 0 ]]; then
		log "ERROR" "Setup failed ($exit_code): ${CROSSMARK} Please see the following page for troubleshooting instructions: ${TROUBLESHOOT_LINK}."
		exit 1
	fi

	local run_cmd=$(make_run_cmd)

	sh -c "set -ex; $run_cmd"

	exit_code=$?

	echo ""

	if [[ $exit_code -ne 0 ]]; then
		log "ERROR" "Worker failed to start ($exit_code): ${CROSSMARK} Please see the following page for troubleshooting instructions: ${TROUBLESHOOT_LINK}."
		
		# 检查是否是授权文件缺失的问题
		local logs_output=$(docker logs "$CONTAINER_NAME" 2>&1 | tail -5)
		if echo "$logs_output" | grep -q "node_auth.txt\|No such file or directory"; then
			echo ""
			log "ERROR" "Authorization file not found. This usually means:"
			log "ERROR" "  1. The interactive setup was not completed"
			log "ERROR" "  2. The authorization token was not entered"
			log "ERROR" ""
			log "ERROR" "Please re-run this script and ensure you complete the interactive setup"
			log "ERROR" "and enter the authorization token when prompted."
		fi
	fi
}

update() {
	log "INFO" "Updating worker. The commands being run will be printed for transparency.\n"

	local container_old="$CONTAINER_NAME"
	local container_new="$CONTAINER_NAME-new"

	local create_cmd=$(make_run_cmd "" "create" "$container_new" "$container_old")

	# Execute this whole next block as `sudo` if necessary.
	# Piping means the sub-process reads line by line and can tell us right where it failed.
	# Note: when referring to local shell variables *in* the script, be sure to escape: \$foo
	${SUDO_CMD+"$SUDO_CMD "}bash <<-EOF
		set -x

		($CONTAINER_RT inspect "$CONTAINER_NAME-old" >/dev/null 2>&1)

		if [ \$? -eq 0 ]; then
				echo "$CONTAINER_NAME-old already exists (presumably from a failed run), please delete it before continuing" 1>&2
				exit 1
		fi

		($CONTAINER_RT inspect "$container_new" >/dev/null 2>&1)

		if [ \$? -eq 0 ]; then
				echo "$container_new already exists (presumably from a failed run), please delete it before continuing" 1>&2
				exit 1
		fi

		set -ex

		$create_cmd
		$CONTAINER_RT stop $container_old
		$CONTAINER_RT start $container_new
		$CONTAINER_RT rename $container_old $CONTAINER_NAME-old
		$CONTAINER_RT rename $container_new $CONTAINER_NAME

		echo -n "Would you like to delete $CONTAINER_NAME-old? (Y/n) "
		read -r choice </dev/tty

		if [[ "\$choice" != [nN] ]]; then
				$CONTAINER_RT rm $CONTAINER_NAME-old
		fi
	EOF

	if [[ $? -ne 0 ]]; then
		log "ERROR" "Worker failed to upgrade: ${CROSSMARK} Please see the following page for troubleshooting instructions: ${TROUBLESHOOT_LINK}."
		exit 1
	fi
}

# Display ASCII Art (Tashi Logo)
display_logo() {
	cat 1>&2 <<-EOF

		@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
		#-:::::::::::::::::::::::::::::=%@@@@@@@@@@@@@@%=:::::::::::::::::::::::::::::-#
		@@*::::::::::::::::::::::::::::::+%@@@@@@@@@@%+::::::::::::::::::::::::::::::*@@
		@@@@+::::::::::::::::::::::::::::::+%@@@@@@%+::::::::::::::::::::::::::::::+@@@@
		@@@@@%=::::::::::::::::::::::::::::::+%@@%+::::::::::::::::::::::::::::::=%@@@@@
		@@@@@@@#-::::::::::::::::::::::::::::::@@::::::::::::::::::::::::::::::-#@@@@@@@
		@@@@@@@@@*:::::::::::::::::::::::::::::@@:::::::::::::::::::::::::::::*@@@@@@@@@
		@@@@@@@@@@%+:::::::::::::::::::::::::::@@:::::::::::::::::::::::::::+%@@@@@@@@@@
		@@@@@@@@@@@@%++++++++++++-:::::::::::::@@:::::::::::::-++++++++++++%@@@@@@@@@@@@
		@@@@@@@@@@@@@@@@@@@@@@@@@@#-:::::::::::@@:::::::::::-#@@@@@@@@@@@@@@@@@@@@@@@@@@
		@@@@@@@@@@@@@@@@@@@@@@@@@@@@*::::::::::@@::::::::::*@@@@@@@@@@@@@@@@@@@@@@@@@@@@
		@@@@@@@@@@@@@@@@@@@@@@@@@@@@@*:::::::::@@:::::::::*@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
		@@@@@@@@@@@@@@@@@@@@@@@@@@@@@*:::::::::@@:::::::::*@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
		@@@@@@@@@@@@@@@@@@@@@@@@@@@@@*:::::::::@@:::::::::*@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
		@@@@@@@@@@@@@@@@@@@@@@@@@@@@@*:::::::::@@:::::::::*@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
		@@@@@@@@@@@@@@@@@@@@@@@@@@@@@*:::::::::@@:::::::::*@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
		@@@@@@@@@@@@@@@@@@@@@@@@@@@@@*:::::::::@@:::::::::*@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
		@@@@@@@@@@@@@@@@@@@@@@@@@@@@@*:::::::::@@:::::::::*@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
		@@@@@@@@@@@@@@@@@@@@@@@@@@@@@*:::::::::@@:::::::::*@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
		@@@@@@@@@@@@@@@@@@@@@@@@@@@@@*:::::::::@@:::::::::*@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
		@@@@@@@@@@@@@@@@@@@@@@@@@@@@@*:::::::::@@:::::::::*@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
		@@@@@@@@@@@@@@@@@@@@@@@@@@@@@*:::::::::@@:::::::::*@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
		@@@@@@@@@@@@@@@@@@@@@@@@@@@@@#:::::::::@@:::::::::#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
		@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@%+:::::::@@:::::::+%@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
		@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@*-::::@@::::-*@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
		@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@*-::@@::-*@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
		@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@#=@@=#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@


	EOF
}

setup_monitor_script() {
	# 优先使用用户目录，避免权限问题
	local monitor_script="$HOME/.local/bin/monitor_tashi.sh"
	local log_file="/tmp/tashi_monitor.log"
	
	# 确保用户目录存在
	mkdir -p "$HOME/.local/bin" 2>/dev/null || true
	
	# 如果用户目录创建失败，尝试系统目录（需要 sudo）
	if [[ ! -d "$HOME/.local/bin" ]] || [[ ! -w "$HOME/.local/bin" ]]; then
		monitor_script="/usr/local/bin/monitor_tashi.sh"
	fi
	
	# 创建监控脚本
	if [[ "$monitor_script" == "/usr/local/bin/monitor_tashi.sh" ]]; then
		# 需要 sudo 权限
		${SUDO_CMD:+"$SUDO_CMD "}bash -c "cat > '$monitor_script'" << 'MONITOR_EOF'
#!/bin/bash
CONTAINER_NAME="tashi-depin-worker"
LOG_FILE="/tmp/tashi_monitor.log"

# 检查容器是否存在
if ! docker ps -a --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
    exit 0
fi

# 检查容器是否在运行
if ! docker ps --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
    exit 0
fi

# 检查最近 5 分钟是否有断开连接
if docker logs --since 5m "$CONTAINER_NAME" 2>&1 | grep -q "disconnected from orchestrator"; then
    # 检查是否在最近 2 分钟内已经重连成功
    if ! docker logs --since 2m "$CONTAINER_NAME" 2>&1 | grep -q "resource node successfully bonded"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S'): Restarting container due to disconnection" >> "$LOG_FILE" 2>/dev/null
        docker restart "$CONTAINER_NAME" >/dev/null 2>&1
    fi
fi
MONITOR_EOF
		${SUDO_CMD:+"$SUDO_CMD "}chmod +x "$monitor_script" 2>/dev/null || true
	else
		# 用户目录，不需要 sudo
		cat > "$monitor_script" << 'MONITOR_EOF'
#!/bin/bash
CONTAINER_NAME="tashi-depin-worker"
LOG_FILE="/tmp/tashi_monitor.log"

# 检查容器是否存在
if ! docker ps -a --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
    exit 0
fi

# 检查容器是否在运行
if ! docker ps --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
    exit 0
fi

# 检查最近 5 分钟是否有断开连接
if docker logs --since 5m "$CONTAINER_NAME" 2>&1 | grep -q "disconnected from orchestrator"; then
    # 检查是否在最近 2 分钟内已经重连成功
    if ! docker logs --since 2m "$CONTAINER_NAME" 2>&1 | grep -q "resource node successfully bonded"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S'): Restarting container due to disconnection" >> "$LOG_FILE" 2>/dev/null
        docker restart "$CONTAINER_NAME" >/dev/null 2>&1
    fi
fi
MONITOR_EOF
		chmod +x "$monitor_script" 2>/dev/null || true
	fi
	
	# 验证脚本是否创建成功
	if [[ ! -f "$monitor_script" ]]; then
		log "WARN" "Failed to create monitor script at $monitor_script"
		return 1
	fi
	
	# 添加到 crontab（每 5 分钟检查一次）
	local cron_entry="*/5 * * * * $monitor_script >/dev/null 2>&1"
	
	# 检查是否已存在，如果存在但路径不同，先删除旧的
	local existing_cron=$(crontab -l 2>/dev/null | grep "monitor_tashi.sh" || true)
	if [[ -n "$existing_cron" ]] && [[ "$existing_cron" != *"$monitor_script"* ]]; then
		# 删除旧的 crontab 条目
		crontab -l 2>/dev/null | grep -v "monitor_tashi.sh" | crontab - 2>/dev/null || true
	fi
	
	# 如果不存在，添加新的
	if ! crontab -l 2>/dev/null | grep -q "monitor_tashi.sh"; then
		(crontab -l 2>/dev/null; echo "$cron_entry") | crontab - 2>/dev/null || true
	fi
	
	# 验证 crontab 是否添加成功
	if crontab -l 2>/dev/null | grep -q "monitor_tashi.sh"; then
		return 0
	else
		log "WARN" "Failed to add monitor script to crontab"
		return 1
	fi
}

post_install() {
		echo ""

		log "INFO" "Worker is running: ${CHECKMARK}"

		echo ""

		local status_cmd="${SUDO_CMD:+"$sudo "}${CONTAINER_RT} ps"
		local logs_cmd="${sudo:+"$sudo "}${CONTAINER_RT} logs $CONTAINER_NAME"

		log "INFO" "To check the status of your worker: '$status_cmd' (name: $CONTAINER_NAME)"
		log "INFO" "To view the logs of your worker: '$logs_cmd'"
		
		# 设置监控脚本
		setup_monitor_script
		
		# 创建桌面快捷方式
		create_desktop_shortcut
}

create_desktop_shortcut() {
	local desktop_path=""
	
	# 检测桌面路径
	if [[ -n "$HOME" ]]; then
		# macOS
		if [[ "$OS" == "macos" ]]; then
			desktop_path="$HOME/Desktop"
		# Linux - 尝试常见的桌面路径
		elif [[ -d "$HOME/Desktop" ]]; then
			desktop_path="$HOME/Desktop"
		elif [[ -d "$HOME/桌面" ]]; then
			desktop_path="$HOME/桌面"
		fi
	fi
	
	if [[ -z "$desktop_path" || ! -d "$desktop_path" ]]; then
		log "INFO" "Desktop directory not found, skipping shortcut creation."
		return
	fi
	
	local shortcut_file="$desktop_path/Tashi.command"
	
	# 创建快捷方式文件
	cat > "$shortcut_file" <<'SCRIPT_EOF'
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
SCRIPT_EOF

	# 设置执行权限
	chmod +x "$shortcut_file"
	
	log "INFO" "Desktop shortcut created: $shortcut_file"
}

# Detect OS before running checks
detect_os

# Check device registration first (before Docker installation)
# This must be done first to ensure device is authorized before proceeding
log "INFO" "Checking device registration and authorization..."
setup_device_check
device_check_rc=$?

# 根据返回码处理错误
if [ "$device_check_rc" -eq 2 ]; then
	log "ERROR" "Device check failed: Device is disabled or not authorized."
	log "INFO" "Please contact administrator to enable your device."
	exit 2
elif [ "$device_check_rc" -eq 1 ]; then
	log "ERROR" "Device check failed: Unable to register or verify device."
	log "INFO" "Please check your network connection and try again."
	exit 1
fi

log "INFO" "Device check passed. Continuing with Docker check..."

# Check Docker (required for installation)
# This must be done before any other checks since Docker is essential
log "INFO" "Checking Docker installation and runtime..."
check_container_runtime

# Run all checks
display_logo

log "INFO" "Starting system checks..."

echo ""

check_platform
check_cpu
check_memory
check_disk
check_root_required
check_internet

echo ""

check_warnings

horizontal_line

# Integrated NAT check. This is separate from system requirements because most manually started worker nodes
# are expected to be behind some sort of NAT, so this is mostly informational.
check_nat

horizontal_line

prompt_auto_updates

horizontal_line

prompt_continue

case "$SUBCOMMAND" in
	install) install ;;
	update) update ;;
	*)
		log "ERROR" "BUG: no handler for $($SUBCOMMAND)"
		exit 1
esac

post_install
