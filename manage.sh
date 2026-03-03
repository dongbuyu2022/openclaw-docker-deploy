#!/bin/bash
set -e

# ============================================================================
# OpenClaw 管理菜单脚本
# ============================================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 配置变量
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
CREDENTIALS_FILE="$SCRIPT_DIR/credentials.txt"

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
    whiptail --title "$1" --yesno "$2" 10 60
}

show_menu() {
    whiptail --title "$1" --menu "$2" 20 70 10 "$@" 3>&1 1>&2 2>&3
}

show_textbox() {
    whiptail --title "$1" --textbox "$2" 20 70 --scrolltext
}

# ============================================================================
# 功能函数
# ============================================================================

configure_domain_menu() {
    if [ -f "$ENV_FILE" ]; then
        source "$ENV_FILE"
        current_domain="${DOMAIN:-未配置}"
    else
        current_domain="未配置"
    fi

    show_msgbox "当前域名" "当前域名：$current_domain"

    if ! show_yesno "配置域名" "是否要配置新域名？"; then
        return
    fi

    while true; do
        NEW_DOMAIN=$(show_inputbox "输入域名" "请输入新域名：" "$current_domain")

        if [ -z "$NEW_DOMAIN" ]; then
            show_msgbox "错误" "域名不能为空"
            continue
        fi

        # 验证域名格式
        if [[ ! "$NEW_DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
            show_msgbox "错误" "域名格式不正确"
            continue
        fi

        break
    done

    # 更新 .env 文件
    if [ -f "$ENV_FILE" ]; then
        sed -i "s/^DOMAIN=.*/DOMAIN=$NEW_DOMAIN/" "$ENV_FILE"
    else
        echo "DOMAIN=$NEW_DOMAIN" > "$ENV_FILE"
    fi

    # 重新配置服务
    show_msgbox "配置中" "正在重新配置服务，请稍候..."

    cd "$SCRIPT_DIR"

    # 重新生成 Authelia 配置
    source "$ENV_FILE"
    sed -i "s|default_redirection_url:.*|default_redirection_url: https://$NEW_DOMAIN|" authelia/configuration.yml
    sed -i "s|domain:.*|domain: $NEW_DOMAIN|" authelia/configuration.yml

    # 重新生成 Nginx 配置
    if [ -f nginx/templates/openclaw.conf.template ]; then
        envsubst '${DOMAIN}' < nginx/templates/openclaw.conf.template > nginx/conf.d/openclaw.conf
    fi

    # 申请 SSL 证书
    if show_yesno "SSL 证书" "是否申请 Let's Encrypt SSL 证书？"; then
        docker run --rm \
            -v "$(pwd)/ssl:/etc/letsencrypt" \
            -v "$(pwd)/certbot-webroot:/var/www/certbot" \
            certbot/certbot certonly \
            --webroot \
            --webroot-path=/var/www/certbot \
            --email "admin@$NEW_DOMAIN" \
            --agree-tos \
            --no-eff-email \
            -d "$NEW_DOMAIN" 2>&1 | tee /tmp/certbot.log

        if [ ${PIPESTATUS[0]} -eq 0 ]; then
            show_msgbox "成功" "SSL 证书申请成功！"
        else
            show_msgbox "失败" "SSL 证书申请失败，请检查日志：/tmp/certbot.log"
        fi
    fi

    # 重启服务
    docker compose restart > /dev/null 2>&1

    show_msgbox "完成" "域名配置完成！\n\n新域名：$NEW_DOMAIN\n访问地址：https://$NEW_DOMAIN"
}

change_password_menu() {
    if [ ! -f "$ENV_FILE" ]; then
        show_msgbox "错误" "环境配置文件不存在"
        return
    fi

    source "$ENV_FILE"

    show_msgbox "修改密码" "当前用户：$ADMIN_USERNAME\n\n即将修改管理员密码"

    while true; do
        NEW_PASSWORD=$(show_passwordbox "新密码" "请输入新密码（至少8位）：")

        if [ -z "$NEW_PASSWORD" ]; then
            show_msgbox "错误" "密码不能为空"
            continue
        fi

        if [ ${#NEW_PASSWORD} -lt 8 ]; then
            show_msgbox "错误" "密码长度至少为8位"
            continue
        fi

        PASSWORD_CONFIRM=$(show_passwordbox "确认密码" "请再次输入新密码：")

        if [ "$NEW_PASSWORD" != "$PASSWORD_CONFIRM" ]; then
            show_msgbox "错误" "两次输入的密码不一致"
            continue
        fi

        break
    done

    # 生成新的密码哈希
    PASSWORD_HASH=$(docker run --rm authelia/authelia:latest \
        authelia crypto hash generate argon2 --password "$NEW_PASSWORD" 2>/dev/null | \
        grep 'Digest:' | awk '{print $2}')

    # 更新 Authelia 用户数据库
    sed -i "s|password:.*|password: \"$PASSWORD_HASH\"|" authelia/users_database.yml

    # 更新 .env 文件
    sed -i "s/^ADMIN_PASSWORD=.*/ADMIN_PASSWORD=$NEW_PASSWORD/" "$ENV_FILE"

    # 重启 Authelia
    docker compose restart authelia > /dev/null 2>&1

    show_msgbox "完成" "密码修改成功！\n\n新密码：$NEW_PASSWORD"
}

view_status_menu() {
    local status_file="/tmp/openclaw_status.txt"

    {
        echo "OpenClaw 服务状态"
        echo "=================="
        echo ""
        docker compose ps
        echo ""
        echo "=================="
        echo "OpenClaw 版本信息"
        echo "=================="
        docker exec openclaw openclaw --version 2>/dev/null || echo "无法获取版本信息"
    } > "$status_file"

    show_textbox "服务状态" "$status_file"
    rm -f "$status_file"
}

view_access_info_menu() {
    if [ ! -f "$ENV_FILE" ]; then
        show_msgbox "错误" "环境配置文件不存在"
        return
    fi

    source "$ENV_FILE"

    local access_url
    if [ -n "$DOMAIN" ]; then
        access_url="https://$DOMAIN"
    else
        local server_ip=$(curl -s ifconfig.me 2>/dev/null || echo "YOUR_SERVER_IP")
        access_url="http://$server_ip"
    fi

    local info="访问信息\n\n"
    info+="访问地址：$access_url\n"
    info+="用户名：$ADMIN_USERNAME\n"
    info+="密码：$ADMIN_PASSWORD\n\n"

    if [ -f "$CREDENTIALS_FILE" ]; then
        info+="凭据文件：$CREDENTIALS_FILE"
    fi

    show_msgbox "访问信息" "$info"
}

update_services_menu() {
    if ! show_yesno "更新确认" "是否要更新 OpenClaw 到最新版本？\n\n此操作将：\n1. 备份当前配置\n2. 拉取最新镜像\n3. 重启服务"; then
        return
    fi

    # 备份
    local backup_dir="backup/backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"
    cp -r openclaw/config "$backup_dir/" 2>/dev/null || true
    cp -r authelia "$backup_dir/" 2>/dev/null || true
    cp "$ENV_FILE" "$backup_dir/" 2>/dev/null || true

    # 更新
    {
        echo "20" ; sleep 1
        docker compose pull > /dev/null 2>&1
        echo "50" ; sleep 1
        docker compose down > /dev/null 2>&1
        echo "70" ; sleep 1
        docker compose up -d > /dev/null 2>&1
        echo "90" ; sleep 1
        docker image prune -f > /dev/null 2>&1
        echo "100" ; sleep 1
    } | whiptail --title "更新进度" --gauge "正在更新服务..." 8 60 0

    # 获取新版本
    local new_version=$(docker exec openclaw openclaw --version 2>/dev/null || echo "未知")

    show_msgbox "更新完成" "服务已更新！\n\n当前版本：$new_version\n\n备份位置：$backup_dir"
}

backup_data_menu() {
    local backup_name=$(show_inputbox "备份名称" "请输入备份名称（留空使用时间戳）：" "")

    if [ -z "$backup_name" ]; then
        backup_name="backup-$(date +%Y%m%d-%H%M%S)"
    fi

    local backup_file="backup/${backup_name}.tar.gz"

    {
        echo "50" ; sleep 1
        tar -czf "$backup_file" openclaw/config openclaw/data authelia .env 2>/dev/null
        echo "100" ; sleep 1
    } | whiptail --title "备份进度" --gauge "正在备份数据..." 8 60 0

    local backup_size=$(du -h "$backup_file" | cut -f1)

    show_msgbox "备份完成" "数据已备份！\n\n备份文件：$backup_file\n文件大小：$backup_size"
}

restore_data_menu() {
    # 列出可用的备份
    local backup_files=($(ls -1 backup/*.tar.gz 2>/dev/null | xargs -n1 basename))

    if [ ${#backup_files[@]} -eq 0 ]; then
        show_msgbox "错误" "没有找到备份文件"
        return
    fi

    # 构建菜单选项
    local menu_options=()
    local index=1
    for file in "${backup_files[@]}"; do
        menu_options+=("$index" "$file")
        ((index++))
    done

    local choice=$(show_menu "选择备份" "请选择要恢复的备份：" "${menu_options[@]}")

    if [ -z "$choice" ]; then
        return
    fi

    local selected_file="${backup_files[$((choice-1))]}"

    if ! show_yesno "确认恢复" "确定要恢复备份吗？\n\n备份文件：$selected_file\n\n警告：当前数据将被覆盖！"; then
        return
    fi

    # 停止服务
    docker compose down > /dev/null 2>&1

    # 恢复备份
    {
        echo "50" ; sleep 1
        tar -xzf "backup/$selected_file" 2>/dev/null
        echo "100" ; sleep 1
    } | whiptail --title "恢复进度" --gauge "正在恢复数据..." 8 60 0

    # 启动服务
    docker compose up -d > /dev/null 2>&1

    show_msgbox "恢复完成" "数据已恢复！\n\n备份文件：$selected_file"
}

view_logs_menu() {
    local service=$(show_menu "选择服务" "请选择要查看日志的服务：" \
        "1" "OpenClaw" \
        "2" "Authelia" \
        "3" "Nginx" \
        "4" "所有服务")

    case $service in
        1) docker compose logs --tail=100 openclaw > /tmp/logs.txt ;;
        2) docker compose logs --tail=100 authelia > /tmp/logs.txt ;;
        3) docker compose logs --tail=100 nginx > /tmp/logs.txt ;;
        4) docker compose logs --tail=100 > /tmp/logs.txt ;;
        *) return ;;
    esac

    show_textbox "服务日志" "/tmp/logs.txt"
    rm -f /tmp/logs.txt
}

# ============================================================================
# 主菜单
# ============================================================================

main_menu() {
    while true; do
        local choice=$(show_menu "OpenClaw 管理菜单" "请选择操作：" \
            "1" "配置域名" \
            "2" "修改管理员密码" \
            "3" "查看服务状态" \
            "4" "查看访问信息" \
            "5" "更新服务" \
            "6" "备份数据" \
            "7" "恢复数据" \
            "8" "查看日志" \
            "0" "退出")

        case $choice in
            1) configure_domain_menu ;;
            2) change_password_menu ;;
            3) view_status_menu ;;
            4) view_access_info_menu ;;
            5) update_services_menu ;;
            6) backup_data_menu ;;
            7) restore_data_menu ;;
            8) view_logs_menu ;;
            0) exit 0 ;;
            *) exit 0 ;;
        esac
    done
}

# ============================================================================
# 主函数
# ============================================================================

main() {
    # 检查 root 权限
    if [ "$EUID" -ne 0 ]; then
        echo "请使用 root 用户运行此脚本"
        exit 1
    fi

    # 检查 whiptail
    check_whiptail

    # 切换到脚本目录
    cd "$SCRIPT_DIR"

    # 显示主菜单
    main_menu
}

# 运行主函数
main "$@"
