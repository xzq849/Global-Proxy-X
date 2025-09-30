#!/bin/bash

# 测试套件脚本
# 提供全面的测试和验证机制

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载通用函数库
if [[ -f "$SCRIPT_DIR/common_functions.sh" ]]; then
    source "$SCRIPT_DIR/common_functions.sh"
else
    echo "错误: 找不到通用函数库 common_functions.sh"
    exit 1
fi

# 初始化
init_common

# 测试配置
TEST_LOG_FILE="${LOG_DIR}/test_results.log"
TEST_REPORT_FILE="${LOG_DIR}/test_report.html"
TEST_TIMEOUT=30
PARALLEL_TESTS=4

# 测试结果统计
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# 测试开始时间
TEST_START_TIME=""

# 初始化测试环境
init_test_environment() {
    log_info "初始化测试环境..."
    export SKIP_CLEANUP=true
    
    # 创建测试日志目录
    mkdir -p "$(dirname "$TEST_LOG_FILE")"
    mkdir -p "$(dirname "$TEST_REPORT_FILE")"
    
    # 清空之前的测试结果
    > "$TEST_LOG_FILE"
    
    # 记录测试开始时间
    TEST_START_TIME=$(date +%s)
    
    log_info "测试环境初始化完成"
}

# 运行单个测试
run_test() {
    local test_name="$1"
    local test_function_or_command="$2"
    local test_description="${3:-$test_name}"
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    
    log_info "Running test: $test_description"
    echo "[$test_name] STARTING TEST: $test_description" >> "$TEST_LOG_FILE"
    
    local start_time=$(date +%s)
    local result=0
    local output
    local exit_code
    
    local command_to_run
    # Check if the second argument is a declared function
    if [[ $(type -t "$test_function_or_command") == "function" ]]; then
        echo "  - Test type: function" >> "$TEST_LOG_FILE"
        echo "  - Test function: $test_function_or_command" >> "$TEST_LOG_FILE"
        # If it's a function, we need to export it to the subshell
        command_to_run="
            SCRIPT_DIR='${SCRIPT_DIR}';
            source '${SCRIPT_DIR}/common_functions.sh';
            $(declare -f "$test_function_or_command");
            $test_function_or_command
        "
        output=$(timeout "$TEST_TIMEOUT" bash -c "$command_to_run" 2>&1)
        exit_code=$?
    else
        echo "  - Test type: command" >> "$TEST_LOG_FILE"
        echo "  - Test command: $test_function_or_command" >> "$TEST_LOG_FILE"
        # If it's not a function, assume it's a shell command string
        output=$(timeout "$TEST_TIMEOUT" bash -c "$test_function_or_command" 2>&1)
        exit_code=$?
    fi
    
    echo "  - Exit code: $exit_code" >> "$TEST_LOG_FILE"
    echo "  - Output:" >> "$TEST_LOG_FILE"
    echo "$output" >> "$TEST_LOG_FILE"

    if [[ $exit_code -eq 0 ]]; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        TESTS_PASSED=$((TESTS_PASSED + 1))
        log_success "Test PASSED: $test_description (Duration: ${duration}s)"
        echo "[$test_name] PASSED (Duration: ${duration}s)" >> "$TEST_LOG_FILE"
    elif [[ $exit_code -eq 124 ]]; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))

        TESTS_FAILED=$((TESTS_FAILED + 1))
        log_error "Test FAILED (Timeout): $test_description (after ${TEST_TIMEOUT}s)"
        echo "[$test_name] FAILED (Timeout after ${TEST_TIMEOUT}s)" >> "$TEST_LOG_FILE"
        result=1
    else
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        TESTS_FAILED=$((TESTS_FAILED + 1))
        log_error "Test FAILED: $test_description (Duration: ${duration}s, Exit Code: $exit_code)"
        echo "[$test_name] FAILED (Duration: ${duration}s, Exit Code: $exit_code)" >> "$TEST_LOG_FILE"
        result=1
    fi
    
    echo "----------------------------------------" >> "$TEST_LOG_FILE"
    return $result
}

# 跳过测试
skip_test() {
    local test_name="$1"
    local reason="${2:-未指定原因}"
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    
    log_warn "跳过测试: $test_name - $reason"
    echo "[$test_name] 跳过测试: $reason" >> "$TEST_LOG_FILE"
}

# 系统环境测试
test_system_environment() {
    log_info "开始系统环境测试..."
    
    # 测试操作系统
    run_test "os_check" "test_os_compatibility" "操作系统兼容性检查"
    
    # 测试系统资源
    run_test "memory_check" "test_memory_requirements" "内存需求检查"
    run_test "disk_check" "test_disk_space" "磁盘空间检查"
    
    # 测试网络连接
    run_test "network_check" "test_network_connectivity" "网络连接测试"
    
    # 测试权限
    run_test "permission_check" "test_permissions" "权限检查"
}

# 操作系统兼容性测试
test_os_compatibility() {
    local os_name=$(uname -s)
    local arch=$(uname -m)
    
    case "$os_name" in
        "Linux")
            echo "检测到Linux系统: $os_name"
            return 0
            ;;
        "Darwin")
            echo "检测到macOS系统: $os_name"
            return 0
            ;;
        *)
            echo "不支持的操作系统: $os_name"
            return 1
            ;;
    esac
}

# 内存需求测试
test_memory_requirements() {
    local required_memory=512  # MB
    local available_memory
    
    if command -v free &>/dev/null; then
        available_memory=$(free -m | awk 'NR==2{print $7}')
    elif [[ -f /proc/meminfo ]]; then
        available_memory=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo)
    else
        echo "无法检测内存信息"
        return 1
    fi
    
    if [[ $available_memory -ge $required_memory ]]; then
        echo "内存检查通过: ${available_memory}MB 可用 (需要: ${required_memory}MB)"
        return 0
    else
        echo "内存不足: ${available_memory}MB 可用 (需要: ${required_memory}MB)"
        return 1
    fi
}

# 磁盘空间测试
test_disk_space() {
    local required_space=1024  # MB
    local available_space
    
    available_space=$(df "$SCRIPT_DIR" | awk 'NR==2 {print int($4/1024)}')
    
    if [[ $available_space -ge $required_space ]]; then
        echo "磁盘空间检查通过: ${available_space}MB 可用 (需要: ${required_space}MB)"
        return 0
    else
        echo "磁盘空间不足: ${available_space}MB 可用 (需要: ${required_space}MB)"
        return 1
    fi
}

# 网络连接测试
test_network_connectivity() {
    local test_urls=(
        "https://github.com"
        "https://api.github.com"
        "https://raw.githubusercontent.com"
    )
    
    for url in "${test_urls[@]}"; do
        if safe_curl -s -I "$url"; then
            echo "网络连接正常: $url"
        else
            echo "网络连接失败: $url"
            return 1
        fi
    done
    
    return 0
}

# 权限测试
test_permissions() {
    # 测试读权限
    if [[ -r "$SCRIPT_DIR" ]]; then
        echo "目录读权限正常: $SCRIPT_DIR"
    else
        echo "目录读权限不足: $SCRIPT_DIR"
        return 1
    fi
    
    # 测试写权限
    local test_file="$SCRIPT_DIR/.test_write_permission"
    if touch "$test_file" 2>/dev/null; then
        echo "目录写权限正常: $SCRIPT_DIR"
        rm -f "$test_file"
    else
        echo "目录写权限不足: $SCRIPT_DIR"
        return 1
    fi
    
    return 0
}

# 依赖项测试
test_dependencies() {
    log_info "开始依赖项测试..."
    
    run_test "curl_check" "test_curl_availability" "curl工具检查"
    run_test "jq_check" "test_jq_availability" "jq工具检查"
    run_test "systemctl_check" "test_systemctl_availability" "systemctl检查"
}

# curl可用性测试
test_curl_availability() {
    if command -v curl &>/dev/null; then
        local version=$(curl --version | head -n1)
        echo "curl可用: $version"
        return 0
    else
        echo "curl不可用"
        return 1
    fi
}

# jq可用性测试
test_jq_availability() {
    if ! command -v jq &>/dev/null; then
        echo "jq not found, attempting to download and install..."
        local jq_url="https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64"
        local jq_path="$SCRIPT_DIR/jq"
        if safe_curl "$jq_url" -o "$jq_path" && chmod +x "$jq_path"; then
            echo "jq downloaded and installed successfully."
            export PATH="$SCRIPT_DIR:$PATH"
        else
            echo "Failed to download and install jq."
            return 1
        fi
    fi
    
    local version=$(jq --version)
    echo "jq is available: $version"
    return 0
}

# systemctl可用性测试
test_systemctl_availability() {
    if command -v systemctl &>/dev/null; then
        echo "systemctl可用"
        return 0
    else
        echo "systemctl不可用"
        return 1
    fi
}

# 脚本语法测试
test_script_syntax() {
    log_info "开始脚本语法测试..."
    
    # 动态查找所有.sh脚本文件
    local scripts
    scripts=$(find "$SCRIPT_DIR" -maxdepth 1 -name "*.sh")
    
    for script in $scripts; do
        run_test "syntax_$(basename "$script")" "bash -n '$script'" "语法检查: $(basename "$script")"
    done
}

# 配置文件测试
    test_configuration() {
        log_info "开始配置文件测试..."
        
        run_test "config_env" "test_config_env_file" "config.env配置文件测试"
        run_test "config_load" "test_config_loading" "配置加载测试"
    }

    # config.env文件测试
    test_config_env_file() {
        local config_file="$SCRIPT_DIR/config.env"
        
        if [[ -f "$config_file" ]]; then
            echo "配置文件存在: $config_file"
            
            # 检查关键配置项
            local required_vars=(
                "SING_BOX_CONFIG_DIR"
                "SING_BOX_CONFIG_FILE"
                "SUBSCRIPTION_DIR"
                "BACKUP_DIR"
                "LOG_DIR"
                "TEMP_DIR"
                "RETRY_COUNT"
                "RETRY_DELAY"
                "CONNECT_TIMEOUT"
                "MAX_TIMEOUT"
                "COLOR_OUTPUT"
                "VERBOSE_LOGGING"
                "SHOW_PROGRESS"
            )
            
            for var in "${required_vars[@]}"; do
                if grep -q -E "^${var}=.*" "$config_file"; then
                echo "配置项存在: $var"
            else
                echo "配置项缺失: $var"
                return 1
            fi
        done
        
        return 0
    else
        echo "配置文件不存在: $config_file"
        return 1
    fi
}

# 配置加载测试
test_config_loading() {
    # 测试加载配置
    if load_config; then
        echo "配置加载成功"
        
        # 检查关键变量是否已设置
        if [[ -n "$CONFIG_DIR" && -n "$LOG_DIR" ]]; then
            echo "关键配置变量已设置"
            return 0
        else
            echo "关键配置变量未设置"
            return 1
        fi
    else
        echo "配置加载失败"
        return 1
    fi
}

# 功能测试
test_functionality() {
    log_info "开始功能测试..."
    
    run_test "common_functions" "test_common_functions" "通用函数测试"
    run_test "logging" "test_logging_functions" "日志功能测试"
    run_test "network_functions" "test_network_functions" "网络功能测试"
}

# 通用函数测试
test_common_functions() {
    # 测试颜色设置
    if setup_colors; then
        echo "颜色设置功能正常"
    else
        echo "颜色设置功能异常"
        return 1
    fi
    
    # 测试系统检查
    if check_system; then
        echo "系统检查功能正常"
    else
        echo "系统检查功能异常"
        return 1
    fi
    
    return 0
}

# 日志功能测试
test_logging_functions() {
    local test_log="/tmp/test_logging.log"
    
    # 重定向日志到测试文件
    LOG_FILE="$test_log"
    
    # 测试各种日志级别
    log_info "测试信息日志"
    log_warn "测试警告日志"
    log_error "测试错误日志"
    log_debug "测试调试日志"
    log_success "测试成功日志"
    
    # 检查日志文件是否创建并包含内容
    if [[ -f "$test_log" && -s "$test_log" ]]; then
        echo "日志功能正常"
        rm -f "$test_log"
        return 0
    else
        echo "日志功能异常"
        return 1
    fi
}

# 网络功能测试
test_network_functions() {
    # 测试safe_curl函数
    if safe_curl -s --head "https://httpbin.org/status/200" &>/dev/null; then
        echo "safe_curl功能正常"
        return 0
    else
        echo "safe_curl功能异常"
        return 1
    fi
}

# 性能测试
test_performance() {
    log_info "开始性能测试..."
    
    run_test "script_execution_time" "test_script_execution_time" "脚本执行时间测试"
    run_test "memory_usage" "test_memory_usage" "内存使用测试"
}

# 脚本执行时间测试
test_script_execution_time() {
    local start_time=$(date +%s.%N)
    
    # 执行一个简单的脚本操作
    bash -c "source '$SCRIPT_DIR/common_functions.sh'; init_common"
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc)
    
    echo "脚本初始化耗时: ${duration}秒"
    
    # 检查是否在合理时间内完成
    if (( $(echo "$duration < 5.0" | bc -l) )); then
        return 0
    else
        return 1
    fi
}

# 内存使用测试
test_memory_usage() {
    local initial_memory=$(ps -o rss= -p $$)
    
    # 执行一些操作
    source "$SCRIPT_DIR/common_functions.sh"
    init_common
    
    local final_memory=$(ps -o rss= -p $$)
    local memory_increase=$((final_memory - initial_memory))
    
    echo "内存使用增加: ${memory_increase}KB"
    
    # 检查内存使用是否合理（小于50MB）
    if [[ $memory_increase -lt 51200 ]]; then
        return 0
    else
        return 1
    fi
}

# 生成测试报告
generate_test_report() {
    local end_time=$(date +%s)
    local total_duration=$((end_time - TEST_START_TIME))
    
    log_info "生成测试报告..."
    
    # 生成HTML报告
    cat > "$TEST_REPORT_FILE" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Sing-box 项目测试报告</title>
    <meta charset="UTF-8">
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background: #f0f0f0; padding: 20px; border-radius: 5px; }
        .summary { margin: 20px 0; }
        .passed { color: green; }
        .failed { color: red; }
        .skipped { color: orange; }
        .details { margin-top: 20px; }
        pre { background: #f5f5f5; padding: 10px; border-radius: 3px; overflow-x: auto; white-space: pre-wrap; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Sing-box 项目测试报告</h1>
        <p>生成时间: $(date '+%Y-%m-%d %H:%M:%S')</p>
        <p>测试耗时: ${total_duration}秒</p>
    </div>
    
    <div class="summary">
        <h2>测试摘要</h2>
        <ul>
            <li>总测试数: $TESTS_TOTAL</li>
            <li class="passed">通过: $TESTS_PASSED</li>
            <li class="failed">失败: $TESTS_FAILED</li>
            <li class="skipped">跳过: $TESTS_SKIPPED</li>
        </ul>
        
        <p>成功率: $(( TESTS_TOTAL > 0 ? TESTS_PASSED * 100 / TESTS_TOTAL : 0 ))%</p>
    </div>
    
    <div class="details">
        <h2>详细日志</h2>
        <pre>$(cat "$TEST_LOG_FILE")</pre>
    </div>
</body>
</html>
EOF
    
    log_success "测试报告已生成: $TEST_REPORT_FILE"
}

# 显示测试结果
show_test_results() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${CYAN}测试结果摘要${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "总测试数: ${BLUE}$TESTS_TOTAL${NC}"
    echo -e "通过: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "失败: ${RED}$TESTS_FAILED${NC}"
    echo -e "跳过: ${YELLOW}$TESTS_SKIPPED${NC}"
    
    if [[ $TESTS_TOTAL -gt 0 ]]; then
        local success_rate=$((TESTS_PASSED * 100 / TESTS_TOTAL))
        echo -e "成功率: ${BLUE}${success_rate}%${NC}"
    fi
    
    local end_time=$(date +%s)
    local total_duration=$((end_time - TEST_START_TIME))
    echo -e "总耗时: ${BLUE}${total_duration}秒${NC}"
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        log_success "所有测试通过！"
        return 0
    else
        log_error "有 $TESTS_FAILED 个测试失败"
        return 1
    fi
}

# 运行所有测试
run_all_tests() {
    init_test_environment
    
    log_info "开始运行完整测试套件..."
    
    # 运行各类测试
    test_system_environment
    test_dependencies
    test_script_syntax
    test_configuration
    test_functionality
    test_performance
    
    # 生成报告
    generate_test_report
    
    # 显示结果
    show_test_results
}

# 运行快速测试
run_quick_tests() {
    init_test_environment
    
    log_info "开始运行快速测试..."
    
    # 只运行关键测试
    test_system_environment
    test_dependencies
    test_script_syntax
    
    show_test_results
}

# 显示帮助信息
show_help() {
    echo "测试套件使用说明:"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  all          运行所有测试 (默认)"
    echo "  quick        运行快速测试"
    echo "  system       仅运行系统环境测试"
    echo "  deps         仅运行依赖项测试"
    echo "  syntax       仅运行语法测试"
    echo "  config       仅运行配置测试"
    echo "  function     仅运行功能测试"
    echo "  performance  仅运行性能测试"
    echo "  report       生成测试报告"
    echo "  help         显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 all       # 运行完整测试套件"
    echo "  $0 quick     # 运行快速测试"
    echo "  $0 syntax    # 仅检查脚本语法"
}

# 主函数
main() {
    case "${1:-all}" in
        "all")
            run_all_tests
            ;;
        "quick")
            run_quick_tests
            ;;
        "system")
            init_test_environment
            test_system_environment
            show_test_results
            ;;
        "deps")
            init_test_environment
            test_dependencies
            show_test_results
            ;;
        "syntax")
            init_test_environment
            test_script_syntax
            show_test_results
            ;;
        "config")
            init_test_environment
            test_configuration
            show_test_results
            ;;
        "function")
            init_test_environment
            test_functionality
            show_test_results
            ;;
        "performance")
            init_test_environment
            test_performance
            show_test_results
            ;;
        "report")
            if [[ -f "$TEST_LOG_FILE" ]]; then
                generate_test_report
            else
                log_error "没有找到测试日志文件，请先运行测试"
                exit 1
            fi
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            log_error "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"