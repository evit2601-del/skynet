# ============================================================
# SKYNET TUNNELING — TELEGRAM BOT
# Menggunakan python-telegram-bot v20+
# ============================================================

import os
import logging
import sqlite3
import httpx
import asyncio
from datetime import datetime
from typing import Optional

from telegram import (
    Update, InlineKeyboardButton, InlineKeyboardMarkup,
    BotCommand
)
from telegram.ext import (
    Application, CommandHandler, CallbackQueryHandler,
    MessageHandler, ConversationHandler, ContextTypes,
    filters
)
from dotenv import load_dotenv

load_dotenv("/opt/skynet/config/settings.conf")

# ── Konfigurasi
BOT_TOKEN = os.getenv("BOT_TOKEN", "")
ADMIN_IDS_RAW = os.getenv("ADMIN_TELEGRAM_ID", "")
ADMIN_IDS = [int(x.strip()) for x in ADMIN_IDS_RAW.split(",") if x.strip().isdigit()]
API_URL = os.getenv("API_URL", "http://127.0.0.1:8080")
API_KEY = os.getenv("API_KEY", "")
DATABASE = os.getenv("DATABASE", "/opt/skynet/database/users.db")

# ── Logging
logging.basicConfig(
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    level=logging.INFO,
    handlers=[
        logging.FileHandler("/opt/skynet/logs/bot.log"),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# ── Conversation states
(
    STATE_MAIN,
    STATE_SSH_USERNAME, STATE_SSH_PASSWORD, STATE_SSH_DAYS,
    STATE_SSH_IP_LIMIT, STATE_SSH_QUOTA,
    STATE_XRAY_USERNAME, STATE_XRAY_DAYS, STATE_XRAY_IP,
    STATE_XRAY_QUOTA, STATE_XRAY_UUID,
    STATE_DELETE_USER, STATE_EXTEND_USER, STATE_EXTEND_DAYS,
    STATE_CHECK_USER, STATE_SET_IP, STATE_SET_QUOTA,
    STATE_BROADCAST_MSG,
) = range(18)

# ── API helper
async def api_call(method: str, endpoint: str, **kwargs) -> dict:
    """Panggil SKYNET REST API."""
    headers = {"X-API-Key": API_KEY}
    async with httpx.AsyncClient(timeout=30) as client:
        if method.upper() == "GET":
            resp = await client.get(f"{API_URL}{endpoint}", headers=headers, params=kwargs.get("params"))
        else:
            resp = await client.post(f"{API_URL}{endpoint}", headers=headers, json=kwargs.get("json"))
    return resp.json()

# ── Auth decorator
def admin_only(func):
    """Pastikan hanya admin yang bisa akses."""
    async def wrapper(update: Update, context: ContextTypes.DEFAULT_TYPE):
        user_id = update.effective_user.id
        if user_id not in ADMIN_IDS:
            await update.effective_message.reply_text(
                "⛔ Akses ditolak! Anda bukan admin."
            )
            return
        return await func(update, context)
    return wrapper

# ── Keyboard helpers
def main_menu_keyboard():
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("🔐 SSH", callback_data="menu_ssh"),
         InlineKeyboardButton("🌀 VMess", callback_data="menu_vmess")],
        [InlineKeyboardButton("💎 VLESS", callback_data="menu_vless"),
         InlineKeyboardButton("🛡 Trojan", callback_data="menu_trojan")],
        [InlineKeyboardButton("📊 Server Status", callback_data="server_status"),
         InlineKeyboardButton("📋 List User", callback_data="list_all")],
        [InlineKeyboardButton("📢 Broadcast", callback_data="broadcast"),
         InlineKeyboardButton("💾 Backup", callback_data="do_backup")],
    ])

def ssh_menu_keyboard():
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("➕ Create User", callback_data="ssh_create"),
         InlineKeyboardButton("🎁 Trial User", callback_data="ssh_trial")],
        [InlineKeyboardButton("🗑 Delete User", callback_data="ssh_delete"),
         InlineKeyboardButton("🔄 Extend User", callback_data="ssh_extend")],
        [InlineKeyboardButton("🔍 Check User", callback_data="ssh_check"),
         InlineKeyboardButton("📋 List User", callback_data="ssh_list")],
        [InlineKeyboardButton("🔒 Lock User", callback_data="ssh_lock"),
         InlineKeyboardButton("🔓 Unlock User", callback_data="ssh_unlock")],
        [InlineKeyboardButton("🌐 Set IP Limit", callback_data="ssh_set_ip"),
         InlineKeyboardButton("📦 Set Quota", callback_data="ssh_set_quota")],
        [InlineKeyboardButton("🔙 Kembali", callback_data="back_main")],
    ])

def xray_menu_keyboard(protocol: str):
    proto_upper = protocol.upper()
    return InlineKeyboardMarkup([
        [InlineKeyboardButton(f"➕ Create {proto_upper}", callback_data=f"{protocol}_create"),
         InlineKeyboardButton("🎁 Trial", callback_data=f"{protocol}_trial")],
        [InlineKeyboardButton("🗑 Delete", callback_data=f"{protocol}_delete"),
         InlineKeyboardButton("🔄 Extend", callback_data=f"{protocol}_extend")],
        [InlineKeyboardButton("🔍 Check", callback_data=f"{protocol}_check"),
         InlineKeyboardButton("📋 List", callback_data=f"{protocol}_list")],
        [InlineKeyboardButton("🔒 Lock", callback_data=f"{protocol}_lock"),
         InlineKeyboardButton("🔓 Unlock", callback_data=f"{protocol}_unlock")],
        [InlineKeyboardButton("🌐 IP Limit", callback_data=f"{protocol}_set_ip"),
         InlineKeyboardButton("📦 Set Quota", callback_data=f"{protocol}_set_quota")],
        [InlineKeyboardButton("🔙 Kembali", callback_data="back_main")],
    ])

def confirm_keyboard(action: str):
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("✅ Ya", callback_data=f"confirm_{action}"),
         InlineKeyboardButton("❌ Tidak", callback_data="back_main")]
    ])

def cancel_keyboard():
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("❌ Batal", callback_data="back_main")]
    ])

# ═══════════════════════════════════════════
# COMMAND HANDLERS
# ═══════════════════════════════════════════

@admin_only
async def start_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler /start."""
    user = update.effective_user
    text = (
        f"🚀 *SKYNET TUNNELING PANEL*\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"👤 Admin: `{user.first_name}`\n"
        f"🆔 ID: `{user.id}`\n"
        f"⏰ {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"Pilih menu di bawah:"
    )
    await update.message.reply_text(
        text,
        parse_mode="Markdown",
        reply_markup=main_menu_keyboard()
    )

@admin_only
async def status_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler /status."""
    await show_server_status(update, context)

async def show_server_status(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Tampilkan status server."""
    try:
        result = await api_call("GET", "/server-status")
        if not result.get("success"):
            await update.effective_message.reply_text("❌ Gagal ambil status server")
            return

        data = result["data"]
        svcs = data["services"]
        accs = data["accounts"]
        ram = data["ram"]
        disk = data["disk"]

        def svc_icon(v): return "🟢" if v else "🔴"

        text = (
            f"📊 *SERVER STATUS*\n"
            f"━━━━━━━━━━━━━━━━━━━━━━━━\n"
            f"🌐 Domain : `{data['domain']}`\n"
            f"⏱ Uptime : `{data['uptime']}`\n"
            f"💾 RAM    : `{ram['used_mb']}MB / {ram['total_mb']}MB`\n"
            f"💿 Disk   : `{disk['used_gb']}GB / {disk['total_gb']}GB`\n"
            f"━━━━━━━━━━━━━━━━━━━━━━━━\n"
            f"*SERVICES*\n"
            f"{svc_icon(svcs.get('ssh'))} SSH   "
            f"{svc_icon(svcs.get('nginx'))} Nginx   "
            f"{svc_icon(svcs.get('xray-skynet'))} Xray\n"
            f"{svc_icon(svcs.get('dropbear'))} Dropbear   "
            f"{svc_icon(svcs.get('fail2ban'))} Fail2Ban\n"
            f"{svc_icon(svcs.get('skynet-api'))} API   "
            f"{svc_icon(svcs.get('skynet-bot'))} Bot\n"
            f"━━━━━━━━━━━━━━━━━━━━━━━━\n"
            f"*ACCOUNTS AKTIF*\n"
            f"🔐 SSH    : `{accs['ssh']}`\n"
            f"🌀 VMess  : `{accs['vmess']}`\n"
            f"💎 VLESS  : `{accs['vless']}`\n"
            f"🛡 Trojan : `{accs['trojan']}`\n"
        )
        keyboard = InlineKeyboardMarkup([
            [InlineKeyboardButton("🔙 Menu Utama", callback_data="back_main")]
        ])
        await update.effective_message.reply_text(
            text, parse_mode="Markdown", reply_markup=keyboard
        )
    except Exception as e:
        await update.effective_message.reply_text(f"❌ Error: {str(e)}")

# ═══════════════════════════════════════════
# CALLBACK QUERY HANDLER
# ═══════════════════════════════════════════

@admin_only
async def callback_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle semua inline button callback."""
    query = update.callback_query
    await query.answer()
    data = query.data

    # ── Main menu navigation
    if data == "back_main":
        await query.edit_message_text(
            "🚀 *SKYNET PANEL* — Pilih menu:",
            parse_mode="Markdown",
            reply_markup=main_menu_keyboard()
        )
        return

    # ── Menu navigasi
    if data == "menu_ssh":
        await query.edit_message_text(
            "🔐 *SSH MANAGEMENT*",
            parse_mode="Markdown",
            reply_markup=ssh_menu_keyboard()
        )
        return

    for proto in ["vmess", "vless", "trojan"]:
        if data == f"menu_{proto}":
            await query.edit_message_text(
                f"🔗 *{proto.upper()} MANAGEMENT*",
                parse_mode="Markdown",
                reply_markup=xray_menu_keyboard(proto)
            )
            return

    # ── Server status
    if data == "server_status":
        await show_server_status(update, context)
        return

    # ── List all users
    if data == "list_all":
        await handle_list_all(query, context)
        return

    # ── Backup
    if data == "do_backup":
        await handle_backup(query, context)
        return

    # ── SSH actions
    if data.startswith("ssh_"):
        await handle_ssh_action(query, context, data[4:])
        return

    # ── Xray actions (vmess_, vless_, trojan_)
    for proto in ["vmess", "vless", "trojan"]:
        if data.startswith(f"{proto}_"):
            action = data[len(proto)+1:]
            await handle_xray_action(query, context, proto, action)
            return

    # ── Broadcast
    if data == "broadcast":
        context.user_data["action"] = "broadcast"
        await query.edit_message_text(
            "📢 *BROADCAST*\nMasukkan pesan yang akan dikirim ke semua admin:",
            parse_mode="Markdown",
            reply_markup=cancel_keyboard()
        )
        context.user_data["awaiting"] = "broadcast_msg"
        return

# ── Handle SSH actions
async def handle_ssh_action(query, context, action: str):
    """Handle aksi SSH dari callback."""
    action_map = {
        "create": ("ssh_username", "🔐 *CREATE SSH USER*\nMasukkan username:"),
        "trial":  ("ssh_trial_username", "🎁 *TRIAL SSH USER*\nMasukkan username:"),
        "delete": ("delete_ssh_username", "🗑 *DELETE SSH USER*\nMasukkan username:"),
        "extend": ("extend_ssh_username", "🔄 *EXTEND SSH USER*\nMasukkan username:"),
        "check":  ("check_ssh_username", "🔍 *CHECK SSH USER*\nMasukkan username:"),
        "list":   None,
        "lock":   ("lock_ssh_username", "🔒 *LOCK SSH USER*\nMasukkan username:"),
        "unlock": ("unlock_ssh_username", "🔓 *UNLOCK SSH USER*\nMasukkan username:"),
        "set_ip": ("set_ip_ssh_username", "🌐 *SET IP LIMIT SSH*\nMasukkan username:"),
        "set_quota": ("set_quota_ssh_username", "📦 *SET QUOTA SSH*\nMasukkan username:"),
    }

    if action == "list":
        await handle_list_users(query, context, "ssh")
        return

    if action in action_map and action_map[action]:
        awaiting_key, prompt = action_map[action]
        context.user_data["awaiting"] = awaiting_key
        context.user_data["proto"] = "ssh"
        await query.edit_message_text(
            prompt, parse_mode="Markdown", reply_markup=cancel_keyboard()
        )

# ── Handle Xray actions
async def handle_xray_action(query, context, proto: str, action: str):
    """Handle aksi Xray dari callback."""
    if action == "list":
        await handle_list_users(query, context, "xray", proto)
        return

    context.user_data["proto"] = proto
    action_prompts = {
        "create":    ("xray_username", f"➕ *CREATE {proto.upper()}*\nMasukkan username:"),
        "trial":     ("xray_trial_username", f"🎁 *TRIAL {proto.upper()}*\nMasukkan username:"),
        "delete":    ("delete_xray_username", f"🗑 *DELETE {proto.upper()}*\nMasukkan username:"),
        "extend":    ("extend_xray_username", f"🔄 *EXTEND {proto.upper()}*\nMasukkan username:"),
        "check":     ("check_xray_username", f"🔍 *CHECK {proto.upper()}*\nMasukkan username:"),
        "lock":      ("lock_xray_username", f"🔒 *LOCK {proto.upper()}*\nMasukkan username:"),
        "unlock":    ("unlock_xray_username", f"🔓 *UNLOCK {proto.upper()}*\nMasukkan username:"),
        "set_ip":    ("set_ip_xray_username", f"🌐 *SET IP LIMIT {proto.upper()}*\nMasukkan username:"),
        "set_quota": ("set_quota_xray_username", f"📦 *SET QUOTA {proto.upper()}*\nMasukkan username:"),
    }

    if action in action_prompts:
        awaiting_key, prompt = action_prompts[action]
        context.user_data["awaiting"] = awaiting_key
        await query.edit_message_text(
            prompt, parse_mode="Markdown", reply_markup=cancel_keyboard()
        )

# ── List users helper
async def handle_list_users(query, context, user_type: str, protocol: str = None):
    """Tampilkan list users."""
    try:
        params = {"user_type": user_type}
        if protocol:
            params["protocol"] = protocol

        result = await api_call("GET", "/list-user", params=params)
        if not result.get("success"):
            await query.edit_message_text("❌ Gagal ambil list user")
            return

        users = result["data"]
        total = result["total"]

        if not users:
            text = f"📋 *LIST {user_type.upper()}*\n\nBelum ada user."
        else:
            text = f"📋 *LIST {(protocol or user_type).upper()}*\nTotal: `{total}`\n\n"
            for u in users[:20]:  # Limit 20 untuk Telegram
                status_icon = "🟢" if u["status"] == "active" else "🔴"
                text += f"{status_icon} `{u['username']}` — Exp: `{u.get('expired_at','N/A')}`\n"
            if total > 20:
                text += f"\n_...dan {total-20} lainnya_"

        keyboard = InlineKeyboardMarkup([
            [InlineKeyboardButton("🔙 Kembali", callback_data=f"menu_{protocol or user_type}")]
        ])
        await query.edit_message_text(text, parse_mode="Markdown", reply_markup=keyboard)

    except Exception as e:
        await query.edit_message_text(f"❌ Error: {str(e)}")

# ── List all
async def handle_list_all(query, context):
    """List semua akun semua tipe."""
    try:
        texts = []
        for utype, proto in [("ssh", None), ("xray", "vmess"), ("xray", "vless"), ("xray", "trojan")]:
            params = {"user_type": utype}
            if proto:
                params["protocol"] = proto
            r = await api_call("GET", "/list-user", params=params)
            label = proto.upper() if proto else "SSH"
            count = r.get("total", 0) if r.get("success") else "?"
            texts.append(f"🔹 {label}: `{count}` akun")

        text = "📊 *RINGKASAN SEMUA AKUN*\n━━━━━━━━━━━━━━\n" + "\n".join(texts)
        await query.edit_message_text(
            text, parse_mode="Markdown",
            reply_markup=InlineKeyboardMarkup([
                [InlineKeyboardButton("🔙 Kembali", callback_data="back_main")]
            ])
        )
    except Exception as e:
        await query.edit_message_text(f"❌ Error: {str(e)}")

# ── Backup handler
async def handle_backup(query, context):
    """Trigger backup."""
    import subprocess
    try:
        result = subprocess.run(
            ["bash", "-c",
             "cd /opt/skynet && TIMESTAMP=$(date +%Y%m%d_%H%M%S) && "
             "zip -q /opt/skynet/backup/skynet_backup_${TIMESTAMP}.zip "
             "/usr/local/etc/xray/config.json "
             "/etc/ssh/sshd_config "
             "/opt/skynet/database/users.db "
             "/opt/skynet/config/settings.conf && "
             "echo /opt/skynet/backup/skynet_backup_${TIMESTAMP}.zip"],
            capture_output=True, text=True, timeout=30
        )
        backup_file = result.stdout.strip()
        if backup_file and os.path.exists(backup_file):
            await query.edit_message_text(f"✅ Backup berhasil!\n`{backup_file}`",
                                          parse_mode="Markdown")
            # Kirim file ke admin
            with open(backup_file, "rb") as f:
                await context.bot.send_document(
                    chat_id=query.from_user.id,
                    document=f,
                    filename=os.path.basename(backup_file),
                    caption="💾 SKYNET Backup File"
                )
        else:
            await query.edit_message_text("❌ Backup gagal!")
    except Exception as e:
        await query.edit_message_text(f"❌ Error: {str(e)}")

# ═══════════════════════════════════════════
# MESSAGE HANDLER (untuk input multi-step)
# ═══════════════════════════════════════════

@admin_only
async def message_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle semua pesan teks untuk alur input multi-step."""
    text = update.message.text.strip()
    awaiting = context.user_data.get("awaiting")
    proto = context.user_data.get("proto", "")

    if not awaiting:
        await update.message.reply_text(
            "Gunakan /start untuk membuka menu.",
            reply_markup=main_menu_keyboard()
        )
        return

    # ── SSH Create flow
    if awaiting == "ssh_username":
        context.user_data["ssh_new_username"] = text
        context.user_data["awaiting"] = "ssh_new_password"
        await update.message.reply_text(
            "🔑 Masukkan password:", reply_markup=cancel_keyboard()
        )
    elif awaiting == "ssh_new_password":
        context.user_data["ssh_new_password"] = text
        context.user_data["awaiting"] = "ssh_new_days"
        await update.message.reply_text(
            "📅 Masa aktif (hari):", reply_markup=cancel_keyboard()
        )
    elif awaiting == "ssh_new_days":
        if not text.isdigit():
            await update.message.reply_text("❌ Harus angka!"); return
        context.user_data["ssh_new_days"] = int(text)
        context.user_data["awaiting"] = "ssh_new_ip"
        await update.message.reply_text(
            "🌐 Limit IP (default 1):", reply_markup=cancel_keyboard()
        )
    elif awaiting == "ssh_new_ip":
        ip_limit = int(text) if text.isdigit() else 1
        context.user_data["ssh_new_ip"] = ip_limit
        context.user_data["awaiting"] = "ssh_new_quota"
        await update.message.reply_text(
            "📦 Quota GB (0=unlimited):", reply_markup=cancel_keyboard()
        )
    elif awaiting == "ssh_new_quota":
        quota = float(text) if text.replace(".", "").isdigit() else 0
        context.user_data["ssh_new_quota"] = quota
        context.user_data["awaiting"] = None

        # Kirim request ke API
        payload = {
            "username": context.user_data["ssh_new_username"],
            "password": context.user_data["ssh_new_password"],
            "days": context.user_data["ssh_new_days"],
            "ip_limit": context.user_data["ssh_new_ip"],
            "quota_gb": quota
        }
        result = await api_call("POST", "/create-user", json=payload)
        if result.get("success"):
            d = result["data"]
            msg = (
                f"✅ *SSH USER BERHASIL DIBUAT*\n"
                f"━━━━━━━━━━━━━━━━━━━━━━━━\n"
                f"👤 Username  : `{d['username']}`\n"
                f"🔑 Password  : `{d['password']}`\n"
                f"📅 Expired   : `{d['expired_at']}`\n"
                f"🌐 IP Limit  : `{d['ip_limit']}`\n"
                f"📦 Quota     : `{d['quota_gb']}GB`\n"
                f"🌍 Domain    : `{d['domain']}`\n"
                f"🔌 Port SSH  : `22, 2222`\n"
                f"🔌 Dropbear  : `442, 109`\n"
            )
        else:
            msg = f"❌ Gagal: {result.get('detail', 'Unknown error')}"

        await update.message.reply_text(
            msg, parse_mode="Markdown", reply_markup=main_menu_keyboard()
        )

    # ── Xray Create flow
    elif awaiting == "xray_username":
        context.user_data["xray_new_username"] = text
        context.user_data["awaiting"] = "xray_new_uuid"
        await update.message.reply_text(
            "🔑 Masukkan UUID custom (kosong=auto generate):",
            reply_markup=cancel_keyboard()
        )
    elif awaiting == "xray_new_uuid":
        context.user_data["xray_new_uuid"] = text if text else None
        context.user_data["awaiting"] = "xray_new_days"
        await update.message.reply_text("📅 Masa aktif (hari):", reply_markup=cancel_keyboard())
    elif awaiting == "xray_new_days":
        if not text.isdigit():
            await update.message.reply_text("❌ Harus angka!"); return
        context.user_data["xray_new_days"] = int(text)
        context.user_data["awaiting"] = "xray_new_ip"
        await update.message.reply_text("🌐 Limit IP (default 1):", reply_markup=cancel_keyboard())
    elif awaiting == "xray_new_ip":
        ip_limit = int(text) if text.isdigit() else 1
        context.user_data["xray_new_ip"] = ip_limit
        context.user_data["awaiting"] = "xray_new_quota"
        await update.message.reply_text("📦 Quota GB (0=unlimited):", reply_markup=cancel_keyboard())
    elif awaiting == "xray_new_quota":
        quota = float(text) if text.replace(".", "").isdigit() else 0
        context.user_data["awaiting"] = None

        payload = {
            "username": context.user_data["xray_new_username"],
            "protocol": proto,
            "days": context.user_data["xray_new_days"],
            "uuid_custom": context.user_data.get("xray_new_uuid"),
            "ip_limit": context.user_data.get("xray_new_ip", 1),
            "quota_gb": quota,
            "tls_enabled": 1
        }
        result = await api_call("POST", "/create-xray", json=payload)
        if result.get("success"):
            d = result["data"]
            msg = (
                f"✅ *{proto.upper()} BERHASIL DIBUAT*\n"
                f"━━━━━━━━━━━━━━━━━━━━━━━━\n"
                f"👤 Username : `{d['username']}`\n"
                f"🔑 UUID     : `{d['uuid']}`\n"
                f"🛤 WS Path  : `{d['ws_path']}`\n"
                f"📅 Expired  : `{d['expired_at']}`\n"
                f"🌐 IP Limit : `{d['ip_limit']}`\n"
                f"📦 Quota    : `{d['quota_gb']}GB`\n"
                f"🔗 TLS      : `{'Aktif' if d['tls_enabled'] else 'Non-TLS'}`\n\n"
                f"📎 *Link Import:*\n`{d['link']}`"
            )
        else:
            msg = f"❌ Gagal: {result.get('detail', 'Unknown error')}"

        await update.message.reply_text(
            msg, parse_mode="Markdown", reply_markup=main_menu_keyboard()
        )

    # ── Delete user
    elif awaiting in ["delete_ssh_username", "delete_xray_username"]:
        utype = "ssh" if "ssh" in awaiting else "xray"
        context.user_data["del_username"] = text
        context.user_data["del_type"] = utype
        context.user_data["awaiting"] = None
        keyboard = InlineKeyboardMarkup([
            [InlineKeyboardButton("✅ Ya, Hapus!", callback_data=f"confirm_delete_{utype}_{text}"),
             InlineKeyboardButton("❌ Batal", callback_data="back_main")]
        ])
        await update.message.reply_text(
            f"⚠️ Konfirmasi hapus user `{text}`?",
            parse_mode="Markdown", reply_markup=keyboard
        )

    # ── Extend user
    elif awaiting in ["extend_ssh_username", "extend_xray_username"]:
        utype = "ssh" if "ssh" in awaiting else "xray"
        context.user_data["extend_username"] = text
        context.user_data["extend_type"] = utype
        context.user_data["awaiting"] = "extend_days"
        await update.message.reply_text("📅 Tambah berapa hari?", reply_markup=cancel_keyboard())
    elif awaiting == "extend_days":
        if not text.isdigit():
            await update.message.reply_text("❌ Harus angka!"); return
        utype = context.user_data.get("extend_type", "ssh")
        username = context.user_data.get("extend_username")
        context.user_data["awaiting"] = None

        payload = {
            "username": username,
            "user_type": utype,
            "days": int(text),
            "protocol": proto if utype == "xray" else None
        }
        result = await api_call("POST", "/extend-user", json=payload)
        if result.get("success"):
            msg = f"✅ User `{username}` diperpanjang hingga `{result.get('expired_at')}`"
        else:
            msg = f"❌ Gagal: {result.get('detail')}"
        await update.message.reply_text(msg, parse_mode="Markdown", reply_markup=main_menu_keyboard())

    # ── Check user
    elif awaiting in ["check_ssh_username", "check_xray_username"]:
        utype = "ssh" if "ssh" in awaiting else "xray"
        context.user_data["awaiting"] = None
        params = {"username": text, "user_type": utype}
        if utype == "xray":
            params["protocol"] = proto
        result = await api_call("GET", "/check-user", params=params)
        if result.get("success"):
            d = result["data"]
            if utype == "ssh":
                msg = (
                    f"🔍 *INFO SSH USER*\n"
                    f"👤 Username : `{d['username']}`\n"
                    f"📊 Status   : `{d['status']}`\n"
                    f"📅 Expired  : `{d['expired_at']}`\n"
                    f"📦 Quota    : `{d['quota_used']}GB / {d['quota_gb']}GB`\n"
                    f"🌐 IP Aktif : `{d['active_ips']}/{d['ip_limit']}`\n"
                )
            else:
                msg = (
                    f"🔍 *INFO {proto.upper()} USER*\n"
                    f"👤 Username : `{d['username']}`\n"
                    f"🔑 UUID     : `{d['uuid']}`\n"
                    f"📊 Status   : `{d['status']}`\n"
                    f"📅 Expired  : `{d['expired_at']}`\n"
                    f"📦 Quota    : `{d['quota_used']}GB / {d['quota_gb']}GB`\n"
                    f"🌐 IP Limit : `{d['ip_limit']}`\n\n"
                    f"📎 Link:\n`{d['link']}`"
                )
        else:
            msg = f"❌ {result.get('detail', 'User tidak ditemukan')}"
        await update.message.reply_text(msg, parse_mode="Markdown", reply_markup=main_menu_keyboard())

    # ── Lock/Unlock
    elif awaiting in ["lock_ssh_username", "unlock_ssh_username",
                      "lock_xray_username", "unlock_xray_username"]:
        action = "lock" if "lock" in awaiting else "unlock"
        utype = "ssh" if "ssh" in awaiting else "xray"
        context.user_data["awaiting"] = None

        payload = {"username": text, "user_type": utype,
                   "protocol": proto if utype == "xray" else None}
        result = await api_call("POST", f"/{action}-user", json=payload)
        icon = "🔒" if action == "lock" else "🔓"
        msg = f"{icon} User `{text}` berhasil di-{action}!" if result.get("success") \
              else f"❌ Gagal: {result.get('detail')}"
        await update.message.reply_text(msg, parse_mode="Markdown", reply_markup=main_menu_keyboard())

    # ── Broadcast
    elif awaiting == "broadcast_msg":
        context.user_data["awaiting"] = None
        for admin_id in ADMIN_IDS:
            try:
                await context.bot.send_message(
                    chat_id=admin_id,
                    text=f"📢 *BROADCAST*\n\n{text}",
                    parse_mode="Markdown"
                )
            except Exception:
                pass
        await update.message.reply_text(
            f"✅ Broadcast terkirim ke {len(ADMIN_IDS)} admin.",
            reply_markup=main_menu_keyboard()
        )

    # ── Set IP limit
    elif awaiting in ["set_ip_ssh_username", "set_ip_xray_username"]:
        utype = "ssh" if "ssh" in awaiting else "xray"
        context.user_data["set_ip_username"] = text
        context.user_data["set_ip_type"] = utype
        context.user_data["awaiting"] = "set_ip_value"
        await update.message.reply_text("🌐 Masukkan limit IP baru:", reply_markup=cancel_keyboard())
    elif awaiting == "set_ip_value":
        if not text.isdigit():
            await update.message.reply_text("❌ Harus angka!"); return
        username = context.user_data.get("set_ip_username")
        utype = context.user_data.get("set_ip_type", "ssh")
        context.user_data["awaiting"] = None

        # Update langsung ke database
        with sqlite3.connect(DATABASE) as conn:
            if utype == "ssh":
                conn.execute("UPDATE ssh_users SET ip_limit=? WHERE username=?",
                             (int(text), username))
            else:
                conn.execute("UPDATE xray_users SET ip_limit=? WHERE username=? AND protocol=?",
                             (int(text), username, proto))
            conn.commit()

        await update.message.reply_text(
            f"✅ IP limit `{username}` diset ke `{text}`",
            parse_mode="Markdown", reply_markup=main_menu_keyboard()
        )

    else:
        context.user_data["awaiting"] = None
        await update.message.reply_text(
            "Menu:", reply_markup=main_menu_keyboard()
        )

# ── Handle confirm delete callbacks
@admin_only
async def confirm_delete_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle konfirmasi delete dari inline button."""
    query = update.callback_query
    await query.answer()
    parts = query.data.split("_")
    # Format: confirm_delete_{type}_{username}
    if len(parts) >= 4:
        utype = parts[2]
        username = "_".join(parts[3:])
        proto_val = context.user_data.get("proto")

        payload = {"username": username, "user_type": utype,
                   "protocol": proto_val if utype == "xray" else None}
        result = await api_call("POST", "/delete-user", json=payload)

        if result.get("success"):
            msg = f"✅ User `{username}` berhasil dihapus!"
        else:
            msg = f"❌ Gagal: {result.get('detail')}"

        await query.edit_message_text(
            msg, parse_mode="Markdown", reply_markup=main_menu_keyboard()
        )

# ═══════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════

def main():
    if not BOT_TOKEN:
        logger.error("BOT_TOKEN tidak dikonfigurasi!")
        return

    if not ADMIN_IDS:
        logger.error("ADMIN_TELEGRAM_ID tidak dikonfigurasi!")
        return

    logger.info(f"Starting SKYNET Bot... Admin IDs: {ADMIN_IDS}")

    app = Application.builder().token(BOT_TOKEN).build()

    # Commands
    app.add_handler(CommandHandler("start", start_command))
    app.add_handler(CommandHandler("menu", start_command))
    app.add_handler(CommandHandler("status", status_command))

    # Callback queries
    app.add_handler(CallbackQueryHandler(
        confirm_delete_handler, pattern="^confirm_delete_"
    ))
    app.add_handler(CallbackQueryHandler(callback_handler))

    # Message handler
    app.add_handler(MessageHandler(
        filters.TEXT & ~filters.COMMAND, message_handler
    ))

    # Set bot commands
    async def post_init(application):
        await application.bot.set_my_commands([
            BotCommand("start", "Buka panel utama"),
            BotCommand("menu", "Buka menu"),
            BotCommand("status", "Status server"),
        ])

    app.post_init = post_init

    logger.info("Bot running...")
    app.run_polling(drop_pending_updates=True)

if __name__ == "__main__":
    main()
