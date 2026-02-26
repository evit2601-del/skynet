#!/bin/bash
# SKYNET - Quick Runner Script
# Shortcut untuk menjalankan berbagai tools

GREEN='\033[0;32m'
DIM='\033[2m'
NC='\033[0m'

case "${1:-}" in
    install|i)
        bash install.sh
        ;;
    fix|f)
        bash fix-xray.sh
        ;;
    autofix|auto|a)
        bash autofix-xray.sh
        ;;
    diagnose|diag|d)
        bash diagnose-xray.sh
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
    help|h)
        bash help.sh
        ;;
    *)
        echo "SKYNET Quick Runner"
        echo ""
        echo "Usage: bash r [command]"
        echo ""
        echo "Commands:"
        echo "  a, autofix    - Auto-fix Xray issues (RECOMMENDED)"
        echo "  d, diagnose   - Diagnose Xray problems"
        echo "  f, fix        - Fix Xray service"
        echo "  c, check      - Check installation"
        echo "  h, help       - Show help guide"
        echo "  m, menu       - Open menu"
        echo "  s, setup      - Manual setup wizard"
        echo "  i, install    - Run full installer"
        echo "  q, quick      - Quick installer"
        echo ""
        echo -e "${GREEN}Common workflows:${NC}"
        echo -e "  ${DIM}If Xray is STOPPED:${NC}"
        echo "    bash r autofix     # Try this first"
        echo "    bash r diagnose    # If autofix fails"
        echo ""
        echo -e "  ${DIM}For help:${NC}"
        echo "    bash r help        # Show quick guide"
        echo ""
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
