#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
待续IP系统 · 商业版后台 v3（SQLite，零第三方依赖）

· 服务端：单文件 Python，只用标准库
· 网页：HTML 内嵌在本文件里，不需要单独放静态页面
· 存储：SQLite 单文件数据库 daixu.db（支持事务、并发、索引）
· 旧版 users.json / nodes.json 会在首次启动时自动迁移

启动：
    python admin_server.py --port 8787 --user admin --pass admin888
"""
import argparse
import base64
import hashlib
import hmac
import json
import os
import secrets
import socket
import sqlite3
import threading
import time
from contextlib import closing
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

BASE = os.path.dirname(os.path.abspath(__file__))
DB_FILE = os.path.join(BASE, "daixu.db")
LEGACY_USERS = os.path.join(BASE, "users.json")
LEGACY_NODES = os.path.join(BASE, "nodes.json")
SECRET_FILE = os.path.join(BASE, ".secret")
WRITE_LOCK = threading.Lock()

VERSION = "3.0"


# ------------------------------------------------------------------ 数据库
SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
    id       TEXT PRIMARY KEY,
    username TEXT UNIQUE NOT NULL,
    pwd      TEXT NOT NULL,
    plain    TEXT DEFAULT '',
    expires  INTEGER DEFAULT 0,
    enabled  INTEGER DEFAULT 1,
    status   TEXT DEFAULT 'active',
    grp      TEXT DEFAULT '',
    remark   TEXT DEFAULT '',
    created  INTEGER DEFAULT 0
);
CREATE TABLE IF NOT EXISTS nodes (
    id       TEXT PRIMARY KEY,
    name     TEXT DEFAULT '',
    host     TEXT NOT NULL,
    port     INTEGER NOT NULL,
    username TEXT DEFAULT '',
    password TEXT DEFAULT '',
    grp      TEXT DEFAULT '默认',
    enabled  INTEGER DEFAULT 1,
    updated  INTEGER DEFAULT 0,
    protocol TEXT DEFAULT 'socks5'
);
CREATE TABLE IF NOT EXISTS settings (
    key   TEXT PRIMARY KEY,
    value TEXT
);
CREATE INDEX IF NOT EXISTS idx_users_status ON users(status);
CREATE INDEX IF NOT EXISTS idx_nodes_grp ON nodes(grp);
"""


def db():
    conn = sqlite3.connect(DB_FILE, timeout=15)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA synchronous=NORMAL")
    return conn


def init_db():
    with closing(db()) as c:
        c.executescript(SCHEMA)
        # 老库补列（协议字段是后加的）
        cols = [r["name"] for r in c.execute("PRAGMA table_info(nodes)")]
        if "protocol" not in cols:
            c.execute("ALTER TABLE nodes ADD COLUMN protocol TEXT DEFAULT 'socks5'")
            print("[migrate] nodes.protocol 已添加")
        # 默认离线密码
        row = c.execute("SELECT value FROM settings WHERE key='offline_password'").fetchone()
        if not row:
            c.execute("INSERT INTO settings(key,value) VALUES(?,?)",
                      ("offline_password", "chenjian520"))
        c.commit()
    migrate_legacy()


def get_setting(key, default=""):
    with closing(db()) as c:
        r = c.execute("SELECT value FROM settings WHERE key=?", (key,)).fetchone()
        return r["value"] if r else default


def set_setting(key, value):
    with WRITE_LOCK, closing(db()) as c:
        c.execute("INSERT INTO settings(key,value) VALUES(?,?) "
                  "ON CONFLICT(key) DO UPDATE SET value=excluded.value", (key, value))
        c.commit()


def migrate_legacy():
    """把老版本 json 数据导入 sqlite（只导一次）"""
    if os.path.isfile(LEGACY_USERS):
        try:
            data = json.load(open(LEGACY_USERS, encoding="utf-8")).get("users", [])
            with closing(db()) as c:
                for u in data:
                    c.execute(
                        "INSERT OR IGNORE INTO users(id,username,pwd,plain,expires,enabled,status,grp,remark,created)"
                        " VALUES(?,?,?,?,?,?,?,?,?,?)",
                        (u.get("id") or secrets.token_hex(8), u["username"], u.get("pwd", ""),
                         u.get("plain", ""), int(u.get("expires", 0)),
                         1 if u.get("enabled", True) else 0,
                         u.get("status", "active"), u.get("group", ""),
                         u.get("remark", ""), int(u.get("created", 0))))
                c.commit()
            os.rename(LEGACY_USERS, LEGACY_USERS + ".migrated")
            print("[migrate] users.json -> daixu.db 完成")
        except Exception as e:
            print("[migrate] users 迁移失败:", e)

    if os.path.isfile(LEGACY_NODES):
        try:
            data = json.load(open(LEGACY_NODES, encoding="utf-8")).get("nodes", [])
            with closing(db()) as c:
                for n in data:
                    c.execute(
                        "INSERT OR IGNORE INTO nodes(id,name,host,port,username,password,grp,enabled,updated)"
                        " VALUES(?,?,?,?,?,?,?,?,?)",
                        (n.get("id") or secrets.token_hex(8), n.get("name", ""), n["host"],
                         int(n["port"]), n.get("username", ""), n.get("password", ""),
                         n.get("group", "默认"), 1 if n.get("enabled", True) else 0,
                         int(n.get("updated", 0))))
                c.commit()
            os.rename(LEGACY_NODES, LEGACY_NODES + ".migrated")
            print("[migrate] nodes.json -> daixu.db 完成")
        except Exception as e:
            print("[migrate] nodes 迁移失败:", e)


def row2dict(r):
    if r is None:
        return None
    d = dict(r)
    if "enabled" in d:
        d["enabled"] = bool(d["enabled"])
    if "grp" in d:
        d["group"] = d["grp"]
    return d


# ---- users
def list_users():
    with closing(db()) as c:
        return [row2dict(r) for r in c.execute("SELECT * FROM users ORDER BY created DESC")]


def get_user_by_name(name):
    with closing(db()) as c:
        return row2dict(c.execute("SELECT * FROM users WHERE username=?", (name,)).fetchone())


def get_user_by_id(uid):
    with closing(db()) as c:
        return row2dict(c.execute("SELECT * FROM users WHERE id=?", (uid,)).fetchone())


def insert_user(u):
    with WRITE_LOCK, closing(db()) as c:
        c.execute("INSERT INTO users(id,username,pwd,plain,expires,enabled,status,grp,remark,created)"
                  " VALUES(?,?,?,?,?,?,?,?,?,?)",
                  (u["id"], u["username"], u["pwd"], u.get("plain", ""), u.get("expires", 0),
                   1 if u.get("enabled", True) else 0, u.get("status", "active"),
                   u.get("group", ""), u.get("remark", ""), u.get("created", int(time.time()))))
        c.commit()


def update_user_fields(uid, fields):
    if not fields:
        return
    keys = ", ".join("%s=?" % k for k in fields)
    vals = list(fields.values()) + [uid]
    with WRITE_LOCK, closing(db()) as c:
        c.execute("UPDATE users SET %s WHERE id=?" % keys, vals)
        c.commit()


def delete_user(uid):
    with WRITE_LOCK, closing(db()) as c:
        c.execute("DELETE FROM users WHERE id=?", (uid,))
        c.commit()


# ---- nodes
def list_nodes(group=None, only_enabled=False):
    sql = "SELECT * FROM nodes WHERE 1=1"
    args = []
    if group:
        sql += " AND grp=?"
        args.append(group)
    if only_enabled:
        sql += " AND enabled=1"
    sql += " ORDER BY updated DESC"
    with closing(db()) as c:
        return [row2dict(r) for r in c.execute(sql, args)]


def upsert_node(n):
    with WRITE_LOCK, closing(db()) as c:
        c.execute(
            "INSERT INTO nodes(id,name,host,port,username,password,grp,enabled,updated,protocol)"
            " VALUES(?,?,?,?,?,?,?,?,?,?)"
            " ON CONFLICT(id) DO UPDATE SET name=excluded.name,host=excluded.host,port=excluded.port,"
            " username=excluded.username,password=excluded.password,grp=excluded.grp,"
            " enabled=excluded.enabled,updated=excluded.updated,protocol=excluded.protocol",
            (n["id"], n.get("name", ""), n["host"], int(n["port"]), n.get("username", ""),
             n.get("password", ""), n.get("group", "默认"), 1 if n.get("enabled", True) else 0,
             int(time.time()), n.get("protocol", "socks5")))
        c.commit()


def delete_node(nid):
    with WRITE_LOCK, closing(db()) as c:
        c.execute("DELETE FROM nodes WHERE id=?", (nid,))
        c.commit()


# ------------------------------------------------------------------ 密码 / token
def secret_key():
    if os.path.isfile(SECRET_FILE):
        with open(SECRET_FILE, "rb") as fh:
            return fh.read()
    key = secrets.token_bytes(32)
    with open(SECRET_FILE, "wb") as fh:
        fh.write(key)
    return key


SECRET = secret_key()


def hash_password(pwd, salt=None):
    salt = salt or secrets.token_hex(8)
    h = hashlib.pbkdf2_hmac("sha256", pwd.encode(), salt.encode(), 60000)
    return "pbkdf2$%s$%s" % (salt, h.hex())


def verify_password(pwd, stored):
    try:
        _, salt, _ = stored.split("$")
    except ValueError:
        return False
    return hmac.compare_digest(hash_password(pwd, salt), stored)


def b64(s):
    return base64.urlsafe_b64encode(s.encode()).decode().rstrip("=")


def unb64(s):
    s += "=" * (-len(s) % 4)
    return base64.urlsafe_b64decode(s.encode()).decode()


def admin_token(user, pwd):
    sig = hmac.new(SECRET, ("admin:%s:%s" % (user, pwd)).encode(), hashlib.sha256).hexdigest()[:40]
    return "ad." + sig


def user_token(u):
    sig = hmac.new(SECRET, ("user:%s:%s" % (u["username"], u["pwd"])).encode(),
                   hashlib.sha256).hexdigest()[:40]
    return "us.%s.%s" % (b64(u["username"]), sig)


def parse_token(tok, admin_user, admin_pwd):
    if not tok:
        return None, None
    parts = tok.split(".")
    if len(parts) == 2 and parts[0] == "ad":
        if hmac.compare_digest(parts[1], admin_token(admin_user, admin_pwd).split(".")[1]):
            return "admin", None
        return None, None
    if len(parts) == 3 and parts[0] == "us":
        try:
            username = unb64(parts[1])
        except Exception:
            return None, None
        u = get_user_by_name(username)
        if not u:
            return None, None
        expect = hmac.new(SECRET, ("user:%s:%s" % (u["username"], u["pwd"])).encode(),
                          hashlib.sha256).hexdigest()[:40]
        if not hmac.compare_digest(parts[2], expect):
            return None, None
        return "user", u
    return None, None


def user_active(u):
    st = u.get("status", "active")
    if st == "pending":
        return False, "账号待审核，请联系管理员开通"
    if st == "rejected":
        return False, "账号申请未通过"
    if st == "disabled" or not u.get("enabled", True):
        return False, "账号已停用"
    exp = u.get("expires", 0)
    if exp and exp < time.time():
        return False, "账号已到期"
    return True, ""


REG_RATE = {}


def rate_ok(ip):
    now = time.time()
    rec = [t for t in REG_RATE.get(ip, []) if now - t < 300]
    if len(rec) >= 5:
        REG_RATE[ip] = rec
        return False
    rec.append(now)
    REG_RATE[ip] = rec
    return True


# ------------------------------------------------------------------ 页面
PAGE = open(os.path.join(BASE, "admin_page.html"), encoding="utf-8").read() \
    if os.path.isfile(os.path.join(BASE, "admin_page.html")) else ""


class Handler(BaseHTTPRequestHandler):
    server_version = "DaixuIP/" + VERSION
    admin_user = "admin"
    admin_pwd = "admin888"

    def log_message(self, fmt, *args):
        print("[%s] %s" % (time.strftime("%H:%M:%S"), fmt % args))

    def send_json(self, obj, code=200):
        body = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
        self.end_headers()
        self.wfile.write(body)

    def send_html(self, html):
        body = html.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def body_json(self):
        try:
            n = int(self.headers.get("Content-Length") or 0)
            raw = self.rfile.read(n) if n else b"{}"
            return json.loads(raw or b"{}")
        except Exception:
            return {}

    def auth(self):
        h = self.headers.get("Authorization", "")
        tok = h[7:].strip() if h.startswith("Bearer ") else ""
        return parse_token(tok, self.admin_user, self.admin_pwd)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
        self.end_headers()

    def do_GET(self):
        path = urlparse(self.path).path
        if path in ("/", "/index.html"):
            return self.send_html(PAGE)
        if path == "/api/ping":
            return self.send_json({"ok": True, "version": VERSION, "server": "待续IP系统",
                                   "storage": "sqlite"})

        # App 启动时拉配置（公开，密码只给 hash）
        if path == "/api/config":
            pwd = get_setting("offline_password", "chenjian520")
            return self.send_json({
                "offline_password_sha256": hashlib.sha256(pwd.encode()).hexdigest(),
                "announcement": get_setting("announcement", ""),
                "server": "待续IP系统",
                "version": VERSION,
            })

        role, user = self.auth()

        if path == "/api/nodes":
            if not role:
                return self.send_json({"error": "unauthorized"}, 401)
            if role == "user":
                g = (user.get("group") or "").strip()
                items = list_nodes(group=g if g else None, only_enabled=True)
            else:
                items = list_nodes()
            return self.send_json({"nodes": items, "updated": int(time.time())})

        if path == "/api/users":
            if role != "admin":
                return self.send_json({"error": "unauthorized"}, 401)
            safe = []
            for u in list_users():
                u = dict(u)
                u.pop("pwd", None)
                safe.append(u)
            return self.send_json({"users": safe})

        if path == "/api/me":
            if role != "user":
                return self.send_json({"error": "unauthorized"}, 401)
            ok, why = user_active(user)
            return self.send_json({"username": user["username"], "expires": user.get("expires", 0),
                                   "enabled": user.get("enabled", True), "active": ok,
                                   "group": user.get("group", ""), "reason": why,
                                   "server": "待续IP系统"})

        if path == "/api/settings":
            if role != "admin":
                return self.send_json({"error": "unauthorized"}, 401)
            return self.send_json({"offline_password": get_setting("offline_password", "")})

        self.send_json({"error": "not found"}, 404)

    def do_POST(self):
        path = urlparse(self.path).path
        data = self.body_json()

        # ---- 注册
        if path == "/api/register":
            u = (data.get("username") or "").strip()
            p = data.get("password") or ""
            contact = (data.get("contact") or "").strip()
            if len(u) < 3 or len(p) < 6:
                return self.send_json({"error": "账号至少 3 位，密码至少 6 位"}, 400)
            if not rate_ok(self.client_address[0]):
                return self.send_json({"error": "提交太频繁，请稍后再试"}, 429)
            if get_user_by_name(u):
                return self.send_json({"error": "账号已存在，换一个"}, 400)
            try:
                insert_user({"id": secrets.token_hex(8), "username": u, "pwd": hash_password(p),
                             "plain": p, "expires": 0, "enabled": True, "status": "pending",
                             "group": "", "remark": contact, "created": int(time.time())})
            except sqlite3.IntegrityError:
                return self.send_json({"error": "账号已存在，换一个"}, 400)
            return self.send_json({"ok": True, "message": "提交成功，等待管理员开通"})

        # ---- 管理员登录
        if path == "/api/login":
            u = (data.get("username") or "").strip()
            p = data.get("password") or ""
            if u == self.admin_user and hmac.compare_digest(p, self.admin_pwd):
                return self.send_json({"token": admin_token(self.admin_user, self.admin_pwd),
                                       "role": "admin", "server": "待续IP系统", "version": VERSION})
            time.sleep(0.4)
            return self.send_json({"error": "管理员账号或密码错误"}, 401)

        # ---- 用户登录（App）
        if path == "/api/user/login":
            u = (data.get("username") or "").strip()
            p = data.get("password") or ""
            rec = get_user_by_name(u)
            if not rec or not verify_password(p, rec.get("pwd", "")):
                time.sleep(0.5)
                return self.send_json({"error": "账号或密码错误，请联系管理员开通"}, 401)
            ok, why = user_active(rec)
            if not ok:
                return self.send_json({"error": why}, 403)
            return self.send_json({"token": user_token(rec), "role": "user",
                                   "user": {"username": rec["username"],
                                            "expires": rec.get("expires", 0),
                                            "group": rec.get("group", "")},
                                   "server": "待续IP系统", "version": VERSION})

        role, user = self.auth()
        if not role:
            return self.send_json({"error": "unauthorized"}, 401)

        if path in ("/api/nodes", "/api/nodes/delete", "/api/nodes/bulk") and role != "admin":
            return self.send_json({"error": "没有权限"}, 403)

        # ---- 线路
        if path == "/api/nodes":
            node = data.get("node") or {}
            host = (node.get("host") or "").strip()
            try:
                port = int(node.get("port") or 0)
            except Exception:
                port = 0
            if not host or not (0 < port < 65536):
                return self.send_json({"error": "地址或端口不合法"}, 400)
            item = {"id": node.get("id") or secrets.token_hex(8),
                    "name": (node.get("name") or host).strip(), "host": host, "port": port,
                    "username": node.get("username") or "", "password": node.get("password") or "",
                    "group": node.get("group") or "默认", "enabled": node.get("enabled", True),
                    "protocol": (node.get("protocol") or "socks5").lower()}
            upsert_node(item)
            return self.send_json({"ok": True, "node": item})

        if path == "/api/nodes/delete":
            delete_node(data.get("id"))
            return self.send_json({"ok": True})

        if path == "/api/nodes/bulk":
            added = 0
            for line in (data.get("text") or "").splitlines():
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                item = parse_line(line)
                if item:
                    upsert_node(item)
                    added += 1
            return self.send_json({"ok": True, "added": added})

        # ---- 用户管理
        # ---- 设置（离线密码 / 公告）
        if path == "/api/settings":
            if role != "admin":
                return self.send_json({"error": "没有权限"}, 403)
            pwd = (data.get("offline_password") or "").strip()
            if pwd:
                if len(pwd) < 4:
                    return self.send_json({"error": "密码至少 4 位"}, 400)
                set_setting("offline_password", pwd)
            if "announcement" in data:
                set_setting("announcement", (data.get("announcement") or "").strip())
            return self.send_json({
                "ok": True,
                "offline_password": get_setting("offline_password", ""),
                "announcement": get_setting("announcement", ""),
            })

        if path == "/api/users/approve":
            if role != "admin":
                return self.send_json({"error": "没有权限"}, 403)
            uid = data.get("id")
            if not get_user_by_id(uid):
                return self.send_json({"error": "账号不存在"}, 404)
            days = int(data.get("days") or 30)
            update_user_fields(uid, {"status": "active", "enabled": 1,
                                     "expires": int(time.time() + days * 86400) if days else 0})
            return self.send_json({"ok": True})

        if path == "/api/users":
            if role != "admin":
                return self.send_json({"error": "没有权限"}, 403)
            u = data.get("user") or {}
            if u.get("id"):
                rec = get_user_by_id(u["id"])
                if not rec:
                    return self.send_json({"error": "账号不存在"}, 404)
                fields = {}
                if "enabled" in u:
                    fields["enabled"] = 1 if u["enabled"] else 0
                if u.get("extend_days"):
                    base = max(time.time(), rec.get("expires", 0) or 0)
                    fields["expires"] = int(base + int(u["extend_days"]) * 86400)
                if u.get("password"):
                    fields["pwd"] = hash_password(u["password"])
                    fields["plain"] = u["password"]
                if "group" in u:
                    fields["grp"] = u["group"]
                if "remark" in u:
                    fields["remark"] = u["remark"]
                update_user_fields(u["id"], fields)
                return self.send_json({"ok": True})

            username = (u.get("username") or "").strip()
            password = u.get("password") or ""
            if not username or not password:
                return self.send_json({"error": "账号和密码必填"}, 400)
            if get_user_by_name(username):
                return self.send_json({"error": "账号已存在"}, 400)
            days = int(u.get("days") or 0)
            rec = {"id": secrets.token_hex(8), "username": username, "pwd": hash_password(password),
                   "plain": password,
                   "expires": int(time.time() + days * 86400) if days else 0,
                   "enabled": True, "status": "active", "group": u.get("group") or "",
                   "remark": u.get("remark") or "", "created": int(time.time())}
            insert_user(rec)
            return self.send_json({"ok": True, "user": {k: v for k, v in rec.items() if k != "pwd"}})

        if path == "/api/users/delete":
            if role != "admin":
                return self.send_json({"error": "没有权限"}, 403)
            delete_user(data.get("id"))
            return self.send_json({"ok": True})

        self.send_json({"error": "not found"}, 404)


def parse_line(line):
    parts = line.replace("|", " ").replace("\t", " ").split()
    if len(parts) >= 3 and parts[2].isdigit():
        return {"id": secrets.token_hex(8), "name": parts[0], "host": parts[1],
                "port": int(parts[2]), "username": parts[3] if len(parts) > 3 else "",
                "password": parts[4] if len(parts) > 4 else "", "group": "导入", "enabled": True}
    if ":" in line:
        seg = line.split(":")
        if len(seg) >= 2 and seg[1].isdigit():
            return {"id": secrets.token_hex(8), "name": seg[0], "host": seg[0],
                    "port": int(seg[1]), "username": seg[2] if len(seg) > 2 else "",
                    "password": seg[3] if len(seg) > 3 else "", "group": "导入", "enabled": True}
    return None


def local_ips():
    ips = []
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ips.append(s.getsockname()[0])
        s.close()
    except Exception:
        pass
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None):
            ip = info[4][0]
            if ip not in ips and not ip.startswith("127.") and ":" not in ip:
                ips.append(ip)
    except Exception:
        pass
    return ips


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=int(os.environ.get("PORT", 8787)))
    ap.add_argument("--bind", default="0.0.0.0")
    ap.add_argument("--user", default=os.environ.get("ADMIN_USER", "admin"))
    ap.add_argument("--pass", dest="password", default=os.environ.get("ADMIN_PASS", "admin888"))
    args = ap.parse_args()

    Handler.admin_user = args.user
    Handler.admin_pwd = args.password

    init_db()

    srv = ThreadingHTTPServer((args.bind, args.port), Handler)
    print("=" * 60)
    print("  待续IP系统 · 商业版后台 v%s（SQLite）" % VERSION)
    print("=" * 60)
    print("  电脑打开：   http://127.0.0.1:%d" % args.port)
    for ip in local_ips():
        print("  局域网/公网：http://%s:%d" % (ip, args.port))
    print("  管理员：     %s / %s" % (args.user, args.password))
    print("  数据库：     %s" % DB_FILE)
    print("  账号数：     %d" % len(list_users()))
    print("=" * 60)
    print("  App 只能用「用户管理」里开通的账号登录。")
    print("=" * 60)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\n已停止")


if __name__ == "__main__":
    main()
