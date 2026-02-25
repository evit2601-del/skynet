# 🚀 SKYNET TUNNELING — Panduan Lengkap

## Persyaratan
- Ubuntu 20.04 / 22.04 / 24.04
- Domain yang sudah pointing ke IP VPS
- Akses root

## Instalasi

```bash
git clone https://github.com/yourrepo/skynet.git /opt/skynet
cd /opt/skynet
chmod +x install.sh
bash install.sh
```

## Setelah Install

```bash
# Buka panel menu
menu

# Atau langsung
bash /opt/skynet/menu.sh
```

## Port yang Digunakan

| Service     | Port     |
|-------------|----------|
| SSH         | 22, 2222 |
| Dropbear    | 442, 109 |
| Stunnel SSH | 777      |
| HTTPS/TLS   | 443      |
| HTTP        | 80       |
| BadVPN UDP  | 7300     |
| REST API    | 8080 (lokal) |

## API Usage

```bash
# Contoh: Create SSH user via API
curl -X POST http://localhost:8080/create-user \
  -H "X-API-Key: YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"username":"testuser","password":"pass123","days":30,"ip_limit":2,"quota_gb":10}'

# Check user
curl -G http://localhost:8080/check-user \
  -H "X-API-Key: YOUR_API_KEY" \
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
