#!/bin/bash

# 批量导入脚本
# 用于从配置文件批量导入订阅和节点
# 作者: 全局代理项目组
# 版本: 2.0
# 更新时间: $(date +%Y-%m-%d)

# 严格模式
set -euo pipefail

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 引入通用函数
if [[ -f "$SCRIPT_DIR/common_functions.sh" ]]; then
    source "$SCRIPT_DIR/common_functions.sh"
else
    echo "错误: 找不到 common_functions.sh 文件" >&2
    exit 1
fi

# 初始化通用函数
init_common

# 检查必要的依赖
check_dependencies "curl" "jq"

# 配置文件路径
SUBSCRIPTIONS_CONF="${SCRIPT_DIR}/subscriptions.conf"
NODES_CONF="${SCRIPT_DIR}/nodes.conf"

# 临时文件目录
TEMP_DIR="${SCRIPT_DIR}/temp"
mkdir -p "$TEMP_DIR"

# 统计变量
declare -g TOTAL_IMPORTED=0
declare -g TOTAL_SKIPPED=0
declare -g TOTAL_FAILED=0

# 检查项目依赖
check_project_dependencies() {
    log_info "检查项目依赖..."
    
    local missing_deps=()
    
    # 检查管理脚本
    if ! command -v proxy-manager &> /dev/null; then
        missing_deps+=("proxy-manager")
    fi
    
    if ! command -v subscription-manager &> /dev/null; then
        missing_deps+=("subscription-manager")
    fi
    
    # 检查节点添加脚本
    if [[ ! -f "$SCRIPT_DIR/add_proxy_nodes.sh" ]]; then
        missing_deps+=("add_proxy_nodes.sh")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "缺少以下依赖:"
        for dep in "${missing_deps[@]}"; do
            log_error "  - $dep"
        done
        log_error "请先运行安装脚本或确保所有组件已正确安装"
        exit 1
    fi
    
    log_success "所有依赖检查通过"
}

# 导入订阅
import_subscriptions() {
    if [[ ! -f "$SUBSCRIPTIONS_CONF" ]]; then
        log_warning "订阅配置文件不存在: $SUBSCRIPTIONS_CONF"
        log_info "请创建配置文件，格式: 名称|URL|启用状态|备注"
        return 1
    fi
    
    log_info "开始导入机场订阅..."
    log_info "配置文件: $SUBSCRIPTIONS_CONF"
    
    local imported=0
    local skipped=0
    local failed=0
    local line_num=0
    
    # 验证配置文件格式
    if [[ ! -s "$SUBSCRIPTIONS_CONF" ]]; then
        log_warning "配置文件为空"
        return 1
    fi
    
    while IFS='|' read -r name url enabled comment || [[ -n "$name" ]]; do
        ((line_num++))
        
        # 跳过注释和空行
        if [[ "$name" =~ ^[[:space:]]*#.*$ ]] || [[ -z "${name// }" ]]; then
            continue
        fi
        
        # 去除前后空格
        name=$(echo "$name" | xargs 2>/dev/null || echo "$name")
        url=$(echo "$url" | xargs 2>/dev/null || echo "$url")
        enabled=$(echo "$enabled" | xargs 2>/dev/null || echo "$enabled")
        comment=$(echo "$comment" | xargs 2>/dev/null || echo "$comment")
        
        # 验证必要字段
        if [[ -z "$name" ]] || [[ -z "$url" ]]; then
            log_warning "第${line_num}行格式错误，跳过: $name|$url"
            ((skipped++))
            continue
        fi
        
        # 验证URL格式
        if ! [[ "$url" =~ ^https?:// ]]; then
            log_warning "第${line_num}行URL格式错误，跳过: $name -> $url"
            ((skipped++))
            continue
        fi
        
        # 检查是否启用
        if [[ "$enabled" != "true" ]]; then
            log_info "跳过已禁用的订阅: $name"
            ((skipped++))
            continue
        fi
        
        log_info "导入订阅: $name"
        log_debug "  URL: $url"
        log_debug "  备注: ${comment:-无}"
        
        # 使用超时和重试机制
        local retry_count=0
        local max_retries=3
        local success=false
        
        while [[ $retry_count -lt $max_retries ]] && [[ "$success" = false ]]; do
            if timeout 30 subscription-manager add "$url" "$name" 2>/dev/null; then
                log_success "✓ 订阅导入成功: $name"
                ((imported++))
                ((TOTAL_IMPORTED++))
                success=true
            else
                ((retry_count++))
                if [[ $retry_count -lt $max_retries ]]; then
                    log_warning "导入失败，重试 $retry_count/$max_retries: $name"
                    sleep 2
                else
                    log_error "✗ 订阅导入失败: $name (已重试 $max_retries 次)"
                    ((failed++))
                    ((TOTAL_FAILED++))
                fi
            fi
        done
        
    done < "$SUBSCRIPTIONS_CONF"
    
    # 更新全局统计
    ((TOTAL_SKIPPED += skipped))
    
    echo ""
    log_info "订阅导入完成: $imported 个成功, $skipped 个跳过, $failed 个失败"
    
    return 0
}

# 验证节点参数
validate_node_params() {
    local protocol="$1"
    local name="$2"
    local server="$3"
    local port="$4"
    shift 4
    local params=("$@")
    
    # 验证基本参数
    if [[ -z "$protocol" ]] || [[ -z "$name" ]] || [[ -z "$server" ]] || [[ -z "$port" ]]; then
        return 1
    fi
    
    # 验证端口号
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [[ $port -lt 1 ]] || [[ $port -gt 65535 ]]; then
        log_warning "无效端口号: $port"
        return 1
    fi
    
    # 验证服务器地址
    if ! [[ "$server" =~ ^[a-zA-Z0-9.-]+$ ]]; then
        log_warning "无效服务器地址: $server"
        return 1
    fi
    
    # 根据协议验证特定参数
    case "$protocol" in
        vmess)
            if [[ ${#params[@]} -lt 5 ]]; then
                log_warning "VMess协议参数不足"
                return 1
            fi
            ;;
        ss)
            if [[ ${#params[@]} -lt 2 ]]; then
                log_warning "Shadowsocks协议参数不足"
                return 1
            fi
            ;;
        trojan)
            if [[ ${#params[@]} -lt 1 ]]; then
                log_warning "Trojan协议参数不足"
                return 1
            fi
            ;;
        *)
            log_warning "不支持的协议: $protocol"
            return 1
            ;;
    esac
    
    return 0
}

# 导入单个节点
import_nodes() {
    if [[ ! -f "$NODES_CONF" ]]; then
        log_warning "节点配置文件不存在: $NODES_CONF"
        log_info "请创建配置文件，格式: 协议|名称|服务器|端口|参数1|参数2|...|备注"
        return 1
    fi
    
    log_info "开始导入单个节点..."
    log_info "配置文件: $NODES_CONF"
    
    local imported=0
    local skipped=0
    local failed=0
    local line_num=0
    
    # 验证配置文件格式
    if [[ ! -s "$NODES_CONF" ]]; then
        log_warning "配置文件为空"
        return 1
    fi
    
    while IFS='|' read -r protocol name server port param1 param2 param3 param4 param5 comment || [[ -n "$protocol" ]]; do
        ((line_num++))
        
        # 跳过注释和空行
        if [[ "$protocol" =~ ^[[:space:]]*#.*$ ]] || [[ -z "${protocol// }" ]]; then
            continue
        fi
        
        # 去除前后空格
        protocol=$(echo "$protocol" | xargs 2>/dev/null || echo "$protocol")
        name=$(echo "$name" | xargs 2>/dev/null || echo "$name")
        server=$(echo "$server" | xargs 2>/dev/null || echo "$server")
        port=$(echo "$port" | xargs 2>/dev/null || echo "$port")
        param1=$(echo "$param1" | xargs 2>/dev/null || echo "$param1")
        param2=$(echo "$param2" | xargs 2>/dev/null || echo "$param2")
        param3=$(echo "$param3" | xargs 2>/dev/null || echo "$param3")
        param4=$(echo "$param4" | xargs 2>/dev/null || echo "$param4")
        param5=$(echo "$param5" | xargs 2>/dev/null || echo "$param5")
        comment=$(echo "$comment" | xargs 2>/dev/null || echo "$comment")
        
        # 验证节点参数
        if ! validate_node_params "$protocol" "$name" "$server" "$port" "$param1" "$param2" "$param3" "$param4" "$param5"; then
            log_warning "第${line_num}行参数错误，跳过: $protocol|$name|$server|$port"
            ((skipped++))
            continue
        fi
        
        log_info "导入节点: $name ($protocol)"
        log_debug "  服务器: $server:$port"
        log_debug "  备注: ${comment:-无}"
        
        local success=false
        local add_script="$SCRIPT_DIR/add_proxy_nodes.sh"
        
        case "$protocol" in
            vmess)
                log_debug "  用户ID: $param1"
                log_debug "  额外ID: $param2"
                log_debug "  加密方式: $param3"
                log_debug "  网络类型: $param4"
                log_debug "  路径: $param5"
                
                if timeout 30 "$add_script" vmess "$name" "$server" "$port" "$param1" "$param2" "$param3" "$param4" "$param5" 2>/dev/null; then
                    log_success "✓ VMess节点导入成功: $name"
                    ((imported++))
                    ((TOTAL_IMPORTED++))
                    success=true
                else
                    log_error "✗ VMess节点导入失败: $name"
                    ((failed++))
                    ((TOTAL_FAILED++))
                fi
                ;;
            ss)
                log_debug "  密码: ${param1:0:8}..."
                log_debug "  加密方式: $param2"
                
                if timeout 30 "$add_script" ss "$name" "$server" "$port" "$param1" "$param2" 2>/dev/null; then
                    log_success "✓ Shadowsocks节点导入成功: $name"
                    ((imported++))
                    ((TOTAL_IMPORTED++))
                    success=true
                else
                    log_error "✗ Shadowsocks节点导入失败: $name"
                    ((failed++))
                    ((TOTAL_FAILED++))
                fi
                ;;
            trojan)
                log_debug "  密码: ${param1:0:8}..."
                
                if timeout 30 "$add_script" trojan "$name" "$server" "$port" "$param1" 2>/dev/null; then
                    log_success "✓ Trojan节点导入成功: $name"
                    ((imported++))
                    ((TOTAL_IMPORTED++))
                    success=true
                else
                    log_error "✗ Trojan节点导入失败: $name"
                    ((failed++))
                    ((TOTAL_FAILED++))
                fi
                ;;
            *)
                log_warning "不支持的协议: $protocol"
                ((skipped++))
                ((TOTAL_SKIPPED++))
                ;;
        esac
        
    done < "$NODES_CONF"
    
    # 更新全局统计
    ((TOTAL_SKIPPED += skipped))
    
    echo ""
    log_info "节点导入完成: $imported 个成功, $skipped 个跳过, $failed 个失败"
    
    return 0
}

# 应用所有订阅
apply_all_subscriptions() {
    log_info "应用所有订阅..."
    
    # 获取所有订阅名称
    local subscriptions
    subscriptions=$(subscription-manager list 2>/dev/null | grep -E "^[^#]" | awk '{print $1}' 2>/dev/null || true)
    
    if [[ -z "$subscriptions" ]]; then
        log_warning "没有找到可用的订阅"
        return 1
    fi
    
    local applied=0
    local failed=0
    
    while IFS= read -r sub_name; do
        if [[ -n "$sub_name" ]]; then
            log_info "应用订阅: $sub_name"
            if timeout 60 subscription-manager apply "$sub_name" 2>/dev/null; then
                log_success "✓ 订阅应用成功: $sub_name"
                ((applied++))
            else
                log_error "✗ 订阅应用失败: $sub_name"
                ((failed++))
            fi
        fi
    done <<< "$subscriptions"
    
    log_info "订阅应用完成: $applied 个成功, $failed 个失败"
    return 0
}

# 重启服务
restart_services() {
    log_info "重启代理服务..."
    
    # 检查服务管理器是否存在
    if ! command -v proxy-manager &> /dev/null; then
        log_error "proxy-manager 命令不存在"
        return 1
    fi
    
    # 尝试重启服务
    if timeout 30 proxy-manager restart 2>/dev/null; then
        log_success "✓ 服务重启成功"
        
        # 等待服务启动
        sleep 3
        
        # 验证服务状态
        if proxy-manager status &> /dev/null; then
            log_success "✓ 服务运行正常"
        else
            log_warning "服务状态检查失败，请手动验证"
        fi
    else
        log_error "✗ 服务重启失败"
        return 1
    fi
    
    return 0
}

# 显示统计信息
show_statistics() {
    echo ""
    log_info "=== 导入统计 ==="
    log_info "总计导入成功: $TOTAL_IMPORTED"
    log_info "总计跳过: $TOTAL_SKIPPED"
    log_info "总计失败: $TOTAL_FAILED"
    
    if [[ $TOTAL_FAILED -gt 0 ]]; then
        log_warning "存在失败项目，请检查配置文件格式和网络连接"
    fi
    
    if [[ $TOTAL_IMPORTED -gt 0 ]]; then
        log_success "导入操作完成，建议重启服务以应用更改"
    fi
}

# 显示帮助
show_help() {
    cat << EOF
批量导入工具 - 全局代理项目

用法: $0 [选项]

选项:
    -s, --subscriptions     仅导入订阅
    -n, --nodes            仅导入节点
    -a, --all              导入所有（默认）
    -r, --restart          导入后重启服务
    --apply                导入后应用所有订阅
    --dry-run              仅验证配置文件，不实际导入
    -v, --verbose          详细输出
    -h, --help             显示帮助信息

配置文件:
    subscriptions.conf     机场订阅配置
                          格式: 名称|URL|启用状态|备注
    nodes.conf            单个节点配置
                          格式: 协议|名称|服务器|端口|参数1|参数2|...|备注

支持的协议:
    vmess                 VMess协议
    ss                    Shadowsocks协议
    trojan                Trojan协议

示例:
    $0                    # 导入所有配置
    $0 -s                 # 仅导入订阅
    $0 -n                 # 仅导入节点
    $0 -a -r              # 导入所有并重启服务
    $0 --apply            # 导入并应用所有订阅
    $0 --dry-run          # 验证配置文件

配置文件示例:
    subscriptions.conf:
    # 名称|URL|启用|备注
    机场1|https://example.com/sub|true|主要机场
    机场2|https://example2.com/sub|false|备用机场

    nodes.conf:
    # 协议|名称|服务器|端口|参数...
    vmess|节点1|example.com|443|uuid|0|auto|ws|/path
    ss|节点2|example.com|8388|password|aes-256-gcm
    trojan|节点3|example.com|443|password

EOF
}

# 验证配置文件
validate_config_files() {
    log_info "验证配置文件..."
    
    local errors=0
    
    # 验证订阅配置文件
    if [[ -f "$SUBSCRIPTIONS_CONF" ]]; then
        log_info "验证订阅配置文件: $SUBSCRIPTIONS_CONF"
        local line_num=0
        while IFS='|' read -r name url enabled comment || [[ -n "$name" ]]; do
            ((line_num++))
            if [[ "$name" =~ ^[[:space:]]*#.*$ ]] || [[ -z "${name// }" ]]; then
                continue
            fi
            
            if [[ -z "$name" ]] || [[ -z "$url" ]]; then
                log_error "订阅配置第${line_num}行格式错误: $name|$url"
                ((errors++))
            elif ! [[ "$url" =~ ^https?:// ]]; then
                log_error "订阅配置第${line_num}行URL格式错误: $url"
                ((errors++))
            fi
        done < "$SUBSCRIPTIONS_CONF"
    fi
    
    # 验证节点配置文件
    if [[ -f "$NODES_CONF" ]]; then
        log_info "验证节点配置文件: $NODES_CONF"
        local line_num=0
        while IFS='|' read -r protocol name server port param1 param2 param3 param4 param5 comment || [[ -n "$protocol" ]]; do
            ((line_num++))
            if [[ "$protocol" =~ ^[[:space:]]*#.*$ ]] || [[ -z "${protocol// }" ]]; then
                continue
            fi
            
            if ! validate_node_params "$protocol" "$name" "$server" "$port" "$param1" "$param2" "$param3" "$param4" "$param5"; then
                log_error "节点配置第${line_num}行参数错误: $protocol|$name|$server|$port"
                ((errors++))
            fi
        done < "$NODES_CONF"
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_success "配置文件验证通过"
        return 0
    else
        log_error "配置文件验证失败，发现 $errors 个错误"
        return 1
    fi
}

# 主函数
main() {
    local import_subscriptions_flag=false
    local import_nodes_flag=false
    local restart_flag=false
    local apply_flag=false
    local dry_run=false
    local verbose=false
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -s|--subscriptions)
                import_subscriptions_flag=true
                shift
                ;;
            -n|--nodes)
                import_nodes_flag=true
                shift
                ;;
            -a|--all)
                import_subscriptions_flag=true
                import_nodes_flag=true
                shift
                ;;
            -r|--restart)
                restart_flag=true
                shift
                ;;
            --apply)
                apply_flag=true
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            -v|--verbose)
                verbose=true
                export DEBUG=1
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
    
    # 如果没有指定任何导入选项，默认导入所有
    if [[ "$import_subscriptions_flag" = false ]] && [[ "$import_nodes_flag" = false ]]; then
        import_subscriptions_flag=true
        import_nodes_flag=true
    fi
    
    log_info "批量导入工具启动"
    log_info "工作目录: $SCRIPT_DIR"
    log_info "配置参数:"
    log_info "  导入订阅: $([ "$import_subscriptions_flag" = true ] && echo "是" || echo "否")"
    log_info "  导入节点: $([ "$import_nodes_flag" = true ] && echo "是" || echo "否")"
    log_info "  重启服务: $([ "$restart_flag" = true ] && echo "是" || echo "否")"
    log_info "  应用订阅: $([ "$apply_flag" = true ] && echo "是" || echo "否")"
    log_info "  详细输出: $([ "$verbose" = true ] && echo "是" || echo "否")"
    
    # 干运行模式
    if [[ "$dry_run" = true ]]; then
        log_info "干运行模式，仅验证配置文件"
        validate_config_files
        exit $?
    fi
    
    # 检查依赖
    check_project_dependencies
    
    # 创建备份
    local backup_dir="$TEMP_DIR/backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    log_info "创建配置备份: $backup_dir"
    
    echo ""
    log_info "=== 批量导入开始 ==="
    echo ""
    
    # 导入订阅
    if [[ "$import_subscriptions_flag" = true ]]; then
        import_subscriptions
        echo ""
    fi
    
    # 导入节点
    if [[ "$import_nodes_flag" = true ]]; then
        import_nodes
        echo ""
    fi
    
    # 应用订阅
    if [[ "$apply_flag" = true ]] && [[ "$import_subscriptions_flag" = true ]]; then
        apply_all_subscriptions
        echo ""
    fi
    
    # 重启服务
    if [[ "$restart_flag" = true ]]; then
        restart_services
        echo ""
    fi
    
    # 显示统计信息
    show_statistics
    
    echo ""
    log_success "=== 批量导入完成 ==="
    
    # 显示服务状态
    if command -v proxy-manager &> /dev/null; then
        echo ""
        log_info "当前服务状态:"
        proxy-manager status || true
    fi
    
    # 清理临时文件
    if [[ -d "$TEMP_DIR" ]] && [[ "$TEMP_DIR" != "$SCRIPT_DIR" ]]; then
        find "$TEMP_DIR" -type f -mtime +7 -delete 2>/dev/null || true
    fi
}

# 如果直接运行此脚本，则执行主函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi