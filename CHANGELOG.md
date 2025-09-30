# 更新日志

本文档记录了 sing-box + zashboard 全局代理服务的所有重要变更。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/)，
并且本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [未发布]

### 新增
- 完整的项目文档体系
- 详细的安装指南 (INSTALL.md)
- 配置说明文档 (CONFIG.md)
- 故障排除指南 (TROUBLESHOOTING.md)
- RESTful API 文档 (API.md)
- 标准化的脚本代码结构

### 改进
- 增强了 README.md 的结构和内容
- 优化了安装脚本的错误处理
- 改进了批量导入功能
- 增强了镜像源测试脚本

## [1.2.0] - 2024-01-15

### 新增
- 🎯 批量导入节点功能 (`batch_import.sh`)
- 📊 镜像源测试和性能评估 (`test_mirror_sources.sh`)
- 🔧 增强的配置验证功能
- 📈 实时流量监控和统计
- 🌐 多协议支持 (VMess, Shadowsocks, Trojan, Hysteria)
- 🔄 自动订阅更新机制
- 🛡️ 安全配置选项

### 改进
- ⚡ 优化了安装脚本性能
- 🔍 增强了错误诊断功能
- 📱 改进了 Web 界面响应式设计
- 🔐 加强了 API 安全性
- 📝 完善了日志记录系统

### 修复
- 🐛 修复了端口冲突检测问题
- 🔧 解决了配置文件权限问题
- 🌐 修复了 DNS 解析异常
- 📊 解决了统计数据不准确的问题

## [1.1.0] - 2024-01-01

### 新增
- 🚀 一键安装脚本
- 🎛️ Web 管理面板 (zashboard)
- 📡 Clash API 支持
- 🔄 订阅管理功能
- 📊 流量统计和监控
- 🛠️ 系统服务管理

### 改进
- 📖 完善了文档说明
- 🔧 优化了配置文件结构
- 🚀 提升了启动速度
- 🔍 增强了日志输出

### 修复
- 🐛 修复了服务启动失败问题
- 🔧 解决了配置解析错误
- 🌐 修复了网络连接异常

## [1.0.0] - 2023-12-15

### 新增
- 🎉 首次发布
- 🌐 基于 sing-box 的代理服务
- 🔧 基础配置管理
- 📱 支持多种客户端
- 🛡️ TUN 模式支持
- 🔄 HTTP/SOCKS5 代理

### 功能特性
- ✅ 支持主流代理协议
- ✅ 自动路由规则
- ✅ DNS 分流功能
- ✅ 系统级代理
- ✅ 跨平台支持

---

## 版本说明

### 版本号格式

本项目使用语义化版本号：`主版本号.次版本号.修订号`

- **主版本号**：不兼容的 API 修改
- **次版本号**：向下兼容的功能性新增
- **修订号**：向下兼容的问题修正

### 变更类型

- **新增** (Added)：新功能
- **改进** (Changed)：对现有功能的修改
- **弃用** (Deprecated)：即将移除的功能
- **移除** (Removed)：已移除的功能
- **修复** (Fixed)：错误修复
- **安全** (Security)：安全相关修复

### 发布周期

- **主版本**：根据重大功能更新发布
- **次版本**：每月发布，包含新功能和改进
- **修订版本**：根据需要发布，主要包含错误修复

---

## 升级指南

### 从 1.1.x 升级到 1.2.x

1. **备份配置**：
   ```bash
   proxy-manager backup create
   ```

2. **停止服务**：
   ```bash
   proxy-manager stop
   ```

3. **更新程序**：
   ```bash
   # 下载新版本
   curl -fsSL https://raw.githubusercontent.com/your-repo/main/setup_zashboard.sh | bash
   ```

4. **迁移配置**：
   ```bash
   # 自动迁移配置文件
   proxy-manager config migrate
   ```

5. **启动服务**：
   ```bash
   proxy-manager start
   ```

6. **验证升级**：
   ```bash
   proxy-manager status
   proxy-manager version
   ```

### 从 1.0.x 升级到 1.1.x

1. **重要提醒**：此版本包含重大配置文件格式变更

2. **升级步骤**：
   ```bash
   # 备份旧配置
   cp /etc/sing-box/config.json /etc/sing-box/config.json.backup
   
   # 运行升级脚本
   curl -fsSL https://raw.githubusercontent.com/your-repo/main/upgrade.sh | bash
   
   # 验证配置
   proxy-manager config validate
   ```

3. **配置迁移**：
   - 旧版本的 `outbounds` 配置需要手动调整
   - 新增的 `experimental.clash_api` 配置会自动添加
   - DNS 配置格式有所变化，请参考新版本文档

---

## 已知问题

### 当前版本 (1.2.0)

- 🔍 **问题**：在某些 ARM 设备上可能出现性能问题
  - **影响**：代理连接延迟较高
  - **解决方案**：正在优化，预计在 1.2.1 版本修复
  - **临时方案**：可以通过调整 `tcp_fast_open` 参数缓解

- 🔍 **问题**：Docker 环境下的 TUN 模式支持有限
  - **影响**：无法在容器中使用 TUN 模式
  - **解决方案**：需要宿主机支持，或使用 HTTP/SOCKS5 模式

### 历史问题

#### 1.1.0
- ✅ **已修复**：配置文件权限问题导致服务启动失败
- ✅ **已修复**：Web 界面在移动设备上显示异常

#### 1.0.0
- ✅ **已修复**：首次安装时可能出现依赖缺失
- ✅ **已修复**：某些发行版上的 systemd 服务配置问题

---

## 贡献指南

### 报告问题

在报告问题时，请提供以下信息：

1. **版本信息**：
   ```bash
   proxy-manager version
   ```

2. **系统信息**：
   ```bash
   uname -a
   cat /etc/os-release
   ```

3. **错误日志**：
   ```bash
   proxy-manager logs --tail 50
   ```

4. **配置信息**（请移除敏感信息）：
   ```bash
   proxy-manager config show --sanitized
   ```

### 提交变更

1. Fork 项目仓库
2. 创建功能分支：`git checkout -b feature/amazing-feature`
3. 提交变更：`git commit -m 'Add some amazing feature'`
4. 推送分支：`git push origin feature/amazing-feature`
5. 创建 Pull Request

### 代码规范

- 遵循现有代码风格
- 添加适当的注释
- 更新相关文档
- 添加测试用例（如适用）

---

## 致谢

感谢以下项目和贡献者：

- [sing-box](https://github.com/SagerNet/sing-box) - 核心代理服务
- [zashboard](https://github.com/Zephyruso/zashboard) - Web 管理界面
- 所有提交 Issue 和 PR 的贡献者

---

## 许可证

本项目采用 [MIT 许可证](LICENSE)。

---

**注意**：本变更日志遵循 [Keep a Changelog](https://keepachangelog.com/) 格式。如有疑问，请查看项目文档或提交 Issue。