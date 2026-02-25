#!/bin/bash
# ============================================================
# SKYNET TUNNELING — MAIN INSTALLER
# Compatible: Ubuntu 20.04 / 22.04 / 24.04
# Author: SKYNET TEAM
# ============================================================

set -e

# ── Warna terminal
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Banner
print_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║              SKYNET TUNNELING INSTALLER              ║"
    echo "║          Ubuntu 20.04 / 22.04 / 24.04               ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# ── Cek root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[ERROR] Script harus dijalankan sebagai root!${NC}"
        exit 1
    fi
}

# ── Cek OS
check_os() {
    if [[ ! -f /etc/os-release ]]; then
        echo -e "${RED}[ERROR] OS tidak didukung!${NC}"
        exit 1
    fi
    source /etc/os-release
    if [[ "$ID" != "ubuntu" ]]; then
        echo -e "${RED}[ERROR] Hanya mendukung Ubuntu!${NC}"
        exit 1
    fi
    echo -e "${GREEN}[OK] OS: Ubuntu $VERSION_ID${NC}"
}

# ── Log function
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> /opt/skynet/logs/install.log
}

err() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >> /opt/skynet/logs/install.log
}

# ── Buat struktur folder project
create_directories() {
    log "Membuat struktur direktori project..."
    mkdir -p /opt/skynet/{api,bot,core,config,database,logs,backup,tmp}
    mkdir -p /etc/skynet
    mkdir -p /var/log/skynet
    chmod 700 /opt/skynet
    chmod 755 /opt/skynet/logs
    log "Direktori berhasil dibuat."
}

# ── Update & install dependency dasar
install_base_packages() {
    log "Update sistem & install dependency dasar..."
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
        cron \
        socat \
        lsof \
        htop \
        speedtest-cli \
        stunnel4 \
        dropbear \
        certbot python3-certbot-nginx \
        build-essential \
        software-properties-common \
        gnupg2 lsb-release
    log "Package dasar berhasil diinstall."
}

# ── Install Python dependencies
install_python_deps() {
    log "Install Python dependencies..."
    pip3 install --upgrade pip
    pip3 install \
        fastapi \
        uvicorn[standard] \
        python-telegram-bot \
        aiohttp \
        aiosqlite \
        pydantic \
        python-dotenv \
        httpx \
        requests \
        python-jose \
        passlib \
        bcrypt
    log "Python dependencies berhasil diinstall."
}

# ── Konfigurasi OpenSSH
configure_openssh() {
    log "Mengkonfigurasi OpenSSH..."
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

    cat > /etc/ssh/sshd_config << 'EOF'
# SKYNET - OpenSSH Configuration
Port 22
Port 2222
AddressFamily any
ListenAddress 0.0.0.0

# Authentication
PermitRootLogin yes
PubkeyAuthentication yes
PasswordAuthentication yes
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes

# Security
MaxAuthTries 3
MaxSessions 10
LoginGraceTime 30
ClientAliveInterval 60
ClientAliveCountMax 3

# Features
X11Forwarding no
PrintMotd yes
PrintLastLog no
Banner /etc/ssh/skynet_banner

# Subsystem
Subsystem sftp /usr/lib/openssh/sftp-server
EOF

    # Buat SSH banner
    cat > /etc/ssh/skynet_banner << 'EOF'

    ╔══════════════════════════════════════════╗
    ║          SKYNET TUNNELING SERVER         ║
    ║    Unauthorized Access is Prohibited     ║
    ╚══════════════════════════════════════════╝

EOF

    systemctl restart ssh
    log "OpenSSH berhasil dikonfigurasi."
}

# ── Konfigurasi Dropbear
configure_dropbear() {
    log "Mengkonfigurasi Dropbear..."
    cat > /etc/default/dropbear << 'EOF'
# SKYNET - Dropbear Configuration
NO_START=0
DROPBEAR_PORT=442
DROPBEAR_EXTRA_ARGS="-p 109"
DROPBEAR_BANNER="/etc/ssh/skynet_banner"
DROPBEAR_RECEIVE_WINDOW=65536
EOF

    systemctl enable dropbear
    systemctl restart dropbear
    log "Dropbear berhasil dikonfigurasi pada port 442 & 109."
}

# ── Install & konfigurasi Xray-core
install_xray() {
    log "Menginstall Xray-core terbaru..."

    # Download installer resmi Xray
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

    # Verifikasi instalasi
    if ! command -v xray &> /dev/null; then
        err "Xray gagal diinstall!"
        exit 1
    fi

    XRAY_VER=$(xray version | head -1)
    log "Xray berhasil diinstall: $XRAY_VER"

    # Buat direktori config
    mkdir -p /usr/local/etc/xray

    # Salin config template (akan di-generate saat setup domain)
    cp /opt/skynet/config/xray.json /usr/local/etc/xray/config.json 2>/dev/null || true
}

# ── Generate konfigurasi Xray
generate_xray_config() {
    local DOMAIN=$1
    log "Membuat konfigurasi Xray untuk domain: $DOMAIN..."

    cat > /usr/local/etc/xray/config.json << EOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "api": {
    "tag": "api",
    "services": ["HandlerService","LoggerService","StatsService"]
  },
  "stats": {},
  "policy": {
    "levels": {
      "0": {"statsUserUplink": true, "statsUserDownlink": true}
    },
    "system": {"statsInboundUplink": true, "statsInboundDownlink": true}
  },
  "inbounds": [
    {
      "tag": "vmess-ws",
      "port": 10086,
      "protocol": "vmess",
      "settings": {
        "clients": []
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/vmess"
        }
      },
      "sniffing": {"enabled": true, "destOverride": ["http","tls"]}
    },
    {
      "tag": "vless-ws",
      "port": 10087,
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/vless"
        }
      },
      "sniffing": {"enabled": true, "destOverride": ["http","tls"]}
    },
    {
      "tag": "trojan-ws",
      "port": 10088,
      "protocol": "trojan",
      "settings": {
        "clients": []
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/trojan"
        }
      },
      "sniffing": {"enabled": true, "destOverride": ["http","tls"]}
    },
    {
      "tag": "vmess-grpc",
      "port": 10089,
      "protocol": "vmess",
      "settings": {
        "clients": []
      },
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": {
          "serviceName": "vmess-grpc"
        }
      }
    },
    {
      "tag": "vless-grpc",
      "port": 10090,
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": {
          "serviceName": "vless-grpc"
        }
      }
    }
  ],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": {}
    },
    {
      "tag": "blocked",
      "protocol": "blackhole",
      "settings": {}
    }
  ],
  "routing": {
    "rules": [
      {
        "inboundTag": ["api"],
        "outboundTag": "api",
        "type": "field"
      },
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "blocked"
      }
    ]
  }
}
EOF

    mkdir -p /var/log/xray
    log "Konfigurasi Xray berhasil dibuat."
}

# ── Konfigurasi Nginx Reverse Proxy
configure_nginx() {
    local DOMAIN=$1
    log "Mengkonfigurasi Nginx untuk domain: $DOMAIN..."

    # Hapus config default
    rm -f /etc/nginx/sites-enabled/default

    # Buat config Skynet
    cat > /etc/nginx/sites-available/skynet << EOF
# SKYNET - Nginx Configuration

# HTTP → Redirect ke HTTPS
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}

# HTTPS
server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;
    ssl_stapling on;
    ssl_stapling_verify on;

    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";

    # VMess WebSocket
    location /vmess {
        proxy_pass http://127.0.0.1:10086;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 86400;
    }

    # VLESS WebSocket
    location /vless {
        proxy_pass http://127.0.0.1:10087;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 86400;
    }

    # Trojan WebSocket
    location /trojan {
        proxy_pass http://127.0.0.1:10088;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 86400;
    }

    # VMess gRPC
    location /vmess-grpc {
        grpc_pass grpc://127.0.0.1:10089;
        grpc_read_timeout 86400;
        grpc_send_timeout 86400;
    }

    # VLESS gRPC
    location /vless-grpc {
        grpc_pass grpc://127.0.0.1:10090;
        grpc_read_timeout 86400;
        grpc_send_timeout 86400;
    }

    # REST API
    location /api/ {
        proxy_pass http://127.0.0.1:8080/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # Default response
    location / {
        return 400 'Bad Request';
        add_header Content-Type text/plain;
    }
}
EOF

    ln -sf /etc/nginx/sites-available/skynet /etc/nginx/sites-enabled/skynet
    nginx -t && systemctl reload nginx
    log "Nginx berhasil dikonfigurasi."
}

# ── Install SSL dengan Let's Encrypt
install_ssl() {
    local DOMAIN=$1
    local EMAIL=$2
    log "Menginstall SSL untuk domain: $DOMAIN..."

    # Stop nginx sementara untuk certbot standalone
    systemctl stop nginx || true

    certbot certonly \
        --standalone \
        --non-interactive \
        --agree-tos \
        --email "$EMAIL" \
        -d "$DOMAIN" \
        --preferred-challenges http

    # Auto-renew
    (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet --post-hook 'systemctl reload nginx xray'") | crontab -

    systemctl start nginx
    log "SSL berhasil diinstall."
}

# ── Konfigurasi Stunnel
configure_stunnel() {
    log "Mengkonfigurasi Stunnel..."
    cat > /etc/stunnel/stunnel.conf << 'EOF'
# SKYNET - Stunnel Configuration
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

    # Generate self-signed cert untuk stunnel
    openssl req -new -x509 -days 3650 -nodes \
        -out /etc/stunnel/stunnel.pem \
        -keyout /etc/stunnel/stunnel.pem \
        -subj "/C=ID/ST=Jakarta/L=Jakarta/O=SKYNET/CN=skynet"

    chmod 600 /etc/stunnel/stunnel.pem

    # Enable stunnel
    sed -i 's/ENABLED=0/ENABLED=1/' /etc/default/stunnel4 2>/dev/null || true
    systemctl enable stunnel4
    systemctl restart stunnel4
    log "Stunnel berhasil dikonfigurasi."
}

# ── Install BadVPN UDPGW
install_badvpn() {
    log "Menginstall BadVPN UDPGW..."

    if command -v badvpn-udpgw &> /dev/null; then
        log "BadVPN sudah terinstall."
        return
    fi

    apt-get install -y cmake

    cd /tmp
    git clone https://github.com/ambrop72/badvpn.git badvpn 2>/dev/null || \
        wget -O badvpn.zip https://github.com/ambrop72/badvpn/archive/refs/heads/master.zip && \
        unzip badvpn.zip && mv badvpn-master badvpn

    mkdir -p /tmp/badvpn/build
    cd /tmp/badvpn/build
    cmake .. -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1
    make install

    # Systemd service untuk BadVPN
    cat > /etc/systemd/system/badvpn-udpgw.service << 'EOF'
[Unit]
Description=BadVPN UDP Gateway
After=network.target

[Service]
Type=simple
User=nobody
ExecStart=/usr/local/bin/badvpn-udpgw --listen-addr 127.0.0.1:7300 --max-clients 1000 --max-connections-for-client 10
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable badvpn-udpgw
    systemctl start badvpn-udpgw
    log "BadVPN UDPGW berhasil diinstall pada port 7300."
}

# ── Konfigurasi UFW Firewall
configure_ufw() {
    log "Mengkonfigurasi UFW Firewall..."

    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing

    # Port yang diizinkan
    ufw allow 22/tcp    # SSH
    ufw allow 2222/tcp  # SSH alt
    ufw allow 80/tcp    # HTTP
    ufw allow 443/tcp   # HTTPS / Stunnel
    ufw allow 109/tcp   # Dropbear
    ufw allow 442/tcp   # Dropbear SSL
    ufw allow 777/tcp   # Stunnel SSH
    ufw allow 1194/udp  # OpenVPN (opsional)
    ufw allow 8080/tcp  # API
    ufw allow 7300/udp  # BadVPN

    # Rate limiting SSH
    ufw limit 22/tcp
    ufw limit 2222/tcp

    ufw --force enable
    log "UFW Firewall berhasil dikonfigurasi."
}

# ── Konfigurasi Fail2Ban
configure_fail2ban() {
    log "Mengkonfigurasi Fail2Ban..."

    cat > /etc/fail2ban/jail.local << 'EOF'
# SKYNET - Fail2Ban Configuration
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 5
backend  = systemd
ignoreip = 127.0.0.1/8

[sshd]
enabled  = true
port     = 22,2222
logpath  = %(sshd_log)s
maxretry = 3
bantime  = 7200

[nginx-http-auth]
enabled  = true
port     = http,https
logpath  = /var/log/nginx/error.log

[nginx-limit-req]
enabled  = true
port     = http,https
logpath  = /var/log/nginx/error.log
maxretry = 10
EOF

    systemctl enable fail2ban
    systemctl restart fail2ban
    log "Fail2Ban berhasil dikonfigurasi."
}

# ── Enable BBR
enable_bbr() {
    log "Mengaktifkan BBR TCP Congestion Control..."

    # Tambah ke sysctl.conf
    cat >> /etc/sysctl.conf << 'EOF'

# SKYNET - BBR & Network Optimization
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_mem = 25600 51200 102400
net.ipv4.tcp_rmem = 4096 65536 8388608
net.ipv4.tcp_wmem = 4096 65536 8388608
net.ipv4.ip_local_port_range = 10000 65000
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_forward = 1
EOF

    sysctl -p
    log "BBR berhasil diaktifkan."
}

# ── Konfigurasi Auto Reboot Scheduler
configure_auto_reboot() {
    log "Mengkonfigurasi auto reboot scheduler..."

    # Default: reboot tiap hari jam 03:00
    (crontab -l 2>/dev/null | grep -v "skynet-reboot"; \
     echo "0 3 * * 0 /sbin/reboot # skynet-reboot") | crontab -

    log "Auto reboot terjadwal setiap Minggu jam 03:00."
}

# ── Inisialisasi Database SQLite
init_database() {
    log "Menginisialisasi database SQLite..."

    sqlite3 /opt/skynet/database/users.db << 'EOF'
-- Tabel SSH users
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
    notes TEXT
);

-- Tabel Xray users
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
    notes TEXT
);

-- Tabel IP tracking
CREATE TABLE IF NOT EXISTS ip_tracking (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL,
    ip_address TEXT NOT NULL,
    protocol TEXT NOT NULL,
    login_at TEXT DEFAULT (datetime('now')),
    logout_at TEXT,
    is_active INTEGER DEFAULT 1
);

-- Tabel traffic log
CREATE TABLE IF NOT EXISTS traffic_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL,
    upload_bytes INTEGER DEFAULT 0,
    download_bytes INTEGER DEFAULT 0,
    recorded_at TEXT DEFAULT (datetime('now'))
);

-- Tabel violation log
CREATE TABLE IF NOT EXISTS violation_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL,
    violation_type TEXT NOT NULL,
    description TEXT,
    occurred_at TEXT DEFAULT (datetime('now'))
);

-- Tabel settings
CREATE TABLE IF NOT EXISTS settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at TEXT DEFAULT (datetime('now'))
);

-- Default settings
INSERT OR IGNORE INTO settings (key, value) VALUES
    ('brand_name', 'SKYNET TUNNELING'),
    ('api_key', 'sk-' || hex(randomblob(16))),
    ('bot_token', ''),
    ('admin_telegram_id', ''),
    ('domain', ''),
    ('version', '1.0.0'),
    ('script_expire', '2027-12-31'),
    ('client_name', 'SKYNET CLIENT');

-- Indices
CREATE INDEX IF NOT EXISTS idx_ssh_username ON ssh_users(username);
CREATE INDEX IF NOT EXISTS idx_xray_username ON xray_users(username);
CREATE INDEX IF NOT EXISTS idx_xray_uuid ON xray_users(uuid);
CREATE INDEX IF NOT EXISTS idx_ip_tracking ON ip_tracking(username, is_active);
EOF

    chmod 600 /opt/skynet/database/users.db
    log "Database SQLite berhasil diinisialisasi."
}

# ── Buat systemd service untuk Xray
create_xray_service() {
    log "Membuat systemd service untuk Xray..."

    cat > /etc/systemd/system/xray-skynet.service << 'EOF'
[Unit]
Description=SKYNET - Xray Service
Documentation=https://github.com/XTLS/Xray-core
After=network.target

[Service]
Type=simple
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
ExecReload=/bin/kill -HUP $MAINPID
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable xray-skynet
    log "Xray service berhasil dibuat."
}

# ── Buat systemd service untuk API
create_api_service() {
    log "Membuat systemd service untuk API..."

    cat > /etc/systemd/system/skynet-api.service << 'EOF'
[Unit]
Description=SKYNET - REST API Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/skynet/api
ExecStart=/usr/bin/python3 -m uvicorn app:app --host 127.0.0.1 --port 8080 --workers 2
Restart=always
RestartSec=5
EnvironmentFile=/opt/skynet/config/settings.conf

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable skynet-api
    log "API service berhasil dibuat."
}

# ── Buat systemd service untuk Bot
create_bot_service() {
    log "Membuat systemd service untuk Bot..."

    cat > /etc/systemd/system/skynet-bot.service << 'EOF'
[Unit]
Description=SKYNET - Telegram Bot Service
After=network.target skynet-api.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/skynet/bot
ExecStart=/usr/bin/python3 bot.py
Restart=always
RestartSec=10
EnvironmentFile=/opt/skynet/config/settings.conf

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log "Bot service berhasil dibuat."
}

# ── Buat systemd service untuk Monitoring
create_monitor_service() {
    log "Membuat systemd service untuk Monitoring..."

    cat > /etc/systemd/system/skynet-monitor.service << 'EOF'
[Unit]
Description=SKYNET - Monitoring Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=/opt/skynet/core/monitor.sh daemon
Restart=always
RestartSec=60

[Install]
WantedBy=multi-user.target
EOF

    # Timer untuk monitoring tiap 1 menit
    cat > /etc/systemd/system/skynet-monitor.timer << 'EOF'
[Unit]
Description=SKYNET Monitor Timer
After=network.target

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable skynet-monitor.timer
    systemctl start skynet-monitor.timer
    log "Monitoring service berhasil dibuat."
}

# ── Salin file-file core ke direktori
deploy_scripts() {
    log "Deploy scripts ke /opt/skynet/..."

    # Pastikan semua script bisa dieksekusi
    find /opt/skynet -name "*.sh" -exec chmod +x {} \;
    find /opt/skynet -name "*.py" -exec chmod 644 {} \;

    # Symlink menu ke /usr/local/bin
    ln -sf /opt/skynet/menu.sh /usr/local/bin/menu
    chmod +x /usr/local/bin/menu

    log "Scripts berhasil di-deploy."
}

# ── Setup MOTD (login banner)
setup_motd() {
    log "Setup MOTD..."

    # Disable MOTD bawaan Ubuntu
    chmod -x /etc/update-motd.d/* 2>/dev/null || true

    cat > /etc/profile.d/skynet-motd.sh << 'MOTDEOF'
#!/bin/bash
# SKYNET MOTD - tampil saat login
[[ -f /opt/skynet/menu.sh ]] && /opt/skynet/menu.sh motd
MOTDEOF

    chmod +x /etc/profile.d/skynet-motd.sh
    log "MOTD berhasil dikonfigurasi."
}

# ── Setup konfigurasi global
create_settings_conf() {
    local DOMAIN=$1
    log "Membuat settings.conf..."

    API_KEY=$(sqlite3 /opt/skynet/database/users.db "SELECT value FROM settings WHERE key='api_key'")

    cat > /opt/skynet/config/settings.conf << EOF
# SKYNET - Global Settings
SKYNET_DIR=/opt/skynet
DATABASE=/opt/skynet/database/users.db
DOMAIN=$DOMAIN
API_KEY=$API_KEY
API_URL=http://127.0.0.1:8080
LOG_DIR=/opt/skynet/logs
BACKUP_DIR=/opt/skynet/backup
XRAY_CONFIG=/usr/local/etc/xray/config.json
VERSION=1.0.0
EOF

    chmod 600 /opt/skynet/config/settings.conf
    log "settings.conf berhasil dibuat."
}

# ── Main installer
main() {
    print_banner
    check_root
    check_os

    # Buat log dir dulu
    mkdir -p /opt/skynet/logs

    echo -e "${YELLOW}Masukkan domain VPS (contoh: vpn.domain.com):${NC}"
    read -r DOMAIN
    echo -e "${YELLOW}Masukkan email untuk SSL Let's Encrypt:${NC}"
    read -r EMAIL

    if [[ -z "$DOMAIN" ]] || [[ -z "$EMAIL" ]]; then
        err "Domain dan email tidak boleh kosong!"
        exit 1
    fi

    log "Mulai instalasi SKYNET TUNNELING..."
    log "Domain: $DOMAIN"
    log "Email: $EMAIL"

    # Update domain ke database setelah init
    create_directories
    install_base_packages
    install_python_deps
    init_database
    configure_openssh
    configure_dropbear
    install_xray
    generate_xray_config "$DOMAIN"
    install_ssl "$DOMAIN" "$EMAIL"
    configure_nginx "$DOMAIN"
    configure_stunnel
    install_badvpn
    configure_ufw
    configure_fail2ban
    enable_bbr
    configure_auto_reboot
    create_xray_service
    create_api_service
    create_bot_service
    create_monitor_service
    create_settings_conf "$DOMAIN"
    deploy_scripts
    setup_motd

    # Update domain di database
    sqlite3 /opt/skynet/database/users.db \
        "UPDATE settings SET value='$DOMAIN' WHERE key='domain'"

    # Start services
    log "Menjalankan semua service..."
    systemctl start xray-skynet
    systemctl start skynet-api

    echo ""
    echo -e "${GREEN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║          INSTALASI BERHASIL! 🎉                      ║"
    echo "╠══════════════════════════════════════════════════════╣"
    echo "║  Domain    : $DOMAIN"
    echo "║  SSH       : Port 22, 2222"
    echo "║  Dropbear  : Port 442, 109"
    echo "║  Stunnel   : Port 443, 777"
    echo "║  HTTPS     : Port 443 (TLS)"
    echo "║  BadVPN    : Port 7300"
    echo "║  API       : http://127.0.0.1:8080"
    echo "╠══════════════════════════════════════════════════════╣"
    echo "║  Ketik 'menu' untuk membuka panel                    ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    API_KEY=$(sqlite3 /opt/skynet/database/users.db "SELECT value FROM settings WHERE key='api_key'")
    echo -e "${YELLOW}API Key: ${GREEN}$API_KEY${NC}"
    echo -e "${YELLOW}Simpan API Key ini dengan aman!${NC}"
}

main "$@"
