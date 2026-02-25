#!/bin/bash
# SKYNET — XRAY Management (minimal)
source /opt/skynet/config/settings.conf 2>/dev/null

XRAY_CONFIG="/usr/local/etc/xray/config.json"

generate_uuid() { cat /proc/sys/kernel/random/uuid; }

reload_xray() { systemctl restart xray-skynet; }

xray_menu() {
  local PROTO="$1"
  clear
  echo "XRAY MENU $PROTO"
  echo "Gunakan API/menu lain untuk create/delete (repo version minimal)."
  read -rp "Enter..."
}
