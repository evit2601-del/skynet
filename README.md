# 🚀 SKYNET TUNNELING — Panduan Lengkap

> **⚠️ Service not found?** Lihat [QUICKSTART.md](QUICKSTART.md) untuk solusi cepat!

---

## 🔥 Quick Fix (Jika ada error)

```bash
# Error: "xray-skynet.service could not be found"
bash fix-xray.sh

# Verifikasi instalasi
bash check.sh

# Akses menu
menu
```

---

## Persyaratan
- Ubuntu 20.04 / 22.04 / 24.04
- Domain yang sudah pointing ke IP VPS
- Akses root
- Port 80 dan 443 harus terbuka (untuk SSL)

## Instalasi

```bash
# Download dan extract
cd /root
git clone https://github.com/yourusername/skynet.git
cd skynet

# Jalankan installer
chmod +x install.sh
bash install.sh
```

Selama instalasi, Anda akan diminta:
1. **Domain VPS** (contoh: vpn.domain.com)
2. **Email untuk SSL** (untuk Let's Encrypt)

### Jika Instalasi Gagal

```bash
# Gunakan quick fix untuk Xray service
bash fix-xray.sh

# Atau setup manual step-by-step
bash manual-setup.sh

# Verifikasi instalasi
bash check.sh
```

## Setelah Install

```bash
# Buka panel menu
menu

# Atau langsung
bash /opt/skynet/menu.sh
```

## Troubleshooting

> **📖 Lihat [TROUBLESHOOTING.md](TROUBLESHOOTING.md) untuk panduan lengkap!**

### Service Not Found Error

Jika `systemctl status xray-skynet` menunjukkan "could not be found":

```bash
# Quick fix
chmod +x fix-xray.sh
bash fix-xray.sh

# Atau manual setup
bash manual-setup.sh
```

### Xray Service OFF/Not Running

```bash
# Cek status
systemctl status xray-skynet

# Cek log error
journalctl -u xray-skynet -n 50

# Test konfigurasi
xray -test -config /usr/local/etc/xray/config.json

# Restart
systemctl restart xray-skynet
```

### SSL Error

```bash
# Pastikan domain sudah pointing ke IP server
ping vpn.domain.com

# Ulangi install SSL
certbot certonly --standalone -d vpn.domain.com

# Restart nginx
systemctl restart nginx
```

### Database Error

```bash
# Cek database
sqlite3 /opt/skynet/database/users.db "SELECT * FROM settings;"

# Re-init database jika perlu
cd /opt/skynet
bash install.sh  # Akan detect existing installation
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
