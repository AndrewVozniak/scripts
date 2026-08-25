#!/bin/bash
set -e

DOMAIN="${1:-resit2.websecurity}"                           # hostname для сертификата
CERT="/etc/ssl/certs/${DOMAIN}.crt"                         # куда сохранить public certificate
KEY="/etc/ssl/private/${DOMAIN}.key"                        # куда сохранить private key

mkdir -p /etc/nginx/ssl                                    # директория для TLS session keys

openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout "$KEY" \
  -out "$CERT" \
  -subj "/CN=$DOMAIN" \
  -addext "subjectAltName=DNS:$DOMAIN"
# создаёт self-signed RSA certificate + private key на 365 дней

openssl rand 80 > /etc/nginx/ssl/session_ticket_keys.key
# генерирует случайный key material для TLS session tickets

chmod 600 "$KEY" /etc/nginx/ssl/session_ticket_keys.key
# private keys читаются только root

cat > /etc/nginx/conf.d/10-tls-session.conf <<'EOF'
ssl_session_cache shared:SSL:10m;                           # shared cache TLS sessions
ssl_session_timeout 10m;                                    # session можно reuse 10 минут
ssl_session_tickets on;                                     # включаем TLS session tickets
ssl_session_ticket_key /etc/nginx/ssl/session_ticket_keys.key; # ключ session tickets
EOF
# conf.d подключается внутри http {}, поэтому эти глобальные TLS-настройки валидны здесь

echo
echo "Certificate: $CERT"
echo "Private key: $KEY"
echo "Session ticket key: /etc/nginx/ssl/session_ticket_keys.key"

nginx -t
# проверяем, что созданный snippet не сломал NGINX
