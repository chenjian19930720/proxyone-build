#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
解析一个已签名的 ipa：看它到底能装到哪些设备、带了哪些权限。

用法：
    python tools/inspect_signed.py 桌面上的某个.ipa

会输出：
    · 签名类型（企业 In-House / Ad Hoc / 开发 / 未签名）
    · ProvisionedDevices（绑定设备列表）—— 决定别人能不能装
    · 到期时间
    · entitlements（重点看 Network Extension、App Groups 在不在）
"""
import argparse
import os
import plistlib
import re
import sys
import zipfile

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass


def extract_plist_from_cms(blob):
    """从 CMS(PKCS#7) 包装里把内嵌的 plist 抠出来"""
    start = blob.find(b"<?xml")
    end = blob.rfind(b"</plist>")
    if start < 0 or end < 0:
        return None
    try:
        return plistlib.loads(blob[start:end + 8])
    except Exception:
        return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ipa")
    args = ap.parse_args()

    if not os.path.isfile(args.ipa):
        raise SystemExit("找不到文件: " + args.ipa)

    with zipfile.ZipFile(args.ipa) as z:
        names = z.namelist()
        app_prefix = next((n.split("/")[1] for n in names
                           if n.startswith("Payload/") and n.count("/") >= 1
                           and n.split("/")[1].endswith(".app")), None)
        if not app_prefix:
            raise SystemExit("不是 ipa：找不到 Payload/*.app")

        # 主 App 的 provisioning
        prov_name = "Payload/%s/embedded.mobileprovision" % app_prefix
        if prov_name not in names:
            print("!! 这个 ipa 里没有 embedded.mobileprovision —— 说明【未签名】")
            print("   未签名的包任何 iPhone 都装不上。")
            return

        blob = z.read(prov_name)
        info = extract_plist_from_cms(blob)
        if not info:
            raise SystemExit("解析 mobileprovision 失败（格式异常）")

        print("=" * 60)
        print("主 App：", app_prefix)
        print("=" * 60)

        devs = info.get("ProvisionedDevices") or []
        all_dev = info.get("ProvisionsAllDevices", False)
        name = info.get("Name", "")
        team = (info.get("TeamIdentifier") or ["-"])[0]
        exp = info.get("ExpirationDate")

        if all_dev:
            stype = "企业 In-House（ProvisionsAllDevices = true）"
        elif devs:
            stype = "Ad Hoc / 开发（绑定 %d 台设备）" % len(devs)
        else:
            stype = "未知"

        print("签名类型 :", stype)
        print("Profile  :", name)
        print("Team     :", team)
        print("到期时间 :", str(exp)[:19] if exp else "-")
        print()

        print("── 别人能不能装 ──")
        if all_dev:
            print("✅ 能。企业证书不绑设备，任何 iPhone 都能安装。")
        elif devs:
            print("❌ 不能。只有下面 %d 台设备能装：" % len(devs))
            for d in devs[:20]:
                print("     ", d)
            if len(devs) > 20:
                print("      ... 共", len(devs), "台")
            print()
            print("   要把别人的 UDID 加进这个 profile 才能装 ——")
            print("   需要证书持有者账号权限，共享证书一般做不到。")
        else:
            print("⚠️ 没有设备列表也没有 ProvisionsAllDevices，判断不了")
        print()

        ent = info.get("Entitlements") or {}
        print("── 关键权限 ──")

        def has(key, label):
            v = ent.get(key)
            if v is None:
                print("❌ %s：没有" % label)
            else:
                print("✅ %s：%s" % (label, v))

        has("com.apple.developer.networking.networkextension", "Network Extension（VPN 扩展）")
        has("com.apple.security.application-groups", "App Groups（节点配置共享）")
        print()

        # 扩展的 provisioning
        ext_provs = [n for n in names if n.endswith(".appex/embedded.mobileprovision")]
        if ext_provs:
            print("── 扩展 ──")
            for n in ext_provs:
                bi = extract_plist_from_cms(z.read(n))
                e = (bi or {}).get("Entitlements") or {}
                ne = e.get("com.apple.developer.networking.networkextension")
                ok = ne is not None
                print("%s  %s" % ("✅" if ok else "❌", n.split("/")[-2]))
                if ok:
                    print("      networkextension =", ne)
        else:
            print("!! 没找到扩展的 provisioning —— 扩展可能未签名，VPN 会加载失败")

        print()
        print("── 结论 ──")
        can_install = all_dev or bool(devs)
        ne_ok = ent.get("com.apple.developer.networking.networkextension") is not None
        if all_dev and ne_ok:
            print("✅ 可以直接分发：任何设备能装，VPN 权限在。上传蒲公英即可。")
        elif all_dev and not ne_ok:
            print("⚠️ 别人能装，但这个 profile 没给 VPN 权限，扩展会加载失败。")
        elif devs and ne_ok:
            print("⚠️ VPN 权限在，但只有 %d 台设备能装。要给别人用必须换企业证书。" % len(devs))
        else:
            print("❌ 不能分发。")


if __name__ == "__main__":
    main()
