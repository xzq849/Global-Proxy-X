#!/bin/bash

# 镜像源可用性测试脚本
# 测试各个镜像源的连通性、响应时间和下载速度
# 
# 功能:
# - 测试镜像源连通性和响应时间
# - 测试下载速度
# - 生成详细的测试报告
# - 提供镜像源推荐排序

# 启用严格模式
set -euo pipefail

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 导入通用函数
if [[ -f "$SCRIPT_DIR/common_functions.sh" ]]; then
    source "$SCRIPT_DIR/common_functions.sh"
else
    echo "错误: 找不到 common_functions.sh 文件" >&2
    exit 1
fi

# 初始化通用函数
init_common

# 检查必要的依赖
check_dependencies curl stat

# 配置变量
readonly ARCH="${ARCH:-amd64}"
readonly LATEST_VERSION="${LATEST_VERSION:-v1.8.0}"
readonly TEST_FILE="sing-box-${LATEST_VERSION#v}-linux-${ARCH}.tar.gz"
readonly TEMP_DIR="${TEMP_DIR:-/tmp}"
readonly REPORT_DIR="$SCRIPT_DIR/reports"

# 创建必要的目录
mkdir -p "$REPORT_DIR" "$TEMP_DIR"

# 定义所有镜像源
declare -A MIRROR_SOURCES=(
    ["Hub.gitmirror"]="https://hub.gitmirror.com/https://github.com/SagerNet/sing-box/releases/download/${LATEST_VERSION}/${TEST_FILE}"
    ["Ghproxy.net"]="https://ghproxy.net/https://github.com/SagerNet/sing-box/releases/download/${LATEST_VERSION}/${TEST_FILE}"
    ["Ghproxy.com"]="https://ghproxy.com/https://github.com/SagerNet/sing-box/releases/download/${LATEST_VERSION}/${TEST_FILE}"
    ["Mirror.ghproxy"]="https://mirror.ghproxy.com/https://github.com/SagerNet/sing-box/releases/download/${LATEST_VERSION}/${TEST_FILE}"
    ["Gitclone.com"]="https://gitclone.com/github.com/SagerNet/sing-box/releases/download/${LATEST_VERSION}/${TEST_FILE}"
)

# 结果存储
declare -A CONNECTIVITY_RESULTS
declare -A RESPONSE_TIMES
declare -A DOWNLOAD_SPEEDS
declare -A STATUS_CODES
declare -A ERROR_MESSAGES

# 测试配置
readonly CONNECT_TIMEOUT=10
readonly MAX_TIMEOUT=30
readonly SPEED_TEST_SIZE=1048576  # 1MB
readonly SPEED_TEST_TIMEOUT=60

# 统计计数器
TOTAL_MIRRORS=0
SUCCESSFUL_MIRRORS=0
FAILED_MIRRORS=0

# 测试连通性和响应时间
test_connectivity() {
    local name="$1"
    local url="$2"
    
    if [[ -z "$name" ]] || [[ -z "$url" ]]; then
        log_error "test_connectivity: 参数不能为空"
        return 1
    fi
    
    log_info "测试 $name 连通性..."
    ((TOTAL_MIRRORS++))
    
    # 创建临时文件存储错误信息
    local error_file="$TEMP_DIR/curl_error_${name//[^a-zA-Z0-9]/_}.tmp"
    
    # 测试连通性和响应时间
    local start_time
    local end_time
    local response
    local curl_exit_code
    
    start_time=$(date +%s%N)
    response=$(curl -s -I \
        --connect-timeout "$CONNECT_TIMEOUT" \
        --max-time "$MAX_TIMEOUT" \
        --user-agent "Mirror-Test/1.0" \
        --location \
        "$url" 2>"$error_file")
    curl_exit_code=$?
    end_time=$(date +%s%N)
    
    if [[ $curl_exit_code -eq 0 ]]; then
        local response_time=$(( (end_time - start_time) / 1000000 ))
        local status_code
        status_code=$(echo "$response" | head -n1 | awk '{print $2}' | tr -d '\r')
        
        CONNECTIVITY_RESULTS["$name"]="成功"
        RESPONSE_TIMES["$name"]=$response_time
        STATUS_CODES["$name"]=$status_code
        ERROR_MESSAGES["$name"]=""
        
        if [[ "$status_code" =~ ^(200|302|301)$ ]]; then
            log_success "✓ $name: 连通正常 (${response_time}ms, HTTP $status_code)"
            ((SUCCESSFUL_MIRRORS++))
        else
            log_warning "⚠ $name: 连通但状态异常 (${response_time}ms, HTTP $status_code)"
        fi
    else
        local error_msg=""
        if [[ -f "$error_file" ]]; then
            error_msg=$(cat "$error_file" 2>/dev/null | head -1)
        fi
        
        CONNECTIVITY_RESULTS["$name"]="失败"
        RESPONSE_TIMES["$name"]=999999
        STATUS_CODES["$name"]="N/A"
        ERROR_MESSAGES["$name"]="$error_msg"
        
        log_error "✗ $name: 连接失败 (错误码: $curl_exit_code)"
        if [[ -n "$error_msg" ]]; then
            log_debug "错误详情: $error_msg"
        fi
        ((FAILED_MIRRORS++))
    fi
    
    # 清理临时文件
    rm -f "$error_file"
}

# 测试下载速度
test_download_speed() {
    local name="$1"
    local url="$2"
    
    if [[ -z "$name" ]] || [[ -z "$url" ]]; then
        log_error "test_download_speed: 参数不能为空"
        return 1
    fi
    
    # 只测试连通性正常的镜像源
    if [[ "${CONNECTIVITY_RESULTS[$name]}" != "成功" ]]; then
        DOWNLOAD_SPEEDS["$name"]="N/A"
        log_debug "$name: 跳过速度测试（连通性测试失败）"
        return 0
    fi
    
    log_info "测试 $name 下载速度..."
    
    # 创建临时文件
    local temp_file="$TEMP_DIR/speed_test_${name//[^a-zA-Z0-9]/_}.tmp"
    local error_file="$TEMP_DIR/speed_error_${name//[^a-zA-Z0-9]/_}.tmp"
    
    # 使用高精度时间测量
    local start_time
    local end_time
    local curl_exit_code
    
    start_time=$(date +%s%N)
    
    # 使用curl下载指定大小的数据进行速度测试
    curl -s \
        --connect-timeout "$CONNECT_TIMEOUT" \
        --max-time "$SPEED_TEST_TIMEOUT" \
        --header "Range: bytes=0-$((SPEED_TEST_SIZE - 1))" \
        --user-agent "Mirror-Test/1.0" \
        --location \
        -o "$temp_file" \
        "$url" 2>"$error_file"
    curl_exit_code=$?
    
    end_time=$(date +%s%N)
    
    if [[ $curl_exit_code -eq 0 ]] && [[ -f "$temp_file" ]]; then
        local file_size
        file_size=$(stat -c%s "$temp_file" 2>/dev/null || echo 0)
        local duration_ns=$((end_time - start_time))
        local duration_ms=$((duration_ns / 1000000))
        
        if [[ $duration_ms -gt 0 ]] && [[ $file_size -gt 0 ]]; then
            # 计算速度 (KB/s)
            local speed_kbps=$((file_size * 1000 / duration_ms / 1024))
            
            # 格式化速度显示
            local speed_display
            if [[ $speed_kbps -gt 1024 ]]; then
                local speed_mbps=$((speed_kbps / 1024))
                speed_display="${speed_mbps} MB/s"
            else
                speed_display="${speed_kbps} KB/s"
            fi
            
            DOWNLOAD_SPEEDS["$name"]="$speed_display"
            log_success "✓ $name: 下载速度 $speed_display (${file_size} 字节, ${duration_ms}ms)"
        else
            DOWNLOAD_SPEEDS["$name"]="测试失败"
            log_warning "⚠ $name: 速度测试失败 (时长: ${duration_ms}ms, 大小: ${file_size} 字节)"
        fi
    else
        local error_msg=""
        if [[ -f "$error_file" ]]; then
            error_msg=$(cat "$error_file" 2>/dev/null | head -1)
        fi
        
        DOWNLOAD_SPEEDS["$name"]="下载失败"
        log_error "✗ $name: 下载失败 (错误码: $curl_exit_code)"
        if [[ -n "$error_msg" ]]; then
            log_debug "错误详情: $error_msg"
        fi
    fi
    
    # 清理临时文件
    rm -f "$temp_file" "$error_file"
}

# 生成测试报告
generate_report() {
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local report_file="$REPORT_DIR/mirror_test_report_${timestamp}.txt"
    local json_file="$REPORT_DIR/mirror_test_report_${timestamp}.json"
    
    log_info "生成测试报告..."
    
    # 生成文本报告
    {
        echo "镜像源可用性测试报告"
        echo "========================================"
        echo "测试时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "测试版本: $LATEST_VERSION"
        echo "目标架构: $ARCH"
        echo "测试文件: $TEST_FILE"
        echo "总镜像数: $TOTAL_MIRRORS"
        echo "成功连接: $SUCCESSFUL_MIRRORS"
        echo "连接失败: $FAILED_MIRRORS"
        echo "成功率: $(( SUCCESSFUL_MIRRORS * 100 / TOTAL_MIRRORS ))%"
        echo "========================================"
        echo ""
        
        printf "%-20s %-10s %-15s %-12s %-15s\n" "镜像源名称" "连通性" "响应时间(ms)" "HTTP状态" "下载速度"
        printf "%-20s %-10s %-15s %-12s %-15s\n" "--------------------" "----------" "---------------" "------------" "---------------"
        
        # 按响应时间排序显示结果
        for name in $(for key in "${!RESPONSE_TIMES[@]}"; do 
            echo "$key ${RESPONSE_TIMES[$key]}"
        done | sort -k2 -n | cut -d' ' -f1); do
            local status="${CONNECTIVITY_RESULTS[$name]}"
            local response_time="${RESPONSE_TIMES[$name]}"
            local http_status="${STATUS_CODES[$name]}"
            local download_speed="${DOWNLOAD_SPEEDS[$name]}"
            
            # 格式化响应时间显示
            if [[ "$response_time" == "999999" ]]; then
                response_time="超时"
            fi
            
            printf "%-20s %-10s %-15s %-12s %-15s\n" \
                "$name" \
                "$status" \
                "$response_time" \
                "$http_status" \
                "$download_speed"
        done
        
        echo ""
        echo "推荐使用顺序（按响应时间排序）:"
        echo "========================================"
        local rank=1
        for name in $(for key in "${!RESPONSE_TIMES[@]}"; do 
            echo "$key ${RESPONSE_TIMES[$key]}"
        done | sort -k2 -n | cut -d' ' -f1); do
            if [[ "${CONNECTIVITY_RESULTS[$name]}" == "成功" ]]; then
                local response_time="${RESPONSE_TIMES[$name]}"
                local download_speed="${DOWNLOAD_SPEEDS[$name]}"
                echo "$rank. $name"
                echo "   响应时间: ${response_time}ms"
                echo "   下载速度: $download_speed"
                echo "   HTTP状态: ${STATUS_CODES[$name]}"
                echo ""
                ((rank++))
            fi
        done
        
        # 显示失败的镜像源详情
        if [[ $FAILED_MIRRORS -gt 0 ]]; then
            echo "失败的镜像源详情:"
            echo "========================================"
            for name in "${!CONNECTIVITY_RESULTS[@]}"; do
                if [[ "${CONNECTIVITY_RESULTS[$name]}" == "失败" ]]; then
                    echo "- $name"
                    if [[ -n "${ERROR_MESSAGES[$name]}" ]]; then
                        echo "  错误: ${ERROR_MESSAGES[$name]}"
                    fi
                fi
            done
            echo ""
        fi
        
        echo "测试完成时间: $(date '+%Y-%m-%d %H:%M:%S')"
        
    } | tee "$report_file"
    
    # 生成JSON格式报告
    generate_json_report "$json_file"
    
    log_success "报告已保存:"
    log_info "  文本格式: $report_file"
    log_info "  JSON格式: $json_file"
}

# 生成JSON格式报告
generate_json_report() {
    local json_file="$1"
    local timestamp
    timestamp=$(date -Iseconds)
    
    {
        echo "{"
        echo "  \"timestamp\": \"$timestamp\","
        echo "  \"test_info\": {"
        echo "    \"version\": \"$LATEST_VERSION\","
        echo "    \"architecture\": \"$ARCH\","
        echo "    \"test_file\": \"$TEST_FILE\","
        echo "    \"total_mirrors\": $TOTAL_MIRRORS,"
        echo "    \"successful_mirrors\": $SUCCESSFUL_MIRRORS,"
        echo "    \"failed_mirrors\": $FAILED_MIRRORS,"
        echo "    \"success_rate\": $(( SUCCESSFUL_MIRRORS * 100 / TOTAL_MIRRORS ))"
        echo "  },"
        echo "  \"results\": ["
        
        local first=true
        for name in "${!CONNECTIVITY_RESULTS[@]}"; do
            if [[ "$first" == "true" ]]; then
                first=false
            else
                echo ","
            fi
            
            echo -n "    {"
            echo -n "\"name\": \"$name\", "
            echo -n "\"connectivity\": \"${CONNECTIVITY_RESULTS[$name]}\", "
            echo -n "\"response_time\": ${RESPONSE_TIMES[$name]}, "
            echo -n "\"status_code\": \"${STATUS_CODES[$name]}\", "
            echo -n "\"download_speed\": \"${DOWNLOAD_SPEEDS[$name]}\""
            if [[ -n "${ERROR_MESSAGES[$name]}" ]]; then
                echo -n ", \"error\": \"${ERROR_MESSAGES[$name]}\""
            fi
            echo -n "}"
        done
        
        echo ""
        echo "  ]"
        echo "}"
    } > "$json_file"
}

# 显示帮助信息
show_help() {
    cat << 'EOF'
镜像源可用性测试工具

用法: test_mirror_sources.sh [选项]

选项:
  -c, --connectivity-only    仅测试连通性，跳过下载速度测试
  -s, --speed-only          仅测试下载速度（需要先通过连通性测试）
  -v, --verbose             详细输出模式
  -q, --quiet               静默模式，仅输出错误信息
  -o, --output DIR          指定报告输出目录
  --version VERSION         指定要测试的版本（默认: v1.8.0）
  --arch ARCH               指定目标架构（默认: amd64）
  --timeout SECONDS         设置连接超时时间（默认: 10秒）
  --no-proxy                禁用代理设置
  -h, --help                显示此帮助信息

示例:
  test_mirror_sources.sh                    # 完整测试
  test_mirror_sources.sh -c                 # 仅测试连通性
  test_mirror_sources.sh -v                 # 详细输出
  test_mirror_sources.sh --version v1.9.0   # 测试指定版本
  test_mirror_sources.sh --arch arm64       # 测试ARM64架构

支持的架构: amd64, arm64, armv7, 386

EOF
}

# 主测试流程
main() {
    local connectivity_only=false
    local speed_only=false
    local verbose=false
    local quiet=false
    local no_proxy=false
    local custom_output_dir=""
    local custom_version=""
    local custom_arch=""
    local custom_timeout=""
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--connectivity-only)
                connectivity_only=true
                shift
                ;;
            -s|--speed-only)
                speed_only=true
                shift
                ;;
            -v|--verbose)
                verbose=true
                export DEBUG=1
                shift
                ;;
            -q|--quiet)
                quiet=true
                shift
                ;;
            -o|--output)
                custom_output_dir="$2"
                shift 2
                ;;
            --version)
                custom_version="$2"
                shift 2
                ;;
            --arch)
                custom_arch="$2"
                shift 2
                ;;
            --timeout)
                custom_timeout="$2"
                shift 2
                ;;
            --no-proxy)
                no_proxy=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # 应用自定义配置
    if [[ -n "$custom_version" ]]; then
        LATEST_VERSION="$custom_version"
        TEST_FILE="sing-box-${LATEST_VERSION#v}-linux-${ARCH}.tar.gz"
    fi
    
    if [[ -n "$custom_arch" ]]; then
        ARCH="$custom_arch"
        TEST_FILE="sing-box-${LATEST_VERSION#v}-linux-${ARCH}.tar.gz"
    fi
    
    if [[ -n "$custom_timeout" ]]; then
        CONNECT_TIMEOUT="$custom_timeout"
    fi
    
    if [[ -n "$custom_output_dir" ]]; then
        REPORT_DIR="$custom_output_dir"
        mkdir -p "$REPORT_DIR"
    fi
    
    # 更新镜像源URL
    for name in "${!MIRROR_SOURCES[@]}"; do
        local base_url="${MIRROR_SOURCES[$name]}"
        base_url="${base_url%/*}"  # 移除文件名
        MIRROR_SOURCES["$name"]="${base_url}/${TEST_FILE}"
    done
    
    # 设置日志级别
    if [[ "$quiet" == "true" ]]; then
        export LOG_LEVEL="ERROR"
    elif [[ "$verbose" == "true" ]]; then
        export LOG_LEVEL="DEBUG"
    fi
    
    log_info "镜像源可用性测试工具启动"
    log_info "测试配置:"
    log_info "  版本: $LATEST_VERSION"
    log_info "  架构: $ARCH"
    log_info "  测试文件: $TEST_FILE"
    log_info "  连接超时: ${CONNECT_TIMEOUT}秒"
    log_info "  报告目录: $REPORT_DIR"
    log_info "  仅连通性: $([ "$connectivity_only" = true ] && echo "是" || echo "否")"
    log_info "  仅速度测试: $([ "$speed_only" = true ] && echo "是" || echo "否")"
    
    # 检测代理设置
    if [[ "$no_proxy" != "true" ]] && setup_proxy 2>/dev/null; then
        log_success "检测到代理设置，将通过代理测试"
    else
        log_info "使用直连测试"
    fi
    
    echo ""
    
    # 第一阶段：测试连通性
    if [[ "$speed_only" != "true" ]]; then
        log_info "=== 第一阶段：连通性测试 ==="
        for name in "${!MIRROR_SOURCES[@]}"; do
            test_connectivity "$name" "${MIRROR_SOURCES[$name]}"
        done
        echo ""
    fi
    
    # 第二阶段：测试下载速度
    if [[ "$connectivity_only" != "true" ]]; then
        log_info "=== 第二阶段：下载速度测试 ==="
        for name in "${!MIRROR_SOURCES[@]}"; do
            test_download_speed "$name" "${MIRROR_SOURCES[$name]}"
        done
        echo ""
    fi
    
    # 生成报告
    generate_report
    
    # 显示测试总结
    echo ""
    log_success "镜像源测试完成！"
    log_info "测试总结:"
    log_info "  总镜像数: $TOTAL_MIRRORS"
    log_info "  成功连接: $SUCCESSFUL_MIRRORS"
    log_info "  连接失败: $FAILED_MIRRORS"
    log_info "  成功率: $(( TOTAL_MIRRORS > 0 ? SUCCESSFUL_MIRRORS * 100 / TOTAL_MIRRORS : 0 ))%"
    
    # 清理临时文件
    if [[ -d "$TEMP_DIR" ]] && [[ "$TEMP_DIR" != "$SCRIPT_DIR" ]]; then
        find "$TEMP_DIR" -name "speed_test_*.tmp" -o -name "curl_error_*.tmp" -o -name "speed_error_*.tmp" | xargs rm -f 2>/dev/null || true
    fi
    
    # 返回适当的退出码
    if [[ $FAILED_MIRRORS -eq $TOTAL_MIRRORS ]]; then
        log_error "所有镜像源测试失败"
        exit 1
    elif [[ $FAILED_MIRRORS -gt 0 ]]; then
        log_warning "部分镜像源测试失败"
        exit 2
    else
        exit 0
    fi
}

# 如果直接运行此脚本，则执行主函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi