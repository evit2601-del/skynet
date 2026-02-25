#!/bin/bash
# ============================================================
# SKYNET — AUTO UPDATE SCRIPT
# ============================================================

source /opt/skynet/config/settings.conf 2>/dev/null

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /opt/skynet/logs/update.log; }

log "=== SKYNET AUTO UPDATE DIMULAI ==="

# Update Xray core ke versi terbaru
log "Update Xray-core..."
if bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install 2>/dev/null; then
    systemctl restart xray-skynet
    log "Xray berhasil diupdate: $(xray version | head -1)"
else
    log "WARN: Xray update gagal"
fi

# Update pip packages
log "Update Python packages..."
pip3 install --upgrade \
    fastapi uvicorn python-telegram-bot \
    aiohttp aiosqlite pydantic httpx \
    > /dev/null 2>&1 && log "Python packages updated" || log "WARN: pip update gagal"

# Reload semua service
log "Reload services..."
for svc in xray-skynet nginx skynet-api skynet-bot; do
    systemctl is-active "$svc" &>/dev/null && systemctl reload "$svc" 2>/dev/null || true
done

log "=== AUTO UPDATE SELESAI ==="
