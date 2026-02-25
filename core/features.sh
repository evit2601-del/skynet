#!/bin/bash
# SKYNET — FEATURES (full menu simplified + MENU 23 lock duration)
source /opt/skynet/config/settings.conf 2>/dev/null

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'; DIM='\033[2m'

parse_duration_to_seconds() {
  local INPUT="$1"
  if [[ ! "$INPUT" =~ ^[0-9]+[smhd]$ ]]; then
    echo "INVALID"; return
  fi
  local NUM="${INPUT%?}"
  local SUF="${INPUT: -1}"
  case "$SUF" in
    s) echo "$NUM" ;;
    m) echo $((NUM*60)) ;;
    h) echo $((NUM*3600)) ;;
    d) echo $((NUM*86400)) ;;
  esac
}

feature_menu23_set_lock_duration() {
  clear
  echo -e "${CYAN}${BOLD}"
  echo "────────────────────────────────────────────────────────────"
  echo "                 MENU 23 - SET DURASI LOCKED                "
  echo "────────────────────────────────────────────────────────────"
  echo -e "${NC}"

  CUR=$(sqlite3 "$DATABASE" "SELECT value FROM settings WHERE key='lock_duration_seconds'" 2>/dev/null)
  CUR=${CUR:-3600}

  echo -e " ${YELLOW}Durasi lock saat ini:${NC} ${GREEN}${CUR} detik${NC}"
  echo ""
  echo -e " ${DIM}Format input: 30s | 1m | 2h | 1d${NC}"
  echo -ne " ${YELLOW}Masukkan durasi (contoh 1m):${NC} "
  read -r DSTR

  SEC=$(parse_duration_to_seconds "$DSTR")
  if [[ "$SEC" == "INVALID" ]]; then
    echo -e "${RED}Format salah! contoh: 1m / 1h / 1d${NC}"
    sleep 2
    return
  fi

  if [[ "$SEC" -lt 10 ]] || [[ "$SEC" -gt 604800 ]]; then
    echo -e "${RED}Durasi harus 10 detik s/d 7 hari (7d).${NC}"
    sleep 2
    return
  fi

  echo -ne " ${YELLOW}Konfirmasi set durasi lock=${DSTR}? [y/N]:${NC} "
  read -r CONF
  if [[ "$CONF" != "y" && "$CONF" != "Y" ]]; then
    echo -e "${YELLOW}Dibatalkan.${NC}"
    sleep 1
    return
  fi

  sqlite3 "$DATABASE" "INSERT OR REPLACE INTO settings(key,value) VALUES('lock_duration_seconds','$SEC');"
  systemctl restart skynet-monitor 2>/dev/null || true

  echo -e "${GREEN}✔ Durasi lock diset ke ${DSTR} (${SEC} detik).${NC}"
  sleep 2
}

features_menu() {
  while true; do
    clear
    echo -e "${CYAN}${BOLD}"
    echo "────────────────────────────────────────────────────────────"
    echo "                     FEATURES"
    echo "────────────────────────────────────────────────────────────"
    echo -e "${NC}"
    echo "23.) Set Durasi Locked (contoh: 1m/1h/1d)"
    echo "22.) Back to Menu"
    echo "x.) Exit"
    echo ""
    read -rp "Pilihan: " c
    case "$c" in
      23) feature_menu23_set_lock_duration ;;
      22) main_menu; return ;;
      x|X) exit 0 ;;
      *) sleep 1 ;;
    esac
  done
}
