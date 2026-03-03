# OpenClaw Docker 一键部署脚本

<div align="center">

![OpenClaw Logo](https://img.shields.io/badge/OpenClaw-Docker-blue?style=for-the-badge)
![License](https://img.shields.io/badge/license-MIT-green?style=for-the-badge)
![Ubuntu](https://img.shields.io/badge/Ubuntu-20.04%2B-orange?style=for-the-badge)

**一键部署 OpenClaw AI 助手到你的 VPS**

[快速开始](#快速开始) • [功能特性](#功能特性) • [详细文档](#详细文档) • [常见问题](#常见问题)

</div>

---

## 📖 简介

OpenClaw Docker 一键部署脚本是一个完整的自动化部署方案，帮助你在 5-15 分钟内将 OpenClaw AI 助手部署到你的 VPS 服务器上。

### 什么是 OpenClaw？

OpenClaw 是一个强大的 AI 助手平台，支持：
- 🤖 多种 AI 模型（Claude、GPT、Gemini 等）
- 💬 Telegram Bot 集成
- 🔐 安全的单点登录认证
- 🌐 Web 控制面板
- 📱 移动端友好

## ✨ 功能特性

### 🚀 一键部署
- ✅ **完全自动化** - 无需手动配置
- ✅ **交互式界面** - 友好的图形化配置向导
- ✅ **智能检查** - 自动检测并安装所有依赖
- ✅ **防火墙配置** - 自动开放必要端口
- ✅ **SSL 证书** - 自动申请 Let's Encrypt 证书

### 🔒 安全可靠
- ✅ **容器隔离** - Docker 容器完全隔离
- ✅ **单点登录** - Authelia 认证系统
- ✅ **HTTPS 加密** - 强制 HTTPS 访问
- ✅ **密码哈希** - Argon2id 加密存储

### 🎯 灵活配置
- ✅ **域名可选** - 支持域名或 IP 访问
- ✅ **自动生成凭据** - 或手动设置用户名密码
- ✅ **自动更新** - Watchtower 自动更新容器
- ✅ **完整管理** - 提供管理菜单脚本

### 📦 完整服务
- **OpenClaw** - AI 助手主服务
- **Authelia** - 单点登录认证
- **Nginx** - 反向代理和 SSL
- **Certbot** - SSL 证书管理
- **Watchtower** - 自动更新服务

## 🎯 快速开始

### 系统要求

- **操作系统**: Ubuntu 20.04 / 22.04 / 24.04
- **CPU**: 至少 2 核
- **内存**: 至少 2GB
- **磁盘**: 至少 10GB 可用空间
- **权限**: Root 权限

### 一键部署

```bash
# 1. 克隆仓库
git clone https://github.com/dongbuyu2022/openclaw-docker-deploy.git
cd openclaw-docker-deploy

# 2. 运行部署脚本
chmod +x setup-enhanced.sh
./setup-enhanced.sh

# 3. 按照提示操作
# - 配置域名（或跳过使用 IP）
# - 设置管理员账号（自动生成或手动输入）
# - 确认配置并开始部署

# 4. 完成！
# 访问显示的地址，使用生成的用户名和密码登录
```

### 部署演示

```
╔════════════════════════════════════════╗
║   欢迎使用 OpenClaw 一键部署脚本      ║
║                                        ║
║   本脚本将帮助您快速部署 OpenClaw     ║
║   预计耗时：5-15 分钟                 ║
╚════════════════════════════════════════╝

✓ 系统检查通过：Ubuntu 22.04
✓ 资源充足：4核 / 8GB / 50GB
✓ Docker 已安装：29.2.1
✓ 所有依赖已安装
✓ 端口可用：80, 443
✓ 防火墙已配置

域名配置：example.com
用户名：admin_x7k9m2
密码：Kp9#mL2$vN8@qR5!

正在部署...
✓ 创建目录结构
✓ 生成安全密钥
✓ 配置服务
✓ 启动容器
✓ 申请 SSL 证书

╔════════════════════════════════════════╗
║        部署完成！                      ║
╚════════════════════════════════════════╝

访问地址：https://example.com
用户名：admin_x7k9m2
密码：Kp9#mL2$vN8@qR5!
```

## 📚 详细文档

### 目录结构

```
openclaw-docker-deploy/
├── setup-enhanced.sh          # 增强版部署脚本（推荐）
├── setup-interactive.sh       # 交互式部署脚本
├── manage.sh                  # 管理菜单脚本
├── update.sh                  # 更新脚本
├── docker-compose.yml         # Docker Compose 配置
├── .env.example               # 环境变量模板
├── nginx/                     # Nginx 配置模板
├── README.md                  # 本文档
└── docs/                      # 详细文档
    ├── INSTALL.md            # 安装指南
    ├── CONFIG.md             # 配置说明
    └── FAQ.md                # 常见问题
```

### 部署脚本对比

| 脚本 | 功能 | 适用场景 |
|------|------|---------|
| `setup-enhanced.sh` | 完整环境检查 + 自动配置 | **推荐**，首次部署 |
| `setup-interactive.sh` | 交互式配置 | 需要自定义配置 |
| `setup.sh` | 基础部署 | 快速部署 |

### 管理菜单

部署完成后，使用管理菜单进行配置：

```bash
./manage.sh
```

功能包括：
1. 📝 配置域名
2. 🔑 修改管理员密码
3. 📊 查看服务状态
4. 📋 查看访问信息
5. 🔄 更新服务
6. 💾 备份数据
7. 📦 恢复数据
8. 📜 查看日志

### 环境变量配置

编辑 `.env` 文件自定义配置：

```bash
# 域名配置
DOMAIN=your-domain.com

# 管理员账号
ADMIN_USERNAME=admin
ADMIN_PASSWORD=your-secure-password

# Telegram Bot（可选）
TELEGRAM_BOT_TOKEN=your_bot_token

# API Keys（可选）
ANTHROPIC_API_KEY=your_anthropic_key
OPENAI_API_KEY=your_openai_key

# 自动更新间隔（秒）
WATCHTOWER_INTERVAL=86400  # 每天
```

## 🔧 高级配置

### 自定义端口

如果 80/443 端口被占用，可以修改 `docker-compose.yml`：

```yaml
nginx:
  ports:
    - "8080:80"   # HTTP
    - "8443:443"  # HTTPS
```

### 禁用自动更新

编辑 `docker-compose.yml`，注释掉 watchtower 服务：

```yaml
# watchtower:
#   image: containrrr/watchtower
#   ...
```

### 添加更多用户

运行管理菜单或编辑 `authelia/users_database.yml`：

```yaml
users:
  user1:
    password: "$argon2id$..."
    email: user1@example.com
    groups:
      - users
```

生成密码哈希：

```bash
docker run --rm authelia/authelia:latest \
  authelia crypto hash generate argon2 --password 'your-password'
```

## 🔄 更新和维护

### 手动更新

```bash
# 运行更新脚本
./update.sh

# 或使用 Docker Compose
docker compose pull
docker compose up -d
```

### 自动更新

Watchtower 会自动检查并更新容器（默认每天一次）。

### 备份数据

```bash
# 使用管理菜单
./manage.sh
# 选择 "6. 备份数据"

# 或手动备份
tar -czf openclaw-backup-$(date +%Y%m%d).tar.gz \
  openclaw/ authelia/ .env
```

### 恢复数据

```bash
# 使用管理菜单
./manage.sh
# 选择 "7. 恢复数据"

# 或手动恢复
tar -xzf openclaw-backup-20260303.tar.gz
docker compose restart
```

## 🐛 故障排查

### 查看日志

```bash
# 所有服务日志
docker compose logs -f

# 特定服务日志
docker compose logs -f openclaw
docker compose logs -f authelia
docker compose logs -f nginx
```

### 重启服务

```bash
# 重启所有服务
docker compose restart

# 重启特定服务
docker compose restart openclaw
```

### 常见问题

#### 1. 端口被占用

**问题**：80 或 443 端口已被占用

**解决**：
```bash
# 查看占用端口的进程
ss -tulnp | grep -E ":80 |:443 "

# 停止占用的服务
systemctl stop nginx  # 或其他服务

# 或修改 docker-compose.yml 使用其他端口
```

#### 2. 域名无法访问

**问题**：配置域名后无法访问

**解决**：
- 检查 DNS 是否正确解析：`nslookup your-domain.com`
- 检查防火墙是否开放端口：`ufw status`
- 检查 Nginx 是否正常运行：`docker compose ps`

#### 3. SSL 证书申请失败

**问题**：Let's Encrypt 证书申请失败

**解决**：
- 确保域名 DNS 已生效
- 确保 80 端口可访问
- 检查是否达到 Let's Encrypt 限流
- 使用自签名证书测试

#### 4. 登录失败

**问题**：无法使用用户名密码登录

**解决**：
- 检查用户名密码是否正确
- 查看 Authelia 日志：`docker compose logs authelia`
- 重置密码：使用管理菜单

更多问题请查看 [FAQ.md](docs/FAQ.md)

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

### 贡献指南

1. Fork 本仓库
2. 创建特性分支：`git checkout -b feature/AmazingFeature`
3. 提交更改：`git commit -m 'Add some AmazingFeature'`
4. 推送到分支：`git push origin feature/AmazingFeature`
5. 提交 Pull Request

## 📄 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情

## 🙏 致谢

- [OpenClaw](https://openclaw.ai) - AI 助手平台
- [Authelia](https://www.authelia.com) - 认证系统
- [Docker](https://www.docker.com) - 容器化平台
- [Let's Encrypt](https://letsencrypt.org) - 免费 SSL 证书

## 📞 联系方式

- **GitHub**: [@dongbuyu2022](https://github.com/dongbuyu2022)
- **Issues**: [提交问题](https://github.com/dongbuyu2022/openclaw-docker-deploy/issues)

## ⭐ Star History

如果这个项目对你有帮助，请给个 Star ⭐️

---

<div align="center">

**[⬆ 回到顶部](#openclaw-docker-一键部署脚本)**

Made with ❤️ by [dongbuyu2022](https://github.com/dongbuyu2022)

</div>
