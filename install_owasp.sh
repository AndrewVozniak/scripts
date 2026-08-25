mkdir -p /etc/nginx/modsec
# директория конфигов ModSecurity

git clone https://github.com/coreruleset/coreruleset /opt/coreruleset
# скачиваем OWASP Core Rule Set

mv /opt/coreruleset/crs-setup.conf.example /opt/coreruleset/crs-setup.conf
# активируем основной CRS config

mv /opt/coreruleset/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf.example \
/opt/coreruleset/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf
# создаём файл для будущих исключений/false positives

cp /usr/local/src/ModSecurity/unicode.mapping /etc/nginx/modsec/
# unicode normalization mapping

cp /usr/local/src/ModSecurity/modsecurity.conf-recommended /etc/nginx/modsec/modsecurity.conf
# основной ModSecurity config
