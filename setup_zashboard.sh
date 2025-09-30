#!/bin/bash
set -euo pipefail

# zashboard 面板部署脚本
# 用于自动部署和配置 zashboard 管理面板
# 版本: 2.0.0
# 更新时间: 2024-01-15

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

# 检查依赖
check_dependencies "curl" "jq" "unzip"

# 配置变量
ZASHBOARD_DIR="${ZASHBOARD_DIR:-/var/www/zashboard}"
NGINX_CONFIG_DIR="${NGINX_CONFIG_DIR:-/etc/nginx}"
TEMP_DOWNLOAD_DIR="${TEMP_DIR:-/tmp}/zashboard-install"
BACKUP_DIR="/var/backups/zashboard-$(date +%Y%m%d-%H%M%S)"

# 安装状态跟踪
INSTALL_STEPS=(
    "network_check"
    "dependency_check"
    "nginx_install"
    "zashboard_deploy"
    "nginx_config"
    "firewall_config"
    "management_script"
    "service_start"
)

COMPLETED_STEPS=()
FAILED_STEP=""

# 创建临时目录
mkdir -p "$TEMP_DOWNLOAD_DIR"

# 进度显示函数
show_progress() {
    local current_step="$1"
    local total_steps=${#INSTALL_STEPS[@]}
    local current_index=0
    
    # 找到当前步骤的索引
    for i in "${!INSTALL_STEPS[@]}"; do
        if [[ "${INSTALL_STEPS[$i]}" == "$current_step" ]]; then
            current_index=$((i + 1))
            break
        fi
    done
    
    local progress=$((current_index * 100 / total_steps))
    local bar_length=50
    local filled_length=$((progress * bar_length / 100))
    
    printf "\r["
    printf "%*s" $filled_length | tr ' ' '='
    printf "%*s" $((bar_length - filled_length)) | tr ' ' '-'
    printf "] %d%% (%d/%d) %s" $progress $current_index $total_steps "$current_step"
}

# 网络连接检测
check_network_connectivity() {
    log_info "检查网络连接..."
    show_progress "network_check"
    
    local test_urls=(
        "https://api.github.com"
        "https://raw.githubusercontent.com"
        "https://ifconfig.me"
    )
    
    local failed_urls=()
    
    for url in "${test_urls[@]}"; do
        if ! curl -s --connect-timeout 10 --max-time 30 "$url" > /dev/null; then
            failed_urls+=("$url")
        fi
    done
    
    if [[ ${#failed_urls[@]} -gt 0 ]]; then
        log_warn "以下URL无法访问:"
        for url in "${failed_urls[@]}"; do
            log_warn "  - $url"
        done
        
        if [[ ${#failed_urls[@]} -eq ${#test_urls[@]} ]]; then
            log_error "网络连接检查失败，请检查网络设置"
            return 1
        else
            log_warn "部分网络连接异常，但可以继续安装"
        fi
    fi
    
    COMPLETED_STEPS+=("network_check")
    log_success "网络连接检查完成"
    echo ""
}

# 增强的依赖检查
enhanced_dependency_check() {
    log_info "检查系统依赖..."
    show_progress "dependency_check"
    
    local required_deps=("curl" "jq" "unzip" "systemctl")
    local optional_deps=("git" "node" "npm")
    local missing_required=()
    local missing_optional=()
    
    # 检查必需依赖
    for dep in "${required_deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_required+=("$dep")
        fi
    done
    
    # 检查可选依赖
    for dep in "${optional_deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_optional+=("$dep")
        fi
    done
    
    # 安装缺失的必需依赖
    if [[ ${#missing_required[@]} -gt 0 ]]; then
        log_info "安装缺失的必需依赖: ${missing_required[*]}"
        for dep in "${missing_required[@]}"; do
            if ! install_package "$dep"; then
                log_error "安装依赖失败: $dep"
                FAILED_STEP="dependency_check"
                return 1
            fi
        done
    fi
    
    # 提示可选依赖
    if [[ ${#missing_optional[@]} -gt 0 ]]; then
        log_warn "缺少可选依赖: ${missing_optional[*]}"
        log_info "这些依赖用于从源码构建，如果使用预编译版本则不需要"
    fi
    
    COMPLETED_STEPS+=("dependency_check")
    log_success "依赖检查完成"
    echo ""
}

# 备份现有配置
backup_existing_config() {
    log_info "备份现有配置..."
    
    local backup_items=(
        "$ZASHBOARD_DIR"
        "$NGINX_CONFIG_DIR/sites-available/zashboard"
        "$NGINX_CONFIG_DIR/sites-enabled/zashboard"
    )
    
    local has_backup=false
    
    for item in "${backup_items[@]}"; do
        if [[ -e "$item" ]]; then
            if [[ ! -d "$BACKUP_DIR" ]]; then
                mkdir -p "$BACKUP_DIR"
            fi
            
            local backup_name=$(basename "$item")
            cp -r "$item" "$BACKUP_DIR/$backup_name" 2>/dev/null || true
            has_backup=true
            log_debug "已备份: $item -> $BACKUP_DIR/$backup_name"
        fi
    done
    
    if [[ "$has_backup" = true ]]; then
        log_info "配置备份保存在: $BACKUP_DIR"
    else
        log_debug "没有发现需要备份的配置"
    fi
}

# 回滚函数
rollback_installation() {
    log_error "安装失败，开始回滚..."
    
    # 停止服务
    systemctl stop nginx 2>/dev/null || true
    
    # 恢复备份
    if [[ -d "$BACKUP_DIR" ]]; then
        log_info "恢复备份配置..."
        
        if [[ -d "$BACKUP_DIR/zashboard" ]]; then
            rm -rf "$ZASHBOARD_DIR" 2>/dev/null || true
            cp -r "$BACKUP_DIR/zashboard" "$ZASHBOARD_DIR" 2>/dev/null || true
        fi
        
        if [[ -f "$BACKUP_DIR/zashboard" ]]; then
            cp "$BACKUP_DIR/zashboard" "$NGINX_CONFIG_DIR/sites-available/zashboard" 2>/dev/null || true
            ln -sf "$NGINX_CONFIG_DIR/sites-available/zashboard" "$NGINX_CONFIG_DIR/sites-enabled/zashboard" 2>/dev/null || true
        fi
    fi
    
    # 清理临时文件
    rm -rf "$TEMP_DOWNLOAD_DIR" 2>/dev/null || true
    
    log_info "回滚完成"
    log_info "如需帮助，请查看日志或联系技术支持"
}

# 安装nginx
install_nginx() {
    log_info "安装nginx..."
    show_progress "nginx_install"
    
    # 检查nginx是否已安装
    if command -v nginx &> /dev/null; then
        local nginx_version
        nginx_version=$(nginx -v 2>&1 | grep -o '[0-9.]*' | head -1)
        log_info "nginx 已安装 (版本: $nginx_version)，跳过安装步骤"
        COMPLETED_STEPS+=("nginx_install")
        echo ""
        return 0
    fi
    
    # 使用通用函数安装nginx
    if ! install_package "nginx"; then
        log_error "nginx 安装失败"
        FAILED_STEP="nginx_install"
        return 1
    fi
    
    # 启用nginx服务
    if ! systemctl enable nginx; then
        log_error "启用nginx服务失败"
        FAILED_STEP="nginx_install"
        return 1
    fi
    
    COMPLETED_STEPS+=("nginx_install")
    log_success "nginx 安装完成"
    echo ""
}

# 下载并部署zashboard
deploy_zashboard() {
    log_info "下载并部署zashboard面板..."
    show_progress "zashboard_deploy"
    
    # 创建目录
    if ! mkdir -p "$ZASHBOARD_DIR"; then
        log_error "创建zashboard目录失败: $ZASHBOARD_DIR"
        FAILED_STEP="zashboard_deploy"
        return 1
    fi
    
    # 切换到临时目录
    cd "$TEMP_DOWNLOAD_DIR" || {
        log_error "无法切换到临时目录: $TEMP_DOWNLOAD_DIR"
        FAILED_STEP="zashboard_deploy"
        return 1
    }
    
    # 获取最新版本信息
    log_info "获取zashboard最新版本信息..."
    local api_url="https://api.github.com/repos/xzq849/zashboard/releases/latest"
    local latest_info
    
    if ! latest_info=$(safe_curl "$api_url"); then
        log_warn "无法获取版本信息，尝试从源码构建..."
        if ! build_from_source; then
            FAILED_STEP="zashboard_deploy"
            return 1
        fi
        COMPLETED_STEPS+=("zashboard_deploy")
        echo ""
        return 0
    fi
    
    # 解析版本信息
    local version_tag
    version_tag=$(echo "$latest_info" | jq -r '.tag_name' 2>/dev/null || echo "unknown")
    log_info "最新版本: $version_tag"
    
    # 解析下载链接
    local download_url
    download_url=$(echo "$latest_info" | jq -r '.assets[] | select(.name | contains("dist.zip")) | .browser_download_url' 2>/dev/null)
    
    if [[ -z "$download_url" || "$download_url" == "null" ]]; then
        log_warn "无法获取预编译版本，尝试从源码构建..."
        if ! build_from_source; then
            FAILED_STEP="zashboard_deploy"
            return 1
        fi
        COMPLETED_STEPS+=("zashboard_deploy")
        echo ""
        return 0
    fi
    
    # 下载zashboard
    log_info "下载zashboard: $download_url"
    local zip_file="$TEMP_DOWNLOAD_DIR/zashboard-dist.zip"
    
    # 显示下载进度
    if ! curl -L --progress-bar -o "$zip_file" "$download_url"; then
        log_error "下载zashboard失败"
        FAILED_STEP="zashboard_deploy"
        return 1
    fi
    
    # 验证下载文件
    if [[ ! -f "$zip_file" ]] || [[ ! -s "$zip_file" ]]; then
        log_error "下载的文件无效或为空"
        FAILED_STEP="zashboard_deploy"
        return 1
    fi
    
    # 解压到目标目录
    log_info "解压zashboard到 $ZASHBOARD_DIR"
    if ! unzip -o "$zip_file" -d "$ZASHBOARD_DIR/"; then
        log_error "解压zashboard失败"
        FAILED_STEP="zashboard_deploy"
        return 1
    fi
    
    # 验证解压结果
    if [[ ! -f "$ZASHBOARD_DIR/index.html" ]]; then
        log_error "解压后未找到index.html文件"
        FAILED_STEP="zashboard_deploy"
        return 1
    fi
    
    # 设置权限
    set_zashboard_permissions
    
    COMPLETED_STEPS+=("zashboard_deploy")
    log_success "zashboard 部署完成"
    echo ""
}

# 设置zashboard权限
set_zashboard_permissions() {
    log_info "设置zashboard权限..."
    
    # 检查www-data用户是否存在
    if id -u www-data &> /dev/null; then
        chown -R www-data:www-data "$ZASHBOARD_DIR" || {
            log_warn "设置所有者失败，使用默认权限"
        }
    else
        log_warn "www-data用户不存在，跳过所有者设置"
    fi
    
    # 设置目录权限
    chmod -R 755 "$ZASHBOARD_DIR" || {
        log_warn "设置权限失败"
    }
    
    log_success "权限设置完成"
}

# 从源码构建zashboard
build_from_source() {
    log_info "从源码构建zashboard..."
    
    # 检查必要的构建工具
    local missing_tools=()
    
    if ! command -v git &> /dev/null; then
        missing_tools+=("git")
    fi
    
    if ! command -v node &> /dev/null && ! command -v nodejs &> /dev/null; then
        missing_tools+=("nodejs")
    fi
    
    if ! command -v npm &> /dev/null; then
        missing_tools+=("npm")
    fi
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "缺少构建工具: ${missing_tools[*]}"
        log_info "正在尝试安装构建工具..."
        
        for tool in "${missing_tools[@]}"; do
            if ! install_package "$tool"; then
                log_error "安装构建工具失败: $tool"
                return 1
            fi
        done
    fi
    
    local src_dir="$TEMP_DOWNLOAD_DIR/zashboard-src"
    
    # 克隆仓库
    log_info "克隆zashboard源码..."
    if ! git clone --depth 1 https://github.com/xzq849/zashboard.git "$src_dir"; then
        log_error "克隆源码失败"
        return 1
    fi
    
    # 切换到源码目录
    cd "$src_dir" || {
        log_error "无法切换到源码目录"
        return 1
    }
    
    # 安装依赖
    log_info "安装构建依赖..."
    if ! npm install --production; then
        log_error "安装依赖失败"
        return 1
    fi
    
    # 构建项目
    log_info "构建项目..."
    if ! npm run build; then
        log_error "构建失败"
        return 1
    fi
    
    # 检查构建结果
    if [[ ! -d "dist" ]]; then
        log_error "构建目录不存在"
        return 1
    fi
    
    # 复制构建结果
    log_info "复制构建结果到 $ZASHBOARD_DIR"
    if ! cp -r dist/* "$ZASHBOARD_DIR/"; then
        log_error "复制构建结果失败"
        return 1
    fi
    
    # 设置权限
    set_zashboard_permissions
    
    log_success "从源码构建完成"
}

# 配置nginx
configure_nginx() {
    log_info "配置nginx..."
    show_progress "nginx_config"
    
    local nginx_config_file="$NGINX_CONFIG_DIR/sites-available/zashboard"
    local nginx_enabled_file="$NGINX_CONFIG_DIR/sites-enabled/zashboard"
    local nginx_default_file="$NGINX_CONFIG_DIR/sites-enabled/default"
    
    # 检查nginx配置目录
    if [[ ! -d "$NGINX_CONFIG_DIR" ]]; then
        log_error "nginx配置目录不存在: $NGINX_CONFIG_DIR"
        FAILED_STEP="nginx_config"
        return 1
    fi
    
    # 创建sites-available和sites-enabled目录（如果不存在）
    mkdir -p "$NGINX_CONFIG_DIR/sites-available" "$NGINX_CONFIG_DIR/sites-enabled"
    
    # 检测端口占用
    local web_port="${ZASHBOARD_PORT:-80}"
    if netstat -tuln 2>/dev/null | grep -q ":$web_port "; then
        log_warn "端口 $web_port 已被占用，尝试使用其他端口"
        for port in 8080 8888 9000 9080; do
            if ! netstat -tuln 2>/dev/null | grep -q ":$port "; then
                web_port=$port
                log_info "使用端口: $port"
                break
            fi
        done
    fi
    
    # 创建nginx配置文件
    log_info "创建nginx配置文件..."
    cat > "$nginx_config_file" << EOF
server {
    listen $web_port;
    server_name _;
    
    # 安全配置
    server_tokens off;
    
    # 日志配置
    access_log /var/log/nginx/zashboard_access.log;
    error_log /var/log/nginx/zashboard_error.log;
    
    # zashboard 面板
    location / {
        root $ZASHBOARD_DIR;
        index index.html;
        try_files \$uri \$uri/ /index.html;
        
        # 添加安全头
        add_header X-Frame-Options DENY;
        add_header X-Content-Type-Options nosniff;
        add_header X-XSS-Protection "1; mode=block";
        add_header Referrer-Policy "strict-origin-when-cross-origin";
    }
    
    # Sing-box API 代理
    location /api/ {
        proxy_pass http://127.0.0.1:${SING_BOX_API_PORT:-9090}/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket 支持
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # 超时设置
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # 缓冲设置
        proxy_buffering off;
        proxy_request_buffering off;
    }
    
    # 静态资源缓存
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        root $ZASHBOARD_DIR;
        expires 1y;
        add_header Cache-Control "public, immutable";
        add_header Vary "Accept-Encoding";
        
        # 启用gzip压缩
        gzip on;
        gzip_vary on;
        gzip_types text/css application/javascript image/svg+xml;
    }
    
    # 健康检查端点
    location /health {
        access_log off;
        return 200 "OK";
        add_header Content-Type text/plain;
    }
}
EOF

    if [[ $? -ne 0 ]]; then
        log_error "创建nginx配置文件失败"
        FAILED_STEP="nginx_config"
        return 1
    fi

    # 启用站点
    log_info "启用zashboard站点..."
    if ! ln -sf "$nginx_config_file" "$nginx_enabled_file"; then
        log_error "启用站点失败"
        FAILED_STEP="nginx_config"
        return 1
    fi
    
    # 禁用默认站点
    if [[ -f "$nginx_default_file" ]]; then
        rm -f "$nginx_default_file"
        log_info "已禁用默认站点"
    fi
    
    # 测试nginx配置
    log_info "测试nginx配置..."
    if ! nginx -t; then
        log_error "nginx配置测试失败"
        FAILED_STEP="nginx_config"
        return 1
    fi
    
    COMPLETED_STEPS+=("nginx_config")
    log_success "nginx 配置完成"
    echo ""
}

# 配置防火墙
configure_firewall() {
    log_info "配置防火墙..."
    show_progress "firewall_config"
    
    # 定义需要开放的端口
    local ports=(
        "${ZASHBOARD_PORT:-80}/tcp"    # HTTP
        "${SING_BOX_HTTP_PORT:-7890}/tcp"   # Sing-box HTTP代理
        "${SING_BOX_API_PORT:-9090}/tcp"    # Sing-box API
    )
    
    local success=true
    
    # 检测并配置防火墙
    if command -v ufw &> /dev/null; then
        log_info "使用UFW配置防火墙..."
        for port in "${ports[@]}"; do
            if ! ufw allow "$port" &> /dev/null; then
                log_warn "UFW开放端口失败: $port"
                success=false
            else
                log_debug "UFW已开放端口: $port"
            fi
        done
        
        if $success; then
            log_success "UFW 防火墙规则配置完成"
        fi
        
    elif command -v firewall-cmd &> /dev/null; then
        log_info "使用firewalld配置防火墙..."
        for port in "${ports[@]}"; do
            if ! firewall-cmd --permanent --add-port="$port" &> /dev/null; then
                log_warn "firewalld开放端口失败: $port"
                success=false
            else
                log_debug "firewalld已开放端口: $port"
            fi
        done
        
        if ! firewall-cmd --reload &> /dev/null; then
            log_warn "firewalld重载配置失败"
            success=false
        fi
        
        if $success; then
            log_success "firewalld 防火墙规则配置完成"
        fi
        
    else
        log_warn "未检测到支持的防火墙管理工具"
        log_info "请手动开放以下端口: ${ports[*]}"
    fi
    
    COMPLETED_STEPS+=("firewall_config")
    echo ""
    return 0
}

# 创建增强的管理脚本
create_management_script() {
    log_info "创建管理脚本..."
    show_progress "management_script"
    
    local script_path="/usr/local/bin/proxy-manager"
    
    cat > "$script_path" << 'EOF'
#!/bin/bash

# 代理服务管理脚本
# 用于管理 sing-box 和 zashboard 服务
# 版本: 2.0.0

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 配置文件路径
SING_BOX_CONFIG="/etc/sing-box/config.json"
ZASHBOARD_DIR="/var/www/zashboard"
NGINX_CONFIG="/etc/nginx/sites-available/zashboard"

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# 检查服务状态
check_service_status() {
    local service="$1"
    if systemctl is-active --quiet "$service"; then
        echo -e "${GREEN}运行中${NC}"
    else
        echo -e "${RED}已停止${NC}"
    fi
}

# 获取服务端口
get_service_port() {
    local service="$1"
    case "$service" in
        "nginx")
            grep -o 'listen [0-9]*' "$NGINX_CONFIG" 2>/dev/null | awk '{print $2}' | head -1 || echo "80"
            ;;
        "sing-box")
            jq -r '.inbounds[] | select(.type=="mixed") | .listen_port' "$SING_BOX_CONFIG" 2>/dev/null || echo "7890"
            ;;
        *)
            echo "N/A"
            ;;
    esac
}

# 诊断功能
diagnose_system() {
    echo "=== 系统诊断报告 ==="
    echo ""
    
    echo "📊 服务状态:"
    printf "  %-15s %-10s %-10s\n" "服务" "状态" "端口"
    printf "  %-15s %-10s %-10s\n" "sing-box" "$(check_service_status sing-box)" "$(get_service_port sing-box)"
    printf "  %-15s %-10s %-10s\n" "nginx" "$(check_service_status nginx)" "$(get_service_port nginx)"
    echo ""
    
    echo "🌐 网络连接:"
    local test_urls=("https://www.google.com" "https://www.github.com")
    for url in "${test_urls[@]}"; do
        if curl -s --connect-timeout 5 --max-time 10 "$url" > /dev/null; then
            echo -e "  $url: ${GREEN}✓${NC}"
        else
            echo -e "  $url: ${RED}✗${NC}"
        fi
    done
    echo ""
    
    echo "📁 文件检查:"
    local files=("$SING_BOX_CONFIG" "$ZASHBOARD_DIR/index.html" "$NGINX_CONFIG")
    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            echo -e "  $file: ${GREEN}✓${NC}"
        else
            echo -e "  $file: ${RED}✗${NC}"
        fi
    done
    echo ""
    
    echo "💾 磁盘空间:"
    df -h / | tail -1 | awk '{printf "  根分区: %s 已用 %s 可用 %s\n", $2, $3, $4}'
    echo ""
    
    echo "🔧 系统信息:"
    echo "  操作系统: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
    echo "  内核版本: $(uname -r)"
    echo "  系统负载: $(uptime | awk -F'load average:' '{print $2}')"
}

# 健康检查
health_check() {
    local issues=0
    
    echo "🏥 健康检查..."
    echo ""
    
    # 检查服务状态
    if ! systemctl is-active --quiet sing-box; then
        log_error "sing-box 服务未运行"
        ((issues++))
    fi
    
    if ! systemctl is-active --quiet nginx; then
        log_error "nginx 服务未运行"
        ((issues++))
    fi
    
    # 检查配置文件
    if [[ ! -f "$SING_BOX_CONFIG" ]]; then
        log_error "sing-box 配置文件不存在"
        ((issues++))
    elif ! sing-box check -c "$SING_BOX_CONFIG" &>/dev/null; then
        log_error "sing-box 配置文件无效"
        ((issues++))
    fi
    
    if [[ ! -f "$NGINX_CONFIG" ]]; then
        log_error "nginx 配置文件不存在"
        ((issues++))
    elif ! nginx -t &>/dev/null; then
        log_error "nginx 配置文件无效"
        ((issues++))
    fi
    
    # 检查端口占用
    local nginx_port
    nginx_port=$(get_service_port nginx)
    if ! netstat -tuln 2>/dev/null | grep -q ":$nginx_port "; then
        log_warn "nginx 端口 $nginx_port 未监听"
        ((issues++))
    fi
    
    if [[ $issues -eq 0 ]]; then
        log_info "✅ 系统健康状态良好"
    else
        log_warn "⚠️  发现 $issues 个问题"
    fi
    
    return $issues
}

# 备份配置
backup_config() {
    local backup_dir="/var/backups/proxy-manager-$(date +%Y%m%d-%H%M%S)"
    
    log_info "创建配置备份..."
    mkdir -p "$backup_dir"
    
    # 备份配置文件
    if [[ -f "$SING_BOX_CONFIG" ]]; then
        cp "$SING_BOX_CONFIG" "$backup_dir/"
    fi
    
    if [[ -f "$NGINX_CONFIG" ]]; then
        cp "$NGINX_CONFIG" "$backup_dir/"
    fi
    
    # 备份zashboard
    if [[ -d "$ZASHBOARD_DIR" ]]; then
        tar -czf "$backup_dir/zashboard.tar.gz" -C "$(dirname "$ZASHBOARD_DIR")" "$(basename "$ZASHBOARD_DIR")"
    fi
    
    log_info "备份完成: $backup_dir"
}

# 显示帮助
show_help() {
    cat << 'HELP'
代理服务管理工具

用法: proxy-manager <命令> [选项]

基础命令:
  start           启动所有服务
  stop            停止所有服务
  restart         重启所有服务
  status          查看服务状态
  logs            查看sing-box日志

管理命令:
  diagnose        系统诊断
  health-check    健康检查
  backup          备份配置
  update-ui       更新zashboard面板
  config          配置管理

配置命令:
  config show     显示当前配置
  config validate 验证配置文件
  config reload   重新加载配置

示例:
  proxy-manager start
  proxy-manager logs --tail 50
  proxy-manager diagnose
  proxy-manager config validate

HELP
}

case "$1" in
    start)
        log_info "启动代理服务..."
        if systemctl start sing-box; then
            log_info "sing-box 服务已启动"
        else
            log_error "sing-box 服务启动失败"
        fi
        
        if systemctl start nginx; then
            log_info "nginx 服务已启动"
        else
            log_error "nginx 服务启动失败"
        fi
        ;;
    stop)
        log_info "停止代理服务..."
        if systemctl stop sing-box; then
            log_info "sing-box 服务已停止"
        else
            log_warn "sing-box 服务停止失败"
        fi
        
        if systemctl stop nginx; then
            log_info "nginx 服务已停止"
        else
            log_warn "nginx 服务停止失败"
        fi
        ;;
    restart)
        log_info "重启代理服务..."
        if systemctl restart sing-box; then
            log_info "sing-box 服务已重启"
        else
            log_error "sing-box 服务重启失败"
        fi
        
        if systemctl restart nginx; then
            log_info "nginx 服务已重启"
        else
            log_error "nginx 服务重启失败"
        fi
        ;;
    status)
        echo "=== 服务状态 ==="
        printf "%-15s %-10s %-10s\n" "服务" "状态" "端口"
        printf "%-15s %-10s %-10s\n" "sing-box" "$(check_service_status sing-box)" "$(get_service_port sing-box)"
        printf "%-15s %-10s %-10s\n" "nginx" "$(check_service_status nginx)" "$(get_service_port nginx)"
        ;;
    logs)
        shift
        echo "=== sing-box 日志 ==="
        journalctl -u sing-box "$@"
        ;;
    diagnose)
        diagnose_system
        ;;
    health-check)
        health_check
        ;;
    backup)
        backup_config
        ;;
    update-ui)
        log_info "更新zashboard面板..."
        cd /tmp || exit 1
        
        if curl -L -o zashboard-dist.zip "https://github.com/xzq849/zashboard/releases/latest/download/dist.zip"; then
            if unzip -o zashboard-dist.zip -d "$ZASHBOARD_DIR/"; then
                if id -u www-data &> /dev/null; then
                    chown -R www-data:www-data "$ZASHBOARD_DIR"
                fi
                chmod -R 755 "$ZASHBOARD_DIR"
                log_info "面板更新完成"
            else
                log_error "解压面板文件失败"
                exit 1
            fi
        else
            log_error "下载面板文件失败"
            exit 1
        fi
        ;;
    config)
        case "$2" in
            show)
                echo "=== Sing-box 配置 ==="
                if [[ -f "$SING_BOX_CONFIG" ]]; then
                    jq . "$SING_BOX_CONFIG" 2>/dev/null || cat "$SING_BOX_CONFIG"
                else
                    log_error "配置文件不存在"
                fi
                ;;
            validate)
                log_info "验证配置文件..."
                if sing-box check -c "$SING_BOX_CONFIG"; then
                    log_info "✅ 配置文件有效"
                else
                    log_error "❌ 配置文件无效"
                    exit 1
                fi
                ;;
            reload)
                log_info "重新加载配置..."
                if systemctl reload sing-box; then
                    log_info "配置重新加载完成"
                else
                    log_error "配置重新加载失败"
                    exit 1
                fi
                ;;
            *)
                echo "用法: proxy-manager config {show|validate|reload}"
                exit 1
                ;;
        esac
        ;;
    -h|--help)
        show_help
        ;;
    *)
        echo "用法: $0 {start|stop|restart|status|logs|diagnose|health-check|backup|update-ui|config}"
        echo "使用 '$0 --help' 查看详细帮助"
        exit 1
        ;;
esac
EOF

    if [[ $? -ne 0 ]]; then
        log_error "创建管理脚本失败"
        FAILED_STEP="management_script"
        return 1
    fi

    # 设置执行权限
    if ! chmod +x "$script_path"; then
        log_error "设置管理脚本权限失败"
        FAILED_STEP="management_script"
        return 1
    fi
    
    COMPLETED_STEPS+=("management_script")
    log_success "管理脚本创建完成: $script_path"
    echo ""
}

# 启动服务
start_services() {
    log_info "启动服务..."
    show_progress "service_start"
    
    # 启动nginx
    if ! systemctl start nginx; then
        log_error "启动nginx失败"
        FAILED_STEP="service_start"
        return 1
    fi
    
    # 检查nginx状态
    sleep 2
    if ! systemctl is-active --quiet nginx; then
        log_error "nginx服务启动后立即停止"
        FAILED_STEP="service_start"
        return 1
    fi
    
    COMPLETED_STEPS+=("service_start")
    log_success "服务启动完成"
    echo ""
}

# 显示帮助信息
show_help() {
    cat << EOF
zashboard 面板部署脚本 v2.0.0

用法: $0 [选项]

选项:
    -h, --help          显示此帮助信息
    -s, --source        从源码构建（默认使用预编译版本）
    -p, --port PORT     设置面板端口（默认: 80）
    --api-port PORT     设置API端口（默认: 9090）
    --skip-firewall     跳过防火墙配置
    --skip-nginx        跳过Nginx安装和配置
    --skip-backup       跳过配置备份
    --dry-run           仅显示将要执行的操作，不实际执行
    --force             强制安装，忽略警告

示例:
    $0                  # 使用默认设置部署
    $0 -s               # 从源码构建
    $0 -p 8080          # 使用8080端口
    $0 --skip-firewall  # 跳过防火墙配置
    $0 --dry-run        # 预览安装步骤

新功能:
    ✨ 增强的错误处理和回滚机制
    📊 实时进度显示
    🌐 网络连接检测
    🔍 详细的系统诊断
    📋 配置备份和恢复
    🛡️ 安全配置优化

部署完成后，可以使用以下命令管理服务:
    proxy-manager start         # 启动服务
    proxy-manager stop          # 停止服务
    proxy-manager restart       # 重启服务
    proxy-manager status        # 查看状态
    proxy-manager diagnose      # 系统诊断
    proxy-manager health-check  # 健康检查
    proxy-manager backup        # 备份配置
    proxy-manager update-ui     # 更新面板

EOF
}

# 主函数
main() {
    local build_from_source=false
    local skip_firewall=false
    local skip_nginx=false
    local skip_backup=false
    local dry_run=false
    local force_install=false
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -s|--source)
                build_from_source=true
                shift
                ;;
            -p|--port)
                ZASHBOARD_PORT="$2"
                shift 2
                ;;
            --api-port)
                SING_BOX_API_PORT="$2"
                shift 2
                ;;
            --skip-firewall)
                skip_firewall=true
                shift
                ;;
            --skip-nginx)
                skip_nginx=true
                shift
                ;;
            --skip-backup)
                skip_backup=true
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --force)
                force_install=true
                shift
                ;;
            *)
                log_error "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    echo "🚀 zashboard 面板部署脚本 v2.0.0"
    echo "================================================"
    echo ""
    
    log_info "配置参数:"
    log_info "  面板端口: ${ZASHBOARD_PORT:-80}"
    log_info "  API端口: ${SING_BOX_API_PORT:-9090}"
    log_info "  从源码构建: $([ "$build_from_source" = true ] && echo "是" || echo "否")"
    log_info "  跳过防火墙: $([ "$skip_firewall" = true ] && echo "是" || echo "否")"
    log_info "  跳过Nginx: $([ "$skip_nginx" = true ] && echo "是" || echo "否")"
    log_info "  跳过备份: $([ "$skip_backup" = true ] && echo "是" || echo "否")"
    echo ""
    
    if [[ "$dry_run" = true ]]; then
        log_info "🔍 预览模式 - 将要执行的步骤："
        echo ""
        for i in "${!INSTALL_STEPS[@]}"; do
            local step="${INSTALL_STEPS[$i]}"
            local step_name=""
            case "$step" in
                "network_check") step_name="网络连接检测" ;;
                "dependency_check") step_name="依赖检查和安装" ;;
                "nginx_install") step_name="$([ "$skip_nginx" = false ] && echo "安装Nginx" || echo "跳过Nginx安装")" ;;
                "zashboard_deploy") step_name="$([ "$build_from_source" = true ] && echo "从源码构建zashboard" || echo "下载预编译的zashboard")" ;;
                "nginx_config") step_name="$([ "$skip_nginx" = false ] && echo "配置Nginx" || echo "跳过Nginx配置")" ;;
                "firewall_config") step_name="$([ "$skip_firewall" = false ] && echo "配置防火墙" || echo "跳过防火墙配置")" ;;
                "management_script") step_name="创建管理脚本" ;;
                "service_start") step_name="启动服务" ;;
            esac
            printf "%2d. %s\n" $((i + 1)) "$step_name"
        done
        echo ""
        log_info "使用 --force 参数执行实际安装"
        return 0
    fi
    
    # 设置错误处理
    trap 'rollback_installation' ERR
    
    # 检查是否为 root 用户
    check_root
    
    # 备份现有配置
    if [[ "$skip_backup" = false ]]; then
        backup_existing_config
    fi
    
    # 执行安装步骤
    check_network_connectivity
    enhanced_dependency_check
    
    if [[ "$skip_nginx" = false ]]; then
        install_nginx
    else
        log_info "⏭️  跳过Nginx安装"
        COMPLETED_STEPS+=("nginx_install")
    fi
    
    if [[ "$build_from_source" = true ]]; then
        build_from_source
        COMPLETED_STEPS+=("zashboard_deploy")
    else
        deploy_zashboard
    fi
    
    if [[ "$skip_nginx" = false ]]; then
        configure_nginx
    else
        log_info "⏭️  跳过Nginx配置"
        COMPLETED_STEPS+=("nginx_config")
    fi
    
    if [[ "$skip_firewall" = false ]]; then
        configure_firewall
    else
        log_info "⏭️  跳过防火墙配置"
        COMPLETED_STEPS+=("firewall_config")
    fi
    
    create_management_script
    
    if [[ "$skip_nginx" = false ]]; then
        start_services
    else
        log_info "⏭️  跳过服务启动"
        COMPLETED_STEPS+=("service_start")
    fi
    
    # 清理临时文件
    if [[ -d "$TEMP_DOWNLOAD_DIR" ]]; then
        rm -rf "$TEMP_DOWNLOAD_DIR"
        log_debug "清理临时文件完成"
    fi
    
    # 显示完成信息
    echo ""
    echo "🎉 zashboard 面板部署完成！"
    echo "================================================"
    echo ""
    log_info "📋 部署摘要:"
    log_info "  ✅ 完成步骤: ${#COMPLETED_STEPS[@]}/${#INSTALL_STEPS[@]}"
    log_info "  🌐 访问地址: http://$(get_server_ip):${ZASHBOARD_PORT:-80}"
    log_info "  📁 面板目录: $ZASHBOARD_DIR"
    log_info "  ⚙️  配置文件: $NGINX_CONFIG_DIR/sites-available/zashboard"
    if [[ -d "$BACKUP_DIR" ]]; then
        log_info "  💾 配置备份: $BACKUP_DIR"
    fi
    echo ""
    log_info "🛠️  管理命令:"
    log_info "  proxy-manager start         # 启动服务"
    log_info "  proxy-manager status        # 查看状态"
    log_info "  proxy-manager diagnose      # 系统诊断"
    log_info "  proxy-manager health-check  # 健康检查"
    log_info "  proxy-manager --help        # 查看所有命令"
    echo ""
    log_info "📚 更多帮助:"
    log_info "  查看文档: README.md, INSTALL.md, TROUBLESHOOTING.md"
    log_info "  技术支持: 运行 'proxy-manager diagnose' 收集诊断信息"
}

# 获取服务器IP地址
get_server_ip() {
    local ip
    ip=$(curl -s --connect-timeout 5 ifconfig.me 2>/dev/null || curl -s --connect-timeout 5 ipinfo.io/ip 2>/dev/null || echo "your-server-ip")
    echo "$ip"
}

# 如果直接运行此脚本，则执行主函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi