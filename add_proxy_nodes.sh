#!/bin/bash
set -euo pipefail

# 代理节点配置脚本
# 支持VMess、Shadowsocks、Trojan节点添加和订阅导入

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
check_dependencies "jq" "curl" "base64"

# 节点配置
NODES_CONFIG_FILE="${SCRIPT_DIR}/nodes.conf"

# 验证输入参数
validate_input() {
    local param_name="$1"
    local param_value="$2"
    local param_type="${3:-string}"
    
    if [[ -z "$param_value" ]]; then
        log_error "参数 $param_name 不能为空"
        return 1
    fi
    
    case "$param_type" in
        "port")
            if ! [[ "$param_value" =~ ^[0-9]+$ ]] || [[ "$param_value" -lt 1 ]] || [[ "$param_value" -gt 65535 ]]; then
                log_error "端口 $param_value 无效，必须是1-65535之间的数字"
                return 1
            fi
            ;;
        "uuid")
            if ! [[ "$param_value" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
                log_error "UUID格式无效: $param_value"
                return 1
            fi
            ;;
        "url")
            if ! [[ "$param_value" =~ ^https?:// ]]; then
                log_error "URL格式无效: $param_value"
                return 1
            fi
            ;;
    esac
    
    return 0
}

# 备份配置文件
backup_config() {
    local backup_file="${BACKUP_DIR}/config_$(date +%Y%m%d_%H%M%S).json"
    
    if [[ -f "$SING_BOX_CONFIG_FILE" ]]; then
        mkdir -p "$BACKUP_DIR"
        if cp "$SING_BOX_CONFIG_FILE" "$backup_file"; then
            log_success "配置文件已备份到: $backup_file"
        else
            log_error "配置文件备份失败"
            return 1
        fi
    else
        log_warn "配置文件不存在，跳过备份"
    fi
}

# 验证配置文件
validate_config() {
    if [[ ! -f "$SING_BOX_CONFIG_FILE" ]]; then
        log_error "Sing-box配置文件不存在: $SING_BOX_CONFIG_FILE"
        return 1
    fi
    
    if ! jq empty "$SING_BOX_CONFIG_FILE" 2>/dev/null; then
        log_error "配置文件JSON格式无效"
        return 1
    fi
    
    return 0
}

# 添加VMess节点
add_vmess_node() {
    local name="$1"
    local server="$2"
    local port="$3"
    local uuid="$4"
    local alterId="$5"
    local security="${6:-auto}"
    local network="${7:-ws}"
    local path="${8:-/}"
    
    log_info "添加VMess节点: $name"
    
    # 验证输入参数
    validate_input "节点名称" "$name" || return 1
    validate_input "服务器地址" "$server" || return 1
    validate_input "端口" "$port" "port" || return 1
    validate_input "UUID" "$uuid" "uuid" || return 1
    
    # 检查节点是否已存在
    if jq -e --arg tag "$name" '.outbounds[] | select(.tag == $tag)' "$SING_BOX_CONFIG_FILE" >/dev/null 2>&1; then
        log_error "节点 $name 已存在"
        return 1
    fi
    
    # 创建VMess节点配置
    local vmess_config
    vmess_config=$(jq -n \
        --arg type "vmess" \
        --arg tag "$name" \
        --arg server "$server" \
        --argjson port "$port" \
        --arg uuid "$uuid" \
        --argjson alter_id "$alterId" \
        --arg security "$security" \
        --arg network "$network" \
        --arg path "$path" \
        '{
            type: $type,
            tag: $tag,
            server: $server,
            server_port: $port,
            uuid: $uuid,
            alter_id: $alter_id,
            security: $security,
            transport: {
                type: $network,
                path: $path,
                headers: {
                    Host: $server
                }
            }
        }')
    
    # 使用临时文件安全地更新配置
    local temp_file
    temp_file=$(mktemp)
    
    if jq --argjson node "$vmess_config" '.outbounds += [$node]' "$SING_BOX_CONFIG_FILE" > "$temp_file"; then
        mv "$temp_file" "$SING_BOX_CONFIG_FILE"
        log_success "VMess节点 $name 添加成功"
    else
        log_error "添加VMess节点失败"
        rm -f "$temp_file"
        return 1
    fi
    
    # 添加到选择器组
    add_to_selector_group "$name"
}

# 添加节点到选择器组
add_to_selector_group() {
    local node_tag="$1"
    local temp_file
    temp_file=$(mktemp)
    
    # 添加到proxy选择器组
    if jq --arg tag "$node_tag" '
        (.outbounds[] | select(.tag == "proxy") | .outbounds) += [$tag]
    ' "$SING_BOX_CONFIG_FILE" > "$temp_file" 2>/dev/null; then
        mv "$temp_file" "$SING_BOX_CONFIG_FILE"
        log_debug "节点 $node_tag 已添加到proxy选择器组"
    else
        log_warn "添加节点到proxy选择器组失败，可能选择器组不存在"
        rm -f "$temp_file"
    fi
    
    # 添加到auto自动测试组
    temp_file=$(mktemp)
    if jq --arg tag "$node_tag" '
        (.outbounds[] | select(.tag == "auto") | .outbounds) += [$tag]
    ' "$SING_BOX_CONFIG_FILE" > "$temp_file" 2>/dev/null; then
        mv "$temp_file" "$SING_BOX_CONFIG_FILE"
        log_debug "节点 $node_tag 已添加到auto测试组"
    else
        log_warn "添加节点到auto测试组失败，可能测试组不存在"
        rm -f "$temp_file"
    fi
}

# 添加Shadowsocks节点
add_shadowsocks_node() {
    local name="$1"
    local server="$2"
    local port="$3"
    local password="$4"
    local method="$5"
    
    log_info "添加Shadowsocks节点: $name"
    
    # 验证输入参数
    validate_input "节点名称" "$name" || return 1
    validate_input "服务器地址" "$server" || return 1
    validate_input "端口" "$port" "port" || return 1
    validate_input "密码" "$password" || return 1
    validate_input "加密方法" "$method" || return 1
    
    # 检查节点是否已存在
    if jq -e --arg tag "$name" '.outbounds[] | select(.tag == $tag)' "$SING_BOX_CONFIG_FILE" >/dev/null 2>&1; then
        log_error "节点 $name 已存在"
        return 1
    fi
    
    # 创建Shadowsocks节点配置
    local ss_config
    ss_config=$(jq -n \
        --arg type "shadowsocks" \
        --arg tag "$name" \
        --arg server "$server" \
        --argjson port "$port" \
        --arg password "$password" \
        --arg method "$method" \
        '{
            type: $type,
            tag: $tag,
            server: $server,
            server_port: $port,
            password: $password,
            method: $method
        }')
    
    # 使用临时文件安全地更新配置
    local temp_file
    temp_file=$(mktemp)
    
    if jq --argjson node "$ss_config" '.outbounds += [$node]' "$SING_BOX_CONFIG_FILE" > "$temp_file"; then
        mv "$temp_file" "$SING_BOX_CONFIG_FILE"
        log_success "Shadowsocks节点 $name 添加成功"
    else
        log_error "添加Shadowsocks节点失败"
        rm -f "$temp_file"
        return 1
    fi
    
    # 添加到选择器组
    add_to_selector_group "$name"
}

# 添加Trojan节点
add_trojan_node() {
    local name="$1"
    local server="$2"
    local port="$3"
    local password="$4"
    local sni="${5:-$server}"
    local insecure="${6:-false}"
    
    log_info "添加Trojan节点: $name"
    
    # 验证输入参数
    validate_input "节点名称" "$name" || return 1
    validate_input "服务器地址" "$server" || return 1
    validate_input "端口" "$port" "port" || return 1
    validate_input "密码" "$password" || return 1
    
    # 检查节点是否已存在
    if jq -e --arg tag "$name" '.outbounds[] | select(.tag == $tag)' "$SING_BOX_CONFIG_FILE" >/dev/null 2>&1; then
        log_error "节点 $name 已存在"
        return 1
    fi
    
    # 创建Trojan节点配置
    local trojan_config
    trojan_config=$(jq -n \
        --arg type "trojan" \
        --arg tag "$name" \
        --arg server "$server" \
        --argjson port "$port" \
        --arg password "$password" \
        --arg sni "$sni" \
        --argjson insecure "$insecure" \
        '{
            type: $type,
            tag: $tag,
            server: $server,
            server_port: $port,
            password: $password,
            tls: {
                enabled: true,
                server_name: $sni,
                insecure: $insecure
            }
        }')
    
    # 使用临时文件安全地更新配置
    local temp_file
    temp_file=$(mktemp)
    
    if jq --argjson node "$trojan_config" '.outbounds += [$node]' "$SING_BOX_CONFIG_FILE" > "$temp_file"; then
        mv "$temp_file" "$SING_BOX_CONFIG_FILE"
        log_success "Trojan节点 $name 添加成功"
    else
        log_error "添加Trojan节点失败"
        rm -f "$temp_file"
        return 1
    fi
    
    # 添加到选择器组
    add_to_selector_group "$name"
}

# 解析VMess链接
parse_vmess_link() {
    local vmess_link="$1"
    local prefix_removed="${vmess_link#vmess://}"
    local decoded
    
    if ! decoded=$(echo "$prefix_removed" | base64 -d 2>/dev/null); then
        log_error "VMess链接解码失败"
        return 1
    fi
    
    # 解析JSON配置
    local name server port uuid aid net path host tls
    name=$(echo "$decoded" | jq -r '.ps // .add // "Unknown"' 2>/dev/null)
    server=$(echo "$decoded" | jq -r '.add // ""' 2>/dev/null)
    port=$(echo "$decoded" | jq -r '.port // ""' 2>/dev/null)
    uuid=$(echo "$decoded" | jq -r '.id // ""' 2>/dev/null)
    aid=$(echo "$decoded" | jq -r '.aid // 0' 2>/dev/null)
    net=$(echo "$decoded" | jq -r '.net // "ws"' 2>/dev/null)
    path=$(echo "$decoded" | jq -r '.path // "/"' 2>/dev/null)
    host=$(echo "$decoded" | jq -r '.host // ""' 2>/dev/null)
    tls=$(echo "$decoded" | jq -r '.tls // ""' 2>/dev/null)
    
    if [[ -n "$server" && -n "$port" && -n "$uuid" ]]; then
        add_vmess_node "$name" "$server" "$port" "$uuid" "$aid" "auto" "$net" "$path"
    else
        log_error "VMess链接解析失败，缺少必要参数"
        return 1
    fi
}

# 解析Shadowsocks链接
parse_shadowsocks_link() {
    local ss_link="$1"
    local prefix_removed="${ss_link#ss://}"
    local decoded
    
    if ! decoded=$(echo "$prefix_removed" | base64 -d 2>/dev/null); then
        log_error "Shadowsocks链接解码失败"
        return 1
    fi
    
    # 解析格式: method:password@server:port
    if [[ "$decoded" =~ ^([^:]+):([^@]+)@([^:]+):([0-9]+)$ ]]; then
        local method="${BASH_REMATCH[1]}"
        local password="${BASH_REMATCH[2]}"
        local server="${BASH_REMATCH[3]}"
        local port="${BASH_REMATCH[4]}"
        local name="${server}_${port}"
        
        add_shadowsocks_node "$name" "$server" "$port" "$password" "$method"
    else
        log_error "Shadowsocks链接格式无效"
        return 1
    fi
}

# 解析Trojan链接
parse_trojan_link() {
    local trojan_link="$1"
    local prefix_removed="${trojan_link#trojan://}"
    
    # 解析格式: password@server:port
    if [[ "$prefix_removed" =~ ^([^@]+)@([^:]+):([0-9]+) ]]; then
        local password="${BASH_REMATCH[1]}"
        local server="${BASH_REMATCH[2]}"
        local port="${BASH_REMATCH[3]}"
        local name="${server}_${port}"
        
        add_trojan_node "$name" "$server" "$port" "$password"
    else
        log_error "Trojan链接格式无效"
        return 1
    fi
}

# 从订阅链接导入节点
import_subscription() {
    local sub_url="$1"
    local sub_name="$2"
    local temp_file
    
    log_info "从订阅链接导入节点: $sub_name"
    
    # 验证URL
    validate_input "订阅链接" "$sub_url" "url" || return 1
    validate_input "订阅名称" "$sub_name" || return 1
    
    # 下载订阅内容
    temp_file=$(mktemp)
    if ! safe_curl "$sub_url" > "$temp_file"; then
        log_error "下载订阅内容失败"
        rm -f "$temp_file"
        return 1
    fi
    
    # 尝试base64解码
    local sub_content
    if sub_content=$(base64 -d < "$temp_file" 2>/dev/null); then
        echo "$sub_content" > "$temp_file"
    fi
    
    local imported_count=0
    local failed_count=0
    
    # 解析订阅内容
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        
        case "$line" in
            vmess://*)
                if parse_vmess_link "$line"; then
                    ((imported_count++))
                else
                    ((failed_count++))
                fi
                ;;
            ss://*)
                if parse_shadowsocks_link "$line"; then
                    ((imported_count++))
                else
                    ((failed_count++))
                fi
                ;;
            trojan://*)
                if parse_trojan_link "$line"; then
                    ((imported_count++))
                else
                    ((failed_count++))
                fi
                ;;
            *)
                log_debug "跳过未知格式的链接: ${line:0:50}..."
                ;;
        esac
    done < "$temp_file"
    
    rm -f "$temp_file"
    
    log_success "订阅导入完成: 成功 $imported_count 个，失败 $failed_count 个"
    
    # 保存订阅信息
    echo "$sub_name|$sub_url|$(date +%Y-%m-%d)" >> "$NODES_CONFIG_FILE"
}

# 测试节点连接
test_node() {
    local node_name="$1"
    log_info "测试节点连接: $node_name"
    
    # 这里可以添加节点连接测试逻辑
    # 例如使用curl通过代理测试连接
    log_info "节点测试功能待实现"
}

# 列出所有节点
list_nodes() {
    log_info "当前配置的节点列表:"
    
    if [[ ! -f "$SING_BOX_CONFIG_FILE" ]]; then
        log_warn "配置文件不存在"
        return 1
    fi
    
    local nodes
    nodes=$(jq -r '.outbounds[] | select(.type != "direct" and .type != "block" and .type != "dns") | .tag' "$SING_BOX_CONFIG_FILE" 2>/dev/null)
    
    if [[ -z "$nodes" ]]; then
        log_info "未找到任何节点"
    else
        echo "$nodes" | while read -r node; do
            echo "  - $node"
        done
    fi
}

# 删除节点
remove_node() {
    local node_name="$1"
    
    validate_input "节点名称" "$node_name" || return 1
    
    log_info "删除节点: $node_name"
    
    # 检查节点是否存在
    if ! jq -e --arg tag "$node_name" '.outbounds[] | select(.tag == $tag)' "$SING_BOX_CONFIG_FILE" >/dev/null 2>&1; then
        log_error "节点 $node_name 不存在"
        return 1
    fi
    
    # 备份配置
    backup_config || return 1
    
    # 删除节点
    local temp_file
    temp_file=$(mktemp)
    
    if jq --arg tag "$node_name" 'del(.outbounds[] | select(.tag == $tag))' "$SING_BOX_CONFIG_FILE" > "$temp_file"; then
        mv "$temp_file" "$SING_BOX_CONFIG_FILE"
        log_success "节点 $node_name 删除成功"
    else
        log_error "删除节点失败"
        rm -f "$temp_file"
        return 1
    fi
}

# 重启服务
restart_service() {
    log_info "重启sing-box服务..."
    
    if systemctl is-active --quiet sing-box; then
        if systemctl restart sing-box; then
            log_success "服务重启完成"
        else
            log_error "服务重启失败"
            return 1
        fi
    else
        log_warn "sing-box服务未运行，尝试启动..."
        if systemctl start sing-box; then
            log_success "服务启动成功"
        else
            log_error "服务启动失败"
            return 1
        fi
    fi
}

# 显示帮助信息
show_help() {
    display_banner
    echo ""
    echo "代理节点配置脚本 - 支持VMess、Shadowsocks、Trojan节点管理"
    echo ""
    echo "用法:"
    echo "  $0 vmess <名称> <服务器> <端口> <UUID> <alterID> [加密方式] [网络类型] [路径]"
    echo "  $0 shadowsocks <名称> <服务器> <端口> <密码> <加密方式>"
    echo "  $0 trojan <名称> <服务器> <端口> <密码> [SNI] [跳过证书验证]"
    echo "  $0 subscription <订阅链接> <订阅名称>"
    echo "  $0 list                    # 列出所有节点"
    echo "  $0 remove <节点名称>       # 删除指定节点"
    echo "  $0 test <节点名称>         # 测试节点连接"
    echo ""
    echo "示例:"
    echo "  $0 vmess 'US-Node1' 'us.example.com' 443 'uuid-here' 0"
    echo "  $0 shadowsocks 'HK-Node1' 'hk.example.com' 8388 'password' 'aes-256-gcm'"
    echo "  $0 trojan 'JP-Node1' 'jp.example.com' 443 'password'"
    echo "  $0 subscription 'https://example.com/sub' 'My-Subscription'"
    echo "  $0 list"
    echo "  $0 remove 'US-Node1'"
    echo ""
    echo "注意:"
    echo "  - 所有操作需要root权限"
    echo "  - 配置文件会自动备份"
    echo "  - 添加节点后会自动重启服务"
}

# 主函数
main() {
    # 显示横幅
    if [[ "${1:-}" != "list" && "${1:-}" != "test" ]]; then
        display_banner
    fi
    
    # 检查参数
    if [[ $# -lt 1 ]]; then
        show_help
        exit 1
    fi
    
    # 检查root权限（除了帮助和列表功能）
    case "$1" in
        help|--help|-h|list)
            ;;
        *)
            check_root
            ;;
    esac
    
    # 验证配置文件（除了帮助功能）
    case "$1" in
        help|--help|-h)
            ;;
        *)
            validate_config || {
                log_error "配置文件验证失败，请检查sing-box配置"
                exit 1
            }
            ;;
    esac
    
    local operation_requires_restart=false
    
    case "$1" in
        vmess)
            if [[ $# -lt 6 ]]; then
                log_error "VMess节点参数不足，至少需要: 名称 服务器 端口 UUID alterID"
                show_help
                exit 1
            fi
            backup_config || exit 1
            add_vmess_node "$2" "$3" "$4" "$5" "$6" "${7:-auto}" "${8:-ws}" "${9:-/}"
            operation_requires_restart=true
            ;;
        shadowsocks|ss)
            if [[ $# -ne 6 ]]; then
                log_error "Shadowsocks节点参数不正确，需要: 名称 服务器 端口 密码 加密方式"
                show_help
                exit 1
            fi
            backup_config || exit 1
            add_shadowsocks_node "$2" "$3" "$4" "$5" "$6"
            operation_requires_restart=true
            ;;
        trojan)
            if [[ $# -lt 5 ]]; then
                log_error "Trojan节点参数不足，至少需要: 名称 服务器 端口 密码"
                show_help
                exit 1
            fi
            backup_config || exit 1
            add_trojan_node "$2" "$3" "$4" "$5" "${6:-}" "${7:-false}"
            operation_requires_restart=true
            ;;
        subscription|sub)
            if [[ $# -ne 3 ]]; then
                log_error "订阅参数不正确，需要: 订阅链接 订阅名称"
                show_help
                exit 1
            fi
            backup_config || exit 1
            import_subscription "$2" "$3"
            operation_requires_restart=true
            ;;
        list)
            list_nodes
            ;;
        remove|delete|del)
            if [[ $# -ne 2 ]]; then
                log_error "删除节点参数不正确，需要: 节点名称"
                show_help
                exit 1
            fi
            remove_node "$2"
            operation_requires_restart=true
            ;;
        test)
            if [[ $# -ne 2 ]]; then
                log_error "测试节点参数不正确，需要: 节点名称"
                show_help
                exit 1
            fi
            test_node "$2"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "未知的操作: $1"
            show_help
            exit 1
            ;;
    esac
    
    # 重启服务（如果需要）
    if [[ "$operation_requires_restart" == "true" ]]; then
        restart_service
        log_success "操作完成！"
    fi
}

# 执行主函数
main "$@"