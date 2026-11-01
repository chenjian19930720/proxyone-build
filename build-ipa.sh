#!/usr/bin/env bash
# 在任意一台 Mac 上产出「未签名」的 ProxyOne-unsigned.ipa，供 Sideloadly / iOS App Signer 自行签名。
#   bash build-ipa.sh
# 产物：当前目录下的 ProxyOne-unsigned.ipa
set -euo pipefail
cd "$(dirname "$0")"

DERIVED="build"
IPA="ProxyOne-unsigned.ipa"

echo "==> Xcode:"; xcodebuild -version

rm -rf "$DERIVED" Payload "$IPA"

echo "==> 编译（禁止签名，产出 iphoneos arm64）"
xcodebuild \
  -project ProxyOne.xcodeproj \
  -scheme ProxyOne \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath "$DERIVED" \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build

APP="$DERIVED/Build/Products/Release-iphoneos/ProxyOne.app"
if [ ! -d "$APP" ]; then
  echo "!! 没找到 $APP，编译可能失败" >&2
  exit 1
fi
if [ ! -d "$APP/PlugIns/ProxyOneTunnel.appex" ]; then
  echo "!! 警告：ProxyOne.app 里没有 PlugIns/ProxyOneTunnel.appex（全局代理会不工作）" >&2
fi

echo "==> 打包 Payload"
mkdir -p Payload
cp -R "$APP" Payload/
zip -qry "$IPA" Payload
rm -rf Payload

echo "==> 完成：$(pwd)/$IPA"
ls -lh "$IPA"
echo
echo "签名时这两个 entitlements 必须都在："
echo "  App:       com.apple.security.application-groups"
echo "  扩展:      com.apple.developer.networking.networkextension = packet-tunnel-provider"
echo "             com.apple.security.application-groups"
