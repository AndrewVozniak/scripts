#!/usr/bin/env bash
set -euo pipefail

if [ "${EUID}" -ne 0 ]; then
  echo "Run as root: sudo $0 [admin-ip-or-range]"
  exit 1
fi

ADMIN_RANGE="${1:-127.0.0.1/8}"

apt update
apt install -y fail2ban iptables

cp -n /etc/fail2ban/jail.conf /etc/fail2ban/jail.local || true

cat > /etc/fail2ban/filter.d/nginx-401-custom.conf <<'EOF'
[Definition]
failregex = ^<HOST>.*"(POST).*" (401) .*
ignoreregex =
EOF

cat >> /etc/fail2ban/jail.local <<EOF

# --- Web Security Lab 7 custom settings ---
[DEFAULT]
ignoreip = 127.0.0.1/8 ::1 ${ADMIN_RANGE}
bantime = 5m
findtime = 600
maxretry = 5
backend = auto

[nginx-401-custom]
enabled = true
filter = nginx-401-custom
port = http,https
logpath = /var/log/nginx/access.log
findtime = 60
bantime = 60
maxretry = 10
action = iptables-multiport[name=nginx_401, port="http,https"]
EOF

systemctl enable --now fail2ban
systemctl restart fail2ban

echo
fail2ban-client status || true
echo
echo "Check the custom jail with:"
echo "  fail2ban-client status nginx-401-custom"
echo "  fail2ban-client get nginx-401-custom banned"
echo
echo "Regex test example:"
echo "  fail2ban-regex /var/log/nginx/access.log /etc/fail2ban/filter.d/nginx-401-custom.conf"
