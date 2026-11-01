#!/usr/bin/env bash
# 待续IP系统 · 后台一键部署（Linux / macOS）
# 用法： sudo bash deploy.sh [端口]
set -euo pipefail

PORT="${1:-8787}"
APP_DIR="/opt/daixu"
SERVICE="daixu"
PY="$(command -v python3 || true)"

if [ -z "$PY" ]; then
  echo "缺少 python3，先装：apt install -y python3  或  yum install -y python3"
  exit 1
fi

echo "==> Python: $PY"
echo "==> 安装目录: $APP_DIR"

mkdir -p "$APP_DIR"
cp admin_server.py "$APP_DIR/"
[ -f admin_page.html ] && cp admin_page.html "$APP_DIR/"
chmod 755 "$APP_DIR/admin_server.py"

if [ ! -f "$APP_DIR/.secret" ]; then
  head -c 32 /dev/urandom > "$APP_DIR/.secret"
  chmod 600 "$APP_DIR/.secret"
  echo "==> 已生成签名密钥"
fi

# systemd（仅 Linux）
if command -v systemctl >/dev/null 2>&1; then
  cat > /etc/systemd/system/${SERVICE}.service <<EOF
[Unit]
Description=Daixu IP Admin Backend
After=network.target

[Service]
Type=simple
WorkingDirectory=${APP_DIR}
ExecStart=${PY} ${APP_DIR}/admin_server.py --port ${PORT} --user admin --pass admin888
Restart=always
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable ${SERVICE}
  systemctl restart ${SERVICE}
  echo "==> systemd 已启动：systemctl status ${SERVICE}"
else
  echo "==> 非 systemd 环境，手动启动："
  echo "    cd ${APP_DIR} && nohup ${PY} admin_server.py --port ${PORT} > admin.log 2>&1 &"
fi

# 防火墙
if command -v ufw >/dev/null 2>&1; then
  ufw allow ${PORT}/tcp || true
  echo "==> ufw 已放行 ${PORT}/tcp"
elif command -v firewall-cmd >/dev/null 2>&1; then
  firewall-cmd --permanent --add-port=${PORT}/tcp || true
  firewall-cmd --reload || true
  echo "==> firewalld 已放行 ${PORT}/tcp"
fi

sleep 1
IP=$(hostname -I 2>/dev/null | awk '{print $1}')
echo
echo "======================================================"
echo "  部署完成"
echo "  后台地址: http://${IP:-服务器IP}:${PORT}"
echo "  管理员:   admin / admin888   ← 请立刻改掉"
echo "  数据文件: ${APP_DIR}/users.json  ${APP_DIR}/nodes.json"
echo "  改密码:   编辑 /etc/systemd/system/${SERVICE}.service 里的 --pass"
echo "======================================================"
echo
echo "强烈建议下一步配 HTTPS（否则密码明文传输）："
echo "  安装 Caddy 后一行搞定："
echo "    caddy reverse-proxy --from ip.你的域名.com --to 127.0.0.1:${PORT}"
echo "  然后把 App 内置地址改成 https://ip.你的域名.com"
