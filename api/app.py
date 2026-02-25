# ============================================================
# SKYNET TUNNELING — REST API (FastAPI)
# Endpoint lengkap untuk manajemen SSH & Xray
# ============================================================

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
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, validator
import uvicorn

# ── Konfigurasi
DATABASE = os.getenv("DATABASE", "/opt/skynet/database/users.db")
API_KEY_ENV = os.getenv("API_KEY", "")
XRAY_CONFIG = "/usr/local/etc/xray/config.json"
LOG_FILE = "/opt/skynet/logs/api.log"

app = FastAPI(
    title="SKYNET Tunneling API",
    description="REST API untuk manajemen SSH & Xray accounts",
    version="1.0.0",
    docs_url=None,   # Disable Swagger UI di production
    redoc_url=None,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── API Key Auth
api_key_header = APIKeyHeader(name="X-API-Key", auto_error=True)

def get_api_key(api_key: str = Security(api_key_header)):
    """Validasi API Key dari header request."""
    db_key = get_setting("api_key")
    if not api_key or api_key != db_key:
        log_event("AUTH_FAIL", f"Invalid API key attempt")
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Invalid API Key"
        )
    return api_key

# ── Database helper
def get_db():
    conn = sqlite3.connect(DATABASE, timeout=10)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    return conn

def get_setting(key: str) -> str:
    with get_db() as conn:
        row = conn.execute(
            "SELECT value FROM settings WHERE key=?", (key,)
        ).fetchone()
        return row["value"] if row else ""

def log_event(event: str, detail: str):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with open(LOG_FILE, "a") as f:
        f.write(f"[{timestamp}] [{event}] {detail}\n")

# ── Xray config helper
def load_xray_config():
    with open(XRAY_CONFIG, "r") as f:
        return json.load(f)

def save_xray_config(config: dict):
    with open(XRAY_CONFIG, "w") as f:
        json.dump(config, f, indent=2)

def reload_xray():
    subprocess.run(
        ["systemctl", "restart", "xray-skynet"],
        capture_output=True, timeout=10
    )

# ── Pydantic Models (validasi input)

class CreateSSHUserRequest(BaseModel):
    username: str
    password: str
    days: int
    ip_limit: int = 1
    quota_gb: float = 0

    @validator("username")
    def validate_username(cls, v):
        if not v.isalnum() or len(v) < 3 or len(v) > 20:
            raise ValueError("Username harus alfanumerik, 3-20 karakter")
        return v.lower()

    @validator("password")
    def validate_password(cls, v):
        if len(v) < 3:
            raise ValueError("Password minimal 3 karakter")
        return v

    @validator("days")
    def validate_days(cls, v):
        if v < 1 or v > 3650:
            raise ValueError("Hari harus antara 1-3650")
        return v

    @validator("ip_limit")
    def validate_ip_limit(cls, v):
        if v < 1 or v > 10:
            raise ValueError("IP limit harus antara 1-10")
        return v

class CreateXrayUserRequest(BaseModel):
    username: str
    protocol: str
    days: int
    uuid_custom: Optional[str] = None
    ip_limit: int = 1
    quota_gb: float = 0
    tls_enabled: int = 1

    @validator("username")
    def validate_username(cls, v):
        if not v.isalnum() or len(v) < 3 or len(v) > 20:
            raise ValueError("Username harus alfanumerik, 3-20 karakter")
        return v.lower()

    @validator("protocol")
    def validate_protocol(cls, v):
        if v not in ["vmess", "vless", "trojan"]:
            raise ValueError("Protokol harus: vmess, vless, atau trojan")
        return v

    @validator("days")
    def validate_days(cls, v):
        if v < 1 or v > 3650:
            raise ValueError("Hari harus antara 1-3650")
        return v

class DeleteUserRequest(BaseModel):
    username: str
    user_type: str  # "ssh" atau "xray"
    protocol: Optional[str] = None

class ExtendUserRequest(BaseModel):
    username: str
    user_type: str
    days: int
    protocol: Optional[str] = None

class LockUnlockRequest(BaseModel):
    username: str
    user_type: str
    protocol: Optional[str] = None

class CheckUserRequest(BaseModel):
    username: str
    user_type: str
    protocol: Optional[str] = None

# ═══════════════════════════════════════════
# ENDPOINT: CREATE SSH USER
# ═══════════════════════════════════════════
@app.post("/create-user")
async def create_user(req: CreateSSHUserRequest, api_key: str = Depends(get_api_key)):
    """Buat akun SSH baru."""
    try:
        # Cek duplikat
        with get_db() as conn:
            exists = conn.execute(
                "SELECT COUNT(*) as cnt FROM ssh_users WHERE username=?",
                (req.username,)
            ).fetchone()["cnt"]
            if exists > 0:
                raise HTTPException(status_code=400, detail="Username sudah ada")

        expire_date = (datetime.now() + timedelta(days=req.days)).strftime("%Y-%m-%d")

        # Buat user sistem
        result = subprocess.run(
            ["useradd", "-M", "-s", "/bin/false", "-e", expire_date, req.username],
            capture_output=True, text=True
        )
        if result.returncode != 0:
            raise HTTPException(status_code=500, detail=f"Gagal buat user sistem: {result.stderr}")

        # Set password
        proc = subprocess.Popen(
            ["chpasswd"],
            stdin=subprocess.PIPE, capture_output=True, text=True
        )
        proc.communicate(f"{req.username}:{req.password}")

        # Simpan ke database
        with get_db() as conn:
            conn.execute(
                """INSERT INTO ssh_users
                   (username, password, quota_gb, ip_limit, expired_at)
                   VALUES (?, ?, ?, ?, ?)""",
                (req.username, req.password, req.quota_gb, req.ip_limit, expire_date)
            )
            conn.commit()

        domain = get_setting("domain")
        log_event("CREATE_SSH", f"User: {req.username}, Exp: {expire_date}")

        return {
            "success": True,
            "data": {
                "username": req.username,
                "password": req.password,
                "expired_at": expire_date,
                "ip_limit": req.ip_limit,
                "quota_gb": req.quota_gb,
                "domain": domain,
                "ports": {"ssh": [22, 2222], "dropbear": [442, 109]}
            }
        }

    except HTTPException:
        raise
    except Exception as e:
        log_event("ERROR_CREATE_SSH", str(e))
        raise HTTPException(status_code=500, detail=str(e))

# ═══════════════════════════════════════════
# ENDPOINT: CREATE XRAY USER
# ═══════════════════════════════════════════
@app.post("/create-xray")
async def create_xray_user(req: CreateXrayUserRequest, api_key: str = Depends(get_api_key)):
    """Buat akun Xray (VMess/VLESS/Trojan)."""
    try:
        with get_db() as conn:
            exists = conn.execute(
                "SELECT COUNT(*) as cnt FROM xray_users WHERE username=? AND protocol=?",
                (req.username, req.protocol)
            ).fetchone()["cnt"]
            if exists > 0:
                raise HTTPException(
                    status_code=400,
                    detail=f"Username sudah ada untuk protokol {req.protocol}"
                )

        # Generate UUID
        user_uuid = req.uuid_custom if req.uuid_custom else str(uuid.uuid4())
        expire_date = (datetime.now() + timedelta(days=req.days)).strftime("%Y-%m-%d")
        ws_path = f"/{req.protocol}-{secrets.token_hex(4)}"

        # Tag Xray berdasarkan protokol
        tag_map = {"vmess": "vmess-ws", "vless": "vless-ws", "trojan": "trojan-ws"}
        tag = tag_map[req.protocol]

        # Tambahkan client ke Xray config
        config = load_xray_config()
        for inbound in config["inbounds"]:
            if inbound["tag"] == tag:
                clients = inbound["settings"].get("clients", [])
                # Cek UUID duplikat
                for c in clients:
                    if c.get("id") == user_uuid or c.get("password") == user_uuid:
                        raise HTTPException(status_code=400, detail="UUID sudah digunakan")

                if req.protocol == "trojan":
                    clients.append({
                        "password": user_uuid,
                        "email": req.username,
                        "level": 0
                    })
                elif req.protocol == "vless":
                    clients.append({
                        "id": user_uuid,
                        "email": req.username,
                        "level": 0
                    })
                else:  # vmess
                    clients.append({
                        "id": user_uuid,
                        "alterId": 0,
                        "email": req.username,
                        "level": 0,
                        "security": "auto"
                    })
                inbound["settings"]["clients"] = clients
                break

        save_xray_config(config)
        reload_xray()

        # Simpan ke database
        with get_db() as conn:
            conn.execute(
                """INSERT INTO xray_users
                   (username, uuid, protocol, quota_gb, ip_limit, expired_at, tls_enabled, ws_path)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
                (req.username, user_uuid, req.protocol, req.quota_gb,
                 req.ip_limit, expire_date, req.tls_enabled, ws_path)
            )
            conn.commit()

        # Generate link
        domain = get_setting("domain")
        port = "443" if req.tls_enabled else "80"
        link = _generate_link(req.protocol, user_uuid, req.username,
                              domain, port, ws_path, req.tls_enabled)

        log_event("CREATE_XRAY", f"User: {req.username}, Proto: {req.protocol}, UUID: {user_uuid}")

        return {
            "success": True,
            "data": {
                "username": req.username,
                "uuid": user_uuid,
                "protocol": req.protocol,
                "ws_path": ws_path,
                "tls_enabled": req.tls_enabled,
                "expired_at": expire_date,
                "ip_limit": req.ip_limit,
                "quota_gb": req.quota_gb,
                "domain": domain,
                "link": link
            }
        }

    except HTTPException:
        raise
    except Exception as e:
        log_event("ERROR_CREATE_XRAY", str(e))
        raise HTTPException(status_code=500, detail=str(e))

def _generate_link(protocol, user_uuid, username, domain, port, ws_path, tls):
    """Generate link import untuk berbagai protokol."""
    import base64
    from urllib.parse import quote

    tls_str = "tls" if tls else "none"
    path_encoded = quote(ws_path)

    if protocol == "vmess":
        vmess_data = {
            "v": "2", "ps": username, "add": domain,
            "port": port, "id": user_uuid, "aid": 0,
            "net": "ws", "type": "none", "host": domain,
            "path": ws_path, "tls": tls_str
        }
        encoded = base64.b64encode(json.dumps(vmess_data).encode()).decode()
        return f"vmess://{encoded}"
    elif protocol == "vless":
        return (f"vless://{user_uuid}@{domain}:{port}"
                f"?encryption=none&security={tls_str}&type=ws"
                f"&host={domain}&path={path_encoded}#{username}")
    elif protocol == "trojan":
        return (f"trojan://{user_uuid}@{domain}:{port}"
                f"?security={tls_str}&type=ws"
                f"&host={domain}&path={path_encoded}#{username}")

# ═══════════════════════════════════════════
# ENDPOINT: DELETE USER
# ═══════════════════════════════════════════
@app.post("/delete-user")
async def delete_user(req: DeleteUserRequest, api_key: str = Depends(get_api_key)):
    """Hapus akun SSH atau Xray."""
    try:
        if req.user_type == "ssh":
            with get_db() as conn:
                exists = conn.execute(
                    "SELECT COUNT(*) as cnt FROM ssh_users WHERE username=?",
                    (req.username,)
                ).fetchone()["cnt"]
                if not exists:
                    raise HTTPException(status_code=404, detail="User tidak ditemukan")

            # Hapus dari sistem
            subprocess.run(["pkill", "-u", req.username], capture_output=True)
            subprocess.run(["userdel", "-f", req.username], capture_output=True)

            with get_db() as conn:
                conn.execute("DELETE FROM ssh_users WHERE username=?", (req.username,))
                conn.execute("DELETE FROM ip_tracking WHERE username=?", (req.username,))
                conn.commit()

        elif req.user_type == "xray":
            if not req.protocol:
                raise HTTPException(status_code=400, detail="Protocol diperlukan untuk user Xray")

            with get_db() as conn:
                row = conn.execute(
                    "SELECT uuid FROM xray_users WHERE username=? AND protocol=?",
                    (req.username, req.protocol)
                ).fetchone()
                if not row:
                    raise HTTPException(status_code=404, detail="User tidak ditemukan")
                user_uuid = row["uuid"]

            # Hapus dari Xray config
            tag_map = {"vmess": "vmess-ws", "vless": "vless-ws", "trojan": "trojan-ws"}
            tag = tag_map.get(req.protocol, "")
            config = load_xray_config()
            for inbound in config["inbounds"]:
                if inbound["tag"] == tag:
                    clients = inbound["settings"].get("clients", [])
                    inbound["settings"]["clients"] = [
                        c for c in clients
                        if c.get("id") != user_uuid and c.get("password") != user_uuid
                    ]
                    break
            save_xray_config(config)
            reload_xray()

            with get_db() as conn:
                conn.execute(
                    "DELETE FROM xray_users WHERE username=? AND protocol=?",
                    (req.username, req.protocol)
                )
                conn.commit()
        else:
            raise HTTPException(status_code=400, detail="user_type harus 'ssh' atau 'xray'")

        log_event("DELETE_USER", f"User: {req.username}, Type: {req.user_type}")
        return {"success": True, "message": f"User {req.username} berhasil dihapus"}

    except HTTPException:
        raise
    except Exception as e:
        log_event("ERROR_DELETE", str(e))
        raise HTTPException(status_code=500, detail=str(e))

# ═══════════════════════════════════════════
# ENDPOINT: EXTEND USER
# ═══════════════════════════════════════════
@app.post("/extend-user")
async def extend_user(req: ExtendUserRequest, api_key: str = Depends(get_api_key)):
    """Perpanjang masa aktif akun."""
    try:
        if req.days < 1:
            raise HTTPException(status_code=400, detail="Hari minimal 1")

        if req.user_type == "ssh":
            with get_db() as conn:
                row = conn.execute(
                    "SELECT expired_at FROM ssh_users WHERE username=?",
                    (req.username,)
                ).fetchone()
                if not row:
                    raise HTTPException(status_code=404, detail="User tidak ditemukan")
                current_exp = row["expired_at"]

            today = datetime.now().strftime("%Y-%m-%d")
            base = current_exp if current_exp and current_exp > today else today
            new_exp = (datetime.strptime(base, "%Y-%m-%d") + timedelta(days=req.days)).strftime("%Y-%m-%d")

            subprocess.run(["chage", "-E", new_exp, req.username], capture_output=True)
            with get_db() as conn:
                conn.execute(
                    "UPDATE ssh_users SET expired_at=?, status='active' WHERE username=?",
                    (new_exp, req.username)
                )
                conn.commit()

        elif req.user_type == "xray":
            with get_db() as conn:
                row = conn.execute(
                    "SELECT expired_at FROM xray_users WHERE username=? AND protocol=?",
                    (req.username, req.protocol)
                ).fetchone()
                if not row:
                    raise HTTPException(status_code=404, detail="User tidak ditemukan")
                current_exp = row["expired_at"]

            today = datetime.now().strftime("%Y-%m-%d")
            base = current_exp if current_exp and current_exp > today else today
            new_exp = (datetime.strptime(base, "%Y-%m-%d") + timedelta(days=req.days)).strftime("%Y-%m-%d")

            with get_db() as conn:
                conn.execute(
                    "UPDATE xray_users SET expired_at=?, status='active' WHERE username=? AND protocol=?",
                    (new_exp, req.username, req.protocol)
                )
                conn.commit()

        log_event("EXTEND_USER", f"User: {req.username}, +{req.days} days, new exp: {new_exp}")
        return {"success": True, "message": f"User diperpanjang hingga {new_exp}", "expired_at": new_exp}

    except HTTPException:
        raise
    except Exception as e:
        log_event("ERROR_EXTEND", str(e))
        raise HTTPException(status_code=500, detail=str(e))

# ═══════════════════════════════════════════
# ENDPOINT: LOCK USER
# ═══════════════════════════════════════════
@app.post("/lock-user")
async def lock_user(req: LockUnlockRequest, api_key: str = Depends(get_api_key)):
    """Lock akun user."""
    try:
        if req.user_type == "ssh":
            subprocess.run(["passwd", "-l", req.username], capture_output=True)
            subprocess.run(["pkill", "-u", req.username], capture_output=True)
            with get_db() as conn:
                conn.execute(
                    "UPDATE ssh_users SET status='locked' WHERE username=?",
                    (req.username,)
                )
                conn.commit()

        elif req.user_type == "xray":
            with get_db() as conn:
                row = conn.execute(
                    "SELECT uuid FROM xray_users WHERE username=? AND protocol=?",
                    (req.username, req.protocol)
                ).fetchone()
                if not row:
                    raise HTTPException(status_code=404, detail="User tidak ditemukan")
                user_uuid = row["uuid"]

            tag_map = {"vmess": "vmess-ws", "vless": "vless-ws", "trojan": "trojan-ws"}
            tag = tag_map.get(req.protocol, "")
            config = load_xray_config()
            for inbound in config["inbounds"]:
                if inbound["tag"] == tag:
                    clients = inbound["settings"].get("clients", [])
                    inbound["settings"]["clients"] = [
                        c for c in clients
                        if c.get("id") != user_uuid and c.get("password") != user_uuid
                    ]
                    break
            save_xray_config(config)
            reload_xray()

            with get_db() as conn:
                conn.execute(
                    "UPDATE xray_users SET status='locked' WHERE username=? AND protocol=?",
                    (req.username, req.protocol)
                )
                conn.commit()

        log_event("LOCK_USER", f"User: {req.username}")
        return {"success": True, "message": f"User {req.username} berhasil di-lock"}

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# ═══════════════════════════════════════════
# ENDPOINT: UNLOCK USER
# ═══════════════════════════════════════════
@app.post("/unlock-user")
async def unlock_user(req: LockUnlockRequest, api_key: str = Depends(get_api_key)):
    """Unlock akun user."""
    try:
        if req.user_type == "ssh":
            subprocess.run(["passwd", "-u", req.username], capture_output=True)
            with get_db() as conn:
                conn.execute(
                    "UPDATE ssh_users SET status='active' WHERE username=?",
                    (req.username,)
                )
                conn.commit()

        elif req.user_type == "xray":
            with get_db() as conn:
                row = conn.execute(
                    "SELECT uuid, ws_path FROM xray_users WHERE username=? AND protocol=?",
                    (req.username, req.protocol)
                ).fetchone()
                if not row:
                    raise HTTPException(status_code=404, detail="User tidak ditemukan")
                user_uuid = row["uuid"]

            # Tambahkan kembali ke Xray config
            tag_map = {"vmess": "vmess-ws", "vless": "vless-ws", "trojan": "trojan-ws"}
            tag = tag_map.get(req.protocol, "")
            config = load_xray_config()
            for inbound in config["inbounds"]:
                if inbound["tag"] == tag:
                    clients = inbound["settings"].get("clients", [])
                    if req.protocol == "trojan":
                        clients.append({"password": user_uuid, "email": req.username, "level": 0})
                    elif req.protocol == "vless":
                        clients.append({"id": user_uuid, "email": req.username, "level": 0})
                    else:
                        clients.append({"id": user_uuid, "alterId": 0, "email": req.username, "level": 0, "security": "auto"})
                    inbound["settings"]["clients"] = clients
                    break
            save_xray_config(config)
            reload_xray()

            with get_db() as conn:
                conn.execute(
                    "UPDATE xray_users SET status='active' WHERE username=? AND protocol=?",
                    (req.username, req.protocol)
                )
                conn.commit()

        log_event("UNLOCK_USER", f"User: {req.username}")
        return {"success": True, "message": f"User {req.username} berhasil di-unlock"}

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# ═══════════════════════════════════════════
# ENDPOINT: CHECK USER
# ═══════════════════════════════════════════
@app.get("/check-user")
async def check_user(username: str, user_type: str,
                     protocol: Optional[str] = None,
                     api_key: str = Depends(get_api_key)):
    """Cek detail akun user."""
    try:
        if user_type == "ssh":
            with get_db() as conn:
                row = conn.execute(
                    "SELECT * FROM ssh_users WHERE username=?", (username,)
                ).fetchone()
                if not row:
                    raise HTTPException(status_code=404, detail="User tidak ditemukan")
                active_ips = conn.execute(
                    "SELECT COUNT(*) as cnt FROM ip_tracking WHERE username=? AND is_active=1",
                    (username,)
                ).fetchone()["cnt"]

            return {
                "success": True,
                "data": {
                    "username": row["username"],
                    "status": row["status"],
                    "expired_at": row["expired_at"],
                    "quota_gb": row["quota_gb"],
                    "quota_used": row["quota_used"],
                    "ip_limit": row["ip_limit"],
                    "active_ips": active_ips,
                    "is_trial": bool(row["is_trial"])
                }
            }

        elif user_type == "xray":
            with get_db() as conn:
                row = conn.execute(
                    "SELECT * FROM xray_users WHERE username=? AND protocol=?",
                    (username, protocol)
                ).fetchone()
                if not row:
                    raise HTTPException(status_code=404, detail="User tidak ditemukan")

            domain = get_setting("domain")
            port = "443" if row["tls_enabled"] else "80"
            link = _generate_link(
                row["protocol"], row["uuid"], row["username"],
                domain, port, row["ws_path"], row["tls_enabled"]
            )

            return {
                "success": True,
                "data": {
                    "username": row["username"],
                    "uuid": row["uuid"],
                    "protocol": row["protocol"],
                    "status": row["status"],
                    "expired_at": row["expired_at"],
                    "quota_gb": row["quota_gb"],
                    "quota_used": row["quota_used"],
                    "ip_limit": row["ip_limit"],
                    "ws_path": row["ws_path"],
                    "tls_enabled": bool(row["tls_enabled"]),
                    "is_trial": bool(row["is_trial"]),
                    "link": link
                }
            }

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# ═══════════════════════════════════════════
# ENDPOINT: LIST USER
# ═══════════════════════════════════════════
@app.get("/list-user")
async def list_users(user_type: str = "ssh",
                     protocol: Optional[str] = None,
                     status_filter: Optional[str] = None,
                     api_key: str = Depends(get_api_key)):
    """List semua akun."""
    try:
        if user_type == "ssh":
            query = "SELECT username, expired_at, status, ip_limit, quota_gb, quota_used, is_trial FROM ssh_users"
            params = []
            if status_filter:
                query += " WHERE status=?"
                params.append(status_filter)
            query += " ORDER BY username"

            with get_db() as conn:
                rows = conn.execute(query, params).fetchall()

            return {
                "success": True,
                "total": len(rows),
                "data": [dict(r) for r in rows]
            }

        elif user_type == "xray":
            query = "SELECT username, uuid, protocol, expired_at, status, ip_limit, quota_gb, quota_used FROM xray_users"
            params = []
            conditions = []
            if protocol:
                conditions.append("protocol=?")
                params.append(protocol)
            if status_filter:
                conditions.append("status=?")
                params.append(status_filter)
            if conditions:
                query += " WHERE " + " AND ".join(conditions)
            query += " ORDER BY username"

            with get_db() as conn:
                rows = conn.execute(query, params).fetchall()

            return {
                "success": True,
                "total": len(rows),
                "data": [dict(r) for r in rows]
            }

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# ═══════════════════════════════════════════
# ENDPOINT: SERVER STATUS
# ═══════════════════════════════════════════
@app.get("/server-status")
async def server_status(api_key: str = Depends(get_api_key)):
    """Status server dan semua service."""
    try:
        import shutil

        # CPU usage
        cpu_result = subprocess.run(
            ["top", "-bn1"], capture_output=True, text=True
        )
        cpu_line = [l for l in cpu_result.stdout.split("\n") if "Cpu(s)" in l]
        cpu_usage = cpu_line[0] if cpu_line else "N/A"

        # RAM
        mem_result = subprocess.run(
            ["free", "-m"], capture_output=True, text=True
        )
        mem_lines = mem_result.stdout.split("\n")
        mem_parts = mem_lines[1].split() if len(mem_lines) > 1 else []
        ram_total = int(mem_parts[1]) if len(mem_parts) > 1 else 0
        ram_used = int(mem_parts[2]) if len(mem_parts) > 2 else 0

        # Disk
        disk_usage = shutil.disk_usage("/")
        disk_total_gb = round(disk_usage.total / (1024**3), 2)
        disk_used_gb = round(disk_usage.used / (1024**3), 2)
        disk_free_gb = round(disk_usage.free / (1024**3), 2)

        # Uptime
        uptime_result = subprocess.run(
            ["uptime", "-p"], capture_output=True, text=True
        )
        uptime = uptime_result.stdout.strip()

        # Service status
        services = ["ssh", "dropbear", "nginx", "xray-skynet", "fail2ban",
                    "stunnel4", "skynet-bot", "skynet-api"]
        svc_status = {}
        for svc in services:
            result = subprocess.run(
                ["systemctl", "is-active", svc],
                capture_output=True, text=True
            )
            svc_status[svc] = result.stdout.strip() == "active"

        # Account counts
        with get_db() as conn:
            ssh_count = conn.execute(
                "SELECT COUNT(*) as cnt FROM ssh_users WHERE status='active'"
            ).fetchone()["cnt"]
            vmess_count = conn.execute(
                "SELECT COUNT(*) as cnt FROM xray_users WHERE protocol='vmess' AND status='active'"
            ).fetchone()["cnt"]
            vless_count = conn.execute(
                "SELECT COUNT(*) as cnt FROM xray_users WHERE protocol='vless' AND status='active'"
            ).fetchone()["cnt"]
            trojan_count = conn.execute(
                "SELECT COUNT(*) as cnt FROM xray_users WHERE protocol='trojan' AND status='active'"
            ).fetchone()["cnt"]

        domain = get_setting("domain")

        return {
            "success": True,
            "data": {
                "domain": domain,
                "uptime": uptime,
                "cpu": cpu_usage,
                "ram": {"total_mb": ram_total, "used_mb": ram_used, "free_mb": ram_total - ram_used},
                "disk": {"total_gb": disk_total_gb, "used_gb": disk_used_gb, "free_gb": disk_free_gb},
                "services": svc_status,
                "accounts": {
                    "ssh": ssh_count,
                    "vmess": vmess_count,
                    "vless": vless_count,
                    "trojan": trojan_count
                }
            }
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# ── Health check
@app.get("/health")
async def health():
    return {"status": "ok", "service": "SKYNET API"}

if __name__ == "__main__":
    uvicorn.run("app:app", host="127.0.0.1", port=8080, reload=False, workers=2)
