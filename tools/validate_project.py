#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Validate project.pbxproj: UUID definitions/references, brace balance, source paths."""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PBX = os.path.join(ROOT, "ProxyOne.xcodeproj", "project.pbxproj")
HEX = re.compile(r"\b[0-9A-F]{24}\b")

text = open(PBX, encoding="utf-8").read()
ok = True

# 1) brace balance
depth = 0
in_str = False
prev = ""
for ch in text:
    if ch == '"' and prev != "\\":
        in_str = not in_str
    elif not in_str:
        if ch in "{(":
            depth += 1
        elif ch in "})":
            depth -= 1
            if depth < 0:
                ok = False
                print("FAIL unbalanced: early close")
                break
    prev = ch
if depth != 0:
    ok = False
    print("FAIL unbalanced depth=%d" % depth)
else:
    print("OK   braces balanced")

# 2) definitions vs references
defs = set(re.findall(r"^\t+([0-9A-F]{24}) ", text, re.M))
refs = set(HEX.findall(text)) - defs
if refs:
    ok = False
    print("FAIL dangling refs ->", sorted(refs))
else:
    print("OK   %d objects defined, no dangling refs" % len(defs))

# 3) source files exist
names = re.findall(r"path = ([A-Za-z0-9_.+-]+\.swift);", text)
missing = []
seen = set()
for f in names:
    if f in seen:
        continue
    seen.add(f)
    bases = ("App", "Shared", "Tunnel", os.path.join("Tunnel", "Tun2Socks"))
    if not any(os.path.isfile(os.path.join(ROOT, b, f)) for b in bases):
        missing.append(f)
if missing:
    ok = False
    print("FAIL missing source files ->", missing)
else:
    print("OK   %d swift files resolved" % len(seen))

# 4) plist / entitlements
for p in ("Resources/Info.plist", "Resources/ProxyOne.entitlements",
          "Tunnel/Resources/Info.plist", "Tunnel/Resources/ProxyOneTunnel.entitlements"):
    if not os.path.isfile(os.path.join(ROOT, p)):
        ok = False
        print("FAIL missing", p)
if ok:
    print("OK   plists/entitlements present")

print("INFO targets   =", len(re.findall(r"isa = PBXNativeTarget;", text)))
print("INFO buildfiles=", len(re.findall(r"isa = PBXBuildFile;", text)))
sys.exit(0 if ok else 1)
