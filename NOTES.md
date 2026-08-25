# Notes / cheat sheet

Compact reference for the Web Security & Honeypot labs.

## NGINX

Main config:

```text
/etc/nginx/nginx.conf
```

Additional vhosts/configs:

```text
/etc/nginx/conf.d/
```

Useful commands:

```bash
nginx -t
nginx -T
systemctl reload nginx
systemctl restart nginx
```

Basic vhost:

```nginx
server {
    listen 80;
    server_name resit1.websecurity;
    root /usr/share/nginx/resit1;
    index index.php index.html;

    location / {
        try_files $uri $uri/ =404;
    }

    location ~ \.php$ {
        fastcgi_pass unix:/run/php/php8.4-fpm.sock;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }
}
```

Catch-all:

```nginx
server {
    listen 80 default_server;
    server_name _;
    return 444;
}
```

HTTP methods:

```nginx
location / {
    limit_except GET HEAD {
        deny all;
    }
    try_files $uri $uri/ =404;
}
```

Rate limit:

```nginx
# http{}
limit_req_zone $binary_remote_addr zone=resit:10m rate=5r/s;

# server/location
limit_req zone=resit;
limit_req_status 429;
```

Hide version:

```nginx
server_tokens off;
```

## TLS / HTTP2 / HTTP3

Self-signed certificate:

```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/resit.key \
  -out /etc/ssl/certs/resit.crt
```

HTTPS:

```nginx
listen 443 ssl;
ssl_certificate /etc/ssl/certs/resit.crt;
ssl_certificate_key /etc/ssl/private/resit.key;
http2 on;
```

HTTP redirect:

```nginx
return 301 https://$host$request_uri;
```

TLS sessions:

```nginx
ssl_session_cache shared:SSL:10m;
ssl_session_timeout 10m;
ssl_session_tickets on;
ssl_session_ticket_key /etc/nginx/ssl/session_ticket_keys.key;
```

Generate ticket key:

```bash
openssl rand 80 > /etc/nginx/ssl/session_ticket_keys.key
```

HTTP/3:

```nginx
listen 443 quic reuseport;
listen 443 ssl;
http3 on;
http2 on;
```

Status endpoint:

```nginx
location /nginx_status {
    stub_status on;
    allow 127.0.0.1;
    deny all;
}
```

Reverse proxy / upstream:

```nginx
upstream backend {
    server 127.0.0.1:8443 max_conns=1;
    server 127.0.0.1:9443;
}

location / {
    proxy_pass http://backend;
}
```

Remember: frontend protocol and backend protocol are independent. `proxy_pass http://...` requires an HTTP backend; `proxy_pass https://...` requires a TLS-enabled backend.

## MySQL / PHP security

Hardening in MySQL server config:

```text
local_infile = 0
skip-name-resolve = 1
```

Apply server config changes with:

```bash
systemctl restart mysql
```

Useful SQL:

```sql
CREATE DATABASE resit3;
CREATE USER 'resit3user'@'%' IDENTIFIED BY 'password';
GRANT SELECT, INSERT, UPDATE, DELETE ON resit3.* TO 'resit3user'@'%';
SHOW GRANTS FOR 'resit3user'@'%';
SELECT User, Host FROM mysql.user;
SHOW DATABASES;
SHOW TABLES;
DESCRIBE users;
DROP USER 'resit3user'@'%';
```

PDO chain:

```text
new PDO() -> prepare() -> execute() -> fetch()
```

Example:

```php
$stmt = $pdo->prepare("SELECT id, username, email FROM users WHERE id = ?");
$stmt->execute([$id]);
$user = $stmt->fetch(PDO::FETCH_ASSOC);
```

XSS output encoding:

```php
htmlspecialchars($value, ENT_QUOTES, 'UTF-8');
```

## Security headers / caching

Modern NGINX can merge inherited headers:

```nginx
add_header_inherit merge;
```

Common headers:

```nginx
add_header X-Content-Type-Options nosniff always;
add_header X-Frame-Options DENY always;
add_header Content-Security-Policy "default-src 'self';" always;
add_header Strict-Transport-Security "max-age=63072000; includeSubDomains" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header Permissions-Policy "geolocation=(), camera=(), microphone=()" always;
```

Static caching:

```nginx
location /static/ {
    etag on;
    expires 1y;
    add_header Cache-Control "public, immutable";
}
```

Dynamic:

```nginx
add_header Cache-Control "no-cache";
```

Sensitive page:

```nginx
location = /private.php {
    add_header Cache-Control "no-store";
    # PHP-FPM directives here
}
```

`location =` is an exact match and prevents the generic `location ~ \.php$` regex from taking the request.

## Filebeat / Elastic / Kibana

Architecture:

```text
NGINX -> Filebeat -> Elasticsearch :9200 -> Kibana :5601
```

Filebeat config:

```text
/etc/filebeat/filebeat.yml
```

Modules:

```text
/etc/filebeat/modules.d/
/etc/filebeat/modules.d/nginx.yml
```

Commands:

```bash
filebeat modules enable nginx
filebeat modules list
filebeat test config
filebeat test output
systemctl enable --now filebeat
journalctl -u filebeat -n 100 --no-pager
```

Elasticsearch CA fingerprint:

```bash
openssl x509 -fingerprint -sha256 -in /etc/elasticsearch/certs/http_ca.crt
```

Example output config:

```yaml
output.elasticsearch:
  hosts: ["https://192.168.176.175:9200"]
  username: "elastic"
  password: "PASSWORD"
  ssl:
    enabled: true
    ca_trusted_fingerprint: "SHA256_WITHOUT_COLONS"
```

Default Filebeat 9.3.0 data stream is typically:

```text
filebeat-9.3.0
```

Backing index example:

```text
.ds-filebeat-9.3.0-YYYY.MM.DD-000001
```

Kibana Data View:

```text
filebeat-*
```

Useful fields:

```text
@timestamp
host.name
host.hostname
agent.id
event.dataset
http.response.status_code
source.ip
url.original
```

## ModSecurity + OWASP CRS

ModSecurity = WAF engine.

OWASP CRS = detection rules used by ModSecurity.

Main files:

```text
/usr/lib/nginx/modules/ngx_http_modsecurity_module.so
/etc/nginx/modsec/modsecurity.conf
/etc/nginx/modsec/main.conf
/opt/coreruleset/
```

Load dynamic module near the top of `nginx.conf`:

```nginx
load_module /usr/lib/nginx/modules/ngx_http_modsecurity_module.so;
```

Enable WAF:

```nginx
modsecurity on;
modsecurity_rules_file /etc/nginx/modsec/main.conf;
```

Main rules file:

```text
Include /etc/nginx/modsec/modsecurity.conf
Include /opt/coreruleset/crs-setup.conf
Include /opt/coreruleset/rules/*.conf
```

Blocking mode:

```text
SecRuleEngine On
```

`DetectionOnly` logs/detects but does not enforce blocking.

CRS uses rule matches and an anomaly score. Once the inbound anomaly score reaches the blocking threshold, ModSecurity can return `403`.

Test SQLi/XSS:

```bash
curl -i 'http://resit1.websecurity/?id=1%20OR%201=1'
curl -i 'http://resit1.websecurity/?x=%3Cscript%3Ealert(1)%3C%2Fscript%3E'
```

Audit directives:

```text
SecAuditEngine RelevantOnly
SecAuditLogFormat JSON
SecAuditLogType Serial
SecAuditLog /var/log/modsec_audit.json
```

Check for duplicate/conflicting audit directives:

```bash
grep -nE 'SecAudit(Log|Engine|LogFormat)' /etc/nginx/modsec/modsecurity.conf
```

Custom Filebeat JSON input:

```yaml
filebeat.inputs:
  - type: filestream
    id: modsecurity-json
    enabled: true
    paths:
      - /var/log/modsec_audit.json
    parsers:
      - ndjson:
          target: ""
          add_error_key: true
    fields:
      log_type: modsecurity
    fields_under_root: true
```

Kibana filter:

```text
log_type: "modsecurity"
```

Useful dashboard ideas:

```text
Blocked attacks total
Attacks over time
Attacks by type
Top attacking IPs
Top triggered rule IDs
Anomaly score
```

Prefer one JSON audit transaction per Elasticsearch document. Native serial audit logs sent line-by-line inflate counts and make "number of attacks" misleading.

## Fast verification

```bash
nginx -t
filebeat test config
filebeat test output
systemctl status nginx --no-pager
systemctl status php8.4-fpm --no-pager
systemctl status filebeat --no-pager
```
