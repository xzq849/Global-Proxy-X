# API 文档

本文档描述 sing-box + zashboard 全局代理服务的 RESTful API 接口。

## 🔐 认证

所有 API 请求都需要在请求头中包含认证信息：

```http
Authorization: Bearer YOUR_SECRET_KEY
```

获取 API 密钥：
```bash
# 查看 API 密钥
sudo cat /etc/sing-box/secret.key

# 或使用管理命令
proxy-manager config show-secret
```

## 📡 基础信息

### API 基础 URL

```
http://your-server-ip:9090
```

### 响应格式

所有 API 响应都使用 JSON 格式：

```json
{
  "success": true,
  "data": {},
  "message": "Success",
  "timestamp": "2024-01-01T12:00:00Z"
}
```

错误响应：
```json
{
  "success": false,
  "error": {
    "code": "ERROR_CODE",
    "message": "Error description"
  },
  "timestamp": "2024-01-01T12:00:00Z"
}
```

## 🔧 系统信息 API

### 获取版本信息

```http
GET /version
```

**响应示例**：
```json
{
  "success": true,
  "data": {
    "version": "1.8.0",
    "build_time": "2024-01-01T00:00:00Z",
    "go_version": "go1.21.0",
    "platform": "linux/amd64"
  }
}
```

### 获取系统状态

```http
GET /status
```

**响应示例**：
```json
{
  "success": true,
  "data": {
    "running": true,
    "uptime": 3600,
    "memory_usage": 52428800,
    "goroutines": 25,
    "connections": {
      "total": 150,
      "active": 45
    }
  }
}
```

### 获取配置信息

```http
GET /configs
```

**响应示例**：
```json
{
  "success": true,
  "data": {
    "mode": "rule",
    "port": 7890,
    "socks_port": 7891,
    "allow_lan": true,
    "log_level": "info"
  }
}
```

## 🌐 代理管理 API

### 获取代理列表

```http
GET /proxies
```

**响应示例**：
```json
{
  "success": true,
  "data": {
    "proxies": {
      "GLOBAL": {
        "type": "Selector",
        "now": "auto",
        "all": ["auto", "DIRECT", "🇺🇸 US-1", "🇭🇰 HK-1"]
      },
      "auto": {
        "type": "URLTest",
        "now": "🇺🇸 US-1",
        "all": ["🇺🇸 US-1", "🇭🇰 HK-1"],
        "history": [
          {
            "time": "2024-01-01T12:00:00Z",
            "delay": 120
          }
        ]
      }
    }
  }
}
```

### 切换代理节点

```http
PUT /proxies/{proxy_name}
```

**请求体**：
```json
{
  "name": "🇺🇸 US-1"
}
```

**响应示例**：
```json
{
  "success": true,
  "message": "Proxy switched successfully"
}
```

### 测试代理延迟

```http
GET /proxies/{proxy_name}/delay
```

**查询参数**：
- `timeout`: 超时时间（毫秒），默认 5000
- `url`: 测试 URL，默认 `http://www.gstatic.com/generate_204`

**响应示例**：
```json
{
  "success": true,
  "data": {
    "delay": 120,
    "timeout": false
  }
}
```

## 📊 流量统计 API

### 获取实时流量

```http
GET /traffic
```

**响应示例**：
```json
{
  "success": true,
  "data": {
    "up": 1024000,
    "down": 2048000
  }
}
```

### 获取连接信息

```http
GET /connections
```

**查询参数**：
- `limit`: 返回数量限制，默认 100
- `offset`: 偏移量，默认 0

**响应示例**：
```json
{
  "success": true,
  "data": {
    "downloadTotal": 1073741824,
    "uploadTotal": 536870912,
    "connections": [
      {
        "id": "uuid-1234",
        "metadata": {
          "network": "tcp",
          "type": "HTTP",
          "sourceIP": "192.168.1.100",
          "destinationPort": "443",
          "destinationIP": "1.1.1.1",
          "host": "example.com",
          "dnsMode": "fakeip",
          "processPath": "/usr/bin/curl",
          "specialProxy": "🇺🇸 US-1"
        },
        "upload": 1024,
        "download": 2048,
        "start": "2024-01-01T12:00:00Z",
        "chains": ["🇺🇸 US-1"],
        "rule": "DOMAIN-SUFFIX,example.com",
        "rulePayload": "example.com"
      }
    ]
  }
}
```

### 关闭连接

```http
DELETE /connections/{connection_id}
```

**响应示例**：
```json
{
  "success": true,
  "message": "Connection closed successfully"
}
```

### 关闭所有连接

```http
DELETE /connections
```

**响应示例**：
```json
{
  "success": true,
  "message": "All connections closed successfully"
}
```

## 📋 规则管理 API

### 获取规则列表

```http
GET /rules
```

**响应示例**：
```json
{
  "success": true,
  "data": {
    "rules": [
      {
        "type": "DOMAIN-SUFFIX",
        "payload": "google.com",
        "proxy": "🇺🇸 US-1"
      },
      {
        "type": "GEOIP",
        "payload": "CN",
        "proxy": "DIRECT"
      }
    ]
  }
}
```

### 添加规则

```http
POST /rules
```

**请求体**：
```json
{
  "type": "DOMAIN-SUFFIX",
  "payload": "example.com",
  "proxy": "🇺🇸 US-1"
}
```

### 删除规则

```http
DELETE /rules/{rule_id}
```

## 🔄 配置管理 API

### 重新加载配置

```http
POST /configs/reload
```

**响应示例**：
```json
{
  "success": true,
  "message": "Configuration reloaded successfully"
}
```

### 更新配置

```http
PUT /configs
```

**请求体**：
```json
{
  "mode": "global",
  "log_level": "debug",
  "allow_lan": true
}
```

### 获取地理位置数据库信息

```http
GET /configs/geo
```

**响应示例**：
```json
{
  "success": true,
  "data": {
    "geoip": {
      "version": "20240101",
      "size": 1048576,
      "last_updated": "2024-01-01T00:00:00Z"
    },
    "geosite": {
      "version": "20240101",
      "size": 2097152,
      "last_updated": "2024-01-01T00:00:00Z"
    }
  }
}
```

## 📡 DNS 管理 API

### 查询 DNS

```http
GET /dns/query
```

**查询参数**：
- `name`: 域名（必需）
- `type`: 记录类型，默认 A

**响应示例**：
```json
{
  "success": true,
  "data": {
    "name": "google.com",
    "type": "A",
    "ttl": 300,
    "data": "172.217.14.206"
  }
}
```

### 清空 DNS 缓存

```http
DELETE /dns/cache
```

**响应示例**：
```json
{
  "success": true,
  "message": "DNS cache cleared successfully"
}
```

## 🔍 日志管理 API

### 获取日志

```http
GET /logs
```

**查询参数**：
- `level`: 日志级别（debug, info, warn, error）
- `limit`: 返回数量限制，默认 100
- `since`: 开始时间（ISO 8601 格式）

**响应示例**：
```json
{
  "success": true,
  "data": {
    "logs": [
      {
        "time": "2024-01-01T12:00:00Z",
        "level": "info",
        "message": "HTTP connection established",
        "metadata": {
          "source": "192.168.1.100",
          "destination": "example.com:443"
        }
      }
    ]
  }
}
```

### 设置日志级别

```http
PUT /logs/level
```

**请求体**：
```json
{
  "level": "debug"
}
```

## 🔧 系统管理 API

### 重启服务

```http
POST /system/restart
```

**响应示例**：
```json
{
  "success": true,
  "message": "Service restart initiated"
}
```

### 关闭服务

```http
POST /system/shutdown
```

**响应示例**：
```json
{
  "success": true,
  "message": "Service shutdown initiated"
}
```

### 系统健康检查

```http
GET /system/health
```

**响应示例**：
```json
{
  "success": true,
  "data": {
    "status": "healthy",
    "checks": {
      "config": "ok",
      "network": "ok",
      "dns": "ok",
      "proxies": "ok"
    },
    "uptime": 3600,
    "memory_usage": 52428800
  }
}
```

## 📊 统计信息 API

### 获取统计概览

```http
GET /stats
```

**响应示例**：
```json
{
  "success": true,
  "data": {
    "total_connections": 1500,
    "active_connections": 45,
    "total_upload": 1073741824,
    "total_download": 2147483648,
    "proxy_usage": {
      "🇺🇸 US-1": {
        "connections": 25,
        "upload": 536870912,
        "download": 1073741824
      },
      "🇭🇰 HK-1": {
        "connections": 20,
        "upload": 268435456,
        "download": 536870912
      }
    }
  }
}
```

### 获取历史统计

```http
GET /stats/history
```

**查询参数**：
- `period`: 时间周期（hour, day, week, month）
- `limit`: 返回数量限制

**响应示例**：
```json
{
  "success": true,
  "data": {
    "period": "hour",
    "data": [
      {
        "timestamp": "2024-01-01T12:00:00Z",
        "upload": 1048576,
        "download": 2097152,
        "connections": 50
      }
    ]
  }
}
```

## 🔄 订阅管理 API

### 获取订阅列表

```http
GET /subscriptions
```

**响应示例**：
```json
{
  "success": true,
  "data": {
    "subscriptions": [
      {
        "id": "sub-1",
        "name": "机场A",
        "url": "https://example.com/sub",
        "last_updated": "2024-01-01T12:00:00Z",
        "node_count": 50,
        "status": "active"
      }
    ]
  }
}
```

### 更新订阅

```http
POST /subscriptions/{subscription_id}/update
```

**响应示例**：
```json
{
  "success": true,
  "data": {
    "updated_nodes": 50,
    "new_nodes": 5,
    "removed_nodes": 2
  }
}
```

## 📝 WebSocket API

### 实时事件推送

连接到 WebSocket 端点以接收实时事件：

```
ws://your-server-ip:9090/ws
```

**事件类型**：

1. **流量更新**：
```json
{
  "type": "traffic",
  "data": {
    "up": 1024,
    "down": 2048
  }
}
```

2. **连接变化**：
```json
{
  "type": "connection",
  "action": "new",
  "data": {
    "id": "uuid-1234",
    "metadata": {
      "host": "example.com",
      "sourceIP": "192.168.1.100"
    }
  }
}
```

3. **日志消息**：
```json
{
  "type": "log",
  "data": {
    "level": "info",
    "message": "Connection established",
    "time": "2024-01-01T12:00:00Z"
  }
}
```

## 🔒 错误代码

| 错误代码 | HTTP 状态码 | 描述 |
|---------|------------|------|
| `UNAUTHORIZED` | 401 | 认证失败 |
| `FORBIDDEN` | 403 | 权限不足 |
| `NOT_FOUND` | 404 | 资源不存在 |
| `INVALID_REQUEST` | 400 | 请求参数无效 |
| `INTERNAL_ERROR` | 500 | 服务器内部错误 |
| `SERVICE_UNAVAILABLE` | 503 | 服务不可用 |
| `RATE_LIMITED` | 429 | 请求频率限制 |

## 📚 SDK 和示例

### cURL 示例

```bash
# 获取代理列表
curl -H "Authorization: Bearer YOUR_SECRET_KEY" \
     http://localhost:9090/proxies

# 切换代理
curl -X PUT \
     -H "Authorization: Bearer YOUR_SECRET_KEY" \
     -H "Content-Type: application/json" \
     -d '{"name": "🇺🇸 US-1"}' \
     http://localhost:9090/proxies/GLOBAL

# 获取连接信息
curl -H "Authorization: Bearer YOUR_SECRET_KEY" \
     http://localhost:9090/connections
```

### Python 示例

```python
import requests
import json

class SingBoxAPI:
    def __init__(self, base_url, secret_key):
        self.base_url = base_url
        self.headers = {
            'Authorization': f'Bearer {secret_key}',
            'Content-Type': 'application/json'
        }
    
    def get_proxies(self):
        response = requests.get(f'{self.base_url}/proxies', headers=self.headers)
        return response.json()
    
    def switch_proxy(self, proxy_name, target_name):
        data = {'name': target_name}
        response = requests.put(
            f'{self.base_url}/proxies/{proxy_name}',
            headers=self.headers,
            json=data
        )
        return response.json()
    
    def get_connections(self):
        response = requests.get(f'{self.base_url}/connections', headers=self.headers)
        return response.json()

# 使用示例
api = SingBoxAPI('http://localhost:9090', 'your-secret-key')
proxies = api.get_proxies()
print(json.dumps(proxies, indent=2))
```

### JavaScript 示例

```javascript
class SingBoxAPI {
    constructor(baseUrl, secretKey) {
        this.baseUrl = baseUrl;
        this.headers = {
            'Authorization': `Bearer ${secretKey}`,
            'Content-Type': 'application/json'
        };
    }

    async getProxies() {
        const response = await fetch(`${this.baseUrl}/proxies`, {
            headers: this.headers
        });
        return await response.json();
    }

    async switchProxy(proxyName, targetName) {
        const response = await fetch(`${this.baseUrl}/proxies/${proxyName}`, {
            method: 'PUT',
            headers: this.headers,
            body: JSON.stringify({ name: targetName })
        });
        return await response.json();
    }

    async getConnections() {
        const response = await fetch(`${this.baseUrl}/connections`, {
            headers: this.headers
        });
        return await response.json();
    }
}

// 使用示例
const api = new SingBoxAPI('http://localhost:9090', 'your-secret-key');
api.getProxies().then(data => console.log(data));
```

---

**注意**：请妥善保管 API 密钥，避免在客户端代码中硬编码敏感信息。建议使用环境变量或配置文件来管理密钥。