#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
把 App 内置的服务器地址改成你的公网地址，然后（可选）触发云端构建。

用法：
    python tools/set_backend.py https://ip.example.com
    python tools/set_backend.py http://1.2.3.4:8787 --build
"""
import argparse
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG = os.path.join(ROOT, "App", "AppConfig.swift")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("url", help="例如 https://ip.example.com 或 http://1.2.3.4:8787")
    ap.add_argument("--build", action="store_true", help="改完立刻触发云端构建")
    args = ap.parse_args()

    url = args.url.strip().rstrip("/")
    if not (url.startswith("http://") or url.startswith("https://")):
        url = "https://" + url

    src = open(CONFIG, encoding="utf-8").read()
    new = re.sub(r'static let defaultBackend = "[^"]*"',
                 'static let defaultBackend = "%s"' % url, src)
    if new == src and url not in src:
        print("没找到 defaultBackend，检查 App/AppConfig.swift")
        sys.exit(1)

    open(CONFIG, "w", encoding="utf-8", newline="\n").write(new)
    print("App 内置地址已改为:", url)
    print("提示：App 登录页的「修改」仍然可以临时覆盖这个地址。")

    if args.build:
        print("\n开始云端构建…")
        subprocess.call([sys.executable, os.path.join(ROOT, "tools", "auto_build.py")],
                        cwd=ROOT)


if __name__ == "__main__":
    main()
