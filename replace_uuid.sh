#!/bin/bash
set -euo pipefail

# UUID替换脚本 - Linux版本
# 用法: ./replace_uuid.sh [文件路径] [可选:行号]

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

# 默认参数
FILE_PATH="${1:-config.json}"
LINE_NUMBER="${2:-0}"

# 生成新的UUID
generate_uuid() {
    if command -v uuidgen &> /dev/null; then
        uuidgen | tr '[:upper:]' '[:lower:]'
    elif [[ -f /proc/sys/kernel/random/uuid ]]; then
        cat /proc/sys/kernel/random/uuid
    else
        # 备用方法：使用随机数生成UUID
        python3 -c "import uuid; print(str(uuid.uuid4()))" 2>/dev/null || \
        python -c "import uuid; print(str(uuid.uuid4()))" 2>/dev/null || \
        {
            log_error "无法生成UUID，请安装uuidgen或python"
            exit 1
        }
    fi
}

# 验证UUID格式
validate_uuid() {
    local uuid="$1"
    if [[ $uuid =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
        return 0
    else
        return 1
    fi
}

# 替换指定行的UUID
replace_line_uuid() {
    local file_path="$1"
    local line_number="$2"
    local new_uuid="$3"
    
    if [[ ! -f "$file_path" ]]; then
        log_error "文件不存在: $file_path"
        return 1
    fi
    
    local total_lines
    total_lines=$(wc -l < "$file_path")
    
    if [[ $line_number -gt $total_lines ]]; then
        log_error "行号超出文件范围 (文件共 $total_lines 行)"
        return 1
    fi
    
    local line_content
    line_content=$(sed -n "${line_number}p" "$file_path")
    
    if [[ $line_content =~ \"uuid\":[[:space:]]*\"([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\" ]]; then
        local old_uuid="${BASH_REMATCH[1]}"
        
        # 创建备份
        cp "$file_path" "${file_path}.backup.$(date +%Y%m%d_%H%M%S)"
        
        # 替换UUID
        sed -i "${line_number}s/$old_uuid/$new_uuid/g" "$file_path"
        
        log_success "第 $line_number 行的UUID已替换"
        log_info "   旧UUID: $old_uuid"
        log_info "   新UUID: $new_uuid"
        return 0
    else
        log_error "第 $line_number 行未找到有效的UUID格式"
        return 1
    fi
}

# 替换所有UUID
replace_all_uuids() {
    local file_path="$1"
    local new_uuid="$2"
    
    if [[ ! -f "$file_path" ]]; then
        log_error "文件不存在: $file_path"
        return 1
    fi
    
    # 查找所有UUID
    local uuid_pattern='"uuid":[[:space:]]*"([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})"'
    local found_uuids
    found_uuids=$(grep -oP "$uuid_pattern" "$file_path" | grep -oP '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' || true)
    
    if [[ -z "$found_uuids" ]]; then
        log_error "文件中未找到UUID格式"
        return 1
    fi
    
    # 创建备份
    cp "$file_path" "${file_path}.backup.$(date +%Y%m%d_%H%M%S)"
    
    local replaced_count=0
    while IFS= read -r old_uuid; do
        if [[ -n "$old_uuid" ]]; then
            sed -i "s/$old_uuid/$new_uuid/g" "$file_path"
            log_info "   替换UUID: $old_uuid → $new_uuid"
            ((replaced_count++))
        fi
    done <<< "$found_uuids"
    
    log_success "成功替换 $replaced_count 个UUID"
    return 0
}

# 显示使用说明
show_usage() {
    echo
    log_info "📖 使用说明:"
    echo "   替换所有UUID:     ./replace_uuid.sh"
    echo "   替换指定文件:     ./replace_uuid.sh config.json"
    echo "   替换指定行:       ./replace_uuid.sh config.json 10"
    echo
    echo "   支持的文件格式: JSON配置文件"
    echo "   自动备份: 替换前会创建 .backup.时间戳 备份文件"
}

# 主函数
main() {
    log_info "UUID替换工具 - Linux版本"
    echo "=========================================="
    
    # 生成新UUID
    local new_uuid
    new_uuid=$(generate_uuid)
    
    if ! validate_uuid "$new_uuid"; then
        log_error "生成的UUID格式无效: $new_uuid"
        exit 1
    fi
    
    log_info "生成新UUID: $new_uuid"
    
    # 检查文件是否存在
    if [[ ! -f "$FILE_PATH" ]]; then
        log_error "文件不存在: $FILE_PATH"
        show_usage
        exit 1
    fi
    
    # 根据参数执行相应操作
    if [[ $LINE_NUMBER -gt 0 ]]; then
        # 替换指定行
        replace_line_uuid "$FILE_PATH" "$LINE_NUMBER" "$new_uuid"
    else
        # 替换所有UUID
        replace_all_uuids "$FILE_PATH" "$new_uuid"
    fi
    
    show_usage
}

# 执行主函数
main "$@"