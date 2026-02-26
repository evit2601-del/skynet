#!/bin/bash
# ============================================================
# SKYNET - Fix Xray Service
# Gunakan jika xray-skynet.service tidak ditemukan
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║        SKYNET - XRAY SERVICE FIXER               ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Error: Harus dijalankan sebagai root!${NC}"
    exit 1
fi

# Step 1: Check if Xray binary exists
echo -e "${YELLOW}[1] Checking Xray binary...${NC}"
if command -v xray &>/dev/null; then
    XRAY_PATH=$(which xray)
    XRAY_VER=$(xray version 2>&1 | head -1)
    echo -e "${GREEN}✓ Xray found: $XRAY_PATH${NC}"
    echo -e "  Version: $XRAY_VER"
else
    echo -e "${RED}✗ Xray not found! Installing...${NC}"
    
    # Install Xray
    echo "Downloading Xray installer..."
    if bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install; then
        echo -e "${GREEN}✓ Xray installed successfully${NC}"
    else
        echo -e "${YELLOW}! Official installer failed, trying manual method...${NC}"
        XRAY_VERSION=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | grep tag_name | cut -d '"' -f 4)
        wget -O /tmp/xray.zip "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-64.zip"
        unzip -o /tmp/xray.zip -d /tmp/xray
        mv /tmp/xray/xray /usr/local/bin/
        chmod +x /usr/local/bin/xray
        rm -rf /tmp/xray /tmp/xray.zip
        echo -e "${GREEN}✓ Xray installed manually${NC}"
    fi
fi

# Step 2: Check config directory and file
echo ""
echo -e "${YELLOW}[2] Checking Xray config...${NC}"
mkdir -p /usr/local/etc/xray
mkdir -p /var/log/xray

if [[ -f /usr/local/etc/xray/config.json ]]; then
    echo -e "${GREEN}✓ Config file exists${NC}"
    
    # Test config
    if xray -test -config /usr/local/etc/xray/config.json &>/dev/null; then
        echo -e "${GREEN}✓ Config is valid${NC}"
    else
        echo -e "${RED}✗ Config has errors!${NC}"
        echo "Testing config..."
        xray -test -config /usr/local/etc/xray/config.json
        echo ""
        echo -e "${YELLOW}Do you want to regenerate config? (y/n)${NC}"
        read -r regen
        if [[ "$regen" == "y" ]]; then
            # Copy template if exists
            if [[ -f /opt/skynet/config/xray.json ]]; then
                cp /opt/skynet/config/xray.json /usr/local/etc/xray/config.json
                echo -e "${GREEN}✓ Config regenerated from template${NC}"
            else
                echo -e "${RED}Template not found at /opt/skynet/config/xray.json${NC}"
                exit 1
            fi
        fi
    fi
else
    echo -e "${RED}✗ Config file not found!${NC}"
    
    if [[ -f /opt/skynet/config/xray.json ]]; then
        echo "Copying from template..."
        cp /opt/skynet/config/xray.json /usr/local/etc/xray/config.json
        echo -e "${GREEN}✓ Config created from template${NC}"
    else
        echo -e "${RED}Template not found! Please run full installer.${NC}"
        exit 1
    fi
fi

# Step 3: Create systemd service
echo ""
echo -e "${YELLOW}[3] Creating systemd service...${NC}"

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

echo -e "${GREEN}✓ Service file created${NC}"

# Step 4: Reload systemd
echo ""
echo -e "${YELLOW}[4] Reloading systemd daemon...${NC}"
systemctl daemon-reload
echo -e "${GREEN}✓ Daemon reloaded${NC}"

# Step 5: Enable and start service
echo ""
echo -e "${YELLOW}[5] Enabling and starting service...${NC}"
systemctl enable xray-skynet
systemctl restart xray-skynet

# Wait a bit
sleep 2

# Step 6: Check status
echo ""
echo -e "${YELLOW}[6] Checking service status...${NC}"
if systemctl is-active --quiet xray-skynet; then
    echo -e "${GREEN}✓ Xray service is RUNNING${NC}"
    systemctl status xray-skynet --no-pager -l
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║            XRAY SERVICE FIXED!                   ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
else
    echo -e "${RED}✗ Service failed to start!${NC}"
    echo ""
    echo "Status:"
    systemctl status xray-skynet --no-pager -l
    echo ""
    echo "Recent logs:"
    journalctl -u xray-skynet -n 20 --no-pager
    echo ""
    echo -e "${YELLOW}Common issues:${NC}"
    echo "  1. Config error - Run: xray -test -config /usr/local/etc/xray/config.json"
    echo "  2. Port already in use - Check: netstat -tulpn | grep '10086\\|10087\\|10088'"
    echo "  3. Permission issue - Check file ownership"
fi

echo ""
