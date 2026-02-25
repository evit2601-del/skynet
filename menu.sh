#!/bin/bash
# SKYNET menu runner (runtime: /opt/skynet)

source /opt/skynet/config/settings.conf 2>/dev/null || true

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'; DIM='\033[2m'

get_system_info() {
  IP_ADDR=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
  OS=$(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)
  RAM_TOTAL=$(free -m | awk 'NR==2{print $2}')
  RAM_USED=$(free -m | awk 'NR==2{print $3}')
  SWAP_TOTAL=$(free -m | awk 'NR==4{print $2}')
  SWAP_USED=$(free -m | awk 'NR==4{print $3}')
  UPTIME=$(uptime -p | sed 's/up //')
  DOMAIN=$(sqlite3 "$DATABASE" "SELECT value FROM settings WHERE key='domain'" 2>/dev/null)
  VERSION=$(sqlite3 "$DATABASE" "SELECT value FROM settings WHERE key='version'" 2>/dev/null || echo "1.0.0")

  [[ $(systemctl is-active xray-skynet 2>/dev/null) == "active" ]] && XRAY_STATUS="${GREEN}ON${NC}" || XRAY_STATUS="${RED}OFF${NC}"
  [[ $(systemctl is-active ssh 2>/dev/null) == "active" ]] && SSH_STATUS="${GREEN}ON${NC}" || SSH_STATUS="${RED}OFF${NC}"
}

show_motd() {
  get_system_info
  clear
  echo -e "${CYAN}${BOLD}┌─────────────────────────────────────────────────┐"
  echo -e "│                SKYNET TUNNELING                 │"
  echo -e "└─────────────────────────────────────────────────┘${NC}"
  echo -e "${YELLOW}OS:${NC} $OS"
  echo -e "${YELLOW}IP:${NC} $IP_ADDR"
  echo -e "${YELLOW}DOMAIN:${NC} $DOMAIN"
  echo -e "${YELLOW}UPTIME:${NC} $UPTIME"
  echo -e "${YELLOW}RAM:${NC} ${RAM_USED}MB / ${RAM_TOTAL}MB"
  echo -e "${YELLOW}SWAP:${NC} ${SWAP_USED}MB / ${SWAP_TOTAL}MB"
  echo -e "${YELLOW}XRAY:${NC} $XRAY_STATUS"
  echo -e "${YELLOW}SSH:${NC}  $SSH_STATUS"
  echo -e "${YELLOW}VERSION:${NC} $VERSION"
  echo ""
  echo -e "${DIM}Ketik ${BOLD}menu${NC}${DIM} untuk membuka panel${NC}"
}

main_menu() {
  clear
  echo -e "${CYAN}${BOLD}┌─────────────────────────────────────────────────┐"
  echo -e "│                SKYNET TUNNELING                 │"
  echo -e "└─────────────────────────────────────────────────┘${NC}"
  echo "1.) SSH"
  echo "2.) VMESS"
  echo "3.) VLESS"
  echo "4.) TROJAN"
  echo "6.) FEATURES"
  echo "x.) EXIT"
  echo ""
  read -rp "Pilihan: " c
  case "$c" in
    1) source /opt/skynet/core/ssh.sh; ssh_menu ;;
    2) source /opt/skynet/core/xray.sh; xray_menu vmess ;;
    3) source /opt/skynet/core/xray.sh; xray_menu vless ;;
    4) source /opt/skynet/core/xray.sh; xray_menu trojan ;;
    6) source /opt/skynet/core/features.sh; features_menu ;;
    x|X) exit 0 ;;
    *) sleep 1; main_menu ;;
  esac
}

case "${1:-}" in
  motd) show_motd ;;
  *) main_menu ;;
esac
