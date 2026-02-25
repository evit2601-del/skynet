import os
import sqlite3
import subprocess
import json
import uuid
import secrets
from datetime import datetime, timedelta
from typing import Optional

from fastapi import FastAPI, HTTPException, Depends, Security, status
from fastapi.security.api_key import APIKeyHeader
from pydantic import BaseModel, validator

DATABASE = os.getenv("DATABASE", "/opt/skynet/database/users.db")
XRAY_CONFIG = os.getenv("XRAY_CONFIG", "/usr/local/etc/xray/config.json")

app = FastAPI(docs_url=None, redoc_url=None)
api_key_header = APIKeyHeader(name="X-API-Key", auto_error=True)

def get_db():
    conn = sqlite3.connect(DATABASE, timeout=10)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    return conn

def get_setting(key: str) -> str:
    with get_db() as conn:
        row = conn.execute("SELECT value FROM settings WHERE key=?", (key,)).fetchone()
        return row["value"] if row else ""

def get_api_key(api_key: str = Security(api_key_header)):
    if api_key != get_setting("api_key"):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Invalid API Key")
    return api_key

def load_xray():
    with open(XRAY_CONFIG, "r") as f:
        return json.load(f)

def save_xray(cfg):
    with open(XRAY_CONFIG, "w") as f:
        json.dump(cfg, f, indent=2)

def restart_xray():
    subprocess.run(["systemctl", "restart", "xray-skynet"], capture_output=True)

class CreateSSHUserRequest(BaseModel):
    username: str
    password: str
    days: int
    ip_limit: int = 1
    quota_gb: float = 0

    @validator("username")
    def v_user(cls, v):
        if not v.isalnum() or len(v) < 3 or len(v) > 20:
            raise ValueError("Username harus alfanumerik, 3-20 karakter")
        return v.lower()

    @validator("password")
    def v_pass(cls, v):
        # ✅ minimal 3
        if len(v) < 3:
            raise ValueError("Password minimal 3 karakter")
        return v

    @validator("days")
    def v_days(cls, v):
        if v < 1 or v > 3650:
            raise ValueError("Hari 1-3650")
        return v

class CreateXrayUserRequest(BaseModel):
    username: str
    protocol: str
    days: int
    uuid_custom: Optional[str] = None
    ip_limit: int = 1
    quota_gb: float = 0
    tls_enabled: int = 1

    @validator("protocol")
    def v_proto(cls, v):
        if v not in ["vmess", "vless", "trojan"]:
            raise ValueError("protocol invalid")
        return v

def _generate_link(protocol, user_uuid, username, domain, port, ws_path, tls):
    import base64
    from urllib.parse import quote
    tls_str = "tls" if tls else "none"
    if protocol == "vmess":
        vmess_data = {
            "v": "2", "ps": username, "add": domain,
            "port": port, "id": user_uuid, "aid": 0,
            "net": "ws", "type": "none", "host": domain,
            "path": ws_path, "tls": tls_str
        }
        encoded = base64.b64encode(json.dumps(vmess_data).encode()).decode()
        return f"vmess://{encoded}"
    if protocol == "vless":
        return f"vless://{user_uuid}@{domain}:{port}?encryption=none&security={tls_str}&type=ws&host={domain}&path={quote(ws_path)}#{username}"
    return f"trojan://{user_uuid}@{domain}:{port}?security={tls_str}&type=ws&host={domain}&path={quote(ws_path)}#{username}"

@app.post("/create-user")
def create_user(req: CreateSSHUserRequest, api_key: str = Depends(get_api_key)):
    with get_db() as conn:
        exists = conn.execute("SELECT COUNT(*) c FROM ssh_users WHERE username=?", (req.username,)).fetchone()["c"]
        if exists:
            raise HTTPException(400, "Username sudah ada")

    exp = (datetime.now() + timedelta(days=req.days)).strftime("%Y-%m-%d")
    r = subprocess.run(["useradd", "-M", "-s", "/bin/false", "-e", exp, req.username], capture_output=True, text=True)
    if r.returncode != 0:
        raise HTTPException(500, r.stderr)

    p = subprocess.Popen(["chpasswd"], stdin=subprocess.PIPE, text=True)
    p.communicate(f"{req.username}:{req.password}")

    with get_db() as conn:
        conn.execute("""INSERT INTO ssh_users(username,password,quota_gb,ip_limit,expired_at)
                        VALUES(?,?,?,?,?)""",
                     (req.username, req.password, req.quota_gb, req.ip_limit, exp))
        conn.commit()

    domain = get_setting("domain")
    return {"success": True, "data": {"username": req.username, "password": req.password, "expired_at": exp, "domain": domain}}

@app.post("/create-xray")
def create_xray(req: CreateXrayUserRequest, api_key: str = Depends(get_api_key)):
    with get_db() as conn:
        exists = conn.execute("SELECT COUNT(*) c FROM xray_users WHERE username=? AND protocol=?",
                              (req.username, req.protocol)).fetchone()["c"]
        if exists:
            raise HTTPException(400, "Username sudah ada")

    user_uuid = req.uuid_custom or str(uuid.uuid4())
    exp = (datetime.now() + timedelta(days=req.days)).strftime("%Y-%m-%d")
    ws_path = f"/{req.protocol}-{secrets.token_hex(4)}"

    tag_map = {"vmess": "vmess-ws", "vless": "vless-ws", "trojan": "trojan-ws"}
    tag = tag_map[req.protocol]

    cfg = load_xray()
    for inbound in cfg.get("inbounds", []):
        if inbound.get("tag") == tag:
            clients = inbound.setdefault("settings", {}).setdefault("clients", [])
            if any(c.get("id") == user_uuid or c.get("password") == user_uuid for c in clients):
                raise HTTPException(400, "UUID sudah digunakan")
            if req.protocol == "trojan":
                clients.append({"password": user_uuid, "email": req.username, "level": 0})
            elif req.protocol == "vless":
                clients.append({"id": user_uuid, "email": req.username, "level": 0})
            else:
                clients.append({"id": user_uuid, "alterId": 0, "email": req.username, "level": 0, "security": "auto"})
            break

    save_xray(cfg)
    restart_xray()

    with get_db() as conn:
        conn.execute("""INSERT INTO xray_users(username,uuid,protocol,quota_gb,ip_limit,expired_at,tls_enabled,ws_path)
                        VALUES(?,?,?,?,?,?,?,?)""",
                     (req.username, user_uuid, req.protocol, req.quota_gb, req.ip_limit, exp, req.tls_enabled, ws_path))
        conn.commit()

    domain = get_setting("domain")
    port = "443" if req.tls_enabled else "80"
    link = _generate_link(req.protocol, user_uuid, req.username, domain, port, ws_path, req.tls_enabled)
    return {"success": True, "data": {"username": req.username, "uuid": user_uuid, "expired_at": exp, "ws_path": ws_path, "link": link}}

@app.get("/server-status")
def server_status(api_key: str = Depends(get_api_key)):
    services = ["ssh", "dropbear", "nginx", "xray-skynet", "fail2ban", "stunnel4", "skynet-api", "skynet-bot", "skynet-monitor"]
    stat = {}
    for s in services:
        r = subprocess.run(["systemctl", "is-active", s], capture_output=True, text=True)
        stat[s] = (r.stdout.strip() == "active")
    with get_db() as conn:
        sshc = conn.execute("SELECT COUNT(*) c FROM ssh_users WHERE status='active'").fetchone()["c"]
        vm = conn.execute("SELECT COUNT(*) c FROM xray_users WHERE protocol='vmess' AND status='active'").fetchone()["c"]
        vl = conn.execute("SELECT COUNT(*) c FROM xray_users WHERE protocol='vless' AND status='active'").fetchone()["c"]
        tr = conn.execute("SELECT COUNT(*) c FROM xray_users WHERE protocol='trojan' AND status='active'").fetchone()["c"]
    return {"success": True, "data": {"services": stat, "accounts": {"ssh": sshc, "vmess": vm, "vless": vl, "trojan": tr}}}
