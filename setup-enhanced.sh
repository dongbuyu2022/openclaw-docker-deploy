#!/bin/bash
set -e

# ============================================================================
# OpenClaw Docker 完整部署脚本（增强版）
# 包含：环境检查、依赖安装、防火墙配置、端口检查
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

# 需要的端口
REQUIRED_PORTS=(80 443)

# 需要的依赖
REQUIRED_PACKAGES=(curl wget git openssl ca-certificates gnupg lsb-release)

# ============================================================================
# UI 函数
# ============================================================================

check_whiptail() {
    if ! command -v whiptail &> /dev/null; then
        echo "正在安装 whiptail..."
        apt-get update -qq
        apt-get install -y -qq whiptail > /dev/null 2>&1
    fi
}

show_msgbox() {
    whiptail --title "$1" --msgbox "$2" 20 70
}

show_inputbox() {
    whiptail --title "$1" --inputbox "$2" 10 60 "$3" 3>&1 1>&2 2>&3
}

show_passwordbox() {
    whiptail --title "$1" --passwordbox "$2" 10 60 3>&1 1>&2 2>&3
}

show_yesno() {
    whiptail --title "$1" --yesno "$2" 15 70
}

show_menu() {
    local title="$1"
    local message="$2"
    shift 2
    whiptail --title "$title" --menu "$message" 20 70 10 "$@" 3>&1 1>&2 2>&3
}

show_gauge() {
    whiptail --title "$1" --gauge "$2" 8 60 0
}

show_checklist() {
    local title="$1"
    local message="$2"
    shift 2
    whiptail --title "$title" --checklist "$message" 20 70 10 "$@" 3>&1 1>&2 2>&3
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
        show_msgbox "权限错误" "请使用 root 用户运行此脚本\n\n使用命令：sudo ./setup-enhanced.sh"
        exit 1
    fi
}

check_ubuntu() {
    if [ ! -f /etc/os-release ]; then
        show_msgbox "系统错误" "无法检测操作系统"
        exit 1
    fi

    . /etc/os-release
    if [ "$ID" != "ubuntu" ]; then
        show_msgbox "系统不支持" "此脚本仅支持 Ubuntu 系统\n\n当前系统：$ID $VERSION"
        exit 1
    fi

    # 检查版本
    local version_id=$(echo $VERSION_ID | cut -d. -f1)
    if [ "$version_id" -lt 20 ]; then
        show_msgbox "版本过旧" "建议使用 Ubuntu 20.04 或更高版本\n\n当前版本：$VERSION"
        if ! show_yesno "继续？" "当前 Ubuntu 版本较旧，可能存在兼容性问题\n\n是否继续？"; then
            exit 1
        fi
    fi

    log_success "系统检查通过：Ubuntu $VERSION"
}

check_system_resources() {
    local total_mem=$(free -m | awk '/^Mem:/{print $2}')
    local total_disk=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    local cpu_cores=$(nproc)

    local warnings=""

    # 检查内存（建议至少 2GB）
    if [ "$total_mem" -lt 2000 ]; then
        warnings+="⚠ 内存不足：${total_mem}MB（建议至少 2GB）\n"
    fi

    # 检查磁盘空间（建议至少 10GB）
    if [ "$total_disk" -lt 10 ]; then
        warnings+="⚠ 磁盘空间不足：${total_disk}GB（建议至少 10GB）\n"
    fi

    # 检查 CPU 核心（建议至少 2 核）
    if [ "$cpu_cores" -lt 2 ]; then
        warnings+="⚠ CPU 核心较少：${cpu_cores} 核（建议至少 2 核）\n"
    fi

    if [ -n "$warnings" ]; then
        local message="系统资源检查\n\n"
        message+="CPU：${cpu_cores} 核\n"
        message+="内存：${total_mem}MB\n"
        message+="磁盘：${total_disk}GB\n\n"
        message+="$warnings\n"
        message+="是否继续部署？"

        if ! show_yesno "资源警告" "$message"; then
            exit 1
        fi
    else
        log_success "系统资源充足：CPU ${cpu_cores}核 / 内存 ${total_mem}MB / 磁盘 ${total_disk}GB"
    fi
}

# ============================================================================
# 依赖检查和安装
# ============================================================================

check_and_install_dependencies() {
    log_info "检查系统依赖..."

    local missing_packages=()

    for package in "${REQUIRED_PACKAGES[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package"; then
            missing_packages+=("$package")
        fi
    done

    if [ ${#missing_packages[@]} -gt 0 ]; then
        local message="需要安装以下依赖包：\n\n"
        for pkg in "${missing_packages[@]}"; do
            message+="- $pkg\n"
        done
        message+="\n是否现在安装？"

        if show_yesno "安装依赖" "$message"; then
            {
                echo "10"
                apt-get update -qq
                echo "50"
                apt-get install -y -qq "${missing_packages[@]}" > /dev/null 2>&1
                echo "100"
            } | show_gauge "安装依赖" "正在安装系统依赖..."

            log_success "依赖安装完成"
        else
            show_msgbox "取消" "缺少必要依赖，无法继续部署"
            exit 1
        fi
    else
        log_success "所有依赖已安装"
    fi
}

check_docker() {
    if ! command -v docker &> /dev/null; then
        if show_yesno "Docker 未安装" "检测到 Docker 未安装\n\nDocker 是运行 OpenClaw 的必要组件\n\n是否现在安装？"; then
            install_docker
        else
            show_msgbox "取消" "Docker 是必需的，无法继续部署"
            exit 1
        fi
    else
        local docker_version=$(docker --version | awk '{print $3}' | sed 's/,//')
        log_success "Docker 已安装：$docker_version"
    fi

    if ! docker compose version &> /dev/null; then
        show_msgbox "错误" "Docker Compose 未安装或版本过旧\n\n请安装 Docker Compose V2"
        exit 1
    fi

    # 检查 Docker 服务状态
    if ! systemctl is-active --quiet docker; then
        log_info "启动 Docker 服务..."
        systemctl start docker
        systemctl enable docker
    fi

    log_success "Docker 检查通过"
}

install_docker() {
    {
        echo "5"
        log_info "准备安装 Docker..."
        sleep 1

        echo "15"
        apt-get update -qq

        echo "25"
        apt-get install -y -qq ca-certificates curl gnupg > /dev/null 2>&1

        echo "35"
        install -m 0755 -d /etc/apt/keyrings

        echo "45"
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null
        chmod a+r /etc/apt/keyrings/docker.gpg

        echo "55"
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

        echo "65"
        apt-get update -qq

        echo "80"
        apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin > /dev/null 2>&1

        echo "95"
        systemctl start docker
        systemctl enable docker

        echo "100"
        sleep 1
    } | show_gauge "安装 Docker" "正在安装 Docker，请稍候..."

    log_success "Docker 安装完成"
}

# ============================================================================
# 端口检查
# ============================================================================

check_port_available() {
    local port=$1
    if netstat -tuln 2>/dev/null | grep -q ":$port " || ss -tuln 2>/dev/null | grep -q ":$port "; then
        return 1
    fi
    return 0
}

check_ports() {
    log_info "检查端口占用..."

    local occupied_ports=()

    for port in "${REQUIRED_PORTS[@]}"; do
        if ! check_port_available "$port"; then
            occupied_ports+=("$port")
        fi
    done

    if [ ${#occupied_ports[@]} -gt 0 ]; then
        local message="以下端口已被占用：\n\n"
        for port in "${occupied_ports[@]}"; do
            local process=$(netstat -tulnp 2>/dev/null | grep ":$port " | awk '{print $7}' | head -1)
            message+="端口 $port：$process\n"
        done
        message+="\n需要释放这些端口才能继续\n\n"
        message+="建议操作：\n"
        message+="1. 停止占用端口的服务\n"
        message+="2. 修改其他服务的端口\n"

        show_msgbox "端口冲突" "$message"

        if ! show_yesno "继续？" "端口被占用可能导致部署失败\n\n是否继续？"; then
            exit 1
        fi
    else
        log_success "所有必需端口可用"
    fi
}

# ============================================================================
# 防火墙配置
# ============================================================================

check_firewall() {
    log_info "检查防火墙配置..."

    local firewall_active=false
    local firewall_type=""

    # 检查 UFW
    if command -v ufw &> /dev/null; then
        if ufw status | grep -q "Status: active"; then
            firewall_active=true
            firewall_type="UFW"
        fi
    fi

    # 检查 firewalld
    if command -v firewall-cmd &> /dev/null; then
        if systemctl is-active --quiet firewalld; then
            firewall_active=true
            firewall_type="firewalld"
        fi
    fi

    # 检查 iptables
    if command -v iptables &> /dev/null; then
        if iptables -L | grep -q "Chain INPUT"; then
            local rules_count=$(iptables -L INPUT -n | grep -c "ACCEPT\|DROP\|REJECT" || echo "0")
            if [ "$rules_count" -gt 5 ]; then
                firewall_active=true
                firewall_type="iptables"
            fi
        fi
    fi

    if [ "$firewall_active" = true ]; then
        local message="检测到防火墙：$firewall_type\n\n"
        message+="OpenClaw 需要开放以下端口：\n"
        message+="- 80 (HTTP)\n"
        message+="- 443 (HTTPS)\n\n"
        message+="是否自动配置防火墙？"

        if show_yesno "防火墙配置" "$message"; then
            configure_firewall "$firewall_type"
        else
            show_msgbox "提醒" "请手动开放端口 80 和 443\n\n否则可能无法访问 OpenClaw"
        fi
    else
        log_info "未检测到活动的防火墙"
    fi
}

configure_firewall() {
    local firewall_type=$1

    {
        echo "20"
        case $firewall_type in
            "UFW")
                ufw allow 80/tcp > /dev/null 2>&1
                echo "50"
                ufw allow 443/tcp > /dev/null 2>&1
                echo "80"
                ufw reload > /dev/null 2>&1
                ;;
            "firewalld")
                firewall-cmd --permanent --add-service=http > /dev/null 2>&1
                echo "50"
                firewall-cmd --permanent --add-service=https > /dev/null 2>&1
                echo "80"
                firewall-cmd --reload > /dev/null 2>&1
                ;;
            "iptables")
                iptables -I INPUT -p tcp --dport 80 -j ACCEPT
                echo "50"
                iptables -I INPUT -p tcp --dport 443 -j ACCEPT
                echo "80"
                # 保存规则
                if command -v netfilter-persistent &> /dev/null; then
                    netfilter-persistent save > /dev/null 2>&1
                elif command -v iptables-save &> /dev/null; then
                    iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
                fi
                ;;
        esac
        echo "100"
    } | show_gauge "配置防火墙" "正在配置防火墙规则..."

    log_success "防火墙配置完成"
}

# ============================================================================
# 环境检查总结
# ============================================================================

show_environment_check() {
    local check_result="/tmp/openclaw_env_check.txt"

    {
        echo "环境检查报告"
        echo "============================================"
        echo ""

        echo "系统信息："
        . /etc/os-release
        echo "  操作系统：$PRETTY_NAME"
        echo "  内核版本：$(uname -r)"
        echo "  CPU 核心：$(nproc)"
        echo "  内存大小：$(free -h | awk '/^Mem:/{print $2}')"
        echo "  磁盘空间：$(df -h / | awk 'NR==2 {print $4}')"
        echo ""

        echo "Docker 信息："
        if command -v docker &> /dev/null; then
            echo "  Docker 版本：$(docker --version | awk '{print $3}' | sed 's/,//')"
            echo "  Compose 版本：$(docker compose version --short)"
        else
            echo "  Docker：未安装"
        fi
        echo ""

        echo "端口状态："
        for port in "${REQUIRED_PORTS[@]}"; do
            if check_port_available "$port"; then
                echo "  端口 $port：✓ 可用"
            else
                echo "  端口 $port：✗ 已占用"
            fi
        done
        echo ""

        echo "防火墙状态："
        if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
            echo "  UFW：活动"
        elif command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
            echo "  firewalld：活动"
        else
            echo "  防火墙：未检测到"
        fi
        echo ""

        echo "============================================"
    } > "$check_result"

    show_msgbox "环境检查" "$(cat $check_result)"
    rm -f "$check_result"
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
    if [ ${#password} -lt 8 ]; then
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
            USERNAME=$(generate_username)
            PASSWORD=$(generate_password)
            show_msgbox "凭据已生成" "用户名：$USERNAME\n密码：$PASSWORD\n\n请妥善保管这些信息！"
            ;;
        2)
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

# ============================================================================
# 域名配置
# ============================================================================

validate_domain() {
    local domain="$1"
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
        SERVER_IP=$(curl -s ifconfig.me || curl -s icanhazip.com || echo "YOUR_SERVER_IP")
        ACCESS_URL="http://$SERVER_IP"
    fi
}

# ============================================================================
# 部署函数
# ============================================================================

deploy_openclaw() {
    log_info "开始部署 OpenClaw..."

    # 创建 .env 文件
    {
        echo "20"
        cat > .env << EOF
# OpenClaw 配置
OPENCLAW_VERSION=latest

# 域名配置
DOMAIN=${DOMAIN:-localhost}

# 管理员账号
ADMIN_USERNAME=${USERNAME}
ADMIN_PASSWORD=${PASSWORD}

# 时区
TZ=Asia/Shanghai
EOF
        echo "40"
        sleep 1
    } | show_gauge "创建配置" "正在创建配置文件..."

    log_success "配置文件创建完成"

    # 启动服务
    {
        echo "20"
        docker compose pull 2>&1 | grep -v "^$" || true
        echo "60"
        docker compose up -d 2>&1 | grep -v "^$" || true
        echo "100"
    } | show_gauge "启动服务" "正在启动 Docker 容器..."

    log_success "服务启动完成"

    # 等待服务就绪
    {
        for i in {1..30}; do
            if docker compose ps | grep -q "Up"; then
                echo "100"
                break
            fi
            echo $((i * 3))
            sleep 1
        done
    } | show_gauge "等待服务" "等待服务启动..."

    log_success "OpenClaw 部署完成！"
}

show_deployment_complete() {
    local info="🎉 OpenClaw 部署完成！\n\n"
    info+="访问地址：$ACCESS_URL\n"
    info+="用户名：$USERNAME\n"
    info+="密码：$PASSWORD\n\n"
    info+="管理命令：\n"
    info+="  查看状态：docker compose ps\n"
    info+="  查看日志：docker compose logs -f\n"
    info+="  停止服务：docker compose stop\n"
    info+="  启动服务：docker compose start\n"
    info+="  重启服务：docker compose restart\n\n"
    info+="管理菜单：./manage.sh"

    show_msgbox "部署完成" "$info"

    # 保存访问信息
    cat > /root/openclaw-access-info.txt << EOF
OpenClaw 访问信息
================

访问地址：$ACCESS_URL
用户名：$USERNAME
密码：$PASSWORD

部署时间：$(date '+%Y-%m-%d %H:%M:%S')
部署目录：$(pwd)

管理命令：
  docker compose ps       # 查看状态
  docker compose logs -f  # 查看日志
  docker compose restart  # 重启服务
  ./manage.sh            # 管理菜单
EOF

    log_success "访问信息已保存到：/root/openclaw-access-info.txt"
}

# ============================================================================
# 主函数
# ============================================================================

main() {
    # 基础检查
    check_root
    check_whiptail
    check_ubuntu

    # 显示欢迎界面
    show_msgbox "欢迎" "欢迎使用 OpenClaw 完整部署脚本\n\n本脚本将：\n✓ 检查系统环境\n✓ 安装必要依赖\n✓ 配置防火墙\n✓ 部署 OpenClaw\n\n预计耗时：5-15 分钟"

    # 系统资源检查
    check_system_resources

    # 依赖检查和安装
    check_and_install_dependencies

    # Docker 检查和安装
    check_docker

    # 端口检查
    check_ports

    # 防火墙配置
    check_firewall

    # 显示环境检查结果
    if show_yesno "环境检查" "环境检查完成！\n\n是否查看详细报告？"; then
        show_environment_check
    fi

    # 配置域名
    configure_domain

    # 配置凭据
    configure_credentials

    # 显示配置摘要并确认
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

    # 开始部署
    log_success "准备开始部署..."

    deploy_openclaw

    # 显示部署完成信息
    show_deployment_complete
}

# 运行主函数
main "$@"
