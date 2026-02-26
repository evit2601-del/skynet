# 🚀 SKYNET Quick Start

## ⚡ Error: "Unit xray-skynet.service could not be found"

**Solusi 1-Menit:**

```bash
cd ~/skynet
chmod +x fix-xray.sh
bash fix-xray.sh
```

Script ini akan:
- ✅ Install/verify Xray binary
- ✅ Create systemd service file
- ✅ Reload daemon
- ✅ Start service
- ✅ Show status

---

## 🔴 Xray Status: STOPPED (Service ada tapi tidak jalan)

**Solusi Auto-Fix:**

```bash
cd ~/skynet
chmod +x autofix-xray.sh
bash autofix-xray.sh
```

Script ini otomatis:
- ✅ Cek & fix config
- ✅ Kill process yang conflict
- ✅ Fix permissions
- ✅ Restart service
- ✅ Verifikasi hasilnya

**Jika masih gagal, jalankan diagnostic:**

```bash
bash diagnose-xray.sh
```

Ini akan menunjukkan error detail dan solusi spesifik.

---

## 📋 Installation Checklist

Setelah run `fix-xray.sh`, verifikasi:

```bash
# 1. Xray service running
systemctl status xray-skynet
# Harus: active (running)

# 2. Check version
xray version

# 3. Test config
xray -test -config /usr/local/etc/xray/config.json
# Harus: Configuration OK

# 4. Verifikasi ports
netstat -tulpn | grep '10086\|10087\|10088'
# Harus ada 3 ports listening
```

---

## 🔧 If Fix Script Doesn't Work

### Manual Method:

```bash
# 1. Install Xray
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# 2. Create service file
cat > /etc/systemd/system/xray-skynet.service << 'EOF'
[Unit]
Description=SKYNET - Xray Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 3. Reload & start
systemctl daemon-reload
systemctl enable xray-skynet
systemctl start xray-skynet

# 4. Check
systemctl status xray-skynet
```

---

## 📊 Full System Check

```bash
bash check.sh
```

Ini akan check:
- Directories (/opt/skynet, configs, etc)
- Files (menu.sh, api, bot, configs)
- Services (xray, nginx, ssh, etc)
- Ports (listening status)
- Database (tables & data)
- SSL certificates

---

## 🎯 Alternative: Manual Setup

Jika installer otomatis gagal:

```bash
bash manual-setup.sh
```

Pilih langkah per langkah:
1. Install Xray + Create Service ← **Start here**
2. Setup Database
3. Deploy Scripts  
4. Setup Nginx
5. Install SSL
6. Setup All Services
7. Check Installation

---

## 🆘 Common Issues & Quick Fixes

### Issue: Config Error

```bash
# Copy from template
cp /opt/skynet/config/xray.json /usr/local/etc/xray/config.json
systemctl restart xray-skynet
```

### Issue: Port Conflict

```bash
# Find what's using the port
netstat -tulpn | grep 10086

# Kill it
kill -9 <PID>

# Restart xray
systemctl restart xray-skynet
```

### Issue: Permission Denied

```bash
chmod +x /usr/local/bin/xray
chown root:root /usr/local/etc/xray/config.json
systemctl restart xray-skynet
```

---

## 📱 After Xray is Running

```bash
# Access menu
menu

# Create first account
# Menu > 1 (SSH) atau 2/3/4 (Xray)
```

---

## 📚 More Help

- Full troubleshooting: [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
- Complete fixes list: [FIXES.md](FIXES.md)
- Full README: [README.md](README.md)

---

## ✅ Success Indicators

Service xray-skynet is **WORKING** jika:

```bash
$ systemctl status xray-skynet
● xray-skynet.service - SKYNET - Xray Service
     Loaded: loaded
     Active: active (running)  ← GOOD!
```

```bash
$ journalctl -u xray-skynet -n 5
# No errors, just "started" messages
```

```bash
$ netstat -tulpn | grep xray
tcp  0  0.0.0.0:10086  LISTEN  1234/xray
tcp  0  0.0.0.0:10087  LISTEN  1234/xray
tcp  0  0.0.0.0:10088  LISTEN  1234/xray
```

**Now you're ready to create accounts! 🎉**
