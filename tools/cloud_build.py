#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
没有 Mac 也能出 ipa：把本工程推到 GitHub，用 Actions 的 macOS runner 编译，
再把未签名 ipa 自动下载回本地。

用法：
    set GH_TOKEN=ghp_xxxx                # cmd
    $env:GH_TOKEN="ghp_xxxx"             # PowerShell
    export GH_TOKEN=ghp_xxxx             # macOS / Linux
    python tools/cloud_build.py

可选参数：
    --repo NAME      仓库名（默认 ProxyOne-Build）
    --public         建公开仓库（默认私有）
    --timeout N      等待构建的分钟数（默认 25）

Token：classic PAT 勾 repo + workflow；或 fine-grained token 给
Contents: RW、Actions: RW、Workflows: Write。

成功产物： ./ProxyOne-unsigned.ipa
"""
import argparse
import base64
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile

API = "https://api.github.com"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORKFLOW_FILE = ".github/workflows/build.yml"
WORKFLOW_NAME = "build.yml"
ARTIFACT_NAME = "ProxyOne-unsigned-ipa"
IPA_LOCAL = os.path.join(ROOT, "待续IP系统.ipa")

EXCLUDE_DIRS = {"build", "Payload", "__pycache__", ".git", "DerivedData"}
EXCLUDE_EXT = {".ipa", ".zip", ".xcarchive", ".pyc", ".mobileprovision", ".p12"}
EXCLUDE_NAMES = {".DS_Store", ".gh_token", "_artifact.zip", "ProxyOne-source.zip"}


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class Api:
    def __init__(self, token):
        self.token = token

    def _headers(self):
        return {
            "Authorization": "Bearer " + self.token,
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "proxyone-cloud-build",
        }

    def call(self, method, path, payload=None, allow=(200, 201, 204), retries=5):
        url = path if path.startswith("http") else API + path
        url = urllib.parse.quote(url, safe=":/?#[]@!$&'()*+,;=%")
        data = None
        headers = self._headers()
        if payload is not None:
            data = json.dumps(payload).encode()
            headers["Content-Type"] = "application/json"

        last = None
        for attempt in range(retries):
            req = urllib.request.Request(url, data=data, headers=headers, method=method)
            try:
                with urllib.request.urlopen(req, timeout=120) as resp:
                    body = resp.read()
                    return resp.status, (json.loads(body) if body else None), dict(resp.headers)
            except urllib.error.HTTPError as e:
                body = e.read()
                if e.code in allow:
                    try:
                        return e.code, (json.loads(body) if body else None), dict(e.headers)
                    except json.JSONDecodeError:
                        return e.code, None, dict(e.headers)
                if 500 <= e.code < 600 and attempt + 1 < retries:
                    last = "HTTP %d" % e.code
                    time.sleep(2 * (attempt + 1))
                    continue
                raise SystemExit("[HTTP %d] %s %s\n%s" % (e.code, method, url,
                                                         body.decode("utf-8", "replace")[:600]))
            except Exception as e:                      # 网络抖动 / SSL EOF / 连接被重置
                last = repr(e)
                if attempt + 1 < retries:
                    time.sleep(2 * (attempt + 1))
                    continue
                raise SystemExit("网络错误（已重试 %d 次）：%s" % (retries, last))
        raise SystemExit("网络错误：%s" % last)

    def download(self, url, retries=5):
        last = None
        for attempt in range(retries):
            try:
                return self._download_once(url)
            except SystemExit:
                raise
            except Exception as e:
                last = e
                if attempt + 1 < retries:
                    time.sleep(2 * (attempt + 1))
        raise SystemExit("下载失败（已重试 %d 次）：%r" % (retries, last))

    def _download_once(self, url):
        """GitHub artifact 返回 302 到带签名的存储地址，那一跳不能带 Authorization。"""
        req = urllib.request.Request(url, headers=self._headers())
        opener = urllib.request.build_opener(NoRedirect)
        try:
            with opener.open(req, timeout=120) as resp:
                return resp.read()
        except urllib.error.HTTPError as e:
            if e.code in (301, 302, 303, 307, 308):
                loc = e.headers.get("Location")
                if not loc:
                    raise SystemExit("artifact 重定向缺少 Location")
                with urllib.request.urlopen(loc, timeout=600) as resp:
                    return resp.read()
            raise SystemExit("[HTTP %d] 下载 artifact 失败" % e.code)


def collect_files():
    out = []
    for base, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS]
        for f in files:
            if os.path.splitext(f)[1] in EXCLUDE_EXT:
                continue
            if f in EXCLUDE_NAMES:
                continue
            full = os.path.join(base, f)
            rel = os.path.relpath(full, ROOT).replace("\\", "/")
            out.append((rel, full))
    out.sort()
    return out


def ensure_repo(api, name, private):
    _, me, _ = api.call("GET", "/user")
    owner = me["login"]
    st, repo, _ = api.call("POST", "/user/repos",
                           {"name": name, "private": private, "auto_init": False,
                            "description": "ProxyOne unsigned IPA builder"}, allow=(201, 422))
    if st == 422:
        print("    仓库已存在，复用 %s/%s" % (owner, name))
        _, repo, _ = api.call("GET", "/repos/%s/%s" % (owner, name))
    else:
        print("    已创建 %s/%s (%s)" % (owner, name, "private" if private else "public"))
    return owner, (repo.get("default_branch") or "main")


def blob_sha(data):
    """Git blob SHA1，和 GitHub Contents API 返回的 sha 一致，用来做增量上传。"""
    h = hashlib.sha1()
    h.update(b"blob %d\0" % len(data))
    h.update(data)
    return h.hexdigest()


def put_file(api, owner, repo, branch, rel, full, use_branch):
    data = open(full, "rb").read()
    local_sha = blob_sha(data)
    path = "/repos/%s/%s/contents/%s" % (owner, repo, rel)
    q = ("?ref=" + branch) if use_branch else ""
    st, existing, _ = api.call("GET", path + q, allow=(200, 404))

    remote_sha = existing.get("sha") if (st == 200 and isinstance(existing, dict)) else None
    if remote_sha == local_sha:
        return 304                      # 内容没变，跳过

    payload = {"message": ("update " if remote_sha else "add ") + rel,
               "content": base64.b64encode(data).decode()}
    if remote_sha:
        payload["sha"] = remote_sha
    if use_branch:
        payload["branch"] = branch
    st, _, _ = api.call("PUT", "/repos/%s/%s/contents/%s" % (owner, repo, rel),
                        payload, allow=(200, 201, 404, 409, 422))
    return st


def push_files(api, owner, repo, branch, files):
    first = True
    skipped = 0
    for rel, full in files:
        st = put_file(api, owner, repo, branch, rel, full, use_branch=not first)
        if st not in (200, 201, 304) and first:
            st = put_file(api, owner, repo, branch, rel, full, use_branch=True)
        if st == 304:
            skipped += 1
            first = False
            continue
        if st not in (200, 201):
            if rel == WORKFLOW_FILE:
                raise SystemExit(
                    "写 .github/workflows/build.yml 被拒绝（HTTP %d）。\n"
                    "这是 token 权限问题：classic PAT 需要同时勾选 repo 和 workflow。" % st)
            raise SystemExit("上传 %s 失败（HTTP %d）" % (rel, st))
        print("    ↑ %s" % rel)
        first = False
    if skipped:
        print("    （%d 个文件未改动，已跳过）" % skipped)


def trigger_and_wait(api, owner, repo, branch, timeout_min):
    api.call("POST", "/repos/%s/%s/actions/workflows/%s/dispatches" % (owner, repo, WORKFLOW_NAME),
             {"ref": branch}, allow=(204,))
    print("    已触发 workflow，等待 macOS runner 启动…")
    deadline = time.time() + timeout_min * 60
    last = None
    while time.time() < deadline:
        time.sleep(10)
        _, data, _ = api.call("GET", "/repos/%s/%s/actions/runs?per_page=10" % (owner, repo))
        runs = [r for r in (data or {}).get("workflow_runs", []) if r.get("name") == "build-ipa"]
        if not runs:
            continue
        run = runs[0]
        state = "%s/%s" % (run["status"], run.get("conclusion"))
        if state != last:
            print("    run %s: %s" % (run["id"], state))
            last = state
        if run["status"] == "completed":
            if run.get("conclusion") != "success":
                raise SystemExit("构建失败（%s）。日志：%s" % (run.get("conclusion"), run["html_url"]))
            return run["id"]
    raise SystemExit("等待构建超时（%d 分钟）。可稍后到仓库 Actions 页面下载 artifact。" % timeout_min)


def download_artifact(api, owner, repo, run_id):
    _, data, _ = api.call("GET", "/repos/%s/%s/actions/runs/%s/artifacts" % (owner, repo, run_id))
    arts = [a for a in (data or {}).get("artifacts", []) if a["name"] == ARTIFACT_NAME]
    if not arts:
        raise SystemExit("artifact 列表为空（构建可能刚结束，稍后重试或去 Actions 页面手动下载）")
    art = arts[0]
    print("    下载 artifact %s (%d bytes)" % (art["id"], art["size_in_bytes"]))
    body = api.download(art["archive_download_url"])
    tmp = os.path.join(ROOT, "_artifact.zip")
    with open(tmp, "wb") as fh:
        fh.write(body)
    try:
        with zipfile.ZipFile(tmp) as zf:
            names = zf.namelist()
            print("    zip:", names)
            ipa = next((n for n in names if n.endswith(".ipa")), None)
            if not ipa:
                raise SystemExit("artifact 里没有 .ipa")
            with zf.open(ipa) as src, open(IPA_LOCAL, "wb") as dst:
                dst.write(src.read())
    finally:
        os.remove(tmp)
    print("\n完成 → %s (%.1f MB)" % (IPA_LOCAL, os.path.getsize(IPA_LOCAL) / 1e6))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--token", default=os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN"))
    ap.add_argument("--repo", default="ProxyOne-Build")
    ap.add_argument("--public", action="store_true")
    ap.add_argument("--timeout", type=int, default=25)
    args = ap.parse_args()

    if not args.token:
        raise SystemExit(
            "缺少 token。\n"
            "  1) 打开 https://github.com/settings/tokens/new\n"
            "  2) 勾选 repo 和 workflow\n"
            "  3) set GH_TOKEN=ghp_xxx  然后重新运行本脚本")

    api = Api(args.token)
    files = collect_files()
    print("[1/4] 收集 %d 个文件" % len(files))
    print("[2/4] 准备仓库")
    owner, branch = ensure_repo(api, args.repo, not args.public)
    print("[3/4] 上传源码到 %s/%s @ %s" % (owner, args.repo, branch))
    push_files(api, owner, args.repo, branch, files)
    print("[4/4] 触发 macOS 构建")
    run_id = trigger_and_wait(api, owner, args.repo, branch, args.timeout)
    download_artifact(api, owner, args.repo, run_id)


if __name__ == "__main__":
    main()
