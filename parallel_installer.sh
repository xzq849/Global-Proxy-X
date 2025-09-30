#!/bin/bash

# 并行安装脚本
# 提供并行下载和安装功能，提升安装效率

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

# 并行配置
MAX_PARALLEL_JOBS="${MAX_PARALLEL_JOBS:-4}"
DOWNLOAD_CACHE_DIR="${TEMP_DIR:-/tmp}/sing-box-cache"
PROGRESS_FILE="$DOWNLOAD_CACHE_DIR/progress"

# 创建缓存目录
mkdir -p "$DOWNLOAD_CACHE_DIR"

# 任务队列
declare -a DOWNLOAD_QUEUE=()
declare -a INSTALL_QUEUE=()

# 进度跟踪
declare -A TASK_STATUS=()
declare -A TASK_PROGRESS=()

# 添加下载任务
add_download_task() {
    local name="$1"
    local url="$2"
    local output="$3"
    local size="${4:-0}"
    
    DOWNLOAD_QUEUE+=("$name|$url|$output|$size")
    TASK_STATUS["$name"]="pending"
    TASK_PROGRESS["$name"]=0
    
    log_debug "添加下载任务: $name"
}

# 添加安装任务
add_install_task() {
    local name="$1"
    local command="$2"
    local depends="${3:-}"
    
    INSTALL_QUEUE+=("$name|$command|$depends")
    TASK_STATUS["$name"]="pending"
    TASK_PROGRESS["$name"]=0
    
    log_debug "添加安装任务: $name"
}

# 并行下载函数
parallel_download() {
    local task="$1"
    local name=$(echo "$task" | cut -d'|' -f1)
    local url=$(echo "$task" | cut -d'|' -f2)
    local output=$(echo "$task" | cut -d'|' -f3)
    local expected_size=$(echo "$task" | cut -d'|' -f4)
    
    log_info "开始下载: $name"
    TASK_STATUS["$name"]="downloading"
    
    # 创建输出目录
    mkdir -p "$(dirname "$output")"
    
    # 下载文件
    if safe_download "$url" "$output" "$expected_size"; then
        TASK_STATUS["$name"]="completed"
        TASK_PROGRESS["$name"]=100
        log_success "下载完成: $name"
        echo "download:$name:completed" >> "$PROGRESS_FILE"
    else
        TASK_STATUS["$name"]="failed"
        log_error "下载失败: $name"
        echo "download:$name:failed" >> "$PROGRESS_FILE"
        return 1
    fi
}

# 并行安装函数
parallel_install() {
    local task="$1"
    local name=$(echo "$task" | cut -d'|' -f1)
    local command=$(echo "$task" | cut -d'|' -f2)
    local depends=$(echo "$task" | cut -d'|' -f3)
    
    # 检查依赖
    if [[ -n "$depends" ]]; then
        log_debug "检查依赖: $depends"
        IFS=',' read -ra DEPS <<< "$depends"
        for dep in "${DEPS[@]}"; do
            while [[ "${TASK_STATUS[$dep]}" != "completed" ]]; do
                if [[ "${TASK_STATUS[$dep]}" == "failed" ]]; then
                    log_error "依赖任务失败: $dep"
                    TASK_STATUS["$name"]="failed"
                    return 1
                fi
                sleep 1
            done
        done
    fi
    
    log_info "开始安装: $name"
    TASK_STATUS["$name"]="installing"
    
    # 执行安装命令
    if eval "$command"; then
        TASK_STATUS["$name"]="completed"
        TASK_PROGRESS["$name"]=100
        log_success "安装完成: $name"
        echo "install:$name:completed" >> "$PROGRESS_FILE"
    else
        TASK_STATUS["$name"]="failed"
        log_error "安装失败: $name"
        echo "install:$name:failed" >> "$PROGRESS_FILE"
        return 1
    fi
}

# 执行并行下载
execute_parallel_downloads() {
    log_info "开始并行下载 (最大并发: $MAX_PARALLEL_JOBS)"
    
    local pids=()
    local active_jobs=0
    local queue_index=0
    
    while [[ $queue_index -lt ${#DOWNLOAD_QUEUE[@]} ]] || [[ $active_jobs -gt 0 ]]; do
        # 启动新任务
        while [[ $active_jobs -lt $MAX_PARALLEL_JOBS ]] && [[ $queue_index -lt ${#DOWNLOAD_QUEUE[@]} ]]; do
            local task="${DOWNLOAD_QUEUE[$queue_index]}"
            parallel_download "$task" &
            local pid=$!
            pids+=($pid)
            ((active_jobs++))
            ((queue_index++))
            
            log_debug "启动下载进程: PID $pid"
        done
        
        # 检查完成的任务
        local new_pids=()
        for pid in "${pids[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                new_pids+=($pid)
            else
                wait "$pid"
                ((active_jobs--))
                log_debug "下载进程完成: PID $pid"
            fi
        done
        pids=("${new_pids[@]}")
        
        # 显示进度
        show_download_progress
        
        sleep 1
    done
    
    log_success "所有下载任务完成"
}

# 执行并行安装
execute_parallel_installs() {
    log_info "开始并行安装"
    
    local pids=()
    local active_jobs=0
    local completed_tasks=()
    
    while [[ ${#completed_tasks[@]} -lt ${#INSTALL_QUEUE[@]} ]]; do
        # 查找可以执行的任务
        for task in "${INSTALL_QUEUE[@]}"; do
            local name=$(echo "$task" | cut -d'|' -f1)
            
            # 跳过已完成或正在执行的任务
            if [[ " ${completed_tasks[*]} " =~ " $name " ]] || [[ "${TASK_STATUS[$name]}" == "installing" ]]; then
                continue
            fi
            
            # 检查是否可以启动新任务
            if [[ $active_jobs -lt $MAX_PARALLEL_JOBS ]] && [[ "${TASK_STATUS[$name]}" == "pending" ]]; then
                parallel_install "$task" &
                local pid=$!
                pids+=($pid)
                ((active_jobs++))
                
                log_debug "启动安装进程: PID $pid ($name)"
            fi
        done
        
        # 检查完成的任务
        local new_pids=()
        for pid in "${pids[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                new_pids+=($pid)
            else
                wait "$pid"
                ((active_jobs--))
                log_debug "安装进程完成: PID $pid"
            fi
        done
        pids=("${new_pids[@]}")
        
        # 更新完成任务列表
        for task in "${INSTALL_QUEUE[@]}"; do
            local name=$(echo "$task" | cut -d'|' -f1)
            if [[ "${TASK_STATUS[$name]}" == "completed" ]] && [[ ! " ${completed_tasks[*]} " =~ " $name " ]]; then
                completed_tasks+=("$name")
            fi
        done
        
        # 显示进度
        show_install_progress
        
        sleep 1
    done
    
    log_success "所有安装任务完成"
}

# 显示下载进度
show_download_progress() {
    if [[ "${SHOW_PROGRESS:-true}" != "true" ]]; then
        return
    fi
    
    local total=${#DOWNLOAD_QUEUE[@]}
    local completed=0
    local failed=0
    
    for task in "${DOWNLOAD_QUEUE[@]}"; do
        local name=$(echo "$task" | cut -d'|' -f1)
        case "${TASK_STATUS[$name]}" in
            "completed") ((completed++)) ;;
            "failed") ((failed++)) ;;
        esac
    done
    
    local percent=$((completed * 100 / total))
    printf "\r${BLUE}下载进度${NC} [%d/%d] %d%% (失败: %d)" $completed $total $percent $failed
    
    if [[ $completed -eq $total ]]; then
        echo ""
    fi
}

# 显示安装进度
show_install_progress() {
    if [[ "${SHOW_PROGRESS:-true}" != "true" ]]; then
        return
    fi
    
    local total=${#INSTALL_QUEUE[@]}
    local completed=0
    local failed=0
    
    for task in "${INSTALL_QUEUE[@]}"; do
        local name=$(echo "$task" | cut -d'|' -f1)
        case "${TASK_STATUS[$name]}" in
            "completed") ((completed++)) ;;
            "failed") ((failed++)) ;;
        esac
    done
    
    local percent=$((completed * 100 / total))
    printf "\r${BLUE}安装进度${NC} [%d/%d] %d%% (失败: %d)" $completed $total $percent $failed
    
    if [[ $completed -eq $total ]]; then
        echo ""
    fi
}

# 检查任务状态
check_task_status() {
    local task_name="$1"
    echo "${TASK_STATUS[$task_name]:-unknown}"
}

# 等待任务完成
wait_for_task() {
    local task_name="$1"
    local timeout="${2:-300}"
    local elapsed=0
    
    while [[ $elapsed -lt $timeout ]]; do
        local status="${TASK_STATUS[$task_name]}"
        case "$status" in
            "completed")
                return 0
                ;;
            "failed")
                return 1
                ;;
            *)
                sleep 1
                ((elapsed++))
                ;;
        esac
    done
    
    log_error "任务超时: $task_name"
    return 1
}

# 清理缓存
cleanup_cache() {
    log_info "清理下载缓存..."
    
    if [[ -d "$DOWNLOAD_CACHE_DIR" ]]; then
        # 保留最近的文件
        find "$DOWNLOAD_CACHE_DIR" -type f -mtime +1 -delete 2>/dev/null || true
        log_success "缓存清理完成"
    fi
}

# 预定义安装任务
setup_singbox_tasks() {
    log_info "设置sing-box安装任务..."
    
    # 获取系统信息
    local arch=$(uname -m)
    case $arch in
        x86_64) arch="amd64" ;;
        aarch64) arch="arm64" ;;
        armv7l) arch="armv7" ;;
    esac
    
    # 获取最新版本
    local version_url="https://api.github.com/repos/SagerNet/sing-box/releases/latest"
    local latest_version=$(safe_curl "$version_url" | jq -r '.tag_name')
    
    if [[ -z "$latest_version" || "$latest_version" == "null" ]]; then
        log_error "无法获取最新版本"
        return 1
    fi
    
    # 构建下载URL
    local download_url="https://github.com/SagerNet/sing-box/releases/download/${latest_version}/sing-box-${latest_version#v}-linux-${arch}.tar.gz"
    local output_file="$DOWNLOAD_CACHE_DIR/sing-box-${latest_version#v}-linux-${arch}.tar.gz"
    
    # 添加下载任务
    add_download_task "sing-box" "$download_url" "$output_file"
    
    # 添加安装任务
    add_install_task "extract-singbox" "tar -xzf '$output_file' -C '$DOWNLOAD_CACHE_DIR'" "sing-box"
    add_install_task "install-singbox" "install_singbox_binary '$DOWNLOAD_CACHE_DIR'" "extract-singbox"
    add_install_task "create-user" "create_singbox_user" ""
    add_install_task "setup-service" "setup_singbox_service" "install-singbox,create-user"
}

# 安装sing-box二进制文件
install_singbox_binary() {
    local extract_dir="$1"
    local binary_path=$(find "$extract_dir" -name "sing-box" -type f | head -1)
    
    if [[ -z "$binary_path" ]]; then
        log_error "找不到sing-box二进制文件"
        return 1
    fi
    
    cp "$binary_path" /usr/local/bin/sing-box
    chmod +x /usr/local/bin/sing-box
    
    log_success "sing-box二进制文件安装完成"
}

# 创建sing-box用户
create_singbox_user() {
    if ! id -u sing-box &>/dev/null; then
        useradd -r -s /bin/false sing-box
        log_success "sing-box用户创建完成"
    else
        log_info "sing-box用户已存在"
    fi
}

# 设置sing-box服务
setup_singbox_service() {
    local service_file="/etc/systemd/system/sing-box.service"
    
    cat > "$service_file" << 'EOF'
[Unit]
Description=sing-box service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target
Wants=network.target

[Service]
Type=simple
User=sing-box
Group=sing-box
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=10s
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable sing-box
    
    log_success "sing-box服务设置完成"
}

# 显示帮助信息
show_help() {
    echo "并行安装脚本使用说明:"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  install      执行完整并行安装"
    echo "  download     仅执行并行下载"
    echo "  setup        设置安装任务"
    echo "  status       显示任务状态"
    echo "  clean        清理缓存"
    echo "  help         显示此帮助信息"
    echo ""
    echo "环境变量:"
    echo "  MAX_PARALLEL_JOBS    最大并行任务数 (默认: 4)"
    echo "  SHOW_PROGRESS        显示进度条 (默认: true)"
    echo ""
    echo "示例:"
    echo "  $0 install           # 执行完整安装"
    echo "  MAX_PARALLEL_JOBS=8 $0 install  # 使用8个并行任务"
}

# 显示任务状态
show_status() {
    echo "任务状态报告:"
    echo "=============="
    
    echo ""
    echo "下载任务:"
    for task in "${DOWNLOAD_QUEUE[@]}"; do
        local name=$(echo "$task" | cut -d'|' -f1)
        local status="${TASK_STATUS[$name]}"
        local progress="${TASK_PROGRESS[$name]}"
        printf "  %-20s %s (%d%%)\n" "$name" "$status" "$progress"
    done
    
    echo ""
    echo "安装任务:"
    for task in "${INSTALL_QUEUE[@]}"; do
        local name=$(echo "$task" | cut -d'|' -f1)
        local status="${TASK_STATUS[$name]}"
        local progress="${TASK_PROGRESS[$name]}"
        printf "  %-20s %s (%d%%)\n" "$name" "$status" "$progress"
    done
}

# 主函数
main() {
    case "${1:-install}" in
        "install")
            log_info "开始并行安装..."
            setup_singbox_tasks
            execute_parallel_downloads
            execute_parallel_installs
            cleanup_cache
            log_success "并行安装完成"
            ;;
        "download")
            setup_singbox_tasks
            execute_parallel_downloads
            ;;
        "setup")
            setup_singbox_tasks
            log_success "安装任务设置完成"
            ;;
        "status")
            show_status
            ;;
        "clean")
            cleanup_cache
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

# 检查root权限
check_root

# 执行主函数
main "$@"