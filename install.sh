cat > /opt/skynetvpn/install.sh <<'EOF'
#!/bin/bash
# ============================================================
# SKYNET TUNNELING — MAIN INSTALLER
# Compatible: Ubuntu 20.04 / 22.04 / 24.04
# ============================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

SKYNET_DIR="/opt/skynet"

print_banner() {
  clear
  echo -e "${CYAN}${BOLD}"
  echo "╔══════════════════════════════════════════════════════╗"
  echo "║              SKYNET TUNNELING INSTALLER              ║"
  echo "╚══════════════════════════════════════════════════════╝"
  echo -e "${NC}"
}

need_root() {
  if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[ERROR] Jalankan sebagai root${NC}"
    exit 1
  fi
}

need_ubuntu() {
  source /etc/os-release
  if [[ "${ID:-}" != "ubuntu" ]]; then
    echo -e "${RED}[ERROR] Hanya Ubuntu yang didukung${NC}"
    exit 1
  fi
}

log() {
  mkdir -p "$SKYNET_DIR/logs"
  echo -e "${GREEN}[INFO]${NC} $1"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$SKYNET_DIR/logs/install.log"
}

ask_domain_email() {
  echo -ne "${YELLOW}Masukkan domain VPS (contoh: vpn.domain.com):${NC} "
  read -r DOMAIN
  echo -ne "${YELLOW}Masukkan email untuk SSL Let's Encrypt:${NC} "
  read -r EMAIL
  if [[ -z "${DOMAIN:-}" || -z "${EMAIL:-}" ]]; then
    echo -e "${RED}[ERROR] Domain & email wajib diisi${NC}"
    exit 1
  fi
}

create_dirs() {
  log "Membuat struktur /opt/skynet ..."
  mkdir -p "$SKYNET_DIR"/{api,bot,core,core/migrations,config,database,logs,backup,tmp}
  chmod 700 "$SKYNET_DIR"
}

install_packages() {
  log "Install dependency..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get upgrade -y
  apt-get install -y \
    curl wget git unzip zip tar \
    net-tools iproute2 iptables \
    ufw fail2ban \
    nginx \
    openssl ca-certificates \
    jq sqlite3 qrencode \
    vnstat \
    python3 python3-pip python3-venv \
    cron socat lsof htop \
    stunnel4 dropbear \
    certbot \
    python3-certbot-nginx
}

install_python_deps() {
  log "Install python deps (API/BOT)..."
  pip3 install --upgrade pip
  pip3 install fastapi "uvicorn[standard]" python-telegram-bot httpx aiosqlite pydantic python-dotenv
}

seed_files_from_repo() {
  # Asumsi repo ini di-clone ke /opt/skynet, tapi kita jalankan dari folder repo saat ini.
  # Copy file sumber ke runtime /opt/skynet.
  log "Copy source repo ke $SKYNET_DIR ..."
  cp -r ./api "$SKYNET_DIR/"
  cp -r ./bot "$SKYNET_DIR/"
  cp -r ./core "$SKYNET_DIR/"
  cp -r ./config "$SKYNET_DIR/"
  cp ./menu.sh "$SKYNET_DIR/menu.sh"
  chmod +x "$SKYNET_DIR/menu.sh" "$SKYNET_DIR/core/"*.sh "$SKYNET_DIR/core/migrations/"*.sh 2>/dev/null || true
}

init_db() {
  log "Init SQLite database..."
  sqlite3 "$SKYNET_DIR/database/users.db" <<'SQL'
CREATE TABLE IF NOT EXISTS ssh_users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT UNIQUE NOT NULL,
  password TEXT NOT NULL,
  quota_gb REAL DEFAULT 0,
  quota_used REAL DEFAULT 0,
  ip_limit INTEGER DEFAULT 1,
  created_at TEXT DEFAULT (datetime('now')),
  expired_at TEXT,
  status TEXT DEFAULT 'active',
  is_trial INTEGER DEFAULT 0,
  notes TEXT,
  locked_until TEXT
);

CREATE TABLE IF NOT EXISTS xray_users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT UNIQUE NOT NULL,
  uuid TEXT UNIQUE NOT NULL,
  protocol TEXT NOT NULL,
  quota_gb REAL DEFAULT 0,
  quota_used REAL DEFAULT 0,
  ip_limit INTEGER DEFAULT 1,
  created_at TEXT DEFAULT (datetime('now')),
  expired_at TEXT,
  status TEXT DEFAULT 'active',
  is_trial INTEGER DEFAULT 0,
  ws_path TEXT,
  tls_enabled INTEGER DEFAULT 1,
  notes TEXT,
  locked_until TEXT
);

CREATE TABLE IF NOT EXISTS ip_tracking (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT NOT NULL,
  ip_address TEXT NOT NULL,
  protocol TEXT NOT NULL,
  login_at TEXT DEFAULT (datetime('now')),
  logout_at TEXT,
  is_active INTEGER DEFAULT 1
);

CREATE TABLE IF NOT EXISTS violation_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT NOT NULL,
  violation_type TEXT NOT NULL,
  description TEXT,
  occurred_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TEXT DEFAULT (datetime('now'))
);

INSERT OR IGNORE INTO settings(key,value) VALUES
('brand_name','SKYNET TUNNELING'),
('api_key','sk-' || hex(randomblob(16))),
('bot_token',''),
('admin_telegram_id',''),
('domain',''),
('version','1.0.0'),
('script_expire','2027-12-31'),
('client_name','SKYNET CLIENT'),
('monitor_interval','60'),
('lock_duration_seconds','3600');
SQL
  chmod 600 "$SKYNET_DIR/database/users.db"
}

write_settings_conf() {
  local API_KEY
  API_KEY=$(sqlite3 "$SKYNET_DIR/database/users.db" "SELECT value FROM settings WHERE key='api_key'")
  cat > "$SKYNET_DIR/config/settings.conf" <<EOF
SKYNET_DIR=$SKYNET_DIR
DATABASE=$SKYNET_DIR/database/users.db
XRAY_CONFIG=/usr/local/etc/xray/config.json
LOG_DIR=$SKYNET_DIR/logs
BACKUP_DIR=$SKYNET_DIR/backup
API_URL=http://127.0.0.1:8080
VERSION=1.0.0

DOMAIN=$DOMAIN
API_KEY=$API_KEY
BOT_TOKEN=
ADMIN_TELEGRAM_ID=
EOF
  chmod 600 "$SKYNET_DIR/config/settings.conf"
  sqlite3 "$SKYNET_DIR/database/users.db" "UPDATE settings SET value='$DOMAIN' WHERE key='domain';"
}

setup_ssh_dropbear() {
  log "Config OpenSSH + Dropbear..."
  cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak || true
  cat > /etc/ssh/skynet_banner <<'B'
╔══════════════════════════════════════════╗
║          SKYNET TUNNELING SERVER         ║
║    Unauthorized Access is Prohibited     ║
╚══════════════════════════════════════════╝
B

  cat > /etc/ssh/sshd_config <<'S'
Port 22
Port 2222
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes
MaxAuthTries 3
MaxSessions 10
ClientAliveInterval 60
ClientAliveCountMax 3
X11Forwarding no
PrintMotd yes
Banner /etc/ssh/skynet_banner
Subsystem sftp /usr/lib/openssh/sftp-server
S
  systemctl restart ssh

  cat > /etc/default/dropbear <<'D'
NO_START=0
DROPBEAR_PORT=442
DROPBEAR_EXTRA_ARGS="-p 109"
DROPBEAR_BANNER="/etc/ssh/skynet_banner"
D
  systemctl enable dropbear
  systemctl restart dropbear
}

install_xray() {
  log "Install Xray-core..."
  bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
  mkdir -p /usr/local/etc/xray /var/log/xray
  cp "$SKYNET_DIR/config/xray.json" /usr/local/etc/xray/config.json
}

setup_nginx_ssl() {
  log "Install SSL (Let's Encrypt) + Nginx reverse proxy..."
  systemctl stop nginx || true
  certbot certonly --standalone --non-interactive --agree-tos --email "$EMAIL" -d "$DOMAIN" --preferred-challenges http
  systemctl start nginx

  rm -f /etc/nginx/sites-enabled/default
  cat > /etc/nginx/sites-available/skynet <<EOF
server {
  listen 80;
  server_name $DOMAIN;
  return 301 https://\$host\$request_uri;
}
server {
  listen 443 ssl http2;
  server_name $DOMAIN;

  ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

  location /vmess  { proxy_pass http://127.0.0.1:10086; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; }
  location /vless  { proxy_pass http://127.0.0.1:10087; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; }
  location /trojan { proxy_pass http://127.0.0.1:10088; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; }

  location /vmess-grpc { grpc_pass grpc://127.0.0.1:10089; }
  location /vless-grpc { grpc_pass grpc://127.0.0.1:10090; }

  location /api/ { proxy_pass http://127.0.0.1:8080/; }

  location / { return 400 'Bad Request'; add_header Content-Type text/plain; }
}
EOF
  ln -sf /etc/nginx/sites-available/skynet /etc/nginx/sites-enabled/skynet
  nginx -t
  systemctl reload nginx

  (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet --post-hook 'systemctl reload nginx && systemctl restart xray-skynet'") | crontab -
}

setup_stunnel() {
  log "Config stunnel..."
  cat > /etc/stunnel/stunnel.conf <<'EOF'
pid = /var/run/stunnel4/stunnel4.pid
setuid = stunnel4
setgid = stunnel4
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1

[dropbear-ssl]
accept  = 443
connect = 127.0.0.1:442
cert    = /etc/stunnel/stunnel.pem

[openssh-ssl]
accept  = 777
connect = 127.0.0.1:22
cert    = /etc/stunnel/stunnel.pem
EOF

  openssl req -new -x509 -days 3650 -nodes \
    -out /etc/stunnel/stunnel.pem \
    -keyout /etc/stunnel/stunnel.pem \
    -subj "/C=ID/ST=Jakarta/L=Jakarta/O=SKYNET/CN=skynet"
  chmod 600 /etc/stunnel/stunnel.pem
  sed -i 's/ENABLED=0/ENABLED=1/' /etc/default/stunnel4 2>/dev/null || true
  systemctl enable stunnel4
  systemctl restart stunnel4
}

setup_security() {
  log "Enable UFW + Fail2ban..."
  ufw --force reset
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow 22/tcp
  ufw allow 2222/tcp
  ufw allow 80/tcp
  ufw allow 443/tcp
  ufw allow 442/tcp
  ufw allow 109/tcp
  ufw allow 777/tcp
  ufw --force enable

  cat > /etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
bantime=3600
findtime=600
maxretry=5
backend=systemd

[sshd]
enabled=true
port=22,2222
maxretry=3
bantime=7200
EOF
  systemctl enable fail2ban
  systemctl restart fail2ban
}

setup_services() {
  log "Create systemd services..."

  cat > /etc/systemd/system/xray-skynet.service <<'EOF'
[Unit]
Description=SKYNET - Xray
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=always
RestartSec=3
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

  cat > /etc/systemd/system/skynet-api.service <<'EOF'
[Unit]
Description=SKYNET - API
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/skynet/api
EnvironmentFile=/opt/skynet/config/settings.conf
ExecStart=/usr/bin/python3 -m uvicorn app:app --host 127.0.0.1 --port 8080 --workers 2
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

  cat > /etc/systemd/system/skynet-bot.service <<'EOF'
[Unit]
Description=SKYNET - Telegram Bot
After=network.target skynet-api.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/skynet/bot
EnvironmentFile=/opt/skynet/config/settings.conf
ExecStart=/usr/bin/python3 bot.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  cat > /etc/systemd/system/skynet-monitor.service <<'EOF'
[Unit]
Description=SKYNET - Monitor
After=network.target

[Service]
Type=simple
User=root
ExecStart=/opt/skynet/core/monitor.sh daemon
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable xray-skynet skynet-api skynet-bot skynet-monitor
  systemctl restart xray-skynet skynet-api skynet-monitor
}

setup_menu_cmd() {
  ln -sf /opt/skynet/menu.sh /usr/local/bin/menu
  chmod +x /usr/local/bin/menu
}

setup_motd() {
  chmod -x /etc/update-motd.d/* 2>/dev/null || true
  cat > /etc/profile.d/skynet-motd.sh <<'EOF'
#!/bin/bash
[[ -f /opt/skynet/menu.sh ]] && /opt/skynet/menu.sh motd
EOF
  chmod +x /etc/profile.d/skynet-motd.sh
}

main() {
  print_banner
  need_root
  need_ubuntu
  ask_domain_email
  create_dirs
  install_packages
  install_python_deps
  seed_files_from_repo
  init_db
  write_settings_conf
  setup_ssh_dropbear
  install_xray
  setup_nginx_ssl
  setup_stunnel
  setup_security
  setup_services
  setup_menu_cmd
  setup_motd

  API_KEY=$(sqlite3 "$SKYNET_DIR/database/users.db" "SELECT value FROM settings WHERE key='api_key'")
  echo -e "${GREEN}${BOLD}INSTALASI SELESAI${NC}"
  echo -e "Domain: ${YELLOW}$DOMAIN${NC}"
  echo -e "API Key: ${YELLOW}$API_KEY${NC}"
  echo -e "Ketik: ${YELLOW}menu${NC}"
}

main "$@"
EOF
chmod +x /opt/skynetvpn/install.sh
