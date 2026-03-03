#!/bin/bash
set -e

# ============================================================================
# OpenClaw Docker 交互式部署脚本（完整版）
# ============================================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志函数
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 检查 root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 root 用户运行此脚本"
        exit 1
    fi
}

# 检查 whiptail
check_whiptail() {
    if ! command -v whiptail &> /dev/null; then
        log_info "正在安装 whiptail..."
        apt-get update -qq && apt-get install -y -qq whiptail > /dev/null 2>&1
    fi
}

# UI 函数
show_msgbox() {
    whiptail --title "$1" --msgbox "$2" 15 60
}

show_inputbox() {
    whiptail --title "$1" --inputbox "$2" 10 60 "$3" 3>&1 1>&2 2>&3
}

show_yesno() {
    whiptail --title "$1" --yesno "$2" 12 60
}

show_menu() {
    local title="$1"
    local message="$2"
    shift 2
    whiptail --title "$title" --menu "$message" 15 60 4 "$@" 3>&1 1>&2 2>&3
}

# 检查 Docker
check_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker 未安装"
        if show_yesno "安装 Docker" "是否现在安装 Docker？"; then
            log_info "正在安装 Docker..."
            curl -fsSL https://get.docker.com | sh
            systemctl start docker
            systemctl enable docker
            log_success "Docker 安装完成"
        else
            exit 1
        fi
    fi

    if ! docker compose version &> /dev/null; then
        log_error "Docker Compose 未安装"
        exit 1
    fi

    log_success "Docker 检查通过"
}

# 生成用户名和密码
generate_username() {
    echo "admin_$(openssl rand -hex 3)"
}

generate_password() {
    openssl rand -base64 16 | tr -d "=+/" | cut -c1-16
}

# 配置系统名称
configure_system_name() {
    local choice=$(show_menu "系统名称" "请为您的 AI 助手系统命名：" \
        "1" "使用默认名称（OpenClaw AI）" \
        "2" "自定义名称")

    case $choice in
        1)
            SYSTEM_NAME="OpenClaw AI"
            ;;
        2)
            SYSTEM_NAME=$(show_inputbox "自定义系统名称" "请输入系统名称（2-20个字符）：" "我的AI助手")
            if [ -z "$SYSTEM_NAME" ]; then
                SYSTEM_NAME="OpenClaw AI"
            fi
            ;;
        *)
            SYSTEM_NAME="OpenClaw AI"
            ;;
    esac

    log_success "系统名称：$SYSTEM_NAME"
}

# 配置域名
configure_domain() {
    local choice=$(show_menu "域名配置" "您是否已经准备好域名？" \
        "1" "是，现在配置域名" \
        "2" "否，稍后配置（使用 IP 访问）")

    case $choice in
        1)
            DOMAIN=$(show_inputbox "输入域名" "请输入您的域名（例如：example.com）：" "")
            if [ -z "$DOMAIN" ]; then
                log_warning "域名为空，将使用 IP 访问"
                USE_DOMAIN=false
            else
                USE_DOMAIN=true
                log_success "域名配置完成：$DOMAIN"
            fi
            ;;
        2)
            DOMAIN=""
            USE_DOMAIN=false
            log_info "跳过域名配置"
            ;;
    esac
}

# 配置凭据
configure_credentials() {
    local choice=$(show_menu "管理员账号配置" "请选择账号配置方式：" \
        "1" "自动生成（推荐）" \
        "2" "手动输入")

    case $choice in
        1)
            USERNAME=$(generate_username)
            PASSWORD=$(generate_password)
            show_msgbox "凭据已生成" "用户名：$USERNAME\n密码：$PASSWORD\n\n请妥善保管这些信息！"
            ;;
        2)
            USERNAME=$(show_inputbox "输入用户名" "请输入管理员用户名：" "admin")
            PASSWORD=$(show_inputbox "输入密码" "请输入管理员密码（至少8位）：" "")
            if [ ${#PASSWORD} -lt 8 ]; then
                log_error "密码长度至少为8位"
                exit 1
            fi
            ;;
    esac

    ADMIN_EMAIL="${USERNAME}@localhost"
    log_success "凭据配置完成"
}

# 创建 .env 文件
create_env_file() {
    log_info "创建环境配置文件..."

    cat > .env << EOF
# OpenClaw Docker 环境配置
# 生成时间：$(date '+%Y-%m-%d %H:%M:%S')

# 域名配置
DOMAIN=${DOMAIN:-localhost}

# 系统名称
SYSTEM_NAME=${SYSTEM_NAME}

# 管理员账号
ADMIN_USERNAME=${USERNAME}
ADMIN_PASSWORD=${PASSWORD}
ADMIN_EMAIL=${ADMIN_EMAIL}

# OpenClaw 版本
OPENCLAW_VERSION=latest

# Watchtower 更新间隔（秒）
WATCHTOWER_INTERVAL=86400

# 时区
TZ=Asia/Shanghai
EOF

    log_success "环境配置文件创建完成"
}

# 创建目录结构
create_directories() {
    log_info "创建目录结构..."

    mkdir -p openclaw/config openclaw/data openclaw/workspace
    mkdir -p authelia nginx/conf.d ssl certbot-webroot backup

    log_success "目录创建完成"
}

# 生成安全密钥
generate_secrets() {
    log_info "生成安全密钥..."

    openssl rand -base64 64 > authelia/jwt_secret
    openssl rand -base64 64 > authelia/session_secret
    openssl rand -base64 64 > authelia/encryption_key
    chmod 600 authelia/*_secret authelia/*_key

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

    source .env

    log_info "生成密码哈希（这可能需要几秒钟）..."
    PASSWORD_HASH=$(generate_password_hash "$ADMIN_PASSWORD")

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

    source .env

    # 创建主配置
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

    # 创建虚拟主机配置（直接替换变量，不使用模板）
    cat > nginx/conf.d/openclaw.conf << EOF
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
        return 301 https://\$host\$request_uri;
    }
}

# HTTPS 主配置
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
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

    # 安全头
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Authelia 认证端点（内部使用）
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

    # Authelia Web UI（登录页面）
    location ^~ /authelia {
        proxy_pass http://authelia:9091/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$http_host;
        proxy_set_header X-Forwarded-Uri \$request_uri;
        proxy_set_header X-Forwarded-Prefix /authelia;
    }

    # Authelia 静态资源（不需要认证）
    location ~* ^/(static|locales) {
        proxy_pass http://authelia:9091;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        expires 1h;
        add_header Cache-Control "public, immutable";
    }

    # OpenClaw 静态资源（不需要认证）
    location ~* ^/(assets|favicon\.|apple-touch-icon|robots\.txt) {
        proxy_pass http://openclaw:18789;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
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
        auth_request_set \$user \$upstream_http_remote_user;
        auth_request_set \$groups \$upstream_http_remote_groups;
        auth_request_set \$name \$upstream_http_remote_name;
        auth_request_set \$email \$upstream_http_remote_email;

        # 认证失败重定向到登录页
        error_page 401 =302 https://\$host/authelia/;

        # 代理到 OpenClaw
        proxy_pass http://openclaw:18789;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # 传递认证信息到 OpenClaw
        proxy_set_header Remote-User \$user;
        proxy_set_header Remote-Groups \$groups;
        proxy_set_header Remote-Name \$name;
        proxy_set_header Remote-Email \$email;

        # WebSocket 支持
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 3600;
        proxy_send_timeout 3600;
    }
}
EOF

    log_success "Nginx 配置完成"
}

# 处理 SSL 证书
setup_ssl() {
    log_info "配置 SSL 证书..."

    source .env

    # 检查是否有现有证书
    if [ -d "/etc/letsencrypt/live/${DOMAIN}" ]; then
        log_info "发现现有 SSL 证书，正在复制..."
        cp -r /etc/letsencrypt/* ssl/
        log_success "SSL 证书复制完成"
    else
        log_info "创建自签名证书用于测试..."
        mkdir -p "ssl/live/${DOMAIN}"
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "ssl/live/${DOMAIN}/privkey.pem" \
            -out "ssl/live/${DOMAIN}/fullchain.pem" \
            -subj "/CN=${DOMAIN}" > /dev/null 2>&1
        cp "ssl/live/${DOMAIN}/fullchain.pem" "ssl/live/${DOMAIN}/chain.pem"
        log_success "自签名证书创建完成"
    fi
}

# 生成自定义登录页面
generate_custom_login() {
    log_info "生成自定义登录页面..."

    if [ -f "generate-login-page.sh" ]; then
        ./generate-login-page.sh "$SYSTEM_NAME" > /dev/null 2>&1
        log_success "自定义登录页面生成完成"
    else
        log_warning "登录页面生成脚本不存在，跳过"
    fi
}

# 启动服务
start_services() {
    log_info "启动所有服务..."

    docker compose down > /dev/null 2>&1 || true
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

# 保存访问信息
save_access_info() {
    source .env

    local access_url
    if [ "$USE_DOMAIN" = true ]; then
        access_url="https://${DOMAIN}"
    else
        local server_ip=$(curl -s ifconfig.me || echo "YOUR_SERVER_IP")
        access_url="http://${server_ip}"
    fi

    cat > /root/openclaw-access-info.txt << EOF
OpenClaw 访问信息
================

系统名称：${SYSTEM_NAME}
访问地址：${access_url}
用户名：${USERNAME}
密码：${PASSWORD}

部署时间：$(date '+%Y-%m-%d %H:%M:%S')
部署目录：$(pwd)

管理命令：
  docker compose ps       # 查看状态
  docker compose logs -f  # 查看日志
  docker compose restart  # 重启服务
  ./manage.sh            # 管理菜单
EOF

    cat > credentials.txt << EOF
系统名称：${SYSTEM_NAME}
访问地址：${access_url}
用户名：${USERNAME}
密码：${PASSWORD}
EOF

    log_success "访问信息已保存"
}

# 显示完成信息
show_completion() {
    source .env

    local access_url
    if [ "$USE_DOMAIN" = true ]; then
        access_url="https://${DOMAIN}"
    else
        local server_ip=$(curl -s ifconfig.me || echo "YOUR_SERVER_IP")
        access_url="http://${server_ip}"
    fi

    echo ""
    echo "========================================="
    echo -e "${GREEN}OpenClaw 部署完成！${NC}"
    echo "========================================="
    echo ""
    echo "系统名称：${SYSTEM_NAME}"
    echo "访问地址：${access_url}"
    echo "用户名：${USERNAME}"
    echo "密码：${PASSWORD}"
    echo ""
    echo "访问信息已保存到："
    echo "  - /root/openclaw-access-info.txt"
    echo "  - $(pwd)/credentials.txt"
    echo ""
    echo "常用命令："
    echo "  docker compose ps       # 查看状态"
    echo "  docker compose logs -f  # 查看日志"
    echo "  docker compose restart  # 重启服务"
    echo "  ./manage.sh            # 管理菜单"
    echo ""
    echo "========================================="
}

# 主函数
main() {
    echo ""
    echo "========================================="
    echo "  OpenClaw Docker 交互式部署脚本"
    echo "========================================="
    echo ""

    # 环境检查
    check_root
    check_whiptail
    check_docker

    # 显示欢迎
    show_msgbox "欢迎" "欢迎使用 OpenClaw 交互式部署脚本\n\n本脚本将：\n✓ 配置系统名称\n✓ 配置域名\n✓ 配置管理员账号\n✓ 自动部署所有服务\n\n预计耗时：5-10 分钟"

    # 配置阶段
    configure_system_name
    configure_domain
    configure_credentials

    # 确认配置
    local summary="部署配置确认\n\n"
    summary+="系统名称：$SYSTEM_NAME\n"
    if [ "$USE_DOMAIN" = true ]; then
        summary+="域名：$DOMAIN\n"
    else
        summary+="访问方式：IP 地址\n"
    fi
    summary+="用户名：$USERNAME\n"
    summary+="密码：$PASSWORD\n"
    summary+="\n是否确认并开始部署？"

    if ! show_yesno "确认配置" "$summary"; then
        log_error "已取消部署"
        exit 1
    fi

    # 部署阶段
    create_env_file
    create_directories
    generate_secrets
    configure_authelia
    configure_nginx
    setup_ssl
    generate_custom_login
    start_services
    wait_for_services
    save_access_info
    show_completion
}

# 运行主函数
main "$@"
