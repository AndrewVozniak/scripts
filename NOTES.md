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

Example output config (credentials + TLS are configured here):

```yaml
output.elasticsearch:
  hosts: ["https://192.168.176.175:9200"]
  username: "elastic"
  password: "PASSWORD"
  ssl:
    enabled: true
    ca_trusted_fingerprint: "SHA256_WITHOUT_COLONS"
```

### Default data stream vs separate application index

With the normal Filebeat 9.3.0 setup, events typically go to the Filebeat data stream:

```text
filebeat-9.3.0                 <- data stream
.ds-filebeat-9.3.0-YYYY.MM.DD-000001 <- backing index
```

Multiple Filebeat clients can send events to the same data stream. Their events can still be distinguished with fields such as `host.name`, `agent.id`, etc.

If a second application/project must NOT be mixed with the old Filebeat data, the simplest lab/exam solution is a separate custom index. Configure it in `/etc/filebeat/filebeat.yml`:

```yaml
setup.ilm.enabled: false
setup.template.name: "app2-filebeat"
setup.template.pattern: "app2-filebeat-*"

output.elasticsearch:
  hosts: ["https://192.168.176.175:9200"]
  username: "elastic"
  password: "PASSWORD"
  index: "app2-filebeat-%{[agent.version]}"
  ssl:
    enabled: true
    ca_trusted_fingerprint: "SHA256_WITHOUT_COLONS"
```

This produces a separate custom index such as:

```text
app2-filebeat-9.3.0
```

Important: setting `output.elasticsearch.index` does NOT automatically create a new data stream with that name. It is custom index naming. The goal here is simply to keep another application's logs separate from the existing Filebeat data.

Create a separate Kibana Data View for it:

```text
app2-filebeat-*
```

If two different applications are collected by the SAME Filebeat instance, tag the inputs and route them conditionally with `output.elasticsearch.indices`.

### Filebeat input example

```yaml
filebeat.inputs:
  - type: filestream
    id: my-application
    enabled: true
    paths:
      - /var/log/myapp/*.log
    fields:
      app: myapp
    fields_under_root: true
```

For a JSON/NDJSON log such as ModSecurity audit JSON:

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

After changing Filebeat configuration:

```bash
filebeat test config
filebeat test output
systemctl restart filebeat
```

## ModSecurity + OWASP CRS

ModSecurity = WAF engine. OWASP CRS = detection rules used by ModSecurity.

Main files:

```text
/usr/lib/nginx/modules/ngx_http_modsecurity_module.so
/etc/nginx/modsec/modsecurity.conf
/etc/nginx/modsec/main.conf
/opt/coreruleset/
```

Load module:

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

Test:

```bash
curl -i 'http://resit1.websecurity/?id=1%20OR%201=1'
curl -i 'http://resit1.websecurity/?x=%3Cscript%3Ealert(1)%3C%2Fscript%3E'
```

Audit JSON:

```text
SecAuditEngine RelevantOnly
SecAuditLogFormat JSON
SecAuditLogType Serial
SecAuditLog /var/log/modsec_audit.json
```

Check duplicates:

```bash
grep -nE 'SecAudit(Log|Engine|LogFormat)' /etc/nginx/modsec/modsecurity.conf
```

## Lab 4 — DECEIVE SSH honeypot + Ollama

Lab 4 builds an AI-generated SSH honeypot. DECEIVE simulates a Linux host over SSH, sends attacker commands to an LLM, returns realistic fake output, and stores structured JSON-line logs. At session end it can summarize attacker behavior and classify a session as BENIGN, SUSPICIOUS, or MALICIOUS. fileciteturn40file0

Architecture:

```text
attacker SSH client
        |
        v
DECEIVE SSH server :8022
        |
        v
Ollama API :11434
        |
        v
llama3

DECEIVE -> SSH/ssh_log.log (JSON lines)
```

Lab VM recommendation:

```text
Debian 13
50 GB disk
16 GB RAM
8 CPUs
```

Docker/Ollama core commands:

```bash
docker run -d -v ollama:/root/.ollama -p 11434:11434 --name ollama ollama/ollama
docker exec -it ollama ollama run llama3
```

Test Ollama API:

```bash
curl http://localhost:11434/api/generate -d '{
  "model": "llama3",
  "prompt": "Who is the best superhero??"
}'
```

DECEIVE setup:

```bash
git clone https://github.com/splunk/DECEIVE
cd DECEIVE
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
ssh-keygen -t rsa -b 4096 -f SSH/ssh_host_key
cp SSH/config.ini.TEMPLATE SSH/config.ini
```

Important config:

```text
DECEIVE/SSH/config.ini
DECEIVE/SSH/prompt.txt
DECEIVE/SSH/ssh_log.log
```

Ollama section in `SSH/config.ini`:

```ini
llm_provider = ollama
model_name = llama3
base_url = http://localhost:11434
```

`SSH/prompt.txt` defines what the fake system pretends to be, e.g. a game developer workstation. Better prompt = more realistic honeypot. fileciteturn40file0

Run:

```bash
cd DECEIVE/SSH
source ../.venv/bin/activate
python3 ./ssh_server.py
```

Test:

```bash
ssh guest@localhost -p 8022
```

Logs are JSON Lines: each line is one complete JSON document. Useful fields include source/destination IP/port, message, username, password, task/session name, and base64-encoded `details`. fileciteturn40file0

Helper script in this repo:

```text
install_deceive_lab4.sh
```

It installs Docker/Ollama, clones DECEIVE, creates the Python venv, installs requirements, generates the SSH host key and copies the config template. `config.ini` and `prompt.txt` still need manual editing.

## Lab 7 — OAuth, Fail2Ban, JWT, CORS

Lab 7 consists of four separate mechanisms: OAuth for delegated authentication/authorization, Fail2Ban for automatic IP banning, JWT for signed bearer tokens, and CORS for browser cross-origin policy. fileciteturn40file1

### OAuth / Google Identity Services

OAuth separates the user's credentials from the third-party application: the client gets an access/token credential from an authorization server instead of receiving the user's password. fileciteturn40file1

Lab flow:

```text
Browser -> Google authorization/identity service
        -> Google returns credential/token
        -> page callback handles token
        -> JavaScript decodes token payload and prints user fields
```

Lab hostname:

```text
oauth-google.websecurity
```

Because Google needs a reachable origin/redirect URI, the lab uses `nip.io`, e.g.:

```text
https://172.16.245.137.nip.io/
```

In Google Console configure OAuth Client ID, Authorized JavaScript Origin and Authorized Redirect URI. Put the resulting client ID into the page's `data-client_id`. fileciteturn41file3

Remember: decoding a Google JWT in JavaScript only reads the payload. A production application must validate the token; Base64URL decoding alone is not verification.

### Fail2Ban

Install:

```bash
apt install fail2ban iptables
cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
```

Main paths:

```text
/etc/fail2ban/jail.conf
/etc/fail2ban/jail.local
/etc/fail2ban/filter.d/
/etc/fail2ban/filter.d/nginx-401-custom.conf
```

Lab filter for NGINX POST requests returning 401:

```ini
[Definition]
failregex = ^<HOST>.*"(POST).*" (401) .*
ignoreregex =
```

Lab jail:

```ini
[nginx-401-custom]
enabled = true
filter = nginx-401-custom
port = http,https
logpath = /var/log/nginx/access.log
findtime = 60
bantime = 60
maxretry = 10
action = iptables-multiport[name=nginx_401, port="http,https"]
```

Meaning:

```text
filter   = what log line counts as a failure
logpath  = which log is scanned
findtime = time window
maxretry = failures allowed inside that window
bantime  = how long the IP stays blocked
action   = firewall action used for the ban
```

Commands:

```bash
systemctl enable --now fail2ban
systemctl restart fail2ban
fail2ban-client status
fail2ban-client status nginx-401-custom
fail2ban-client get nginx-401-custom banned
fail2ban-regex /var/log/nginx/access.log /etc/fail2ban/filter.d/nginx-401-custom.conf
```

The lab expects the client to be blocked after 10 matching 401 POST attempts within 60 seconds. fileciteturn40file1

Helper script:

```text
install_fail2ban_lab7.sh
```

### JWT

JWT structure:

```text
base64url(header).base64url(payload).signature
```

Header in the lab:

```json
{
  "alg": "HS256",
  "typ": "JWT"
}
```

Required payload shape from the lab:

```json
{
  "username": "KoenK",
  "role": "lecturer",
  "admin": false,
  "student": "YOUR_USERNAME",
  "iss": "https://lab7-2.websecurity"
}
```

HS256 means HMAC-SHA256 with a shared secret. The signature protects integrity/authenticity; the header and payload are only Base64URL encoded and remain readable. Do not put secrets in a normal signed JWT payload. fileciteturn39file8

Lab result is returned as:

```text
Authorization: Bearer <JWT>
```

Useful checks:

```bash
curl -k -i https://7-2.websecurity/
```

Look for the `Authorization: Bearer ...` response header after successful login.

### CORS

Origin = scheme + host + port. If any part differs, it is cross-origin. Browser JavaScript is restricted by the Same-Origin Policy unless the target server explicitly permits the origin with CORS headers. fileciteturn41file1

Key headers:

```text
Access-Control-Allow-Origin
Access-Control-Allow-Methods
Access-Control-Allow-Headers
Access-Control-Allow-Credentials
```

Simple request: browser sends the real request with an `Origin` header and then checks the response's CORS headers.

Preflight request: browser first sends `OPTIONS` with the intended method/headers; only if the response permits them does it send the real request. fileciteturn41file1

Lab requirement: `/` and `/api/api.json` should allow only the specified lab origin and GET, POST, OPTIONS. Expected response includes headers similar to: fileciteturn41file1

```text
Access-Control-Allow-Origin: https://lab7-2.websecurity
Access-Control-Allow-Methods: POST, GET, OPTIONS
```

Typical NGINX idea:

```nginx
add_header Access-Control-Allow-Origin "https://lab7-2.websecurity" always;
add_header Access-Control-Allow-Methods "GET, POST, OPTIONS" always;
add_header Access-Control-Allow-Headers "Content-Type, Authorization" always;

if ($request_method = OPTIONS) {
    return 204;
}
```

Test preflight manually:

```bash
curl -k -i -X OPTIONS https://7-2.websecurity/api/api.json \
  -H 'Origin: https://lab7-2.websecurity' \
  -H 'Access-Control-Request-Method: POST' \
  -H 'Access-Control-Request-Headers: Authorization, Content-Type'
```

Important oral distinction:

```text
CORS is enforced by browsers, not by curl and not as a server-side authentication mechanism.
```

## Fast verification

```bash
nginx -t
filebeat test config
filebeat test output
systemctl status nginx --no-pager
systemctl status php8.4-fpm --no-pager
systemctl status filebeat --no-pager
systemctl status fail2ban --no-pager
```
