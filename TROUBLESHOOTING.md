# SKYNET - Quick Troubleshooting Guide

## Service "xray-skynet.service could not be found"

### Penyebab:
1. Installer belum selesai/gagal
2. Service file tidak terbuat
3. Systemd belum reload

### Solusi Cepat:

```bash
cd ~/skynet

# Opsi 1: Jalankan Fix Script (RECOMMENDED)
chmod +x fix-xray.sh
bash fix-xray.sh

# Opsi 2: Manual
bash manual-setup.sh
# Pilih: 1. Install Xray + Create Service
```

### Verifikasi:

```bash
# Cek service ada
systemctl status xray-skynet

# Cek xray binary
which xray
xray version

# Cek config
xray -test -config /usr/local/etc/xray/config.json

# Cek log
journalctl -u xray-skynet -n 50
```

---

## Xray Status: STOPPED (Service ada tapi tidak jalan) ⚠️

**Ini adalah masalah paling umum!**

### Solusi Tercepat - Auto Fix:

```bash
cd ~/skynet
chmod +x autofix-xray.sh
bash autofix-xray.sh
```

Script ini akan otomatis:
1. Test config validity
2. Regenerate config jika error
3. Kill conflicting processes
4. Fix file permissions
5. Restart service
6. Show hasil verifikasi

### Jika Auto-Fix Gagal - Run Diagnostic:

```bash
bash diagnose-xray.sh
```

Diagnostic tool akan:
- Cek setiap komponen Xray
- Tampilkan error spesifik
- Berikan solusi untuk setiap masalah
- Attempt to start service
- Show detail logs

### Manual Troubleshooting:

#### 1. Cek Log Error Detail:
```bash
# Lihat 50 baris terakhir
journalctl -u xray-skynet -n 50 --no-pager

# Follow live log
journalctl -u xray-skynet -f

# Cek error log Xray
tail -f /var/log/xray/error.log
```

#### 2. Test Config Validity:
```bash
xray -test -config /usr/local/etc/xray/config.json
```

Jika ada error:
```bash
# Regenerate dari template
cp /opt/skynet/config/xray.json /usr/local/etc/xray/config.json
systemctl restart xray-skynet
```

#### 3. Check Port Conflicts:
```bash
# Cek port yang dibutuhkan
netstat -tulpn | grep '10086\|10087\|10088'

# Atau dengan ss
ss -tulpn | grep '10086\|10087\|10088'
```

Jika port sudah digunakan:
```bash
# Lihat process ID
netstat -tulpn | grep 10086

# Kill process (ganti <PID> dengan nomor yang muncul)
kill -9 <PID>

# Restart xray
systemctl restart xray-skynet
```

#### 4. Fix Permissions:
```bash
chmod +x /usr/local/bin/xray
chown root:root /usr/local/etc/xray/config.json
chmod 644 /usr/local/etc/xray/config.json
mkdir -p /var/log/xray
chmod 755 /var/log/xray
systemctl restart xray-skynet
```

#### 5. Try Manual Start (untuk debug):
```bash
# Stop service dulu
systemctl stop xray-skynet

# Run manual (akan tampilkan error langsung)
xray run -config /usr/local/etc/xray/config.json

# Tekan Ctrl+C untuk stop
# Fix error yang muncul, lalu:
systemctl start xray-skynet
```

### Common Error Messages & Fixes:

#### Error: "failed to parse config"
```bash
# Config file corrupt atau format salah
cp /opt/skynet/config/xray.json /usr/local/etc/xray/config.json
systemctl restart xray-skynet
```

#### Error: "address already in use"
```bash
# Port conflict
pkill -9 xray
systemctl restart xray-skynet
```

#### Error: "permission denied"
```bash
# Permission issue
chmod +x /usr/local/bin/xray
systemctl restart xray-skynet
```

#### Error: "no such file or directory"
```bash
# Missing files
bash fix-xray.sh
```

---

## Service Berjalan Tapi Status OFF

### Cek Log Error:
```bash
journalctl -u xray-skynet -n 100 --no-pager
```

### Common Errors:

#### 1. Config Error
```bash
# Test config
xray -test -config /usr/local/etc/xray/config.json

# Jika error, regenerate:
cp /opt/skynet/config/xray.json /usr/local/etc/xray/config.json
systemctl restart xray-skynet
```

#### 2. Port Already in Use
```bash
# Cek port
netstat -tulpn | grep '10086\|10087\|10088'

# Kill process jika ada
kill -9 <PID>
systemctl restart xray-skynet
```

#### 3. Permission Issue
```bash
chmod +x /usr/local/bin/xray
chown root:root /usr/local/etc/xray/config.json
systemctl restart xray-skynet
```

---

## Instalasi Gagal/Tidak Selesai

### Restart Instalasi:
```bash
cd ~/skynet

# Bersihkan partial install
rm -rf /opt/skynet/*
rm -f /etc/systemd/system/xray-skynet.service
rm -f /etc/systemd/system/skynet-*.service

# Jalankan ulang
bash install.sh
```

### Manual Step-by-Step:
```bash
bash manual-setup.sh
```

Ikuti menu:
1. Install Xray + Create Service
2. Setup Database
3. Deploy Scripts
4. Setup Nginx (jika perlu SSL)
6. Setup All Services
7. Check Installation

---

## SSL/Certbot Error

### Domain Belum Pointing:
```bash
# Cek DNS
dig +short vpn.yourdomain.com

# Bandingkan dengan IP server
curl ifconfig.me

# Harus sama!
```

### Port 80 Tidak Terbuka:
```bash
# Cek firewall
ufw status
ufw allow 80/tcp
ufw allow 443/tcp

# Test nginx
systemctl stop nginx
python3 -m http.server 80

# Dari komputer lain:
# curl http://your-server-ip
```

### Re-install SSL:
```bash
systemctl stop nginx
certbot certonly --standalone -d vpn.yourdomain.com --email your@email.com
systemctl start nginx
```

---

## Database Error

### Check Database:
```bash
# Cek file ada
ls -lah /opt/skynet/database/users.db

# Cek tables
sqlite3 /opt/skynet/database/users.db ".tables"

# Cek data
sqlite3 /opt/skynet/database/users.db "SELECT * FROM settings;"
```

### Re-create Database:
```bash
# Backup dulu jika ada data penting
cp /opt/skynet/database/users.db /opt/skynet/database/users.db.backup

# Re-init
bash manual-setup.sh
# Pilih: 2. Setup Database
```

---

## Menu Command Not Found

```bash
# Create symlink
ln -sf /opt/skynet/menu.sh /usr/local/bin/menu
chmod +x /usr/local/bin/menu

# Test
menu
```

---

## API Service Error

### Check Python Dependencies:
```bash
pip3 list | grep -E 'fastapi|uvicorn|aiosqlite'

# Install jika tidak ada
pip3 install fastapi uvicorn[standard] aiosqlite pydantic
```

### Check Service:
```bash
systemctl status skynet-api
journalctl -u skynet-api -n 50
```

### Test API Manually:
```bash
cd /opt/skynet/api
python3 -m uvicorn app:app --host 127.0.0.1 --port 8080
```

---

## Complete Reset (CAUTION: Data Loss!)

```bash
# Stop all services
systemctl stop xray-skynet skynet-api skynet-bot nginx

# Remove everything
rm -rf /opt/skynet
rm -f /etc/systemd/system/xray-skynet.service
rm -f /etc/systemd/system/skynet-*.service
rm -rf /usr/local/etc/xray
rm -f /usr/local/bin/menu

# Reload systemd
systemctl daemon-reload

# Fresh install
cd ~/skynet
bash install.sh
```

---

## Quick Command Reference

```bash
# Check all services
systemctl status xray-skynet skynet-api ssh nginx

# Restart all
systemctl restart xray-skynet skynet-api nginx

# View logs
journalctl -u xray-skynet -f      # Follow Xray log
journalctl -u skynet-api -f       # Follow API log
tail -f /var/log/xray/error.log   # Xray error log

# Test configs
xray -test -config /usr/local/etc/xray/config.json
nginx -t

# Check ports
netstat -tulpn | grep LISTEN
ss -tulpn | grep LISTEN

# Check disk space
df -h

# Check memory
free -m

# Check processes
ps aux | grep xray
ps aux | grep uvicorn
```

---

## Dapatkan Support

1. Run diagnostic:
   ```bash
   bash check.sh > /tmp/diagnostic.txt
   ```

2. Get logs:
   ```bash
   journalctl -u xray-skynet -n 100 > /tmp/xray.log
   journalctl -u skynet-api -n 100 > /tmp/api.log
   ```

3. Share output untuk debugging

---

## Prevention Tips

1. **Selalu cek domain pointing** sebelum install
2. **Backup API key** yang muncul saat install
3. **Gunakan VPS minimal 1GB RAM**
4. **Pastikan port 80, 443 terbuka** untuk SSL
5. **Run `bash check.sh`** setelah install untuk verify
