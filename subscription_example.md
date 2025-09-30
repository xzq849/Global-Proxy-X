# 机场订阅使用示例

## 快速开始

### 1. 添加机场订阅
```bash
# 添加订阅（替换为你的机场订阅链接）
proxy-manager sub add "https://example.com/api/v1/client/subscribe?token=your_token" "我的机场"
```

### 2. 应用订阅
```bash
# 应用订阅，将节点导入到sing-box配置
proxy-manager sub apply "我的机场"
```

### 3. 重启服务
```bash
# 重启代理服务使配置生效
proxy-manager restart
```

## 常用命令

### 订阅管理
```bash
# 查看所有订阅
proxy-manager sub list

# 更新指定订阅
proxy-manager sub update "我的机场"

# 更新所有订阅
proxy-manager sub update-all

# 删除订阅
proxy-manager sub remove "我的机场"

# 测试订阅连接
proxy-manager sub test "我的机场"
```

### 服务管理
```bash
# 查看服务状态
proxy-manager status

# 查看实时日志
proxy-manager logs

# 重启服务
proxy-manager restart
```

## 支持的协议

- **VMess**: 支持WebSocket、TCP、gRPC传输
- **Shadowsocks**: 支持各种加密方式
- **Trojan**: 支持TLS传输
- **VLESS**: 支持Reality、Vision等新特性

## 订阅格式

支持以下订阅格式：
- Base64编码的节点列表
- Clash配置格式
- V2Ray订阅格式
- Shadowsocks SIP008格式

## 注意事项

1. **订阅更新**: 建议定期更新订阅以获取最新节点
2. **节点测试**: 应用订阅后可通过面板测试节点连通性
3. **配置备份**: 系统会自动备份配置文件到 `/etc/sing-box/backup/`
4. **日志查看**: 如遇问题可查看 `/var/log/sing-box/` 下的日志文件

## 故障排除

### 订阅无法下载
```bash
# 检查网络连接
curl -I "你的订阅链接"

# 检查DNS解析
nslookup 订阅域名
```

### 节点无法连接
```bash
# 测试节点连通性
proxy-manager sub test "机场名称"

# 查看详细日志
journalctl -u sing-box -f
```

### 配置文件错误
```bash
# 验证配置文件
sing-box check -c /etc/sing-box/config.json

# 恢复备份配置
cp /etc/sing-box/backup/config.json.bak /etc/sing-box/config.json
```

## 高级用法

### 自动更新订阅
创建定时任务自动更新订阅：
```bash
# 编辑crontab
crontab -e

# 添加以下行（每6小时更新一次）
0 */6 * * * /usr/local/bin/proxy-manager sub update-all
```

### 多机场负载均衡
```bash
# 添加多个机场
proxy-manager sub add "机场1订阅链接" "机场1"
proxy-manager sub add "机场2订阅链接" "机场2"

# 分别应用
proxy-manager sub apply "机场1"
proxy-manager sub apply "机场2"
```

### 自定义分组
订阅管理器会自动根据地区和协议对节点进行分组：
- 🇭🇰 香港节点
- 🇺🇸 美国节点
- 🇯🇵 日本节点
- 🇸🇬 新加坡节点
- ⚡ 自动选择
- 🎯 手动选择