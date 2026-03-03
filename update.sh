#!/bin/bash
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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
if [ "$EUID" -ne 0 ]; then
    log_error "请使用 root 用户运行此脚本"
    exit 1
fi

echo ""
echo "========================================="
echo "  OpenClaw 更新脚本"
echo "========================================="
echo ""

# 备份当前配置
log_info "备份当前配置..."
BACKUP_DIR="backup/backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

cp -r openclaw/config "$BACKUP_DIR/" 2>/dev/null || true
cp -r authelia "$BACKUP_DIR/" 2>/dev/null || true
cp .env "$BACKUP_DIR/" 2>/dev/null || true

log_success "配置已备份到 $BACKUP_DIR"

# 拉取最新镜像
log_info "拉取最新镜像..."
docker compose pull

# 停止服务
log_info "停止服务..."
docker compose down

# 启动服务
log_info "启动服务..."
docker compose up -d

# 等待服务就绪
log_info "等待服务就绪..."
sleep 10

# 检查服务状态
log_info "检查服务状态..."
docker compose ps

# 清理旧镜像
log_info "清理旧镜像..."
docker image prune -f

log_success "更新完成！"

# 显示版本信息
echo ""
echo "当前版本："
docker exec openclaw openclaw --version

echo ""
echo "========================================="
echo "  更新完成"
echo "========================================="
echo ""
echo "查看日志：docker compose logs -f openclaw"
echo ""
