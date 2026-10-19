#!/bin/bash
# ============================================================
# MySQL 备份脚本（针对 docker-compose 里的 pb-mysql 容器）
# 功能：mysqldump 全库备份 + 日期命名 + 保留 7 天 + 写日志
# ============================================================

# 出错即退出，避免半截备份还以为成功
set -e

# ---------- 配置区（按你环境填）----------
BACKUP_DIR="/opt/backup"          # 备份存放目录
DB_CONTAINER="pb-mysql"           # compose 起的 mysql 容器名
MYSQL_ROOT_PASSWORD="<mysql_root_password>"   # mysql root 密码（部署时填入强密码）
RETENTION_DAYS=7                  # 保留天数
LOG_FILE="${BACKUP_DIR}/backup.log"

# ---------- 关键坑：cron 环境 PATH 极简 ----------
# cron 跑脚本时 PATH 通常只有 /usr/bin:/bin，可能找不到 docker
# 保险起见显式把常用路径补上（这步就是"mysqldump 要绝对路径"那个坑的通用解法）
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# ---------- 准备目录 ----------
mkdir -p "$BACKUP_DIR"

# ---------- 日期戳：20261010_132900 这种格式 ----------
DATE=$(date +%Y%m%d_%H%M%S)

# ---------- 1) mysqldump 备份 ----------
# 用 docker exec 进容器执行；容器内 mysqldump 用绝对路径 /usr/bin/mysqldump
# --all-databases 把 pb 库和系统库一起备，恢复最省事
echo "[$(date '+%Y-%m-%d %H:%M:%S')] 开始备份..." >> "$LOG_FILE"
if docker exec "$DB_CONTAINER" /usr/bin/mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" --all-databases \
     > "${BACKUP_DIR}/mysql_${DATE}.sql" 2>> "$LOG_FILE"; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 备份成功: mysql_${DATE}.sql" >> "$LOG_FILE"
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 备份失败!" >> "$LOG_FILE"
    exit 1
fi

# ---------- 2) 保留 7 天：删掉修改时间超过 7 天的旧备份 ----------
# -mtime +7 表示"7×24小时之前修改的"
find "$BACKUP_DIR" -name "mysql_*.sql" -mtime +"$RETENTION_DAYS" -delete >> "$LOG_FILE" 2>&1

echo "[$(date '+%Y-%m-%d %H:%M:%S')] 清理完成，仅保留最近 ${RETENTION_DAYS} 天" >> "$LOG_FILE"