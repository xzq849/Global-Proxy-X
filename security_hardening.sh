#!/bin/bash
set -euo pipefail

# 安全加固脚本
# 用于加强sing-box和系统安全性

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

# 安全配置文件
SECURITY_CONFIG="/etc/sing-box/security.conf"
FIREWALL_RULES="/etc/sing-box/firewall.rules"

# 创建安全配置
create_security_config() {
    log_info "创建安全配置文件..."
    
    mkdir -p "$(dirname "$SECURITY_CONFIG")"
    
    cat > "$SECURITY_CONFIG" << 'EOF'
# Sing-box 安全配置

# 允许的端口
ALLOWED_PORTS="22 80 443 9090"

# 允许的IP段（可选，留空表示允许所有）
ALLOWED_NETWORKS=""

# 日志记录
ENABLE_LOGGING="true"
LOG_LEVEL="info"

# 访问控制
ENABLE_ACCESS_CONTROL="true"
MAX_CONNECTIONS_PER_IP="100"

# 安全选项
DISABLE_IPV6="false"
ENABLE_FAIL2BAN="true"
ENABLE_RATE_LIMITING="true"
EOF

    log_success "安全配置文件已创建: $SECURITY_CONFIG"
}

# 配置防火墙
configure_firewall() {
    log_info "配置防火墙规则..."
    
    # 加载安全配置
    if [[ -f "$SECURITY_CONFIG" ]]; then
        source "$SECURITY_CONFIG"
    else
        create_security_config
        source "$SECURITY_CONFIG"
    fi
    
    # 检测防火墙类型
    if command -v ufw &>/dev/null; then
        configure_ufw
    elif command -v firewall-cmd &>/dev/null; then
        configure_firewalld
    elif command -v iptables &>/dev/null; then
        configure_iptables
    else
        log_warn "未找到支持的防火墙工具"
        return 1
    fi
}

# 配置UFW防火墙
configure_ufw() {
    log_info "配置UFW防火墙..."
    
    # 重置UFW规则
    ufw --force reset
    
    # 设置默认策略
    ufw default deny incoming
    ufw default allow outgoing
    
    # 允许指定端口
    for port in $ALLOWED_PORTS; do
        ufw allow "$port"
        log_info "已允许端口: $port"
    done
    
    # 限制SSH连接
    ufw limit ssh
    
    # 启用UFW
    ufw --force enable
    
    log_success "UFW防火墙配置完成"
}

# 配置firewalld
configure_firewalld() {
    log_info "配置firewalld防火墙..."
    
    # 启动firewalld
    systemctl enable firewalld
    systemctl start firewalld
    
    # 设置默认区域
    firewall-cmd --set-default-zone=public
    
    # 移除所有服务
    firewall-cmd --zone=public --remove-service=ssh --permanent 2>/dev/null || true
    firewall-cmd --zone=public --remove-service=dhcpv6-client --permanent 2>/dev/null || true
    
    # 添加允许的端口
    for port in $ALLOWED_PORTS; do
        firewall-cmd --zone=public --add-port="$port/tcp" --permanent
        log_info "已允许端口: $port"
    done
    
    # 重新加载规则
    firewall-cmd --reload
    
    log_success "firewalld防火墙配置完成"
}

# 配置iptables
configure_iptables() {
    log_info "配置iptables防火墙..."
    
    # 创建防火墙规则文件
    cat > "$FIREWALL_RULES" << EOF
#!/bin/bash
# iptables防火墙规则

# 清空现有规则
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X

# 设置默认策略
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# 允许本地回环
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# 允许已建立的连接
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# 允许指定端口
EOF

    for port in $ALLOWED_PORTS; do
        echo "iptables -A INPUT -p tcp --dport $port -j ACCEPT" >> "$FIREWALL_RULES"
    done
    
    cat >> "$FIREWALL_RULES" << 'EOF'

# 防止常见攻击
iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP
iptables -A INPUT -p tcp --tcp-flags ALL ALL -j DROP
iptables -A INPUT -p tcp --tcp-flags ALL FIN,URG,PSH -j DROP
iptables -A INPUT -p tcp --tcp-flags ALL SYN,RST,ACK,FIN,URG -j DROP

# 限制连接数
iptables -A INPUT -p tcp --dport 22 -m connlimit --connlimit-above 3 -j DROP
iptables -A INPUT -p tcp --dport 80 -m connlimit --connlimit-above 50 -j DROP
iptables -A INPUT -p tcp --dport 443 -m connlimit --connlimit-above 50 -j DROP

# 保存规则
iptables-save > /etc/iptables/rules.v4
EOF

    chmod +x "$FIREWALL_RULES"
    bash "$FIREWALL_RULES"
    
    # 创建systemd服务
    cat > /etc/systemd/system/iptables-restore.service << 'EOF'
[Unit]
Description=Restore iptables rules
After=network.target

[Service]
Type=oneshot
ExecStart=/sbin/iptables-restore /etc/iptables/rules.v4
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl enable iptables-restore
    
    log_success "iptables防火墙配置完成"
}

# 配置fail2ban
configure_fail2ban() {
    log_info "配置fail2ban..."
    
    # 安装fail2ban
    if ! command -v fail2ban-server &>/dev/null; then
        log_info "安装fail2ban..."
        if command -v apt-get &>/dev/null; then
            apt-get update
            apt-get install -y fail2ban
        elif command -v yum &>/dev/null; then
            yum install -y epel-release
            yum install -y fail2ban
        elif command -v dnf &>/dev/null; then
            dnf install -y fail2ban
        else
            log_error "无法安装fail2ban"
            return 1
        fi
    fi
    
    # 创建fail2ban配置
    cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3
backend = systemd

[sshd]
enabled = true
port = ssh
logpath = %(sshd_log)s
maxretry = 3

[nginx-http-auth]
enabled = true
port = http,https
logpath = /var/log/nginx/error.log

[nginx-limit-req]
enabled = true
port = http,https
logpath = /var/log/nginx/error.log
maxretry = 10

[sing-box]
enabled = true
port = 9090
logpath = /var/log/sing-box/sing-box.log
maxretry = 5
findtime = 300
bantime = 1800
filter = sing-box

[recidive]
enabled = true
logpath = /var/log/fail2ban.log
action = %(action_mwl)s
bantime = 86400
findtime = 86400
maxretry = 3
EOF

    # 创建sing-box过滤器
    cat > /etc/fail2ban/filter.d/sing-box.conf << 'EOF'
[Definition]
failregex = ^.*\[ERROR\].*<HOST>.*connection.*failed.*$
            ^.*\[WARN\].*<HOST>.*too many.*$
            ^.*\[ERROR\].*<HOST>.*authentication.*failed.*$

ignoreregex =
EOF

    # 启动fail2ban
    systemctl enable fail2ban
    systemctl restart fail2ban
    
    log_success "fail2ban配置完成"
}

# 加固SSH配置
harden_ssh() {
    log_info "加固SSH配置..."
    
    local ssh_config="/etc/ssh/sshd_config"
    
    # 备份原始配置
    safe_backup "$ssh_config"
    
    # 创建安全的SSH配置
    cat > "$ssh_config" << 'EOF'
# SSH安全配置

# 基本设置
Port 22
Protocol 2
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key

# 安全设置
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes

# 连接设置
MaxAuthTries 3
MaxSessions 2
ClientAliveInterval 300
ClientAliveCountMax 2
LoginGraceTime 60

# 协议设置
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
PermitTunnel no

# 日志设置
SyslogFacility AUTH
LogLevel INFO

# 其他安全设置
StrictModes yes
IgnoreRhosts yes
HostbasedAuthentication no
PermitUserEnvironment no
Compression delayed
TCPKeepAlive yes
UsePrivilegeSeparation sandbox

# 允许的用户和组
AllowUsers sing-box
DenyUsers root
EOF

    # 重启SSH服务
    systemctl restart sshd
    
    log_success "SSH配置加固完成"
}

# 设置文件权限
set_file_permissions() {
    log_info "设置文件权限..."
    
    # sing-box配置文件权限
    local config_dir="${SING_BOX_CONFIG_DIR:-/etc/sing-box}"
    if [[ -d "$config_dir" ]]; then
        chown -R sing-box:sing-box "$config_dir"
        chmod 750 "$config_dir"
        find "$config_dir" -type f -exec chmod 640 {} \;
        log_info "已设置sing-box配置目录权限"
    fi
    
    # 日志文件权限
    local log_dir="${LOG_DIR:-/var/log/sing-box}"
    if [[ -d "$log_dir" ]]; then
        chown -R sing-box:sing-box "$log_dir"
        chmod 750 "$log_dir"
        find "$log_dir" -type f -exec chmod 640 {} \;
        log_info "已设置日志目录权限"
    fi
    
    # 脚本文件权限
    find "$SCRIPT_DIR" -name "*.sh" -exec chmod 750 {} \;
    log_info "已设置脚本文件权限"
    
    # 敏感文件权限
    if [[ -f "$SECURITY_CONFIG" ]]; then
        chmod 600 "$SECURITY_CONFIG"
        chown root:root "$SECURITY_CONFIG"
    fi
    
    log_success "文件权限设置完成"
}

# 配置系统审计
configure_audit() {
    log_info "配置系统审计..."
    
    # 安装auditd
    if ! command -v auditctl &>/dev/null; then
        if command -v apt-get &>/dev/null; then
            apt-get install -y auditd
        elif command -v yum &>/dev/null; then
            yum install -y audit
        elif command -v dnf &>/dev/null; then
            dnf install -y audit
        fi
    fi
    
    # 配置审计规则
    cat > /etc/audit/rules.d/sing-box.rules << 'EOF'
# Sing-box审计规则

# 监控配置文件变更
-w /etc/sing-box/ -p wa -k sing-box-config

# 监控日志文件
-w /var/log/sing-box/ -p wa -k sing-box-logs

# 监控服务文件
-w /etc/systemd/system/sing-box.service -p wa -k sing-box-service

# 监控可执行文件
-w /usr/local/bin/sing-box -p x -k sing-box-exec

# 监控网络配置
-w /etc/hosts -p wa -k network-config
-w /etc/resolv.conf -p wa -k network-config

# 监控用户管理
-w /etc/passwd -p wa -k user-management
-w /etc/group -p wa -k user-management
-w /etc/shadow -p wa -k user-management

# 监控权限变更
-a always,exit -F arch=b64 -S chmod -S fchmod -S fchmodat -k perm-mod
-a always,exit -F arch=b64 -S chown -S fchown -S fchownat -S lchown -k perm-mod
EOF

    # 重启auditd
    systemctl enable auditd
    systemctl restart auditd
    
    log_success "系统审计配置完成"
}

# 安全扫描
security_scan() {
    log_info "执行安全扫描..."
    
    # 检查开放端口
    log_info "检查开放端口..."
    ss -tuln | grep LISTEN | while read line; do
        local port=$(echo "$line" | awk '{print $5}' | cut -d':' -f2)
        log_info "开放端口: $port"
    done
    
    # 检查运行进程
    log_info "检查可疑进程..."
    ps aux | grep -E "(nc|netcat|ncat)" | grep -v grep && log_warn "发现可疑网络工具进程"
    
    # 检查文件权限
    log_info "检查关键文件权限..."
    local critical_files=("/etc/passwd" "/etc/shadow" "/etc/ssh/sshd_config")
    for file in "${critical_files[@]}"; do
        if [[ -f "$file" ]]; then
            local perms=$(stat -c "%a" "$file")
            log_info "$file 权限: $perms"
        fi
    done
    
    # 检查登录失败
    log_info "检查登录失败记录..."
    if [[ -f /var/log/auth.log ]]; then
        local failed_logins=$(grep "Failed password" /var/log/auth.log | wc -l)
        log_info "登录失败次数: $failed_logins"
    fi
    
    # 检查系统更新
    log_info "检查系统更新..."
    if command -v apt &>/dev/null; then
        local updates=$(apt list --upgradable 2>/dev/null | wc -l)
        log_info "可用更新: $updates"
    fi
    
    log_success "安全扫描完成"
}

# 显示帮助信息
show_help() {
    cat << 'EOF'
安全加固脚本使用说明
====================

用法: ./security_hardening.sh [选项]

主要功能:
  harden       执行完整安全加固（推荐）
  scan         执行安全扫描和检查
  verify       验证当前安全配置状态

单项配置:
  firewall     配置防火墙规则（UFW/firewalld/iptables）
  fail2ban     配置入侵防护系统
  ssh          加固SSH服务配置
  permissions  设置文件和目录权限
  audit        配置系统审计日志
  kernel       配置内核安全参数
  limits       配置用户资源限制
  monitor      配置日志监控和告警

工具功能:
  backup       创建安全配置备份
  help         显示此帮助信息

使用示例:
  ./security_hardening.sh harden      # 执行完整安全加固
  ./security_hardening.sh scan        # 安全扫描
  ./security_hardening.sh verify      # 验证安全配置
  ./security_hardening.sh firewall    # 仅配置防火墙
  ./security_hardening.sh backup      # 备份安全配置

安全加固包含:
  ✓ 防火墙配置和规则优化
  ✓ SSH服务安全加固
  ✓ 入侵检测和防护（fail2ban）
  ✓ 系统审计日志配置
  ✓ 内核安全参数调优
  ✓ 用户权限和资源限制
  ✓ 文件权限安全设置
  ✓ 日志监控和告警系统
  ✓ 安全配置验证

注意事项:
  • 需要root权限执行
  • 建议在测试环境先验证
  • 会自动备份原始配置
  • 某些配置可能需要重启服务

EOF
}

# 配置内核安全参数
configure_kernel_security() {
    log_info "配置内核安全参数..."
    
    # 创建内核安全配置
    cat > /etc/sysctl.d/99-sing-box-security.conf << 'EOF'
# 网络安全参数
net.ipv4.ip_forward = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 5

# IPv6安全参数
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# 内存保护
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.yama.ptrace_scope = 1

# 文件系统安全
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
fs.suid_dumpable = 0
EOF

    # 应用配置
    sysctl -p /etc/sysctl.d/99-sing-box-security.conf
    
    log_success "内核安全参数配置完成"
}

# 配置用户安全限制
configure_user_limits() {
    log_info "配置用户安全限制..."
    
    # 创建安全限制配置
    cat > /etc/security/limits.d/99-sing-box.conf << 'EOF'
# Sing-box用户限制
sing-box soft nofile 65536
sing-box hard nofile 65536
sing-box soft nproc 4096
sing-box hard nproc 4096

# 防止fork炸弹
* hard nproc 4096
root hard nproc unlimited
EOF

    log_success "用户安全限制配置完成"
}

# 配置日志监控
configure_log_monitoring() {
    log_info "配置日志监控..."
    
    # 创建日志监控脚本
    cat > /usr/local/bin/sing-box-log-monitor.sh << 'EOF'
#!/bin/bash
# Sing-box日志监控脚本

LOG_FILE="/var/log/sing-box/sing-box.log"
ALERT_EMAIL="admin@example.com"
ALERT_THRESHOLD=10

# 检查错误日志
check_errors() {
    local error_count=$(grep -c "ERROR" "$LOG_FILE" 2>/dev/null || echo 0)
    if [[ $error_count -gt $ALERT_THRESHOLD ]]; then
        echo "警告: 检测到 $error_count 个错误日志" | mail -s "Sing-box错误告警" "$ALERT_EMAIL"
    fi
}

# 检查连接异常
check_connections() {
    local failed_connections=$(grep -c "connection.*failed" "$LOG_FILE" 2>/dev/null || echo 0)
    if [[ $failed_connections -gt $ALERT_THRESHOLD ]]; then
        echo "警告: 检测到 $failed_connections 个连接失败" | mail -s "Sing-box连接告警" "$ALERT_EMAIL"
    fi
}

# 执行检查
check_errors
check_connections
EOF

    chmod +x /usr/local/bin/sing-box-log-monitor.sh
    
    # 创建定时任务
    cat > /etc/cron.d/sing-box-monitor << 'EOF'
# Sing-box监控定时任务
*/5 * * * * root /usr/local/bin/sing-box-log-monitor.sh
EOF

    log_success "日志监控配置完成"
}

# 创建安全备份
create_security_backup() {
    log_info "创建安全配置备份..."
    
    local backup_dir="/etc/sing-box/security-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"
    
    # 备份关键配置文件
    local files_to_backup=(
        "/etc/ssh/sshd_config"
        "/etc/fail2ban/jail.local"
        "/etc/sysctl.d/99-sing-box-security.conf"
        "/etc/security/limits.d/99-sing-box.conf"
        "$SECURITY_CONFIG"
    )
    
    for file in "${files_to_backup[@]}"; do
        if [[ -f "$file" ]]; then
            cp "$file" "$backup_dir/"
            log_info "已备份: $file"
        fi
    done
    
    log_success "安全配置备份完成: $backup_dir"
}

# 验证安全配置
verify_security_config() {
    log_info "验证安全配置..."
    
    local issues=0
    
    # 检查防火墙状态
    if command -v ufw &>/dev/null; then
        if ! ufw status | grep -q "Status: active"; then
            log_warn "UFW防火墙未启用"
            ((issues++))
        fi
    elif command -v firewall-cmd &>/dev/null; then
        if ! systemctl is-active firewalld &>/dev/null; then
            log_warn "firewalld未运行"
            ((issues++))
        fi
    fi
    
    # 检查fail2ban状态
    if command -v fail2ban-server &>/dev/null; then
        if ! systemctl is-active fail2ban &>/dev/null; then
            log_warn "fail2ban未运行"
            ((issues++))
        fi
    fi
    
    # 检查SSH配置
    if [[ -f /etc/ssh/sshd_config ]]; then
        if grep -q "PermitRootLogin yes" /etc/ssh/sshd_config; then
            log_warn "SSH允许root登录，存在安全风险"
            ((issues++))
        fi
        if grep -q "PasswordAuthentication yes" /etc/ssh/sshd_config; then
            log_warn "SSH允许密码认证，建议使用密钥认证"
            ((issues++))
        fi
    fi
    
    # 检查文件权限
    local config_dir="${SING_BOX_CONFIG_DIR:-/etc/sing-box}"
    if [[ -d "$config_dir" ]]; then
        local perms=$(stat -c "%a" "$config_dir" 2>/dev/null || echo "000")
        if [[ "$perms" != "750" ]]; then
            log_warn "配置目录权限不安全: $perms"
            ((issues++))
        fi
    fi
    
    if [[ $issues -eq 0 ]]; then
        log_success "安全配置验证通过"
    else
        log_warn "发现 $issues 个安全问题，请检查"
    fi
    
    return $issues
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
        "harden")
            log_info "开始完整安全加固..."
            create_security_backup
            create_security_config
            configure_kernel_security
            configure_user_limits
            configure_firewall
            configure_fail2ban
            harden_ssh
            set_file_permissions
            configure_audit
            configure_log_monitoring
            verify_security_config
            log_success "安全加固完成"
            ;;
        "firewall")
            create_security_config
            configure_firewall
            ;;
        "fail2ban")
            configure_fail2ban
            ;;
        "ssh")
            create_security_backup
            harden_ssh
            ;;
        "permissions")
            set_file_permissions
            ;;
        "audit")
            configure_audit
            ;;
        "kernel")
            configure_kernel_security
            ;;
        "limits")
            configure_user_limits
            ;;
        "monitor")
            configure_log_monitoring
            ;;
        "scan")
            security_scan
            ;;
        "verify")
            verify_security_config
            ;;
        "backup")
            create_security_backup
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