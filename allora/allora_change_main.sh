#!/bin/bash

# Allora 替换 main.go 并重启节点脚本
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志函数
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}==>${NC} $1"; }

# 常量定义
PROJECT_DIR="allora-offchain-node"
MAIN_GO_PATH="$PROJECT_DIR/adapter/api/apiadapter/main.go"

echo "🚀 Allora 替换 main.go 并重启节点..."
echo "================================================"

# 检查项目目录是否存在
log_step "1. 检查项目目录..."
if [ ! -d "$PROJECT_DIR" ]; then
    log_error "❌ 项目目录 $PROJECT_DIR 不存在"
    log_info "请先运行 deploy_allora.sh 安装 Allora"
    exit 1
fi
log_info "✅ 项目目录存在"

# 停止现有服务
log_step "2. 停止现有 Docker 服务..."
cd "$PROJECT_DIR" || exit 1

# 停止可能运行的旧服务
if docker compose ps 2>/dev/null | grep -q "allora-offchain-node"; then
    log_info "正在停止 Allora 节点..."
    docker compose down 2>/dev/null || true
    log_info "✅ 服务已停止"
else
    log_info "✅ 没有运行中的服务"
fi

cd ..

# 备份旧的 main.go
log_step "3. 备份并清理 main.go 文件..."
# 确保目录存在
mkdir -p "$(dirname "$MAIN_GO_PATH")"

# 备份正确位置的文件
if [ -f "$MAIN_GO_PATH" ]; then
    BACKUP_FILE="${MAIN_GO_PATH}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$MAIN_GO_PATH" "$BACKUP_FILE"
    log_info "✅ 已备份旧文件到: $BACKUP_FILE"
else
    log_warn "⚠️  旧的 main.go 不存在，将直接创建新文件"
fi

# 检查并删除其他位置可能存在的错误位置的 main.go（如果包名是 apiadapter）
log_info "清理其他位置的 apiadapter 包文件..."
find "$PROJECT_DIR" -name "main.go" -type f | while IFS= read -r file; do
    if [ "$file" != "$MAIN_GO_PATH" ]; then
        if grep -q "^package apiadapter" "$file" 2>/dev/null; then
            log_warn "⚠️  发现错误位置的 apiadapter 包文件: $file"
            rm -f "$file"
            log_info "✅ 已删除错误位置的文件: $file"
        fi
    fi
done

# 替换 main.go 文件
log_step "4. 写入新的 main.go 文件..."
log_info "目标路径: $MAIN_GO_PATH"
log_info "确保目录存在: $(dirname "$MAIN_GO_PATH")"
mkdir -p "$(dirname "$MAIN_GO_PATH")"

cat > "$MAIN_GO_PATH" << 'MAIN_GO_EOF'
package apiadapter

import (
	"allora_offchain_node/lib"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"

	alloraMath "github.com/allora-network/allora-chain/math"
	"github.com/rs/zerolog/log"
)

type AlloraAdapter struct {
	name string
}

func (a *AlloraAdapter) Name() string {
	return a.name
}

func replacePlaceholders(urlTemplate string, params map[string]string) string {
	for key, value := range params {
		placeholder := fmt.Sprintf("{%s}", key)
		urlTemplate = strings.ReplaceAll(urlTemplate, placeholder, value)
	}
	return urlTemplate
}

// Replace placeholders and also the blockheheight
func replaceExtendedPlaceholders(urlTemplate string, params map[string]string, blockHeight int64, topicId uint64) string {
	// Create a map of default parameters
	blockHeightAsString := strconv.FormatInt(blockHeight, 10)
	topicIdAsString := strconv.FormatUint(topicId, 10)
	defaultParams := map[string]string{
		"BlockHeight": blockHeightAsString,
		"TopicId":     topicIdAsString,
	}
	urlTemplate = replacePlaceholders(urlTemplate, defaultParams)
	urlTemplate = replacePlaceholders(urlTemplate, params)
	return urlTemplate
}

func requestEndpoint(url string) (string, error) {
	// make request to url
	resp, err := http.Get(url) // nolint: gosec
	if err != nil {
		return "", fmt.Errorf("failed to make request to %s: %w", url, err)
	}
	defer resp.Body.Close()

	// Check if the response status is OK
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("received non-OK HTTP status %d", resp.StatusCode)
	}

	// Read the response body
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("failed to read response body: %w", err)
	}

	log.Debug().Bytes("body", body).Msg("Requested endpoint")
	// convert bytes to string
	return string(body), nil
}

// parseJSONToNodeValues parses the incoming JSON string and returns a slice of NodeValue.
func parseJSONToNodeValues(jsonStr string) ([]lib.NodeValue, error) {
	// Define a map to hold the parsed JSON data.
	var data map[string][]float64

	// Parse the JSON string into the map.
	err := json.Unmarshal([]byte(jsonStr), &data)
	if err != nil {
		return nil, err
	}

	// Create a slice to hold the NodeValues.
	var nodeValues []lib.NodeValue

	// Iterate over the map to create NodeValue structs.
	for worker, values := range data {
		if len(values) > 0 {
			// Only pick the first value in the list.
			nodeValue := lib.NodeValue{
				Worker: worker,
				Value:  fmt.Sprintf("%f", values[0]),
			}
			nodeValues = append(nodeValues, nodeValue)
		}
	}

	return nodeValues, nil
}

// Expects an inference as a string scalar value
// If the response is JSON, extracts the "prediction" field
// Otherwise returns the response as-is for backward compatibility
func (a *AlloraAdapter) CalcInference(node lib.WorkerConfig, blockHeight int64) (string, error) {
	log := log.With().Str("actorType", "worker").Uint64("topicId", node.TopicId).Logger()

	urlTemplate := node.Parameters["InferenceEndpoint"]
	url := replaceExtendedPlaceholders(urlTemplate, node.Parameters, blockHeight, node.TopicId)
	log.Debug().Str("url", url).Msg("Inference endpoint")
	
	response, err := requestEndpoint(url)
	if err != nil {
		return "", err
	}

	// Try to parse as JSON and extract prediction field
	var jsonData map[string]interface{}
	if err := json.Unmarshal([]byte(response), &jsonData); err == nil {
		// Successfully parsed as JSON, try to extract prediction
		if prediction, ok := jsonData["prediction"]; ok {
			// Convert prediction to string
			predictionStr := fmt.Sprintf("%v", prediction)
			log.Debug().Str("prediction", predictionStr).Msg("Extracted prediction from JSON response")
			return predictionStr, nil
		}
		// JSON parsed but no prediction field, log warning and return original
		log.Warn().Msg("Response is JSON but contains no 'prediction' field, returning original response")
	}

	// Not JSON or no prediction field, return as-is (backward compatible)
	return response, nil
}

// Expects forecast as a json array of NodeValue
func (a *AlloraAdapter) CalcForecast(node lib.WorkerConfig, blockHeight int64) ([]lib.NodeValue, error) {
	log := log.With().Str("actorType", "worker").Uint64("topicId", node.TopicId).Logger()

	urlTemplate := node.Parameters["ForecastEndpoint"]
	url := replaceExtendedPlaceholders(urlTemplate, node.Parameters, blockHeight, node.TopicId)
	log.Debug().Str("url", url).Msg("Forecasts endpoint")

	forecastsAsJsonString, err := requestEndpoint(url)
	if err != nil {
		log.Error().Err(err).Msg("Failed to get forecasts")
		return []lib.NodeValue{}, err
	}

	// parse json forecasts into a slice of NodeValue
	nodeValues, err := parseJSONToNodeValues(forecastsAsJsonString)
	if err != nil {
		log.Error().Err(err).Msg("Error transforming forecasts")
		return []lib.NodeValue{}, err
	}
	return nodeValues, nil
}

func (a *AlloraAdapter) GroundTruth(node lib.ReputerConfig, blockHeight int64) (lib.Truth, error) {
	log := log.With().Str("actorType", "reputer").Uint64("topicId", node.TopicId).Logger()

	urlTemplate := node.GroundTruthParameters["GroundTruthEndpoint"]
	url := replaceExtendedPlaceholders(urlTemplate, node.GroundTruthParameters, blockHeight, node.TopicId)
	log.Debug().Str("url", url).Msg("Ground truth endpoint")
	groundTruth, err := requestEndpoint(url)
	if err != nil {
		log.Error().Err(err).Msg("Failed to get ground truth")
		return "", err
	}
	// Check conversion to decimal before handing it over
	groundTruthDec, err := alloraMath.NewDecFromString(groundTruth)
	if err != nil {
		groundTruthDec, err = alloraMath.NewDecFromString(sanitizeDecString(groundTruth))
		if err != nil {
			log.Error().Err(err).Msg("Failed to convert ground truth to decimal")
			return "", err
		}
	}
	log.Info().Str("url", url).Str("groundTruth", groundTruthDec.String()).Msg("Ground truth")
	return groundTruthDec.String(), nil
}

func (a *AlloraAdapter) LossFunction(node lib.ReputerConfig, groundTruth string, inferenceValue string, options map[string]string) (string, error) {
	log := log.With().Str("actorType", "reputer").Uint64("topicId", node.TopicId).Logger()

	url := node.LossFunctionParameters.LossFunctionService
	if url == "" {
		return "", fmt.Errorf("no loss function endpoint provided")
	}
	// Use /calculate endpoint of loss-functions service
	url = fmt.Sprintf("%s/calculate", url)
	log.Debug().Str("url", url).Msg("Loss function endpoint")

	// Prepare the request payload
	payload := map[string]interface{}{
		"y_true":  groundTruth,
		"y_pred":  inferenceValue,
		"options": options,
	}

	// Convert payload to JSON
	jsonPayload, err := json.Marshal(payload)
	if err != nil {
		return "", fmt.Errorf("failed to marshal payload: %w", err)
	}

	// Create a new POST request
	req, err := http.NewRequest("POST", url, bytes.NewBuffer(jsonPayload))
	if err != nil {
		return "", fmt.Errorf("failed to create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	// Send the request
	client := &http.Client{} // nolint: exhaustruct
	resp, err := client.Do(req)
	if err != nil {
		return "", fmt.Errorf("failed to send request: %w", err)
	}
	defer resp.Body.Close()

	// Check the response status
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("received non-OK HTTP status %d", resp.StatusCode)
	}

	// Read and parse the response
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("failed to read response body: %w", err)
	}

	var result struct {
		Loss string `json:"loss"`
	}
	if err := json.Unmarshal(body, &result); err != nil {
		return "", fmt.Errorf("failed to parse response: %w", err)
	}

	log.Debug().Str("url", url).Str("Loss", result.Loss).Msg("Calculated loss value from external endpoint")
	return result.Loss, nil
}

func (a *AlloraAdapter) IsLossFunctionNeverNegative(node lib.ReputerConfig, options map[string]string) (bool, error) {
	log := log.With().Str("actorType", "reputer").Uint64("topicId", node.TopicId).Logger()
	url := node.LossFunctionParameters.LossFunctionService
	if url == "" {
		return false, fmt.Errorf("no loss function endpoint provided")
	}
	// Use /is_never_negative endpoint of loss-functions service
	url = fmt.Sprintf("%s/is_never_negative", url)
	log.Debug().Str("url", url).Msg("Checking if loss function is never negative - endpoint")

	// Prepare the request payload
	payload := map[string]interface{}{
		"options": options,
	}

	// Convert payload to JSON
	jsonPayload, err := json.Marshal(payload)
	if err != nil {
		return false, fmt.Errorf("failed to marshal payload: %w", err)
	}

	// Create a new POST request
	req, err := http.NewRequest("POST", url, bytes.NewBuffer(jsonPayload))
	if err != nil {
		return false, fmt.Errorf("failed to create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	// Send the request
	client := &http.Client{} // nolint: exhaustruct
	resp, err := client.Do(req)
	if err != nil {
		return false, fmt.Errorf("failed to send request: %w", err)
	}
	defer resp.Body.Close()

	// Check the response status
	if resp.StatusCode != http.StatusOK {
		return false, fmt.Errorf("received non-OK HTTP status %d", resp.StatusCode)
	}

	// Read and parse the response
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return false, fmt.Errorf("failed to read response body: %w", err)
	}

	var result struct {
		IsNeverNegative bool `json:"is_never_negative"`
	}
	if err := json.Unmarshal(body, &result); err != nil {
		return false, fmt.Errorf("failed to parse response: %w", err)
	}

	log.Debug().Str("url", url).Interface("options", options).Bool("IsNeverNegative", result.IsNeverNegative).Msg("Checked if loss function is never negative")
	return result.IsNeverNegative, nil
}

func (a *AlloraAdapter) CanInfer() bool {
	return true
}

func (a *AlloraAdapter) CanForecast() bool {
	return true
}

func (a *AlloraAdapter) CanSourceGroundTruthAndComputeLoss() bool {
	return true
}

func NewAlloraAdapter() *AlloraAdapter {
	return &AlloraAdapter{
		name: "apiAdapter",
	}
}

func sanitizeDecString(input string) string {
	// Remove any double quotes
	input = strings.ReplaceAll(input, "\"", "")

	// Remove any leading/trailing whitespace
	input = strings.TrimSpace(input)

	// Remove any commas (often used as thousand separators)
	input = strings.ReplaceAll(input, ",", "")

	// Ensure only one decimal point
	parts := strings.Split(input, ".")
	if len(parts) > 2 {
		input = parts[0] + "." + strings.Join(parts[1:], "")
	}

	return input
}
MAIN_GO_EOF
log_info "✅ main.go 文件已写入"

# 验证新文件
if [ ! -f "$MAIN_GO_PATH" ]; then
    log_error "❌ 替换失败，文件不存在"
    exit 1
fi

# 验证文件内容
if ! grep -q "^package apiadapter" "$MAIN_GO_PATH" 2>/dev/null; then
    log_error "❌ 文件内容验证失败，包名不正确"
    exit 1
fi
log_info "✅ 文件内容验证通过"

# 最终检查：确保没有其他位置的 apiadapter 包的 main.go
log_step "4.5. 最终清理检查..."
CORRECT_REL_PATH="adapter/api/apiadapter/main.go"

# 使用临时文件收集需要删除的文件列表
TEMP_DELETE_LIST=$(mktemp)
trap "rm -f '$TEMP_DELETE_LIST'" EXIT

find "$PROJECT_DIR" -name "main.go" -type f | while IFS= read -r file; do
    if grep -q "^package apiadapter" "$file" 2>/dev/null; then
        # 获取相对于项目目录的路径
        rel_path="${file#$PROJECT_DIR/}"
        
        # 规范化路径（移除多余的斜杠）
        rel_path=$(echo "$rel_path" | sed 's|^/||')
        normalized_correct=$(echo "$CORRECT_REL_PATH" | sed 's|^/||')
        
        # 检查是否是正确的路径
        if [ "$rel_path" != "$normalized_correct" ]; then
            log_warn "⚠️  发现错误位置的 apiadapter 包文件: $file"
            echo "$file" >> "$TEMP_DELETE_LIST"
        else
            log_info "  ✓ 正确位置的 apiadapter 包文件: $file"
        fi
    else
        log_info "  - 其他包文件: $file"
    fi
done

# 删除所有错误位置的文件
if [ -s "$TEMP_DELETE_LIST" ]; then
    DELETE_COUNT=$(wc -l < "$TEMP_DELETE_LIST" | tr -d ' ')
    log_info "发现 $DELETE_COUNT 个需要删除的文件"
    while IFS= read -r file; do
        if [ -n "$file" ]; then
            log_info "正在删除错误位置的文件: $file"
            rm -f "$file"
            if [ ! -f "$file" ]; then
                log_info "✅ 已删除: $file"
            else
                log_warn "⚠️  删除失败: $file"
            fi
        fi
    done < "$TEMP_DELETE_LIST"
else
    log_info "✅ 没有发现错误位置的 apiadapter 包文件"
fi

# 重新构建和启动服务
log_step "5. 重新构建和启动 Docker 服务..."

# 确保在正确的目录（项目根目录）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

# 检查项目目录是否存在
if [ ! -d "$PROJECT_DIR" ]; then
    log_error "❌ 项目目录 $PROJECT_DIR 不存在"
    log_info "当前目录: $(pwd)"
    exit 1
fi

# 进入项目目录
cd "$PROJECT_DIR" || {
    log_error "❌ 无法进入项目目录: $PROJECT_DIR"
    log_info "当前目录: $(pwd)"
    exit 1
}

# 检查 Docker 配置文件是否存在
if [ ! -f "docker-compose.yml" ]; then
    log_error "❌ docker-compose.yml 文件不存在"
    exit 1
fi

if [ ! -f "Dockerfile.offchain" ]; then
    log_error "❌ Dockerfile.offchain 文件不存在"
    exit 1
fi

# 构建前最终清理：删除所有可能冲突的 main.go 文件（apiadapter 包在错误位置）
log_info "构建前最终清理冲突文件..."
CORRECT_REL_PATH="adapter/api/apiadapter/main.go"

# 查找所有 apiadapter 包的 main.go 文件
find . -name "main.go" -type f | while read -r file; do
    if grep -q "^package apiadapter" "$file" 2>/dev/null; then
        # 获取相对路径
        rel_path=${file#./}
        
        # 检查是否是正确的路径
        if [ "$rel_path" != "$CORRECT_REL_PATH" ]; then
            log_warn "⚠️  发现并删除错误位置的 apiadapter 包文件: $file"
            rm -f "$file"
        fi
    fi
done

log_info "✅ 清理完成"

# 清理旧的 Docker 镜像（避免缓存问题）
log_info "清理旧的 Docker 镜像..."
docker rmi -f $(docker images | grep "allora" | awk '{print $3}') 2>/dev/null || true
log_info "✅ 镜像清理完成"

log_info "检查 Docker 配置..."
docker compose config >/dev/null 2>&1 || {
    log_error "❌ Docker 配置检查失败"
    exit 1
}

# 构建 Docker 镜像
log_info "构建 Docker 镜像..."
if docker compose build; then
    log_info "✅ 镜像构建成功"
else
    log_error "❌ 镜像构建失败"
    docker compose logs --tail=20 2>/dev/null || true
    exit 1
fi

# 启动服务
log_info "启动服务..."
if docker compose up -d; then
    log_info "✅ 服务启动成功"
    
    # 等待服务完全启动
    log_info "等待服务启动..."
    for i in {1..30}; do
        if docker ps | grep -q "allora-offchain-node" && docker ps | grep allora-offchain-node | grep -q "Up"; then
            log_info "✅ Offchain 节点正在运行！"
            break
        fi
        echo -n "."
        sleep 1
    done
    echo ""
    
    # 检查服务状态
    if docker ps | grep -q "allora-offchain-node"; then
        log_info "✅ 节点启动成功！"
        
        # 显示服务状态
        echo ""
        echo "=== 服务状态 ==="
        docker ps | grep -E "CONTAINER|allora"
        echo ""
        
        log_info "查看日志: cd $PROJECT_DIR && docker compose logs -f"
        log_info "停止服务: cd $PROJECT_DIR && docker compose down"
    else
        log_error "❌ 节点启动失败，请检查日志"
        echo ""
        echo "=== 错误日志 ==="
        docker compose logs --tail=30 2>/dev/null || true
        exit 1
    fi
else
    log_error "❌ 服务启动失败"
    exit 1
fi

cd ..

echo "================================================"
log_info "✅ main.go 替换并重启节点完成！"
echo "================================================"

