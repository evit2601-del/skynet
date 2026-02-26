#!/bin/bash
# SKYNET - Quick Runner Script
# Shortcut untuk menjalankan berbagai tools

case "${1:-}" in
    install|i)
        bash install.sh
        ;;
    fix|f)
        bash fix-xray.sh
        ;;
    check|c)
        bash check.sh
        ;;
    menu|m)
        bash menu.sh
        ;;
    manual|setup|s)
        bash manual-setup.sh
        ;;
    quick|q)
        bash quick-install.sh
        ;;
    *)
        echo "SKYNET Quick Runner"
        echo ""
        echo "Usage: bash r [command]"
        echo ""
        echo "Commands:"
        echo "  i, install  - Run full installer"
        echo "  f, fix      - Fix Xray service"
        echo "  c, check    - Check installation"
        echo "  m, menu     - Open menu"
        echo "  s, setup    - Manual setup wizard"
        echo "  q, quick    - Quick installer"
        echo ""
        echo "Examples:"
        echo "  bash r fix"
        echo "  bash r check"
        echo "  bash r menu"
        ;;
esac

  --data-urlencode "username=testuser" \
  --data-urlencode "user_type=ssh"

# Server status
curl http://localhost:8080/server-status \
  -H "X-API-Key: YOUR_API_KEY"
```

## Struktur File

```
/opt/skynet/
├── install.sh          # Installer utama
├── menu.sh             # Menu terminal
├── api/app.py          # REST API (FastAPI)
├── bot/bot.py          # Telegram Bot
├── core/
│   ├── ssh.sh          # Manajemen SSH
│   ├── xray.sh         # Manajemen Xray
│   ├── monitor.sh      # Monitoring daemon
│   ├── features.sh     # Menu FEATURES
│   └── update.sh       # Auto update
├── config/
│   ├── xray.json       # Template Xray config
│   └── settings.conf   # Konfigurasi global
├── database/users.db   # SQLite database
├── logs/               # Log files
└── backup/             # Backup files
```

## Keamanan

- API Key otomatis di-generate saat install
- Semua input divalidasi
- UFW + Fail2Ban aktif
- Tidak ada hardcoded password
- Log lengkap di `/opt/skynet/logs/`
