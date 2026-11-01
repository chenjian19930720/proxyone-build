#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
待续IP系统 · 商业版后台（零依赖，单文件）

功能：
  · 管理员登录后管理「线路」和「用户」
  · 用户必须由管理员开通（账号 / 密码 / 有效期 / 启用状态）
  · App 端只能用已开通的账号登录，登录后自动同步线路，不能自己加线路

启动：
    python admin_server.py --port 8787 --user admin --pass admin888
浏览器打开 http://本机IP:8787
"""
import argparse
import base64
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
NODES_FILE = os.path.join(BASE, "nodes.json")
USERS_FILE = os.path.join(BASE, "users.json")
SECRET_FILE = os.path.join(BASE, ".secret")
LOCK = threading.Lock()

VERSION = "2.0"


# ------------------------------------------------------------------ 存储
def _load(path, key):
    if not os.path.isfile(path):
        return {key: [], "updated": 0}
    try:
        with open(path, encoding="utf-8") as fh:
            d = json.load(fh)
        d.setdefault(key, [])
        d.setdefault("updated", 0)
        return d
    except Exception:
        return {key: [], "updated": 0}


def _save(path, d):
    d["updated"] = int(time.time())
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(d, fh, ensure_ascii=False, indent=2)
    os.replace(tmp, path)


def load_nodes():
    return _load(NODES_FILE, "nodes")


def save_nodes(d):
    _save(NODES_FILE, d)


def load_users():
    return _load(USERS_FILE, "users")


def save_users(d):
    _save(USERS_FILE, d)


def secret_key():
    if os.path.isfile(SECRET_FILE):
        with open(SECRET_FILE, "rb") as fh:
            return fh.read()
    key = secrets.token_bytes(32)
    with open(SECRET_FILE, "wb") as fh:
        fh.write(key)
    return key


SECRET = secret_key()


# ------------------------------------------------------------------ 密码 / token
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
    payload = b64(u["username"])
    sig = hmac.new(SECRET, ("user:%s:%s" % (u["username"], u["pwd"])).encode(), hashlib.sha256).hexdigest()[:40]
    return "us.%s.%s" % (payload, sig)


def parse_token(tok, admin_user, admin_pwd):
    """返回 ("admin", None) / ("user", user_dict) / (None, None)"""
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
        with LOCK:
            d = load_users()
        u = next((x for x in d["users"] if x["username"] == username), None)
        if not u:
            return None, None
        expect = hmac.new(SECRET, ("user:%s:%s" % (u["username"], u["pwd"])).encode(),
                          hashlib.sha256).hexdigest()[:40]
        if not hmac.compare_digest(parts[2], expect):
            return None, None
        return "user", u
    return None, None


def user_active(u):
    if not u.get("enabled", True):
        return False, "账号已停用"
    exp = u.get("expires", 0)
    if exp and exp < time.time():
        return False, "账号已到期"
    return True, ""


# ------------------------------------------------------------------ 页面
PAGE = r"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>待续IP系统 · 商业后台</title>
<style>
  *{box-sizing:border-box;margin:0;padding:0}
  body{font-family:-apple-system,"PingFang SC","Microsoft YaHei",sans-serif;background:#08090f;
       color:#e8ecf5;min-height:100vh;
       background-image:radial-gradient(circle at 15% 0%,rgba(76,144,255,.16),transparent 45%),
                        radial-gradient(circle at 85% 8%,rgba(139,95,255,.13),transparent 42%)}
  .wrap{max-width:1120px;margin:0 auto;padding:30px 20px 80px}
  .brand{display:flex;align-items:center;gap:12px}
  .logo{width:40px;height:40px;border-radius:12px;display:grid;place-items:center;
        background:linear-gradient(135deg,#4c90ff,#8b5fff);font-size:19px}
  h1{font-size:19px;font-weight:700}
  .sub{font-size:11.5px;color:#5d6a85;margin-left:52px;margin-top:4px;margin-bottom:26px}
  .card{background:#11151f;border:1px solid rgba(255,255,255,.07);border-radius:18px;padding:20px}
  .login{max-width:380px;margin:11vh auto 0}
  label{display:block;font-size:11.5px;color:#7c88a3;margin:13px 0 5px}
  input,select{width:100%;padding:11px 13px;border-radius:11px;border:1px solid rgba(255,255,255,.09);
        background:#0b0e16;color:#e8ecf5;font-size:13.5px;outline:none}
  input:focus{border-color:#4c90ff}
  button{cursor:pointer;border:0;border-radius:11px;font-size:13.5px;font-weight:600;
         padding:11px 17px;color:#fff;background:linear-gradient(135deg,#4c90ff,#8b5fff)}
  button.ghost{background:rgba(255,255,255,.07);color:#c8d2e6}
  button.danger{background:rgba(255,80,80,.14);color:#ff6b6b}
  button.sm{padding:6px 11px;font-size:12px;border-radius:9px}
  button:disabled{opacity:.45;cursor:not-allowed}
  .row{display:flex;gap:10px;flex-wrap:wrap}
  .row>*{flex:1;min-width:120px}
  .tabs{display:flex;gap:8px;margin-bottom:16px}
  .tab{padding:9px 18px;border-radius:11px;font-size:13px;cursor:pointer;
       background:rgba(255,255,255,.05);color:#8b97b0}
  .tab.on{background:rgba(76,144,255,.16);color:#7fb0ff}
  table{width:100%;border-collapse:collapse;font-size:12.5px}
  th{text-align:left;color:#5d6a85;font-weight:600;font-size:10.5px;letter-spacing:.5px;
     text-transform:uppercase;padding:9px 7px;border-bottom:1px solid rgba(255,255,255,.07)}
  td{padding:11px 7px;border-bottom:1px solid rgba(255,255,255,.045)}
  td.mono{font-family:ui-monospace,Menlo,monospace;font-size:11.5px;color:#8f9cb8}
  .tag{display:inline-block;padding:2px 8px;border-radius:20px;font-size:10px;
       background:rgba(76,144,255,.15);color:#6fa8ff}
  .ok{color:#34d399}.warn{color:#ffb020}.bad{color:#ff6b6b}.off{color:#5d6a85}
  .head{display:flex;justify-content:space-between;align-items:center;margin-bottom:14px;gap:12px;flex-wrap:wrap}
  .muted{color:#5d6a85;font-size:11.5px}
  .toast{position:fixed;left:50%;bottom:26px;transform:translateX(-50%);background:#1a2130;
         border:1px solid rgba(255,255,255,.1);padding:11px 18px;border-radius:12px;font-size:13px;
         opacity:0;transition:.25s;pointer-events:none}
  .toast.show{opacity:1}
  .empty{text-align:center;color:#4a5568;padding:38px 0;font-size:12.5px}
  .kv{display:flex;gap:8px;font-size:11px;color:#5d6a85;margin-top:10px;flex-wrap:wrap}
  .kv span{background:rgba(255,255,255,.04);padding:4px 9px;border-radius:7px}
</style>
</head>
<body><div class="wrap"><div id="app"></div></div>
<div class="toast" id="toast"></div>
<script>
const $ = s => document.querySelector(s);
let token = localStorage.getItem('token') || '';
let tab = 'nodes';
let nodes = [], users = [], me = null;

function toast(m){const t=$('#toast');t.textContent=m;t.classList.add('show');
  clearTimeout(window._t);window._t=setTimeout(()=>t.classList.remove('show'),2000);}

async function api(path, body, method){
  const opt={method:method||(body?'POST':'GET'),headers:{'Content-Type':'application/json'}};
  if(token) opt.headers['Authorization']='Bearer '+token;
  if(body) opt.body=JSON.stringify(body);
  const r=await fetch(path,opt);
  if(r.status===401){token='';localStorage.removeItem('token');render();throw new Error('登录已失效');}
  const d=await r.json().catch(()=>({}));
  if(!r.ok) throw new Error(d.error||('HTTP '+r.status));
  return d;
}
const esc=s=>String(s==null?'':s).replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
const fmtDate=ts=>{ if(!ts) return '永久'; const d=new Date(ts*1000);
  return d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+'-'+String(d.getDate()).padStart(2,'0'); };
const daysLeft=ts=>{ if(!ts) return null; return Math.ceil((ts*1000-Date.now())/86400000); };

function render(){
  $('#app').innerHTML = token ? mainPage() : loginPage();
  if(token){ loadAll(); }
}

function loginPage(){
  return `<div class="login">
    <div class="brand"><div class="logo">⚡</div><h1>待续IP系统</h1></div>
    <div class="sub">商业版管理后台</div>
    <div class="card">
      <label>管理员账号</label><input id="u" placeholder="admin">
      <label>密码</label><input id="p" type="password" placeholder="••••••"
        onkeydown="if(event.key==='Enter')doLogin()">
      <div style="height:16px"></div>
      <button style="width:100%" onclick="doLogin()">登 录</button>
    </div></div>`;
}

function mainPage(){
  return `
  <div class="brand"><div class="logo">⚡</div><h1>待续IP系统</h1></div>
  <div class="sub">商业版管理后台 · 用户必须由这里开通</div>
  <div class="tabs">
    <div class="tab ${tab==='nodes'?'on':''}" onclick="switchTab('nodes')">线路管理</div>
    <div class="tab ${tab==='users'?'on':''}" onclick="switchTab('users')">用户管理</div>
    <div style="flex:1"></div>
    <div class="tab" onclick="logout()">退出</div>
  </div>
  <div id="pane"></div>`;
}

function switchTab(t){ tab=t; render(); }

async function loadAll(){
  try{
    if(tab==='nodes'){
      const d = await api('/api/nodes'); nodes = d.nodes||[];
      $('#pane').innerHTML = nodesPane();
    }else{
      const d = await api('/api/users'); users = d.users||[];
      $('#pane').innerHTML = usersPane();
    }
  }catch(e){ toast(e.message); }
}

function nodesPane(){
  return `
  <div class="card" style="margin-bottom:16px">
    <div class="head"><b style="font-size:13.5px">添加线路</b><span class="muted">SOCKS5</span></div>
    <div class="row">
      <input id="n_name" placeholder="名称">
      <input id="n_host" placeholder="服务器 IP / 域名">
      <input id="n_port" placeholder="端口" value="1080">
    </div>
    <div class="row" style="margin-top:10px">
      <input id="n_user" placeholder="用户名（可空）">
      <input id="n_pass" placeholder="密码（可空）">
      <input id="n_group" placeholder="分组，如 香港">
    </div>
    <div style="height:14px"></div>
    <div class="row">
      <button onclick="addNode()">添加线路</button>
      <button class="ghost" onclick="bulkAdd()">批量导入</button>
    </div>
  </div>
  <div class="card">
    <div class="head"><b style="font-size:13.5px">线路列表</b><span class="muted">${nodes.length} 条</span></div>
    ${nodes.length? nodeTable():'<div class="empty">还没有线路</div>'}
  </div>`;
}

function nodeTable(){
  return `<table><thead><tr><th>名称</th><th>服务器</th><th>端口</th><th>分组</th><th>状态</th><th></th></tr></thead><tbody>`
  + nodes.map(n=>`<tr>
      <td>${esc(n.name)}</td><td class="mono">${esc(n.host)}</td><td class="mono">${n.port}</td>
      <td>${n.group?'<span class="tag">'+esc(n.group)+'</span>':'<span class="muted">—</span>'}</td>
      <td class="${n.enabled===false?'off':'ok'}">${n.enabled===false?'停用':'启用'}</td>
      <td style="text-align:right;white-space:nowrap">
        <button class="ghost sm" onclick="toggleNode('${n.id}')">${n.enabled===false?'启用':'停用'}</button>
        <button class="danger sm" onclick="delNode('${n.id}')">删除</button>
      </td></tr>`).join('')+`</tbody></table>`;
}

function usersPane(){
  return `
  <div class="card" style="margin-bottom:16px">
    <div class="head"><b style="font-size:13.5px">开通账号</b><span class="muted">App 只能用这里开的账号登录</span></div>
    <div class="row">
      <input id="u_name" placeholder="账号，如 vip001">
      <input id="u_pass" placeholder="密码">
      <input id="u_days" placeholder="有效天数，留空=永久" value="30">
    </div>
    <div class="row" style="margin-top:10px">
      <input id="u_group" placeholder="线路分组（留空=全部线路）">
      <input id="u_remark" placeholder="备注，如 微信 xxx">
    </div>
    <div style="height:14px"></div>
    <button onclick="addUser()">开通账号</button>
    <div class="kv"><span>账号总数 ${users.length}</span>
      <span>启用 ${users.filter(u=>u.enabled).length}</span>
      <span>已到期 ${users.filter(u=>u.expires&&u.expires<Date.now()/1000).length}</span></div>
  </div>
  <div class="card">
    <div class="head"><b style="font-size:13.5px">账号列表</b>
      <button class="ghost sm" onclick="loadAll()">刷新</button></div>
    ${users.length? userTable():'<div class="empty">还没有账号，上面开一个</div>'}
  </div>`;
}

function userTable(){
  return `<table><thead><tr><th>账号</th><th>密码</th><th>到期</th><th>剩余</th><th>状态</th><th>备注</th><th></th></tr></thead><tbody>`
  + users.map(u=>{
      const left=daysLeft(u.expires);
      const expired=u.expires && u.expires<Date.now()/1000;
      return `<tr>
        <td><b>${esc(u.username)}</b></td>
        <td class="mono">${esc(u.plain||'••••')}</td>
        <td class="mono">${fmtDate(u.expires)}</td>
        <td class="${expired?'bad':(left!==null&&left<7?'warn':'ok')}">${left===null?'永久':(expired?'已过期':left+' 天')}</td>
        <td class="${u.enabled?'ok':'off'}">${u.enabled?'正常':'停用'}</td>
        <td class="muted">${esc(u.remark||'')}</td>
        <td style="text-align:right;white-space:nowrap">
          <button class="ghost sm" onclick="extend('${u.id}')">续期</button>
          <button class="ghost sm" onclick="toggleUser('${u.id}')">${u.enabled?'停用':'启用'}</button>
          <button class="danger sm" onclick="delUser('${u.id}')">删除</button>
        </td></tr>`;}).join('')+`</tbody></table>`;
}

async function doLogin(){
  const username=$('#u').value.trim(), password=$('#p').value;
  try{ const d=await api('/api/login',{username,password});
    token=d.token; localStorage.setItem('token',token); render(); toast('登录成功');
  }catch(e){ toast(e.message); }
}
function logout(){ token=''; localStorage.removeItem('token'); render(); }

async function addNode(){
  const n={name:$('#n_name').value.trim(),host:$('#n_host').value.trim(),
    port:parseInt($('#n_port').value||'0'),username:$('#n_user').value.trim(),
    password:$('#n_pass').value,group:$('#n_group').value.trim()||'默认'};
  if(!n.name||!n.host||!n.port) return toast('名称/地址/端口必填');
  try{ await api('/api/nodes',{node:n}); toast('已添加');
    ['n_name','n_host','n_user','n_pass','n_group'].forEach(k=>$('#'+k).value=''); loadAll();
  }catch(e){ toast(e.message); }
}
async function bulkAdd(){
  const text=prompt('一行一条：\n名称|地址|端口|用户名|密码\n或 地址:端口');
  if(!text) return;
  try{ const d=await api('/api/nodes/bulk',{text}); toast('导入 '+d.added+' 条'); loadAll(); }
  catch(e){ toast(e.message); }
}
async function toggleNode(id){
  const n=nodes.find(x=>x.id===id); if(!n) return;
  try{ await api('/api/nodes',{node:{...n,enabled:n.enabled===false}}); loadAll(); }catch(e){ toast(e.message); }
}
async function delNode(id){
  if(!confirm('删除这条线路？')) return;
  try{ await api('/api/nodes/delete',{id}); toast('已删除'); loadAll(); }catch(e){ toast(e.message); }
}

async function addUser(){
  const username=$('#u_name').value.trim(), password=$('#u_pass').value;
  const days=$('#u_days').value.trim();
  if(!username||!password) return toast('账号和密码必填');
  const body={user:{username,password,days:days?parseInt(days):0,
    group:$('#u_group').value.trim(),remark:$('#u_remark').value.trim()}};
  try{ await api('/api/users',body); toast('已开通');
    ['u_name','u_pass','u_group','u_remark'].forEach(k=>$('#'+k).value=''); loadAll();
  }catch(e){ toast(e.message); }
}
async function toggleUser(id){
  const u=users.find(x=>x.id===id); if(!u) return;
  try{ await api('/api/users',{user:{id:u.id,enabled:!u.enabled}}); loadAll(); }catch(e){ toast(e.message); }
}
async function extend(id){
  const u=users.find(x=>x.id===id); if(!u) return;
  const d=prompt('续期天数（从现在起算）','30');
  if(!d) return;
  try{ await api('/api/users',{user:{id:u.id,extend_days:parseInt(d)}}); toast('已续期'); loadAll(); }
  catch(e){ toast(e.message); }
}
async function delUser(id){
  if(!confirm('删除该账号？删掉后 App 立刻登不进来。')) return;
  try{ await api('/api/users/delete',{id}); toast('已删除'); loadAll(); }catch(e){ toast(e.message); }
}

render();
</script>
</body></html>
"""


# ------------------------------------------------------------------ HTTP
class Handler(BaseHTTPRequestHandler):
    server_version = "DaixuIP/" + VERSION
    admin_user = "admin"
    admin_pwd = "admin888"

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

    def auth(self):
        h = self.headers.get("Authorization", "")
        tok = h[7:].strip() if h.startswith("Bearer ") else ""
        return parse_token(tok, self.admin_user, self.admin_pwd)

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

        role, user = self.auth()

        if path == "/api/nodes":
            if not role:
                return self.send_json({"error": "unauthorized"}, 401)
            with LOCK:
                d = load_nodes()
            items = d["nodes"]
            if role == "user":
                g = (user.get("group") or "").strip()
                items = [n for n in items if n.get("enabled", True) and (not g or n.get("group") == g)]
            return self.send_json({"nodes": items, "updated": d["updated"]})

        if path == "/api/users":
            if role != "admin":
                return self.send_json({"error": "unauthorized"}, 401)
            with LOCK:
                d = load_users()
            safe = [dict(u, pwd="") for u in d["users"]]
            return self.send_json({"users": safe})

        if path == "/api/me":
            if role != "user":
                return self.send_json({"error": "unauthorized"}, 401)
            ok, why = user_active(user)
            return self.send_json({"username": user["username"], "expires": user.get("expires", 0),
                                   "enabled": user.get("enabled", True), "active": ok,
                                   "group": user.get("group", ""), "reason": why,
                                   "server": "待续IP系统"})

        self.send_json({"error": "not found"}, 404)

    def do_POST(self):
        path = urlparse(self.path).path
        data = self.body_json()

        # ---------------- 管理员登录
        if path == "/api/login":
            u = (data.get("username") or "").strip()
            p = data.get("password") or ""
            if u == self.admin_user and hmac.compare_digest(p, self.admin_pwd):
                return self.send_json({"token": admin_token(self.admin_user, self.admin_pwd),
                                       "role": "admin", "server": "待续IP系统", "version": VERSION})
            time.sleep(0.4)
            return self.send_json({"error": "管理员账号或密码错误"}, 401)

        # ---------------- 用户登录（App 用）
        if path == "/api/user/login":
            u = (data.get("username") or "").strip()
            p = data.get("password") or ""
            with LOCK:
                d = load_users()
            rec = next((x for x in d["users"] if x["username"] == u), None)
            if not rec or not verify_password(p, rec.get("pwd", "")):
                time.sleep(0.5)
                return self.send_json({"error": "账号或密码错误，请联系管理员开通"}, 401)
            ok, why = user_active(rec)
            if not ok:
                return self.send_json({"error": why}, 403)
            return self.send_json({"token": user_token(rec),
                                   "role": "user",
                                   "user": {"username": rec["username"],
                                            "expires": rec.get("expires", 0),
                                            "group": rec.get("group", "")},
                                   "server": "待续IP系统", "version": VERSION})

        role, user = self.auth()
        if not role:
            return self.send_json({"error": "unauthorized"}, 401)

        # ---------------- 线路（仅管理员可写）
        if path in ("/api/nodes", "/api/nodes/delete", "/api/nodes/bulk") and role != "admin":
            return self.send_json({"error": "没有权限"}, 403)

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
                d = load_nodes()
                nid = node.get("id") or ""
                item = {
                    "id": nid or secrets.token_hex(8),
                    "name": (node.get("name") or host).strip(),
                    "host": host, "port": port,
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
                save_nodes(d)
            return self.send_json({"ok": True, "node": item})

        if path == "/api/nodes/delete":
            nid = data.get("id")
            with LOCK:
                d = load_nodes()
                d["nodes"] = [x for x in d["nodes"] if x["id"] != nid]
                save_nodes(d)
            return self.send_json({"ok": True})

        if path == "/api/nodes/bulk":
            text = data.get("text") or ""
            added = 0
            with LOCK:
                d = load_nodes()
                for line in text.splitlines():
                    line = line.strip()
                    if not line or line.startswith("#"):
                        continue
                    item = parse_line(line)
                    if item:
                        d["nodes"].append(item)
                        added += 1
                save_nodes(d)
            return self.send_json({"ok": True, "added": added})

        # ---------------- 用户管理（仅管理员）
        if path == "/api/users":
            if role != "admin":
                return self.send_json({"error": "没有权限"}, 403)
            u = data.get("user") or {}
            with LOCK:
                d = load_users()
                if u.get("id"):
                    rec = next((x for x in d["users"] if x["id"] == u["id"]), None)
                    if not rec:
                        return self.send_json({"error": "账号不存在"}, 404)
                    if "enabled" in u:
                        rec["enabled"] = bool(u["enabled"])
                    if u.get("extend_days"):
                        base = max(time.time(), rec.get("expires", 0))
                        rec["expires"] = int(base + int(u["extend_days"]) * 86400)
                    if u.get("password"):
                        rec["pwd"] = hash_password(u["password"])
                        rec["plain"] = u["password"]
                    if "group" in u:
                        rec["group"] = u["group"]
                    if "remark" in u:
                        rec["remark"] = u["remark"]
                    save_users(d)
                    return self.send_json({"ok": True})

                username = (u.get("username") or "").strip()
                password = u.get("password") or ""
                if not username or not password:
                    return self.send_json({"error": "账号和密码必填"}, 400)
                if any(x["username"] == username for x in d["users"]):
                    return self.send_json({"error": "账号已存在"}, 400)
                days = int(u.get("days") or 0)
                rec = {
                    "id": secrets.token_hex(8),
                    "username": username,
                    "pwd": hash_password(password),
                    "plain": password,
                    "expires": int(time.time() + days * 86400) if days else 0,
                    "enabled": True,
                    "group": u.get("group") or "",
                    "remark": u.get("remark") or "",
                    "created": int(time.time()),
                }
                d["users"].append(rec)
                save_users(d)
            return self.send_json({"ok": True, "user": {k: v for k, v in rec.items() if k != "pwd"}})

        if path == "/api/users/delete":
            if role != "admin":
                return self.send_json({"error": "没有权限"}, 403)
            uid = data.get("id")
            with LOCK:
                d = load_users()
                d["users"] = [x for x in d["users"] if x["id"] != uid]
                save_users(d)
            return self.send_json({"ok": True})

        self.send_json({"error": "not found"}, 404)


def parse_line(line):
    parts = line.replace("|", " ").replace("\t", " ").split()
    if len(parts) >= 3 and parts[2].isdigit():
        return {"id": secrets.token_hex(8), "name": parts[0], "host": parts[1], "port": int(parts[2]),
                "username": parts[3] if len(parts) > 3 else "",
                "password": parts[4] if len(parts) > 4 else "", "group": "导入",
                "enabled": True, "updated": int(time.time())}
    if ":" in line:
        seg = line.split(":")
        if len(seg) >= 2 and seg[1].isdigit():
            return {"id": secrets.token_hex(8), "name": seg[0], "host": seg[0], "port": int(seg[1]),
                    "username": seg[2] if len(seg) > 2 else "",
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

    Handler.admin_user = args.user
    Handler.admin_pwd = args.password

    srv = ThreadingHTTPServer((args.bind, args.port), Handler)
    print("=" * 60)
    print("  待续IP系统 · 商业版后台已启动")
    print("=" * 60)
    print("  电脑打开：   http://127.0.0.1:%d" % args.port)
    for ip in local_ips():
        print("  局域网/手机：http://%s:%d" % (ip, args.port))
    print("  管理员：     %s / %s" % (args.user, args.password))
    print("  线路数据：   %s" % NODES_FILE)
    print("  用户数据：   %s" % USERS_FILE)
    print("=" * 60)
    print("  注意：App 只能用「用户管理」里开通的账号登录。")
    print("=" * 60)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\n已停止")


if __name__ == "__main__":
    main()
