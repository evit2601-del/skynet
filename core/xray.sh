#!/bin/bash
# ============================================================
# SKYNET — MANAJEMEN XRAY (VMess / VLESS / Trojan)
# ============================================================

source /opt/skynet/config/settings.conf 2>/dev/null

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

XRAY_CONFIG="/usr/local/etc/xray/config.json"

# ── Generate UUID
generate_uuid() {
    cat /proc/sys/kernel/random/uuid
}

# ── Reload Xray
reload_xray() {
    systemctl restart xray-skynet
    sleep 1
    if systemctl is-active xray-skynet &>/dev/null; then
        echo -e "${GREEN}✔ Xray berhasil di-reload${NC}"
    else
        echo -e "${RED}✗ Xray gagal di-reload! Cek log: journalctl -u xray-skynet${NC}"
    fi
}

# ── Add client ke xray config
add_xray_client() {
    local PROTOCOL=$1
    local USERNAME=$2
    local UUID=$3
    local IP_LIMIT=$4

    # Tag berdasarkan protokol
    local TAG
    case "$PROTOCOL" in
        vmess) TAG="vmess-ws" ;;
        vless) TAG="vless-ws" ;;
        trojan) TAG="trojan-ws" ;;
    esac

    # Build client JSON
    if [[ "$PROTOCOL" == "trojan" ]]; then
        CLIENT_JSON="{\"password\":\"$UUID\",\"email\":\"$USERNAME\",\"level\":0}"
    elif [[ "$PROTOCOL" == "vless" ]]; then
        CLIENT_JSON="{\"id\":\"$UUID\",\"email\":\"$USERNAME\",\"level\":0}"
    else
        CLIENT_JSON="{\"id\":\"$UUID\",\"alterId\":0,\"email\":\"$USERNAME\",\"level\":0,\"security\":\"auto\"}"
    fi

    # Gunakan Python untuk modifikasi JSON config
    python3 << EOF
import json

config_path = "$XRAY_CONFIG"
with open(config_path, 'r') as f:
    config = json.load(f)

client = $CLIENT_JSON

for inbound in config['inbounds']:
    if inbound['tag'] == '$TAG':
        clients = inbound['settings'].get('clients', [])
        # Cek duplikat
        for c in clients:
            if c.get('id') == '$UUID' or c.get('password') == '$UUID':
                print("DUPLICATE")
                exit(1)
        clients.append(client)
        inbound['settings']['clients'] = clients
        break

with open(config_path, 'w') as f:
    json.dump(config, f, indent=2)

print("OK")
EOF
}

# ── Remove client dari xray config
remove_xray_client() {
    local PROTOCOL=$1
    local UUID=$2

    local TAG
    case "$PROTOCOL" in
        vmess) TAG="vmess-ws" ;;
        vless) TAG="vless-ws" ;;
        trojan) TAG="trojan-ws" ;;
    esac

    python3 << EOF
import json

with open("$XRAY_CONFIG", 'r') as f:
    config = json.load(f)

for inbound in config['inbounds']:
    if inbound['tag'] == '$TAG':
        clients = inbound['settings'].get('clients', [])
        inbound['settings']['clients'] = [
            c for c in clients
            if c.get('id') != '$UUID' and c.get('password') != '$UUID'
        ]
        break

with open("$XRAY_CONFIG", 'w') as f:
    json.dump(config, f, indent=2)
print("OK")
EOF
}

# ── Generate WS Path acak
gen_ws_path() {
    local PROTO=$1
    echo "/${PROTO}-$(cat /dev/urandom | tr -dc 'a-z0-9' | head -c 8)"
}

# ── Generate link Xray
generate_link() {
    local PROTO=$1
    local UUID=$2
    local USERNAME=$3
    local TLS=$4
    local WS_PATH=$5

    DOMAIN=$(sqlite3 "$DATABASE" "SELECT value FROM settings WHERE key='domain'")
    SCHEME="https"; PORT="443"
    [[ "$TLS" == "0" ]] && SCHEME="http" && PORT="80"

    case "$PROTO" in
        vmess)
            local VMESS_JSON
            VMESS_JSON=$(python3 -c "
import json, base64
d = {
    'v': '2', 'ps': '$USERNAME', 'add': '$DOMAIN',
    'port': '$PORT', 'id': '$UUID', 'aid': 0,
    'net': 'ws', 'type': 'none', 'host': '$DOMAIN',
    'path': '$WS_PATH', 'tls': '$( [ "$TLS" = "1" ] && echo tls || echo none )'
}
print(base64.b64encode(json.dumps(d).encode()).decode())")
            echo "vmess://$VMESS_JSON"
            ;;
        vless)
            echo "vless://$UUID@$DOMAIN:$PORT?encryption=none&security=$( [ "$TLS" = "1" ] && echo tls || echo none )&type=ws&host=$DOMAIN&path=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$WS_PATH'))")#$USERNAME"
            ;;
        trojan)
            echo "trojan://$UUID@$DOMAIN:$PORT?security=$( [ "$TLS" = "1" ] && echo tls || echo none )&type=ws&host=$DOMAIN&path=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$WS_PATH'))")#$USERNAME"
            ;;
    esac
}

# ── Buat akun Xray
xray_create() {
    local PROTO=$1
    clear
    echo -e "${CYAN}${BOLD}━━━━━━━━━━ CREATE ${PROTO^^} ACCOUNT ━━━━━━━━━━${NC}"
    echo ""
    echo -ne " Username       : "; read -r USERNAME
    echo -ne " UUID (kosong=auto): "; read -r CUSTOM_UUID
    echo -ne " Masa aktif (hari): "; read -r DAYS
    echo -ne " Limit IP       : "; read -r IP_LIMIT
    echo -ne " Quota (GB, 0=unlimited): "; read -r QUOTA
    echo -ne " TLS? (1=ya, 0=tidak): "; read -r TLS_ENABLED

    # Validasi
    if [[ -z "$USERNAME" ]] || ! [[ "$DAYS" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Input tidak valid!${NC}"; sleep 2; xray_create "$PROTO"; return
    fi

    EXIST=$(sqlite3 "$DATABASE" \
        "SELECT COUNT(*) FROM xray_users WHERE username='$USERNAME' AND protocol='$PROTO'")
    if [[ "$EXIST" -gt 0 ]]; then
        echo -e "${RED}Username sudah ada untuk protokol ini!${NC}"; sleep 2; return
    fi

    UUID=${CUSTOM_UUID:-$(generate_uuid)}
    IP_LIMIT=${IP_LIMIT:-1}
    QUOTA=${QUOTA:-0}
    TLS_ENABLED=${TLS_ENABLED:-1}
    EXPIRE_DATE=$(date -d "+${DAYS} days" +"%Y-%m-%d")
    WS_PATH=$(gen_ws_path "$PROTO")

    # Tambahkan ke Xray config
    RESULT=$(add_xray_client "$PROTO" "$USERNAME" "$UUID" "$IP_LIMIT")
    if [[ "$RESULT" == "DUPLICATE" ]]; then
        echo -e "${RED}UUID sudah digunakan!${NC}"; sleep 2; xray_create "$PROTO"; return
    fi

    # Update WS path di nginx config jika custom
    # (opsional, path sudah di-proxy di nginx)

    # Simpan ke database
    sqlite3 "$DATABASE" << EOF
INSERT INTO xray_users (username, uuid, protocol, quota_gb, ip_limit, expired_at, tls_enabled, ws_path)
VALUES ('$USERNAME', '$UUID', '$PROTO', $QUOTA, $IP_LIMIT, '$EXPIRE_DATE', $TLS_ENABLED, '$WS_PATH');
EOF

    # Reload Xray
    reload_xray

    # Generate link
    LINK=$(generate_link "$PROTO" "$UUID" "$USERNAME" "$TLS_ENABLED" "$WS_PATH")
    DOMAIN=$(sqlite3 "$DATABASE" "SELECT value FROM settings WHERE key='domain'")

    # Tampilkan info
    echo ""
    echo -e "${GREEN}✔ Akun ${PROTO^^} berhasil dibuat!${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e " Username  : ${YELLOW}$USERNAME${NC}"
    echo -e " UUID/Pass : ${YELLOW}$UUID${NC}"
    echo -e " Protokol  : ${YELLOW}${PROTO^^}${NC}"
    echo -e " WS Path   : ${YELLOW}$WS_PATH${NC}"
    echo -e " TLS       : ${YELLOW}$([ "$TLS_ENABLED" = "1" ] && echo 'Aktif' || echo 'Non-TLS')${NC}"
    echo -e " Expired   : ${YELLOW}$EXPIRE_DATE${NC}"
    echo -e " IP Limit  : ${YELLOW}$IP_LIMIT${NC}"
    echo -e " Quota     : ${YELLOW}${QUOTA}GB${NC}"
    echo -e " Domain    : ${YELLOW}$DOMAIN${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e " ${YELLOW}Link Import:${NC}"
    echo -e " ${GREEN}$LINK${NC}"
    echo ""

    # Generate QR Code jika ada qrencode
    if command -v qrencode &>/dev/null; then
        echo -e " ${YELLOW}QR Code:${NC}"
        echo "$LINK" | qrencode -t ANSIUTF8
    fi

    echo -ne " ${YELLOW}[Enter] Kembali...${NC}"; read -r
    xray_menu "$PROTO"
}

# ── Trial akun Xray
xray_trial() {
    local PROTO=$1
    clear
    echo -e "${CYAN}${BOLD}━━━━━━━━━━ TRIAL ${PROTO^^} ACCOUNT ━━━━━━━━━━${NC}"
    echo ""
    echo -ne " Username: "; read -r USERNAME

    if [[ -z "$USERNAME" ]]; then
        echo -e "${RED}Username tidak boleh kosong!${NC}"; sleep 2; xray_trial "$PROTO"; return
    fi

    UUID=$(generate_uuid)
    EXPIRE_DATE=$(date -d "+1 day" +"%Y-%m-%d")
    WS_PATH=$(gen_ws_path "$PROTO")

    add_xray_client "$PROTO" "$USERNAME" "$UUID" 1

    sqlite3 "$DATABASE" << EOF
INSERT INTO xray_users (username, uuid, protocol, quota_gb, ip_limit, expired_at, tls_enabled, ws_path, is_trial)
VALUES ('$USERNAME', '$UUID', '$PROTO', 1, 1, '$EXPIRE_DATE', 1, '$WS_PATH', 1);
EOF

    reload_xray
    LINK=$(generate_link "$PROTO" "$UUID" "$USERNAME" "1" "$WS_PATH")

    echo -e "${GREEN}✔ Trial ${PROTO^^} dibuat (1 hari, 1GB, 1 IP)${NC}"
    echo -e " UUID: ${YELLOW}$UUID${NC}"
    echo -e " Expired: ${YELLOW}$EXPIRE_DATE${NC}"
    echo -e " Link: ${GREEN}$LINK${NC}"
    echo -ne " ${YELLOW}[Enter] Kembali...${NC}"; read -r
    xray_menu "$PROTO"
}

# ── Hapus akun Xray
xray_delete() {
    local PROTO=$1
    clear
    echo -e "${CYAN}${BOLD}━━━━━━━━━━ DELETE ${PROTO^^} ACCOUNT ━━━━━━━━━━${NC}"
    echo ""
    echo -ne " Username: "; read -r USERNAME

    ROW=$(sqlite3 "$DATABASE" \
        "SELECT uuid FROM xray_users WHERE username='$USERNAME' AND protocol='$PROTO'")
    if [[ -z "$ROW" ]]; then
        echo -e "${RED}User tidak ditemukan!${NC}"; sleep 2; xray_menu "$PROTO"; return
    fi

    echo -ne " ${YELLOW}Konfirmasi hapus $USERNAME? [y/N]:${NC} "; read -r CONFIRM
    [[ "$CONFIRM" != "y" ]] && [[ "$CONFIRM" != "Y" ]] && xray_menu "$PROTO" && return

    remove_xray_client "$PROTO" "$ROW"
    sqlite3 "$DATABASE" \
        "DELETE FROM xray_users WHERE username='$USERNAME' AND protocol='$PROTO'"
    reload_xray

    echo -e "${GREEN}✔ Akun $USERNAME dihapus!${NC}"
    sleep 2; xray_menu "$PROTO"
}

# ── Extend akun Xray
xray_extend() {
    local PROTO=$1
    clear
    echo -e "${CYAN}${BOLD}━━━━━━━━━━ EXTEND ${PROTO^^} ACCOUNT ━━━━━━━━━━${NC}"
    echo ""
    echo -ne " Username: "; read -r USERNAME
    echo -ne " Tambah berapa hari: "; read -r DAYS

    if ! [[ "$DAYS" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Hari harus angka!${NC}"; sleep 2; xray_extend "$PROTO"; return
    fi

    CURRENT_EXP=$(sqlite3 "$DATABASE" \
        "SELECT expired_at FROM xray_users WHERE username='$USERNAME' AND protocol='$PROTO'")
    if [[ -z "$CURRENT_EXP" ]]; then
        echo -e "${RED}User tidak ditemukan!${NC}"; sleep 2; xray_menu "$PROTO"; return
    fi

    if [[ "$CURRENT_EXP" < "$(date +%Y-%m-%d)" ]]; then
        NEW_EXP=$(date -d "+${DAYS} days" +"%Y-%m-%d")
    else
        NEW_EXP=$(date -d "$CURRENT_EXP +${DAYS} days" +"%Y-%m-%d")
    fi

    sqlite3 "$DATABASE" \
        "UPDATE xray_users SET expired_at='$NEW_EXP', status='active' WHERE username='$USERNAME' AND protocol='$PROTO'"

    echo -e "${GREEN}✔ Akun $USERNAME diperpanjang hingga: ${YELLOW}$NEW_EXP${NC}"
    sleep 2; xray_menu "$PROTO"
}

# ── Cek akun Xray
xray_check() {
    local PROTO=$1
    clear
    echo -e "${CYAN}${BOLD}━━━━━━━━━━ CHECK ${PROTO^^} ACCOUNT ━━━━━━━━━━${NC}"
    echo ""
    echo -ne " Username: "; read -r USERNAME

    ROW=$(sqlite3 "$DATABASE" \
        "SELECT username, uuid, quota_gb, quota_used, ip_limit, expired_at, status, ws_path, tls_enabled \
         FROM xray_users WHERE username='$USERNAME' AND protocol='$PROTO'")

    if [[ -z "$ROW" ]]; then
        echo -e "${RED}User tidak ditemukan!${NC}"
    else
        IFS='|' read -r UN UUID QUOTA QU IP_LIM EXP STAT WS_PATH TLS <<< "$ROW"
        LINK=$(generate_link "$PROTO" "$UUID" "$UN" "$TLS" "$WS_PATH")
        echo ""
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e " Username  : ${YELLOW}$UN${NC}"
        echo -e " UUID/Pass : ${YELLOW}$UUID${NC}"
        echo -e " Status    : ${YELLOW}$STAT${NC}"
        echo -e " Quota     : ${YELLOW}${QU}GB / ${QUOTA}GB${NC}"
        echo -e " IP Limit  : ${YELLOW}$IP_LIM${NC}"
        echo -e " Expired   : ${YELLOW}$EXP${NC}"
        echo -e " WS Path   : ${YELLOW}$WS_PATH${NC}"
        echo -e " TLS       : ${YELLOW}$([ "$TLS" = "1" ] && echo 'Aktif' || echo 'Non-TLS')${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e " ${YELLOW}Link Import:${NC}"
        echo -e " ${GREEN}$LINK${NC}"
        if command -v qrencode &>/dev/null; then
            echo ""
            echo "$LINK" | qrencode -t ANSIUTF8
        fi
    fi

    echo -ne " ${YELLOW}[Enter] Kembali...${NC}"; read -r
    xray_menu "$PROTO"
}

# ── List akun Xray
xray_list() {
    local PROTO=$1
    clear
    echo -e "${CYAN}${BOLD}━━━━━━━━━━ LIST ${PROTO^^} ACCOUNTS ━━━━━━━━━━${NC}"
    echo ""
    printf " %-15s %-12s %-16s %-8s %-10s\n" "Username" "Expired" "Quota Used" "IP Lim" "Status"
    echo -e " ${CYAN}──────────────────────────────────────────────────────────────${NC}"

    sqlite3 "$DATABASE" \
        "SELECT username, expired_at, quota_used, quota_gb, ip_limit, status FROM xray_users WHERE protocol='$PROTO' ORDER BY username" | \
    while IFS='|' read -r UN EXP QU QUOTA IPN STAT; do
        QUOTA_DISPLAY="${QU:-0}/${QUOTA}GB"
        case "$STAT" in
            active)  STAT_COLOR="${GREEN}${STAT}${NC}" ;;
            locked)  STAT_COLOR="${RED}${STAT}${NC}" ;;
            *)       STAT_COLOR="${YELLOW}${STAT}${NC}" ;;
        esac
        printf " %-15s %-12s %-16s %-8s " "$UN" "$EXP" "$QUOTA_DISPLAY" "$IPN"
        echo -e "$STAT_COLOR"
    done

    TOTAL=$(sqlite3 "$DATABASE" "SELECT COUNT(*) FROM xray_users WHERE protocol='$PROTO'")
    echo -e " ${CYAN}──────────────────────────────────────────────────────────────${NC}"
    echo -e " Total: ${YELLOW}$TOTAL${NC}"
    echo -ne " ${YELLOW}[Enter] Kembali...${NC}"; read -r
    xray_menu "$PROTO"
}

# ── Lock/Unlock akun Xray
xray_lock() {
    local PROTO=$1
    local ACTION=$2
    clear
    echo -e "${CYAN}${BOLD}━━━━━━━━━━ ${ACTION^^} ${PROTO^^} ACCOUNT ━━━━━━━━━━${NC}"
    echo ""
    echo -ne " Username: "; read -r USERNAME

    ROW=$(sqlite3 "$DATABASE" \
        "SELECT uuid FROM xray_users WHERE username='$USERNAME' AND protocol='$PROTO'")
    if [[ -z "$ROW" ]]; then
        echo -e "${RED}User tidak ditemukan!${NC}"; sleep 2; xray_menu "$PROTO"; return
    fi

    if [[ "$ACTION" == "lock" ]]; then
        remove_xray_client "$PROTO" "$ROW"
        sqlite3 "$DATABASE" \
            "UPDATE xray_users SET status='locked' WHERE username='$USERNAME' AND protocol='$PROTO'"
        echo -e "${GREEN}✔ Akun $USERNAME di-lock!${NC}"
    else
        add_xray_client "$PROTO" "$USERNAME" "$ROW" 1
        sqlite3 "$DATABASE" \
            "UPDATE xray_users SET status='active' WHERE username='$USERNAME' AND protocol='$PROTO'"
        echo -e "${GREEN}✔ Akun $USERNAME di-unlock!${NC}"
    fi

    reload_xray
    sleep 2; xray_menu "$PROTO"
}

# ── Edit limit IP Xray
xray_edit_ip_limit() {
    local PROTO=$1
    clear
    echo -e "${CYAN}${BOLD}━━━━━━━━━━ EDIT IP LIMIT ${PROTO^^} ━━━━━━━━━━${NC}"
    echo ""
    echo -e " ${GREEN}1.)${NC} Edit per user"
    echo -e " ${GREEN}2.)${NC} Edit semua user"
    echo -e " ${RED}x.)${NC} Kembali"
    echo ""
    echo -ne " Pilihan: "; read -r OPT

    case "$OPT" in
        1)
            echo -ne " Username: "; read -r USERNAME
            echo -ne " Limit IP baru: "; read -r NEW_LIMIT
            sqlite3 "$DATABASE" \
                "UPDATE xray_users SET ip_limit=$NEW_LIMIT WHERE username='$USERNAME' AND protocol='$PROTO'"
            echo -e "${GREEN}✔ IP limit $USERNAME diset $NEW_LIMIT${NC}"
            ;;
        2)
            echo -ne " Limit IP baru (semua): "; read -r NEW_LIMIT
            sqlite3 "$DATABASE" "UPDATE xray_users SET ip_limit=$NEW_LIMIT WHERE protocol='$PROTO'"
            echo -e "${GREEN}✔ IP limit semua user diset $NEW_LIMIT${NC}"
            ;;
        x|X) xray_menu "$PROTO"; return ;;
    esac
    sleep 2; xray_edit_ip_limit "$PROTO"
}

# ── Edit bandwidth Xray
xray_edit_bandwidth() {
    local PROTO=$1
    clear
    echo -e "${CYAN}${BOLD}━━━━━━━━━━ EDIT BANDWIDTH ${PROTO^^} ━━━━━━━━━━${NC}"
    echo ""
    echo -e " ${GREEN}1.)${NC} Edit per user"
    echo -e " ${GREEN}2.)${NC} Edit semua user"
    echo -ne " Pilihan: "; read -r OPT

    case "$OPT" in
        1)
            echo -ne " Username: "; read -r USERNAME
            echo -ne " Quota GB baru (0=unlimited): "; read -r QUOTA
            sqlite3 "$DATABASE" \
                "UPDATE xray_users SET quota_gb=$QUOTA WHERE username='$USERNAME' AND protocol='$PROTO'"
            echo -e "${GREEN}✔ Quota $USERNAME diset ${QUOTA}GB${NC}"
            ;;
        2)
            echo -ne " Quota GB baru (semua): "; read -r QUOTA
            sqlite3 "$DATABASE" "UPDATE xray_users SET quota_gb=$QUOTA WHERE protocol='$PROTO'"
            echo -e "${GREEN}✔ Quota semua user diset ${QUOTA}GB${NC}"
            ;;
    esac
    sleep 2; xray_menu "$PROTO"
}

# ── Monitor koneksi aktif Xray
xray_monitor_login() {
    local PROTO=$1
    clear
    echo -e "${CYAN}${BOLD}━━━━━━━━━━ MONITOR LOGIN AKTIF ${PROTO^^} ━━━━━━━━━━${NC}"
    echo ""

    local LOG_FILE="/var/log/xray/access.log"
    echo -e " ${YELLOW}Koneksi aktif dari access log (20 terakhir):${NC}"
    echo ""
    if [[ -f "$LOG_FILE" ]]; then
        echo -e " ${CYAN}──────────────────────────────────────────────────────────────${NC}"
        printf " %-20s %-25s %-20s\n" "Email/Username" "IP Asal" "Waktu"
        echo -e " ${CYAN}──────────────────────────────────────────────────────────────${NC}"
        tail -n 500 "$LOG_FILE" 2>/dev/null | grep "accepted" | awk '{
            ts = $1 " " $2
            email = ""
            ip = ""
            for(i=1;i<=NF;i++) {
                if ($i == "email:") email = $(i+1)
                if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$/) ip = $i
            }
            if (email != "") printf " %-20s %-25s %-20s\n", email, ip, ts
        }' | tail -n 20
        echo -e " ${CYAN}──────────────────────────────────────────────────────────────${NC}"
    else
        echo -e " ${RED}File log tidak ditemukan: $LOG_FILE${NC}"
    fi

    echo ""
    echo -e " ${YELLOW}User aktif di database (status=active, diurutkan quota terbesar):${NC}"
    echo ""
    printf " %-18s %-14s %-8s %-12s\n" "Username" "Quota Dipakai" "IP Lim" "Expired"
    echo -e " ${CYAN}──────────────────────────────────────────────────────────────${NC}"
    sqlite3 "$DATABASE" \
        "SELECT username, quota_used, ip_limit, expired_at FROM xray_users WHERE protocol='$PROTO' AND status='active' ORDER BY quota_used DESC LIMIT 20" | \
    while IFS='|' read -r UN QU IPN EXP; do
        printf " %-18s %-14s %-8s %-12s\n" "$UN" "${QU:-0}GB" "$IPN" "$EXP"
    done
    echo -e " ${CYAN}──────────────────────────────────────────────────────────────${NC}"

    echo ""
    echo -ne " ${YELLOW}[Enter] Kembali...${NC}"; read -r
    xray_menu "$PROTO"
}

# ── Auto-lock user Xray yang quota habis
xray_check_quota_lock() {
    sqlite3 "$DATABASE" \
        "SELECT username, uuid, protocol FROM xray_users WHERE status='active' AND quota_gb > 0 AND quota_used >= quota_gb" 2>/dev/null | \
    while IFS='|' read -r USERNAME UUID PROTO; do
        remove_xray_client "$PROTO" "$UUID"
        sqlite3 "$DATABASE" \
            "UPDATE xray_users SET status='locked' WHERE username='$USERNAME' AND protocol='$PROTO'"
        systemctl restart xray-skynet 2>/dev/null || true
        echo "[QUOTA_LOCK] $PROTO user $USERNAME quota habis, akun di-lock"
    done
}

# ── Auto-lock user Xray yang melebihi IP limit
xray_check_ip_lock() {
    local PROTO=$1
    local LOG_FILE="/var/log/xray/access.log"
    [[ ! -f "$LOG_FILE" ]] && return

    sqlite3 "$DATABASE" \
        "SELECT username, uuid, ip_limit FROM xray_users WHERE protocol='$PROTO' AND status='active'" 2>/dev/null | \
    while IFS='|' read -r USERNAME UUID IP_LIMIT; do
        ACTIVE_COUNT=$(tail -n 2000 "$LOG_FILE" 2>/dev/null | grep "email: $USERNAME" | awk '{
            for(i=1;i<=NF;i++) {
                if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$/) print $i
            }
        }' | cut -d: -f1 | sort -u | wc -l)
        if [[ "$ACTIVE_COUNT" -gt "$IP_LIMIT" ]]; then
            remove_xray_client "$PROTO" "$UUID"
            sqlite3 "$DATABASE" \
                "UPDATE xray_users SET status='locked' WHERE username='$USERNAME' AND protocol='$PROTO'"
            systemctl restart xray-skynet 2>/dev/null || true
            echo "[IP_LOCK] $PROTO user $USERNAME melebihi IP limit ($ACTIVE_COUNT/$IP_LIMIT), akun di-lock"
        fi
    done
}

# ── Menu Xray
xray_menu() {
    local PROTO=$1
    clear
    echo -e "${CYAN}${BOLD}"
    echo "┌─────────────────────────────────────────────────────┐"
    printf "│               MENU %-32s│\n" "${PROTO^^}"
    echo "└─────────────────────────────────────────────────────┘"
    echo -e "${NC}"
    echo -e " ${GREEN}1.)${NC}  Create Account"
    echo -e " ${GREEN}2.)${NC}  Trial Account"
    echo -e " ${GREEN}3.)${NC}  Delete Account"
    echo -e " ${GREEN}4.)${NC}  Extend Account"
    echo -e " ${GREEN}5.)${NC}  Check Account"
    echo -e " ${GREEN}6.)${NC}  List Account"
    echo -e " ${GREEN}7.)${NC}  Lock Account"
    echo -e " ${GREEN}8.)${NC}  Unlock Account"
    echo -e " ${GREEN}9.)${NC}  Edit Limit IP"
    echo -e " ${GREEN}10.)${NC} Edit Bandwidth/Quota"
    echo -e " ${GREEN}11.)${NC} Monitor Login Aktif"
    echo -e " ${RED}x.)${NC}  Kembali"
    echo ""
    echo -ne " ${YELLOW}Pilihan:${NC} "; read -r choice

    case "$choice" in
        1)  xray_create "$PROTO" ;;
        2)  xray_trial "$PROTO" ;;
        3)  xray_delete "$PROTO" ;;
        4)  xray_extend "$PROTO" ;;
        5)  xray_check "$PROTO" ;;
        6)  xray_list "$PROTO" ;;
        7)  xray_lock "$PROTO" "lock" ;;
        8)  xray_lock "$PROTO" "unlock" ;;
        9)  xray_edit_ip_limit "$PROTO" ;;
        10) xray_edit_bandwidth "$PROTO" ;;
        11) xray_monitor_login "$PROTO" ;;
        x|X) source /opt/skynet/menu.sh; show_main_menu ;;
        *) echo -e "${RED}Pilihan tidak valid!${NC}"; sleep 1; xray_menu "$PROTO" ;;
    esac
}
