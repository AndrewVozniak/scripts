#!/usr/bin/env bash
set -euo pipefail

if [ "${EUID}" -ne 0 ]; then
  echo "[ERROR] Run as root: sudo $0"
  exit 1
fi

mkdir -p /etc/nginx/modsec
# directory for ModSecurity configuration

if [ ! -d /opt/coreruleset/.git ]; then
  git clone https://github.com/coreruleset/coreruleset /opt/coreruleset
fi
# download OWASP Core Rule Set

if [ -f /opt/coreruleset/crs-setup.conf.example ] && [ ! -f /opt/coreruleset/crs-setup.conf ]; then
  cp /opt/coreruleset/crs-setup.conf.example /opt/coreruleset/crs-setup.conf
fi
# activate CRS setup config

if [ -f /opt/coreruleset/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf.example ] && [ ! -f /opt/coreruleset/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf ]; then
  cp /opt/coreruleset/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf.example \
    /opt/coreruleset/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf
fi
# create exclusions file for future false-positive tuning

cp /usr/local/src/ModSecurity/unicode.mapping /etc/nginx/modsec/unicode.mapping
cp /usr/local/src/ModSecurity/modsecurity.conf-recommended /etc/nginx/modsec/modsecurity.conf
# copy base ModSecurity configuration

cat > /etc/nginx/modsec/main.conf <<'EOF'
Include /etc/nginx/modsec/modsecurity.conf
Include /opt/coreruleset/crs-setup.conf
Include /opt/coreruleset/rules/*.conf
EOF
# main file referenced by nginx: modsecurity_rules_file /etc/nginx/modsec/main.conf;

echo "[SUCCESS] OWASP CRS installed."
echo "[INFO] Edit /etc/nginx/modsec/modsecurity.conf and set: SecRuleEngine On"
echo "[INFO] Then add inside nginx http{} or server{}:"
echo "       modsecurity on;"
echo "       modsecurity_rules_file /etc/nginx/modsec/main.conf;"
