#!/bin/bash
# ============================================================
# SKYNET QUICK INSTALLER
# Untuk fresh install di VPS baru
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

clear
echo -e "${CYAN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════╗
║                                                       ║
║          ███████╗██╗  ██╗██╗   ██╗███╗   ██╗         ║
║          ██╔════╝██║ ██╔╝╚██╗ ██╔╝████╗  ██║         ║
║          ███████╗█████╔╝  ╚████╔╝ ██╔██╗ ██║         ║
║          ╚════██║██╔═██╗   ╚██╔╝  ██║╚██╗██║         ║
║          ███████║██║  ██╗   ██║   ██║ ╚████║         ║
║          ╚══════╝╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═══╝         ║
║                                                       ║
║              TUNNELING QUICK INSTALLER                ║
║                                                       ║
╚═══════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Check root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Error: Script harus dijalankan sebagai root!${NC}"
    echo "Gunakan: sudo bash quick-install.sh"
    exit 1
fi

# Check OS
if [[ ! -f /etc/os-release ]]; then
    echo -e "${RED}Error: Tidak bisa detect OS!${NC}"
    exit 1
fi

source /etc/os-release
if [[ "$ID" != "ubuntu" ]]; then
    echo -e "${RED}Error: Hanya support Ubuntu!${NC}"
    echo "OS anda: $PRETTY_NAME"
    exit 1
fi

echo -e "${GREEN}✓ OS Supported: $PRETTY_NAME${NC}"
echo ""

# Pre-check
echo -e "${YELLOW}Pre-installation checks:${NC}"
echo ""

# Check memory
TOTAL_RAM=$(free -m | awk 'NR==2{print $2}')
if [[ $TOTAL_RAM -lt 512 ]]; then
    echo -e "${RED}✗ RAM terlalu kecil! Minimal 512MB${NC}"
    exit 1
else
    echo -e "${GREEN}✓ RAM: ${TOTAL_RAM}MB${NC}"
fi

# Check disk
DISK_FREE=$(df -m / | awk 'NR==2{print $4}')
if [[ $DISK_FREE -lt 2048 ]]; then
    echo -e "${YELLOW}! Disk space kurang dari 2GB (${DISK_FREE}MB free)${NC}"
    echo -e "  Lanjutkan? (y/n)"
    read -r confirm
    [[ "$confirm" != "y" ]] && exit 0
else
    echo -e "${GREEN}✓ Disk: ${DISK_FREE}MB free${NC}"
fi

# Check internet
if ! ping -c 1 google.com &>/dev/null; then
    echo -e "${RED}✗ Tidak ada koneksi internet!${NC}"
    exit 1
else
    echo -e "${GREEN}✓ Internet connection OK${NC}"
fi

echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}DOMAIN SETUP${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo ""
echo "Pastikan domain sudah di-pointing ke IP server ini!"
echo "IP Server: $(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')"
echo ""
read -p "Domain (contoh: vpn.domain.com): " DOMAIN
read -p "Email untuk SSL: " EMAIL

if [[ -z "$DOMAIN" ]] || [[ -z "$EMAIL" ]]; then
    echo -e "${RED}Domain dan email tidak boleh kosong!${NC}"
    exit 1
fi

# Verify domain pointing
echo ""
echo -e "${YELLOW}Memverifikasi domain...${NC}"
DOMAIN_IP=$(dig +short "$DOMAIN" @8.8.8.8 | tail -1)
SERVER_IP=$(curl -s ifconfig.me)

if [[ "$DOMAIN_IP" != "$SERVER_IP" ]]; then
    echo -e "${YELLOW}! WARNING: Domain belum pointing ke IP server ini${NC}"
    echo "  Domain IP: $DOMAIN_IP"
    echo "  Server IP: $SERVER_IP"
    echo ""
    echo "Lanjut install? SSL mungkin gagal. (y/n)"
    read -r confirm
    [[ "$confirm" != "y" ]] && exit 0
else
    echo -e "${GREEN}✓ Domain sudah pointing dengan benar${NC}"
fi

echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}INSTALLATION${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo ""
echo "Domain : $DOMAIN"
echo "Email  : $EMAIL"
echo ""
echo "Proses instalasi akan memakan waktu 10-15 menit."
echo "Tekan Enter untuk mulai atau Ctrl+C untuk batal..."
read -r

# Get current directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Run main installer
echo -e "${GREEN}Menjalankan installer...${NC}"
echo ""

# Export variables untuk installer
export DOMAIN
export EMAIL

# Run installer
cd "$SCRIPT_DIR"
bash install.sh

# Done
echo ""
echo -e "${GREEN}${BOLD}"
echo "╔═══════════════════════════════════════════════════╗"
echo "║            INSTALASI SELESAI!                     ║"
echo "╚═══════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Cek status: ${CYAN}bash check.sh${NC}"
echo "  2. Buka panel: ${CYAN}menu${NC}"
echo "  3. Setup bot (opsional): pilih menu 5 di panel"
echo ""
echo -e "${YELLOW}Jika ada masalah:${NC}"
echo "  - Lihat log: ${CYAN}journalctl -u xray-skynet -n 50${NC}"
echo "  - Run checker: ${CYAN}bash $SCRIPT_DIR/check.sh${NC}"
echo ""
