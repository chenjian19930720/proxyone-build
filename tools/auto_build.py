#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
全自动：GitHub 设备码登录 → 上传工程 → macOS runner 构建 → 下载未签名 ipa。

第一次运行会打印一个 8 位设备码，你只需要在浏览器里输入它（不用创建 PAT）。
授权成功后 token 会存到 .gh_token，之后所有构建都不再需要登录。
"""
import json
import os
import sys
import time
import urllib.parse
import urllib.request

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import cloud_build as cb  # noqa: E402

CLIENT_ID = "178c6fc778ccc68e1d6a"   # GitHub CLI 的公开 OAuth client id
SCOPE = "repo workflow"
DEVICE_URL = "https://github.com/login/device/code"
TOKEN_URL = "https://github.com/login/oauth/access_token"
# 故意放在工程目录之外，避免任何上传路径把它带进仓库
TOKEN_FILE = os.path.join(__import__("tempfile").gettempdir(), "proxyone_gh_token")


def post_form(url, params):
    data = urllib.parse.urlencode(params).encode()
    req = urllib.request.Request(
        url, data=data,
        headers={"Accept": "application/json", "User-Agent": "proxyone-builder"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.loads(resp.read())


def device_login():
    resp = post_form(DEVICE_URL, {"client_id": CLIENT_ID, "scope": SCOPE})
    if "user_code" not in resp:
        raise SystemExit("设备码申请失败: %s" % resp)

    code = resp["user_code"]
    uri = resp.get("verification_uri", "https://github.com/login/device")
    interval = int(resp.get("interval", 5))
    expires = int(resp.get("expires_in", 900))

    print("", flush=True)
    print("=" * 58, flush=True)
    print("  打开   %s" % uri, flush=True)
    print("  输入   %s" % code, flush=True)
    print("  （%d 分钟内有效，授权后本脚本自动继续）" % (expires // 60), flush=True)
    print("=" * 58, flush=True)
    print("", flush=True)
    print("等待授权…", flush=True)

    deadline = time.time() + expires
    while time.time() < deadline:
        time.sleep(interval)
        r = post_form(TOKEN_URL, {
            "client_id": CLIENT_ID,
            "device_code": resp["device_code"],
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
        })
        if "access_token" in r:
            token = r["access_token"]
            with open(TOKEN_FILE, "w", encoding="utf-8") as fh:
                fh.write(token)
            print("授权成功，token 已保存（工程目录之外）", flush=True)
            return token
        err = r.get("error", "")
        if err == "authorization_pending":
            continue
        if err == "slow_down":
            interval += 5
            continue
        if err == "access_denied":
            raise SystemExit("你在页面上拒绝了授权")
        if err == "expired_token":
            raise SystemExit("设备码已过期，请重新运行")
        if err == "device_flow_disabled":
            raise SystemExit("该 OAuth 应用未启用 device flow")
        print("  等待中: %s" % err, flush=True)
    raise SystemExit("等待授权超时")


def get_token():
    tok = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if tok:
        print("使用环境变量里的 token", flush=True)
        return tok
    if os.path.isfile(TOKEN_FILE):
        tok = open(TOKEN_FILE, encoding="utf-8").read().strip()
        if tok:
            print("使用已保存的 token", flush=True)
            return tok
    return device_login()


def main():
    repo = "proxyone-build"
    for i, a in enumerate(sys.argv):
        if a == "--repo" and i + 1 < len(sys.argv):
            repo = sys.argv[i + 1]

    token = get_token()
    api = cb.Api(token)

    files = cb.collect_files()
    print("[1/4] 收集 %d 个文件" % len(files), flush=True)
    print("[2/4] 准备仓库", flush=True)
    owner, branch = cb.ensure_repo(api, repo, private=True)
    print("[3/4] 上传源码", flush=True)
    cb.push_files(api, owner, repo, branch, files)
    print("[4/4] 触发 macOS 构建（约 3-5 分钟）", flush=True)
    run_id = cb.trigger_and_wait(api, owner, repo, branch, 30)
    cb.download_artifact(api, owner, repo, run_id)


if __name__ == "__main__":
    main()
