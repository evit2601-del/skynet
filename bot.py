import os
import httpx
from datetime import datetime
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import Application, CommandHandler, CallbackQueryHandler, MessageHandler, ContextTypes, filters

def load_env(path="/opt/skynet/config/settings.conf"):
    if not os.path.exists(path):
        return
    with open(path, "r") as f:
        for line in f:
            line=line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k,v=line.split("=",1)
            os.environ.setdefault(k, v)

load_env()

BOT_TOKEN = os.getenv("BOT_TOKEN", "")
API_URL = os.getenv("API_URL", "http://127.0.0.1:8080")
API_KEY = os.getenv("API_KEY", "")
ADMIN_ID = os.getenv("ADMIN_TELEGRAM_ID", "")

ADMIN_IDS = []
for x in ADMIN_ID.split(","):
    x=x.strip()
    if x.isdigit():
        ADMIN_IDS.append(int(x))

def admin_only(func):
    async def wrapper(update: Update, context: ContextTypes.DEFAULT_TYPE):
        uid = update.effective_user.id
        if uid not in ADMIN_IDS:
            await update.effective_message.reply_text("Akses ditolak (bukan admin).")
            return
        return await func(update, context)
    return wrapper

def main_kb():
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("Create SSH", callback_data="ssh_create")]
    ])

async def api_post(endpoint, payload):
    async with httpx.AsyncClient(timeout=30) as client:
        r = await client.post(f"{API_URL}{endpoint}", json=payload, headers={"X-API-Key": API_KEY})
        return r.json()

@admin_only
async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(
        f"SKYNET BOT\n{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
        reply_markup=main_kb()
    )

@admin_only
async def cb(update: Update, context: ContextTypes.DEFAULT_TYPE):
    q = update.callback_query
    await q.answer()
    if q.data == "ssh_create":
        context.user_data["await"] = "ssh_user"
        await q.edit_message_text("Masukkan username SSH:")

@admin_only
async def msg(update: Update, context: ContextTypes.DEFAULT_TYPE):
    text = update.message.text.strip()
    st = context.user_data.get("await")
    if st == "ssh_user":
        context.user_data["ssh_user"] = text
        context.user_data["await"] = "ssh_pass"
        await update.message.reply_text("Masukkan password SSH (min 3 karakter):")
        return
    if st == "ssh_pass":
        # ✅ minimal 3
        if len(text) < 3:
            await update.message.reply_text("Password minimal 3 karakter. Coba lagi:")
            return
        context.user_data["ssh_pass"] = text
        context.user_data["await"] = "ssh_days"
        await update.message.reply_text("Masa aktif (hari):")
        return
    if st == "ssh_days":
        if not text.isdigit():
            await update.message.reply_text("Harus angka.")
            return
        payload = {
            "username": context.user_data["ssh_user"],
            "password": context.user_data["ssh_pass"],
            "days": int(text),
            "ip_limit": 1,
            "quota_gb": 0
        }
        context.user_data["await"] = None
        res = await api_post("/create-user", payload)
        await update.message.reply_text(str(res))
        return

async def main():
    if not BOT_TOKEN:
        raise SystemExit("BOT_TOKEN kosong. Set lewat menu SETUP BOT / settings.conf")
    app = Application.builder().token(BOT_TOKEN).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CallbackQueryHandler(cb))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, msg))
    await app.initialize()
    await app.start()
    await app.updater.start_polling()
    await app.updater.idle()

if __name__ == "__main__":
    import asyncio
    asyncio.run(main())
