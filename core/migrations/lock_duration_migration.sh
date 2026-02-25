#!/bin/bash
set -e

DB="/opt/skynet/database/users.db"

has_col() {
  local table="$1"
  local col="$2"
  sqlite3 "$DB" "PRAGMA table_info($table);" | awk -F'|' '{print $2}' | grep -qx "$col"
}

if ! has_col "ssh_users" "locked_until"; then
  sqlite3 "$DB" "ALTER TABLE ssh_users ADD COLUMN locked_until TEXT;"
  echo "OK: added ssh_users.locked_until"
else
  echo "SKIP: ssh_users.locked_until already exists"
fi

if ! has_col "xray_users" "locked_until"; then
  sqlite3 "$DB" "ALTER TABLE xray_users ADD COLUMN locked_until TEXT;"
  echo "OK: added xray_users.locked_until"
else
  echo "SKIP: xray_users.locked_until already exists"
fi

sqlite3 "$DB" "INSERT OR IGNORE INTO settings(key,value) VALUES('lock_duration_seconds','3600');"
echo "OK: settings.lock_duration_seconds ready"
