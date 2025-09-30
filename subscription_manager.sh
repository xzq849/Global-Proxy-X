#!/bin/bash
set -euo pipefail

# Airport订阅管理脚本
# 用于管理sing-box的机场订阅配置

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

# 配置文件路径（从config.env加载）
CONFIG_DIR="${SING_BOX_CONFIG_DIR:-/etc/sing-box}"
CONFIG_FILE="${SING_BOX_CONFIG_FILE:-$CONFIG_DIR/config.json}"
BACKUP_FILE="$CONFIG_DIR/config.json.backup"
SUBSCRIPTION_DIR="${SUBSCRIPTION_DIR:-$CONFIG_DIR/subscriptions}"
LOG_FILE="${LOG_DIR:-/var/log/sing-box}/subscription.log"

# 创建必要目录
mkdir -p "$SUBSCRIPTION_DIR" "$(dirname "$LOG_FILE")"

# 创建订阅目录
create_subscription_dir() {
    mkdir -p "$SUBSCRIPTION_DIR"
    if command -v chown &> /dev/null && id -u sing-box &> /dev/null; then
        chown -R sing-box:sing-box "$SUBSCRIPTION_DIR"
    fi
}

# 备份配置文件
backup_config() {
    if [ -f "$CONFIG_FILE" ]; then
        cp "$CONFIG_FILE" "$BACKUP_FILE.$(date +%Y%m%d_%H%M%S)"
        log_info "配置文件已备份"
    fi
}

# Base64 解码函数
safe_base64_decode() {
    local input="$1"
    # 添加必要的填充
    local padding=$((4 - ${#input} % 4))
    if [ $padding -ne 4 ]; then
        input="${input}$(printf '=%.0s' $(seq 1 $padding))"
    fi
    echo "$input" | base64 -d 2>/dev/null || echo ""
}

# 解析VMess链接
parse_vmess() {
    local vmess_url="$1"
    local vmess_data=$(echo "$vmess_url" | sed 's/vmess:\/\///' | safe_base64_decode)
    
    if [ -z "$vmess_data" ]; then
        log_error "无法解析VMess链接"
        return 1
    fi
    
    # 解析JSON数据
    local ps=$(echo "$vmess_data" | jq -r '.ps // .remark // "Unknown"' 2>/dev/null)
    local add=$(echo "$vmess_data" | jq -r '.add // .address' 2>/dev/null)
    local port=$(echo "$vmess_data" | jq -r '.port' 2>/dev/null)
    local id=$(echo "$vmess_data" | jq -r '.id // .uuid' 2>/dev/null)
    local aid=$(echo "$vmess_data" | jq -r '.aid // .alterId // 0' 2>/dev/null)
    local net=$(echo "$vmess_data" | jq -r '.net // .network // "tcp"' 2>/dev/null)
    local type=$(echo "$vmess_data" | jq -r '.type // "none"' 2>/dev/null)
    local host=$(echo "$vmess_data" | jq -r '.host // ""' 2>/dev/null)
    local path=$(echo "$vmess_data" | jq -r '.path // "/"' 2>/dev/null)
    local tls=$(echo "$vmess_data" | jq -r '.tls // ""' 2>/dev/null)
    local sni=$(echo "$vmess_data" | jq -r '.sni // ""' 2>/dev/null)
    
    # 生成sing-box配置
    local vmess_config=$(cat << EOF
{
  "type": "vmess",
  "tag": "$ps",
  "server": "$add",
  "server_port": $port,
  "uuid": "$id",
  "alter_id": $aid,
  "security": "auto"
EOF

    # 添加传输层配置
    if [ "$net" = "ws" ]; then
        vmess_config+=',
  "transport": {
    "type": "ws",
    "path": "'$path'"'
        if [ -n "$host" ]; then
            vmess_config+=',
    "headers": {
      "Host": "'$host'"
    }'
        fi
        vmess_config+='
  }'
    elif [ "$net" = "grpc" ]; then
        vmess_config+=',
  "transport": {
    "type": "grpc",
    "service_name": "'$path'"
  }'
    fi
    
    # 添加TLS配置
    if [ "$tls" = "tls" ]; then
        vmess_config+=',
  "tls": {
    "enabled": true'
        if [ -n "$sni" ]; then
            vmess_config+=',
    "server_name": "'$sni'"'
        elif [ -n "$host" ]; then
            vmess_config+=',
    "server_name": "'$host'"'
        fi
        vmess_config+=',
    "insecure": false
  }'
    fi
    
    vmess_config+='
}'
    
    echo "$vmess_config"
}

# 解析Shadowsocks链接
parse_shadowsocks() {
    local ss_url="$1"
    local ss_data=$(echo "$ss_url" | sed 's/ss:\/\///')
    
    # 分离用户信息和服务器信息
    local userinfo=$(echo "$ss_data" | cut -d'@' -f1)
    local serverinfo=$(echo "$ss_data" | cut -d'@' -f2)
    
    # 解码用户信息
    local decoded_userinfo=$(echo "$userinfo" | safe_base64_decode)
    local method=$(echo "$decoded_userinfo" | cut -d':' -f1)
    local password=$(echo "$decoded_userinfo" | cut -d':' -f2-)
    
    # 解析服务器信息
    local server=$(echo "$serverinfo" | cut -d':' -f1)
    local port_and_name=$(echo "$serverinfo" | cut -d':' -f2-)
    local port=$(echo "$port_and_name" | cut -d'#' -f1)
    local name=$(echo "$port_and_name" | cut -d'#' -f2- | sed 's/%20/ /g')
    
    if [ -z "$name" ]; then
        name="SS-$server:$port"
    fi
    
    # 生成sing-box配置
    cat << EOF
{
  "type": "shadowsocks",
  "tag": "$name",
  "server": "$server",
  "server_port": $port,
  "password": "$password",
  "method": "$method"
}
EOF
}

# 解析Trojan链接
parse_trojan() {
    local trojan_url="$1"
    local trojan_data=$(echo "$trojan_url" | sed 's/trojan:\/\///')
    
    # 分离密码和服务器信息
    local password=$(echo "$trojan_data" | cut -d'@' -f1)
    local serverinfo=$(echo "$trojan_data" | cut -d'@' -f2)
    
    # 解析服务器信息
    local server=$(echo "$serverinfo" | cut -d':' -f1)
    local port_and_params=$(echo "$serverinfo" | cut -d':' -f2-)
    local port=$(echo "$port_and_params" | cut -d'?' -f1 | cut -d'#' -f1)
    local name=$(echo "$serverinfo" | cut -d'#' -f2- | sed 's/%20/ /g')
    
    if [ -z "$name" ]; then
        name="Trojan-$server:$port"
    fi
    
    # 生成sing-box配置
    cat << EOF
{
  "type": "trojan",
  "tag": "$name",
  "server": "$server",
  "server_port": $port,
  "password": "$password",
  "tls": {
    "enabled": true,
    "server_name": "$server",
    "insecure": false
  }
}
EOF
}

# 下载并解析订阅
download_subscription() {
    local sub_url="$1"
    local sub_name="$2"
    local url_file="$SUBSCRIPTION_DIR/${sub_name}.url"
    
    log_info "下载订阅: $sub_name"
    
    # 保存订阅URL
    echo "$sub_url" > "$url_file"
    
    # 下载订阅内容
    local sub_content=$(safe_curl "$sub_url")
    
    if [ -z "$sub_content" ]; then
        log_error "无法下载订阅内容"
        return 1
    fi
    
    # 尝试Base64解码
    local decoded_content=$(echo "$sub_content" | safe_base64_decode)
    if [ -n "$decoded_content" ]; then
        sub_content="$decoded_content"
    fi
    
    # 保存原始订阅内容
    echo "$sub_content" > "$SUBSCRIPTION_DIR/${sub_name}.txt"
    
    # 解析节点
    local nodes_config="[]"
    local node_count=0
    
    while IFS= read -r line; do
        if [ -z "$line" ]; then
            continue
        fi
        
        local node_config=""
        
        if [[ $line == vmess://* ]]; then
            node_config=$(parse_vmess "$line")
        elif [[ $line == ss://* ]]; then
            node_config=$(parse_shadowsocks "$line")
        elif [[ $line == trojan://* ]]; then
            node_config=$(parse_trojan "$line")
        else
            continue
        fi
        
        if [ -n "$node_config" ]; then
            if [ "$nodes_config" = "[]" ]; then
                nodes_config="[$node_config]"
            else
                nodes_config=$(echo "$nodes_config" | jq --argjson node "$node_config" '. += [$node]')
            fi
            node_count=$((node_count + 1))
        fi
    done <<< "$sub_content"
    
    # 保存解析后的配置
    echo "$nodes_config" > "$SUBSCRIPTION_DIR/${sub_name}.json"
    
    log_info "解析完成，共 $node_count 个节点"
    return 0
}

# 更新指定订阅
update_subscription() {
    local sub_name="$1"
    local url_file="$SUBSCRIPTION_DIR/${sub_name}.url"
    
    if [ ! -f "$url_file" ]; then
        log_error "订阅不存在或缺少URL文件: $sub_name"
        return 1
    fi
    
    local url=$(cat "$url_file")
    log_info "更新订阅: $sub_name"
    
    if download_subscription "$url" "$sub_name"; then
        echo -e "${GREEN}✓ 订阅更新成功: $sub_name${NC}"
        return 0
    else
        echo -e "${RED}✗ 订阅更新失败: $sub_name${NC}"
        return 1
    fi
}

# 更新sing-box配置
update_singbox_config() {
    local sub_name="$1"
    local nodes_file="$SUBSCRIPTION_DIR/${sub_name}.json"
    
    if [ ! -f "$nodes_file" ]; then
        log_error "节点配置文件不存在: $nodes_file"
        return 1
    fi
    
    log_info "更新sing-box配置..."
    
    # 备份当前配置
    backup_config
    
    # 读取节点配置
    local nodes=$(cat "$nodes_file")
    
    # 清除旧的代理节点（保留direct、dns-out、block等系统节点）
    jq '.outbounds = [.outbounds[] | select(.tag == "proxy" or .tag == "auto" or .tag == "direct" or .tag == "dns-out" or .tag == "block")]' "$CONFIG_FILE" > /tmp/config_temp.json
    mv /tmp/config_temp.json "$CONFIG_FILE"
    
    # 添加新节点
    local node_tags="[]"
    echo "$nodes" | jq -c '.[]' | while read -r node; do
        local tag=$(echo "$node" | jq -r '.tag')
        
        # 添加节点到outbounds
        jq --argjson node "$node" '.outbounds += [$node]' "$CONFIG_FILE" > /tmp/config_temp.json
        mv /tmp/config_temp.json "$CONFIG_FILE"
        
        # 收集节点标签
        node_tags=$(echo "$node_tags" | jq --arg tag "$tag" '. += [$tag]')
    done
    
    # 更新proxy选择器的outbounds
    local final_tags=$(echo "$node_tags" | jq -r '.[]' | tr '\n' ',' | sed 's/,$//')
    if [ -n "$final_tags" ]; then
        # 添加auto和direct到选择器
        jq --argjson tags "$(echo "[\"auto\", \"direct\"] + $node_tags")" '.outbounds[] |= if .tag == "proxy" then .outbounds = $tags else . end' "$CONFIG_FILE" > /tmp/config_temp.json
        mv /tmp/config_temp.json "$CONFIG_FILE"
        
        # 更新auto组的outbounds
        jq --argjson tags "$node_tags" '.outbounds[] |= if .tag == "auto" then .outbounds = $tags else . end' "$CONFIG_FILE" > /tmp/config_temp.json
        mv /tmp/config_temp.json "$CONFIG_FILE"
    fi
    
    log_info "配置更新完成"
}

# 列出订阅
list_subscriptions() {
    log_info "已保存的订阅:"
    
    if [ ! -d "$SUBSCRIPTION_DIR" ]; then
        log_warn "订阅目录不存在"
        return
    fi
    
    for file in "$SUBSCRIPTION_DIR"/*.json; do
        if [ -f "$file" ]; then
            local sub_name=$(basename "$file" .json)
            local node_count=$(jq length "$file" 2>/dev/null || echo "0")
            echo "  - $sub_name ($node_count 个节点)"
        fi
    done
}

# 删除订阅
remove_subscription() {
    local sub_name="$1"
    
    log_info "删除订阅: $sub_name"
    
    rm -f "$SUBSCRIPTION_DIR/${sub_name}.txt"
    rm -f "$SUBSCRIPTION_DIR/${sub_name}.json"
    
    log_info "订阅已删除"
}

# 重启服务
restart_service() {
    log_info "重启sing-box服务..."
    systemctl restart sing-box
    
    # 等待服务启动
    sleep 3
    
    if systemctl is-active --quiet sing-box; then
        log_info "服务重启成功"
    else
        log_error "服务重启失败"
        systemctl status sing-box
        return 1
    fi
}

# 测试配置
test_config() {
    log_info "测试配置文件..."
    
    if /usr/local/bin/sing-box check -c "$CONFIG_FILE"; then
        log_info "配置文件语法正确"
        return 0
    else
        log_error "配置文件语法错误"
        return 1
    fi
}

# 更新所有订阅
update_all_subscriptions() {
    log_info "开始更新所有订阅..."
    
    local updated=0
    local failed=0
    
    for sub_file in "$SUBSCRIPTION_DIR"/*.txt; do
        if [ -f "$sub_file" ]; then
            local sub_name=$(basename "$sub_file" .txt)
            local url_file="$SUBSCRIPTION_DIR/${sub_name}.url"
            
            if [ -f "$url_file" ]; then
                local url=$(cat "$url_file")
                echo -e "${BLUE}更新订阅: $sub_name${NC}"
                
                if download_subscription "$url" "$sub_name"; then
                    echo -e "${GREEN}✓ $sub_name 更新成功${NC}"
                    ((updated++))
                else
                    echo -e "${RED}✗ $sub_name 更新失败${NC}"
                    ((failed++))
                fi
            else
                echo -e "${YELLOW}⚠ $sub_name 缺少URL文件，跳过${NC}"
            fi
        fi
    done
    
    echo ""
    echo -e "${GREEN}更新完成: $updated 个成功, $failed 个失败${NC}"
}

# 测试指定订阅
test_subscription() {
    local sub_name="$1"
    local sub_file="$SUBSCRIPTION_DIR/${sub_name}.txt"
    
    if [ ! -f "$sub_file" ]; then
        log_error "订阅不存在: $sub_name"
        return 1
    fi
    
    echo -e "${BLUE}测试订阅: $sub_name${NC}"
    
    # 解析节点数量
    local node_count=$(parse_subscription "$sub_file" | jq length 2>/dev/null || echo "0")
    echo "节点数量: $node_count"
    
    # 检查节点格式
    if [ "$node_count" -gt 0 ]; then
        echo -e "${GREEN}✓ 订阅格式正确${NC}"
        return 0
    else
        echo -e "${RED}✗ 订阅格式错误或无有效节点${NC}"
        return 1
    fi
}

# 显示状态信息
show_status() {
    echo -e "${BLUE}=== 订阅管理状态 ===${NC}"
    echo ""
    
    # 显示订阅数量
    local sub_count=$(ls "$SUBSCRIPTION_DIR"/*.txt 2>/dev/null | wc -l)
    echo "订阅数量: $sub_count"
    
    # 显示配置文件状态
    if [ -f "$SING_BOX_CONFIG" ]; then
        echo -e "${GREEN}✓ 配置文件存在${NC}"
        
        # 显示节点数量
        local node_count=$(jq '.outbounds | map(select(.type != "direct" and .type != "dns" and .type != "block" and .type != "selector" and .type != "urltest")) | length' "$SING_BOX_CONFIG" 2>/dev/null || echo "0")
        echo "配置中的节点数量: $node_count"
    else
        echo -e "${RED}✗ 配置文件不存在${NC}"
    fi
    
    # 显示服务状态
    if systemctl is-active --quiet sing-box; then
        echo -e "${GREEN}✓ sing-box 服务运行中${NC}"
    else
        echo -e "${RED}✗ sing-box 服务未运行${NC}"
    fi
    
    # 显示备份数量
    local backup_count=$(ls "$BACKUP_DIR"/*.bak 2>/dev/null | wc -l)
    echo "配置备份数量: $backup_count"
}

# 清理旧备份
clean_old_backups() {
    log_info "清理旧备份文件..."
    
    # 保留最近10个备份
    local backup_files=($(ls -t "$BACKUP_DIR"/*.bak 2>/dev/null))
    local keep_count=10
    
    if [ ${#backup_files[@]} -gt $keep_count ]; then
        local delete_count=$((${#backup_files[@]} - $keep_count))
        echo "发现 ${#backup_files[@]} 个备份文件，将删除最旧的 $delete_count 个"
        
        for ((i=$keep_count; i<${#backup_files[@]}; i++)); do
            rm -f "${backup_files[$i]}"
            echo "已删除: $(basename "${backup_files[$i]}")"
        done
        
        echo -e "${GREEN}清理完成${NC}"
    else
        echo "备份文件数量正常，无需清理"
    fi
}

# 显示帮助信息
show_help() {
    echo -e "${BLUE}机场订阅管理工具${NC}"
    echo ""
    echo "用法: $0 <命令> [参数]"
    echo ""
    echo "命令:"
    echo "  add <订阅链接> <订阅名称>    添加新的机场订阅"
    echo "  update <订阅名称>           更新指定订阅"
    echo "  update-all                  更新所有订阅"
    echo "  list                        列出所有订阅"
    echo "  remove <订阅名称>           删除指定订阅"
    echo "  apply <订阅名称>            应用订阅到配置文件"
    echo "  test [订阅名称]             测试配置文件或指定订阅"
    echo "  status                      显示状态信息"
    echo "  clean                       清理旧备份文件"
    echo ""
    echo "示例:"
    echo "  $0 add 'https://example.com/sub' 'MyAirport'"
    echo "  $0 apply 'MyAirport'"
    echo "  $0 update-all"
    echo "  $0 list"
}

# 主函数
main() {
    display_banner
    # 检查依赖
    check_dependencies "jq" "curl"

    # 解析命令行参数
    if [[ $# -eq 0 ]]; then
        log_error "参数错误"
        show_help
        exit 1
    fi
    download_subscription "$2" "$3"
    ;;
    update)
        if [ -z "$2" ]; then
            echo "用法: $0 update <订阅名称>"
            exit 1
        fi
        update_subscription "$2"
        ;;
        update-all)
            update_all_subscriptions
            ;;
        list)
            list_subscriptions
            ;;
        remove)
            if [ -z "$2" ]; then
                echo "用法: $0 remove <订阅名称>"
                exit 1
            fi
            remove_subscription "$2"
            ;;
        test)
            if [ -z "$2" ]; then
                test_configuration
            else
                test_subscription "$2"
            fi
            ;;
        apply)
            if [ -z "$2" ]; then
                echo "用法: $0 apply <订阅名称>"
                exit 1
            fi
            apply_subscription "$2"
            ;;
        status)
            show_status
            ;;
        clean)
            clean_old_backups
            ;;
        *)
            show_help
            exit 1
            ;;
    esac
}

main "$@"