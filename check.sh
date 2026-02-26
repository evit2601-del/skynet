#!/bin/bash
# ============================================================
# SKYNET TUNNELING — Installation Checker
# Gunakan script ini untuk verifikasi instalasi
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     SKYNET INSTALLATION CHECKER                  ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
echo ""

# Check directories
echo -e "${YELLOW}[1] Checking directories...${NC}"
for dir in /opt/skynet /opt/skynet/api /opt/skynet/bot /opt/skynet/core /opt/skynet/config /opt/skynet/database /opt/skynet/logs; do
    if [[ -d "$dir" ]]; then
        echo -e "  ${GREEN}✓${NC} $dir"
    else
        echo -e "  ${RED}✗${NC} $dir ${RED}NOT FOUND${NC}"
    fi
done
echo ""

# Check files
echo -e "${YELLOW}[2] Checking critical files...${NC}"
files=(
    "/opt/skynet/menu.sh"
    "/opt/skynet/api/app.py"
    "/opt/skynet/bot/bot.py"
    "/opt/skynet/config/settings.conf"
    "/opt/skynet/config/xray.json"
    "/opt/skynet/database/users.db"
    "/usr/local/etc/xray/config.json"
)
for file in "${files[@]}"; do
    if [[ -f "$file" ]]; then
        echo -e "  ${GREEN}✓${NC} $file"
    else
        echo -e "  ${RED}✗${NC} $file ${RED}NOT FOUND${NC}"
    fi
done
echo ""

# Check binaries
echo -e "${YELLOW}[3] Checking binaries...${NC}"
bins=("xray" "sqlite3" "nginx" "python3" "certbot")
for bin in "${bins[@]}"; do
    if command -v "$bin" &> /dev/null; then
        VER=$("$bin" --version 2>&1 | head -1)
        echo -e "  ${GREEN}✓${NC} $bin - $VER"
    else
        echo -e "  ${RED}✗${NC} $bin ${RED}NOT INSTALLED${NC}"
    fi
done
echo ""

# Check services
echo -e "${YELLOW}[4] Checking services...${NC}"
services=("xray-skynet" "skynet-api" "ssh" "nginx" "fail2ban" "dropbear" "stunnel4")
for svc in "${services[@]}"; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $svc - ${GREEN}RUNNING${NC}"
    else
        STATUS=$(systemctl is-active "$svc" 2>/dev/null || echo "not-found")
        echo -e "  ${RED}✗${NC} $svc - ${RED}$STATUS${NC}"
    fi
done
echo ""

# Check ports
echo -e "${YELLOW}[5] Checking listening ports...${NC}"
ports=(22 80 443 442 109 777 444 10086 10087 10088)
for port in "${ports[@]}"; do
    if netstat -tuln 2>/dev/null | grep -q ":$port " || ss -tuln 2>/dev/null | grep -q ":$port "; then
        echo -e "  ${GREEN}✓${NC} Port $port - LISTENING"
    else
        echo -e "  ${YELLOW}!${NC} Port $port - NOT LISTENING"
    fi
done
echo ""

# Check database
echo -e "${YELLOW}[6] Checking database...${NC}"
if [[ -f /opt/skynet/database/users.db ]]; then
    TABLES=$(sqlite3 /opt/skynet/database/users.db "SELECT name FROM sqlite_master WHERE type='table';" 2>/dev/null)
    if [[ -n "$TABLES" ]]; then
        echo -e "  ${GREEN}✓${NC} Database OK - Tables found:"
        echo "$TABLES" | sed 's/^/    /'
    else
        echo -e "  ${RED}✗${NC} Database empty or corrupt"
    fi
else
    echo -e "  ${RED}✗${NC} Database not found"
fi
echo ""

# Check Xray config
echo -e "${YELLOW}[7] Checking Xray configuration...${NC}"
if [[ -f /usr/local/etc/xray/config.json ]]; then
    if xray -test -config /usr/local/etc/xray/config.json &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Xray config is valid"
    else
        echo -e "  ${RED}✗${NC} Xray config has errors!"
        echo -e "     Run: ${CYAN}xray -test -config /usr/local/etc/xray/config.json${NC}"
    fi
else
    echo -e "  ${RED}✗${NC} Xray config not found"
fi
echo ""

# Check SSL
echo -e "${YELLOW}[8] Checking SSL certificate...${NC}"
if [[ -f /opt/skynet/config/settings.conf ]]; then
    DOMAIN=$(grep "^DOMAIN=" /opt/skynet/config/settings.conf | cut -d'=' -f2)
    if [[ -n "$DOMAIN" ]] && [[ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]]; then
        EXPIRY=$(openssl x509 -enddate -noout -in "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" | cut -d'=' -f2)
        echo -e "  ${GREEN}✓${NC} SSL certificate found for $DOMAIN"
        echo -e "     Expires: $EXPIRY"
    else
        echo -e "  ${YELLOW}!${NC} No SSL certificate found (might be using self-signed)"
    fi
fi
echo ""

# Summary
echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                    SUMMARY                       ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"

# Count issues
ISSUE_COUNT=0

# Re-check critical services
for svc in "xray-skynet" "nginx"; do
    if ! systemctl is-active --quiet "$svc" 2>/dev/null; then
        ((ISSUE_COUNT++))
    fi
done

if [[ $ISSUE_COUNT -eq 0 ]]; then
    echo -e "${GREEN}✓ Installation looks good!${NC}"
    echo -e "  Run ${CYAN}menu${NC} to access the management panel"
else
    echo -e "${RED}✗ Found $ISSUE_COUNT critical issue(s)${NC}"
    echo -e "  Check the details above and fix the issues"
    echo ""
    echo -e "${YELLOW}Common fixes:${NC}"
    echo -e "  1. Restart services: ${CYAN}systemctl restart xray-skynet nginx${NC}"
    echo -e "  2. Check logs: ${CYAN}journalctl -u xray-skynet -n 50${NC}"
    echo -e "  3. Re-run installer: ${CYAN}bash /root/skynet/install.sh${NC}"
fi
echo ""
