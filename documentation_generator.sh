#!/bin/bash
set -euo pipefail

# 文档生成器脚本
# 用于自动生成项目文档

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

# 文档目录配置
DOCS_DIR="$SCRIPT_DIR/docs"
README_FILE="$SCRIPT_DIR/README.md"
INSTALL_DOC_FILE="$DOCS_DIR/INSTALL.md"
CONFIG_DOC_FILE="$DOCS_DIR/CONFIGURATION.md"
TROUBLESHOOTING_DOC_FILE="$DOCS_DIR/TROUBLESHOOTING.md"
API_DOC_FILE="$DOCS_DIR/API.md"
CHANGELOG_FILE="$DOCS_DIR/CHANGELOG.md"

# 创建文档目录
create_docs_directory() {
    log_info "创建文档目录..."
    mkdir -p "$DOCS_DIR"
    log_success "文档目录创建完成"
}

# 生成主README文件
generate_main_readme() {
    log_info "生成主README文件..."
    
    cat > "$README_FILE" << 'EOF'
# Sing-box 全局代理管理系统

一个功能完整的 sing-box 代理服务管理系统，提供自动化安装、配置管理、订阅更新等功能。

## 功能特性

- 🚀 一键自动安装 sing-box
- 📝 智能配置管理
- 🔄 订阅链接自动更新
- 🛡️ 安全加固配置
- 📊 性能优化工具
- 🎯 用户友好界面
- 🧪 完整测试套件

## 快速开始

```bash
# 克隆项目
git clone <repository-url>
cd sing-box-manager

# 运行安装脚本
sudo ./install_all.sh

# 启动用户界面
./user_interface.sh
```

## 文档

- [安装指南](INSTALL.md)
- [配置说明](CONFIG.md)
- [故障排除](TROUBLESHOOTING.md)
- [API文档](API.md)
- [更新日志](CHANGELOG.md)

## 系统要求

- Linux 系统 (Ubuntu 18.04+, CentOS 7+, Debian 9+)
- 512MB+ 内存
- 1GB+ 磁盘空间
- curl, jq 工具

## 许可证

MIT License
EOF

    log_success "主README文件生成完成"
}

# 生成安装文档
generate_installation_doc() {
    log_info "生成安装文档..."
    
    cat > "$INSTALL_DOC_FILE" << 'EOF'
# 安装指南

本文档详细说明了如何安装和配置 sing-box 全局代理管理系统。

## 系统要求

### 操作系统
- Ubuntu 18.04 或更高版本
- CentOS 7 或更高版本
- Debian 9 或更高版本

### 硬件要求
- 内存: 512MB 或更多
- 磁盘空间: 1GB 或更多
- 网络: 稳定的互联网连接

### 软件依赖
- curl
- jq
- systemctl (systemd)

## 安装步骤

### 1. 下载项目

```bash
git clone <repository-url>
cd sing-box-manager
```

### 2. 运行安装脚本

```bash
sudo ./install_all.sh
```

### 3. 验证安装

```bash
# 检查服务状态
systemctl status sing-box

# 运行测试套件
./test_suite.sh
```

## 配置

安装完成后，您可以通过以下方式进行配置：

### 使用用户界面
```bash
./user_interface.sh
```

### 手动配置
编辑配置文件 `/etc/sing-box/config.json`

## 故障排除

如果安装过程中遇到问题，请参考 [故障排除文档](TROUBLESHOOTING.md)。
EOF

    log_success "安装文档生成完成"
}

# 显示帮助信息
show_help() {
    echo "文档生成器使用说明:"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  all          生成所有文档 (默认)"
    echo "  readme       仅生成主 README 文件"
    echo "  install      仅生成安装文档"
    echo "  help         显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 all       # 生成所有文档"
    echo "  $0 readme    # 仅生成 README"
}

# 主函数
main() {
    case "${1:-all}" in
        "all")
            create_docs_directory
            generate_main_readme
            generate_installation_doc
            log_success "所有文档生成完成！"
            ;;
        "readme")
            generate_main_readme
            ;;
        "install")
            create_docs_directory
            generate_installation_doc
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