#!/bin/bash
# ============================================================
# SKYNET — MONITORING & LIMIT ENGINE
# - Multi login -> LOCK sampai locked_until
# - Auto unlock setelah locked_until lewat
# - Loop tiap N detik (monitor_interval) default 60
# ============================================================

source /opt/skynet/config/settings.conf 2>/dev/null

LOG_FILE="${LOG_DIR:-/opt/skynet/logs}/monitor.log"
DATABASE="${DATABASE:-/opt/skynet/database/users.db}"

log_monitor() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

get_monitor_interval() {
    local I
    I=$(sqlite3 "$DATABASE" "SELECT value FROM settings WHERE key='monitor_interval'" 2>/dev/null)
    echo "${I:-60}"
}

get_lock_duration_seconds() {
    local D
    D=$(sqlite3 "$DATABASE" "SELECT value FROM settings WHERE key='lock_duration_seconds'" 2>/dev/null)
    echo "${D:-3600}"
}

_xray_remove_client() {
    local PROTO=$1
    local UUID=$2
    local TAG
    case "$PROTO" in
        vmess) TAG="vmess-ws" ;;
        vless) TAG="vless-ws" ;;
        trojan) TAG="trojan-ws" ;;
        *) return ;;
    esac

    python3 << EOF
import json
p="/usr/local/etc/xray/config.json"
with open(p,"r") as f:
    c=json.load(f)
for inbound in c.get("inbounds",[]):
    if inbound.get("tag")== "$TAG":
        clients=inbound.get("settings",{}).get("clients",[])
        inbound["settings"]["clients"]=[x for x in clients if x.get("id")!="$UUID" and x.get("password")!="$UUID"]
        break
with open(p,"w") as f:
    json.dump(c,f,indent=2)
EOF
}

_xray_add_client() {
    local PROTO=$1
    local UUID=$2
    local USERNAME=$3
    local TAG
    case "$PROTO" in
        vmess) TAG="vmess-ws" ;;
        vless) TAG="vless-ws" ;;
        trojan) TAG="trojan-ws" ;;
        *) return ;;
    esac

    python3 << EOF
import json
p="/usr/local/etc/xray/config.json"
with open(p,"r") as f:
    c=json.load(f)
for inbound in c.get("inbounds",[]):
    if inbound.get("tag")== "$TAG":
        s=inbound.setdefault("settings",{})
        clients=s.setdefault("clients",[])
        if any(x.get("id")== "$UUID" or x.get("password")== "$UUID" for x in clients):
            break
        if "$PROTO" == "trojan":
            clients.append({"password":"$UUID","email":"$USERNAME","level":0})
        elif "$PROTO" == "vless":
            clients.append({"id":"$UUID","email":"$USERNAME","level":0})
        else:
            clients.append({"id":"$UUID","alterId":0,"email":"$USERNAME","level":0,"security":"auto"})
        break
with open(p,"w") as f:
    json.dump(c,f,indent=2)
EOF
}

sync_xray_ip_tracking() {
    local XRAY_LOG="/var/log/xray/access.log"
    [[ ! -f "$XRAY_LOG" ]] && return

    sqlite3 "$DATABASE" \
      "UPDATE ip_tracking SET is_active=0, logout_at=datetime('now')
       WHERE protocol IN ('vmess','vless','trojan') AND is_active=1" 2>/dev/null || true

    tail -2000 "$XRAY_LOG" 2>/dev/null | grep "accepted" | while read -r LINE; do
        SRC_IP=$(echo "$LINE" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
        EMAIL=$(echo "$LINE" | grep -oP 'email: \K[^\s]+' 2>/dev/null | head -1)

        PROTO=""
        echo "$LINE" | grep -qi "vmess"  && PROTO="vmess"
        echo "$LINE" | grep -qi "vless"  && PROTO="vless"
        echo "$LINE" | grep -qi "trojan" && PROTO="trojan"

        [[ -z "$SRC_IP" || -z "$EMAIL" || -z "$PROTO" ]] && continue

        EXISTS=$(sqlite3 "$DATABASE" "SELECT COUNT(*) FROM xray_users WHERE username='$EMAIL' AND protocol='$PROTO' AND status='active';" 2>/dev/null || echo 0)
        [[ "$EXISTS" -lt 1 ]] && continue

        sqlite3 "$DATABASE" << EOF
INSERT INTO ip_tracking (username, ip_address, protocol, login_at, is_active)
SELECT '$EMAIL', '$SRC_IP', '$PROTO', datetime('now'), 1
WHERE NOT EXISTS (
  SELECT 1 FROM ip_tracking WHERE username='$EMAIL' AND ip_address='$SRC_IP' AND protocol='$PROTO' AND is_active=1
);
EOF
    done
}

auto_unlock_expired_locks() {
    local NOW
    NOW=$(date +"%Y-%m-%d %H:%M:%S")
    local XRAY_CHANGED=0

    while read -r USERNAME; do
        passwd -u "$USERNAME" 2>/dev/null || true
        sqlite3 "$DATABASE" "UPDATE ssh_users SET status='active', locked_until=NULL WHERE username='$USERNAME';"
        log_monitor "AUTO_UNLOCK: SSH $USERNAME"
    done < <(sqlite3 "$DATABASE" \
      "SELECT username FROM ssh_users WHERE status='locked' AND locked_until IS NOT NULL AND locked_until <= '$NOW'" 2>/dev/null)

    while IFS='|' read -r USERNAME UUID PROTO; do
        _xray_add_client "$PROTO" "$UUID" "$USERNAME"
        sqlite3 "$DATABASE" "UPDATE xray_users SET status='active', locked_until=NULL WHERE username='$USERNAME' AND protocol='$PROTO';"
        XRAY_CHANGED=1
        log_monitor "AUTO_UNLOCK: XRAY $PROTO $USERNAME"
    done < <(sqlite3 "$DATABASE" \
      "SELECT username, uuid, protocol FROM xray_users WHERE status='locked' AND locked_until IS NOT NULL AND locked_until <= '$NOW'" 2>/dev/null)

    [[ "$XRAY_CHANGED" -eq 1 ]] && systemctl restart xray-skynet 2>/dev/null || true
}

lock_ssh_user() {
    local USERNAME="$1"
    local REASON="$2"
    local LOCK_SEC LOCK_UNTIL
    LOCK_SEC=$(get_lock_duration_seconds)
    LOCK_UNTIL=$(date -d "+${LOCK_SEC} seconds" +"%Y-%m-%d %H:%M:%S")

    pkill -u "$USERNAME" 2>/dev/null || true
    passwd -l "$USERNAME" 2>/dev/null || true
    sqlite3 "$DATABASE" "UPDATE ssh_users SET status='locked', locked_until='$LOCK_UNTIL' WHERE username='$USERNAME';"
    sqlite3 "$DATABASE" "INSERT INTO violation_log(username,violation_type,description) VALUES('$USERNAME','multi_login','$REASON locked_until=$LOCK_UNTIL');" 2>/dev/null || true
    log_monitor "LOCKED: SSH $USERNAME until $LOCK_UNTIL | $REASON"
}

lock_xray_user() {
    local USERNAME="$1"
    local UUID="$2"
    local PROTO="$3"
    local REASON="$4"
    local LOCK_SEC LOCK_UNTIL
    LOCK_SEC=$(get_lock_duration_seconds)
    LOCK_UNTIL=$(date -d "+${LOCK_SEC} seconds" +"%Y-%m-%d %H:%M:%S")

    _xray_remove_client "$PROTO" "$UUID"
    sqlite3 "$DATABASE" "UPDATE xray_users SET status='locked', locked_until='$LOCK_UNTIL' WHERE username='$USERNAME' AND protocol='$PROTO';"
    sqlite3 "$DATABASE" "INSERT INTO violation_log(username,violation_type,description) VALUES('$USERNAME','multi_login','Xray $PROTO: $REASON locked_until=$LOCK_UNTIL');" 2>/dev/null || true
    systemctl restart xray-skynet 2>/dev/null || true
    log_monitor "LOCKED: XRAY $PROTO $USERNAME until $LOCK_UNTIL | $REASON"
}

check_ssh_multi_login() {
    sqlite3 "$DATABASE" "SELECT username, ip_limit FROM ssh_users WHERE status='active';" 2>/dev/null | \
    while IFS='|' read -r USERNAME IP_LIMIT; do
        [[ -z "$USERNAME" ]] && continue
        IP_LIMIT=${IP_LIMIT:-1}
        ACTIVE_COUNT=$(who | awk -v u="$USERNAME" '$1==u{print $5}' | sort -u | wc -l)
        if [[ "$ACTIVE_COUNT" -gt "$IP_LIMIT" ]]; then
            lock_ssh_user "$USERNAME" "SSH multi login ($ACTIVE_COUNT/$IP_LIMIT)"
        fi
    done
}

check_xray_multi_login() {
    sqlite3 "$DATABASE" "SELECT username, uuid, protocol, ip_limit FROM xray_users WHERE status='active';" 2>/dev/null | \
    while IFS='|' read -r USERNAME UUID PROTO IP_LIMIT; do
        [[ -z "$USERNAME" || -z "$UUID" || -z "$PROTO" ]] && continue
        IP_LIMIT=${IP_LIMIT:-1}
        CUR_IPS=$(sqlite3 "$DATABASE" "SELECT COUNT(DISTINCT ip_address) FROM ip_tracking WHERE username='$USERNAME' AND protocol='$PROTO' AND is_active=1;" 2>/dev/null || echo 0)
        if [[ "$CUR_IPS" -gt "$IP_LIMIT" ]]; then
            lock_xray_user "$USERNAME" "$UUID" "$PROTO" "Xray multi login ($CUR_IPS/$IP_LIMIT)"
        fi
    done
}

check_xray_quota() {
    local XRAY_CHANGED=0

    while IFS='|' read -r USERNAME UUID PROTO QUOTA_USED QUOTA_GB; do
        lock_xray_user "$USERNAME" "$UUID" "$PROTO" "quota habis (${QUOTA_USED}/${QUOTA_GB}GB)"
        XRAY_CHANGED=1
        log_monitor "QUOTA_LOCK: XRAY $PROTO $USERNAME quota habis (${QUOTA_USED}/${QUOTA_GB}GB)"
    done < <(sqlite3 "$DATABASE" \
      "SELECT username, uuid, protocol, quota_used, quota_gb FROM xray_users WHERE status='active' AND quota_gb > 0 AND quota_used >= quota_gb" 2>/dev/null)
}

run_daemon() {
    log_monitor "=== Monitor daemon started ==="
    while true; do
        INTERVAL=$(get_monitor_interval)
        [[ -z "$INTERVAL" ]] && INTERVAL=60
        auto_unlock_expired_locks
        sync_xray_ip_tracking
        check_xray_multi_login
        check_xray_quota
        check_ssh_multi_login
        sleep "$INTERVAL"
    done
}

case "${1:-daemon}" in
  daemon) run_daemon ;;
  once)
    auto_unlock_expired_locks
    sync_xray_ip_tracking
    check_xray_multi_login
    check_xray_quota
    check_ssh_multi_login
    ;;
esac
