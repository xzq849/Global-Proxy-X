#!/bin/bash
set -euo pipefail

# 增强性能优化脚本
# 用于优化sing-box和系统性能

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

# 性能配置文件
PERFORMANCE_CONFIG="/etc/sing-box/performance.conf"

# 创建性能配置
create_performance_config() {
    log_info "创建性能配置文件..."
    
    mkdir -p "$(dirname "$PERFORMANCE_CONFIG")"
    
    cat > "$PERFORMANCE_CONFIG" << 'EOF'
# Sing-box 性能配置

# 网络优化
ENABLE_TCP_BBR="true"
ENABLE_TCP_FASTOPEN="true"
TCP_CONGESTION_CONTROL="bbr"

# 内存优化
ENABLE_MEMORY_OPTIMIZATION="true"
SWAP_OPTIMIZATION="true"

# CPU优化
ENABLE_CPU_OPTIMIZATION="true"
CPU_GOVERNOR="performance"

# I/O优化
ENABLE_IO_OPTIMIZATION="true"
IO_SCHEDULER="mq-deadline"

# 并发优化
MAX_CONNECTIONS="65536"
MAX_OPEN_FILES="1048576"

# 缓存优化
ENABLE_CACHE_OPTIMIZATION="true"
CACHE_SIZE="256M"
EOF

    log_success "性能配置文件已创建: $PERFORMANCE_CONFIG"
}

# 优化网络参数
optimize_network() {
    log_info "优化网络参数..."
    
    # 加载性能配置
    if [[ -f "$PERFORMANCE_CONFIG" ]]; then
        source "$PERFORMANCE_CONFIG"
    else
        create_performance_config
        source "$PERFORMANCE_CONFIG"
    fi
    
    # 创建网络优化配置
    cat > /etc/sysctl.d/99-sing-box-performance.conf << 'EOF'
# 网络性能优化参数

# TCP优化
net.core.rmem_default = 262144
net.core.rmem_max = 16777216
net.core.wmem_default = 262144
net.core.wmem_max = 16777216
net.core.netdev_max_backlog = 5000
net.core.netdev_budget = 600

# TCP缓冲区
net.ipv4.tcp_rmem = 4096 65536 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_mem = 786432 1048576 26777216

# TCP连接优化
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 60
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_max_tw_buckets = 6000
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_fack = 1
net.ipv4.tcp_dsack = 1

# TCP拥塞控制
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq

# TCP Fast Open
net.ipv4.tcp_fastopen = 3

# 连接跟踪优化
net.netfilter.nf_conntrack_max = 1048576
net.netfilter.nf_conntrack_tcp_timeout_established = 7200
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 120
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 60
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 120

# UDP优化
net.core.rmem_default = 262144
net.core.rmem_max = 16777216
net.core.wmem_default = 262144
net.core.wmem_max = 16777216

# 其他网络优化
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_max_orphans = 65536
net.ipv4.tcp_orphan_retries = 3
net.ipv4.tcp_syn_retries = 6
net.ipv4.tcp_synack_retries = 5
EOF

    # 应用网络优化
    sysctl -p /etc/sysctl.d/99-sing-box-performance.conf
    
    # 启用BBR拥塞控制
    if [[ "$ENABLE_TCP_BBR" == "true" ]]; then
        modprobe tcp_bbr
        echo 'tcp_bbr' >> /etc/modules-load.d/modules.conf
        log_info "已启用TCP BBR拥塞控制"
    fi
    
    log_success "网络参数优化完成"
}

# 优化内存管理
optimize_memory() {
    log_info "优化内存管理..."
    
    # 创建内存优化配置
    cat >> /etc/sysctl.d/99-sing-box-performance.conf << 'EOF'

# 内存管理优化
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
vm.dirty_expire_centisecs = 3000
vm.dirty_writeback_centisecs = 500
vm.vfs_cache_pressure = 50
vm.min_free_kbytes = 65536
vm.zone_reclaim_mode = 0
vm.page_cluster = 3
vm.overcommit_memory = 1
vm.overcommit_ratio = 50
EOF

    # 应用内存优化
    sysctl -p /etc/sysctl.d/99-sing-box-performance.conf
    
    # 配置透明大页
    echo 'madvise' > /sys/kernel/mm/transparent_hugepage/enabled
    echo 'madvise' > /sys/kernel/mm/transparent_hugepage/defrag
    
    # 创建内存优化服务
    cat > /etc/systemd/system/memory-optimization.service << 'EOF'
[Unit]
Description=Memory Optimization for Sing-box
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'echo madvise > /sys/kernel/mm/transparent_hugepage/enabled'
ExecStart=/bin/bash -c 'echo madvise > /sys/kernel/mm/transparent_hugepage/defrag'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl enable memory-optimization.service
    
    log_success "内存管理优化完成"
}

# 优化CPU性能
optimize_cpu() {
    log_info "优化CPU性能..."
    
    # 设置CPU调度器
    if [[ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]]; then
        for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
            echo 'performance' > "$cpu" 2>/dev/null || true
        done
        log_info "已设置CPU调度器为performance模式"
    fi
    
    # 禁用CPU节能功能
    if command -v cpupower &>/dev/null; then
        cpupower frequency-set -g performance 2>/dev/null || true
        cpupower idle-set -D 0 2>/dev/null || true
    fi
    
    # 设置CPU亲和性
    if [[ -f /proc/irq/default_smp_affinity ]]; then
        echo 'ff' > /proc/irq/default_smp_affinity 2>/dev/null || true
    fi
    
    # 创建CPU优化服务
    cat > /etc/systemd/system/cpu-optimization.service << 'EOF'
[Unit]
Description=CPU Optimization for Sing-box
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo performance > "$cpu" 2>/dev/null || true; done'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl enable cpu-optimization.service
    
    log_success "CPU性能优化完成"
}

# 优化I/O性能
optimize_io() {
    log_info "优化I/O性能..."
    
    # 设置I/O调度器
    for disk in /sys/block/*/queue/scheduler; do
        if [[ -f "$disk" ]]; then
            echo 'mq-deadline' > "$disk" 2>/dev/null || echo 'deadline' > "$disk" 2>/dev/null || true
        fi
    done
    
    # 优化I/O参数
    for disk in /sys/block/*/queue; do
        if [[ -d "$disk" ]]; then
            echo '2' > "$disk/rq_affinity" 2>/dev/null || true
            echo '256' > "$disk/nr_requests" 2>/dev/null || true
            echo '1024' > "$disk/read_ahead_kb" 2>/dev/null || true
        fi
    done
    
    # 创建I/O优化服务
    cat > /etc/systemd/system/io-optimization.service << 'EOF'
[Unit]
Description=I/O Optimization for Sing-box
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'for disk in /sys/block/*/queue/scheduler; do echo mq-deadline > "$disk" 2>/dev/null || echo deadline > "$disk" 2>/dev/null || true; done'
ExecStart=/bin/bash -c 'for disk in /sys/block/*/queue; do echo 2 > "$disk/rq_affinity" 2>/dev/null || true; echo 256 > "$disk/nr_requests" 2>/dev/null || true; echo 1024 > "$disk/read_ahead_kb" 2>/dev/null || true; done'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl enable io-optimization.service
    
    log_success "I/O性能优化完成"
}

# 优化文件描述符限制
optimize_file_limits() {
    log_info "优化文件描述符限制..."
    
    # 创建系统限制配置
    cat > /etc/security/limits.d/99-sing-box-performance.conf << 'EOF'
# Sing-box性能优化限制

# 文件描述符限制
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576

# 进程限制
* soft nproc 65536
* hard nproc 65536
root soft nproc unlimited
root hard nproc unlimited

# 内存锁定限制
* soft memlock unlimited
* hard memlock unlimited

# 核心转储限制
* soft core unlimited
* hard core unlimited
EOF

    # 更新systemd限制
    mkdir -p /etc/systemd/system.conf.d
    cat > /etc/systemd/system.conf.d/limits.conf << 'EOF'
[Manager]
DefaultLimitNOFILE=1048576
DefaultLimitNPROC=65536
DefaultLimitMEMLOCK=infinity
DefaultLimitCORE=infinity
EOF

    # 更新systemd用户限制
    mkdir -p /etc/systemd/user.conf.d
    cat > /etc/systemd/user.conf.d/limits.conf << 'EOF'
[Manager]
DefaultLimitNOFILE=1048576
DefaultLimitNPROC=65536
DefaultLimitMEMLOCK=infinity
DefaultLimitCORE=infinity
EOF

    log_success "文件描述符限制优化完成"
}

# 优化sing-box配置
optimize_singbox_config() {
    log_info "优化sing-box配置..."
    
    local config_file="${SING_BOX_CONFIG_FILE:-/etc/sing-box/config.json}"
    
    if [[ ! -f "$config_file" ]]; then
        log_warn "sing-box配置文件不存在，跳过配置优化"
        return 0
    fi
    
    # 备份原始配置
    safe_backup "$config_file"
    
    # 使用jq优化配置
    if command -v jq &>/dev/null; then
        # 优化实验性配置
        jq '.experimental.cache_file.enabled = true |
            .experimental.cache_file.path = "/var/cache/sing-box/cache.db" |
            .experimental.cache_file.cache_id = "main" |
            .experimental.cache_file.store_fakeip = true |
            .experimental.clash_api.external_controller = "0.0.0.0:9090" |
            .experimental.clash_api.external_ui = "/var/www/sing-box-ui" |
            .experimental.clash_api.secret = "" |
            .experimental.clash_api.default_mode = "rule"' \
            "$config_file" > "${config_file}.tmp" && mv "${config_file}.tmp" "$config_file"
        
        # 优化日志配置
        jq '.log.level = "info" |
            .log.output = "/var/log/sing-box/sing-box.log" |
            .log.timestamp = true' \
            "$config_file" > "${config_file}.tmp" && mv "${config_file}.tmp" "$config_file"
        
        log_info "已优化sing-box配置"
    else
        log_warn "未找到jq命令，跳过配置优化"
    fi
    
    # 创建缓存目录
    mkdir -p /var/cache/sing-box
    chown -R sing-box:sing-box /var/cache/sing-box 2>/dev/null || true
    
    log_success "sing-box配置优化完成"
}

# 创建性能监控脚本
create_performance_monitor() {
    log_info "创建性能监控脚本..."
    
    cat > /usr/local/bin/sing-box-performance-monitor.sh << 'EOF'
#!/bin/bash
# Sing-box性能监控脚本

LOG_FILE="/var/log/sing-box/performance.log"
ALERT_EMAIL="admin@example.com"

# 创建日志目录
mkdir -p "$(dirname "$LOG_FILE")"

# 记录性能数据
log_performance() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # CPU使用率
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    
    # 内存使用率
    local mem_usage=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}')
    
    # 网络连接数
    local connections=$(ss -tuln | wc -l)
    
    # sing-box进程状态
    local singbox_cpu=$(ps aux | grep sing-box | grep -v grep | awk '{print $3}' | head -1)
    local singbox_mem=$(ps aux | grep sing-box | grep -v grep | awk '{print $4}' | head -1)
    
    # 记录到日志
    echo "$timestamp,CPU:${cpu_usage:-0}%,MEM:${mem_usage}%,CONN:$connections,SINGBOX_CPU:${singbox_cpu:-0}%,SINGBOX_MEM:${singbox_mem:-0}%" >> "$LOG_FILE"
    
    # 检查性能告警
    if (( $(echo "$cpu_usage > 80" | bc -l 2>/dev/null || echo 0) )); then
        echo "警告: CPU使用率过高 ${cpu_usage}%" | mail -s "性能告警" "$ALERT_EMAIL" 2>/dev/null || true
    fi
    
    if (( $(echo "$mem_usage > 90" | bc -l 2>/dev/null || echo 0) )); then
        echo "警告: 内存使用率过高 ${mem_usage}%" | mail -s "性能告警" "$ALERT_EMAIL" 2>/dev/null || true
    fi
}

# 清理旧日志
cleanup_logs() {
    find "$(dirname "$LOG_FILE")" -name "performance.log*" -mtime +7 -delete 2>/dev/null || true
}

# 执行监控
log_performance
cleanup_logs
EOF

    chmod +x /usr/local/bin/sing-box-performance-monitor.sh
    
    # 创建定时任务
    cat > /etc/cron.d/sing-box-performance << 'EOF'
# Sing-box性能监控定时任务
*/1 * * * * root /usr/local/bin/sing-box-performance-monitor.sh
EOF

    log_success "性能监控脚本创建完成"
}

# 性能测试
performance_test() {
    log_info "执行性能测试..."
    
    # 网络性能测试
    log_info "测试网络性能..."
    if command -v iperf3 &>/dev/null; then
        log_info "iperf3可用，可进行网络性能测试"
    else
        log_info "建议安装iperf3进行网络性能测试: apt install iperf3"
    fi
    
    # 磁盘I/O测试
    log_info "测试磁盘I/O性能..."
    if command -v dd &>/dev/null; then
        local write_speed=$(dd if=/dev/zero of=/tmp/test_write bs=1M count=100 2>&1 | grep -o '[0-9.]* MB/s' | tail -1)
        local read_speed=$(dd if=/tmp/test_write of=/dev/null bs=1M 2>&1 | grep -o '[0-9.]* MB/s' | tail -1)
        rm -f /tmp/test_write
        log_info "磁盘写入速度: ${write_speed:-未知}"
        log_info "磁盘读取速度: ${read_speed:-未知}"
    fi
    
    # 内存性能测试
    log_info "检查内存状态..."
    free -h
    
    # CPU性能信息
    log_info "检查CPU信息..."
    if [[ -f /proc/cpuinfo ]]; then
        local cpu_cores=$(grep -c ^processor /proc/cpuinfo)
        local cpu_model=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
        log_info "CPU核心数: $cpu_cores"
        log_info "CPU型号: $cpu_model"
    fi
    
    # 网络连接状态
    log_info "检查网络连接状态..."
    local tcp_connections=$(ss -t | wc -l)
    local udp_connections=$(ss -u | wc -l)
    log_info "TCP连接数: $tcp_connections"
    log_info "UDP连接数: $udp_connections"
    
    log_success "性能测试完成"
}

# 显示帮助信息
show_help() {
    cat << 'EOF'
性能优化脚本使用说明
====================

用法: ./performance_optimizer_enhanced.sh [选项]

主要功能:
  optimize     执行完整性能优化（推荐）
  test         执行性能测试
  monitor      启动性能监控

单项优化:
  network      优化网络参数
  memory       优化内存管理
  cpu          优化CPU性能
  io           优化I/O性能
  limits       优化系统限制
  singbox      优化sing-box配置

工具功能:
  help         显示此帮助信息

使用示例:
  ./performance_optimizer_enhanced.sh optimize   # 执行完整优化
  ./performance_optimizer_enhanced.sh test       # 性能测试
  ./performance_optimizer_enhanced.sh network    # 仅优化网络
  ./performance_optimizer_enhanced.sh monitor    # 启动监控

性能优化包含:
  ✓ 网络参数调优（TCP BBR、缓冲区等）
  ✓ 内存管理优化（交换、缓存等）
  ✓ CPU性能调优（调度器、亲和性等）
  ✓ I/O性能优化（调度器、队列等）
  ✓ 系统限制优化（文件描述符等）
  ✓ Sing-box配置优化
  ✓ 性能监控和告警

注意事项:
  • 需要root权限执行
  • 某些优化需要重启生效
  • 建议在测试环境先验证
  • 会自动备份原始配置

EOF
}

# 主函数
main() {
    display_banner
    
    # 检查root权限
    check_root
    
    if [[ $# -eq 0 ]]; then
        show_help
        return 0
    fi
    
    case "${1}" in
        "optimize")
            log_info "开始完整性能优化..."
            create_performance_config
            optimize_network
            optimize_memory
            optimize_cpu
            optimize_io
            optimize_file_limits
            optimize_singbox_config
            create_performance_monitor
            log_success "性能优化完成，建议重启系统以使所有优化生效"
            ;;
        "network")
            create_performance_config
            optimize_network
            ;;
        "memory")
            optimize_memory
            ;;
        "cpu")
            optimize_cpu
            ;;
        "io")
            optimize_io
            ;;
        "limits")
            optimize_file_limits
            ;;
        "singbox")
            optimize_singbox_config
            ;;
        "monitor")
            create_performance_monitor
            ;;
        "test")
            performance_test
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