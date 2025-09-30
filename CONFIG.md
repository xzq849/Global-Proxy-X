# 配置指南

本文档详细介绍 sing-box + zashboard 全局代理服务的配置方法。

## 📁 配置文件结构

### 主要配置文件

```
/etc/sing-box/
├── config.json              # 主配置文件
├── secret.key              # API 密钥
├── geoip.db                # IP 地理位置数据库
├── geosite.db              # 域名分类数据库
└── rule-sets/               # 自定义规则集
    ├── cn-sites.json        # 中国大陆网站
    ├── proxy-sites.json     # 代理网站
    └── block-ads.json       # 广告拦截
```

## 🔧 基础配置

### 1. 主配置文件 (config.json)

完整的配置文件结构：

```json
{
  "log": {
    "level": "info",
    "output": "/var/log/sing-box/sing-box.log",
    "timestamp": true
  },
  "experimental": {
    "clash_api": {
      "external_controller": "0.0.0.0:9090",
      "external_ui": "/var/www/zashboard",
      "secret": "your-secret-key",
      "default_mode": "rule"
    }
  },
  "dns": {
    "servers": [
      {
        "tag": "cloudflare",
        "address": "https://1.1.1.1/dns-query",
        "detour": "proxy"
      },
      {
        "tag": "local",
        "address": "223.5.5.5",
        "detour": "direct"
      }
    ],
    "rules": [
      {
        "geosite": "cn",
        "server": "local"
      }
    ],
    "final": "cloudflare",
    "strategy": "prefer_ipv4"
  },
  "inbounds": [
    {
      "type": "mixed",
      "tag": "mixed-in",
      "listen": "0.0.0.0",
      "listen_port": 7890,
      "users": []
    },
    {
      "type": "tun",
      "tag": "tun-in",
      "interface_name": "tun0",
      "inet4_address": "172.19.0.1/30",
      "auto_route": true,
      "strict_route": false,
      "sniff": true
    }
  ],
  "outbounds": [
    {
      "type": "selector",
      "tag": "proxy",
      "outbounds": ["auto", "direct"],
      "default": "auto"
    },
    {
      "type": "urltest",
      "tag": "auto",
      "outbounds": [],
      "url": "http://www.gstatic.com/generate_204",
      "interval": "5m",
      "tolerance": 50
    },
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    }
  ],
  "route": {
    "geoip": {
      "path": "/etc/sing-box/geoip.db"
    },
    "geosite": {
      "path": "/etc/sing-box/geosite.db"
    },
    "rules": [
      {
        "protocol": "dns",
        "outbound": "dns-out"
      },
      {
        "geosite": "category-ads-all",
        "outbound": "block"
      },
      {
        "geosite": "cn",
        "geoip": "cn",
        "outbound": "direct"
      }
    ],
    "final": "proxy",
    "auto_detect_interface": true
  }
}
```

### 2. 日志配置

```json
{
  "log": {
    "level": "info",           // 日志级别: trace, debug, info, warn, error
    "output": "/var/log/sing-box/sing-box.log",
    "timestamp": true,         // 包含时间戳
    "disable_color": false     // 禁用颜色输出
  }
}
```

**日志级别说明**：
- `trace`: 最详细的日志，包含所有调试信息
- `debug`: 调试信息，用于问题排查
- `info`: 一般信息，推荐日常使用
- `warn`: 警告信息
- `error`: 仅错误信息

### 3. DNS 配置

#### 基础 DNS 配置

```json
{
  "dns": {
    "servers": [
      {
        "tag": "cloudflare",
        "address": "https://1.1.1.1/dns-query",
        "detour": "proxy"
      },
      {
        "tag": "google",
        "address": "https://8.8.8.8/dns-query",
        "detour": "proxy"
      },
      {
        "tag": "local",
        "address": "223.5.5.5",
        "detour": "direct"
      }
    ],
    "rules": [
      {
        "geosite": "cn",
        "server": "local"
      },
      {
        "geosite": "geolocation-!cn",
        "server": "cloudflare"
      }
    ],
    "final": "cloudflare",
    "strategy": "prefer_ipv4"
  }
}
```

#### 高级 DNS 配置

```json
{
  "dns": {
    "servers": [
      {
        "tag": "cloudflare-doh",
        "address": "https://1.1.1.1/dns-query",
        "address_resolver": "local-dns",
        "detour": "proxy"
      },
      {
        "tag": "google-dot",
        "address": "tls://8.8.8.8",
        "address_resolver": "local-dns",
        "detour": "proxy"
      },
      {
        "tag": "local-dns",
        "address": "223.5.5.5",
        "detour": "direct"
      },
      {
        "tag": "block-dns",
        "address": "rcode://success"
      }
    ],
    "rules": [
      {
        "geosite": "category-ads-all",
        "server": "block-dns",
        "disable_cache": true
      },
      {
        "geosite": "cn",
        "server": "local-dns"
      },
      {
        "geosite": "geolocation-!cn",
        "server": "cloudflare-doh"
      }
    ],
    "final": "cloudflare-doh",
    "strategy": "prefer_ipv4",
    "disable_cache": false,
    "disable_expire": false
  }
}
```

## 🌐 入站配置 (Inbounds)

### 1. 混合代理 (HTTP + SOCKS5)

```json
{
  "type": "mixed",
  "tag": "mixed-in",
  "listen": "0.0.0.0",
  "listen_port": 7890,
  "sniff": true,
  "sniff_override_destination": false,
  "users": [
    {
      "username": "user1",
      "password": "password1"
    }
  ]
}
```

### 2. TUN 接口（透明代理）

```json
{
  "type": "tun",
  "tag": "tun-in",
  "interface_name": "tun0",
  "inet4_address": "172.19.0.1/30",
  "inet6_address": "fdfe:dcba:9876::1/126",
  "mtu": 9000,
  "auto_route": true,
  "strict_route": false,
  "sniff": true,
  "sniff_override_destination": false,
  "domain_strategy": "prefer_ipv4"
}
```

### 3. HTTP 代理

```json
{
  "type": "http",
  "tag": "http-in",
  "listen": "0.0.0.0",
  "listen_port": 8080,
  "users": [
    {
      "username": "admin",
      "password": "password"
    }
  ],
  "tls": {
    "enabled": true,
    "certificate_path": "/etc/ssl/cert.pem",
    "key_path": "/etc/ssl/key.pem"
  }
}
```

## 🚀 出站配置 (Outbounds)

### 1. 节点选择器

```json
{
  "type": "selector",
  "tag": "proxy",
  "outbounds": [
    "auto",
    "🇺🇸 美国节点",
    "🇭🇰 香港节点",
    "🇯🇵 日本节点",
    "direct"
  ],
  "default": "auto"
}
```

### 2. 自动选择（延迟测试）

```json
{
  "type": "urltest",
  "tag": "auto",
  "outbounds": [
    "us-node-1",
    "us-node-2",
    "hk-node-1",
    "jp-node-1"
  ],
  "url": "http://www.gstatic.com/generate_204",
  "interval": "5m",
  "tolerance": 50,
  "idle_timeout": "30m"
}
```

### 3. 负载均衡

```json
{
  "type": "loadbalance",
  "tag": "load-balance",
  "outbounds": [
    "us-node-1",
    "us-node-2",
    "hk-node-1"
  ],
  "strategy": "round_robin"
}
```

### 4. VMess 节点

```json
{
  "type": "vmess",
  "tag": "vmess-out",
  "server": "example.com",
  "server_port": 443,
  "uuid": "12345678-1234-1234-1234-123456789abc",
  "security": "auto",
  "alter_id": 0,
  "global_padding": false,
  "authenticated_length": true,
  "tls": {
    "enabled": true,
    "server_name": "example.com",
    "insecure": false,
    "alpn": ["h2", "http/1.1"]
  },
  "transport": {
    "type": "ws",
    "path": "/v2ray",
    "headers": {
      "Host": "example.com"
    }
  }
}
```

### 5. Shadowsocks 节点

```json
{
  "type": "shadowsocks",
  "tag": "ss-out",
  "server": "example.com",
  "server_port": 8388,
  "method": "aes-256-gcm",
  "password": "your-password",
  "plugin": "v2ray-plugin",
  "plugin_opts": "server;tls;host=example.com"
}
```

### 6. Trojan 节点

```json
{
  "type": "trojan",
  "tag": "trojan-out",
  "server": "example.com",
  "server_port": 443,
  "password": "your-password",
  "tls": {
    "enabled": true,
    "server_name": "example.com",
    "insecure": false,
    "alpn": ["h2", "http/1.1"]
  },
  "transport": {
    "type": "grpc",
    "service_name": "trojan-grpc"
  }
}
```

## 🛣️ 路由配置 (Route)

### 1. 基础路由规则

```json
{
  "route": {
    "geoip": {
      "path": "/etc/sing-box/geoip.db"
    },
    "geosite": {
      "path": "/etc/sing-box/geosite.db"
    },
    "rules": [
      {
        "protocol": "dns",
        "outbound": "dns-out"
      },
      {
        "geosite": "category-ads-all",
        "outbound": "block"
      },
      {
        "geosite": "cn",
        "geoip": "cn",
        "outbound": "direct"
      },
      {
        "geosite": "geolocation-!cn",
        "outbound": "proxy"
      }
    ],
    "final": "proxy",
    "auto_detect_interface": true
  }
}
```

### 2. 高级路由规则

```json
{
  "route": {
    "rules": [
      {
        "inbound": "tun-in",
        "action": "sniff"
      },
      {
        "protocol": "dns",
        "outbound": "dns-out"
      },
      {
        "clash_mode": "direct",
        "outbound": "direct"
      },
      {
        "clash_mode": "global",
        "outbound": "proxy"
      },
      {
        "domain_suffix": [".cn", ".中国"],
        "geoip": "cn",
        "outbound": "direct"
      },
      {
        "domain_keyword": ["google", "youtube", "facebook"],
        "outbound": "proxy"
      },
      {
        "domain_regex": ".*\\.google\\..*",
        "outbound": "proxy"
      },
      {
        "source_ip_cidr": ["192.168.1.0/24"],
        "outbound": "direct"
      },
      {
        "port": [80, 443],
        "outbound": "proxy"
      },
      {
        "port_range": ["1000:2000"],
        "outbound": "direct"
      },
      {
        "process_name": ["chrome", "firefox"],
        "outbound": "proxy"
      },
      {
        "rule_set": "geosite-cn",
        "outbound": "direct"
      }
    ],
    "rule_set": [
      {
        "tag": "geosite-cn",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-cn.srs",
        "download_detour": "direct"
      }
    ],
    "final": "proxy"
  }
}
```

## 🔐 安全配置

### 1. TLS 配置

```json
{
  "tls": {
    "enabled": true,
    "server_name": "example.com",
    "insecure": false,
    "alpn": ["h2", "http/1.1"],
    "min_version": "1.2",
    "max_version": "1.3",
    "cipher_suites": [
      "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384",
      "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384"
    ],
    "certificate_path": "/etc/ssl/cert.pem",
    "key_path": "/etc/ssl/key.pem",
    "ech": {
      "enabled": true,
      "pq_signature_schemes_enabled": true,
      "dynamic_record_sizing_disabled": false
    }
  }
}
```

### 2. 用户认证

```json
{
  "users": [
    {
      "username": "admin",
      "password": "secure-password-123"
    },
    {
      "username": "user1",
      "password": "user-password-456"
    }
  ]
}
```

## 📊 性能优化配置

### 1. 内存优化

```json
{
  "experimental": {
    "cache_file": {
      "enabled": true,
      "path": "/var/cache/sing-box/cache.db",
      "cache_id": "my_profile",
      "store_fakeip": true
    }
  }
}
```

### 2. 网络优化

```json
{
  "inbounds": [
    {
      "type": "mixed",
      "listen": "0.0.0.0",
      "listen_port": 7890,
      "tcp_fast_open": true,
      "tcp_multi_path": true,
      "udp_fragment": true,
      "sniff": true,
      "sniff_override_destination": false,
      "sniff_timeout": "300ms"
    }
  ]
}
```

## 🔧 配置管理命令

### 1. 验证配置

```bash
# 检查配置文件语法
sing-box check -c /etc/sing-box/config.json

# 使用管理工具验证
proxy-manager config validate
```

### 2. 重新加载配置

```bash
# 重新加载配置（无需重启）
proxy-manager reload

# 或者使用 systemctl
sudo systemctl reload sing-box
```

### 3. 备份和恢复

```bash
# 备份当前配置
proxy-manager config backup

# 恢复配置
proxy-manager config restore backup-20240101.json

# 重置为默认配置
proxy-manager config reset
```

## 📝 配置模板

### 1. 家庭用户配置

适合家庭网络环境，注重稳定性和易用性：

```bash
# 生成家庭用户配置模板
proxy-manager config template --type home --output home-config.json
```

### 2. 企业用户配置

适合企业环境，注重安全性和管理功能：

```bash
# 生成企业用户配置模板
proxy-manager config template --type enterprise --output enterprise-config.json
```

### 3. 高级用户配置

适合高级用户，包含完整功能：

```bash
# 生成高级用户配置模板
proxy-manager config template --type advanced --output advanced-config.json
```

## 🔍 配置调试

### 1. 启用调试日志

```json
{
  "log": {
    "level": "debug",
    "output": "/var/log/sing-box/debug.log"
  }
}
```

### 2. 网络诊断

```bash
# 诊断网络连接
proxy-manager diagnose --target google.com

# 测试特定节点
proxy-manager nodes test "节点名称"

# 检查路由规则
proxy-manager route test --domain google.com
```

---

**注意**：修改配置文件后，建议先使用 `sing-box check` 命令验证语法正确性，然后再重新加载配置。