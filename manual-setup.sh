#!/bin/bash
# ============================================================
# SKYNET - Manual Setup Guide
# Untuk instalasi bertahap jika installer otomatis gagal
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

clear
echo -e "${CYAN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════╗
║          SKYNET MANUAL SETUP GUIDE                    ║
╚═══════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Error: Run as root!${NC}"
    exit 1
fi

PS3="Pilih aksi: "
options=(
    "1. Install Xray + Create Service"
    "2. Setup Database"
    "3. Deploy Scripts"
    "4. Setup Nginx"
    "5. Install SSL (Certbot)"
    "6. Setup All Services"
    "7. Check Installation"
    "8. Exit"
)

select opt in "${options[@]}"; do
    case $REPLY in
        1)
            echo -e "${YELLOW}Installing Xray...${NC}"
            bash fix-xray.sh
            ;;
        2)
            echo -e "${YELLOW}Setting up database...${NC}"
            mkdir -p /opt/skynet/database
            
            if [[ -f /opt/skynet/database/users.db ]]; then
                echo -e "${YELLOW}Database already exists. Recreate? (y/n)${NC}"
                read -r confirm
                [[ "$confirm" != "y" ]] && continue
            fi
            
            sqlite3 /opt/skynet/database/users.db << 'EOSQL'
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

CREATE TABLE IF NOT EXISTS ip_tracking (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL,
    ip_address TEXT NOT NULL,
    protocol TEXT NOT NULL,
    login_at TEXT DEFAULT (datetime('now')),
    logout_at TEXT,
    is_active INTEGER DEFAULT 1
);

CREATE TABLE IF NOT EXISTS settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at TEXT DEFAULT (datetime('now'))
);

INSERT OR IGNORE INTO settings (key, value) VALUES
    ('brand_name', 'SKYNET TUNNELING'),
    ('api_key', 'sk-' || hex(randomblob(16))),
    ('bot_token', ''),
    ('admin_telegram_id', ''),
    ('domain', ''),
    ('version', '1.0.0'),
    ('script_expire', '2027-12-31'),
    ('client_name', 'SKYNET CLIENT');
EOSQL
            
            chmod 600 /opt/skynet/database/users.db
            echo -e "${GREEN}✓ Database created${NC}"
            ;;
        3)
            echo -e "${YELLOW}Deploying scripts...${NC}"
            SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
            
            mkdir -p /opt/skynet/{api,bot,core,config,database,logs,backup}
            
            cp -r "$SCRIPT_DIR/core"/* /opt/skynet/core/ 2>/dev/null || true
            cp -r "$SCRIPT_DIR/api"/* /opt/skynet/api/ 2>/dev/null || true
            cp -r "$SCRIPT_DIR/bot"/* /opt/skynet/bot/ 2>/dev/null || true
            cp -r "$SCRIPT_DIR/config"/* /opt/skynet/config/ 2>/dev/null || true
            cp "$SCRIPT_DIR/menu.sh" /opt/skynet/menu.sh 2>/dev/null || true
            
            find /opt/skynet -name "*.sh" -exec chmod +x {} \;
            ln -sf /opt/skynet/menu.sh /usr/local/bin/menu
            
            echo -e "${GREEN}✓ Scripts deployed${NC}"
            ;;
        4)
            echo -e "${YELLOW}Setting up Nginx...${NC}"
            read -p "Domain: " DOMAIN
            
            if [[ -z "$DOMAIN" ]]; then
                echo -e "${RED}Domain required!${NC}"
                continue
            fi
            
            # Create basic config
            cat > /etc/nginx/sites-available/skynet << EOF
server {
    listen 80;
    server_name $DOMAIN;
    
    location / {
        return 200 'SKYNET Server - Please setup SSL';
        add_header Content-Type text/plain;
    }
}
EOF
            
            rm -f /etc/nginx/sites-enabled/default
            ln -sf /etc/nginx/sites-available/skynet /etc/nginx/sites-enabled/
            nginx -t && systemctl reload nginx
            
            echo -e "${GREEN}✓ Nginx configured${NC}"
            echo "Setup SSL next (option 5)"
            ;;
        5)
            echo -e "${YELLOW}Installing SSL...${NC}"
            read -p "Domain: " DOMAIN
            read -p "Email: " EMAIL
            
            systemctl stop nginx
            certbot certonly --standalone -d "$DOMAIN" --email "$EMAIL" --agree-tos --non-interactive
            systemctl start nginx
            
            echo -e "${GREEN}✓ SSL installed${NC}"
            ;;
        6)
            echo -e "${YELLOW}Setting up all services...${NC}"
            
            # API Service
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
            
            echo -e "${GREEN}✓ Services configured${NC}"
            echo "Start them with: systemctl start xray-skynet skynet-api"
            ;;
        7)
            bash check.sh
            ;;
        8)
            exit 0
            ;;
        *)
            echo "Invalid option"
            ;;
    esac
    
    echo ""
    echo -e "${CYAN}Press Enter to continue...${NC}"
    read
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║          SKYNET MANUAL SETUP GUIDE                    ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════╝${NC}"
done
