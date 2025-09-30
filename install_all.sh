#!/bin/bash
set -euo pipefail

# 一键安装脚本 - 安装sing-box、配置代理和面板
# 支持Debian/Ubuntu/CentOS/RHEL系统

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



# 检查系统要求
check_system() {
    log_info "检查系统要求..."
    
    # 检查操作系统
    if [[ ! -f /etc/debian_version ]] && [[ ! -f /etc/redhat-release ]]; then
        log_error "此脚本仅支持 Debian/Ubuntu 和 CentOS/RHEL 系统"
        exit 1
    fi
    
    # 检查root权限
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行"
        exit 1
    fi
    
    # 检查网络连接
    if ! ping -c 1 google.com &> /dev/null; then
        log_warn "网络连接可能有问题，但继续安装..."
    fi
    
    log_info "系统检查通过"
}

# 检测系统架构
detect_arch() {
    case $(uname -m) in
        x86_64)
            ARCH="amd64"
            ;;
        aarch64)
            ARCH="arm64"
            ;;
        armv7l)
            ARCH="armv7"
            ;;
        *)
            log_error "不支持的系统架构: $(uname -m)"
            exit 1
            ;;
    esac
    log_info "检测到系统架构: $ARCH"
}

# 智能下载函数 - 并发测试镜像速度
smart_download() {
    local urls=("$@")
    local output_file="sing-box.tar.gz"
    local test_timeout=5
    local fastest_url=""
    local fastest_time=999999
    
    log_info "正在测试 ${#urls[@]} 个下载源的速度..."
    
    # 创建临时文件存储测试结果
    local temp_results="/tmp/mirror_test_$$"
    
    # 并发测试所有镜像的响应时间
    for url in "${urls[@]}"; do
        (
            local start_time=$(date +%s%N)
            if timeout $test_timeout curl -s -I --connect-timeout 3 "$url" >/dev/null 2>&1; then
                local end_time=$(date +%s%N)
                local response_time=$(( (end_time - start_time) / 1000000 ))
                echo "$response_time|$url" >> "$temp_results"
            else
                echo "999999|$url" >> "$temp_results"
            fi
        ) &
    done
    
    # 等待所有测试完成
    wait
    
    # 选择最快的镜像
    if [[ -f "$temp_results" ]]; then
        local best_result=$(sort -n "$temp_results" | head -1)
        fastest_time=$(echo "$best_result" | cut -d'|' -f1)
        fastest_url=$(echo "$best_result" | cut -d'|' -f2)
        rm -f "$temp_results"
    else
        fastest_time=999999
        fastest_url="fallback"
    fi
    
    if [[ "$fastest_url" != "fallback" ]] && [[ $fastest_time -lt 10000 ]]; then
        log_info "选择最快镜像 (${fastest_time}ms): $fastest_url"
        
        # 构建wget参数数组
        local wget_opts=(
            --tries=5
            --timeout=30
            --connect-timeout=10
            --read-timeout=60
            --continue
            --progress=bar:force
            --show-progress
            --no-check-certificate
            --user-agent="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
            --header="Accept: application/octet-stream,*/*;q=0.9"
            --header="Accept-Language: zh-CN,zh;q=0.9,en;q=0.8"
            --header="Cache-Control: no-cache"
            --dns-timeout=10
            --retry-connrefused
            --waitretry=3
            -O "$output_file"
        )
        
        # 如果设置了代理，添加代理参数
        if [[ -n "${HTTP_PROXY:-}" ]]; then
            wget_opts+=(--proxy=on)
            wget_opts+=(--http-proxy="$HTTP_PROXY")
            if [[ -n "${HTTPS_PROXY:-}" ]]; then
                wget_opts+=(--https-proxy="$HTTPS_PROXY")
            fi
            log_info "使用代理下载: $HTTP_PROXY"
        fi
        
        # 使用最快的镜像下载
        if timeout 300 wget "${wget_opts[@]}" "$fastest_url" 2>&1 | tee -a "${LOG_DIR}/sing-box.log" 2>/dev/null || true; then
            return 0
        fi
    fi
    
    # 如果智能选择失败，回退到逐个尝试
    log_warn "智能下载失败，回退到逐个尝试模式"
    return 1
}

# 下载并安装sing-box
install_singbox() {
    log_info "下载并安装sing-box..."
    
    # 检测并设置代理
    setup_proxy
    
    # 确保日志目录存在（处理相对路径）
    if [[ "${LOG_DIR}" == ./* ]]; then
        # 如果是相对路径，需要在当前工作目录创建
        local abs_log_dir="$(pwd)/${LOG_DIR#./}"
        mkdir -p "$abs_log_dir" 2>/dev/null || true
    else
        mkdir -p "${LOG_DIR}" 2>/dev/null || true
    fi
    
    # 获取最新版本，如果失败则使用备用版本
    local api_response
    api_response=$(safe_curl "https://api.github.com/repos/SagerNet/sing-box/releases/latest" 2>/dev/null)
    
    if [[ -n "$api_response" ]] && echo "$api_response" | jq -e '.tag_name' >/dev/null 2>&1; then
        LATEST_VERSION=$(echo "$api_response" | jq -r '.tag_name')
        log_info "从GitHub API获取到最新版本: $LATEST_VERSION"
    else
        # 备用版本号（定期更新）
        LATEST_VERSION="v1.8.0"
        log_warn "无法从GitHub API获取版本信息，使用备用版本: $LATEST_VERSION"
    fi
    
    # 下载sing-box
    # 定义可用的下载源（基于测试结果，只保留可用镜像）
    DOWNLOAD_URLS=(
        "https://hub.gitmirror.com/https://github.com/SagerNet/sing-box/releases/download/${LATEST_VERSION}/sing-box-${LATEST_VERSION#v}-linux-${ARCH}.tar.gz"
        "https://ghproxy.net/https://github.com/SagerNet/sing-box/releases/download/${LATEST_VERSION}/sing-box-${LATEST_VERSION#v}-linux-${ARCH}.tar.gz"
    )
    
    cd /tmp || { log_error "无法切换到/tmp目录"; return 1; }
    
    # 清理可能存在的旧文件
    rm -f sing-box.tar.gz sing-box.tar.gz.*
    
    # 首先尝试智能下载
    DOWNLOAD_SUCCESS=false
    if smart_download "${DOWNLOAD_URLS[@]}"; then
        # 验证下载的文件
        if [[ -f "sing-box.tar.gz" ]] && [[ $(stat -c%s "sing-box.tar.gz" 2>/dev/null || echo 0) -gt 1000000 ]]; then
            log_info "智能下载成功"
            DOWNLOAD_SUCCESS=true
        else
            log_warn "智能下载的文件不完整，尝试传统下载方式"
            rm -f sing-box.tar.gz
        fi
    fi
    
    # 如果智能下载失败，回退到逐个尝试
    if [[ "$DOWNLOAD_SUCCESS" == "false" ]]; then
        log_info "使用传统下载方式，逐个尝试下载源..."
        for i in "${!DOWNLOAD_URLS[@]}"; do
        DOWNLOAD_URL="${DOWNLOAD_URLS[$i]}"
        log_info "尝试下载源 $((i+1)): $DOWNLOAD_URL"
        
        # 构建wget参数数组
        local wget_opts=(
            --tries=5
            --timeout=15
            --connect-timeout=10
            --read-timeout=30
            --continue
            --progress=bar:force
            --show-progress
            --no-check-certificate
            --user-agent="Mozilla/5.0 (Linux; x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
            --header="Accept: application/octet-stream,*/*;q=0.9"
            --header="Accept-Language: zh-CN,zh;q=0.9,en;q=0.8"
            --header="Cache-Control: no-cache"
            --dns-timeout=10
            --retry-connrefused
            --waitretry=2
            -O sing-box.tar.gz
        )
        
        # 如果设置了代理，添加代理参数
        if [[ -n "${HTTP_PROXY:-}" ]]; then
            wget_opts+=(--proxy=on)
            wget_opts+=(--http-proxy="$HTTP_PROXY")
            if [[ -n "${HTTPS_PROXY:-}" ]]; then
                wget_opts+=(--https-proxy="$HTTPS_PROXY")
            fi
            log_info "使用代理下载: $HTTP_PROXY"
        fi
        
        # 使用优化的wget参数：重试、断点续传、超时设置、并发连接
        if timeout 300 wget "${wget_opts[@]}" "$DOWNLOAD_URL" 2>&1 | tee -a "${LOG_DIR}/sing-box.log" 2>/dev/null || true; then
            
            # 验证下载的文件
            if [[ -f "sing-box.tar.gz" ]] && [[ $(stat -c%s "sing-box.tar.gz" 2>/dev/null || echo 0) -gt 1000000 ]]; then
                log_info "下载源 $((i+1)) 下载成功"
                DOWNLOAD_SUCCESS=true
                break
            else
                log_warn "下载源 $((i+1)) 下载的文件不完整，尝试下一个源"
                rm -f sing-box.tar.gz
            fi
        else
            log_warn "下载源 $((i+1)) 下载失败，尝试下一个源"
            rm -f sing-box.tar.gz
        fi
    done
    fi
    
    if [[ "$DOWNLOAD_SUCCESS" == "true" ]]; then
        log_info "下载完成，开始解压..."
        if tar -xzf sing-box.tar.gz; then
            log_info "解压完成，开始安装..."
            # 安装到系统目录
            if cp sing-box-*/sing-box /usr/local/bin/ && chmod +x /usr/local/bin/sing-box; then
                log_info "sing-box二进制文件安装成功"
            else
                log_error "sing-box二进制文件安装失败"
                return 1
            fi
        else
            log_error "解压sing-box失败"
            return 1
        fi
    else
        log_error "所有下载源都失败，请检查网络连接或稍后重试"
        return 1
    fi
    
    # 创建配置目录
    mkdir -p /etc/sing-box
    mkdir -p /var/log/sing-box
    mkdir -p /var/cache/sing-box
    
    log_info "sing-box 安装完成"
}

# 创建sing-box用户
create_singbox_user() {
    log_info "创建sing-box用户..."
    if ! id "sing-box" &>/dev/null; then
        useradd -r -s /bin/false sing-box
    fi
    chown -R sing-box:sing-box /var/log/sing-box
    chown -R sing-box:sing-box /var/cache/sing-box
}

# 创建sing-box配置文件
create_singbox_config() {
    log_info "创建sing-box配置文件..."
    
    # 生成随机密钥
    SECRET_KEY=$(openssl rand -hex 16)
    
    cat > /etc/sing-box/config.json << EOF
{
  "log": {
    "level": "info",
    "output": "/var/log/sing-box/sing-box.log",
    "timestamp": true
  },
  "experimental": {
    "clash_api": {
      "external_controller": "0.0.0.0:9090",
      "external_ui": "/var/www/zashboard",
      "secret": "$SECRET_KEY",
      "external_ui_download_url": "https://github.com/xzq849/zashboard/releases/latest/download/dist.zip",
      "external_ui_download_detour": "direct",
      "default_mode": "rule"
    },
    "cache_file": {
      "enabled": true,
      "path": "/var/cache/sing-box/cache.db",
      "cache_id": "main",
      "store_fakeip": true,
      "store_rdrc": true,
      "rdrc_timeout": "7d"
    }
  },
  "dns": {
    "servers": [
      {
        "tag": "cloudflare",
        "address": "https://1.1.1.1/dns-query",
        "detour": "proxy"
      },
      {
        "tag": "local",
        "address": "223.5.5.5",
        "detour": "direct"
      },
      {
        "tag": "fakeip",
        "address": "fakeip"
      }
    ],
    "rules": [
      {
        "outbound": "any",
        "server": "local"
      },
      {
        "clash_mode": "direct",
        "server": "local"
      },
      {
        "clash_mode": "global",
        "server": "cloudflare"
      },
      {
        "rule_set": "geosite-cn",
        "server": "local"
      },
      {
        "query_type": [
          "A",
          "AAAA"
        ],
        "server": "fakeip"
      }
    ],
    "fakeip": {
      "enabled": true,
      "inet4_range": "198.18.0.0/15",
      "inet6_range": "fc00::/18"
    },
    "independent_cache": true,
    "strategy": "prefer_ipv4"
  },
  "inbounds": [
    {
      "type": "mixed",
      "tag": "mixed-in",
      "listen": "0.0.0.0",
      "listen_port": 7890,
      "sniff": true,
      "sniff_override_destination": true,
      "set_system_proxy": false
    },
    {
      "type": "tun",
      "tag": "tun-in",
      "interface_name": "tun0",
      "inet4_address": "172.19.0.1/30",
      "inet6_address": "fdfe:dcba:9876::1/126",
      "mtu": 9000,
      "auto_route": true,
      "strict_route": true,
      "sniff": true,
      "sniff_override_destination": true,
      "endpoint_independent_nat": false,
      "stack": "system",
      "platform": {
        "http_proxy": {
          "enabled": true,
          "server": "127.0.0.1",
          "server_port": 7890
        }
      }
    }
  ],
  "outbounds": [
    {
      "type": "selector",
      "tag": "proxy",
      "outbounds": [
        "auto",
        "direct"
      ],
      "default": "auto"
    },
    {
      "type": "urltest",
      "tag": "auto",
      "outbounds": [],
      "url": "http://www.gstatic.com/generate_204",
      "interval": "10m",
      "tolerance": 50
    },
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "dns",
      "tag": "dns-out"
    },
    {
      "type": "block",
      "tag": "block"
    }
  ],
  "route": {
    "auto_detect_interface": true,
    "final": "proxy",
    "rules": [
      {
        "protocol": "dns",
        "outbound": "dns-out"
      },
      {
        "clash_mode": "direct",
        "outbound": "direct"
      },
      {
        "clash_mode": "global",
        "outbound": "proxy"
      },
      {
        "rule_set": "geosite-cn",
        "outbound": "direct"
      },
      {
        "rule_set": "geoip-cn",
        "outbound": "direct"
      },
      {
        "ip_is_private": true,
        "outbound": "direct"
      }
    ],
    "rule_set": [
      {
        "tag": "geosite-cn",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-cn.srs",
        "download_detour": "direct"
      },
      {
        "tag": "geoip-cn",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs",
        "download_detour": "direct"
      }
    ]
  }
}
EOF

    chown sing-box:sing-box /etc/sing-box/config.json
    chmod 600 /etc/sing-box/config.json
    
    # 保存密钥到文件
    echo "$SECRET_KEY" > /etc/sing-box/secret.key
    chmod 600 /etc/sing-box/secret.key
    
    log_info "配置文件创建完成，API密钥: $SECRET_KEY"
}

# 创建systemd服务
create_systemd_service() {
    log_info "创建systemd服务..."
    
    cat > /etc/systemd/system/sing-box.service << 'EOF'
[Unit]
Description=sing-box service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target

[Service]
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_SYS_PTRACE CAP_DAC_READ_SEARCH
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_SYS_PTRACE CAP_DAC_READ_SEARCH
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=10s
LimitNOFILE=infinity
User=sing-box
Group=sing-box

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable sing-box
}

# 部署zashboard面板
deploy_zashboard() {
    log_info "部署zashboard面板..."
    
    # 创建目录
    mkdir -p /var/www/zashboard
    cd /tmp
    
    # 下载最新版本的zashboard
    log_info "下载zashboard最新版本..."
    LATEST_RELEASE=$(safe_curl "https://api.github.com/repos/xzq849/zashboard/releases/latest" | jq -r '.assets[] | select(.name | contains("dist.zip")) | .browser_download_url')
    
    if [ -n "$LATEST_RELEASE" ]; then
        wget -O zashboard-dist.zip "$LATEST_RELEASE"
        unzip -o zashboard-dist.zip -d /var/www/zashboard/
    else
        log_warn "无法获取预编译版本，从源码构建..."
        git clone https://github.com/xzq849/zashboard.git /tmp/zashboard-src
        cd /tmp/zashboard-src
        npm install
        npm run build
        cp -r dist/* /var/www/zashboard/
    fi
    
    # 设置权限
    chown -R www-data:www-data /var/www/zashboard
    chmod -R 755 /var/www/zashboard
    
    log_info "zashboard 部署完成"
}

# 配置nginx
configure_nginx() {
    log_info "配置nginx..."
    
    cat > /etc/nginx/sites-available/zashboard << 'EOF'
server {
    listen 80;
    server_name _;
    
    # zashboard 面板
    location / {
        root /var/www/zashboard;
        index index.html;
        try_files $uri $uri/ /index.html;
        
        # 添加安全头
        add_header X-Frame-Options DENY;
        add_header X-Content-Type-Options nosniff;
        add_header X-XSS-Protection "1; mode=block";
    }
    
    # Clash API 代理
    location /api/ {
        proxy_pass http://127.0.0.1:9090/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # WebSocket 支持
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # 超时设置
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
    
    # 静态资源缓存
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ {
        root /var/www/zashboard;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
EOF

    # 启用站点
    ln -sf /etc/nginx/sites-available/zashboard /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    
    # 测试配置
    nginx -t
    systemctl enable nginx
    systemctl restart nginx
    
    log_info "nginx 配置完成"
}

# 配置防火墙
configure_firewall() {
    log_info "配置防火墙..."
    
    if command -v ufw &> /dev/null; then
        ufw --force enable
        ufw allow 22/tcp
        ufw allow 80/tcp
        ufw allow 7890/tcp
        ufw allow 9090/tcp
        log_info "UFW 防火墙规则已添加"
    elif command -v firewall-cmd &> /dev/null; then
        systemctl enable firewalld
        systemctl start firewalld
        firewall-cmd --permanent --add-port=22/tcp
        firewall-cmd --permanent --add-port=80/tcp
        firewall-cmd --permanent --add-port=7890/tcp
        firewall-cmd --permanent --add-port=9090/tcp
        firewall-cmd --reload
        log_info "firewalld 防火墙规则已添加"
    else
        log_warn "未检测到防火墙，请手动开放端口 22, 80, 7890, 9090"
    fi
}

# 启动服务
start_services() {
    log_info "启动服务..."
    
    systemctl start sing-box
    systemctl start nginx
    
    # 等待服务启动
    sleep 5
    
    # 检查服务状态
    if systemctl is-active --quiet sing-box; then
        log_info "sing-box 服务启动成功"
    else
        log_error "sing-box 服务启动失败"
        systemctl status sing-box
    fi
    
    if systemctl is-active --quiet nginx; then
        log_info "nginx 服务启动成功"
    else
        log_error "nginx 服务启动失败"
        systemctl status nginx
    fi
}

# 创建管理脚本
create_management_script() {
    log_info "创建管理脚本..."
    
    cat > /usr/local/bin/proxy-manager << 'EOF'
#!/bin/bash

# 代理服务管理脚本

case "$1" in
    start)
        echo "启动代理服务..."
        systemctl start sing-box
        systemctl start nginx
        echo "代理服务已启动"
        ;;
    stop)
        echo "停止代理服务..."
        systemctl stop sing-box
        systemctl stop nginx
        echo "代理服务已停止"
        ;;
    restart)
        echo "重启代理服务..."
        systemctl restart sing-box
        systemctl restart nginx
        echo "代理服务已重启"
        ;;
    status)
        echo "=== sing-box 状态 ==="
        systemctl status sing-box --no-pager
        echo ""
        echo "=== nginx 状态 ==="
        systemctl status nginx --no-pager
        ;;
    logs)
        echo "=== sing-box 日志 ==="
        journalctl -u sing-box -f
        ;;
    config)
        echo "=== 配置信息 ==="
        echo "配置文件: /etc/sing-box/config.json"
        echo "API密钥: $(cat /etc/sing-box/secret.key 2>/dev/null || echo '未找到')"
        echo "面板地址: http://$(hostname -I | awk '{print $1}')"
        echo "API地址: http://$(hostname -I | awk '{print $1}'):9090"
        echo "代理端口: 7890"
        ;;
    update-ui)
        echo "更新面板..."
        cd /tmp
        wget -O zashboard-dist.zip "https://github.com/xzq849/zashboard/releases/latest/download/dist.zip"
        unzip -o zashboard-dist.zip -d /var/www/zashboard/
        chown -R www-data:www-data /var/www/zashboard
        echo "面板更新完成"
        ;;
    sub)
        shift
        /usr/local/bin/subscription-manager "$@"
        ;;
    *)
        echo "用法: $0 {start|stop|restart|status|logs|config|update-ui|sub}"
        echo ""
        echo "订阅管理:"
        echo "  $0 sub add <订阅链接> <订阅名称>     # 添加机场订阅"
        echo "  $0 sub list                         # 列出所有订阅"
        echo "  $0 sub apply <订阅名称>             # 应用订阅"
        echo "  $0 sub remove <订阅名称>            # 删除订阅"
        exit 1
        ;;
esac
EOF

    chmod +x /usr/local/bin/proxy-manager
    
    # 复制订阅管理脚本
    if [ -f "./subscription_manager.sh" ]; then
        cp ./subscription_manager.sh /usr/local/bin/subscription-manager
        chmod +x /usr/local/bin/subscription-manager
        log_info "订阅管理脚本已安装"
    fi
    
    log_info "管理脚本创建完成: /usr/local/bin/proxy-manager"
}

# 显示安装结果
show_result() {
    local server_ip=$(hostname -I | awk '{print $1}')
    local secret_key=$(cat /etc/sing-box/secret.key 2>/dev/null || echo '未找到')
    
    echo -e "${GREEN}"
    echo "=================================================="
    echo "           安装完成！"
    echo "=================================================="
    echo -e "${NC}"
    echo "面板地址: http://$server_ip"
    echo "API地址: http://$server_ip:9090"
    echo "API密钥: $secret_key"
    echo "代理端口: 7890 (HTTP/SOCKS5)"
    echo ""
    echo "管理命令:"
    echo "  proxy-manager start    # 启动服务"
    echo "  proxy-manager stop     # 停止服务"
    echo "  proxy-manager restart  # 重启服务"
    echo "  proxy-manager status   # 查看状态"
    echo "  proxy-manager logs     # 查看日志"
    echo "  proxy-manager config   # 查看配置"
    echo "  proxy-manager update-ui # 更新面板"
    echo ""
    echo "配置文件: /etc/sing-box/config.json"
    echo "日志文件: /var/log/sing-box/sing-box.log"
    echo ""
    echo -e "${YELLOW}注意: 请在面板中添加代理节点后使用${NC}"
}

# 主函数
main() {
    display_banner
    check_root
    check_system
    check_connectivity
    check_dependencies "curl" "wget" "unzip" "jq" "git" "nodejs" "npm" "nginx"
    detect_arch
    install_singbox
    create_singbox_user
    create_singbox_config
    create_systemd_service
    deploy_zashboard
    configure_nginx
    configure_firewall
    start_services
    create_management_script
    show_result
}

main "$@"