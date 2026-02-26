#!/bin/bash
# ============================================================
# SKYNET - Auto Fix Xray (One-Click Solution)
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}╔════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   XRAY AUTO-FIX (Solving common issues)${NC}"
echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"
echo ""

# Quick checks
echo -e "${YELLOW}Running diagnostics...${NC}"

# 1. Pastikan xray binary ada
if ! command -v xray &>/dev/null; then
    echo -e "${RED}✗ Xray not installed${NC}"
    echo -e "${YELLOW}Installing Xray...${NC}"
    bash fix-xray.sh
    exit 0
fi

# 2. Pastikan config ada dan valid
if [[ ! -f /usr/local/etc/xray/config.json ]]; then
    echo -e "${RED}✗ Config missing${NC}"
    echo -e "${YELLOW}Creating config...${NC}"
    mkdir -p /usr/local/etc/xray
    if [[ -f /opt/skynet/config/xray.json ]]; then
        cp /opt/skynet/config/xray.json /usr/local/etc/xray/config.json
        echo -e "${GREEN}✓ Config created${NC}"
    else
        echo -e "${RED}Template not found! Run full install.${NC}"
        exit 1
    fi
fi

# 3. Test config
echo -e "${YELLOW}Testing config...${NC}"
if ! xray -test -config /usr/local/etc/xray/config.json &>/dev/null; then
    echo -e "${RED}✗ Config has errors${NC}"
    echo -e "${YELLOW}Regenerating config from template...${NC}"
    cp /opt/skynet/config/xray.json /usr/local/etc/xray/config.json
    
    if xray -test -config /usr/local/etc/xray/config.json &>/dev/null; then
        echo -e "${GREEN}✓ Config fixed${NC}"
    else
        echo -e "${RED}✗ Config still has errors!${NC}"
        xray -test -config /usr/local/etc/xray/config.json
        exit 1
    fi
else
    echo -e "${GREEN}✓ Config valid${NC}"
fi

# 4. Pastikan service file ada
if [[ ! -f /etc/systemd/system/xray-skynet.service ]]; then
    echo -e "${RED}✗ Service file missing${NC}"
    echo -e "${YELLOW}Creating service file...${NC}"
    
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
    echo -e "${GREEN}✓ Service file created${NC}"
fi

# 5. Check for port conflicts
echo -e "${YELLOW}Checking ports...${NC}"
CONFLICT=0
for PORT in 10086 10087 10088; do
    if netstat -tuln 2>/dev/null | grep -q ":$PORT " || ss -tuln 2>/dev/null | grep -q ":$PORT "; then
        PROC=$(netstat -tulpn 2>/dev/null | grep ":$PORT " | grep -v xray | awk '{print $7}' | head -1)
        if [[ -n "$PROC" ]]; then
            echo -e "${RED}✗ Port $PORT in use by: $PROC${NC}"
            PID=$(echo "$PROC" | cut -d'/' -f1)
            if [[ -n "$PID" ]]; then
                echo -e "${YELLOW}  Killing process $PID...${NC}"
                kill -9 "$PID" 2>/dev/null
                CONFLICT=1
            fi
        fi
    fi
done

if [[ $CONFLICT -eq 1 ]]; then
    echo -e "${GREEN}✓ Port conflicts resolved${NC}"
    sleep 1
fi

# 6. Fix permissions
echo -e "${YELLOW}Fixing permissions...${NC}"
chmod +x /usr/local/bin/xray
chown root:root /usr/local/etc/xray/config.json
mkdir -p /var/log/xray
chmod 755 /var/log/xray
echo -e "${GREEN}✓ Permissions fixed${NC}"

# 7. Stop any running instance
systemctl stop xray-skynet 2>/dev/null
pkill -9 xray 2>/dev/null
sleep 2

# 8. Start service
echo ""
echo -e "${YELLOW}Starting Xray service...${NC}"
systemctl daemon-reload
systemctl enable xray-skynet
systemctl start xray-skynet

sleep 3

# 9. Check result
STATUS=$(systemctl is-active xray-skynet 2>/dev/null)

echo ""
if [[ "$STATUS" == "active" ]]; then
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║        ✓ XRAY IS NOW RUNNING!         ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo "Verification:"
    systemctl status xray-skynet --no-pager | head -15
    echo ""
    echo "Listening ports:"
    netstat -tulpn 2>/dev/null | grep xray || ss -tulpn 2>/dev/null | grep xray
else
    echo -e "${RED}╔════════════════════════════════════════╗${NC}"
    echo -e "${RED}║      ✗ XRAY FAILED TO START!          ║${NC}"  
    echo -e "${RED}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo "Status:"
    systemctl status xray-skynet --no-pager
    echo ""
    echo "Last 30 log lines:"
    journalctl -u xray-skynet -n 30 --no-pager
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo "  1. Run full diagnostic: ${CYAN}bash diagnose-xray.sh${NC}"
    echo "  2. Check config manually: ${CYAN}xray -test -config /usr/local/etc/xray/config.json${NC}"
    echo "  3. Try manual start: ${CYAN}xray run -config /usr/local/etc/xray/config.json${NC}"
fi

echo ""
