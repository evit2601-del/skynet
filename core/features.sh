#!/bin/bash
# ============================================================
# SKYNET — MENU FEATURES (LENGKAP)
# ============================================================

source /opt/skynet/config/settings.conf 2>/dev/null

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; BLUE='\033[0;34m'
NC='\033[0m'; BOLD='\033[1m'; DIM='\033[2m'

# ══════════════════════════════════════════
# 1. CHECK BANDWIDTH
# ══════════════════════════════════════════
feature_bandwidth() {
    clear
    echo -e "${CYAN}${BOLD}━━━━━━━━━━ CHECK BANDWIDTH ━━━━━━━━━━${NC}"
    echo ""
    if ! command -v vnstat &>/dev/null; then
        echo -e "${RED}vnstat tidak terinstall!${NC}"; sleep 2; features_menu; return
    fi
    echo -e "${YELLOW}Daily Traffic:${NC}"
    vnstat -d 2>/dev/null || echo "Data belum tersedia"
    echo ""
    echo -e "${YELLOW}Monthly Traffic:${NC}"
    vnstat -m 2>/dev/null || echo "Data belum tersedia"
    echo ""
    echo -e "${YELLOW}Realtime (5 detik):${NC}"
    vnstat -l -i "$(ip route | grep default | awk '{print $5}' | head -1)" --style 0 2>/dev/null &
    VNPID=$!
    sleep 5
    kill $VNPID 2>/dev/null || true

    echo ""
    echo -ne " ${YELLOW}[Enter] Kembali...${NC}"; read -r
    features_menu
}

# ══════════════════════════════════════════
# 2. SET DATE AUTO REBOOT
# ══════════════════════════════════════════
feature_auto_reboot() {
    clear
    echo -e "${CYAN}${BOLD}━━━━━━━━━━ SET AUTO REBOOT ━━━━━━━━━━${NC}"
    echo ""
    echo -e " ${GREEN}1.)${NC} Aktifkan auto reboot"
    echo -e " ${GREEN}2.)${NC} Disable auto reboot"
    echo -e " ${GREEN}3.)${NC} Lihat jadwal aktif"
    echo -ne " Pilihan: "; read -r OPT

    case "$OPT" in
        1)
            echo -ne " Jam (0-23): "; read -r HOUR
            echo -ne " Hari (0=Minggu, *=setiap hari): "; read -r DAY
            if ! [[ "$HOUR" =~ ^[0-9]+$ ]] || [[ "$HOUR" -gt 23 ]]; then
                echo -e "${RED}Jam tidak valid!${NC}"; sleep 2; feature_auto_reboot; return
            fi
            (crontab -l 2>/dev/null | grep -v "skynet-reboot"; \
             echo "0 $HOUR * * $DAY /sbin/reboot # skynet-reboot") | crontab -
            echo -e "${GREEN}✔ Auto reboot diset jam $HOUR hari $DAY${NC}"
            ;;
        2)
            crontab -l 2>/dev/null | grep -v "skynet-reboot" | crontab -
            echo -e "${GREEN}✔ Auto reboot dinonaktifkan${NC}"
            ;;
        3)
            echo -e "${YELLOW}Jadwal reboot aktif:${NC}"
            crontab -l 2>/dev/null | grep "skynet-reboot" || echo " (tidak ada)"
            ;;
    esac
    echo -ne " ${YELLOW}[Enter] Kembali...${NC}"; read -r
    features_menu
}

# ══════════════════════════════════════════
# 3. REBOOT VPS
# ══════════════════════════════════════════
feature_reboot_vps() {
    clear
    echo -e "${RED}${BOLD}━━━━━━━━━━ REBOOT VPS ━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}⚠ Semua koneksi aktif akan terputus!${NC}"
    echo -ne " Konfirmasi reboot? [y/N]: "; read -r CONFIRM
    if [[ "$CONFIRM" == "y" ]] || [[ "$CONFIRM" == "Y" ]]; then
        echo -e "${RED}Rebooting in 3 seconds...${NC}"
        sleep 3
        /sbin/reboot
    else
        echo -e "${GREEN}Reboot dibatalkan.${NC}"
        sleep 2; features_menu
    fi
}

# ══════════════════════════════════════════
# 4. SPEED TEST VPS
# ══════════════════════════════════════════
feature_speedtest() {
    clear
    echo -e "${CYAN}${BOLD}━━━━━━━━━━ SPEED TEST VPS ━━━━━━━━━━${NC}"
    echo ""
    if command -v speedtest &>/dev/null; then
        echo -e "${YELLOW}Menjalankan speedtest...${NC}"
        speedtest
    elif command -v speedtest-cli &>/dev/null; then
        speedtest-cli
    else
        echo -e "${YELLOW}Menginstall speedtest-cli...${NC}"
        pip3 install speedtest-cli -q
        speedtest-cli
    fi
    echo -ne " ${YELLOW}[Enter] Kembali...${NC}"; read -r
    features_menu
}

# ══════════════════════════════════════════
# 5. CHANGE DROPBEAR VERSION
# ══════════════════════════════════════════
feature_change_dropbear() {
    clear
    echo -e "${CYAN}${BOLD}━━━━━━━━━━ CHANGE DROPBEAR VERSION ━━━━━━━━━━${NC}"
    echo ""
    CURRENT_VER=$(dropbear -V 2>&1 | head -1 || echo "Unknown")
    echo -e " Versi saat ini: ${YELLOW}$CURRENT_VER${NC}"
    echo ""
    echo -e " ${GREEN}1.)${NC} Install Dropbear terbaru (apt)"
    echo -e " ${GREEN}2.)${NC} Install Dropbear versi spesifik"
    echo -e " ${RED}x.)${NC} Kembali"
    echo -ne " Pilihan: "; read -r OPT

    case "$OPT" in
        1)
            apt-get install -y --only-upgrade dropbear
            systemctl restart dropbear
            echo -e "${GREEN}✔ Dropbear diupgrade!${NC}"
            ;;
        2)
            echo -ne " Versi (contoh: 2022.83): "; read -r VERSION
            apt-get install -y dropbear="$VERSION" 2>/dev/null || \
                echo -e "${RED}Versi tidak tersedia!${NC}"
            systemctl restart dropbear
            ;;
        x|X) features_menu; return ;;
    esac
    sleep 2; feature_change_dropbear
}

# ══════════════════════════════════════════
# 6. CHECK ALL SERVICES
# ══════════════════════════════════════════
feature_check_services() {
    clear
    echo -e "${CYAN}${BOLD}━━━━━━━━━━ CHECK ALL SERVICES ━━━━━━━━━━${NC}"
    echo ""
    declare -A SVCS=(
        ["SSH"]="ssh"
        ["Dropbear"]="dropbear"
        ["Nginx"]="nginx"
        ["Xray"]="xray-skynet"
        ["Fail2Ban"]="fail2ban"
        ["Stunnel"]="stunnel4"
        ["Bot Telegram"]="skynet-bot"
        ["REST API"]="skynet-api"
        ["BadVPN"]="badvpn-udpgw"
    )

    for NAME in "${!SVCS[@]}"; do
        SVC="${SVCS[$NAME]}"
        if systemctl is-active "$SVC" &>/dev/null; then
            echo -e " $(printf '%-15s' "$NAME") : ${GREEN}● ON${NC}"
        else
            echo -e " $(printf '%-15s' "$NAME") : ${RED}● OFF${NC}"
        fi
    done

    echo ""
    echo -ne " ${YELLOW}[Enter] Kembali...${NC}"; read -r
    features_menu
}

# ══════════════════════════════════════════
# 7. SETUP BOT TELEGRAM
# ══════════════════════════════════════════
feature_setup_bot() {
    clear
    echo -e "${CYAN}${BOLD}━━━━━━━━━━ SETUP BOT TELEGRAM ━━━━━━━━━━${NC}"
    echo ""
    echo -ne " Bot Token    : "; read -r BOT_TOKEN
    echo -ne " Admin ID     : "; read -r ADMIN_ID

    if [[ -z "$BOT_TOKEN" ]] || [[ -z "$ADMIN_ID" ]]; then
        echo -e "${RED}Token dan ID tidak boleh kosong!${NC}"
        sleep 2; feature_setup_bot; return
    fi

    # Simpan ke database dan config
    sqlite3 "$DATABASE" "UPDATE settings SET value='$BOT_TOKEN' WHERE key='bot_token'"
    sqlite3 "$DATABASE" "UPDATE settings SET value='$ADMIN_ID' WHERE key='admin_telegram_id'"

    # Update settings.conf
    grep -v "^BOT_TOKEN\|^ADMIN_TELEGRAM_ID" /opt/skynet/config/settings.conf > /tmp/settings_tmp
    echo "BOT_TOKEN=$BOT_TOKEN" >> /tmp/settings_tmp
    echo "ADMIN_TELEGRAM_ID=$ADMIN_ID" >> /tmp/settings_tmp
    mv /tmp/settings_tmp /opt/skynet/config/settings.conf
    chmod 600 /opt/skynet/config/settings.conf

    # Buat systemd service jika belum ada
    if ! systemctl is-enabled skynet-bot &>/dev/null; then
        systemctl enable skynet-bot
    fi
    systemctl restart skynet-bot
    sleep 2

    if systemctl is-active skynet-bot &>/dev/null; then
        echo -e "${GREEN}✔ Bot Telegram berhasil distart!${NC}"
    else
        echo -e "${RED}Bot gagal start. Cek: journalctl -u skynet-bot${NC}"
    fi

    echo -ne " ${YELLOW}[Enter] Kembali...${NC}"; read -r
    features_menu
}

# ══════════════════════════════════════════
# 8. BACKUP CONFIG
# ══════════════════════════════════════════
feature_backup() {
    clear
    echo -e "${CYAN}${BOLD}━━━━━━━━━━ BACKUP CONFIGURATION ━━━━━━━━━━${NC}"
    echo ""

    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    BACKUP_FILE="$BACKUP_DIR/skynet_backup_$TIMESTAMP.zip"
    mkdir -p "$BACKUP_DIR"

    echo -e "${YELLOW}Memproses backup...${NC}"
    zip -q "$BACKUP_FILE" \
        /usr/local/etc/xray/config.json \
        /etc/ssh/sshd_config \
        "$DATABASE" \
        /opt/skynet/config/settings.conf \
        /etc/nginx/sites-available/skynet \
        2>/dev/null || true

    if [[ -f "$BACKUP_FILE" ]]; then
        SIZE=$(du -sh "$BACKUP_FILE" | cut -f1)
        echo -e "${GREEN}✔ Backup berhasil: $BACKUP_FILE ($SIZE)${NC}"

        # Kirim ke Telegram jika dikonfigurasi
        BOT_TOKEN=$(sqlite3 "$DATABASE" "SELECT value FROM settings WHERE key='bot_token'")
        ADMIN_ID=$(sqlite3 "$DATABASE" "SELECT value FROM settings WHERE key='admin_telegram_id'")
        if [[ -n "$BOT_TOKEN" ]] && [[ -n "$ADMIN_ID" ]]; then
            echo -ne " Kirim ke Telegram? [y/N]: "; read -r SEND
            if [[ "$SEND" == "y" ]]; then
                curl -s -F document=@"$BACKUP_FILE" \
                    "https://api.telegram.org/bot$BOT_TOKEN/sendDocument?chat_id=$ADMIN_ID" \
                    -F caption="SKYNET Backup - $TIMESTAMP" > /dev/null
                echo -e "${GREEN}✔ Backup terkirim ke Telegram!${NC}"
            fi
        fi
    else
        echo -e "${RED}Backup gagal!${NC}"
    fi

    echo -ne " ${YELLOW}[Enter] Kembali...${NC}"; read -r
    features_menu
}

# ══════════════════════════════════════════
# 9. RESTORE CONFIG
# ══════════════════════════════════════════
feature_restore() {
    clear
    echo -e "${CYAN}${BOLD}━━━━━━━━━━ RESTORE CONFIGURATION ━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}File backup tersedia:${NC}"
    ls -la "$BACKUP_DIR"/*.zip 2>/dev/null || echo " (tidak ada backup)"
    echo ""
    echo -ne " Path file backup: "; read -r BACKUP_PATH

    if [[ ! -f "$BACKUP_PATH" ]]; then
        echo -e "${RED}File tidak ditemukan!${NC}"; sleep 2; feature_restore; return
    fi

    echo -ne " ${YELLOW}Konfirmasi restore? Ini akan menimpa config saat ini! [y/N]:${NC} "; read -r CONFIRM
    [[ "$CONFIRM" != "y" ]] && [[ "$CONFIRM" != "Y" ]] && features_menu && return

    echo -e "${YELLOW}Restore...${NC}"
    unzip -o "$BACKUP_PATH" -d / 2>/dev/null

    # Restart services
    systemctl restart xray-skynet nginx ssh 2>/dev/null || true
    echo -e "${GREEN}✔ Restore berhasil! Services direstart.${NC}"
    sleep 2; features_menu
}

# ══════════════════════════════════════════
# 10. CLOUDFLARE DOMAIN MANAGER (lanjutan)
# ══════════════════════════════════════════
feature_cloudflare_domain() {
    clear
    echo -e "${CYAN}${BOLD}━━━━━━━━━━ MANAGES DOMAIN CLOUDFLARE ━━━━━━━━━━${NC}"
    echo ""
    echo -e " ${GREEN}1.)${NC} Tambah A Record"
    echo -e " ${GREEN}2.)${NC} Update Record"
    echo -e " ${GREEN}3.)${NC} Hapus Record"
    echo -e " ${RED}x.)${NC} Kembali"
    echo -ne " Pilihan: "; read -r OPT
    [[ "$OPT" == "x" || "$OPT" == "X" ]] && features_menu && return

    echo -ne " Cloudflare API Token : "; read -r CF_TOKEN
    echo -ne " Zone ID              : "; read -r CF_ZONE_ID

    case "$OPT" in
        1)
            echo -ne " Nama subdomain (ex: vpn): "; read -r CF_NAME
            echo -ne " IP Address             : "; read -r CF_IP
            RESP=$(curl -s -X POST \
                "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
                -H "Authorization: Bearer $CF_TOKEN" \
                -H "Content-Type: application/json" \
                --data "{\"type\":\"A\",\"name\":\"$CF_NAME\",\"content\":\"$CF_IP\",\"ttl\":120,\"proxied\":false}")
            SUCCESS=$(echo "$RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['success'])" 2>/dev/null)
            if [[ "$SUCCESS" == "True" ]]; then
                echo -e "${GREEN}✔ A Record berhasil ditambahkan!${NC}"
            else
                echo -e "${RED}Gagal: $(echo "$RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['errors'])" 2>/dev/null)${NC}"
            fi
            ;;
        2)
            echo -ne " Record ID (dari CF dashboard): "; read -r RECORD_ID
            echo -ne " Nama baru                    : "; read -r CF_NAME
            echo -ne " IP baru                      : "; read -r CF_IP
            RESP=$(curl -s -X PUT \
                "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records/$RECORD_ID" \
                -H "Authorization: Bearer $CF_TOKEN" \
                -H "Content-Type: application/json" \
                --data "{\"type\":\"A\",\"name\":\"$CF_NAME\",\"content\":\"$CF_IP\",\"ttl\":120,\"proxied\":false}")
            echo -e "${GREEN}✔ Record diupdate!${NC}"
            ;;
        3)
            echo -ne " Record ID: "; read -r RECORD_ID
            echo -ne " ${YELLOW}Konfirmasi hapus record? [y/N]:${NC} "; read -r CONFIRM
            if [[ "$CONFIRM" == "y" || "$CONFIRM" == "Y" ]]; then
                curl -s -X DELETE \
                    "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records/$RECORD_ID" \
                    -H "Authorization: Bearer $CF_TOKEN" > /dev/null
                echo -e "${GREEN}✔ Record dihapus!${NC}"
            fi
            ;;
    esac
    echo -ne " ${YELLOW}[Enter] Kembali...${NC}"; read -r
    features_menu
}

# ══════════════════════════════════════════
# 11. CLOUDFLARE WARP
# ══════════════════════════════════════════
feature_cloudflare_warp() {
    clear
    echo -e "${CYAN}${BOLD}━━━━━━━━━━ CLOUDFLARE WARP ━━━━━━━━━━${NC}"
    echo ""
    echo -e " ${GREEN}1.)${NC} Install WARP"
    echo -e " ${GREEN}2.)${NC} Connect WARP"
    echo -e " ${GREEN}3.)${NC} Disconnect WARP"
    echo -e " ${GREEN}4.)${NC} Status WARP"
    echo -e " ${RED}x.)${NC} Kembali"
    echo -ne " Pilihan: "; read -r OPT

    case "$OPT" in
        1)
            echo -e "${YELLOW}Menginstall Cloudflare WARP...${NC}"
            curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | \
                gpg --yes --dearmor -o /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
            echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] \
                https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | \
                tee /etc/apt/sources.list.d/cloudflare-client.list
            apt-get update -y && apt-get install -y cloudflare-warp
            warp-cli register --accept-tos
            echo -e "${GREEN}✔ WARP berhasil diinstall!${NC}"
            ;;
        2)
            warp-cli connect
            echo -e "${GREEN}✔ WARP terhubung!${NC}"
            ;;
        3)
            warp-cli disconnect
            echo -e "${GREEN}✔ WARP diputus!${NC}"
            ;;
        4)
            warp-cli status
            ;;
        x|X) features_menu; return ;;
    esac
    echo -ne " ${YELLOW}[Enter] Kembali...${NC}"; read -r
    feature_cloudflare_warp
}

# ══════════════════════════════════════════
# 12. OUTBOUNDS ROUTING XRAY
# ══════════════════════════════════════════
feature_outbounds_routing() {
    clear
    echo -e "${CYAN}${BOLD}━━━━━━━━━━ OUTBOUNDS ROUTING ━━━━━━━━━━${NC}"
    echo ""
    echo -e " ${GREEN}1.)${NC} Tampilkan outbound aktif"
    echo -e " ${GREEN}2.)${NC} Tambah outbound"
    echo -e " ${GREEN}3.)${NC} Hapus outbound"
    echo -e " ${RED}x.)${NC} Kembali"
    echo -ne " Pilihan: "; read -r OPT

    case "$OPT" in
        1)
            echo -e "${YELLOW}Outbound aktif:${NC}"
            python3 -c "
import json
with open('/usr/local/etc/xray/config.json') as f:
    c = json.load(f)
for o in c.get('outbounds', []):
    print(f\"  Tag: {o.get('tag')} | Protocol: {o.get('protocol')}\")
"
            ;;
        2)
            echo -ne " Tag outbound   : "; read -r OB_TAG
            echo -ne " Protokol (freedom/socks/http/vmess/vless): "; read -r OB_PROTO
            echo -ne " Server address : "; read -r OB_ADDR
            echo -ne " Port           : "; read -r OB_PORT
            python3 << EOF
import json
with open('/usr/local/etc/xray/config.json') as f:
    c = json.load(f)

new_outbound = {
    "tag": "$OB_TAG",
    "protocol": "$OB_PROTO",
    "settings": {
        "servers": [{"address": "$OB_ADDR", "port": int("$OB_PORT")}]
    } if "$OB_PROTO" in ["socks","http"] else {}
}
c['outbounds'].append(new_outbound)
with open('/usr/local/etc/xray/config.json', 'w') as f:
    json.dump(c, f, indent=2)
print("OK")
EOF
            systemctl restart xray-skynet
            echo -e "${GREEN}✔ Outbound '$OB_TAG' ditambahkan!${NC}"
            ;;
        3)
            echo -ne " Tag outbound yang dihapus: "; read -r OB_TAG
            echo -ne " ${YELLOW}Konfirmasi? [y/N]:${NC} "; read -r CONFIRM
            if [[ "$CONFIRM" == "y" || "$CONFIRM" == "Y" ]]; then
                python3 << EOF
import json
with open('/usr/local/etc/xray/config.json') as f:
    c = json.load(f)
c['outbounds'] = [o for o in c['outbounds'] if o.get('tag') != '$OB_TAG']
with open('/usr/local/etc/xray/config.json', 'w') as f:
    json.dump(c, f, indent=2)
print("OK")
EOF
                systemctl restart xray-skynet
                echo -e "${GREEN}✔ Outbound '$OB_TAG' dihapus!${NC}"
            fi
            ;;
        x|X) features_menu; return ;;
    esac
    echo -ne " ${YELLOW}[Enter] Kembali...${NC}"; read -r
    feature_outbounds_routing
}

# ══════════════════════════════════════════
# 13. RULES ROUTING XRAY
# ══════════════════════════════════════════
feature_rules_routing() {
    clear
    echo -e "${CYAN}${BOLD}━━━━━━━━━━ RULES ROUTING XRAY ━━━━━━━━━━${NC}"
    echo ""
    echo -e " ${GREEN}1.)${NC} Tambah rule domain"
    echo -e " ${GREEN}2.)${NC} Tambah rule IP"
    echo -e " ${GREEN}3.)${NC} Tambah rule geoip"
    echo -e " ${GREEN}4.)${NC} Tampilkan rules aktif"
    echo -e " ${RED}x.)${NC} Kembali"
    echo -ne " Pilihan: "; read -r OPT

    case "$OPT" in
        1)
            echo -ne " Domain (ex: example.com): "; read -r DOMAIN_RULE
            echo -ne " Outbound tag tujuan     : "; read -r OUT_TAG
            python3 << EOF
import json
with open('/usr/local/etc/xray/config.json') as f:
    c = json.load(f)
rule = {"type": "field", "domain": ["$DOMAIN_RULE"], "outboundTag": "$OUT_TAG"}
c['routing']['rules'].append(rule)
with open('/usr/local/etc/xray/config.json', 'w') as f:
    json.dump(c, f, indent=2)
print("OK")
EOF
            systemctl restart xray-skynet
            echo -e "${GREEN}✔ Rule domain ditambahkan!${NC}"
            ;;
        2)
            echo -ne " IP/CIDR (ex: 192.168.1.0/24): "; read -r IP_RULE
            echo -ne " Outbound tag tujuan          : "; read -r OUT_TAG
            python3 << EOF
import json
with open('/usr/local/etc/xray/config.json') as f:
    c = json.load(f)
rule = {"type": "field", "ip": ["$IP_RULE"], "outboundTag": "$OUT_TAG"}
c['routing']['rules'].append(rule)
with open('/usr/local/etc/xray/config.json', 'w') as f:
    json.dump(c, f, indent=2)
print("OK")
EOF
            systemctl restart xray-skynet
            echo -e "${GREEN}✔ Rule IP ditambahkan!${NC}"
            ;;
        3)
            echo -ne " Kode negara geoip (ex: cn, us): "; read -r GEO_CODE
            echo -ne " Outbound tag tujuan           : "; read -r OUT_TAG
            python3 << EOF
import json
with open('/usr/local/etc/xray/config.json') as f:
    c = json.load(f)
rule = {"type": "field", "ip": ["geoip:$GEO_CODE"], "outboundTag": "$OUT_TAG"}
c['routing']['rules'].append(rule)
with open('/usr/local/etc/xray/config.json', 'w') as f:
    json.dump(c, f, indent=2)
print("OK")
EOF
            systemctl restart xray-skynet
            echo -e "${GREEN}✔ Rule geoip ditambahkan!${NC}"
            ;;
        4)
            echo -e "${YELLOW}Rules aktif:${NC}"
            python3 -c "
import json
with open('/usr/local/etc/xray/config.json') as f:
    c = json.load(f)
for i, r in enumerate(c.get('routing',{}).get('rules',[])):
    print(f'  [{i+1}] outbound: {r.get(\"outboundTag\")} | domain: {r.get(\"domain\",[])} | ip: {r.get(\"ip\",[])}')
"
            ;;
        x|X) features_menu; return ;;
    esac
    echo -ne " ${YELLOW}[Enter] Kembali...${NC}"; read -r
    feature_rules_routing
}

# ══════════════════════════════════════════
# 14. CHECK CONFIG ROUTING
# ══════════════════════════════════════════
feature_check_config() {
    clear
    echo -e "${CYAN}${BOLD}━━━━━━━━━━ CHECK CONFIG ROUTING ━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}Validasi JSON config Xray...${NC}"

    if python3 -c "import json; json.load(open('/usr/local/etc/xray/config.json'))" 2>/dev/null; then
        echo -e "${GREEN}✔ JSON valid!${NC}"
    else
        echo -e "${RED}✗ JSON tidak valid! Perbaiki config.${NC}"
        echo ""
        echo -e "${YELLOW}Error detail:${NC}"
        python3 -c "import json; json.load(open('/usr/local/etc/xray/config.json'))" 2>&1
    fi

    echo ""
    echo -e "${YELLOW}Test Xray dengan config saat ini...${NC}"
    if xray test -config /usr/local/etc/xray/config.json 2>&1; then
        echo -e "${GREEN}✔ Config Xray OK!${NC}"
    else
        echo -e "${RED}✗ Config Xray error!${NC}"
    fi

    echo -ne " ${YELLOW}[Enter] Kembali...${NC}"; read -r
    features_menu
}

# ══════════════════════════════════════════
# 15. START/STOP SERVICE
# ══════════════════════════════════════════
feature_start_stop_service() {
    clear
    echo -e "${CYAN}${BOLD}━━━━━━━━━━ START/STOP SERVICE ━━━━━━━━━━${NC}"
    echo ""
    local SVCS=("ssh" "dropbear" "nginx" "xray-skynet" "fail2ban" "stunnel4" "skynet-bot" "skynet-api" "badvpn-udpgw")
    for i in "${!SVCS[@]}"; do
        STATUS=$(systemctl is-active "${SVCS[$i]}" 2>/dev/null)
        [[ "$STATUS" == "active" ]] && STAT="${GREEN}ON${NC}" || STAT="${RED}OFF${NC}"
        echo -e " ${GREEN}$((i+1)).)${NC} ${SVCS[$i]} [$STAT]"
    done
    echo ""
    echo -ne " Pilih service (nomor): "; read -r SVC_NUM
    SVC_IDX=$((SVC_NUM - 1))
    if [[ -z "${SVCS[$SVC_IDX]}" ]]; then
        echo -e "${RED}Pilihan tidak valid!${NC}"; sleep 2; feature_start_stop_service; return
    fi
    SVC="${SVCS[$SVC_IDX]}"
    echo -e " ${GREEN}1.)${NC} Start  ${GREEN}2.)${NC} Stop  ${GREEN}3.)${NC} Restart"
    echo -ne " Aksi: "; read -r ACT
    case "$ACT" in
        1) systemctl start "$SVC" && echo -e "${GREEN}✔ $SVC started${NC}" ;;
        2)
            echo -ne " ${YELLOW}Konfirmasi stop $SVC? [y/N]:${NC} "; read -r CONF
            [[ "$CONF" == "y" || "$CONF" == "Y" ]] && systemctl stop "$SVC" && echo -e "${GREEN}✔ $SVC stopped${NC}"
            ;;
        3) systemctl restart "$SVC" && echo -e "${GREEN}✔ $SVC restarted${NC}" ;;
        *) echo -e "${RED}Pilihan tidak valid!${NC}" ;;
    esac
    echo -ne " ${YELLOW}[Enter] Kembali...${NC}"; read -r
    feature_start_stop_service
}

# ══════════════════════════════════════════
# 16. SECURITY SYN / ANTI DDOS
# ══════════════════════════════════════════
feature_security_syn() {
    clear
    echo -e "${CYAN}${BOLD}━━━━━━━━━━ SECURITY SYN / ANTI DDOS ━━━━━━━━━━${NC}"
    echo ""
    echo -e " ${GREEN}1.)${NC} Aktifkan proteksi SYN flood"
    echo -e " ${GREEN}2.)${NC} Limit koneksi per IP"
    echo -e " ${GREEN}3.)${NC} Basic Anti-DDoS iptables"
    echo -e " ${GREEN}4.)${NC} Reset semua rules iptables"
    echo -e " ${RED}x.)${NC} Kembali"
    echo -ne " Pilihan: "; read -r OPT

    case "$OPT" in
        1)
            # SYN flood protection via sysctl
            sysctl -w net.ipv4.tcp_syncookies=1
            sysctl -w net.ipv4.tcp_max_syn_backlog=2048
            sysctl -w net.ipv4.tcp_synack_retries=2
            sysctl -w net.ipv4.tcp_syn_retries=5

            # SYN flood iptables
            iptables -N SYN_FLOOD 2>/dev/null || true
            iptables -A INPUT -p tcp --syn -j SYN_FLOOD
            iptables -A SYN_FLOOD -m limit --limit 10/s --limit-burst 20 -j RETURN
            iptables -A SYN_FLOOD -j DROP

            echo -e "${GREEN}✔ Proteksi SYN flood aktif!${NC}"
            ;;
        2)
            echo -ne " Maksimal koneksi per IP (default 20): "; read -r MAX_CONN
            MAX_CONN=${MAX_CONN:-20}
            iptables -A INPUT -p tcp --dport 22 -m connlimit --connlimit-above "$MAX_CONN" -j REJECT
            iptables -A INPUT -p tcp --dport 443 -m connlimit --connlimit-above "$MAX_CONN" -j REJECT
            echo -e "${GREEN}✔ Limit koneksi $MAX_CONN per IP aktif!${NC}"
            ;;
        3)
            # Basic Anti-DDoS
            # Drop invalid packets
            iptables -A INPUT -m state --state INVALID -j DROP
            # Drop XMAS packets
            iptables -A INPUT -p tcp --tcp-flags ALL ALL -j DROP
            # Drop NULL packets
            iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP
            # Rate limit ICMP
            iptables -A INPUT -p icmp --icmp-type echo-request -m limit --limit 1/s --limit-burst 4 -j ACCEPT
            iptables -A INPUT -p icmp --icmp-type echo-request -j DROP
            echo -e "${GREEN}✔ Basic anti-DDoS aktif!${NC}"
            ;;
        4)
            echo -ne " ${YELLOW}Konfirmasi reset semua rules? [y/N]:${NC} "; read -r CONFIRM
            if [[ "$CONFIRM" == "y" || "$CONFIRM" == "Y" ]]; then
                iptables -F; iptables -X; iptables -Z
                ufw --force enable
                echo -e "${GREEN}✔ Rules direset!${NC}"
            fi
            ;;
        x|X) features_menu; return ;;
    esac
    echo -ne " ${YELLOW}[Enter] Kembali...${NC}"; read -r
    feature_security_syn
}

# ══════════════════════════════════════════
# 17. CHANGE DOMAIN VPS
# ══════════════════════════════════════════
feature_change_domain() {
    clear
    echo -e "${CYAN}${BOLD}━━━━━━━━━━ CHANGE DOMAIN VPS ━━━━━━━━━━${NC}"
    echo ""
    OLD_DOMAIN=$(sqlite3 "$DATABASE" "SELECT value FROM settings WHERE key='domain'")
    echo -e " Domain saat ini: ${YELLOW}$OLD_DOMAIN${NC}"
    echo -ne " Domain baru    : "; read -r NEW_DOMAIN
    echo -ne " Email SSL      : "; read -r NEW_EMAIL

    if [[ -z "$NEW_DOMAIN" ]] || [[ -z "$NEW_EMAIL" ]]; then
        echo -e "${RED}Domain dan email tidak boleh kosong!${NC}"
        sleep 2; feature_change_domain; return
    fi

    echo -e "${YELLOW}Proses ganti domain...${NC}"

    # Install SSL baru
    systemctl stop nginx
    certbot certonly --standalone --non-interactive --agree-tos \
        --email "$NEW_EMAIL" -d "$NEW_DOMAIN" --preferred-challenges http

    # Update nginx config
    sed -i "s/$OLD_DOMAIN/$NEW_DOMAIN/g" /etc/nginx/sites-available/skynet

    # Update Xray config
    sed -i "s/$OLD_DOMAIN/$NEW_DOMAIN/g" /usr/local/etc/xray/config.json

    # Update database
    sqlite3 "$DATABASE" "UPDATE settings SET value='$NEW_DOMAIN' WHERE key='domain'"

    # Update settings.conf
    sed -i "s/^DOMAIN=.*/DOMAIN=$NEW_DOMAIN/" /opt/skynet/config/settings.conf

    # Restart services
    systemctl start nginx
    systemctl restart xray-skynet nginx

    echo -e "${GREEN}✔ Domain berhasil diubah ke: $NEW_DOMAIN${NC}"
    echo -ne " ${YELLOW}[Enter] Kembali...${NC}"; read -r
    features_menu
}

# ══════════════════════════════════════════
# 18. CHANGE BANNER & HTTP RESPONSE
# ══════════════════════════════════════════
feature_change_banner() {
    clear
    echo -e "${CYAN}${BOLD}━━━━━━━━━━ CHANGE BANNER & RESPONSE ━━━━━━━━━━${NC}"
    echo ""
    echo -e " ${GREEN}1.)${NC} Edit SSH Banner"
    echo -e " ${GREEN}2.)${NC} Edit HTTP Response (Nginx)"
    echo -e " ${GREEN}3.)${NC} Lihat banner saat ini"
    echo -e " ${RED}x.)${NC} Kembali"
    echo -ne " Pilihan: "; read -r OPT

    case "$OPT" in
        1)
            echo -e "${YELLOW}Masukkan banner baru (ketik END pada baris baru untuk selesai):${NC}"
            BANNER_TEXT=""
            while IFS= read -r line; do
                [[ "$line" == "END" ]] && break
                BANNER_TEXT+="$line\n"
            done
            printf "%b" "$BANNER_TEXT" > /etc/ssh/skynet_banner
            systemctl restart ssh
            echo -e "${GREEN}✔ SSH Banner diperbarui!${NC}"
            ;;
        2)
            echo -e "${YELLOW}Masukkan HTTP response baru (untuk lokasi '/' di Nginx):${NC}"
            echo -ne " Response text: "; read -r HTTP_RESP
            sed -i "s|return 400 '.*'|return 400 '$HTTP_RESP'|" /etc/nginx/sites-available/skynet
            nginx -t && systemctl reload nginx
            echo -e "${GREEN}✔ HTTP response diperbarui!${NC}"
            ;;
        3)
            echo -e "${YELLOW}SSH Banner saat ini:${NC}"
            cat /etc/ssh/skynet_banner 2>/dev/null || echo "(kosong)"
            ;;
        x|X) features_menu; return ;;
    esac
    echo -ne " ${YELLOW}[Enter] Kembali...${NC}"; read -r
    feature_change_banner
}

# ══════════════════════════════════════════
# 19. SLOWDNS
# ══════════════════════════════════════════
feature_slowdns() {
    clear
    echo -e "${CYAN}${BOLD}━━━━━━━━━━ SLOWDNS ━━━━━━━━━━${NC}"
    echo ""
    echo -e " ${GREEN}1.)${NC} Install SlowDNS"
    echo -e " ${GREEN}2.)${NC} Start SlowDNS"
    echo -e " ${GREEN}3.)${NC} Stop SlowDNS"
    echo -e " ${GREEN}4.)${NC} Status SlowDNS"
    echo -e " ${RED}x.)${NC} Kembali"
    echo -ne " Pilihan: "; read -r OPT

    case "$OPT" in
        1)
            echo -e "${YELLOW}Menginstall SlowDNS...${NC}"
            cd /tmp
            wget -qO slowdns.zip https://github.com/beyondatlas/slowdns/releases/latest/download/slowdns-linux-amd64.zip 2>/dev/null || \
                echo -e "${YELLOW}Download manual: https://github.com/beyondatlas/slowdns${NC}"
            unzip -o slowdns.zip -d /usr/local/bin/ 2>/dev/null || true
            chmod +x /usr/local/bin/slowdns 2>/dev/null || true

            # Buat systemd service
            cat > /etc/systemd/system/slowdns.service << 'EOF'
[Unit]
Description=SlowDNS Tunnel
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/slowdns -server
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
            systemctl daemon-reload
            echo -e "${GREEN}✔ SlowDNS terinstall!${NC}"
            ;;
        2)
            systemctl start slowdns && \
                echo -e "${GREEN}✔ SlowDNS started!${NC}" || \
                echo -e "${RED}Gagal start SlowDNS!${NC}"
            ;;
        3)
            systemctl stop slowdns && echo -e "${GREEN}✔ SlowDNS stopped!${NC}"
            ;;
        4)
            systemctl status slowdns --no-pager
            ;;
        x|X) features_menu; return ;;
    esac
    echo -ne " ${YELLOW}[Enter] Kembali...${NC}"; read -r
    feature_slowdns
}

# ══════════════════════════════════════════
# 20. SET AUTO UPDATE
# ══════════════════════════════════════════
feature_auto_update() {
    clear
    echo -e "${CYAN}${BOLD}━━━━━━━━━━ SET AUTO UPDATE ━━━━━━━━━━${NC}"
    echo ""
    echo -e " ${GREEN}1.)${NC} Enable auto update"
    echo -e " ${GREEN}2.)${NC} Disable auto update"
    echo -e " ${GREEN}3.)${NC} Update sekarang"
    echo -e " ${RED}x.)${NC} Kembali"
    echo -ne " Pilihan: "; read -r OPT

    case "$OPT" in
        1)
            echo -ne " Interval update (jam, default 24): "; read -r INTERVAL
            INTERVAL=${INTERVAL:-24}
            (crontab -l 2>/dev/null | grep -v "skynet-autoupdate"; \
             echo "0 */$INTERVAL * * * /opt/skynet/core/update.sh >> /opt/skynet/logs/update.log 2>&1 # skynet-autoupdate") | crontab -
            sqlite3 "$DATABASE" "UPDATE settings SET value='enabled' WHERE key='auto_update'" 2>/dev/null || \
                sqlite3 "$DATABASE" "INSERT OR IGNORE INTO settings (key,value) VALUES ('auto_update','enabled')"
            echo -e "${GREEN}✔ Auto update enabled (setiap $INTERVAL jam)${NC}"
            ;;
        2)
            crontab -l 2>/dev/null | grep -v "skynet-autoupdate" | crontab -
            echo -e "${GREEN}✔ Auto update disabled!${NC}"
            ;;
        3)
            echo -e "${YELLOW}Update Xray ke versi terbaru...${NC}"
            bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
            systemctl restart xray-skynet
            echo -e "${GREEN}✔ Update selesai!${NC}"
            ;;
        x|X) features_menu; return ;;
    esac
    echo -ne " ${YELLOW}[Enter] Kembali...${NC}"; read -r
    feature_auto_update
}

# ══════════════════════════════════════════
# 21. INFORMATION SYSTEM
# ══════════════════════════════════════════
feature_system_info() {
    clear
    echo -e "${CYAN}${BOLD}━━━━━━━━━━ INFORMATION SYSTEM ━━━━━━━━━━${NC}"
    echo ""
    OS=$(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)
    KERNEL=$(uname -r)
    RAM_TOTAL=$(free -m | awk 'NR==2{print $2}')
    RAM_USED=$(free -m | awk 'NR==2{print $3}')
    DISK_TOTAL=$(df -h / | awk 'NR==2{print $2}')
    DISK_USED=$(df -h / | awk 'NR==2{print $3}')
    DISK_FREE=$(df -h / | awk 'NR==2{print $4}')
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    UPTIME_VAL=$(uptime -p)
    IP_ADDR=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    DOMAIN=$(sqlite3 "$DATABASE" "SELECT value FROM settings WHERE key='domain'")
    VERSION=$(sqlite3 "$DATABASE" "SELECT value FROM settings WHERE key='version'")
    XRAY_VER=$(xray version 2>/dev/null | head -1 || echo "Unknown")

    echo -e " ${YELLOW}OS         :${NC} $OS"
    echo -e " ${YELLOW}Kernel     :${NC} $KERNEL"
    echo -e " ${YELLOW}RAM        :${NC} ${RAM_USED}MB / ${RAM_TOTAL}MB"
    echo -e " ${YELLOW}Disk       :${NC} Used: $DISK_USED | Free: $DISK_FREE | Total: $DISK_TOTAL"
    echo -e " ${YELLOW}CPU Usage  :${NC} ${CPU_USAGE}%"
    echo -e " ${YELLOW}Uptime     :${NC} $UPTIME_VAL"
    echo -e " ${YELLOW}IP Publik  :${NC} $IP_ADDR"
    echo -e " ${YELLOW}Domain     :${NC} $DOMAIN"
    echo -e " ${YELLOW}Versi Script:${NC} $VERSION"
    echo -e " ${YELLOW}Xray Core  :${NC} $XRAY_VER"
    echo ""
    echo -ne " ${YELLOW}[Enter] Kembali...${NC}"; read -r
    features_menu
}

# ══════════════════════════════════════════
# MENU FEATURES UTAMA
# ══════════════════════════════════════════
features_menu() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "────────────────────────────────────────────────────────────"
    echo "                        FEATURES                            "
    echo "────────────────────────────────────────────────────────────"
    echo -e "${NC}"
    echo -e " ${GREEN} 1.)${NC}  Check Bandwidth"
    echo -e " ${GREEN} 2.)${NC}  Set Date Auto Reboot"
    echo -e " ${GREEN} 3.)${NC}  Reboot VPS"
    echo -e " ${GREEN} 4.)${NC}  Speed VPS"
    echo -e " ${GREEN} 5.)${NC}  Change Dropbear Version"
    echo -e " ${GREEN} 6.)${NC}  Check All Service"
    echo ""
    echo -e "${CYAN}────────────────────────────────────────────"
    echo "                  BOT TELEGRAM"
    echo "────────────────────────────────────────────"
    echo -e "${NC}"
    echo -e " ${GREEN} 7.)${NC}  Setup BOT"
    echo ""
    echo -e "${CYAN}────────────────────────────────────────────"
    echo "               BACKUP & RESTORE"
    echo "────────────────────────────────────────────"
    echo -e "${NC}"
    echo -e " ${GREEN} 8.)${NC}  Backup Configuration VPS"
    echo -e " ${GREEN} 9.)${NC}  Restore Configuration VPS"
    echo ""
    echo -e "${CYAN}────────────────────────────────────────────"
    echo "                  CLOUDFLARE"
    echo "────────────────────────────────────────────"
    echo -e "${NC}"
    echo -e " ${GREEN}10.)${NC}  Manages Domain Cloudflare"
    echo -e " ${GREEN}11.)${NC}  WARP Cloudflare"
    echo ""
    echo -e "${CYAN}────────────────────────────────────────────"
    echo "            ROUTING XRAY/V2RAY"
    echo "────────────────────────────────────────────"
    echo -e "${NC}"
    echo -e " ${GREEN}12.)${NC}  Outbounds Routing"
    echo -e " ${GREEN}13.)${NC}  Rules Routing"
    echo -e " ${GREEN}14.)${NC}  Check Config Routing"
    echo ""
    echo -e "${CYAN}────────────────────────────────────────────${NC}"
    echo ""
    echo -e " ${GREEN}15.)${NC}  Start/Stop Service"
    echo -e " ${GREEN}16.)${NC}  Security SYN ETC"
    echo -e " ${GREEN}17.)${NC}  Change Domain VPS"
    echo -e " ${GREEN}18.)${NC}  Change Banner & Response"
    echo -e " ${GREEN}19.)${NC}  SlowDNS"
    echo -e " ${GREEN}20.)${NC}  Set Auto Update"
    echo -e " ${GREEN}21.)${NC}  Information System"
    echo ""
    echo -e "${CYAN}────────────────────────────────────────────${NC}"
    echo ""
    echo -e " ${YELLOW}22.)${NC}  Back to Menu"
    echo -e " ${RED}  x.)${NC}  Exit"
    echo ""
    echo -ne " ${YELLOW}Pilihan [1-22/x]:${NC} "; read -r choice

    case "$choice" in
        1)  feature_bandwidth ;;
        2)  feature_auto_reboot ;;
        3)  feature_reboot_vps ;;
        4)  feature_speedtest ;;
        5)  feature_change_dropbear ;;
        6)  feature_check_services ;;
        7)  feature_setup_bot ;;
        8)  feature_backup ;;
        9)  feature_restore ;;
        10) feature_cloudflare_domain ;;
        11) feature_cloudflare_warp ;;
        12) feature_outbounds_routing ;;
        13) feature_rules_routing ;;
        14) feature_check_config ;;
        15) feature_start_stop_service ;;
        16) feature_security_syn ;;
        17) feature_change_domain ;;
        18) feature_change_banner ;;
        19) feature_slowdns ;;
        20) feature_auto_update ;;
        21) feature_system_info ;;
        22) source /opt/skynet/menu.sh; show_main_menu ;;
        x|X) clear; exit 0 ;;
        *) echo -e "${RED}Pilihan tidak valid!${NC}"; sleep 1; features_menu ;;
    esac
}
