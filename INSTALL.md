# 详细安装指南

本文档提供 sing-box + zashboard 全局代理服务的详细安装指南。

## 📋 安装前准备

### 1. 系统检查

在开始安装前，请确认您的系统满足以下要求：

```bash
# 检查操作系统版本
cat /etc/os-release

# 检查系统架构
uname -m

# 检查可用内存
free -h

# 检查可用磁盘空间
df -h

# 检查网络连接
ping -c 4 google.com
```

### 2. 更新系统

```bash
# Ubuntu/Debian
sudo apt update && sudo apt upgrade -y

# CentOS/RHEL
sudo yum update -y

# Fedora
sudo dnf update -y
```

### 3. 安装基础依赖

```bash
# Ubuntu/Debian
sudo apt install -y curl wget unzip systemd iptables

# CentOS/RHEL
sudo yum install -y curl wget unzip systemd iptables

# Fedora
sudo dnf install -y curl wget unzip systemd iptables
```

## 🚀 安装方式选择

### 方式一：一键自动安装（推荐新手）

这是最简单的安装方式，适合大多数用户：

```bash
# 下载并运行安装脚本
curl -fsSL https://raw.githubusercontent.com/your-repo/install_all.sh | sudo bash

# 或者分步执行
wget https://raw.githubusercontent.com/your-repo/install_all.sh
chmod +x install_all.sh
sudo ./install_all.sh
```

**安装过程说明**：
1. 脚本会自动检测系统环境
2. 下载适合您系统的 sing-box 二进制文件
3. 创建必要的目录和配置文件
4. 安装和配置 Web 面板
5. 设置系统服务并启动

### 方式二：分步手动安装（推荐高级用户）

如果您需要更精细的控制，可以分步安装：

#### 步骤 1：安装 sing-box 内核

```bash
# 运行 sing-box 安装脚本
sudo ./install_singbox.sh

# 验证安装
sing-box version
```

#### 步骤 2：配置 sing-box

```bash
# 创建配置目录
sudo mkdir -p /etc/sing-box

# 生成基础配置文件
sudo ./generate_config.sh

# 验证配置文件
sing-box check -c /etc/sing-box/config.json
```

#### 步骤 3：安装 Web 面板

```bash
# 运行面板安装脚本
sudo ./setup_zashboard.sh

# 验证面板安装
curl -I http://localhost
```

#### 步骤 4：配置系统服务

```bash
# 启用并启动服务
sudo systemctl enable sing-box
sudo systemctl start sing-box

# 检查服务状态
sudo systemctl status sing-box
```

### 方式三：Docker 安装

适合熟悉 Docker 的用户：

#### 使用 Docker Compose（推荐）

1. **创建项目目录**：
```bash
mkdir sing-box-proxy && cd sing-box-proxy
```

2. **创建 docker-compose.yml**：
```yaml
version: '3.8'

services:
  sing-box:
    image: your-repo/sing-box-zashboard:latest
    container_name: sing-box-proxy
    restart: unless-stopped
    ports:
      - "80:80"       # Web 面板
      - "7890:7890"   # 代理端口
      - "9090:9090"   # API 端口
    volumes:
      - ./config:/etc/sing-box
      - ./logs:/var/log/sing-box
      - ./cache:/var/cache/sing-box
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Asia/Shanghai
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun
```

3. **启动服务**：
```bash
docker-compose up -d
```

#### 使用 Docker 命令

```bash
# 创建数据目录
mkdir -p ./config ./logs ./cache

# 运行容器
docker run -d \
  --name sing-box-proxy \
  --restart unless-stopped \
  -p 80:80 \
  -p 7890:7890 \
  -p 9090:9090 \
  -v ./config:/etc/sing-box \
  -v ./logs:/var/log/sing-box \
  -v ./cache:/var/cache/sing-box \
  --cap-add NET_ADMIN \
  --device /dev/net/tun \
  your-repo/sing-box-zashboard:latest
```

## 🔧 安装后配置

### 1. 首次访问设置

安装完成后，在浏览器中访问：`http://your-server-ip`

**如果无法访问，请检查**：
- 防火墙设置
- 端口是否被占用
- 服务是否正常运行

### 2. 配置 API 连接

在 Web 面板中配置 Clash API：
- **API 地址**：`http://your-server-ip:9090`
- **API 密钥**：查看 `/etc/sing-box/secret.key`

```bash
# 查看 API 密钥
sudo cat /etc/sing-box/secret.key
```

### 3. 添加第一个代理节点

```bash
# 使用脚本添加 VMess 节点
sudo ./add_proxy_nodes.sh vmess "测试节点" "example.com" 443 "your-uuid" 0 "auto"

# 或者添加机场订阅
proxy-manager sub add "https://your-subscription-url" "机场名称"
```

## 🔍 安装验证

### 1. 检查服务状态

```bash
# 检查 sing-box 服务
sudo systemctl status sing-box

# 检查 nginx 服务（如果使用）
sudo systemctl status nginx

# 检查端口监听
sudo netstat -tlnp | grep -E '(80|7890|9090)'
```

### 2. 测试代理功能

```bash
# 测试 HTTP 代理
curl -x http://127.0.0.1:7890 http://httpbin.org/ip

# 测试 SOCKS5 代理
curl --socks5 127.0.0.1:7890 http://httpbin.org/ip
```

### 3. 检查 Web 面板

```bash
# 测试面板访问
curl -I http://localhost

# 测试 API 接口
curl -H "Authorization: Bearer $(cat /etc/sing-box/secret.key)" \
     http://localhost:9090/version
```

## 🛠️ 故障排除

### 常见问题及解决方案

#### 1. 安装脚本下载失败

```bash
# 使用镜像源
export GITHUB_PROXY="https://ghproxy.com/"
curl -fsSL ${GITHUB_PROXY}https://raw.githubusercontent.com/your-repo/install_all.sh | sudo bash
```

#### 2. 端口被占用

```bash
# 查看端口占用
sudo lsof -i :80
sudo lsof -i :7890
sudo lsof -i :9090

# 修改配置使用其他端口
sudo ./install_all.sh --custom-port 8080 --api-port 9091 --proxy-port 7891
```

#### 3. 权限问题

```bash
# 确保使用 root 权限
sudo su -

# 检查文件权限
ls -la /etc/sing-box/
ls -la /var/www/zashboard/
```

#### 4. 防火墙问题

```bash
# Ubuntu/Debian (ufw)
sudo ufw allow 80
sudo ufw allow 7890
sudo ufw allow 9090

# CentOS/RHEL (firewalld)
sudo firewall-cmd --permanent --add-port=80/tcp
sudo firewall-cmd --permanent --add-port=7890/tcp
sudo firewall-cmd --permanent --add-port=9090/tcp
sudo firewall-cmd --reload
```

#### 5. 服务启动失败

```bash
# 查看详细错误信息
sudo journalctl -u sing-box -f

# 检查配置文件语法
sing-box check -c /etc/sing-box/config.json

# 重新生成配置
sudo ./generate_config.sh --reset
```

## 📞 获取帮助

如果遇到问题，可以：

1. **查看日志**：
```bash
sudo journalctl -u sing-box -f
tail -f /var/log/sing-box/sing-box.log
```

2. **运行诊断**：
```bash
proxy-manager diagnose
```

3. **提交 Issue**：
   - 访问项目 GitHub 页面
   - 提供详细的错误信息和系统环境
   - 包含相关日志文件

4. **社区支持**：
   - 查看项目文档
   - 搜索已有的 Issues
   - 参与社区讨论

## 🔄 卸载指南

如果需要完全卸载：

```bash
# 停止服务
sudo systemctl stop sing-box
sudo systemctl disable sing-box

# 删除文件
sudo rm -rf /etc/sing-box
sudo rm -rf /var/www/zashboard
sudo rm -rf /var/log/sing-box
sudo rm -rf /var/cache/sing-box
sudo rm /usr/local/bin/sing-box
sudo rm /usr/local/bin/proxy-manager

# 删除系统服务文件
sudo rm /etc/systemd/system/sing-box.service
sudo systemctl daemon-reload
```

---

**注意**：安装过程中请确保网络连接稳定，并使用具有管理员权限的账户进行操作。