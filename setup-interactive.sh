#!/bin/bash
set -e

# ============================================================================
# OpenClaw Docker 交互式部署脚本
# ============================================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 配置变量
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
CREDENTIALS_FILE="$SCRIPT_DIR/credentials.txt"

# ============================================================================
# UI 函数
# ============================================================================

# 检查 whiptail 是否可用
check_whiptail() {
    if ! command -v whiptail &> /dev/null; then
        echo "正在安装 whiptail..."
        apt-get update -qq
        apt-get install -y -qq whiptail > /dev/null 2>&1
    fi
}

# 显示消息框
show_msgbox() {
    local title="$1"
    local message="$2"
    whiptail --title "$title" --msgbox "$message" 15 60
}

# 显示输入框
show_inputbox() {
    local title="$1"
    local message="$2"
    local default="$3"
    whiptail --title "$title" --inputbox "$message" 10 60 "$default" 3>&1 1>&2 2>&3
}

# 显示密码输入框
show_passwordbox() {
    local title="$1"
    local message="$2"
    whiptail --title "$title" --passwordbox "$message" 10 60 3>&1 1>&2 2>&3
}

# 显示是/否对话框
show_yesno() {
    local title="$1"
    local message="$2"
    whiptail --title "$title" --yesno "$message" 10 60
}

# 显示菜单
show_menu() {
    local title="$1"
    local message="$2"
    shift 2
    whiptail --title "$title" --menu "$message" 20 70 10 "$@" 3>&1 1>&2 2>&3
}

# 显示进度
show_gauge() {
    local title="$1"
    local message="$2"
    whiptail --title "$title" --gauge "$message" 8 60 0
}

# ============================================================================
# 日志函数
# ============================================================================

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

# ============================================================================
# 系统检查
# ============================================================================

check_root() {
    if [ "$EUID" -ne 0 ]; then
        show_msgbox "错误" "请使用 root 用户运行此脚本\n\n使用命令：sudo ./setup.sh"
        exit 1
    fi
}

check_ubuntu() {
    if [ ! -f /etc/os-release ]; then
        show_msgbox "错误" "无法检测操作系统"
        exit 1
    fi

    . /etc/os-release
    if [ "$ID" != "ubuntu" ]; then
        show_msgbox "错误" "此脚本仅支持 Ubuntu 系统\n\n当前系统：$ID"
        exit 1
    fi

    log_success "系统检查通过：Ubuntu $VERSION"
}

check_docker() {
    if ! command -v docker &> /dev/null; then
        if show_yesno "Docker 未安装" "检测到 Docker 未安装，是否现在安装？"; then
            install_docker
        else
            show_msgbox "取消" "Docker 是必需的，无法继续部署"
            exit 1
        fi
    fi

    if ! docker compose version &> /dev/null; then
        show_msgbox "错误" "Docker Compose 未安装或版本过旧\n\n请安装 Docker Compose V2"
        exit 1
    fi

    log_success "Docker 检查通过"
}

install_docker() {
    {
        echo "10" ; sleep 1
        apt-get update -qq
        echo "30" ; sleep 1
        apt-get install -y -qq ca-certificates curl gnupg > /dev/null 2>&1
        echo "50" ; sleep 1
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg
        echo "70" ; sleep 1
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        apt-get update -qq
        echo "90" ; sleep 1
        apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin > /dev/null 2>&1
        echo "100" ; sleep 1
    } | show_gauge "安装 Docker" "正在安装 Docker，请稍候..."

    log_success "Docker 安装完成"
}

# ============================================================================
# 凭据管理
# ============================================================================

generate_username() {
    local random_suffix=$(openssl rand -hex 3)
    echo "admin_${random_suffix}"
}

generate_password() {
    openssl rand -base64 16 | tr -d "=+/" | cut -c1-16
}

validate_password() {
    local password="$1"
    local length=${#password}

    if [ $length -lt 8 ]; then
        return 1
    fi

    return 0
}

configure_credentials() {
    local choice=$(show_menu "管理员账号配置" "请选择账号配置方式：" \
        "1" "自动生成（推荐）" \
        "2" "手动输入")

    case $choice in
        1)
            # 自动生成
            USERNAME=$(generate_username)
            PASSWORD=$(generate_password)

            show_msgbox "凭据已生成" "用户名：$USERNAME\n密码：$PASSWORD\n\n请妥善保管这些信息！"
            ;;
        2)
            # 手动输入
            while true; do
                USERNAME=$(show_inputbox "输入用户名" "请输入管理员用户名：" "admin")

                if [ -z "$USERNAME" ]; then
                    show_msgbox "错误" "用户名不能为空"
                    continue
                fi

                PASSWORD=$(show_passwordbox "输入密码" "请输入管理员密码（至少8位）：")

                if [ -z "$PASSWORD" ]; then
                    show_msgbox "错误" "密码不能为空"
                    continue
                fi

                if ! validate_password "$PASSWORD"; then
                    show_msgbox "错误" "密码长度至少为8位"
                    continue
                fi

                PASSWORD_CONFIRM=$(show_passwordbox "确认密码" "请再次输入密码：")

                if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
                    show_msgbox "错误" "两次输入的密码不一致"
                    continue
                fi

                break
            done
            ;;
        *)
            show_msgbox "取消" "已取消配置"
            exit 1
            ;;
    esac

    log_success "凭据配置完成"
}

save_credentials() {
    cat > "$CREDENTIALS_FILE" << EOF
OpenClaw 管理员凭据
==================

访问地址：${ACCESS_URL}
用户名：${USERNAME}
密码：${PASSWORD}

生成时间：$(date '+%Y-%m-%d %H:%M:%S')

请妥善保管此文件！
EOF

    chmod 600 "$CREDENTIALS_FILE"
    log_success "凭据已保存到：$CREDENTIALS_FILE"
}

# ============================================================================
# 域名配置
# ============================================================================

validate_domain() {
    local domain="$1"

    # 基本格式检查
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 1
    fi

    return 0
}

check_dns() {
    local domain="$1"

    if host "$domain" > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

configure_domain() {
    local choice=$(show_menu "域名配置" "您是否已经准备好域名？" \
        "1" "是，现在配置域名" \
        "2" "否，稍后配置（使用 IP 访问）")

    case $choice in
        1)
            while true; do
                DOMAIN=$(show_inputbox "输入域名" "请输入您的域名（例如：example.com）：" "")

                if [ -z "$DOMAIN" ]; then
                    if show_yesno "确认" "域名为空，是否跳过域名配置？"; then
                        DOMAIN=""
                        USE_DOMAIN=false
                        break
                    else
                        continue
                    fi
                fi

                if ! validate_domain "$DOMAIN"; then
                    show_msgbox "错误" "域名格式不正确\n\n请输入有效的域名"
                    continue
                fi

                # 检查 DNS
                if ! check_dns "$DOMAIN"; then
                    if show_yesno "DNS 警告" "域名 $DOMAIN 的 DNS 解析失败\n\n请确保：\n1. 域名已正确配置 DNS\n2. DNS 记录已生效\n\n是否继续？"; then
                        USE_DOMAIN=true
                        break
                    else
                        continue
                    fi
                else
                    USE_DOMAIN=true
                    break
                fi
            done
            ;;
        2)
            DOMAIN=""
            USE_DOMAIN=false
            ;;
        *)
            show_msgbox "取消" "已取消配置"
            exit 1
            ;;
    esac

    if [ "$USE_DOMAIN" = true ]; then
        log_success "域名配置完成：$DOMAIN"
        ACCESS_URL="https://$DOMAIN"
    else
        log_info "跳过域名配置，将使用 IP 访问"
        SERVER_IP=$(curl -s ifconfig.me || echo "YOUR_SERVER_IP")
        ACCESS_URL="http://$SERVER_IP"
    fi
}

# ============================================================================
# 环境配置
# ============================================================================

create_env_file() {
    cat > "$ENV_FILE" << EOF
# OpenClaw Docker 环境配置
# 生成时间：$(date '+%Y-%m-%d %H:%M:%S')

# 域名配置
DOMAIN=${DOMAIN}

# 管理员账号
ADMIN_USERNAME=${USERNAME}
ADMIN_PASSWORD=${PASSWORD}
ADMIN_EMAIL=admin@${DOMAIN:-localhost}

# OpenClaw 版本
OPENCLAW_VERSION=latest

# Watchtower 更新间隔（秒）
WATCHTOWER_INTERVAL=86400

# 时区
TZ=Asia/Shanghai

# Telegram Bot Token（可选）
TELEGRAM_BOT_TOKEN=

# API Keys（可选）
ANTHROPIC_API_KEY=
OPENAI_API_KEY=
EOF

    chmod 600 "$ENV_FILE"
    log_success "环境配置文件已创建"
}

# ============================================================================
# 部署流程
# ============================================================================

show_welcome() {
    show_msgbox "欢迎" "欢迎使用 OpenClaw 一键部署脚本\n\n本脚本将帮助您快速部署 OpenClaw\n预计耗时：5-10 分钟\n\n支持系统：Ubuntu 20.04/22.04/24.04"
}

show_summary() {
    local summary="部署配置确认\n\n"

    if [ "$USE_DOMAIN" = true ]; then
        summary+="域名：$DOMAIN\n"
        summary+="访问地址：https://$DOMAIN\n"
    else
        summary+="访问方式：IP 地址\n"
        summary+="访问地址：$ACCESS_URL\n"
    fi

    summary+="\n用户名：$USERNAME\n"
    summary+="密码：$PASSWORD\n"
    summary+="\n是否确认并开始部署？"

    if ! show_yesno "确认配置" "$summary"; then
        show_msgbox "取消" "已取消部署"
        exit 1
    fi
}

deploy_services() {
    {
        echo "10"
        log_info "创建目录结构..."
        mkdir -p openclaw/config openclaw/data openclaw/workspace
        mkdir -p authelia nginx/conf.d nginx/templates ssl certbot-webroot backup
        sleep 1

        echo "20"
        log_info "生成安全密钥..."
        openssl rand -base64 64 > authelia/jwt_secret
        openssl rand -base64 64 > authelia/session_secret
        openssl rand -base64 64 > authelia/encryption_key
        chmod 600 authelia/*_secret authelia/*_key
        sleep 1

        echo "30"
        log_info "配置 Authelia..."
        configure_authelia_service
        sleep 1

        echo "50"
        log_info "配置 Nginx..."
        configure_nginx_service
        sleep 1

        echo "70"
        log_info "启动服务..."
        docker compose up -d > /dev/null 2>&1
        sleep 3

        echo "85"
        if [ "$USE_DOMAIN" = true ]; then
            log_info "申请 SSL 证书..."
            request_ssl_certificate
        fi
        sleep 1

        echo "100"
        log_success "部署完成！"
        sleep 1
    } | show_gauge "部署进度" "正在部署 OpenClaw，请稍候..."
}

configure_authelia_service() {
    source "$ENV_FILE"

    # 生成密码哈希
    PASSWORD_HASH=$(docker run --rm authelia/authelia:latest \
        authelia crypto hash generate argon2 --password "$ADMIN_PASSWORD" 2>/dev/null | \
        grep 'Digest:' | awk '{print $2}')

    # 创建配置文件
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
default_redirection_url: ${ACCESS_URL}

totp:
  disable: false
  issuer: OpenClaw

authentication_backend:
  file:
    path: /config/users_database.yml
    password:
      algorithm: argon2id

access_control:
  default_policy: deny
  rules:
    - domain: ${DOMAIN:-*}
      policy: one_factor

session:
  name: authelia_session
  secret: file:///config/session_secret
  expiration: 1h
  inactivity: 5m
  domain: ${DOMAIN:-localhost}

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
}

configure_nginx_service() {
    # Nginx 配置在之前的 docker-compose.yml 中已经包含
    # 这里只需要处理模板
    if [ "$USE_DOMAIN" = true ]; then
        envsubst '${DOMAIN}' < nginx/templates/openclaw.conf.template > nginx/conf.d/openclaw.conf 2>/dev/null || true
    fi
}

request_ssl_certificate() {
    if [ "$USE_DOMAIN" = false ]; then
        return 0
    fi

    # 简化的 SSL 证书申请
    docker run --rm \
        -v "$(pwd)/ssl:/etc/letsencrypt" \
        -v "$(pwd)/certbot-webroot:/var/www/certbot" \
        certbot/certbot certonly \
        --webroot \
        --webroot-path=/var/www/certbot \
        --email "${ADMIN_EMAIL}" \
        --agree-tos \
        --no-eff-email \
        -d "${DOMAIN}" > /dev/null 2>&1 || {
        log_warning "SSL 证书申请失败，将使用自签名证书"
        create_self_signed_certificate
    }
}

create_self_signed_certificate() {
    mkdir -p "ssl/live/${DOMAIN}"
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "ssl/live/${DOMAIN}/privkey.pem" \
        -out "ssl/live/${DOMAIN}/fullchain.pem" \
        -subj "/CN=${DOMAIN}" > /dev/null 2>&1
    cp "ssl/live/${DOMAIN}/fullchain.pem" "ssl/live/${DOMAIN}/chain.pem"
}

show_completion() {
    local message="部署完成！\n\n"
    message+="访问地址：${ACCESS_URL}\n"
    message+="用户名：${USERNAME}\n"
    message+="密码：${PASSWORD}\n\n"
    message+="凭据已保存到：\n${CREDENTIALS_FILE}\n\n"

    if [ "$USE_DOMAIN" = false ]; then
        message+="提示：您可以稍后运行 ./manage.sh 配置域名"
    fi

    show_msgbox "部署完成" "$message"
}

# ============================================================================
# 主函数
# ============================================================================

main() {
    # 检查环境
    check_root
    check_whiptail
    check_ubuntu
    check_docker

    # 显示欢迎界面
    show_welcome

    # 配置域名
    configure_domain

    # 配置凭据
    configure_credentials

    # 显示配置摘要
    show_summary

    # 创建环境文件
    create_env_file

    # 部署服务
    deploy_services

    # 保存凭据
    save_credentials

    # 显示完成信息
    show_completion

    log_success "所有操作已完成！"
}

# 运行主函数
main "$@"
