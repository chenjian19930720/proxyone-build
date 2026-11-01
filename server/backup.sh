#!/usr/bin/env bash
# 备份线路和用户数据（建议加到 crontab 每天跑）
# crontab: 0 4 * * * bash /opt/daixu/backup.sh >> /opt/daixu/backup.log 2>&1
set -euo pipefail

DIR="/opt/daixu"
DEST="/opt/daixu/backups"
KEEP=30

mkdir -p "$DEST"
STAMP=$(date +%Y%m%d-%H%M%S)
FILE="$DEST/daixu-$STAMP.tar.gz"

tar czf "$FILE" -C "$DIR" users.json nodes.json .secret 2>/dev/null || true
ls -1t "$DEST"/daixu-*.tar.gz 2>/dev/null | tail -n +$((KEEP + 1)) | xargs -r rm -f

echo "[$(date '+%F %T')] backed up -> $FILE"
