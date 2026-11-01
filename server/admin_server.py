#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
待续IP系统 · 网页后台（零依赖，单文件）

启动：
    python admin_server.py --port 8787 --user admin --pass admin888

然后用浏览器打开  http://服务器IP:8787
默认账号 admin / admin888（启动参数或环境变量可改）

App 里「设置 → 线路同步」填：
    地址  http://服务器IP:8787
    账号  你在后台的账号
    密码  你在后台的密码
后台加的线路，App 会自动同步。
"""
import argparse
import hashlib
import hmac
import json
import os
import secrets
import socket
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

BASE = os.path.dirname(os.path.abspath(__file__))
DB = os.path.join(BASE, "nodes.json")
SECRET_FILE = os.path.join(BASE, ".secret")
LOCK = threading.Lock()

VERSION = "1.0"


# ------------------------------------------------------------------ 存储
def load_db():
    if not os.path.isfile(DB):
        return {"nodes": [], "updated": 0}
    try:
        with open(DB, encoding="utf-8") as fh:
            d = json.load(fh)
        d.setdefault("nodes", [])
        d.setdefault("updated", 0)
        return d
    except Exception:
        return {"nodes": [], "updated": 0}


def save_db(d):
    d["updated"] = int(time.time())
    tmp = DB + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(d, fh, ensure_ascii=False, indent=2)
    os.replace(tmp, DB)


def secret_key():
    if os.path.isfile(SECRET_FILE):
        with open(SECRET_FILE, "rb") as fh:
            return fh.read()
    key = secrets.token_bytes(32)
    with open(SECRET_FILE, "wb") as fh:
        fh.write(key)
    return key


SECRET = secret_key()


def make_token(user, pwd):
    return hmac.new(SECRET, ("%s:%s:%s" % (user, pwd, VERSION)).encode(), hashlib.sha256).hexdigest()[:40]


# ------------------------------------------------------------------ 页面
PAGE = r"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>待续IP系统 · 线路后台</title>
<style>
  *{box-sizing:border-box;margin:0;padding:0}
  body{font-family:-apple-system,"PingFang SC","Microsoft YaHei",sans-serif;
       background:#08090f;color:#e8ecf5;min-height:100vh;
       background-image:radial-gradient(circle at 15% 0%,rgba(76,144,255,.18),transparent 45%),
                        radial-gradient(circle at 85% 10%,rgba(139,95,255,.14),transparent 40%)}
  .wrap{max-width:1080px;margin:0 auto;padding:32px 20px 80px}
  .brand{display:flex;align-items:center;gap:12px;margin-bottom:6px}
  .logo{width:42px;height:42px;border-radius:13px;display:grid;place-items:center;
        background:linear-gradient(135deg,#4c90ff,#8b5fff);font-size:20px}
  h1{font-size:20px;font-weight:700;letter-spacing:.5px}
  .sub{font-size:12px;color:#5d6a85;margin-left:54px;margin-bottom:28px}
  .card{background:#11151f;border:1px solid rgba(255,255,255,.07);border-radius:18px;padding:22px}
  .login{max-width:380px;margin:12vh auto 0}
  label{display:block;font-size:12px;color:#7c88a3;margin:14px 0 6px}
  input{width:100%;padding:12px 14px;border-radius:12px;border:1px solid rgba(255,255,255,.09);
        background:#0b0e16;color:#e8ecf5;font-size:14px;outline:none}
  input:focus{border-color:#4c90ff}
  button{cursor:pointer;border:0;border-radius:12px;font-size:14px;font-weight:600;
         padding:12px 18px;color:#fff;background:linear-gradient(135deg,#4c90ff,#8b5fff)}
  button.ghost{background:rgba(255,255,255,.07);color:#c8d2e6}
  button.danger{background:rgba(255,80,80,.15);color:#ff6b6b}
  button:disabled{opacity:.5;cursor:not-allowed}
  .row{display:flex;gap:12px;flex-wrap:wrap}
  .row>*{flex:1;min-width:130px}
  table{width:100%;border-collapse:collapse;margin-top:8px;font-size:13px}
  th{text-align:left;color:#5d6a85;font-weight:600;font-size:11px;letter-spacing:.6px;
     text-transform:uppercase;padding:10px 8px;border-bottom:1px solid rgba(255,255,255,.07)}
  td{padding:12px 8px;border-bottom:1px solid rgba(255,255,255,.045)}
  td.mono{font-family:ui-monospace,Menlo,monospace;font-size:12px;color:#8f9cb8}
  .tag{display:inline-block;padding:2px 8px;border-radius:20px;font-size:10px;
       background:rgba(76,144,255,.15);color:#6fa8ff}
  .ok{color:#34d399}.off{color:#5d6a85}
  .head{display:flex;justify-content:space-between;align-items:center;margin-bottom:16px;gap:12px;flex-wrap:wrap}
  .muted{color:#5d6a85;font-size:12px}
  .toast{position:fixed;left:50%;bottom:28px;transform:translateX(-50%);
         background:#1a2130;border:1px solid rgba(255,255,255,.1);padding:11px 18px;
         border-radius:12px;font-size:13px;opacity:0;transition:.25s;pointer-events:none}
  .toast.show{opacity:1}
  .empty{text-align:center;color:#4a5568;padding:42px 0;font-size:13px}
  @media(max-width:680px){th:nth-child(3),td:nth-child(3){display:none}}
</style>
</head>
<body>
<div class="wrap">
  <div id="app"></div>
</div>
<div class="toast" id="toast"></div>
<script>
const $ = s => document.querySelector(s);
let token = localStorage.getItem('token') || '';
let nodes = [];

function toast(msg){
  const t = $('#toast'); t.textContent = msg; t.classList.add('show');
  clearTimeout(window._tt); window._tt = setTimeout(()=>t.classList.remove('show'), 1900);
}

async function api(path, body, method){
  const opt = {method: method || (body ? 'POST' : 'GET'), headers: {'Content-Type':'application/json'}};
  if (token) opt.headers['Authorization'] = 'Bearer ' + token;
  if (body) opt.body = JSON.stringify(body);
  const r = await fetch(path, opt);
  if (r.status === 401) { token = ''; localStorage.removeItem('token'); render(); throw new Error('登录已失效'); }
  const data = await r.json().catch(()=>({}));
  if (!r.ok) throw new Error(data.error || ('HTTP ' + r.status));
  return data;
}

function render(){
  $('#app').innerHTML = token ? mainPage() : loginPage();
  if (token) loadNodes();
}

function loginPage(){
  return `
  <div class="login">
    <div class="brand"><div class="logo">⚡</div><h1>待续IP系统</h1></div>
    <div class="sub">线路管理后台 · 定制版</div>
    <div class="card">
      <label>账号</label><input id="u" placeholder="admin" autocomplete="username">
      <label>密码</label><input id="p" type="password" placeholder="••••••" autocomplete="current-password">
      <div style="height:18px"></div>
      <button style="width:100%" onclick="doLogin()">登 录</button>
    </div>
  </div>`;
}

function mainPage(){
  return `
  <div class="brand"><div class="logo">⚡</div><h1>待续IP系统</h1></div>
  <div class="sub">线路管理后台 · 这里的改动 App 会自动同步</div>

  <div class="card" style="margin-bottom:18px">
    <div class="head"><b style="font-size:14px">添加线路</b>
      <span class="muted">SOCKS5 · 一行一条可批量</span></div>
    <div class="row">
      <input id="name" placeholder="名称，如 香港01">
      <input id="host" placeholder="服务器 IP 或域名">
      <input id="port" placeholder="端口 1080" value="1080">
    </div>
    <div class="row" style="margin-top:12px">
      <input id="user" placeholder="用户名（可空）">
      <input id="pass" placeholder="密码（可空）">
      <input id="group" placeholder="分组，如 香港">
    </div>
    <div style="height:16px"></div>
    <div class="row">
      <button onclick="addNode()">添加线路</button>
      <button class="ghost" onclick="bulkAdd()">批量导入</button>
      <button class="ghost" onclick="logout()">退出登录</button>
    </div>
  </div>

  <div class="card">
    <div class="head"><b style="font-size:14px">线路列表</b>
      <span class="muted" id="count"></span></div>
    <div id="list"></div>
  </div>`;
}

async function doLogin(){
  const username = $('#u').value.trim(), password = $('#p').value;
  try{
    const d = await api('/api/login', {username, password});
    token = d.token; localStorage.setItem('token', token);
    render(); toast('登录成功');
  }catch(e){ toast(e.message); }
}

function logout(){ token=''; localStorage.removeItem('token'); render(); }

async function loadNodes(){
  try{
    const d = await api('/api/nodes');
    nodes = d.nodes || [];
  }catch(e){ nodes = []; }
  $('#count').textContent = nodes.length + ' 条';
  $('#list').innerHTML = nodes.length ? tableHtml() : '<div class="empty">还没有线路，上面添加一条</div>';
}

function tableHtml(){
  return `<table><thead><tr>
    <th>名称</th><th>服务器</th><th>端口</th><th>分组</th><th>状态</th><th></th>
  </tr></thead><tbody>` + nodes.map(n=>`
    <tr>
      <td>${esc(n.name)}</td>
      <td class="mono">${esc(n.host)}</td>
      <td class="mono">${n.port}</td>
      <td>${n.group?'<span class="tag">'+esc(n.group)+'</span>':'<span class="muted">—</span>'}</td>
      <td class="${n.enabled===false?'off':'ok'}">${n.enabled===false?'停用':'启用'}</td>
      <td style="text-align:right;white-space:nowrap">
        <button class="ghost" style="padding:6px 10px;font-size:12px" onclick="toggle('${n.id}')">${n.enabled===false?'启用':'停用'}</button>
        <button class="danger" style="padding:6px 10px;font-size:12px" onclick="del('${n.id}')">删除</button>
      </td>
    </tr>`).join('') + `</tbody></table>`;
}

function esc(s){ return String(s==null?'':s).replace(/[&<>"]/g, c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c])); }

async function addNode(){
  const n = {
    name: $('#name').value.trim(),
    host: $('#host').value.trim(),
    port: parseInt($('#port').value || '0'),
    username: $('#user').value.trim(),
    password: $('#pass').value,
    group: $('#group').value.trim() || '默认'
  };
  if(!n.name || !n.host || !n.port){ toast('名称/地址/端口必填'); return; }
  try{ await api('/api/nodes', {node:n}); toast('已添加'); ['name','host','user','pass','group'].forEach(k=>$('#'+k).value=''); loadNodes(); }
  catch(e){ toast(e.message); }
}

async function bulkAdd(){
  const text = prompt('一行一条，格式：\n名称|地址|端口|用户名|密码\n或 地址:端口');
  if(!text) return;
  try{ const d = await api('/api/nodes/bulk', {text}); toast('导入 '+d.added+' 条'); loadNodes(); }
  catch(e){ toast(e.message); }
}

async function toggle(id){
  const n = nodes.find(x=>x.id===id); if(!n) return;
  try{ await api('/api/nodes', {node:{...n, enabled: n.enabled===false}}); loadNodes(); }
  catch(e){ toast(e.message); }
}

async function del(id){
  if(!confirm('删除这条线路？')) return;
  try{ await api('/api/nodes/delete', {id}); toast('已删除'); loadNodes(); }
  catch(e){ toast(e.message); }
}

render();
</script>
</body>
</html>
"""


# ------------------------------------------------------------------ HTTP
class Handler(BaseHTTPRequestHandler):
    server_version = "DaixuIP/" + VERSION
    user = "admin"
    pwd = "admin888"

    def log_message(self, fmt, *args):
        print("[%s] %s" % (time.strftime("%H:%M:%S"), fmt % args))

    # ---- helpers
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

    def authed(self):
        h = self.headers.get("Authorization", "")
        if not h.startswith("Bearer "):
            return False
        return hmac.compare_digest(h[7:].strip(), make_token(self.user, self.pwd))

    # ---- routes
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
            return self.send_json({"ok": True, "version": VERSION, "server": "待续IP系统"})
        if path == "/api/nodes":
            if not self.authed():
                return self.send_json({"error": "unauthorized"}, 401)
            with LOCK:
                d = load_db()
            return self.send_json({"nodes": d["nodes"], "updated": d["updated"]})
        self.send_json({"error": "not found"}, 404)

    def do_POST(self):
        path = urlparse(self.path).path
        data = self.body_json()

        if path == "/api/login":
            u = (data.get("username") or "").strip()
            p = data.get("password") or ""
            if u == self.user and hmac.compare_digest(p, self.pwd):
                return self.send_json({"token": make_token(self.user, self.pwd),
                                       "server": "待续IP系统", "version": VERSION})
            time.sleep(0.4)
            return self.send_json({"error": "账号或密码错误"}, 401)

        if not self.authed():
            return self.send_json({"error": "unauthorized"}, 401)

        if path == "/api/nodes":
            node = data.get("node") or {}
            host = (node.get("host") or "").strip()
            try:
                port = int(node.get("port") or 0)
            except Exception:
                port = 0
            if not host or not (0 < port < 65536):
                return self.send_json({"error": "地址或端口不合法"}, 400)
            with LOCK:
                d = load_db()
                nid = node.get("id") or ""
                item = {
                    "id": nid or secrets.token_hex(8),
                    "name": (node.get("name") or host).strip(),
                    "host": host,
                    "port": port,
                    "username": node.get("username") or "",
                    "password": node.get("password") or "",
                    "group": node.get("group") or "默认",
                    "enabled": node.get("enabled", True),
                    "updated": int(time.time()),
                }
                idx = next((i for i, x in enumerate(d["nodes"]) if x["id"] == item["id"]), None)
                if idx is None:
                    d["nodes"].append(item)
                else:
                    d["nodes"][idx] = item
                save_db(d)
            return self.send_json({"ok": True, "node": item})

        if path == "/api/nodes/delete":
            nid = data.get("id")
            with LOCK:
                d = load_db()
                d["nodes"] = [x for x in d["nodes"] if x["id"] != nid]
                save_db(d)
            return self.send_json({"ok": True})

        if path == "/api/nodes/bulk":
            text = data.get("text") or ""
            added = 0
            with LOCK:
                d = load_db()
                for line in text.splitlines():
                    line = line.strip()
                    if not line or line.startswith("#"):
                        continue
                    item = parse_line(line)
                    if not item:
                        continue
                    d["nodes"].append(item)
                    added += 1
                save_db(d)
            return self.send_json({"ok": True, "added": added})

        self.send_json({"error": "not found"}, 404)


def parse_line(line):
    parts = line.replace("|", " ").replace("\t", " ").split()
    if len(parts) >= 3 and parts[2].isdigit():
        return {"id": secrets.token_hex(8), "name": parts[0], "host": parts[1],
                "port": int(parts[2]), "username": parts[3] if len(parts) > 3 else "",
                "password": parts[4] if len(parts) > 4 else "", "group": "导入",
                "enabled": True, "updated": int(time.time())}
    if ":" in line:
        seg = line.split(":")
        if len(seg) >= 2 and seg[1].isdigit():
            return {"id": secrets.token_hex(8), "name": seg[0], "host": seg[0],
                    "port": int(seg[1]), "username": seg[2] if len(seg) > 2 else "",
                    "password": seg[3] if len(seg) > 3 else "", "group": "导入",
                    "enabled": True, "updated": int(time.time())}
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

    Handler.user = args.user
    Handler.pwd = args.password

    srv = ThreadingHTTPServer((args.bind, args.port), Handler)
    print("=" * 60)
    print("  待续IP系统 · 线路后台已启动")
    print("=" * 60)
    print("  电脑上打开：  http://127.0.0.1:%d" % args.port)
    for ip in local_ips():
        print("  手机/局域网：  http://%s:%d" % (ip, args.port))
    print("  账号：        %s" % args.user)
    print("  密码：        %s" % args.password)
    print("  数据文件：    %s" % DB)
    print("=" * 60)
    print("  手机打不开 = 手机和电脑不在同一个 WiFi / 网段。")
    print("  Ctrl+C 停止。")
    print("=" * 60)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\n已停止")


if __name__ == "__main__":
    main()
