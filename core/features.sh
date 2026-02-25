#!/bin/bash
# ============================================================
# SKYNET — MONITORING & LIMIT ENGINE
# Berjalan sebagai daemon / timer setiap 1 menit
# ============================================================

source /opt/skynet/config/settings.conf 2>/dev/null

LOG_FILE="$LOG_DIR/monitor.log"

log_monitor() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# ── Cek & auto-delete akun expired
check_expired_accounts() {
    TODAY=$(date +"%Y-%m-%d")

    # SSH expired
    sqlite3 "$DATABASE" \
        "SELECT username FROM ssh_users WHERE expired_at < '$TODAY' AND status != 'expired'" | \
    while read -r USERNAME; do
        passwd -l "$USERNAME" 2>/dev/null || true
        pkill -u "$USERNAME" 2>/dev/null || true
        sqlite3 "$DATABASE" "UPDATE ssh_users SET status='expired' WHERE username='$USERNAME'"
        log_monitor "EXPIRED: SSH user $USERNAME"
    done

    # Xray expired
    sqlite3 "$DATABASE" \
        "SELECT username, uuid, protocol FROM xray_users WHERE expired_at < '$TODAY' AND status != 'expired'" | \
    while IFS='|' read -r USERNAME UUID PROTO; do
        # Remove dari xray config
        source /opt/skynet/core/xray.sh
        remove_xray_client "$PROTO" "$UUID"
        sqlite3 "$DATABASE" \
            "UPDATE xray_users SET status='expired' WHERE username='$USERNAME' AND protocol='$PROTO'"
        log_monitor "EXPIRED: Xray $PROTO user $USERNAME"
    done

    # Reload Xray jika ada perubahan
    systemctl reload xray-skynet 2>/dev/null || true
}

# ── Cek quota SSH (via iptables accounting)
check_ssh_quota() {
    sqlite3 "$DATABASE" \
        "SELECT username, quota_gb, quota_used FROM ssh_users WHERE status='active' AND quota_gb > 0" | \
    while IFS='|' read -r USERNAME QUOTA_GB QUOTA_USED; do
        if (( $(echo "$QUOTA_USED >= $QUOTA_GB" | bc -l) )); then
            passwd -l "$USERNAME" 2>/dev/null || true
            pkill -u "$USERNAME" 2>/dev/null || true
            sqlite3 "$DATABASE" "UPDATE ssh_users SET status='quota_exceeded' WHERE username='$USERNAME'"
            sqlite3 "$DATABASE" \
                "INSERT INTO violation_log (username, violation_type, description) \
                 VALUES ('$USERNAME', 'quota_exceeded', 'SSH quota habis: ${QUOTA_USED}GB/${QUOTA_GB}GB')"
            log_monitor "QUOTA: SSH user $USERNAME quota habis"
        fi
    done
}

# ── Cek quota Xray
check_xray_quota() {
    sqlite3 "$DATABASE" \
        "SELECT username, uuid, protocol, quota_gb, quota_used FROM xray_users WHERE status='active' AND quota_gb > 0" | \
    while IFS='|' read -r USERNAME UUID PROTO QUOTA_GB QUOTA_USED; do
        if (( $(echo "$QUOTA_USED >= $QUOTA_GB" | bc -l) )); then
            source /opt/skynet/core/xray.sh
            remove_xray_client "$PROTO" "$UUID"
            sqlite3 "$DATABASE" \
                "UPDATE xray_users SET status='quota_exceeded' WHERE username='$USERNAME' AND protocol='$PROTO'"
            sqlite3 "$DATABASE" \
                "INSERT INTO violation_log (username, violation_type, description) \
                 VALUES ('$USERNAME', 'quota_exceeded', 'Xray $PROTO quota habis: ${QUOTA_USED}GB/${QUOTA_GB}GB')"
            log_monitor "QUOTA: Xray $PROTO user $USERNAME quota habis"
        fi
    done
}

# ── Cek multi login SSH
check_ssh_multi_login() {
    sqlite3 "$DATABASE" \
        "SELECT username, ip_limit FROM ssh_users WHERE status='active'" | \
    while IFS='|' read -r USERNAME IP_LIMIT; do
        # Hitung IP aktif unik
        ACTIVE_COUNT=$(who | grep "^$USERNAME " | awk '{print $5}' | sort -u | wc -l)
        if [[ "$ACTIVE_COUNT" -gt "$IP_LIMIT" ]]; then
            pkill -u "$USERNAME" 2>/dev/null || true
            sqlite3 "$DATABASE" \
                "INSERT INTO violation_log (username, violation_type, description) \
                 VALUES ('$USERNAME', 'multi_login', 'SSH multi login: $ACTIVE_COUNT/$IP_LIMIT')"
            log_monitor "MULTI_LOGIN: SSH user $USERNAME ($ACTIVE_COUNT/$IP_LIMIT IP)"
        fi
    done
}

# ── Auto restart service yang mati
auto_restart_services() {
    local SERVICES=("xray-skynet" "nginx" "skynet-api" "skynet-bot" "fail2ban")
    for SVC in "${SERVICES[@]}"; do
        if ! systemctl is-active "$SVC" &>/dev/null; then
            systemctl restart "$SVC" 2>/dev/null || true
            log_monitor "RESTART: Service $SVC direstart otomatis"
        fi
    done
}

# ── Update traffic statistics dari iptables
update_traffic_stats() {
    # Gunakan iptables accounting per user
    sqlite3 "$DATABASE" "SELECT username FROM ssh_users WHERE status='active'" | \
    while read -r USERNAME; do
        # Ambil bytes dari iptables (jika rule per user ada)
        BYTES=$(iptables -L OUTPUT -v -x -n 2>/dev/null | grep "$USERNAME" | awk '{print $2}' || echo 0)
        if [[ "$BYTES" -gt 0 ]]; then
            QUOTA_USED_GB=$(echo "scale=4; $BYTES / 1073741824" | bc)
            sqlite3 "$DATABASE" \
                "UPDATE ssh_users SET quota_used=quota_used+$QUOTA_USED_GB WHERE username='$USERNAME'"
        fi
    done
}

# ── Main daemon loop
run_daemon() {
    log_monitor "Monitor daemon started"
    while true; do
        check_expired_accounts
        check_ssh_quota
        check_xray_quota
        check_ssh_multi_login
        auto_restart_services
        update_traffic_stats
        sleep 60
    done
}

# ── Entry point
case "${1:-daemon}" in
    daemon)  run_daemon ;;
    once)
        check_expired_accounts
        check_ssh_quota
        check_xray_quota
        check_ssh_multi_login
        auto_restart_services
        ;;
esac
