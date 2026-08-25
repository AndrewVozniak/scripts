#!/bin/bash
set -e

# Скрипт должен выполняться от root
if [ "$EUID" -ne 0 ]; then
    echo "Run as root: sudo ./install-nginx.sh"
    exit 1
fi

# Обновляем список пакетов
apt update

# Ставим зависимости для nginx.org repository и PHP
apt install -y \
    curl \
    gnupg2 \
    ca-certificates \
    lsb-release \
    debian-archive-keyring

# Создаём GPG home, чтобы на свежей minimal Debian не получить ошибку от gpg
mkdir -p /root/.gnupg
chmod 700 /root/.gnupg

# Скачиваем официальный signing key NGINX
curl -fsSL https://nginx.org/keys/nginx_signing.key \
    | gpg --dearmor -o /usr/share/keyrings/nginx-archive-keyring.gpg

# Показываем fingerprint ключа для проверки
echo "=== NGINX signing key ==="
gpg --dry-run --quiet --no-keyring \
    --import --import-options import-show \
    /usr/share/keyrings/nginx-archive-keyring.gpg

# Добавляем официальный nginx.org repository для текущего Debian release
echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] https://nginx.org/packages/debian $(lsb_release -cs) nginx" \
    > /etc/apt/sources.list.d/nginx.list

# Даём nginx.org приоритет 900 над другими repositories
cat > /etc/apt/preferences.d/99nginx <<'EOF'
Package: *
Pin: origin nginx.org
Pin-Priority: 900
EOF

# Обновляем APT уже с новым repository
apt update

# Показываем откуда будет установлен NGINX
echo "=== NGINX APT policy ==="
apt policy nginx

# Устанавливаем NGINX и PHP 8.4/FPM
apt install -y \
    nginx \
    php8.4 \
    php8.4-fpm

# Даём nginx доступ к ресурсам группы www-data, как требовалось в lab
usermod -aG www-data nginx

# Запускаем сервисы сейчас и при следующих загрузках
systemctl enable --now nginx
systemctl enable --now php8.4-fpm

# Финальная проверка
echo "=== Versions ==="
nginx -v
php -v

echo "=== Services ==="
systemctl is-active nginx
systemctl is-active php8.4-fpm

echo "=== NGINX config ==="
nginx -t

echo "NGINX + PHP-FPM installation complete."
