#!/bin/bash
set -e

# 使用之前的配置直接部署
SYSTEM_NAME="小龙虾AI助手"
DOMAIN="xiaolongxia.nvhuang.dpdns.org"
USE_DOMAIN=true
USERNAME="admin"
PASSWORD="YourPassword123"  # 请修改
ADMIN_EMAIL="admin@localhost"

echo "========================================="
echo "  OpenClaw 自动部署"
echo "========================================="
echo ""
echo "系统名称：$SYSTEM_NAME"
echo "域名：$DOMAIN"
echo "用户名：$USERNAME"
echo ""
echo "开始部署..."
echo ""

# 创建 .env
cat > .env << EOF
DOMAIN=${DOMAIN}
SYSTEM_NAME=${SYSTEM_NAME}
ADMIN_USERNAME=${USERNAME}
ADMIN_PASSWORD=${PASSWORD}
ADMIN_EMAIL=${ADMIN_EMAIL}
OPENCLAW_VERSION=latest
WATCHTOWER_INTERVAL=86400
TZ=Asia/Shanghai
EOF

# 创建目录
mkdir -p openclaw/config openclaw/data openclaw/workspace
mkdir -p authelia nginx/conf.d ssl certbot-webroot backup

# 生成密钥
openssl rand -base64 64 > authelia/jwt_secret
openssl rand -base64 64 > authelia/session_secret
openssl rand -base64 64 > authelia/encryption_key
chmod 600 authelia/*

# 生成密码哈希
echo "生成密码哈希..."
PASSWORD_HASH=$(docker run --rm authelia/authelia:latest \
    authelia crypto hash generate argon2 --password "$PASSWORD" 2>/dev/null | \
    grep 'Digest:' | awk '{print $2}')

# Authelia 配置
cat > authelia/configuration.yml << EOF
---
server:
  host: 0.0.0.0
  port: 9091
  path: authelia
log:
  level: info
theme: light
jwt_secret: file:///config/jwt_secret
default_redirection_url: https://${DOMAIN}
totp:
  disable: false
  issuer: ${SYSTEM_NAME}
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

cat > authelia/users_database.yml << EOF
---
users:
  ${USERNAME}:
    displayname: "${USERNAME}"
    password: "${PASSWORD_HASH}"
    email: ${ADMIN_EMAIL}
    groups:
      - admins
      - users
EOF
chmod 600 authelia/users_database.yml

# Nginx 主配置
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
               application/json application/javascript application/xml+rss;
    include /etc/nginx/conf.d/*.conf;
}
EOF

# Nginx 虚拟主机配置
cat > nginx/conf.d/openclaw.conf << EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    location / {
        return 301 https://\$host\$request_uri;
    }
}
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name ${DOMAIN};
    ssl_certificate /etc/nginx/ssl/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/live/${DOMAIN}/privkey.pem;
    ssl_trusted_certificate /etc/nginx/ssl/live/${DOMAIN}/chain.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    location = /authelia/api/verify {
        internal;
        proxy_pass http://authelia:9091/api/verify;
        proxy_set_header X-Original-URL \$scheme://\$http_host\$request_uri;
        proxy_set_header X-Forwarded-Method \$request_method;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$http_host;
        proxy_set_header X-Forwarded-Uri \$request_uri;
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_set_header Content-Length "";
        proxy_pass_request_body off;
    }
    location ^~ /authelia {
        proxy_pass http://authelia:9091/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    location = /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
    location / {
        auth_request /authelia/api/verify;
        auth_request_set \$user \$upstream_http_remote_user;
        error_page 401 =302 https://\$host/authelia/;
        proxy_pass http://openclaw:18789;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Remote-User \$user;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 3600;
    }
}
EOF

# 复制 SSL 证书
if [ -d "/etc/letsencrypt/live/${DOMAIN}" ]; then
    echo "复制 SSL 证书..."
    cp -r /etc/letsencrypt/* ssl/
fi

# 生成自定义登录页面
if [ -f "generate-login-page.sh" ]; then
    echo "生成自定义登录页面..."
    ./generate-login-page.sh "$SYSTEM_NAME"
fi

# 启动服务
echo "启动服务..."
docker compose down > /dev/null 2>&1 || true
docker compose up -d

# 等待服务
echo "等待服务启动..."
sleep 10

# 显示结果
echo ""
echo "========================================="
echo "部署完成！"
echo "========================================="
echo ""
echo "系统名称：$SYSTEM_NAME"
echo "访问地址：https://${DOMAIN}"
echo "用户名：$USERNAME"
echo "密码：$PASSWORD"
echo ""
echo "查看状态：docker compose ps"
echo "查看日志：docker compose logs -f"
echo ""
