#!/bin/bash

# 用户界面脚本
# 提供友好的交互式界面和菜单系统

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

# 界面配置
MENU_WIDTH=60
DIALOG_HEIGHT=20
DIALOG_WIDTH=70

# 检查dialog是否可用
check_dialog() {
    if command -v dialog &>/dev/null; then
        return 0
    elif command -v whiptail &>/dev/null; then
        alias dialog='whiptail'
        return 0
    else
        log_warn "未找到dialog或whiptail，使用文本界面"
        return 1
    fi
}

# 显示主菜单
show_main_menu() {
    local use_dialog=false
    check_dialog && use_dialog=true
    
    # 首次启动时显示系统状态
    local first_run=true
    
    while true; do
        clear
        display_banner
        
        # 首次运行时显示系统状态
        if [[ "$first_run" == "true" ]]; then
            show_system_status
            first_run=false
        fi
        
        if [[ "$use_dialog" == "true" ]]; then
            show_dialog_menu
        else
            show_text_menu
        fi
        
        echo ""
        echo -e "${GRAY}提示: 输入 'h' 查看帮助，'s' 查看系统状态${NC}"
        read -rp "请输入选项 [1-5]: " choice
        
        case "$choice" in
            1) 
                if confirm_action "确定要进入安装菜单吗？" "y"; then
                    show_installation_menu
                fi
                ;;
            2) 
                if confirm_action "确定要进入订阅管理吗？" "y"; then
                    subscription_menu
                fi
                ;;
            3) 
                if confirm_action "确定要进入服务管理吗？" "y"; then
                    service_menu
                fi
                ;;
            4) show_about_info ;;
            5)
                if confirm_action "确定要退出程序吗？" "n"; then
                    clear
                    show_result "info" "感谢使用，再见！"
                    exit 0
                fi
                ;;
            [Hh]|help)
                show_help
                pause
                ;;
            [Ss]|status)
                show_system_status
                pause
                ;;
            *)
                show_result "error" "无效选项: $choice" "请输入 1-5 之间的数字"
                sleep 2
                ;;
        esac
    done
}

# 显示文本菜单
show_text_menu() {
    echo "主菜单"
    echo "1. 安装和更新"
    echo "2. 订阅管理"
    echo "3. 服务管理"
    echo "4. 关于"
    echo "5. 退出"
}

# 显示dialog菜单
show_dialog_menu() {
    local choice
    choice=$(dialog --clear --backtitle "Sing-box 管理脚本" \
        --title "主菜单" \
        --menu "请选择一个操作:" \
        $DIALOG_HEIGHT $DIALOG_WIDTH 4 \
        "1" "安装和更新" \
        "2" "订阅管理" \
        "3" "服务管理" \
        "4" "关于" \
        3>&1 1>&2 2>&3)
    
    case "$choice" in
        1) show_installation_menu ;;
        2) subscription_menu ;;
        3) service_menu ;;
        4) show_about_info ;;
        *)
            clear
            log_info "感谢使用，再见！"
            exit 0
            ;;
    esac
}

# 显示关于信息
show_about_info() {
    local version="2.0.0"
    local description="一个强大的 Sing-box 管理脚本"
    
    if check_dialog; then
        dialog --clear --backtitle "关于" \
            --msgbox "版本: $version\n\n$description" 10 40
    else
        clear
        display_banner
        echo "版本: $version"
        echo ""
        echo "$description"
        pause
    fi
}

# 显示安装菜单
show_installation_menu() {
    while true; do
        clear
        echo -e "${CYAN}安装和配置${NC}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo -e "${GREEN}1.${NC} 一键安装      - 安装所有组件"
        echo -e "${GREEN}2.${NC} 仅安装sing-box"
        echo -e "${GREEN}3.${NC} 仅安装面板"
        echo -e "${GREEN}4.${NC} 并行安装      - 高速并行安装"
        echo -e "${GREEN}5.${NC} 自定义安装    - 选择性安装组件"
        echo -e "${GREEN}6.${NC} 卸载程序"
        echo -e "${GREEN}0.${NC} 返回主菜单"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        local choice
        read -p "请选择操作 [0-6]: " choice
        
        case $choice in
            1) 
                log_info "开始一键安装..."
                bash "$SCRIPT_DIR/install_all.sh"
                pause
                ;;
            2)
                log_info "开始安装sing-box..."
                bash "$SCRIPT_DIR/install_singbox.sh"
                pause
                ;;
            3)
                log_info "开始安装面板..."
                bash "$SCRIPT_DIR/setup_zashboard.sh"
                pause
                ;;
            4)
                log_info "开始并行安装..."
                bash "$SCRIPT_DIR/parallel_installer.sh"
                pause
                ;;
            5)
                custom_install_menu
                ;;
            6)
                uninstall_menu
                ;;
            0)
                return
                ;;
            *)
                log_error "无效选择，请重试"
                sleep 2
                ;;
        esac
    done
}

# 订阅管理菜单
subscription_menu() {
    while true; do
        clear
        echo -e "${CYAN}订阅管理${NC}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo -e "${GREEN}1.${NC} 添加订阅"
        echo -e "${GREEN}2.${NC} 列出订阅"
        echo -e "${GREEN}3.${NC} 更新订阅"
        echo -e "${GREEN}4.${NC} 删除订阅"
        echo -e "${GREEN}5.${NC} 应用订阅"
        echo -e "${GREEN}6.${NC} 测试订阅"
        echo -e "${GREEN}7.${NC} 批量导入"
        echo -e "${GREEN}0.${NC} 返回主菜单"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        local choice
        read -p "请选择操作 [0-7]: " choice
        
        case $choice in
            1) add_subscription_interactive ;;
            2) list_subscriptions ;;
            3) update_subscription_interactive ;;
            4) remove_subscription_interactive ;;
            5) apply_subscription_interactive ;;
            6) test_subscription_interactive ;;
            7) batch_import_menu ;;
            0) return ;;
            *)
                log_error "无效选择，请重试"
                sleep 2
                ;;
        esac
    done
}

# 服务管理菜单
service_menu() {
    while true; do
        clear
        echo -e "${CYAN}服务管理${NC}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        # 显示服务状态
        show_service_status_enhanced
        
        echo ""
        echo -e "${GREEN}1.${NC} 启动服务      - 启动所有服务"
        echo -e "${GREEN}2.${NC} 停止服务      - 安全停止所有服务"
        echo -e "${GREEN}3.${NC} 重启服务      - 重新启动所有服务"
        echo -e "${GREEN}4.${NC} 查看日志      - 实时查看服务日志"
        echo -e "${GREEN}5.${NC} 服务配置      - 修改服务配置"
        echo -e "${GREEN}6.${NC} 自动启动设置  - 配置开机自启"
        echo -e "${GREEN}7.${NC} 服务诊断      - 检查服务健康状态"
        echo -e "${GREEN}0.${NC} 返回主菜单"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        local choice
        read -p "请选择操作 [0-7]: " choice
        
        case $choice in
            1) 
                if confirm_action "确定要启动所有服务吗？" "y"; then
                    start_services_enhanced
                fi
                ;;
            2) 
                if confirm_action "确定要停止所有服务吗？" "n" 0 "true"; then
                    stop_services_enhanced
                fi
                ;;
            3) 
                if confirm_action "确定要重启所有服务吗？" "n" 0 "true"; then
                    restart_services_enhanced
                fi
                ;;
            4) view_logs_menu ;;
            5) service_config_menu ;;
            6) autostart_menu ;;
            7) service_diagnostics ;;
            0) return ;;
            *)
                show_result "error" "无效选择: $choice" "请输入 0-7 之间的数字"
                sleep 2
                ;;
        esac
    done
}

# 显示服务状态
show_service_status() {
    echo -e "${YELLOW}当前服务状态:${NC}"
    
    local services=("sing-box" "nginx")
    for service in "${services[@]}"; do
        if systemctl is-active "$service" &>/dev/null; then
            echo -e "  $service: ${GREEN}运行中${NC}"
        else
            echo -e "  $service: ${RED}已停止${NC}"
        fi
    done
}

# 增强的服务状态显示
show_service_status_enhanced() {
    echo -e "${YELLOW}=== 服务状态详情 ===${NC}"
    
    local services=("sing-box" "nginx")
    local all_running=true
    
    for service in "${services[@]}"; do
        echo -n "  $service: "
        
        if systemctl is-active "$service" &>/dev/null; then
            local uptime=$(systemctl show "$service" --property=ActiveEnterTimestamp --value 2>/dev/null)
            local memory=$(systemctl show "$service" --property=MemoryCurrent --value 2>/dev/null)
            
            echo -e "${GREEN}●${NC} 运行中"
            [[ -n "$uptime" ]] && echo -e "    ${GRAY}启动时间: $uptime${NC}"
            [[ -n "$memory" && "$memory" != "0" ]] && echo -e "    ${GRAY}内存使用: $(( memory / 1024 / 1024 ))MB${NC}"
        else
            echo -e "${RED}●${NC} 已停止"
            all_running=false
            
            # 检查是否启用了自动启动
            if systemctl is-enabled "$service" &>/dev/null; then
                echo -e "    ${YELLOW}⚠${NC} 已设置开机自启但当前未运行"
            fi
        fi
        echo ""
    done
    
    # 显示整体状态
    if [[ "$all_running" == "true" ]]; then
        show_result "success" "所有服务正常运行"
    else
        show_result "warning" "部分服务未运行"
    fi
}

# 增强的启动服务
start_services_enhanced() {
    local services=("sing-box" "nginx")
    local total=${#services[@]}
    local current=0
    
    echo -e "${CYAN}正在启动服务...${NC}"
    
    for service in "${services[@]}"; do
        ((current++))
        show_progress $current $total "启动 $service"
        
        if systemctl is-active "$service" &>/dev/null; then
            show_result "info" "$service 已经在运行"
        else
            if retry_operation 3 2 "启动$service" systemctl start "$service"; then
                show_result "success" "$service 启动成功"
            else
                show_result "error" "$service 启动失败"
                handle_ui_error 1 "服务启动失败" "启动$service服务"
                return 1
            fi
        fi
        sleep 1
    done
    
    echo ""
    show_result "success" "所有服务启动完成"
    pause
}

# 增强的停止服务
stop_services_enhanced() {
    local services=("nginx" "sing-box")  # 反向顺序停止
    local total=${#services[@]}
    local current=0
    
    echo -e "${CYAN}正在停止服务...${NC}"
    
    for service in "${services[@]}"; do
        ((current++))
        show_progress $current $total "停止 $service"
        
        if ! systemctl is-active "$service" &>/dev/null; then
            show_result "info" "$service 已经停止"
        else
            if retry_operation 3 2 "停止$service" systemctl stop "$service"; then
                show_result "success" "$service 停止成功"
            else
                show_result "warning" "$service 停止失败，尝试强制停止"
                systemctl kill "$service" 2>/dev/null || true
            fi
        fi
        sleep 1
    done
    
    echo ""
    show_result "success" "所有服务停止完成"
    pause
}

# 增强的重启服务
restart_services_enhanced() {
    echo -e "${CYAN}正在重启服务...${NC}"
    
    # 先停止服务
    stop_services_enhanced
    
    echo -e "${CYAN}等待服务完全停止...${NC}"
    sleep 3
    
    # 再启动服务
    start_services_enhanced
}

# 服务诊断
service_diagnostics() {
    clear
    echo -e "${CYAN}=== 服务诊断报告 ===${NC}"
    echo ""
    
    local services=("sing-box" "nginx")
    
    for service in "${services[@]}"; do
        echo -e "${YELLOW}诊断服务: $service${NC}"
        echo "----------------------------------------"
        
        # 检查服务状态
        if systemctl is-active "$service" &>/dev/null; then
            show_result "success" "服务运行状态正常"
        else
            show_result "error" "服务未运行"
        fi
        
        # 检查服务配置
        if systemctl is-enabled "$service" &>/dev/null; then
            show_result "success" "开机自启已启用"
        else
            show_result "warning" "开机自启未启用"
        fi
        
        # 检查配置文件
        local config_file=""
        case "$service" in
            "sing-box") config_file="/etc/sing-box/config.json" ;;
            "nginx") config_file="/etc/nginx/nginx.conf" ;;
        esac
        
        if [[ -n "$config_file" && -f "$config_file" ]]; then
            show_result "success" "配置文件存在: $config_file"
        else
            show_result "error" "配置文件缺失: $config_file"
        fi
        
        # 检查端口占用
        case "$service" in
            "sing-box")
                if netstat -tlnp 2>/dev/null | grep -q ":1080\|:7890"; then
                    show_result "success" "代理端口正常监听"
                else
                    show_result "warning" "代理端口未监听"
                fi
                ;;
            "nginx")
                if netstat -tlnp 2>/dev/null | grep -q ":80\|:443"; then
                    show_result "success" "Web端口正常监听"
                else
                    show_result "warning" "Web端口未监听"
                fi
                ;;
        esac
        
        echo ""
    done
    
    # 系统资源检查
    echo -e "${YELLOW}系统资源状态:${NC}"
    echo "----------------------------------------"
    show_system_status
    
    pause
}

# 交互式添加订阅
add_subscription_interactive() {
    echo -e "${CYAN}添加新订阅${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local name url
    read -p "请输入订阅名称: " name
    read -p "请输入订阅链接: " url
    
    if [[ -n "$name" && -n "$url" ]]; then
        bash "$SCRIPT_DIR/subscription_manager.sh" add "$name" "$url"
        log_success "订阅添加完成"
    else
        log_error "名称和链接不能为空"
    fi
    
    pause
}

# 列出订阅
list_subscriptions() {
    echo -e "${CYAN}订阅列表${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    bash "$SCRIPT_DIR/subscription_manager.sh" list
    
    pause
}

# 暂停函数
pause() {
    echo ""
    read -p "按回车键继续..."
}

# 显示进度条
show_progress_bar() {
    local current="$1"
    local total="$2"
    local message="${3:-处理中}"
    local width=50
    
    local percent=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))
    
    printf "\r%s [" "$message"
    printf "%*s" $filled | tr ' ' '█'
    printf "%*s" $empty | tr ' ' '░'
    printf "] %d%%" $percent
    
    if [[ $current -eq $total ]]; then
        echo ""
    fi
}

# 确认对话框 - 增强版
confirm_dialog() {
    local message="$1"
    local default="${2:-n}"
    local timeout="${3:-0}"
    local prompt="确认吗?"
    
    # 根据默认值设置提示
    if [[ "$default" == "y" ]]; then
        prompt="$prompt [Y/n]"
    else
        prompt="$prompt [y/N]"
    fi
    
    echo -e "${YELLOW}$message${NC}"
    
    # 如果设置了超时
    if [[ $timeout -gt 0 ]]; then
        echo -e "${CYAN}将在 $timeout 秒后自动选择默认选项...${NC}"
        if read -t $timeout -p "$prompt: " -n 1 -r; then
            echo ""
        else
            echo ""
            echo -e "${CYAN}超时，使用默认选项: $default${NC}"
            REPLY="$default"
        fi
    else
        read -p "$prompt: " -n 1 -r
        echo ""
    fi
    
    # 处理空输入
    if [[ -z "$REPLY" ]]; then
        REPLY="$default"
    fi
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

# 输入验证 - 增强版
validate_input() {
    local input="$1"
    local type="$2"
    local field_name="${3:-输入}"
    local allow_empty="${4:-false}"
    
    # 检查空输入
    if [[ -z "$input" ]]; then
        if [[ "$allow_empty" == "true" ]]; then
            return 0
        else
            log_error "$field_name 不能为空"
            return 1
        fi
    fi
    
    case "$type" in
        "url")
            if [[ "$input" =~ ^https?://[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}(/.*)?$ ]]; then
                return 0
            else
                log_error "$field_name 格式无效。示例: https://example.com/path"
                return 1
            fi
            ;;
        "port")
            if [[ "$input" =~ ^[0-9]+$ ]] && [[ $input -ge 1 ]] && [[ $input -le 65535 ]]; then
                return 0
            else
                log_error "$field_name 必须是1-65535之间的数字"
                return 1
            fi
            ;;
        "ip")
            if [[ "$input" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
                # 进一步验证每个八位组
                IFS='.' read -ra ADDR <<< "$input"
                for i in "${ADDR[@]}"; do
                    if [[ $i -gt 255 ]]; then
                        log_error "$field_name 格式无效。IP地址每段必须在0-255之间"
                        return 1
                    fi
                done
                return 0
            else
                log_error "$field_name 格式无效。示例: 192.168.1.1"
                return 1
            fi
            ;;
        "domain")
            if [[ "$input" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
                return 0
            else
                log_error "$field_name 格式无效。示例: example.com"
                return 1
            fi
            ;;
        "email")
            if [[ "$input" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
                return 0
            else
                log_error "$field_name 格式无效。示例: user@example.com"
                return 1
            fi
            ;;
        "number")
            if [[ "$input" =~ ^[0-9]+$ ]]; then
                return 0
            else
                log_error "$field_name 必须是数字"
                return 1
            fi
            ;;
        "path")
            if [[ -e "$input" ]]; then
                return 0
            else
                log_error "$field_name 路径不存在: $input"
                return 1
            fi
            ;;
        "filename")
            if [[ "$input" =~ ^[a-zA-Z0-9._-]+$ ]]; then
                return 0
            else
                log_error "$field_name 包含无效字符。只允许字母、数字、点、下划线和连字符"
                return 1
            fi
            ;;
        *)
            # 默认只检查非空
            return 0
            ;;
    esac
}

# 错误处理 - 增强版
handle_ui_error() {
    local error_code="$1"
    local error_message="$2"
    local context="${3:-未知操作}"
    local auto_retry="${4:-false}"
    
    log_error "操作失败: $error_message (错误代码: $error_code)"
    log_error "操作上下文: $context"
    
    # 详细的错误分析和建议
    case $error_code in
        1)
            log_error "一般错误"
            echo -e "${YELLOW}可能的原因:${NC}"
            echo "  • 网络连接问题"
            echo "  • 服务器响应超时"
            echo "  • 配置文件错误"
            echo -e "${CYAN}建议解决方案:${NC}"
            echo "  1. 检查网络连接状态"
            echo "  2. 验证服务器地址和端口"
            echo "  3. 检查防火墙设置"
            ;;
        2)
            log_error "权限错误"
            echo -e "${YELLOW}可能的原因:${NC}"
            echo "  • 文件或目录权限不足"
            echo "  • 需要管理员权限"
            echo -e "${CYAN}建议解决方案:${NC}"
            echo "  1. 使用 sudo 运行脚本"
            echo "  2. 检查文件所有者和权限"
            echo "  3. 确保当前用户在正确的用户组中"
            ;;
        126)
            log_error "执行权限错误"
            echo -e "${YELLOW}可能的原因:${NC}"
            echo "  • 文件没有执行权限"
            echo "  • 文件格式不正确"
            echo -e "${CYAN}建议解决方案:${NC}"
            echo "  1. 运行: chmod +x <文件名>"
            echo "  2. 检查文件是否损坏"
            echo "  3. 验证文件格式和编码"
            ;;
        127)
            log_error "命令未找到"
            echo -e "${YELLOW}可能的原因:${NC}"
            echo "  • 命令不存在或未安装"
            echo "  • PATH环境变量配置错误"
            echo -e "${CYAN}建议解决方案:${NC}"
            echo "  1. 安装缺失的软件包"
            echo "  2. 检查命令拼写"
            echo "  3. 更新PATH环境变量"
            ;;
        130)
            log_error "用户中断操作"
            echo -e "${CYAN}操作被用户取消${NC}"
            return 0
            ;;
        *)
            log_error "未知错误"
            echo -e "${YELLOW}可能的原因:${NC}"
            echo "  • 系统资源不足"
            echo "  • 软件包依赖问题"
            echo "  • 配置文件损坏"
            echo -e "${CYAN}建议解决方案:${NC}"
            echo "  1. 查看详细日志文件"
            echo "  2. 检查系统资源使用情况"
            echo "  3. 重新安装相关软件包"
            echo "  4. 联系技术支持"
            ;;
    esac
    
    # 提供操作选项
    echo ""
    echo -e "${YELLOW}您可以选择:${NC}"
    echo "1. 重试操作"
    echo "2. 跳过此步骤"
    echo "3. 查看详细日志"
    echo "4. 返回主菜单"
    echo "5. 退出程序"
    
    if [[ "$auto_retry" == "true" ]]; then
        echo -e "${CYAN}将在10秒后自动重试...${NC}"
        if read -t 10 -p "请选择 [1-5] (默认:1): " choice; then
            echo ""
        else
            echo ""
            choice="1"
        fi
    else
        read -p "请选择 [1-5]: " choice
    fi
    
    case "$choice" in
        1)
            log_info "准备重试操作..."
            return 1  # 表示需要重试
            ;;
        2)
            log_warn "跳过当前操作"
            return 0
            ;;
        3)
            show_error_logs
            pause
            return 2  # 表示查看了日志
            ;;
        4)
            log_info "返回主菜单"
            return 3  # 表示返回主菜单
            ;;
        5)
            log_info "退出程序"
            exit 0
            ;;
        *)
            log_warn "无效选择，返回主菜单"
            return 3
            ;;
    esac
}

# 显示错误日志
show_error_logs() {
    local log_file="/var/log/sing-box-manager.log"
    
    echo -e "${CYAN}最近的错误日志:${NC}"
    echo "----------------------------------------"
    
    if [[ -f "$log_file" ]]; then
        tail -20 "$log_file" | grep -i "error\|fail\|exception" || echo "未找到最近的错误记录"
    else
        echo "日志文件不存在: $log_file"
    fi
    
    echo "----------------------------------------"
}

# 进度指示器
show_progress() {
    local current="$1"
    local total="$2"
    local description="$3"
    local width=50
    
    local percentage=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))
    
    printf "\r${CYAN}%s${NC} [" "$description"
    printf "%*s" $filled | tr ' ' '█'
    printf "%*s" $empty | tr ' ' '░'
    printf "] %d%% (%d/%d)" $percentage $current $total
    
    if [[ $current -eq $total ]]; then
        echo -e " ${GREEN}✓${NC}"
    fi
}

# 旋转进度指示器
show_spinner() {
    local pid="$1"
    local message="$2"
    local delay=0.1
    local spinstr='|/-\'
    
    while kill -0 "$pid" 2>/dev/null; do
        local temp=${spinstr#?}
        printf "\r${CYAN}%s${NC} [%c]" "$message" "$spinstr"
        spinstr=$temp${spinstr%"$temp"}
        sleep $delay
    done
    printf "\r${GREEN}%s${NC} [✓]\n" "$message"
}

# 操作确认增强版
confirm_action() {
    local message="$1"
    local default="${2:-n}"
    local timeout="${3:-0}"
    local danger="${4:-false}"
    
    local prompt_color="$YELLOW"
    local icon="❓"
    
    if [[ "$danger" == "true" ]]; then
        prompt_color="$RED"
        icon="⚠️"
    fi
    
    echo ""
    echo -e "${prompt_color}${icon} $message${NC}"
    
    if [[ "$danger" == "true" ]]; then
        echo -e "${RED}警告: 此操作可能有风险，请仔细确认！${NC}"
    fi
    
    local prompt_text
    if [[ "$default" == "y" ]]; then
        prompt_text="请确认 [Y/n]"
    else
        prompt_text="请确认 [y/N]"
    fi
    
    if [[ $timeout -gt 0 ]]; then
        prompt_text="$prompt_text (${timeout}秒后默认选择: $default)"
        if read -t "$timeout" -p "$prompt_text: " response; then
            echo ""
        else
            echo ""
            response="$default"
            echo -e "${CYAN}超时，使用默认选择: $default${NC}"
        fi
    else
        read -p "$prompt_text: " response
    fi
    
    response=${response:-$default}
    case "$response" in
        [Yy]|[Yy][Ee][Ss]|是|y) return 0 ;;
        *) return 1 ;;
    esac
}

# 显示操作结果
show_result() {
    local status="$1"
    local message="$2"
    local details="$3"
    
    case "$status" in
        "success")
            echo -e "${GREEN}✓ 成功: $message${NC}"
            ;;
        "warning")
            echo -e "${YELLOW}⚠ 警告: $message${NC}"
            ;;
        "error")
            echo -e "${RED}✗ 错误: $message${NC}"
            ;;
        "info")
            echo -e "${CYAN}ℹ 信息: $message${NC}"
            ;;
    esac
    
    if [[ -n "$details" ]]; then
        echo -e "${GRAY}  详情: $details${NC}"
    fi
}

# 显示系统状态
show_system_status() {
    echo -e "${CYAN}=== 系统状态检查 ===${NC}"
    
    # 检查磁盘空间
    local disk_usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [[ $disk_usage -gt 90 ]]; then
        show_result "warning" "磁盘空间不足" "已使用 ${disk_usage}%"
    else
        show_result "success" "磁盘空间充足" "已使用 ${disk_usage}%"
    fi
    
    # 检查内存使用
    local mem_usage=$(free | awk 'NR==2{printf "%.0f", $3*100/$2}')
    if [[ $mem_usage -gt 90 ]]; then
        show_result "warning" "内存使用率高" "已使用 ${mem_usage}%"
    else
        show_result "success" "内存使用正常" "已使用 ${mem_usage}%"
    fi
    
    # 检查网络连接
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        show_result "success" "网络连接正常"
    else
        show_result "error" "网络连接异常"
    fi
    
    echo ""
}

# 智能重试机制
retry_operation() {
    local max_attempts="$1"
    local delay="$2"
    local operation="$3"
    shift 3
    local args=("$@")
    
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        echo -e "${CYAN}尝试 $attempt/$max_attempts: $operation${NC}"
        
        if "${args[@]}"; then
            show_result "success" "操作成功完成"
            return 0
        else
            local exit_code=$?
            show_result "warning" "第 $attempt 次尝试失败" "退出代码: $exit_code"
            
            if [[ $attempt -lt $max_attempts ]]; then
                echo -e "${YELLOW}等待 $delay 秒后重试...${NC}"
                sleep "$delay"
                ((attempt++))
            else
                show_result "error" "所有重试都失败了"
                return $exit_code
            fi
        fi
    done
}

# 主函数显示帮助信息
show_help() {
    echo "用户界面脚本使用说明:"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  menu         显示主菜单 (默认)"
    echo "  install      直接进入安装菜单"
    echo "  subscription 直接进入订阅管理"
    echo "  service      直接进入服务管理"
    echo "  help         显示此帮助信息"
    echo ""
    echo "功能特性:"
    echo "  - 交互式菜单界面"
    echo "  - 输入验证和错误处理"
    echo "  - 进度显示和状态反馈"
    echo "  - 支持dialog/whiptail图形界面"
}

# 更新订阅交互式函数
update_subscription_interactive() {
    echo "请输入要更新的订阅名称："
    read -r sub_name
    if [[ -n "$sub_name" ]]; then
        bash "$SCRIPT_DIR/subscription_manager.sh" update "$sub_name"
    else
        log_error "订阅名称不能为空"
    fi
    pause
}

# 删除订阅交互式函数
remove_subscription_interactive() {
    echo "请输入要删除的订阅名称："
    read -r sub_name
    if [[ -n "$sub_name" ]]; then
        bash "$SCRIPT_DIR/subscription_manager.sh" remove "$sub_name"
    else
        log_error "订阅名称不能为空"
    fi
    pause
}

# 应用订阅交互式函数
apply_subscription_interactive() {
    echo "请输入要应用的订阅名称："
    read -r sub_name
    if [[ -n "$sub_name" ]]; then
        bash "$SCRIPT_DIR/subscription_manager.sh" apply "$sub_name"
    else
        log_error "订阅名称不能为空"
    fi
    pause
}

# 测试订阅交互式函数
test_subscription_interactive() {
    echo "请输入要测试的订阅名称："
    read -r sub_name
    if [[ -n "$sub_name" ]]; then
        bash "$SCRIPT_DIR/subscription_manager.sh" test "$sub_name"
    else
        log_error "订阅名称不能为空"
    fi
    pause
}

# 批量导入菜单
batch_import_menu() {
    echo "批量导入功能"
    echo "1. 从文件导入"
    echo "2. 从URL导入"
    read -p "请选择 [1-2]: " choice
    case $choice in
        1)
            echo "请输入文件路径："
            read -r file_path
            if [[ -f "$file_path" ]]; then
                bash "$SCRIPT_DIR/batch_import.sh" file "$file_path"
            else
                log_error "文件不存在"
            fi
            ;;
        2)
            echo "请输入URL："
            read -r url
            if [[ -n "$url" ]]; then
                bash "$SCRIPT_DIR/batch_import.sh" url "$url"
            else
                log_error "URL不能为空"
            fi
            ;;
        *)
            log_error "无效选择"
            ;;
    esac
    pause
}

# 启动服务
start_services() {
    log_info "启动服务..."
    systemctl start sing-box
    systemctl start nginx
    pause
}

# 停止服务
stop_services() {
    log_info "停止服务..."
    systemctl stop sing-box
    systemctl stop nginx
    pause
}

# 重启服务
restart_services() {
    log_info "重启服务..."
    systemctl restart sing-box
    systemctl restart nginx
    pause
}

# 查看日志菜单
view_logs_menu() {
    log_info "查看日志功能开发中..."
    pause
}

# 服务配置菜单
service_config_menu() {
    log_info "服务配置功能开发中..."
    pause
}

# 自动启动菜单
autostart_menu() {
    log_info "自动启动设置功能开发中..."
    pause
}

# 自定义安装菜单
custom_install_menu() {
    log_info "自定义安装功能开发中..."
    pause
}

# 卸载菜单
uninstall_menu() {
    log_info "卸载功能开发中..."
    pause
}

# 主函数
main() {
    case "${1:-menu}" in
        "menu")
            show_main_menu
            ;;
        "install")
            install_menu
            ;;
        "subscription")
            subscription_menu
            ;;
        "service")
            service_menu
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