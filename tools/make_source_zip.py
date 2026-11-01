#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把工程打包成可直接上传 GitHub / 传到 Mac 的 zip（含 .github 隐藏目录）。"""
import os
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "ProxyOne-source.zip")
SKIP_DIRS = {"build", "Payload", "__pycache__", ".git", "DerivedData", ".venv"}
SKIP_EXT = {".ipa", ".zip", ".xcarchive", ".pyc"}

count = 0
with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as zf:
    for base, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for f in files:
            if os.path.splitext(f)[1] in SKIP_EXT or f == ".DS_Store":
                continue
            full = os.path.join(base, f)
            rel = os.path.relpath(full, ROOT).replace("\\", "/")
            zf.write(full, "ProxyOne/" + rel)
            count += 1

print("wrote %s (%d files, %.1f KB)" % (OUT, count, os.path.getsize(OUT) / 1024))
