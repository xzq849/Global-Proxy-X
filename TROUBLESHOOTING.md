# 故障排除指南

本文档提供 sing-box + zashboard 全局代理服务常见问题的解决方案。

## 🔍 快速诊断

### 自动诊断工具

```bash
# 运行完整系统诊断
proxy-manager diagnose

# 检查服务状态
proxy-manager health-check

# 测试网络连接
proxy-manager diagnose --target google.com --timeout 10s
```

### 手动检查清单

```bash
# 1. 检查服务状态
sudo systemctl status sing-box
sudo systemctl status nginx

# 2. 检查端口监听
sudo netstat -tlnp | grep -E '(80|7890|9090)'

# 3. 检查配置文件
sing-box check -c /etc/sing-box/config.json

# 4. 查看最新日志
sudo journalctl -u sing-box -n 50

# 5. 测试代理连接
curl -x http://127.0.0.1:7890 http://httpbin.org/ip
```

## 🚨 常见问题及解决方案

### 1. 安装相关问题

#### 问题：安装脚本下载失败
```
Error: Failed to download installation script
```

**解决方案**：
```bash
# 方法1：使用镜像源
export GITHUB_PROXY="https://ghproxy.com/"
curl -fsSL ${GITHUB_PROXY}https://raw.githubusercontent.com/your-repo/install_all.sh | sudo bash

# 方法2：手动下载
wget https://github.com/your-repo/archive/main.zip
unzip main.zip && cd your-repo-main
sudo ./install_all.sh

# 方法3：使用备用源
curl -fsSL https://gitee.com/your-repo/install_all.sh | sudo bash
```

#### 问题：权限不足
```
Permission denied
```

**解决方案**：
```bash
# 确保使用 root 权限
sudo su -

# 或者为脚本添加执行权限
chmod +x install_all.sh
sudo ./install_all.sh
```

#### 问题：依赖包安装失败
```
Package not found or installation failed
```

**解决方案**：
```bash
# Ubuntu/Debian
sudo apt update
sudo apt install -y curl wget unzip systemd

# CentOS/RHEL
sudo yum update
sudo yum install -y curl wget unzip systemd

# 检查网络连接
ping -c 4 8.8.8.8
```

### 2. 服务启动问题

#### 问题：sing-box 服务无法启动
```
Failed to start sing-box.service
```

**解决方案**：
```bash
# 1. 查看详细错误信息
sudo journalctl -u sing-box -f

# 2. 检查配置文件语法
sing-box check -c /etc/sing-box/config.json

# 3. 检查文件权限
sudo chown -R root:root /etc/sing-box/
sudo chmod 644 /etc/sing-box/config.json

# 4. 重新生成配置文件
sudo ./generate_config.sh --reset

# 5. 手动启动测试
sudo sing-box run -c /etc/sing-box/config.json
```

#### 问题：端口被占用
```
bind: address already in use
```

**解决方案**：
```bash
# 1. 查看端口占用情况
sudo lsof -i :7890
sudo lsof -i :9090
sudo lsof -i :80

# 2. 终止占用进程
sudo kill -9 <PID>

# 3. 或者修改配置使用其他端口
sudo nano /etc/sing-box/config.json
# 修改 listen_port 为其他可用端口

# 4. 重新安装并指定端口
sudo ./install_all.sh --proxy-port 7891 --api-port 9091
```

### 3. 网络连接问题

#### 问题：无法访问 Web 面板
```
This site can't be reached
```

**解决方案**：
```bash
# 1. 检查 nginx 服务状态
sudo systemctl status nginx

# 2. 检查防火墙设置
# Ubuntu/Debian
sudo ufw status
sudo ufw allow 80

# CentOS/RHEL
sudo firewall-cmd --list-ports
sudo firewall-cmd --permanent --add-port=80/tcp
sudo firewall-cmd --reload

# 3. 检查端口监听
sudo netstat -tlnp | grep :80

# 4. 测试本地访问
curl -I http://localhost

# 5. 检查 nginx 配置
sudo nginx -t
sudo systemctl reload nginx
```

#### 问题：代理连接失败
```
Proxy connection failed
```

**解决方案**：
```bash
# 1. 测试代理端口
telnet 127.0.0.1 7890

# 2. 检查 sing-box 日志
tail -f /var/log/sing-box/sing-box.log

# 3. 测试代理功能
curl -x http://127.0.0.1:7890 http://httpbin.org/ip

# 4. 检查节点配置
proxy-manager nodes list
proxy-manager nodes test

# 5. 重新启动服务
sudo systemctl restart sing-box
```

#### 问题：DNS 解析失败
```
DNS resolution failed
```

**解决方案**：
```bash
# 1. 检查 DNS 配置
nslookup google.com
dig google.com

# 2. 修改 DNS 服务器
sudo nano /etc/resolv.conf
# 添加：nameserver 8.8.8.8

# 3. 检查 sing-box DNS 配置
grep -A 10 '"dns"' /etc/sing-box/config.json

# 4. 重启网络服务
sudo systemctl restart systemd-resolved
```

### 4. 配置相关问题

#### 问题：配置文件语法错误
```
JSON syntax error
```

**解决方案**：
```bash
# 1. 验证 JSON 语法
sing-box check -c /etc/sing-box/config.json

# 2. 使用 JSON 验证工具
cat /etc/sing-box/config.json | jq .

# 3. 备份并重新生成配置
sudo cp /etc/sing-box/config.json /etc/sing-box/config.json.bak
sudo ./generate_config.sh

# 4. 使用配置模板
proxy-manager config template --type basic --output /etc/sing-box/config.json
```

#### 问题：节点无法连接
```
Outbound connection failed
```

**解决方案**：
```bash
# 1. 测试节点连通性
proxy-manager nodes test "节点名称"

# 2. 检查节点配置
proxy-manager nodes info "节点名称"

# 3. 验证节点参数
ping 节点服务器地址
telnet 节点服务器地址 端口

# 4. 更新节点信息
proxy-manager nodes update "节点名称"

# 5. 重新添加节点
proxy-manager nodes remove "节点名称"
sudo ./add_proxy_nodes.sh vmess "节点名称" "服务器" 端口 "UUID" 0 "auto"
```

### 5. 性能相关问题

#### 问题：代理速度慢
```
Slow proxy connection
```

**解决方案**：
```bash
# 1. 测试节点延迟
proxy-manager nodes test --latency

# 2. 检查系统资源使用
top
htop
proxy-manager system-info

# 3. 优化配置
proxy-manager optimize-config

# 4. 启用缓存
# 在配置文件中添加缓存设置
{
  "experimental": {
    "cache_file": {
      "enabled": true,
      "path": "/var/cache/sing-box/cache.db"
    }
  }
}

# 5. 调整并发连接数
# 修改系统限制
echo "* soft nofile 65536" >> /etc/security/limits.conf
echo "* hard nofile 65536" >> /etc/security/limits.conf
```

#### 问题：内存使用过高
```
High memory usage
```

**解决方案**：
```bash
# 1. 检查内存使用
proxy-manager memory
free -h

# 2. 清理缓存
proxy-manager clean-cache

# 3. 重启服务
sudo systemctl restart sing-box

# 4. 优化配置
# 减少日志级别
{
  "log": {
    "level": "warn"
  }
}

# 5. 限制缓存大小
{
  "experimental": {
    "cache_file": {
      "enabled": true,
      "cache_id": "main",
      "store_fakeip": false
    }
  }
}
```

### 6. 订阅相关问题

#### 问题：订阅更新失败
```
Subscription update failed
```

**解决方案**：
```bash
# 1. 检查订阅 URL
curl -I "订阅URL"

# 2. 手动更新订阅
proxy-manager sub update "订阅名称" --force

# 3. 检查网络连接
proxy-manager diagnose --target 订阅域名

# 4. 重新添加订阅
proxy-manager sub remove "订阅名称"
proxy-manager sub add "订阅URL" "新订阅名称"

# 5. 检查订阅格式
proxy-manager sub info "订阅名称"
```

#### 问题：节点导入失败
```
Node import failed
```

**解决方案**：
```bash
# 1. 检查订阅内容
proxy-manager sub test "订阅名称"

# 2. 验证节点格式
proxy-manager sub info "订阅名称" --verbose

# 3. 手动导入节点
proxy-manager sub apply "订阅名称" --force

# 4. 批量导入
sudo ./batch_import.sh --subscriptions subscriptions.conf --verbose

# 5. 检查导入日志
tail -f /var/log/sing-box/import.log
```

## 🔧 高级故障排除

### 1. 网络抓包分析

```bash
# 安装 tcpdump
sudo apt install tcpdump

# 抓取代理端口流量
sudo tcpdump -i any port 7890 -w proxy.pcap

# 抓取 API 端口流量
sudo tcpdump -i any port 9090 -w api.pcap

# 分析抓包文件
wireshark proxy.pcap
```

### 2. 系统调用跟踪

```bash
# 安装 strace
sudo apt install strace

# 跟踪 sing-box 进程
sudo strace -p $(pgrep sing-box) -o sing-box.trace

# 分析系统调用
grep -E "(connect|bind|listen)" sing-box.trace
```

### 3. 性能分析

```bash
# CPU 使用分析
top -p $(pgrep sing-box)

# 内存使用分析
pmap $(pgrep sing-box)

# 网络连接分析
ss -tuln | grep -E "(7890|9090)"
```

## 📞 获取帮助

### 1. 收集诊断信息

运行以下命令收集完整的诊断信息：

```bash
#!/bin/bash
# 创建诊断报告
REPORT_DIR="/tmp/sing-box-diagnosis-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$REPORT_DIR"

# 系统信息
uname -a > "$REPORT_DIR/system-info.txt"
cat /etc/os-release >> "$REPORT_DIR/system-info.txt"
free -h > "$REPORT_DIR/memory.txt"
df -h > "$REPORT_DIR/disk.txt"

# 服务状态
systemctl status sing-box > "$REPORT_DIR/service-status.txt"
systemctl status nginx >> "$REPORT_DIR/service-status.txt"

# 配置文件
cp /etc/sing-box/config.json "$REPORT_DIR/"
sing-box check -c /etc/sing-box/config.json > "$REPORT_DIR/config-check.txt"

# 日志文件
journalctl -u sing-box -n 100 > "$REPORT_DIR/service-logs.txt"
tail -n 100 /var/log/sing-box/sing-box.log > "$REPORT_DIR/app-logs.txt"

# 网络信息
netstat -tlnp > "$REPORT_DIR/network.txt"
ss -tuln >> "$REPORT_DIR/network.txt"

# 打包诊断报告
tar -czf "$REPORT_DIR.tar.gz" -C /tmp "$(basename $REPORT_DIR)"
echo "诊断报告已生成：$REPORT_DIR.tar.gz"
```

### 2. 提交问题报告

在提交 Issue 时，请包含以下信息：

1. **系统环境**：
   - 操作系统版本
   - 系统架构
   - sing-box 版本

2. **问题描述**：
   - 具体的错误信息
   - 重现步骤
   - 预期行为

3. **配置信息**：
   - 配置文件（隐藏敏感信息）
   - 安装方式
   - 自定义修改

4. **日志文件**：
   - 错误日志
   - 系统日志
   - 诊断报告

### 3. 社区支持

- **GitHub Issues**: 提交 Bug 报告和功能请求
- **文档**: 查看最新的文档和教程
- **讨论区**: 参与社区讨论和经验分享

---

**注意**：在提交问题报告时，请确保隐藏所有敏感信息（如密码、密钥、服务器地址等）。