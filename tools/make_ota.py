#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成 iOS OTA 安装页（manifest.plist + index.html + 图标）。

用法：
    python tools/make_ota.py 待续IP系统.ipa --base-url https://ip.你的域名.com/ota

产物在 ota/ 目录：
    index.html          安装页（手机 Safari 打开）
    manifest.plist      iOS 安装清单
    icon.png            图标
    <你的ipa>.ipa       复制过来一起上传

把 ota/ 整个目录上传到服务器的 HTTPS 站点，然后让用户在手机 Safari 打开
    https://ip.你的域名.com/ota/
点「安装」即可。

注意：iOS 要求 manifest 和 ipa 都走 HTTPS；http 链接点安装是没有任何反应的。
"""
import argparse
import os
import plistlib
import shutil
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def read_ipa(ipa_path):
    with zipfile.ZipFile(ipa_path) as z:
        names = z.namelist()
        info_path = next((n for n in names
                          if n.startswith("Payload/") and n.endswith(".app/Info.plist")
                          and n.count("/") == 2), None)
        if not info_path:
            raise SystemExit("这个文件不像 ipa：找不到 Payload/*.app/Info.plist")
        info = plistlib.loads(z.read(info_path))

        icon = None
        for cand in ("AppIcon60x60@2x.png", "AppIcon76x76@2x~ipad.png"):
            hit = next((n for n in names if n.endswith(cand)), None)
            if hit:
                icon = z.read(hit)
                break
    return info, icon


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ipa")
    ap.add_argument("--base-url", required=True,
                    help="https://你的域名/ota   （必须以 / 结尾或不以 / 结尾都行）")
    ap.add_argument("--out", default=os.path.join(ROOT, "ota"))
    args = ap.parse_args()

    ipa = os.path.abspath(args.ipa)
    if not os.path.isfile(ipa):
        raise SystemExit("找不到 ipa: " + ipa)

    base = args.base_url.rstrip("/")
    if not base.startswith("https://"):
        print("!! 警告：iOS 的 OTA 安装只接受 https 链接，http 会点了没反应")

    info, icon = read_ipa(ipa)
    bundle_id = info.get("CFBundleIdentifier", "com.example.proxyone")
    version = info.get("CFBundleShortVersionString", "1.0")
    build = info.get("CFBundleVersion", "1")
    title = info.get("CFBundleDisplayName") or info.get("CFBundleName") or "App"
    ipa_name = os.path.basename(ipa)

    out = args.out
    os.makedirs(out, exist_ok=True)

    # 1. ipa 复制进来
    shutil.copy2(ipa, os.path.join(out, ipa_name))

    # 2. 图标
    if icon:
        with open(os.path.join(out, "icon.png"), "wb") as fh:
            fh.write(icon)

    # 3. manifest.plist
    manifest = {
        "items": [{
            "assets": [
                {"kind": "software-package", "url": "%s/%s" % (base, ipa_name)},
                {"kind": "display-image", "url": "%s/icon.png" % base},
                {"kind": "full-size-image", "url": "%s/icon.png" % base},
            ],
            "metadata": {
                "bundle-identifier": bundle_id,
                "bundle-version": version,
                "kind": "software",
                "title": title,
                "subtitle": "定制版",
            },
        }]
    }
    with open(os.path.join(out, "manifest.plist"), "wb") as fh:
        plistlib.dump(manifest, fh)

    # 4. index.html
    install_url = "itms-services://?action=download-manifest&url=%s/manifest.plist" % base
    html = PAGE_TEMPLATE.format(title=title, version=version, build=build,
                                bundle=bundle_id, install=install_url, size=os.path.getsize(ipa) / 1e6)
    with open(os.path.join(out, "index.html"), "w", encoding="utf-8") as fh:
        fh.write(html)

    print("生成完成：", out)
    print("  bundle id :", bundle_id)
    print("  版本      :", version, "(", build, ")")
    print("  ipa       :", ipa_name, "%.1f MB" % (os.path.getsize(ipa) / 1e6))
    print()
    print("把整个目录传到服务器，手机 Safari 打开：", base + "/")
    print("安装链接：", install_url)
    if not base.startswith("https://"):
        print()
        print("!! 当前不是 https，iOS 不会响应安装请求。先去配 HTTPS 再来。")


PAGE_TEMPLATE = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>{title} · 安装</title>
<style>
  *{{margin:0;padding:0;box-sizing:border-box;-webkit-tap-highlight-color:transparent}}
  body{{font-family:-apple-system,"PingFang SC",sans-serif;background:#08090f;color:#e8ecf5;
       min-height:100vh;display:flex;align-items:center;justify-content:center;padding:24px;
       background-image:radial-gradient(circle at 20% 0%,rgba(76,144,255,.22),transparent 45%),
                        radial-gradient(circle at 80% 10%,rgba(139,95,255,.16),transparent 42%)}}
  .card{{width:100%;max-width:360px;text-align:center}}
  .icon{{width:96px;height:96px;border-radius:24px;margin:0 auto 18px;
         box-shadow:0 12px 40px rgba(76,144,255,.35)}}
  h1{{font-size:21px;font-weight:700;margin-bottom:6px}}
  .ver{{font-size:12px;color:#5d6a85;margin-bottom:26px}}
  .btn{{display:block;padding:16px;border-radius:15px;font-size:16px;font-weight:600;
        color:#fff;text-decoration:none;background:linear-gradient(135deg,#4c90ff,#8b5fff);
        box-shadow:0 8px 26px rgba(76,144,255,.35)}}
  .btn:active{{transform:scale(.98);opacity:.9}}
  .tip{{margin-top:22px;font-size:12px;color:#5d6a85;line-height:1.9;text-align:left;
        background:#11151f;border:1px solid rgba(255,255,255,.07);border-radius:14px;padding:14px 16px}}
  .tip b{{color:#8fa3c7}}
</style>
</head>
<body>
  <div class="card">
    <img class="icon" src="icon.png" alt="">
    <h1>{title}</h1>
    <div class="ver">版本 {version} (build {build}) · {size:.1f} MB</div>
    <a class="btn" href="{install}">安 装</a>
    <div class="tip">
      <b>第一次安装需要：</b><br>
      1. 用 <b>Safari</b> 打开本页（微信/QQ 内置浏览器装不了）<br>
      2. 点「安装」→ 弹窗点「安装」<br>
      3. 装完若提示"未受信任的企业级开发者"，去<br>
         <b>设置 → 通用 → VPN与设备管理</b> 点信任<br>
      <b>包名：</b>{bundle}
    </div>
  </div>
</body>
</html>
"""

if __name__ == "__main__":
    main()
