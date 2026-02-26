#!/bin/bash
# ============================================================
# SKYNET - Xray Diagnostic Tool
# Cek detail kenapa Xray tidak mau jalan
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}${BOLD}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║          XRAY DIAGNOSTIC TOOL                        ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""

# 1. Check Xray Binary
echo -e "${YELLOW}[1] Checking Xray Binary...${NC}"
if command -v xray &>/dev/null; then
    XRAY_PATH=$(which xray)
    XRAY_VER=$(xray version 2>&1 | head -1)
    echo -e "  ${GREEN}✓ Xray found${NC}"
    echo -e "    Path    : $XRAY_PATH"
    echo -e "    Version : $XRAY_VER"
    ls -lh "$XRAY_PATH"
else
    echo -e "  ${RED}✗ Xray binary NOT FOUND!${NC}"
    echo -e "  ${YELLOW}Fix: bash fix-xray.sh${NC}"
    exit 1
fi

# 2. Check Config File
echo ""
echo -e "${YELLOW}[2] Checking Config File...${NC}"
CONFIG="/usr/local/etc/xray/config.json"
if [[ -f "$CONFIG" ]]; then
    echo -e "  ${GREEN}✓ Config file exists${NC}"
    echo -e "    Path: $CONFIG"
    ls -lh "$CONFIG"
    
    # Test config validity
    echo -e "  ${CYAN}Testing config validity...${NC}"
    TEST_OUTPUT=$(xray -test -config "$CONFIG" 2>&1)
    if echo "$TEST_OUTPUT" | grep -q "Configuration OK"; then
        echo -e "  ${GREEN}✓ Config is VALID${NC}"
    else
        echo -e "  ${RED}✗ Config has ERRORS:${NC}"
        echo "$TEST_OUTPUT" | sed 's/^/    /'
        echo ""
        echo -e "  ${YELLOW}Possible fix:${NC}"
        echo -e "    cp /opt/skynet/config/xray.json $CONFIG"
        echo -e "    systemctl restart xray-skynet"
        exit 1
    fi
else
    echo -e "  ${RED}✗ Config file NOT FOUND!${NC}"
    echo -e "  ${YELLOW}Fix:${NC}"
    echo -e "    cp /opt/skynet/config/xray.json $CONFIG"
    exit 1
fi

# 3. Check Service File
echo ""
echo -e "${YELLOW}[3] Checking Service File...${NC}"
SERVICE_FILE="/etc/systemd/system/xray-skynet.service"
if [[ -f "$SERVICE_FILE" ]]; then
    echo -e "  ${GREEN}✓ Service file exists${NC}"
    echo -e "    Path: $SERVICE_FILE"
    echo -e "  ${CYAN}Service content:${NC}"
    cat "$SERVICE_FILE" | sed 's/^/    /'
else
    echo -e "  ${RED}✗ Service file NOT FOUND!${NC}"
    echo -e "  ${YELLOW}Fix: bash fix-xray.sh${NC}"
    exit 1
fi

# 4. Check Service Status
echo ""
echo -e "${YELLOW}[4] Checking Service Status...${NC}"
if systemctl list-unit-files | grep -q xray-skynet; then
    echo -e "  ${GREEN}✓ Service registered${NC}"
    
    STATUS=$(systemctl is-active xray-skynet 2>/dev/null)
    ENABLED=$(systemctl is-enabled xray-skynet 2>/dev/null)
    
    echo -e "    Status  : $STATUS"
    echo -e "    Enabled : $ENABLED"
    
    if [[ "$STATUS" != "active" ]]; then
        echo -e "  ${RED}✗ Service is NOT RUNNING!${NC}"
    fi
else
    echo -e "  ${RED}✗ Service NOT registered!${NC}"
    echo -e "  ${YELLOW}Fix: systemctl daemon-reload${NC}"
fi

# 5. Check Recent Logs
echo ""
echo -e "${YELLOW}[5] Checking Recent Logs (Last 20 lines)...${NC}"
echo -e "  ${CYAN}Systemd Journal:${NC}"
if journalctl -u xray-skynet -n 20 --no-pager 2>/dev/null | grep -q .; then
    journalctl -u xray-skynet -n 20 --no-pager | sed 's/^/    /'
else
    echo -e "    ${YELLOW}No logs found (service never started?)${NC}"
fi

echo ""
echo -e "  ${CYAN}Xray Error Log:${NC}"
if [[ -f /var/log/xray/error.log ]]; then
    tail -n 10 /var/log/xray/error.log | sed 's/^/    /'
else
    echo -e "    ${YELLOW}Log file not found${NC}"
fi

# 6. Check Ports
echo ""
echo -e "${YELLOW}[6] Checking Required Ports...${NC}"
PORTS=(10086 10087 10088 10089 10090)
PORT_ISSUES=0

for PORT in "${PORTS[@]}"; do
    if netstat -tuln 2>/dev/null | grep -q ":$PORT " || ss -tuln 2>/dev/null | grep -q ":$PORT "; then
        PROCESS=$(netstat -tulpn 2>/dev/null | grep ":$PORT " | awk '{print $7}' || ss -tulpn 2>/dev/null | grep ":$PORT " | awk '{print $7}')
        if echo "$PROCESS" | grep -q "xray"; then
            echo -e "  ${GREEN}✓ Port $PORT - listening (xray)${NC}"
        else
            echo -e "  ${RED}✗ Port $PORT - used by: $PROCESS${NC}"
            ((PORT_ISSUES++))
        fi
    else
        echo -e "  ${YELLOW}! Port $PORT - not listening${NC}"
    fi
done

if [[ $PORT_ISSUES -gt 0 ]]; then
    echo -e "  ${RED}Found $PORT_ISSUES port conflict(s)!${NC}"
    echo -e "  ${YELLOW}Kill the conflicting process and restart xray${NC}"
fi

# 7. Check Permissions
echo ""
echo -e "${YELLOW}[7] Checking Permissions...${NC}"
echo -e "  Config file:"
ls -la "$CONFIG" 2>/dev/null | sed 's/^/    /' || echo -e "    ${RED}Not found${NC}"
echo -e "  Binary:"
ls -la "$(which xray)" 2>/dev/null | sed 's/^/    /' || echo -e "    ${RED}Not found${NC}"
echo -e "  Log directory:"
ls -lad /var/log/xray 2>/dev/null | sed 's/^/    /' || echo -e "    ${RED}Not found${NC}"

# 8. Try to Start Service
echo ""
echo -e "${YELLOW}[8] Attempting to Start Service...${NC}"
echo -e "  ${CYAN}Running: systemctl start xray-skynet${NC}"
systemctl start xray-skynet 2>&1 | sed 's/^/    /'

sleep 3

STATUS=$(systemctl is-active xray-skynet 2>/dev/null)
if [[ "$STATUS" == "active" ]]; then
    echo -e "  ${GREEN}✓ Service started successfully!${NC}"
else
    echo -e "  ${RED}✗ Service failed to start!${NC}"
    echo ""
    echo -e "  ${YELLOW}Detailed status:${NC}"
    systemctl status xray-skynet --no-pager -l | sed 's/^/    /'
fi

# 9. Summary & Recommendations
echo ""
echo -e "${CYAN}${BOLD}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║                  DIAGNOSTIC SUMMARY                  ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"

FINAL_STATUS=$(systemctl is-active xray-skynet 2>/dev/null)
if [[ "$FINAL_STATUS" == "active" ]]; then
    echo -e "${GREEN}${BOLD}✓ XRAY IS NOW RUNNING!${NC}"
    echo ""
    echo "Verification:"
    echo "  systemctl status xray-skynet"
    echo "  netstat -tulpn | grep xray"
else
    echo -e "${RED}${BOLD}✗ XRAY STILL NOT RUNNING${NC}"
    echo ""
    echo -e "${YELLOW}Common Issues & Fixes:${NC}"
    echo ""
    
    # Check for common errors in logs
    LOGS=$(journalctl -u xray-skynet -n 50 --no-pager 2>/dev/null)
    
    if echo "$LOGS" | grep -qi "failed to parse"; then
        echo -e "  ${RED}→ Config Parse Error${NC}"
        echo -e "    Fix: cp /opt/skynet/config/xray.json /usr/local/etc/xray/config.json"
        echo -e "         systemctl restart xray-skynet"
    fi
    
    if echo "$LOGS" | grep -qi "address already in use"; then
        echo -e "  ${RED}→ Port Already in Use${NC}"
        echo -e "    Fix: netstat -tulpn | grep '10086\\|10087\\|10088'"
        echo -e "         kill -9 <PID>"
        echo -e "         systemctl restart xray-skynet"
    fi
    
    if echo "$LOGS" | grep -qi "permission denied"; then
        echo -e "  ${RED}→ Permission Denied${NC}"
        echo -e "    Fix: chmod +x /usr/local/bin/xray"
        echo -e "         chown root:root /usr/local/etc/xray/config.json"
        echo -e "         systemctl restart xray-skynet"
    fi
    
    if echo "$LOGS" | grep -qi "no such file"; then
        echo -e "  ${RED}→ Missing File${NC}"
        echo -e "    Fix: bash fix-xray.sh"
    fi
    
    echo ""
    echo -e "${YELLOW}Manual Troubleshooting:${NC}"
    echo ""
    echo -e "  1. View full logs:"
    echo -e "     ${CYAN}journalctl -u xray-skynet -n 100 --no-pager${NC}"
    echo ""
    echo -e "  2. Test config manually:"
    echo -e "     ${CYAN}xray -test -config /usr/local/etc/xray/config.json${NC}"
    echo ""
    echo -e "  3. Run Xray manually (for debugging):"
    echo -e "     ${CYAN}xray run -config /usr/local/etc/xray/config.json${NC}"
    echo -e "     (Press Ctrl+C to stop, then fix the error)"
    echo ""
    echo -e "  4. Re-create service:"
    echo -e "     ${CYAN}bash fix-xray.sh${NC}"
    echo ""
    echo -e "  5. Check full system:"
    echo -e "     ${CYAN}bash check.sh${NC}"
fi

echo ""
