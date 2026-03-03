#!/bin/bash
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否为 root 用户
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 root 用户运行此脚本"
        exit 1
    fi
}

# 检查依赖
check_dependencies() {
    log_info "检查依赖..."

    # 检查 Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker 未安装，请先安装 Docker"
        log_info "安装命令：curl -fsSL https://get.docker.com | sh"
        exit 1
    fi

    # 检查 Docker Compose
    if ! docker compose version &> /dev/null; then
        log_error "Docker Compose 未安装"
        exit 1
    fi

    log_success "依赖检查通过"
}

# 创建目录结构
create_directories() {
    log_info "创建目录结构..."

    mkdir -p openclaw/config
    mkdir -p openclaw/data
    mkdir -p openclaw/workspace
    mkdir -p authelia
    mkdir -p nginx/conf.d
    mkdir -p nginx/templates
    mkdir -p ssl
    mkdir -p certbot-webroot
    mkdir -p backup

    log_success "目录创建完成"
}

# 生成安全密钥
generate_secrets() {
    log_info "生成安全密钥..."

    # JWT Secret
    openssl rand -base64 64 > authelia/jwt_secret
    chmod 600 authelia/jwt_secret

    # Session Secret
    openssl rand -base64 64 > authelia/session_secret
    chmod 600 authelia/session_secret

    # Encryption Key
    openssl rand -base64 64 > authelia/encryption_key
    chmod 600 authelia/encryption_key

    log_success "安全密钥生成完成"
}

# 生成密码哈希
generate_password_hash() {
    local password=$1
    docker run --rm authelia/authelia:latest \
        authelia crypto hash generate argon2 --password "$password" 2>/dev/null | \
        grep 'Digest:' | awk '{print $2}'
}

# 配置 Authelia
configure_authelia() {
    log_info "配置 Authelia..."

    # 加载环境变量
    if [ -f .env ]; then
        source .env
    else
        log_error ".env 文件不存在，请先复制 .env.example 并配置"
        exit 1
    fi

    # 生成密码哈希
    log_info "生成密码哈希（这可能需要几秒钟）..."
    PASSWORD_HASH=$(generate_password_hash "$ADMIN_PASSWORD")

    # 创建 Authelia 配置
    cat > authelia/configuration.yml << EOF
---
server:
  host: 0.0.0.0
  port: 9091
  path: authelia

log:
  level: info
  format: text

theme: light

jwt_secret: file:///config/jwt_secret

default_redirection_url: https://${DOMAIN}

totp:
  disable: false
  issuer: OpenClaw

authentication_backend:
  file:
    path: /config/users_database.yml
    password:
      algorithm: argon2id
      iterations: 3
      salt_length: 16
      parallelism: 4
      memory: 65536

access_control:
  default_policy: deny
  rules:
    - domain: ${DOMAIN}
      policy: one_factor

session:
  name: authelia_session
  secret: file:///config/session_secret
  expiration: 1h
  inactivity: 5m
  remember_me_duration: 1M
  domain: ${DOMAIN}
  same_site: lax

storage:
  encryption_key: file:///config/encryption_key
  local:
    path: /config/db.sqlite3

notifier:
  filesystem:
    filename: /config/notification.txt
EOF

    # 创建用户数据库
    cat > authelia/users_database.yml << EOF
---
users:
  ${ADMIN_USERNAME}:
    displayname: "${ADMIN_USERNAME}"
    password: "${PASSWORD_HASH}"
    email: ${ADMIN_EMAIL}
    groups:
      - admins
      - users
EOF

    chmod 600 authelia/users_database.yml

    log_success "Authelia 配置完成"
}

# 配置 Nginx
configure_nginx() {
    log_info "配置 Nginx..."

    # 加载环境变量
    source .env

    # 创建 Nginx 主配置
    cat > nginx/nginx.conf << 'EOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;

    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml text/javascript
               application/json application/javascript application/xml+rss
               application/rss+xml font/truetype font/opentype
               application/vnd.ms-fontobject image/svg+xml;

    include /etc/nginx/conf.d/*.conf;
}
EOF

    # 创建 OpenClaw 虚拟主机配置模板
    cat > nginx/templates/openclaw.conf.template << 'EOF'
# HTTP 重定向到 HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};

    # Let's Encrypt 验证
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    # 其他请求重定向到 HTTPS
    location / {
        return 301 https://$host$request_uri;
    }
}

# HTTPS 主配置
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${DOMAIN};

    # SSL 证书配置
    ssl_certificate /etc/nginx/ssl/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/live/${DOMAIN}/privkey.pem;
    ssl_trusted_certificate /etc/nginx/ssl/live/${DOMAIN}/chain.pem;

    # SSL 安全配置
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384';
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_stapling on;
    ssl_stapling_verify on;

    # 安全头
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Authelia 认证端点（内部使用）
    location = /authelia/api/verify {
        internal;
        proxy_pass http://authelia:9091/api/verify;
        proxy_set_header X-Original-URL $scheme://$http_host$request_uri;
        proxy_set_header X-Forwarded-Method $request_method;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $http_host;
        proxy_set_header X-Forwarded-Uri $request_uri;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header Content-Length "";
        proxy_pass_request_body off;
    }

    # Authelia Web UI（登录页面）
    location ^~ /authelia {
        proxy_pass http://authelia:9091/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $http_host;
        proxy_set_header X-Forwarded-Uri $request_uri;
        proxy_set_header X-Forwarded-Prefix /authelia;
    }

    # Authelia 静态资源（不需要认证）
    location ~* ^/(static|locales) {
        proxy_pass http://authelia:9091;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # 缓存静态资源
        expires 1h;
        add_header Cache-Control "public, immutable";
    }

    # OpenClaw 静态资源（不需要认证）
    location ~* ^/(assets|favicon\.|apple-touch-icon|robots\.txt) {
        proxy_pass http://openclaw:18789;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # 缓存静态资源
        expires 1h;
        add_header Cache-Control "public, immutable";
    }

    # 健康检查端点（不需要认证）
    location = /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }

    # OpenClaw 主应用
    location / {
        # Authelia 认证检查
        auth_request /authelia/api/verify;

        # 获取认证用户信息
        auth_request_set $user $upstream_http_remote_user;
        auth_request_set $groups $upstream_http_remote_groups;
        auth_request_set $name $upstream_http_remote_name;
        auth_request_set $email $upstream_http_remote_email;

        # 认证失败重定向到登录页
        error_page 401 =302 https://$host/authelia/;

        # 代理到 OpenClaw
        proxy_pass http://openclaw:18789;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # 传递认证信息到 OpenClaw
        proxy_set_header Remote-User $user;
        proxy_set_header Remote-Groups $groups;
        proxy_set_header Remote-Name $name;
        proxy_set_header Remote-Email $email;

        # WebSocket 支持
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 3600;
        proxy_send_timeout 3600;
    }
}
EOF

    # 处理模板变量
    envsubst '${DOMAIN}' < nginx/templates/openclaw.conf.template > nginx/conf.d/openclaw.conf

    log_success "Nginx 配置完成"
}

# 申请 SSL 证书
request_ssl_certificate() {
    log_info "申请 SSL 证书..."

    source .env

    # 检查证书是否已存在
    if [ -f "ssl/live/${DOMAIN}/fullchain.pem" ]; then
        log_warning "SSL 证书已存在，跳过申请"
        return 0
    fi

    # 启动临时 Nginx 用于验证
    log_info "启动临时 Nginx 服务..."
    docker compose up -d nginx
    sleep 5

    # 申请证书
    log_info "正在申请 Let's Encrypt 证书..."
    docker run --rm \
        -v "$(pwd)/ssl:/etc/letsencrypt" \
        -v "$(pwd)/certbot-webroot:/var/www/certbot" \
        certbot/certbot certonly \
        --webroot \
        --webroot-path=/var/www/certbot \
        --email "${ADMIN_EMAIL}" \
        --agree-tos \
        --no-eff-email \
        -d "${DOMAIN}"

    if [ $? -eq 0 ]; then
        log_success "SSL 证书申请成功"
    else
        log_error "SSL 证书申请失败"
        log_warning "将使用自签名证书"
        create_self_signed_certificate
    fi
}

# 创建自签名证书（用于测试）
create_self_signed_certificate() {
    log_info "创建自签名证书..."

    source .env

    mkdir -p "ssl/live/${DOMAIN}"

    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "ssl/live/${DOMAIN}/privkey.pem" \
        -out "ssl/live/${DOMAIN}/fullchain.pem" \
        -subj "/CN=${DOMAIN}"

    cp "ssl/live/${DOMAIN}/fullchain.pem" "ssl/live/${DOMAIN}/chain.pem"

    log_success "自签名证书创建完成"
}

# 启动服务
start_services() {
    log_info "启动所有服务..."

    docker compose down
    docker compose up -d

    log_success "服务启动完成"
}

# 等待服务就绪
wait_for_services() {
    log_info "等待服务就绪..."

    local max_attempts=30
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        if docker compose ps | grep -q "healthy"; then
            log_success "服务已就绪"
            return 0
        fi

        attempt=$((attempt + 1))
        echo -n "."
        sleep 2
    done

    log_warning "服务启动超时，请检查日志"
}

# 显示访问信息
show_access_info() {
    source .env

    echo ""
    echo "========================================="
    echo -e "${GREEN}OpenClaw 部署完成！${NC}"
    echo "========================================="
    echo ""
    echo "访问地址：https://${DOMAIN}"
    echo "用户名：${ADMIN_USERNAME}"
    echo "密码：${ADMIN_PASSWORD}"
    echo ""
    echo "常用命令："
    echo "  查看日志：docker compose logs -f"
    echo "  重启服务：docker compose restart"
    echo "  停止服务：docker compose down"
    echo "  更新服务：./update.sh"
    echo ""
    echo "========================================="
}

# 主函数
main() {
    echo ""
    echo "========================================="
    echo "  OpenClaw Docker 一键部署脚本"
    echo "========================================="
    echo ""

    check_root
    check_dependencies
    create_directories

    # 检查 .env 文件
    if [ ! -f .env ]; then
        log_warning ".env 文件不存在，从示例文件复制..."
        cp .env.example .env
        log_error "请编辑 .env 文件配置域名和账号信息，然后重新运行此脚本"
        exit 1
    fi

    generate_secrets
    configure_authelia
    configure_nginx
    request_ssl_certificate
    start_services
    wait_for_services
    show_access_info
}

# 运行主函数
main "$@"
