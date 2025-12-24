#!/bin/bash

# Tashi DePIN Worker 重启脚本
# 双击此文件可以重启节点并查看日志

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

# 切换到脚本所在目录
cd "$(dirname "$0")" || exit 1

# 清屏
clear

# 显示标题
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${RESET}"
echo -e "${GREEN}  Tashi DePIN Worker 重启脚本${RESET}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${RESET}"
echo ""

# 停止现有容器
echo "正在停止现有容器..."
if docker stop "$CONTAINER_NAME" >/dev/null 2>&1; then
    docker rm "$CONTAINER_NAME" >/dev/null 2>&1
    echo -e "${GREEN}✓${RESET} 容器已停止并删除"
else
    echo -e "${YELLOW}⚠${RESET} 没有运行中的容器"
fi
echo ""

# 启动新容器
echo "正在启动新容器..."
if docker run -d \
    -p "$AGENT_PORT:$AGENT_PORT" \
    -p 127.0.0.1:9000:9000 \
    --mount type=volume,src="$AUTH_VOLUME",dst="$AUTH_DIR" \
    --name "$CONTAINER_NAME" \
    -e RUST_LOG="$RUST_LOG" \
    --pull=always \
    --restart=on-failure \
    $PLATFORM_ARG \
    "$IMAGE_TAG" \
    run "$AUTH_DIR" \
    --unstable-update-download-path /tmp/tashi-depin-worker; then
    echo -e "${GREEN}✓${RESET} 容器已启动"
else
    echo -e "${RED}✗${RESET} 容器启动失败"
    exit 1
fi
echo ""

# 显示日志
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${RESET}"
echo -e "${GREEN}  开始显示日志（按 Ctrl+C 退出）${RESET}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${RESET}"
echo ""

# 持续显示日志
docker logs -f "$CONTAINER_NAME"

