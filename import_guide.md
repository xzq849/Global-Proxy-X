# 批量导入配置指南

## 📁 配置文件说明

### 1. subscriptions.conf - 机场订阅配置
用于批量管理机场订阅链接。

**格式**: `订阅名称|订阅链接|是否启用|备注`

**示例**:
```
# 机场订阅配置文件
MyAirport|https://example.com/api/v1/client/subscribe?token=abc123|true|主要机场
BackupAirport|https://backup.example.com/subscribe/def456|false|备用机场
SpeedAirport|https://speed.example.com/sub?key=ghi789|true|高速机场
```

**字段说明**:
- **订阅名称**: 自定义的机场名称，用于识别
- **订阅链接**: 机场提供的订阅URL
- **是否启用**: `true`启用，`false`禁用
- **备注**: 可选，用于说明

### 2. nodes.conf - 单个节点配置
用于手动添加单个代理节点。

#### VMess 节点格式
```
vmess|节点名称|服务器地址|端口|用户ID|额外ID|加密方式|网络类型|路径|备注
```

**示例**:
```
vmess|香港节点1|hk1.example.com|443|12345678-1234-1234-1234-123456789abc|0|auto|ws|/path|高速节点
vmess|美国节点1|us1.example.com|80|87654321-4321-4321-4321-210987654321|0|aes-128-gcm|tcp||稳定节点
```

#### Shadowsocks 节点格式
```
ss|节点名称|服务器地址|端口|密码|加密方式|备注
```

**示例**:
```
ss|日本节点1|jp1.example.com|8388|mypassword123|aes-256-gcm|低延迟
ss|新加坡节点1|sg1.example.com|443|secretpass456|chacha20-ietf-poly1305|高速
```

#### Trojan 节点格式
```
trojan|节点名称|服务器地址|端口|密码|备注
```

**示例**:
```
trojan|德国节点1|de1.example.com|443|trojanpass123|稳定连接
trojan|英国节点1|uk1.example.com|443|trojanpass456|解锁专用
```

## 🚀 使用方法

### 1. 编辑配置文件
```bash
# 编辑订阅配置
nano subscriptions.conf

# 编辑节点配置
nano nodes.conf
```

### 2. 批量导入
```bash
# 导入所有配置（订阅+节点）
./batch_import.sh

# 仅导入订阅
./batch_import.sh --subscriptions

# 仅导入节点
./batch_import.sh --nodes

# 导入并自动重启服务
./batch_import.sh --all --restart
```

### 3. 查看导入结果
```bash
# 查看订阅列表
proxy-manager sub list

# 查看服务状态
proxy-manager status

# 查看配置
proxy-manager config
```

## 📋 完整操作流程

### 步骤1: 准备配置文件
1. 编辑 `subscriptions.conf`，添加您的机场订阅
2. 编辑 `nodes.conf`，添加单个节点（可选）

### 步骤2: 批量导入
```bash
# 一键导入所有配置并重启服务
./batch_import.sh --all --restart
```

### 步骤3: 验证配置
```bash
# 检查服务状态
proxy-manager status

# 测试代理连接
curl --proxy http://127.0.0.1:7890 https://www.google.com
```

## 🔧 高级用法

### 自动化导入
创建定时任务，定期更新订阅：
```bash
# 编辑crontab
crontab -e

# 添加定时任务（每天凌晨2点更新）
0 2 * * * cd /path/to/proxy && ./batch_import.sh --subscriptions --restart
```

### 分环境配置
```bash
# 生产环境配置
cp subscriptions.conf subscriptions.prod.conf
cp nodes.conf nodes.prod.conf

# 测试环境配置
cp subscriptions.conf subscriptions.test.conf
cp nodes.conf nodes.test.conf
```

### 备份配置
```bash
# 备份当前配置
cp subscriptions.conf subscriptions.conf.bak
cp nodes.conf nodes.conf.bak

# 恢复配置
cp subscriptions.conf.bak subscriptions.conf
cp nodes.conf.bak nodes.conf
```

## ⚠️ 注意事项

1. **格式要求**:
   - 使用 `|` 分隔字段
   - 不要在字段中包含 `|` 字符
   - 以 `#` 开头的行为注释

2. **安全建议**:
   - 不要在配置文件中使用明文密码
   - 定期更换订阅链接
   - 备份重要配置

3. **性能优化**:
   - 禁用不需要的订阅（设置为 false）
   - 定期清理无效节点
   - 监控服务资源使用

4. **故障排除**:
   - 检查配置文件格式
   - 验证订阅链接有效性
   - 查看服务日志

## 📞 技术支持

如遇问题，请检查：
1. 配置文件格式是否正确
2. 网络连接是否正常
3. 服务是否正常运行
4. 查看详细日志信息

```bash
# 查看详细日志
journalctl -u sing-box -f

# 测试配置文件
sing-box check -c /etc/sing-box/config.json
```