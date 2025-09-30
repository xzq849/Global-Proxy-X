#!/bin/bash
set -euo pipefail

# 通用函数库
# 提供所有脚本共用的函数和工具

# 加载配置文件
load_config() {
    local script_dir="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
    local config_file="${1:-$script_dir/config.env}"
    if [[ -f "$config_file" ]]; then
        source "$config_file"
    else
        echo "警告: 配置文件不存在: $config_file"
        echo "使用默认配置..."
        # 设置默认配置
        SING_BOX_CONFIG_DIR="/etc/sing-box"
        SING_BOX_CONFIG_FILE="/etc/sing-box/config.json"
        SUBSCRIPTION_DIR="/etc/sing-box/subscriptions"
        BACKUP_DIR="/etc/sing-box/backup"
        LOG_DIR="/var/log/sing-box"
    fi
}

# 颜色定义（支持终端检测）
setup_colors() {
    if [[ -t 1 ]] && [[ "${COLOR_OUTPUT:-true}" == "true" ]]; then
        RED='\033[0;31m'
        GREEN='\033[0;32m'
        YELLOW='\033[1;33m'
        BLUE='\033[0;34m'
        PURPLE='\033[0;35m'
        CYAN='\033[0;36m'
        WHITE='\033[1;37m'
        NC='\033[0m' # No Color
    else
        RED=''
        GREEN=''
        YELLOW=''
        BLUE=''
        PURPLE=''
        CYAN=''
        WHITE=''
        NC=''
    fi
}

# 显示横幅
display_banner() {
    echo -e "${PURPLE}=======================================================================${NC}"
    echo -e "${CYAN}                        Sing-Box 全能脚本                        ${NC}"
    echo -e "${BLUE}         一个集安装、优化、安全、管理于一体的综合工具         ${NC}"
    echo -e "${PURPLE}=======================================================================${NC}"
    echo -e "版本: ${GREEN}1.0.0${NC}"
    echo -e "作者: ${GREEN}Your Name${NC}"
    echo -e "Github: ${GREEN}https://github.com/your-repo${NC}"
    echo -e "======================================================================="
}

# 增强的日志函数
log_info() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${GREEN}[INFO]${NC} ${timestamp} $1" | tee -a "${LOG_FILE:-/tmp/install.log}"
}

log_warn() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${YELLOW}[WARN]${NC} ${timestamp} $1" | tee -a "${LOG_FILE:-/tmp/install.log}"
}

log_error() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${RED}[ERROR]${NC} ${timestamp} $1" | tee -a "${LOG_FILE:-/tmp/install.log}"
}

log_debug() {
    if [[ "${VERBOSE_LOGGING:-false}" == "true" ]]; then
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        echo -e "${CYAN}[DEBUG]${NC} ${timestamp} $1" | tee -a "${LOG_FILE:-/tmp/install.log}"
    fi
}

log_success() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${GREEN}[SUCCESS]${NC} ${timestamp} $1" | tee -a "${LOG_FILE:-/tmp/install.log}"
}

# 错误处理函数
setup_error_handling() {
    set -euo pipefail
    
    # 错误陷阱
    trap 'handle_error $? $LINENO $BASH_LINENO "$BASH_COMMAND" $(printf "%s " "${FUNCNAME[@]}")' ERR
    
    # 退出陷阱
    trap 'cleanup_on_exit' EXIT
    
    # 中断陷阱
    trap 'handle_interrupt' INT TERM
}

# 错误处理器
handle_error() {
    local exit_code=$1
    local line_number=$2
    local bash_line_number=$3
    local last_command=$4
    local function_stack=${5:-"未知"}
    
    log_error "脚本执行失败!"
    log_error "退出码: $exit_code"
    log_error "错误行号: $line_number (Bash 行号: $bash_line_number)"
    log_error "失败命令: $last_command"
    log_error "函数调用栈: $function_stack"
    
    # 尝试提供解决建议
    case $exit_code in
        1) log_error "建议: 检查命令语法和参数" ;;
        2) log_error "建议: 检查文件权限和路径" ;;
        126) log_error "建议: 检查文件执行权限" ;;
        127) log_error "建议: 检查命令是否存在或路径是否正确" ;;
        *) log_error "建议: 查看详细日志获取更多信息" ;;
    esac
}

# 中断处理器
handle_interrupt() {
    log_warn "收到中断信号，正在清理..."
    cleanup_on_exit
    exit 130
}

# 清理函数
cleanup_on_exit() {
    if [[ "${SKIP_CLEANUP:-false}" == "true" ]]; then
        log_debug "跳过清理操作..."
        return
    fi

    log_debug "执行清理操作..."
    
    # 清理临时文件
    if [[ -n "${TEMP_DIR:-}" ]] && [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        log_debug "已清理临时目录: $TEMP_DIR"
    fi
    
    # 清理临时变量
    unset TEMP_FILE TEMP_DIR
}

# 权限检查
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行"
        log_error "请使用: sudo $0"
        exit 1
    fi
}

check_user() {
    local required_user="$1"
    if [[ "$(whoami)" != "$required_user" ]]; then
        log_error "此脚本需要以 $required_user 用户运行"
        exit 1
    fi
}

# 系统检查
check_system() {
    log_info "检查系统环境..."
    
    # 检查操作系统
    if [[ ! -f /etc/os-release ]]; then
        log_error "无法识别操作系统"
        exit 1
    fi
    
    source /etc/os-release
    local os_id="${ID,,}"
    
    if [[ ! " ${SUPPORTED_OS[*]} " =~ " $os_id " ]]; then
        log_error "不支持的操作系统: $os_id"
        log_error "支持的系统: ${SUPPORTED_OS[*]}"
        exit 1
    fi
    
    log_success "操作系统检查通过: $PRETTY_NAME"
    
    # 检查架构
    local arch=$(uname -m)
    case $arch in
        x86_64) arch="amd64" ;;
        aarch64) arch="arm64" ;;
        armv7l) arch="armv7" ;;
        *) 
            log_error "不支持的架构: $arch"
            exit 1
            ;;
    esac
    
    log_success "系统架构检查通过: $arch"
    export SYSTEM_ARCH="$arch"
}

# 依赖检查
check_dependencies() {
    log_info "检查依赖工具..."
    
    local required_tools=("curl" "wget" "jq" "systemctl" "unzip" "nc")
    local missing_tools=()
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "缺少必要工具: ${missing_tools[*]}"
        log_info "正在尝试安装缺少的工具..."
        install_dependencies "${missing_tools[@]}"
        
        # 再次检查
        for tool in "${missing_tools[@]}"; do
            if ! command -v "$tool" &> /dev/null; then
                log_error "工具 '$tool' 安装失败，请手动安装后重试。"
                exit 1
            fi
        done
        log_success "所有缺少的依赖已成功安装。"
    else
        log_success "所有依赖工具已安装"
    fi
}

# 安装依赖
install_dependencies() {
    local tools=("$@")
    
    # 检测包管理器
    if command -v apt-get &> /dev/null; then
        apt-get update
        apt-get install -y "${tools[@]}"
    elif command -v yum &> /dev/null; then
        yum install -y "${tools[@]}"
    elif command -v dnf &> /dev/null; then
        dnf install -y "${tools[@]}"
    else
        log_error "无法识别包管理器"
        exit 1
    fi
}

# 检测并设置代理
setup_proxy() {
    # 检测常见代理环境变量
    if [[ -n "${HTTP_PROXY:-}" ]] || [[ -n "${http_proxy:-}" ]] || [[ -n "${HTTPS_PROXY:-}" ]] || [[ -n "${https_proxy:-}" ]]; then
        log_info "检测到代理设置，将使用代理下载"
        return 0
    fi
    
    # 检测常见代理端口
    local common_ports=("7890" "1080" "8080" "3128")
    for port in "${common_ports[@]}"; do
        if nc -z 127.0.0.1 "$port" 2>/dev/null; then
            export HTTP_PROXY="http://127.0.0.1:$port"
            export HTTPS_PROXY="http://127.0.0.1:$port"
            log_info "检测到本地代理端口 $port，自动设置代理"
            return 0
        fi
    done
    
    return 1
}

# 增强的网络请求函数
safe_curl() {
    local max_retries="${RETRY_COUNT:-3}"
    local retry_delay="${RETRY_DELAY:-2}"
    
    # 尝试设置代理
    setup_proxy
    
    local curl_opts=(
        --location
        --connect-timeout "${CONNECT_TIMEOUT:-8}"
        --max-time "${MAX_TIMEOUT:-60}"
        --retry "$max_retries"
        --retry-delay "$retry_delay"
        --retry-connrefused
        --retry-max-time 180
        --user-agent "Mozilla/5.0 (Linux; x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
        --header "Accept: application/json,application/octet-stream,*/*;q=0.9"
        --header "Accept-Language: zh-CN,zh;q=0.9,en;q=0.8"
        --header "Cache-Control: no-cache"
        --compressed
        --tcp-fastopen
        --tcp-nodelay
        --keepalive-time 60
        # DNS优化（仅在支持的curl版本中启用）
        # --dns-servers "223.5.5.5,8.8.8.8,1.1.1.1"
        # --resolve "api.github.com:443:140.82.112.5"
        # --resolve "github.com:443:140.82.112.3"
        --insecure
    )
    
    log_debug "Running curl with options: ${curl_opts[*]} $*"
    
    if curl "${curl_opts[@]}" "$@"; then
        log_debug "Network request successful"
        return 0
    else
        local exit_code=$?
        log_error "Network request failed with exit code: $exit_code"
        return $exit_code
    fi
}

# 进度显示函数
show_progress() {
    local current="$1"
    local total="$2"
    local message="${3:-处理中}"
    
    if [[ "${SHOW_PROGRESS:-true}" != "true" ]]; then
        return
    fi
    
    local percent=$((current * 100 / total))
    local filled=$((percent / 2))
    local empty=$((50 - filled))
    
    printf "\r${BLUE}%s${NC} [" "$message"
    printf "%*s" $filled | tr ' ' '#'
    printf "%*s" $empty | tr ' ' '-'
    printf "] %d%% (%d/%d)" $percent $current $total
    
    if [[ $current -eq $total ]]; then
        echo ""
    fi
}

# 文件操作函数
safe_backup() {
    local file="$1"
    local backup_dir="${BACKUP_DIR:-/tmp/backup}"
    
    if [[ ! -f "$file" ]]; then
        log_warn "备份文件不存在: $file"
        return 1
    fi
    
    mkdir -p "$backup_dir"
    local backup_file="$backup_dir/$(basename "$file").$(date +%Y%m%d_%H%M%S).bak"
    
    if cp "$file" "$backup_file"; then
        log_success "文件已备份: $backup_file"
        return 0
    else
        log_error "文件备份失败: $file"
        return 1
    fi
}

safe_download() {
    local url="$1"
    local output_file="$2"
    local expected_size="${3:-}"
    
    log_info "下载文件: $(basename "$output_file")"
    
    # 创建输出目录
    mkdir -p "$(dirname "$output_file")"
    
    # 下载文件
    if safe_curl "$url" "$output_file"; then
        # 验证文件大小
        if [[ -n "$expected_size" ]]; then
            local actual_size=$(stat -c%s "$output_file" 2>/dev/null || echo "0")
            if [[ "$actual_size" -lt "$expected_size" ]]; then
                log_error "下载文件大小异常: $actual_size < $expected_size"
                rm -f "$output_file"
                return 1
            fi
        fi
        
        log_success "文件下载完成: $(basename "$output_file")"
        return 0
    else
        log_error "文件下载失败: $url"
        return 1
    fi
}

# 服务管理函数
manage_service() {
    local action="$1"
    local service="$2"
    
    log_info "${action} 服务: $service"
    
    case "$action" in
        start|stop|restart|enable|disable)
            if systemctl "$action" "$service"; then
                log_success "服务 $service $action 成功"
                return 0
            else
                log_error "服务 $service $action 失败"
                return 1
            fi
            ;;
        status)
            systemctl status "$service" --no-pager
            ;;
        *)
            log_error "不支持的服务操作: $action"
            return 1
            ;;
    esac
}

# 端口检查函数
check_port() {
    local port="$1"
    local protocol="${2:-tcp}"
    
    if ss -tuln | grep -q ":$port\b"; then
        log_warn "端口 $port ($protocol) 已被占用"
        return 1
    else
        log_success "端口 $port ($protocol) 可用"
        return 0
    fi
}

# 网络连通性检查
check_connectivity() {
    local host="${1:-8.8.8.8}"
    local port="${2:-53}"
    local timeout="${3:-5}"
    
    log_debug "使用 'nc' 检查到 $host:$port 的连通性..."
    if nc -z -w "$timeout" "$host" "$port"; then
        log_success "网络连通性检查通过 (主机: $host, 端口: $port)"
        return 0
    else
        log_error "网络连通性检查失败 (主机: $host, 端口: $port)"
        return 1
    fi
}

# 初始化函数
init_common() {
    # 加载配置
    load_config
    
    # 设置颜色
    setup_colors
    
    # 设置错误处理
    setup_error_handling
    
    # 转换相对路径为绝对路径并导出
    if [[ "${LOG_DIR:-}" =~ ^\. ]]; then
        LOG_DIR="$(pwd)/${LOG_DIR#./}"
        export LOG_DIR
    fi
    if [[ "${LOG_FILE:-}" =~ ^\. ]]; then
        LOG_FILE="$(pwd)/${LOG_FILE#./}"
        export LOG_FILE
    fi
    if [[ "${BACKUP_DIR:-}" =~ ^\. ]]; then
        BACKUP_DIR="$(pwd)/${BACKUP_DIR#./}"
        export BACKUP_DIR
    fi
    if [[ "${TEMP_DIR:-}" =~ ^\. ]]; then
        TEMP_DIR="$(pwd)/${TEMP_DIR#./}"
        export TEMP_DIR
    fi
    if [[ "${SING_BOX_CONFIG_DIR:-}" =~ ^\. ]]; then
        SING_BOX_CONFIG_DIR="$(pwd)/${SING_BOX_CONFIG_DIR#./}"
        export SING_BOX_CONFIG_DIR
    fi
    if [[ "${SING_BOX_CONFIG_FILE:-}" =~ ^\. ]]; then
        SING_BOX_CONFIG_FILE="$(pwd)/${SING_BOX_CONFIG_FILE#./}"
        export SING_BOX_CONFIG_FILE
    fi
    if [[ "${SUBSCRIPTION_DIR:-}" =~ ^\. ]]; then
        SUBSCRIPTION_DIR="$(pwd)/${SUBSCRIPTION_DIR#./}"
        export SUBSCRIPTION_DIR
    fi
    
    # 创建必要目录
    mkdir -p "${LOG_DIR:-/tmp}" "${BACKUP_DIR:-/tmp/backup}" "${TEMP_DIR:-/tmp/sing-box-install}"
    
    log_info "通用函数库初始化完成"
}

# 如果直接运行此脚本，则执行初始化
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    init_common
    log_info "通用函数库测试完成"
fi