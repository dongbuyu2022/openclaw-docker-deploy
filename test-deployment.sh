#!/bin/bash

# ============================================================================
# OpenClaw 部署脚本测试版本
# 只执行检查，不真正部署，最后自动清理
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="$SCRIPT_DIR/test-deployment"
LOG_FILE="$SCRIPT_DIR/test-deployment.log"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[TEST]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1" | tee -a "$LOG_FILE"
}

# 初始化日志
echo "OpenClaw 部署测试 - $(date)" > "$LOG_FILE"
echo "========================================" >> "$LOG_FILE"

log "开始部署测试..."

# ============================================================================
# 1. 系统检查
# ============================================================================

log "1. 检查系统信息..."

if [ ! -f /etc/os-release ]; then
    log_error "无法读取系统信息"
    exit 1
fi

. /etc/os-release
log_success "操作系统：$PRETTY_NAME"
log_success "内核版本：$(uname -r)"

if [ "$ID" != "ubuntu" ]; then
    log_warning "当前系统不是 Ubuntu：$ID"
else
    log_success "系统类型：Ubuntu"
fi

# ============================================================================
# 2. 权限检查
# ============================================================================

log "2. 检查权限..."

if [ "$EUID" -ne 0 ]; then
    log_error "需要 root 权限"
    exit 1
else
    log_success "权限检查通过：root"
fi

# ============================================================================
# 3. 系统资源检查
# ============================================================================

log "3. 检查系统资源..."

CPU_CORES=$(nproc)
TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
TOTAL_DISK=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')

log_success "CPU 核心：$CPU_CORES"
log_success "内存大小：${TOTAL_MEM}MB"
log_success "磁盘空间：${TOTAL_DISK}GB"

if [ "$TOTAL_MEM" -lt 2000 ]; then
    log_warning "内存不足 2GB，可能影响性能"
fi

if [ "$TOTAL_DISK" -lt 10 ]; then
    log_warning "磁盘空间不足 10GB"
fi

# ============================================================================
# 4. 依赖检查
# ============================================================================

log "4. 检查系统依赖..."

REQUIRED_PACKAGES=(curl wget git openssl ca-certificates gnupg lsb-release)
MISSING_PACKAGES=()

for package in "${REQUIRED_PACKAGES[@]}"; do
    if dpkg -l | grep -q "^ii  $package"; then
        log_success "$package: 已安装"
    else
        log_warning "$package: 未安装"
        MISSING_PACKAGES+=("$package")
    fi
done

if [ ${#MISSING_PACKAGES[@]} -gt 0 ]; then
    log_warning "缺少 ${#MISSING_PACKAGES[@]} 个依赖包"
else
    log_success "所有依赖已安装"
fi

# ============================================================================
# 5. Docker 检查
# ============================================================================

log "5. 检查 Docker..."

if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version | awk '{print $3}' | sed 's/,//')
    log_success "Docker 已安装：$DOCKER_VERSION"

    if systemctl is-active --quiet docker; then
        log_success "Docker 服务：运行中"
    else
        log_warning "Docker 服务：未运行"
    fi
else
    log_warning "Docker 未安装"
fi

if docker compose version &> /dev/null; then
    COMPOSE_VERSION=$(docker compose version --short)
    log_success "Docker Compose：$COMPOSE_VERSION"
else
    log_warning "Docker Compose 未安装"
fi

# ============================================================================
# 6. 端口检查
# ============================================================================

log "6. 检查端口占用..."

REQUIRED_PORTS=(80 443)

for port in "${REQUIRED_PORTS[@]}"; do
    if netstat -tuln 2>/dev/null | grep -q ":$port " || ss -tuln 2>/dev/null | grep -q ":$port "; then
        PROCESS=$(netstat -tulnp 2>/dev/null | grep ":$port " | awk '{print $7}' | head -1)
        log_warning "端口 $port 已被占用：$PROCESS"
    else
        log_success "端口 $port：可用"
    fi
done

# ============================================================================
# 7. 防火墙检查
# ============================================================================

log "7. 检查防火墙..."

FIREWALL_DETECTED=false

if command -v ufw &> /dev/null; then
    if ufw status | grep -q "Status: active"; then
        log_success "UFW 防火墙：活动"
        FIREWALL_DETECTED=true

        # 检查端口规则
        if ufw status | grep -q "80/tcp"; then
            log_success "UFW 规则：80 端口已开放"
        else
            log_warning "UFW 规则：80 端口未开放"
        fi

        if ufw status | grep -q "443/tcp"; then
            log_success "UFW 规则：443 端口已开放"
        else
            log_warning "UFW 规则：443 端口未开放"
        fi
    else
        log_success "UFW 防火墙：未激活"
    fi
fi

if command -v firewall-cmd &> /dev/null; then
    if systemctl is-active --quiet firewalld; then
        log_success "firewalld：活动"
        FIREWALL_DETECTED=true
    fi
fi

if ! $FIREWALL_DETECTED; then
    log_success "未检测到活动的防火墙"
fi

# ============================================================================
# 8. 网络检查
# ============================================================================

log "8. 检查网络连接..."

if ping -c 1 8.8.8.8 &> /dev/null; then
    log_success "网络连接：正常"
else
    log_warning "网络连接：可能存在问题"
fi

if curl -s --connect-timeout 5 https://www.google.com > /dev/null; then
    log_success "HTTPS 连接：正常"
else
    log_warning "HTTPS 连接：可能存在问题"
fi

# ============================================================================
# 9. Docker Hub 连接测试
# ============================================================================

log "9. 测试 Docker Hub 连接..."

if docker pull hello-world:latest &> /dev/null; then
    log_success "Docker Hub 连接：正常"
    docker rmi hello-world:latest &> /dev/null
else
    log_warning "Docker Hub 连接：失败"
fi

# ============================================================================
# 10. 测试目录创建
# ============================================================================

log "10. 测试目录创建..."

mkdir -p "$TEST_DIR"/{openclaw,authelia,nginx,ssl,backup}

if [ -d "$TEST_DIR" ]; then
    log_success "测试目录创建：成功"
    log_success "测试目录位置：$TEST_DIR"
else
    log_error "测试目录创建：失败"
fi

# ============================================================================
# 11. 测试文件写入
# ============================================================================

log "11. 测试文件写入..."

TEST_FILE="$TEST_DIR/test.txt"
echo "OpenClaw Test" > "$TEST_FILE"

if [ -f "$TEST_FILE" ]; then
    log_success "文件写入：成功"
else
    log_error "文件写入：失败"
fi

# ============================================================================
# 12. 测试密钥生成
# ============================================================================

log "12. 测试密钥生成..."

TEST_KEY="$TEST_DIR/test_key"
openssl rand -base64 64 > "$TEST_KEY" 2>/dev/null

if [ -f "$TEST_KEY" ] && [ -s "$TEST_KEY" ]; then
    log_success "密钥生成：成功"
else
    log_error "密钥生成：失败"
fi

# ============================================================================
# 13. 测试 Docker Compose 配置
# ============================================================================

log "13. 测试 Docker Compose 配置..."

if [ -f "$SCRIPT_DIR/docker-compose.yml" ]; then
    if docker compose -f "$SCRIPT_DIR/docker-compose.yml" config &> /dev/null; then
        log_success "Docker Compose 配置：有效"
    else
        log_warning "Docker Compose 配置：可能存在问题"
    fi
else
    log_warning "Docker Compose 配置文件不存在"
fi

# ============================================================================
# 14. 检查现有的 OpenClaw 安装
# ============================================================================

log "14. 检查现有安装..."

if [ -d "/opt/openclaw" ]; then
    log_warning "检测到现有的 OpenClaw 安装：/opt/openclaw"
fi

if docker ps -a | grep -q "openclaw"; then
    log_warning "检测到现有的 OpenClaw 容器"
fi

if docker ps -a | grep -q "authelia"; then
    log_warning "检测到现有的 Authelia 容器"
fi

# ============================================================================
# 测试总结
# ============================================================================

echo ""
echo "========================================" | tee -a "$LOG_FILE"
echo "测试完成！" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# 统计结果
SUCCESS_COUNT=$(grep -c "\[✓\]" "$LOG_FILE" || echo "0")
WARNING_COUNT=$(grep -c "\[!\]" "$LOG_FILE" || echo "0")
ERROR_COUNT=$(grep -c "\[✗\]" "$LOG_FILE" || echo "0")

echo "测试结果统计：" | tee -a "$LOG_FILE"
echo "  成功：$SUCCESS_COUNT" | tee -a "$LOG_FILE"
echo "  警告：$WARNING_COUNT" | tee -a "$LOG_FILE"
echo "  错误：$ERROR_COUNT" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

if [ "$ERROR_COUNT" -gt 0 ]; then
    log_error "发现 $ERROR_COUNT 个错误，建议修复后再部署"
elif [ "$WARNING_COUNT" -gt 0 ]; then
    log_warning "发现 $WARNING_COUNT 个警告，建议检查后再部署"
else
    log_success "所有检查通过，可以开始部署！"
fi

echo "" | tee -a "$LOG_FILE"
echo "详细日志：$LOG_FILE" | tee -a "$LOG_FILE"

# ============================================================================
# 清理测试文件
# ============================================================================

log "清理测试文件..."

if [ -d "$TEST_DIR" ]; then
    rm -rf "$TEST_DIR"
    log_success "测试目录已清理"
fi

log "测试完成！"
