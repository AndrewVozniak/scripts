#!/usr/bin/env bash
set -euo pipefail

if [ "${EUID}" -ne 0 ]; then
  echo "[ERROR] Run as root: sudo $0"
  exit 1
fi

if ! command -v nginx >/dev/null 2>&1; then
  echo "[ERROR] nginx is not installed"
  exit 1
fi

NGINX_VERSION="$(nginx -v 2>&1 | sed -n 's#nginx version: nginx/##p')"
SRC="/usr/local/src"
MODSEC_DIR="${SRC}/ModSecurity"
CONNECTOR_DIR="${SRC}/ModSecurity-nginx"
NGINX_SRC="${SRC}/nginx-${NGINX_VERSION}"
NGINX_TGZ="${SRC}/nginx-${NGINX_VERSION}.tar.gz"
MODULE_DIR="/usr/lib/nginx/modules"
MODULE_PATH="${MODULE_DIR}/ngx_http_modsecurity_module.so"

echo "[INFO] NGINX version: ${NGINX_VERSION}"

apt-get update
apt-get install -y git g++ autoconf automake build-essential \
  libcurl4-openssl-dev liblmdb-dev libpcre2-dev libtool \
  libxml2-dev libyajl-dev pkgconf zlib1g-dev wget ca-certificates libssl-dev

mkdir -p "${SRC}"

if [ ! -d "${MODSEC_DIR}/.git" ]; then
  git clone --depth 1 --recursive https://github.com/owasp-modsecurity/ModSecurity.git "${MODSEC_DIR}"
fi

cd "${MODSEC_DIR}"
git submodule update --init --recursive
./build.sh
./configure
make -j"$(nproc)"
make install
ldconfig

if [ ! -d "${CONNECTOR_DIR}/.git" ]; then
  git clone --depth 1 https://github.com/owasp-modsecurity/ModSecurity-nginx.git "${CONNECTOR_DIR}"
fi

cd "${SRC}"
if [ ! -f "${NGINX_TGZ}" ]; then
  wget "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" -O "${NGINX_TGZ}"
fi
if [ ! -d "${NGINX_SRC}" ]; then
  tar xzf "${NGINX_TGZ}"
fi

CONFIGURE_ARGS="$(nginx -V 2>&1 | sed -n 's/^configure arguments: //p')"
if [ -z "${CONFIGURE_ARGS}" ]; then
  echo "[ERROR] Could not extract configure args from nginx -V"
  exit 1
fi

cd "${NGINX_SRC}"
eval ./configure ${CONFIGURE_ARGS} --with-compat --add-dynamic-module="${CONNECTOR_DIR}"
make modules

mkdir -p "${MODULE_DIR}"
cp -f objs/ngx_http_modsecurity_module.so "${MODULE_PATH}"

NGINX_CONF="/etc/nginx/nginx.conf"
LOAD_LINE="load_module ${MODULE_PATH};"
if ! grep -Fqx "${LOAD_LINE}" "${NGINX_CONF}"; then
  cp -a "${NGINX_CONF}" "${NGINX_CONF}.bak-modsecurity-$(date +%Y%m%d-%H%M%S)"
  tmp="$(mktemp)"
  { echo "${LOAD_LINE}"; cat "${NGINX_CONF}"; } > "${tmp}"
  cat "${tmp}" > "${NGINX_CONF}"
  rm -f "${tmp}"
fi

nginx -t

echo
echo "[SUCCESS] ModSecurity module installed:"
echo "  ${MODULE_PATH}"
echo "[INFO] Next: configure ModSecurity + OWASP CRS"
