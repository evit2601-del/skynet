#!/bin/bash
# SKYNET — SSH Management
source /opt/skynet/config/settings.conf 2>/dev/null

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

ssh_create() {
  clear
  echo -e "${CYAN}${BOLD}CREATE SSH USER${NC}"
  read -rp "Username: " USERNAME
  read -rsp "Password: " PASSWORD; echo
  read -rp "Masa aktif (hari): " DAYS
  read -rp "Limit IP: " IP_LIMIT

  [[ -z "${USERNAME:-}" || -z "${PASSWORD:-}" || -z "${DAYS:-}" ]] && echo "Input wajib." && sleep 1 && return
  # ✅ minimal 3
  if [[ ${#PASSWORD} -lt 3 ]]; then
    echo -e "${RED}Password minimal 3 karakter!${NC}"
    sleep 2
    return
  fi
  [[ ! "$DAYS" =~ ^[0-9]+$ ]] && echo "Hari harus angka" && sleep 1 && return
  IP_LIMIT=${IP_LIMIT:-1}
  [[ ! "$IP_LIMIT" =~ ^[0-9]+$ ]] && IP_LIMIT=1

  EXP=$(date -d "+$DAYS days" +"%Y-%m-%d")
  useradd -M -s /bin/false -e "$EXP" "$USERNAME"
  echo "$USERNAME:$PASSWORD" | chpasswd

  sqlite3 "$DATABASE" "INSERT INTO ssh_users(username,password,ip_limit,expired_at) VALUES('$USERNAME','$PASSWORD',$IP_LIMIT,'$EXP');"
  echo -e "${GREEN}OK created: $USERNAME exp $EXP${NC}"
  read -rp "Enter..."
}

ssh_change_password() {
  clear
  echo -e "${CYAN}${BOLD}CHANGE PASSWORD SSH${NC}"
  read -rp "Username: " USERNAME
  read -rsp "Password baru: " NEW_PASS; echo

  # ✅ minimal 3
  if [[ ${#NEW_PASS} -lt 3 ]]; then
    echo -e "${RED}Password minimal 3 karakter!${NC}"
    sleep 2
    return
  fi

  echo "$USERNAME:$NEW_PASS" | chpasswd
  sqlite3 "$DATABASE" "UPDATE ssh_users SET password='$NEW_PASS' WHERE username='$USERNAME';"
  echo -e "${GREEN}OK${NC}"
  read -rp "Enter..."
}

ssh_menu() {
  while true; do
    clear
    echo "1) Create"
    echo "2) Change Password"
    echo "x) Back"
    read -rp "Pilih: " c
    case "$c" in
      1) ssh_create ;;
      2) ssh_change_password ;;
      x|X) return ;;
    esac
  done
}
