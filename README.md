# SKYNET VPN (Repo Source)

## Install
```bash
cd /opt
git clone https://github.com/evit2601-del/skynetvpn skynetvpn
cd skynetvpn
chmod +x install.sh
sudo bash install.sh
```

## Multi-login Auto Lock
- SSH: deteksi dari `who` vs `ip_limit`
- Xray (VMess/VLESS/Trojan): parse `/var/log/xray/access.log` -> `ip_tracking` vs `ip_limit`
- Saat melanggar: status jadi `locked`, set `locked_until`
- Setelah waktunya habis: auto unlock (SSH unlock + Xray client ditambahkan lagi)

## Menu 23 (Durasi Locked)
Masuk `FEATURES` -> `23` lalu ketik:
- `1m` (1 menit)
- `1h` (1 jam)
- `1d` (1 hari)

Disimpan di SQLite: `settings.lock_duration_seconds`
