#!/bin/bash
# ============================================================
# SKYNET — MANAJEMEN SSH
# ============================================================

source /opt/skynet/config/settings.conf 2>/dev/null

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

# ── Fungsi: Buat user SSH
ssh_create() {
    clear
    echo -e "${CYAN}${BOLD}━━━━━━━━━━ CREATE SSH USER ━━━━━━━━━━${NC}"
    echo ""
    echo -ne " Username     : "; read -r USERNAME
    echo -ne " Password     : "; read -r -s PASSWORD; echo
    echo -ne " Masa aktif (hari): "; read -r DAYS
    echo -ne " Limit IP     : "; read -r IP_LIMIT
    echo -ne " Quota (GB, 0=unlimited): "; read -r QUOTA

    # Validasi
    if [[ -z "$USERNAME" ]] || [[ -z "$PASSWORD" ]] || [[ -z "$DAYS" ]]; then
        echo -e "${RED}Semua field wajib diisi!${NC}"; sleep 2; ssh_create; return
    fi
    if ! [[ "$DAYS" =~ ^[0-9]+$ ]] || ! [[ "${IP_LIMIT:-1}" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Masa aktif dan limit IP harus angka!${NC}"; sleep 2; ssh_create; return
    fi
    if id "$USERNAME" &>/dev/null; then
        echo -e "${RED}Username sudah ada!${NC}"; sleep 2; return
    fi

    IP_LIMIT=${IP_LIMIT:-1}
    QUOTA=${QUOTA:-0}
    EXPIRE_DATE=$(date -d "+${DAYS} days" +"%Y-%m-%d")

    # Buat user sistem
    useradd -M -s /bin/false -e "$EXPIRE_DATE" "$USERNAME"
    echo "$USERNAME:$PASSWORD" | chpasswd

    # Simpan ke database
    sqlite3 "$DATABASE" << EOF
INSERT INTO ssh_users (username, password, quota_gb, ip_limit, expired_at)
VALUES ('$USERNAME', '$PASSWORD', $QUOTA, $IP_LIMIT, '$EXPIRE_DATE');
EOF

    # Tampilkan info akun
    echo ""
    echo -e "${GREEN}✔ User SSH berhasil dibuat!${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e " Username : ${YELLOW}$USERNAME${NC}"
    echo -e " Password : ${YELLOW}$PASSWORD${NC}"
    echo -e " Expired  : ${YELLOW}$EXPIRE_DATE${NC}"
    echo -e " IP Limit : ${YELLOW}$IP_LIMIT${NC}"
    echo -e " Quota    : ${YELLOW}${QUOTA}GB${NC}"
    DOMAIN_VAL=$(sqlite3 "$DATABASE" "SELECT value FROM settings WHERE key='domain'")
    echo -e " Host     : ${YELLOW}$DOMAIN_VAL${NC}"
    echo -e " Port SSH : ${YELLOW}22, 2222${NC}"
    echo -e " Port Drop: ${YELLOW}442, 109${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    echo ""
    echo -ne " ${YELLOW}[Enter] Kembali...${NC}"; read -r
    ssh_menu
}

# ── Fungsi: Trial user SSH
ssh_trial() {
    clear
    echo -e "${CYAN}${BOLD}━━━━━━━━━━ TRIAL SSH USER ━━━━━━━━━━${NC}"
    echo ""
    echo -ne " Username : "; read -r USERNAME
    echo -ne " Password : "; read -r -s PASSWORD; echo

    if [[ -z "$USERNAME" ]] || [[ -z "$PASSWORD" ]]; then
        echo -e "${RED}Semua field wajib diisi!${NC}"; sleep 2; ssh_trial; return
    fi
    if id "$USERNAME" &>/dev/null; then
        echo -e "${RED}Username sudah ada!${NC}"; sleep 2; return
    fi

    EXPIRE_DATE=$(date -d "+1 day" +"%Y-%m-%d")
    useradd -M -s /bin/false -e "$EXPIRE_DATE" "$USERNAME"
    echo "$USERNAME:$PASSWORD" | chpasswd

    sqlite3 "$DATABASE" << EOF
INSERT INTO ssh_users (username, password, quota_gb, ip_limit, expired_at, is_trial)
VALUES ('$USERNAME', '$PASSWORD', 1, 1, '$EXPIRE_DATE', 1);
EOF

    echo -e "${GREEN}✔ Trial SSH user dibuat (1 hari, 1GB, 1 IP)${NC}"
    echo -e " Username: ${YELLOW}$USERNAME${NC} | Password: ${YELLOW}$PASSWORD${NC} | Expired: ${YELLOW}$EXPIRE_DATE${NC}"
    echo -ne " ${YELLOW}[Enter] Kembali...${NC}"; read -r
    ssh_menu
}

# ── Fungsi: Hapus user SSH
ssh_delete() {
    clear
    echo -e "${CYAN}${BOLD}━━━━━━━━━━ DELETE SSH USER ━━━━━━━━━━${NC}"
    echo ""
    echo -ne " Username yang akan dihapus: "; read -r USERNAME

    if [[ -z "$USERNAME" ]]; then
        echo -e "${RED}Username tidak boleh kosong!${NC}"; sleep 2; ssh_delete; return
    fi

    EXISTS=$(sqlite3 "$DATABASE" "SELECT COUNT(*) FROM ssh_users WHERE username='$USERNAME'")
    if [[ "$EXISTS" -eq 0 ]]; then
        echo -e "${RED}User tidak ditemukan!${NC}"; sleep 2; ssh_menu; return
    fi

    echo -ne " ${YELLOW}Konfirmasi hapus user $USERNAME? [y/N]:${NC} "; read -r CONFIRM
    if [[ "$CONFIRM" != "y" ]] && [[ "$CONFIRM" != "Y" ]]; then
        ssh_menu; return
    fi

    # Hapus user sistem
    userdel -f "$USERNAME" 2>/dev/null || true
    # Kill session aktif
    pkill -u "$USERNAME" 2>/dev/null || true

    # Hapus dari database
    sqlite3 "$DATABASE" "DELETE FROM ssh_users WHERE username='$USERNAME'"
    sqlite3 "$DATABASE" "DELETE FROM ip_tracking WHERE username='$USERNAME'"

    echo -e "${GREEN}✔ User $USERNAME berhasil dihapus!${NC}"
    sleep 2; ssh_menu
}

# ── Fungsi: Extend user SSH
ssh_extend() {
    clear
    echo -e "${CYAN}${BOLD}━━━━━━━━━━ EXTEND SSH USER ━━━━━━━━━━${NC}"
    echo ""
    echo -ne " Username : "; read -r USERNAME
    echo -ne " Tambah berapa hari: "; read -r DAYS

    if [[ -z "$USERNAME" ]] || ! [[ "$DAYS" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Input tidak valid!${NC}"; sleep 2; ssh_extend; return
    fi

    EXISTS=$(sqlite3 "$DATABASE" "SELECT COUNT(*) FROM ssh_users WHERE username='$USERNAME'")
    if [[ "$EXISTS" -eq 0 ]]; then
        echo -e "${RED}User tidak ditemukan!${NC}"; sleep 2; ssh_menu; return
    fi

    # Hitung tanggal baru
    CURRENT_EXP=$(sqlite3 "$DATABASE" "SELECT expired_at FROM ssh_users WHERE username='$USERNAME'")
    if [[ -z "$CURRENT_EXP" ]] || [[ "$CURRENT_EXP" < "$(date +%Y-%m-%d)" ]]; then
        NEW_EXP=$(date -d "+${DAYS} days" +"%Y-%m-%d")
    else
        NEW_EXP=$(date -d "$CURRENT_EXP +${DAYS} days" +"%Y-%m-%d")
    fi

    # Update di sistem
    chage -E "$NEW_EXP" "$USERNAME" 2>/dev/null || usermod -e "$NEW_EXP" "$USERNAME"

    # Update database
    sqlite3 "$DATABASE" "UPDATE ssh_users SET expired_at='$NEW_EXP', status='active' WHERE username='$USERNAME'"

    echo -e "${GREEN}✔ User $USERNAME diperpanjang hingga: ${YELLOW}$NEW_EXP${NC}"
    sleep 2; ssh_menu
}

# ── Fungsi: Ubah password
ssh_change_password() {
    clear
    echo -e "${CYAN}${BOLD}━━━━━━━━━━ CHANGE PASSWORD ━━━━━━━━━━${NC}"
    echo ""
    echo -ne " Username     : "; read -r USERNAME
    echo -ne " Password baru: "; read -r -s NEW_PASS; echo

    if [[ -z "$USERNAME" ]] || [[ -z "$NEW_PASS" ]]; then
        echo -e "${RED}Input tidak valid!${NC}"; sleep 2; ssh_change_password; return
    fi

    if ! id "$USERNAME" &>/dev/null; then
        echo -e "${RED}User tidak ditemukan!${NC}"; sleep 2; ssh_menu; return
    fi

    echo "$USERNAME:$NEW_PASS" | chpasswd
    sqlite3 "$DATABASE" "UPDATE ssh_users SET password='$NEW_PASS' WHERE username='$USERNAME'"

    echo -e "${GREEN}✔ Password user $USERNAME berhasil diubah!${NC}"
    sleep 2; ssh_menu
}

# ── Fungsi: Cek user SSH
ssh_check() {
    clear
    echo -e "${CYAN}${BOLD}━━━━━━━━━━ CHECK SSH USER ━━━━━━━━━━${NC}"
    echo ""
    echo -ne " Username: "; read -r USERNAME

    USER_DATA=$(sqlite3 "$DATABASE" \
        "SELECT username, quota_gb, quota_used, ip_limit, expired_at, status, is_trial \
         FROM ssh_users WHERE username='$USERNAME'")

    if [[ -z "$USER_DATA" ]]; then
        echo -e "${RED}User tidak ditemukan!${NC}"
    else
        IFS='|' read -r UN QUOTA QUOTA_USED IP_LIM EXP STATUS TRIAL <<< "$USER_DATA"
        ACTIVE_IP=$(sqlite3 "$DATABASE" \
            "SELECT COUNT(*) FROM ip_tracking WHERE username='$USERNAME' AND is_active=1")
        echo ""
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e " Username  : ${YELLOW}$UN${NC}"
        echo -e " Status    : ${YELLOW}$STATUS${NC}"
        echo -e " Trial     : ${YELLOW}$([ "$TRIAL" -eq 1 ] && echo 'Ya' || echo 'Tidak')${NC}"
        echo -e " Quota     : ${YELLOW}${QUOTA_USED}GB / ${QUOTA}GB${NC}"
        echo -e " IP Limit  : ${YELLOW}$ACTIVE_IP / $IP_LIM${NC}"
        echo -e " Expired   : ${YELLOW}$EXP${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    fi

    echo -ne " ${YELLOW}[Enter] Kembali...${NC}"; read -r
    ssh_menu
}

# ── Fungsi: List semua user SSH
ssh_list() {
    clear
    echo -e "${CYAN}${BOLD}━━━━━━━━━━ LIST SSH USERS ━━━━━━━━━━${NC}"
    echo ""
    printf " %-15s %-12s %-12s %-8s %-8s\n" "Username" "Expired" "Status" "IP/Lim" "Quota"
    echo -e " ${CYAN}─────────────────────────────────────────────────${NC}"

    sqlite3 "$DATABASE" \
        "SELECT username, expired_at, status, ip_limit, quota_gb FROM ssh_users ORDER BY username" | \
    while IFS='|' read -r UN EXP STAT IPN QUOTA; do
        ACTIVE_IP=$(sqlite3 "$DATABASE" \
            "SELECT COUNT(*) FROM ip_tracking WHERE username='$UN' AND is_active=1")
        printf " %-15s %-12s %-12s %-8s %-8s\n" \
            "$UN" "$EXP" "$STAT" "${ACTIVE_IP}/${IPN}" "${QUOTA}GB"
    done

    TOTAL=$(sqlite3 "$DATABASE" "SELECT COUNT(*) FROM ssh_users")
    echo -e " ${CYAN}─────────────────────────────────────────────────${NC}"
    echo -e " Total: ${YELLOW}$TOTAL${NC} user"
    echo -ne " ${YELLOW}[Enter] Kembali...${NC}"; read -r
    ssh_menu
}

# ── Fungsi: Lock/Unlock user
ssh_lock() {
    local ACTION=$1
    clear
    echo -e "${CYAN}${BOLD}━━━━━━━━━━ ${ACTION^^} SSH USER ━━━━━━━━━━${NC}"
    echo ""
    echo -ne " Username: "; read -r USERNAME

    EXISTS=$(sqlite3 "$DATABASE" "SELECT COUNT(*) FROM ssh_users WHERE username='$USERNAME'")
    if [[ "$EXISTS" -eq 0 ]]; then
        echo -e "${RED}User tidak ditemukan!${NC}"; sleep 2; ssh_menu; return
    fi

    if [[ "$ACTION" == "lock" ]]; then
        passwd -l "$USERNAME" 2>/dev/null || true
        sqlite3 "$DATABASE" "UPDATE ssh_users SET status='locked' WHERE username='$USERNAME'"
        pkill -u "$USERNAME" 2>/dev/null || true
        echo -e "${GREEN}✔ User $USERNAME berhasil di-lock!${NC}"
    else
        passwd -u "$USERNAME" 2>/dev/null || true
        sqlite3 "$DATABASE" "UPDATE ssh_users SET status='active' WHERE username='$USERNAME'"
        echo -e "${GREEN}✔ User $USERNAME berhasil di-unlock!${NC}"
    fi

    sleep 2; ssh_menu
}

# ── Fungsi: Edit limit IP
ssh_edit_ip_limit() {
    clear
    echo -e "${CYAN}${BOLD}━━━━━━━━━━ EDIT IP LIMIT ━━━━━━━━━━${NC}"
    echo ""
    echo -e " ${GREEN}1.)${NC} Edit limit IP per user"
    echo -e " ${GREEN}2.)${NC} Edit limit IP semua user"
    echo -e " ${RED}x.)${NC} Kembali"
    echo ""
    echo -ne " Pilihan: "; read -r OPT

    case "$OPT" in
        1)
            echo -ne " Username: "; read -r USERNAME
            echo -ne " Limit IP baru: "; read -r NEW_LIMIT
            if ! [[ "$NEW_LIMIT" =~ ^[0-9]+$ ]]; then
                echo -e "${RED}Limit harus angka!${NC}"; sleep 2; ssh_edit_ip_limit; return
            fi
            sqlite3 "$DATABASE" "UPDATE ssh_users SET ip_limit=$NEW_LIMIT WHERE username='$USERNAME'"
            echo -e "${GREEN}✔ Limit IP user $USERNAME diset ke $NEW_LIMIT${NC}"
            ;;
        2)
            echo -ne " Limit IP baru (untuk semua user): "; read -r NEW_LIMIT
            if ! [[ "$NEW_LIMIT" =~ ^[0-9]+$ ]]; then
                echo -e "${RED}Limit harus angka!${NC}"; sleep 2; ssh_edit_ip_limit; return
            fi
            sqlite3 "$DATABASE" "UPDATE ssh_users SET ip_limit=$NEW_LIMIT"
            echo -e "${GREEN}✔ Limit IP semua user diset ke $NEW_LIMIT${NC}"
            ;;
        x|X) ssh_menu; return ;;
    esac
    sleep 2; ssh_edit_ip_limit
}

# ── Fungsi: Monitor login aktif
ssh_monitor_login() {
    clear
    echo -e "${CYAN}${BOLD}━━━━━━━━━━ MONITOR LOGIN AKTIF ━━━━━━━━━━${NC}"
    echo ""
    echo -e " ${YELLOW}Session SSH aktif saat ini:${NC}"
    echo ""
    who | awk '{print " " NR". User: "$1" | TTY: "$2" | Dari: "$5" | Waktu: "$3" "$4}'
    echo ""
    echo -e " ${YELLOW}IP aktif per user (database):${NC}"
    sqlite3 "$DATABASE" \
        "SELECT username, ip_address, login_at FROM ip_tracking WHERE is_active=1 ORDER BY username" | \
    while IFS='|' read -r UN IP_ADDR LOGIN_AT; do
        echo -e "  ${GREEN}$UN${NC} → $IP_ADDR (login: $LOGIN_AT)"
    done
    echo ""
    echo -ne " ${YELLOW}[Enter] Kembali...${NC}"; read -r
    ssh_menu
}

# ── Menu SSH
ssh_menu() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "┌─────────────────────────────────────────────────────┐"
    echo "│                   MENU SSH                         │"
    echo "└─────────────────────────────────────────────────────┘"
    echo -e "${NC}"
    echo -e " ${GREEN}1.)${NC}  Create User"
    echo -e " ${GREEN}2.)${NC}  Trial User"
    echo -e " ${GREEN}3.)${NC}  Delete User"
    echo -e " ${GREEN}4.)${NC}  Extend User"
    echo -e " ${GREEN}5.)${NC}  Change Password"
    echo -e " ${GREEN}6.)${NC}  Check User"
    echo -e " ${GREEN}7.)${NC}  List User"
    echo -e " ${GREEN}8.)${NC}  Lock User"
    echo -e " ${GREEN}9.)${NC}  Unlock User"
    echo -e " ${GREEN}10.)${NC} Edit Limit IP"
    echo -e " ${GREEN}11.)${NC} Monitor Login Aktif"
    echo -e " ${RED}x.)${NC}  Kembali"
    echo ""
    echo -ne " ${YELLOW}Pilihan [1-11/x]:${NC} "; read -r choice

    case "$choice" in
        1)  ssh_create ;;
        2)  ssh_trial ;;
        3)  ssh_delete ;;
        4)  ssh_extend ;;
        5)  ssh_change_password ;;
        6)  ssh_check ;;
        7)  ssh_list ;;
        8)  ssh_lock "lock" ;;
        9)  ssh_lock "unlock" ;;
        10) ssh_edit_ip_limit ;;
        11) ssh_monitor_login ;;
        x|X) source /opt/skynet/menu.sh; show_main_menu ;;
        *) echo -e "${RED}Pilihan tidak valid!${NC}"; sleep 1; ssh_menu ;;
    esac
}
