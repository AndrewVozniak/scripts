#!/usr/bin/env bash
set -euo pipefail

if [ "${EUID}" -ne 0 ]; then
  echo "Run as root: sudo $0 <username>"
  exit 1
fi

USER_NAME="${1:-}"
if [ -z "$USER_NAME" ]; then
  echo "Usage: sudo $0 <username>"
  exit 1
fi

apt update
apt install -y ca-certificates curl git python3 python3.13-venv openssh-client

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
usermod -aG docker "$USER_NAME"
systemctl enable --now docker

if ! docker ps -a --format '{{.Names}}' | grep -qx ollama; then
  docker run -d -v ollama:/root/.ollama -p 11434:11434 --name ollama ollama/ollama
else
  docker start ollama >/dev/null || true
fi

echo "Pulling llama3 in Ollama..."
docker exec ollama ollama pull llama3

WORKDIR="/home/${USER_NAME}/DECEIVE"
if [ ! -d "$WORKDIR/.git" ]; then
  git clone https://github.com/splunk/DECEIVE "$WORKDIR"
fi

chown -R "$USER_NAME:$USER_NAME" "$WORKDIR"

sudo -u "$USER_NAME" bash <<EOF
set -e
cd "$WORKDIR"
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
[ -f SSH/ssh_host_key ] || ssh-keygen -q -t rsa -b 4096 -N '' -f SSH/ssh_host_key
[ -f SSH/config.ini ] || cp SSH/config.ini.TEMPLATE SSH/config.ini
EOF

echo
echo "DECEIVE base setup complete."
echo "Manual steps still required:"
echo "  1) edit $WORKDIR/SSH/config.ini"
echo "     llm_provider = ollama"
echo "     model_name = llama3"
echo "     base_url = http://localhost:11434"
echo "  2) edit $WORKDIR/SSH/prompt.txt"
echo "  3) login again so Docker group membership applies"
echo "  4) run: cd $WORKDIR/SSH && source ../.venv/bin/activate && python3 ./ssh_server.py"
echo "  5) test: ssh guest@localhost -p 8022"
