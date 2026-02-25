#!/bin/bash
# ============================================================
# SKYNET TUNNELING — MENU UTAMA
# ============================================================

source /opt/skynet/config/settings.conf 2>/dev/null || true

# ── Warna
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ── Fungsi info sistem
get_system_info() {
    IP_ADDR=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    OS=$(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)
    RAM_TOTAL=$(free -m | awk 'NR==2{print $2}')
    RAM_USED=$(free -m | awk 'NR==2{print $3}')
    RAM_FREE=$(free -m | awk 'NR==2{print $4}')
    SWAP_TOTAL=$(free -m | awk 'NR==4{print $2}')
    SWAP_USED=$(free -m | awk 'NR==4{print $3}')
    UPTIME=$(uptime -p | sed 's/up //')
    DOMAIN=$(sqlite3 "$DATABASE" "SELECT value FROM settings WHERE key='domain'" 2>/dev/null)
    BRAND=$(sqlite3 "$DATABASE" "SELECT value FROM settings WHERE key='brand_name'" 2>/dev/null)
    CLIENT=$(sqlite3 "$DATABASE" "SELECT value FROM settings WHERE key='client_name'" 2>/dev/null)
    SCRIPT_EXP=$(sqlite3 "$DATABASE" "SELECT value FROM settings WHERE key='script_expire'" 2>/dev/null)
    VERSION=$(sqlite3 "$DATABASE" "SELECT value FROM settings WHERE key='version'" 2>/dev/null)

    # ISP & City
    CITY=$(curl -s "https://ipinfo.io/city" 2>/dev/null || echo "Unknown")
    ISP=$(curl -s "https://ipinfo.io/org" 2>/dev/null || echo "Unknown")

    # Traffic dari vnstat
    RX_TODAY=$(vnstat --oneline 2>/dev/null | awk -F';' '{print $4}' || echo "N/A")
    TX_TODAY=$(vnstat --oneline 2>/dev/null | awk -F';' '{print $5}' || echo "N/A")
    RX_MONTH=$(vnstat --oneline 2>/dev/null | awk -F';' '{print $9}' || echo "N/A")
    TX_MONTH=$(vnstat --oneline 2>/dev/null | awk -F';' '{print $10}' || echo "N/A")

    # Total accounts
    SSH_COUNT=$(sqlite3 "$DATABASE" "SELECT COUNT(*) FROM ssh_users WHERE status='active'" 2>/dev/null || echo "0")
    VMESS_COUNT=$(sqlite3 "$DATABASE" "SELECT COUNT(*) FROM xray_users WHERE protocol='vmess' AND status='active'" 2>/dev/null || echo "0")
    VLESS_COUNT=$(sqlite3 "$DATABASE" "SELECT COUNT(*) FROM xray_users WHERE protocol='vless' AND status='active'" 2>/dev/null || echo "0")
    TROJAN_COUNT=$(sqlite3 "$DATABASE" "SELECT COUNT(*) FROM xray_users WHERE protocol='trojan' AND status='active'" 2>/dev/null || echo "0")

    # Status services
    XRAY_STATUS=$(systemctl is-active xray-skynet 2>/dev/null | grep -c "^active$" && echo "ON" || echo "OFF")
    SSH_STATUS=$(systemctl is-active ssh 2>/dev/null | grep -c "^active$" && echo "ON" || echo "OFF")
    [[ $(systemctl is-active xray-skynet 2>/dev/null) == "active" ]] && XRAY_STATUS="${GREEN}ON${NC}" || XRAY_STATUS="${RED}OFF${NC}"
    [[ $(systemctl is-active ssh 2>/dev/null) == "active" ]] && SSH_STATUS="${GREEN}ON${NC}" || SSH_STATUS="${RED}OFF${NC}"
    [[ $(systemctl is-active skynet-nkn 2>/dev/null) == "active" ]] && NKN_STATUS="${GREEN}ON${NC}" || NKN_STATUS="${RED}OFF${NC}"
}

# ── Tampilan MOTD / Dashboard
show_motd() {
    get_system_info
    clear
    echo -e "${CYAN}${BOLD}"
    echo "┌─────────────────────────────────────────────────────┐"
    printf "│%${#BRAND}s%-$(( 53 - ${#BRAND} ))s│\n" "" "         ${BRAND}           "
    echo "└─────────────────────────────────────────────────────┘"
    echo -e "${NC}"

    echo -e " ${CYAN}SYSTEM INFORMATION${NC}"
    echo -e " ${DIM}─────────────────────────────────────────────────────${NC}"
    echo -e " ${YELLOW}OS        :${NC} $OS"
    echo -e " ${YELLOW}IP        :${NC} $IP_ADDR"
    echo -e " ${YELLOW}Domain    :${NC} $DOMAIN"
    echo -e " ${YELLOW}City      :${NC} $CITY"
    echo -e " ${YELLOW}ISP       :${NC} $ISP"
    echo -e " ${YELLOW}Uptime    :${NC} $UPTIME"
    echo -e " ${YELLOW}RAM       :${NC} ${RAM_USED}MB / ${RAM_TOTAL}MB (Free: ${RAM_FREE}MB)"
    echo -e " ${YELLOW}SWAP      :${NC} ${SWAP_USED}MB / ${SWAP_TOTAL}MB"

    echo ""
    echo -e " ${CYAN}TRAFFIC INFORMATION${NC}"
    echo -e " ${DIM}─────────────────────────────────────────────────────${NC}"
    echo -e " ${YELLOW}Daily     :${NC} RX: $RX_TODAY | TX: $TX_TODAY"
    echo -e " ${YELLOW}Monthly   :${NC} RX: $RX_MONTH | TX: $TX_MONTH"

    echo ""
    echo -e " ${CYAN}SERVICE STATUS${NC}"
    echo -e " ${DIM}─────────────────────────────────────────────────────${NC}"
    echo -e " ${YELLOW}Xray      :${NC} $XRAY_STATUS"
    echo -e " ${YELLOW}SSH       :${NC} $SSH_STATUS"
    echo -e " ${YELLOW}NKN Tunnel:${NC} $NKN_STATUS"

    echo ""
    echo -e " ${CYAN}ACCOUNT SUMMARY${NC}"
    echo -e " ${DIM}─────────────────────────────────────────────────────${NC}"
    echo -e " ${YELLOW}SSH       :${NC} $SSH_COUNT akun aktif"
    echo -e " ${YELLOW}VMess     :${NC} $VMESS_COUNT akun aktif"
    echo -e " ${YELLOW}VLESS     :${NC} $VLESS_COUNT akun aktif"
    echo -e " ${YELLOW}Trojan    :${NC} $TROJAN_COUNT akun aktif"

    echo ""
    echo -e " ${CYAN}SCRIPT INFO${NC}"
    echo -e " ${DIM}─────────────────────────────────────────────────────${NC}"
    echo -e " ${YELLOW}Version   :${NC} $VERSION"
    echo -e " ${YELLOW}Client    :${NC} $CLIENT"
    echo -e " ${YELLOW}Exp Script:${NC} $SCRIPT_EXP"

    echo ""
    echo -e " ${DIM}Ketik ${BOLD}menu${NC}${DIM} untuk membuka panel manajemen${NC}"
    echo ""
}

# ── Menu Utama
show_main_menu() {
    clear
    BRAND=$(sqlite3 "$DATABASE" "SELECT value FROM settings WHERE key='brand_name'" 2>/dev/null || echo "SKYNET TUNNELING")
    echo -e "${CYAN}${BOLD}"
    echo "┌─────────────────────────────────────────────────────┐"
    echo "│                                                     │"
    printf "│%*s%*s│\n" $(( (53 + ${#BRAND}) / 2 )) "$BRAND" $(( (53 - ${#BRAND}) / 2 )) ""
    echo "│                   PANEL UTAMA                      │"
    echo "└─────────────────────────────────────────────────────┘"
    echo -e "${NC}"
    echo -e " ${GREEN}1.)${NC}  SSH"
    echo -e " ${GREEN}2.)${NC}  VMESS"
    echo -e " ${GREEN}3.)${NC}  VLESS"
    echo -e " ${GREEN}4.)${NC}  TROJAN"
    echo -e " ${GREEN}5.)${NC}  SETUP BOT"
    echo -e " ${GREEN}6.)${NC}  FEATURES"
    echo -e " ${GREEN}7.)${NC}  SET REDUCE/TIME"
    echo -e " ${GREEN}8.)${NC}  SET BRAND NAME"
    echo -e " ${GREEN}9.)${NC}  CHECK SERVICES"
    echo -e " ${RED}x.)${NC}  EXIT"
    echo ""
    echo -ne " ${YELLOW}Pilihan [1-9/x]:${NC} "
    read -r choice

    case "$choice" in
        1) source /opt/skynet/core/ssh.sh; ssh_menu ;;
        2) source /opt/skynet/core/xray.sh; xray_menu "vmess" ;;
        3) source /opt/skynet/core/xray.sh; xray_menu "vless" ;;
        4) source /opt/skynet/core/xray.sh; xray_menu "trojan" ;;
        5) setup_bot_menu ;;
        6) source /opt/skynet/core/features.sh; features_menu ;;
        7) set_reduce_time_menu ;;
        8) set_brand_name ;;
        9) check_services_menu ;;
        x|X|q|Q) clear; exit 0 ;;
        *) echo -e "${RED}Pilihan tidak valid!${NC}"; sleep 1; show_main_menu ;;
    esac
}

# ── Setup Bot Menu
setup_bot_menu() {
    clear
    echo -e "${CYAN}${BOLD}━━━━━━━━━━ SETUP TELEGRAM BOT ━━━━━━━━━━${NC}"
    echo ""
    echo -ne " ${YELLOW}Masukkan Bot Token:${NC} "
    read -r BOT_TOKEN
    echo -ne " ${YELLOW}Masukkan Admin Telegram ID:${NC} "
    read -r ADMIN_ID

    if [[ -z "$BOT_TOKEN" ]] || [[ -z "$ADMIN_ID" ]]; then
        echo -e "${RED}Token dan ID tidak boleh kosong!${NC}"
        sleep 2; setup_bot_menu; return
    fi

    # Update database
    sqlite3 "$DATABASE" "UPDATE settings SET value='$BOT_TOKEN' WHERE key='bot_token'"
    sqlite3 "$DATABASE" "UPDATE settings SET value='$ADMIN_ID' WHERE key='admin_telegram_id'"

    # Update settings.conf
    sed -i "s/^BOT_TOKEN=.*/BOT_TOKEN=$BOT_TOKEN/" /opt/skynet/config/settings.conf
    sed -i "s/^ADMIN_TELEGRAM_ID=.*/ADMIN_TELEGRAM_ID=$ADMIN_ID/" /opt/skynet/config/settings.conf
    echo "BOT_TOKEN=$BOT_TOKEN" >> /opt/skynet/config/settings.conf
    echo "ADMIN_TELEGRAM_ID=$ADMIN_ID" >> /opt/skynet/config/settings.conf

    systemctl restart skynet-bot
    echo -e "${GREEN}Bot berhasil dikonfigurasi dan distart!${NC}"
    sleep 2; show_main_menu
}

# ── Set Brand Name
set_brand_name() {
    clear
    echo -e "${CYAN}${BOLD}━━━━━━━━━━ SET BRAND NAME ━━━━━━━━━━${NC}"
    echo ""
    CURRENT=$(sqlite3 "$DATABASE" "SELECT value FROM settings WHERE key='brand_name'")
    echo -e " Brand saat ini: ${YELLOW}$CURRENT${NC}"
    echo -ne " ${YELLOW}Brand baru:${NC} "
    read -r NEW_BRAND

    if [[ -z "$NEW_BRAND" ]]; then
        echo -e "${RED}Brand tidak boleh kosong!${NC}"
        sleep 2; set_brand_name; return
    fi

    sqlite3 "$DATABASE" "UPDATE settings SET value='$NEW_BRAND' WHERE key='brand_name'"
    echo -e "${GREEN}Brand berhasil diubah ke: $NEW_BRAND${NC}"
    sleep 2; show_main_menu
}

# ── Check Services
check_services_menu() {
    clear
    echo -e "${CYAN}${BOLD}━━━━━━━━━━ STATUS SERVICES ━━━━━━━━━━${NC}"
    echo ""
    services=("ssh" "dropbear" "nginx" "xray-skynet" "fail2ban" "stunnel4" "skynet-bot" "skynet-api" "skynet-nkn")
    labels=("SSH" "Dropbear" "Nginx" "Xray" "Fail2Ban" "Stunnel" "Bot Telegram" "REST API" "NKN Tunnel")

    for i in "${!services[@]}"; do
        STATUS=$(systemctl is-active "${services[$i]}" 2>/dev/null)
        if [[ "$STATUS" == "active" ]]; then
            echo -e " ${labels[$i]}\t: ${GREEN}● RUNNING${NC}"
        else
            echo -e " ${labels[$i]}\t: ${RED}● STOPPED${NC}"
        fi
    done

    echo ""
    echo -ne " ${YELLOW}[Enter] Kembali...${NC}"
    read -r
    show_main_menu
}

# ── Set Reduce/Time
set_reduce_time_menu() {
    clear
    echo -e "${CYAN}${BOLD}━━━━━━━━━━ SET REDUCE/TIME ━━━━━━━━━━${NC}"
    echo ""
    echo -e " ${GREEN}1.)${NC} Set Auto Reboot"
    echo -e " ${GREEN}2.)${NC} Disable Auto Reboot"
    echo -e " ${GREEN}3.)${NC} Set Script Expiry"
    echo -e " ${RED}x.)${NC} Kembali"
    echo ""
    echo -ne " ${YELLOW}Pilihan:${NC} "
    read -r opt

    case "$opt" in
        1)
            echo -ne " Jam reboot (0-23): "
            read -r HOUR
            echo -ne " Hari (0=Minggu, 1-6=Senin-Sabtu, *=setiap hari): "
            read -r DAY
            (crontab -l 2>/dev/null | grep -v "skynet-reboot"; \
             echo "$HOUR 0 * * $DAY /sbin/reboot # skynet-reboot") | crontab -
            echo -e "${GREEN}Auto reboot diset ke jam $HOUR hari $DAY${NC}"
            ;;
        2)
            crontab -l 2>/dev/null | grep -v "skynet-reboot" | crontab -
            echo -e "${GREEN}Auto reboot dinonaktifkan!${NC}"
            ;;
        3)
            echo -ne " Tanggal expiry (YYYY-MM-DD): "
            read -r EXP_DATE
            sqlite3 "$DATABASE" "UPDATE settings SET value='$EXP_DATE' WHERE key='script_expire'"
            echo -e "${GREEN}Script expiry diset ke: $EXP_DATE${NC}"
            ;;
        x|X) show_main_menu; return ;;
    esac
    sleep 2; set_reduce_time_menu
}

# ── Entry point
case "${1:-}" in
    motd)   show_motd ;;
    *)      show_main_menu ;;
esac
