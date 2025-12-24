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

# 默认启用非交互式安装（自动跳过非必需交互）
# 可以通过 --interactive 参数启用交互式模式
YES=${YES:-1}
AUTO_UPDATE=${AUTO_UPDATE:-y}
IGNORE_WARNINGS=${IGNORE_WARNINGS:-y}

# munch args
POSITIONAL_ARGS=()

SUBCOMMAND=install

while [[ $# -gt 0 ]]; do
	case $1 in
		--interactive)
			YES=0
			AUTO_UPDATE=""
			IGNORE_WARNINGS=""
			shift
			;;
		--ignore-warnings)
			IGNORE_WARNINGS=y
			shift
			;;
		--no-ignore-warnings)
			IGNORE_WARNINGS=""
			shift
			;;
		-y | --yes)
			YES=1
			shift
			;;
		--no-yes)
			YES=0
			shift
			;;
		--auto-update)
			AUTO_UPDATE=y
			shift
			;;
		--no-auto-update)
			AUTO_UPDATE=""
			shift
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

# Container Runtime Check
check_container_runtime() {
	if check_command docker; then
		CONTAINER_RT="docker"
		CONTAINER_NAME="tashi-depin-worker"
		log "INFO" "Container Runtime Check: ${CHECKMARK} Docker found"
		return
	fi

	if check_command podman; then
		CONTAINER_RT="podman"
		CONTAINER_NAME="tashi-depin-worker"
		log "INFO" "Container Runtime Check: ${CHECKMARK} Podman found"
		return
	fi

	log "ERROR" "Container Runtime Check: ${CROSSMARK} Neither Docker nor Podman found"
	log "INFO" "Please install Docker or Podman:"
	suggest_install "docker"
	suggest_install "podman"
	((ERRORS++))
}

# Root Check
check_root_required() {
	if [[ "$CONTAINER_RT" == "docker" ]]; then
		if docker info >/dev/null 2>&1; then
			SUDO_CMD=""
			log "INFO" "Root Check: ${CHECKMARK} Docker accessible without sudo"
		elif sudo docker info >/dev/null 2>&1; then
			SUDO_CMD="sudo"
			log "WARNING" "Root Check: ${WARNING} Docker requires sudo"
			log "INFO" "Consider setting up rootless Docker: ${DOCKER_ROOTLESS_LINK}"
			((WARNINGS++))
		else
			log "ERROR" "Root Check: ${CROSSMARK} Cannot access Docker"
			((ERRORS++))
		fi
	elif [[ "$CONTAINER_RT" == "podman" ]]; then
		if podman info >/dev/null 2>&1; then
			SUDO_CMD=""
			log "INFO" "Root Check: ${CHECKMARK} Podman accessible without sudo"
		elif sudo podman info >/dev/null 2>&1; then
			SUDO_CMD="sudo"
			log "WARNING" "Root Check: ${WARNING} Podman requires sudo"
			log "INFO" "Consider setting up rootless Podman: ${PODMAN_ROOTLESS_LINK}"
			((WARNINGS++))
		else
			log "ERROR" "Root Check: ${CROSSMARK} Cannot access Podman"
			((ERRORS++))
		fi
	fi
}

# Internet Check
check_internet() {
	if curl -s --max-time 5 https://www.google.com >/dev/null 2>&1 || curl -s --max-time 5 https://www.baidu.com >/dev/null 2>&1; then
		log "INFO" "Internet Check: ${CHECKMARK} Internet connection available"
	else
		log "ERROR" "Internet Check: ${CROSSMARK} No internet connection"
		((ERRORS++))
	fi
}

# NAT Check
check_nat() {
	local public_ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || curl -s --max-time 5 https://ifconfig.me 2>/dev/null || echo "")
	
	if [[ -z "$public_ip" ]]; then
		log "WARNING" "NAT Check: ${WARNING} Could not determine public IP"
		return
	fi
	
	local local_ip=""
	case "$OS" in
		"macos")
			local_ip=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "")
			;;
		*)
			local_ip=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $7; exit}' || echo "")
			;;
	esac
	
	if [[ -n "$local_ip" && "$public_ip" != "$local_ip" ]]; then
		log "INFO" "NAT Check: ${CHECKMARK} Detected NAT (Public IP: $public_ip, Local IP: $local_ip)"
		log "INFO" "Your worker will be accessible via the public IP address."
	else
		log "INFO" "NAT Check: ${CHECKMARK} No NAT detected (Public IP: $public_ip)"
	fi
	
	PUBLIC_IP="$public_ip"
}

# Check Warnings
check_warnings() {
	if [[ $WARNINGS -gt 0 ]]; then
		if [[ "${IGNORE_WARNINGS:-}" == "y" ]]; then
			log "INFO" "Found $WARNINGS warning(s), but continuing due to --ignore-warnings (default in non-interactive mode)."
		elif [[ "${YES:-}" == "1" ]]; then
			log "INFO" "Found $WARNINGS warning(s), but continuing due to non-interactive mode (-y/--yes)."
		else
			log "WARNING" "Found $WARNINGS warning(s). Use --ignore-warnings to continue anyway."
			echo -n "Continue anyway? (y/N) "
			read -r choice </dev/tty
			if [[ "$choice" != [yY] ]]; then
				exit 1
			fi
		fi
	fi

	if [[ $ERRORS -gt 0 ]]; then
		log "ERROR" "Found $ERRORS error(s). Please fix them before continuing."
		exit 1
	fi
}

# Prompt for auto-updates
prompt_auto_updates() {
	if [[ "${AUTO_UPDATE:-}" == "y" ]]; then
		log "INFO" "Auto-updates: Enabled (default in non-interactive mode)"
		return
	fi

	if [[ "${YES:-}" == "1" ]]; then
		log "INFO" "Auto-updates: Enabled (non-interactive mode)"
		AUTO_UPDATE=y
		return
	fi

	log "INFO" "Auto-updates: The worker can automatically update itself when new versions are available."
	echo -n "Enable auto-updates? (Y/n) "
	read -r choice </dev/tty

	if [[ "$choice" != [nN] ]]; then
		AUTO_UPDATE=y
	fi
}

# Prompt to continue
prompt_continue() {
	if [[ "${YES:-}" == "1" ]]; then
		log "INFO" "All checks passed. Proceeding with installation (non-interactive mode)..."
		return
	fi

	log "INFO" "All checks passed. Ready to install."
	echo -n "Continue with installation? (Y/n) "
	read -r choice </dev/tty

	if [[ "$choice" == [nN] ]]; then
		exit 0
	fi
}

# Make setup command
make_setup_cmd() {
	local cmd="${SUDO_CMD:+"$SUDO_CMD "}${CONTAINER_RT}"
	local name="$CONTAINER_NAME-setup"
	local auth_dir="/var/lib/tashi-depin-worker"
	local auth_volume="tashi-depin-worker-auth"
	local auto_update_arg=""
	
	if [[ "${AUTO_UPDATE:-}" == "y" ]]; then
		auto_update_arg="--auto-update"
	fi

	cat <<-EOF
		${cmd} run --rm -it \\
			--mount type=volume,src=$auth_volume,dst=$auth_dir \\
			--name "$name" -e RUST_LOG="$RUST_LOG" \\
			$PLATFORM_ARG $IMAGE_TAG \\
			setup $auth_dir $auto_update_arg
	EOF
}

# Make run command
make_run_cmd() {
	local cmd="${1:-${SUDO_CMD:+"$SUDO_CMD "}${CONTAINER_RT}}"
	local action="${2:-run}"
	local name="${3:-$CONTAINER_NAME}"
	local old_name="${4:-}"
	local auth_dir="/var/lib/tashi-depin-worker"
	local auth_volume="tashi-depin-worker-auth"
	local auto_update_arg=""
	local volumes_from=""
	local pull_flag=""
	
	if [[ "${AUTO_UPDATE:-}" == "y" ]]; then
		auto_update_arg="--auto-update"
	fi
	
	if [[ "$action" == "create" ]]; then
		pull_flag="--pull=always"
		if [[ -n "$old_name" ]]; then
			volumes_from="--volumes-from $old_name"
		fi
	fi

	if [[ "$CONTAINER_RT" == "docker" ]]; then
		restart_arg="--restart=on-failure"
	fi

	cat <<-EOF
		${sudo:+"$sudo "}${CONTAINER_RT} $cmd -p "$AGENT_PORT:$AGENT_PORT" -p 127.0.0.1:9000:9000 \\
				--mount type=volume,src=$auth_volume,dst=$auth_dir \\
				--name "$name" -e RUST_LOG="$RUST_LOG" $volumes_from \\
				$pull_flag $restart_arg $PLATFORM_ARG $IMAGE_TAG \\
				run $auth_dir \\
				$auto_update_arg \\
				${PUBLIC_IP:+"--agent-public-addr=$PUBLIC_IP:$AGENT_PORT"}
	EOF
}

install() {
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

post_install() {
		echo ""

		log "INFO" "Worker is running: ${CHECKMARK}"

		echo ""

		local status_cmd="${SUDO_CMD:+"$sudo "}${CONTAINER_RT} ps"
		local logs_cmd="${sudo:+"$sudo "}${CONTAINER_RT} logs $CONTAINER_NAME"

		log "INFO" "To check the status of your worker: '$status_cmd' (name: $CONTAINER_NAME)"
		log "INFO" "To view the logs of your worker: '$logs_cmd'"
}

# Detect OS before running checks
detect_os

# Run all checks
display_logo

# 显示运行模式
if [[ "${YES:-}" == "1" ]]; then
	log "INFO" "Running in non-interactive mode (default). Use --interactive to enable interactive prompts."
else
	log "INFO" "Running in interactive mode. Use -y/--yes for non-interactive mode."
fi

log "INFO" "Starting system checks..."

echo ""

check_platform
check_cpu
check_memory
check_disk
check_container_runtime
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

