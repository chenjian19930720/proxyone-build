# 给有 Mac 的人：3 分钟出 ipa

把 `ProxyOne-source.zip` 发给他，让他照下面做就行。**不需要开发者账号，不需要 Xcode 配置，不需要装任何依赖。**

## 步骤

```bash
# 1. 解压
unzip ProxyOne-source.zip
cd ProxyOne

# 2. 一行命令（需要 Xcode 15/16，App Store 里免费装）
bash build-ipa.sh
```

脚本内部就是：

```bash
xcodebuild -project ProxyOne.xcodeproj -scheme ProxyOne \
  -configuration Release -sdk iphoneos -derivedDataPath build \
  ARCHS=arm64 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build
mkdir -p Payload && cp -R build/Build/Products/Release-iphoneos/ProxyOne.app Payload/
zip -qry ProxyOne-unsigned.ipa Payload
```

## 成功标志

```
==> 完成：/Users/xxx/ProxyOne/ProxyOne-unsigned.ipa
-rw-r--r--  1 xxx  staff   ...
```

把 `ProxyOne-unsigned.ipa` 发回来即可（几 MB）。

## 如果报错

| 报错 | 处理 |
|---|---|
| `xcodebuild: error: tool 'xcodebuild' requires Xcode` | 只装了 Command Line Tools，去 App Store 装 Xcode |
| `Signing for "ProxyOneTunnel" requires a development team` | 脚本已经关了签名，出现这行说明用的是旧脚本，确认 `CODE_SIGNING_ALLOWED=NO` 在命令里 |
| `error: unable to find utility "xcodebuild"` | 执行 `sudo xcode-select -s /Applications/Xcode.app` |
| 找不到 `PlugIns/ProxyOneTunnel.appex` | 直接把完整日志发回来 |

## 注意

- 这个 ipa 是**未签名**的，装到手机前要用你自己的证书签（Sideloadly / iOS App Signer / 企业平台）。
- 必须用**付费** Apple Developer 证书，且扩展要开 Network Extensions → Packet Tunnel，否则装上去开关点不动。详见 `SIGNING.md`。
