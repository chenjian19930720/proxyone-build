#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成 ProxyOne.xcodeproj/project.pbxproj + 共享 scheme（不依赖 XcodeGen，也不需要 Mac）。

用法：  python tools/gen_xcodeproj.py
产物：  ProxyOne.xcodeproj/
          project.pbxproj
          xcshareddata/xcschemes/ProxyOne.xcscheme
"""
import hashlib
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJ = "ProxyOne.xcodeproj"
BUNDLE_PREFIX = "com.example"


def uid(key: str) -> str:
    return hashlib.md5(key.encode("utf-8")).hexdigest().upper()[:24]


# ---------------------------------------------------------------- 文件清单
APP_FILES = ["ProxyOneApp.swift", "ContentView.swift", "HomeView.swift", "NodeListView.swift",
             "AccountView.swift", "ServerEditorView.swift", "TunnelManager.swift",
             "DebugView.swift", "Theme.swift", "ShareSheet.swift",
             "SplashView.swift", "LoginView.swift", "SyncView.swift", "AppConfig.swift",
             "RegisterView.swift"]
SHARED_FILES = ["ProxyConfig.swift", "MobileConfig.swift", "SyncConfig.swift", "SimpleHTTP.swift"]
TUNNEL_ROOT_FILES = ["PacketTunnelProvider.swift"]
TUN2SOCKS_FILES = [
    "Tun2Socks.swift",
    "IPPacket.swift",
    "Socks5.swift",
    "TCPRelay.swift",
    "UDPRelay.swift",
    "DNSRelay.swift",
]
APP_RESOURCES = ["Info.plist", "ProxyOne.entitlements"]
TUNNEL_RESOURCES = ["Info.plist", "ProxyOneTunnel.entitlements"]

# ---------------------------------------------------------------- UUID
U = {
    "proj": uid("project"),
    "mainGroup": uid("group:main"),
    "appGroup": uid("group:app"),
    "sharedGroup": uid("group:shared"),
    "tunnelGroup": uid("group:tunnel"),
    "tun2socksGroup": uid("group:tun2socks"),
    "appResGroup": uid("group:resources:app"),
    "tunnelResGroup": uid("group:resources:tunnel"),
    "productsGroup": uid("group:products"),
    "appTarget": uid("target:app"),
    "extTarget": uid("target:ext"),
    "appProduct": uid("product:app"),
    "extProduct": uid("product:ext"),
    "appSources": uid("phase:app:sources"),
    "appFrameworks": uid("phase:app:frameworks"),
    "appResources": uid("phase:app:resources"),
    "appCopy": uid("phase:app:copyfiles"),
    "extSources": uid("phase:ext:sources"),
    "extFrameworks": uid("phase:ext:frameworks"),
    "extResources": uid("phase:ext:resources"),
    "embedBuildFile": uid("buildfile:embed"),
    "file:assets": uid("file:App/Assets.xcassets"),
    "build:assets": uid("build:app:Assets.xcassets"),
    "extDependency": uid("dep:ext"),
    "extProxy": uid("proxy:ext"),
    "projConfigList": uid("configlist:project"),
    "appConfigList": uid("configlist:app"),
    "extConfigList": uid("configlist:ext"),
    "projDebug": uid("config:project:debug"),
    "projRelease": uid("config:project:release"),
    "appDebug": uid("config:app:debug"),
    "appRelease": uid("config:app:release"),
    "extDebug": uid("config:ext:debug"),
    "extRelease": uid("config:ext:release"),
}
for f in APP_FILES:
    U["file:" + f] = uid("file:App/" + f)
    U["build:app:" + f] = uid("build:app:App/" + f)
for f in SHARED_FILES:
    U["file:" + f] = uid("file:Shared/" + f)
    U["build:app:" + f] = uid("build:app:Shared/" + f)
    U["build:ext:" + f] = uid("build:ext:Shared/" + f)
for f in TUNNEL_ROOT_FILES:
    U["file:" + f] = uid("file:Tunnel/" + f)
    U["build:ext:" + f] = uid("build:ext:Tunnel/" + f)
for f in TUN2SOCKS_FILES:
    U["file:" + f] = uid("file:Tunnel/Tun2Socks/" + f)
    U["build:ext:" + f] = uid("build:ext:Tunnel/Tun2Socks/" + f)
for f in APP_RESOURCES:
    U["file:res:" + f] = uid("file:Resources/" + f)
for f in TUNNEL_RESOURCES:
    U["file:tres:" + f] = uid("file:Tunnel/Resources/" + f)

out = []
def line(s="", indent=1):
    out.append("\t" * indent + s if s else "")


# ---------------------------------------------------------------- 构建
line("// !$*UTF8*$!")
line("{")
line("archiveVersion = 1;", 1)
line("classes = {", 1)
line("};", 1)
line("objectVersion = 56;", 1)
line("objects = {", 1)

# PBXBuildFile
line("", 1)
line("/* Begin PBXBuildFile section */", 2)
for f in APP_FILES:
    line(f'{U["build:app:"+f]} /* {f} in Sources */ = {{isa = PBXBuildFile; fileRef = {U["file:"+f]} /* {f} */; }};', 3)
for f in SHARED_FILES:
    line(f'{U["build:app:"+f]} /* {f} in Sources */ = {{isa = PBXBuildFile; fileRef = {U["file:"+f]} /* {f} */; }};', 3)
for f in SHARED_FILES:
    line(f'{U["build:ext:"+f]} /* {f} in Sources */ = {{isa = PBXBuildFile; fileRef = {U["file:"+f]} /* {f} */; }};', 3)
for f in TUNNEL_ROOT_FILES:
    line(f'{U["build:ext:"+f]} /* {f} in Sources */ = {{isa = PBXBuildFile; fileRef = {U["file:"+f]} /* {f} */; }};', 3)
for f in TUN2SOCKS_FILES:
    line(f'{U["build:ext:"+f]} /* {f} in Sources */ = {{isa = PBXBuildFile; fileRef = {U["file:"+f]} /* {f} */; }};', 3)
line(f'{U["embedBuildFile"]} /* ProxyOneTunnel.appex in Embed App Extensions */ = {{isa = PBXBuildFile; fileRef = {U["extProduct"]} /* ProxyOneTunnel.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};', 3)
line(f'{U["build:assets"]} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {U["file:assets"]} /* Assets.xcassets */; }};', 3)
line("/* End PBXBuildFile section */", 2)

# PBXContainerItemProxy
line("", 1)
line("/* Begin PBXContainerItemProxy section */", 2)
line(f'{U["extProxy"]} /* PBXContainerItemProxy */ = {{', 3)
line("isa = PBXContainerItemProxy;", 4)
line(f"containerPortal = {U['proj']} /* Project object */;", 4)
line("proxyType = 1;", 4)
line(f"remoteGlobalIDString = {U['extTarget']};", 4)
line('remoteInfo = ProxyOneTunnel;', 4)
line("};", 3)
line("/* End PBXContainerItemProxy section */", 2)

# PBXCopyFilesBuildPhase
line("", 1)
line("/* Begin PBXCopyFilesBuildPhase section */", 2)
line(f'{U["appCopy"]} /* Embed App Extensions */ = {{', 3)
line("isa = PBXCopyFilesBuildPhase;", 4)
line("buildActionMask = 2147483647;", 4)
line('dstPath = "";', 4)
line("dstSubfolderSpec = 13;", 4)
line("files = (", 4)
line(f'{U["embedBuildFile"]} /* ProxyOneTunnel.appex in Embed App Extensions */,', 5)
line(");", 4)
line('name = "Embed App Extensions";', 4)
line("runOnlyForDeploymentPostprocessing = 0;", 4)
line("};", 3)
line("/* End PBXCopyFilesBuildPhase section */", 2)

# PBXFileReference
line("", 1)
line("/* Begin PBXFileReference section */", 2)
for f in APP_FILES:
    line(f'{U["file:"+f]} /* {f} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {f}; sourceTree = "<group>"; }};', 3)
for f in SHARED_FILES:
    line(f'{U["file:"+f]} /* {f} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {f}; sourceTree = "<group>"; }};', 3)
for f in TUNNEL_ROOT_FILES:
    line(f'{U["file:"+f]} /* {f} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {f}; sourceTree = "<group>"; }};', 3)
for f in TUN2SOCKS_FILES:
    line(f'{U["file:"+f]} /* {f} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {f}; sourceTree = "<group>"; }};', 3)
for f in APP_RESOURCES:
    ftype = "text.plist.xml" if f.endswith(".plist") else "text.plist.entitlements"
    line(f'{U["file:res:"+f]} /* {f} */ = {{isa = PBXFileReference; lastKnownFileType = {ftype}; path = {f}; sourceTree = "<group>"; }};', 3)
for f in TUNNEL_RESOURCES:
    ftype = "text.plist.xml" if f.endswith(".plist") else "text.plist.entitlements"
    line(f'{U["file:tres:"+f]} /* {f} */ = {{isa = PBXFileReference; lastKnownFileType = {ftype}; path = {f}; sourceTree = "<group>"; }};', 3)
line(f'{U["appProduct"]} /* ProxyOne.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = ProxyOne.app; sourceTree = BUILT_PRODUCTS_DIR; }};', 3)
line(f'{U["file:assets"]} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; }};', 3)
line(f'{U["extProduct"]} /* ProxyOneTunnel.appex */ = {{isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = ProxyOneTunnel.appex; sourceTree = BUILT_PRODUCTS_DIR; }};', 3)
line("/* End PBXFileReference section */", 2)

# PBXFrameworksBuildPhase
line("", 1)
line("/* Begin PBXFrameworksBuildPhase section */", 2)
for key, name in (("appFrameworks", "ProxyOne"), ("extFrameworks", "ProxyOneTunnel")):
    line(f'{U[key]} /* Frameworks */ = {{', 3)
    line("isa = PBXFrameworksBuildPhase;", 4)
    line("buildActionMask = 2147483647;", 4)
    line("files = (", 4)
    line(");", 4)
    line("runOnlyForDeploymentPostprocessing = 0;", 4)
    line("};", 3)
line("/* End PBXFrameworksBuildPhase section */", 2)

# PBXGroup
line("", 1)
line("/* Begin PBXGroup section */", 2)

def group(key, comment, children, path=None):
    line(f'{U[key]} /* {comment} */ = {{', 3)
    line("isa = PBXGroup;", 4)
    line("children = (", 4)
    for cid, cname in children:
        line(f"{cid} /* {cname} */,", 5)
    line(");", 4)
    if path:
        line(f"path = {path};", 4)
    line('sourceTree = "<group>";', 4)
    line("};", 3)

group("mainGroup", "Main", [
    (U["appGroup"], "App"),
    (U["sharedGroup"], "Shared"),
    (U["tunnelGroup"], "Tunnel"),
    (U["appResGroup"], "Resources"),
    (U["productsGroup"], "Products"),
])
group("appGroup", "App", [(U["file:" + f], f) for f in APP_FILES] + [(U["file:assets"], "Assets.xcassets")], path="App")
group("sharedGroup", "Shared", [(U["file:" + f], f) for f in SHARED_FILES], path="Shared")
group("tunnelGroup", "Tunnel", [
    (U["file:" + f], f) for f in TUNNEL_ROOT_FILES
] + [
    (U["tun2socksGroup"], "Tun2Socks"),
    (U["tunnelResGroup"], "Resources"),
], path="Tunnel")
group("tun2socksGroup", "Tun2Socks", [(U["file:" + f], f) for f in TUN2SOCKS_FILES], path="Tun2Socks")
group("appResGroup", "Resources", [(U["file:res:" + f], f) for f in APP_RESOURCES], path="Resources")
group("tunnelResGroup", "Resources", [(U["file:tres:" + f], f) for f in TUNNEL_RESOURCES], path="Resources")

# Products group（没有 path）
line(f'{U["productsGroup"]} /* Products */ = {{', 3)
line("isa = PBXGroup;", 4)
line("children = (", 4)
line(f'{U["appProduct"]} /* ProxyOne.app */,', 5)
line(f'{U["extProduct"]} /* ProxyOneTunnel.appex */,', 5)
line(");", 4)
line("name = Products;", 4)
line('sourceTree = "<group>";', 4)
line("};", 3)
line("/* End PBXGroup section */", 2)

# PBXNativeTarget
line("", 1)
line("/* Begin PBXNativeTarget section */", 2)
line(f'{U["appTarget"]} /* ProxyOne */ = {{', 3)
line("isa = PBXNativeTarget;", 4)
line(f'buildConfigurationList = {U["appConfigList"]} /* Build configuration list for PBXNativeTarget "ProxyOne" */;', 4)
line("buildPhases = (", 4)
line(f'{U["appSources"]} /* Sources */,', 5)
line(f'{U["appFrameworks"]} /* Frameworks */,', 5)
line(f'{U["appResources"]} /* Resources */,', 5)
line(f'{U["appCopy"]} /* Embed App Extensions */,', 5)
line(");", 4)
line("buildRules = (", 4)
line(");", 4)
line("dependencies = (", 4)
line(f'{U["extDependency"]} /* PBXTargetDependency */,', 5)
line(");", 4)
line("name = ProxyOne;", 4)
line("productName = ProxyOne;", 4)
line(f'productReference = {U["appProduct"]} /* ProxyOne.app */;', 4)
line('productType = "com.apple.product-type.application";', 4)
line("};", 3)

line(f'{U["extTarget"]} /* ProxyOneTunnel */ = {{', 3)
line("isa = PBXNativeTarget;", 4)
line(f'buildConfigurationList = {U["extConfigList"]} /* Build configuration list for PBXNativeTarget "ProxyOneTunnel" */;', 4)
line("buildPhases = (", 4)
line(f'{U["extSources"]} /* Sources */,', 5)
line(f'{U["extFrameworks"]} /* Frameworks */,', 5)
line(f'{U["extResources"]} /* Resources */,', 5)
line(");", 4)
line("buildRules = (", 4)
line(");", 4)
line("dependencies = (", 4)
line(");", 4)
line("name = ProxyOneTunnel;", 4)
line("productName = ProxyOneTunnel;", 4)
line(f'productReference = {U["extProduct"]} /* ProxyOneTunnel.appex */;', 4)
line('productType = "com.apple.product-type.app-extension";', 4)
line("};", 3)
line("/* End PBXNativeTarget section */", 2)

# PBXProject
line("", 1)
line("/* Begin PBXProject section */", 2)
line(f'{U["proj"]} /* Project object */ = {{', 3)
line("isa = PBXProject;", 4)
line("attributes = {", 4)
line("BuildIndependentTargetsInParallel = 1;", 5)
line("LastSwiftUpdateCheck = 1600;", 5)
line("LastUpgradeCheck = 1600;", 5)
line("TargetAttributes = {", 5)
line(f"{U['appTarget']} = {{", 6)
line("CreatedOnToolsVersion = 16.0;", 7)
line("};", 6)
line(f"{U['extTarget']} = {{", 6)
line("CreatedOnToolsVersion = 16.0;", 7)
line("};", 6)
line("};", 5)
line("};", 4)
line(f'buildConfigurationList = {U["projConfigList"]} /* Build configuration list for PBXProject "ProxyOne" */;', 4)
line('compatibilityVersion = "Xcode 14.0";', 4)
line("developmentRegion = en;", 4)
line("hasScannedForEncodings = 0;", 4)
line("knownRegions = (", 4)
line("en,", 5)
line("Base,", 5)
line('"zh-Hans",', 5)
line(");", 4)
line(f'mainGroup = {U["mainGroup"]};', 4)
line(f'productRefGroup = {U["productsGroup"]} /* Products */;', 4)
line('projectDirPath = "";', 4)
line('projectRoot = "";', 4)
line("targets = (", 4)
line(f'{U["appTarget"]} /* ProxyOne */,', 5)
line(f'{U["extTarget"]} /* ProxyOneTunnel */,', 5)
line(");", 4)
line("};", 3)
line("/* End PBXProject section */", 2)

# PBXResourcesBuildPhase
line("", 1)
line("/* Begin PBXResourcesBuildPhase section */", 2)
line(f'{U["appResources"]} /* Resources */ = {{', 3)
line("isa = PBXResourcesBuildPhase;", 4)
line("buildActionMask = 2147483647;", 4)
line("files = (", 4)
line(f'{U["build:assets"]} /* Assets.xcassets in Resources */,', 5)
line(");", 4)
line("runOnlyForDeploymentPostprocessing = 0;", 4)
line("};", 3)
for key in ("extResources",):
    line(f'{U[key]} /* Resources */ = {{', 3)
    line("isa = PBXResourcesBuildPhase;", 4)
    line("buildActionMask = 2147483647;", 4)
    line("files = (", 4)
    line(");", 4)
    line("runOnlyForDeploymentPostprocessing = 0;", 4)
    line("};", 3)
line("/* End PBXResourcesBuildPhase section */", 2)

# PBXSourcesBuildPhase
line("", 1)
line("/* Begin PBXSourcesBuildPhase section */", 2)
line(f'{U["appSources"]} /* Sources */ = {{', 3)
line("isa = PBXSourcesBuildPhase;", 4)
line("buildActionMask = 2147483647;", 4)
line("files = (", 4)
for f in APP_FILES:
    line(f'{U["build:app:"+f]} /* {f} in Sources */,', 5)
for f in SHARED_FILES:
    line(f'{U["build:app:"+f]} /* {f} in Sources */,', 5)
line(");", 4)
line("runOnlyForDeploymentPostprocessing = 0;", 4)
line("};", 3)

line(f'{U["extSources"]} /* Sources */ = {{', 3)
line("isa = PBXSourcesBuildPhase;", 4)
line("buildActionMask = 2147483647;", 4)
line("files = (", 4)
for f in TUNNEL_ROOT_FILES:
    line(f'{U["build:ext:"+f]} /* {f} in Sources */,', 5)
for f in TUN2SOCKS_FILES:
    line(f'{U["build:ext:"+f]} /* {f} in Sources */,', 5)
for f in SHARED_FILES:
    line(f'{U["build:ext:"+f]} /* {f} in Sources */,', 5)
line(");", 4)
line("runOnlyForDeploymentPostprocessing = 0;", 4)
line("};", 3)
line("/* End PBXSourcesBuildPhase section */", 2)

# PBXTargetDependency
line("", 1)
line("/* Begin PBXTargetDependency section */", 2)
line(f'{U["extDependency"]} /* PBXTargetDependency */ = {{', 3)
line("isa = PBXTargetDependency;", 4)
line(f'target = {U["extTarget"]} /* ProxyOneTunnel */;', 4)
line(f'targetProxy = {U["extProxy"]} /* PBXContainerItemProxy */;', 4)
line("};", 3)
line("/* End PBXTargetDependency section */", 2)

# XCBuildConfiguration
line("", 1)
line("/* Begin XCBuildConfiguration section */", 2)

PROJECT_COMMON = """\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCLANG_ENABLE_OBJC_WEAK = YES;
\t\t\t\tCLANG_WARN_BOOL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_CONSTANT_CONVERSION = YES;
\t\t\t\tCLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
\t\t\t\tCLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
\t\t\t\tCLANG_WARN_DOCUMENTATION_COMMENTS = YES;
\t\t\t\tCLANG_WARN_EMPTY_BODY = YES;
\t\t\t\tCLANG_WARN_ENUM_CONVERSION = YES;
\t\t\t\tCLANG_WARN_INFINITE_RECURSION = YES;
\t\t\t\tCLANG_WARN_INT_CONVERSION = YES;
\t\t\t\tCLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
\t\t\t\tCLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
\t\t\t\tCLANG_WARN_UNREACHABLE_CODE = YES;
\t\t\t\tCLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;
\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;
\t\t\t\tGCC_WARN_64_TO_32_BIT_CONVERSION = YES;
\t\t\t\tGCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
\t\t\t\tGCC_WARN_UNDECLARED_SELECTOR = YES;
\t\t\t\tGCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
\t\t\t\tGCC_WARN_UNUSED_FUNCTION = YES;
\t\t\t\tGCC_WARN_UNUSED_VARIABLE = YES;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 16.0;
\t\t\t\tLOCALIZATION_PREFERS_STRING_CATALOGS = YES;
\t\t\t\tMTL_FAST_MATH = YES;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";"""

def config(uuid, name, extra_lines):
    line(f"{uuid} /* {name} */ = {{", 3)
    line("isa = XCBuildConfiguration;", 4)
    line("buildSettings = {", 4)
    for l in extra_lines:
        out.append(l)
    line("};", 4)
    line(f"name = {name};", 4)
    line("};", 3)

config(U["projDebug"], "Debug", PROJECT_COMMON.split("\n") + [
    "\t\t\t\tCOPY_PHASE_STRIP = NO;",
    "\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;",
    "\t\t\t\tENABLE_TESTABILITY = YES;",
    "\t\t\t\tGCC_DYNAMIC_NO_PIC = NO;",
    "\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;",
    '\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = (',
    '\t\t\t\t\t"DEBUG=1",',
    '\t\t\t\t\t"$(inherited)",',
    "\t\t\t\t);",
    "\t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;",
    "\t\t\t\tONLY_ACTIVE_ARCH = YES;",
    "\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;",
    '\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";',
])
config(U["projRelease"], "Release", PROJECT_COMMON.split("\n") + [
    "\t\t\t\tCOPY_PHASE_STRIP = NO;",
    '\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";',
    "\t\t\t\tENABLE_NS_ASSERTIONS = NO;",
    "\t\t\t\tMTL_ENABLE_DEBUG_INFO = NO;",
    "\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;",
    '\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-O";',
    "\t\t\t\tVALIDATE_PRODUCT = YES;",
])

APP_SETTINGS = [
    "\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;",
    "\t\t\t\tCODE_SIGN_ENTITLEMENTS = Resources/ProxyOne.entitlements;",
    "\t\t\t\tCODE_SIGN_STYLE = Automatic;",
    "\t\t\t\tCURRENT_PROJECT_VERSION = 1;",
    "\t\t\t\tGENERATE_INFOPLIST_FILE = NO;",
    "\t\t\t\tINFOPLIST_FILE = Resources/Info.plist;",
    '\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (',
    '\t\t\t\t\t"$(inherited)",',
    '\t\t\t\t\t"@executable_path/Frameworks",',
    "\t\t\t\t);",
    "\t\t\t\tMARKETING_VERSION = 1.0;",
    f"\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_PREFIX}.proxyone;",
    '\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";',
    "\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;",
    "\t\t\t\tSWIFT_VERSION = 5.0;",
    '\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";',
]
EXT_SETTINGS = [
    "\t\t\t\tAPPLICATION_EXTENSION_API_ONLY = YES;",
    "\t\t\t\tCODE_SIGN_ENTITLEMENTS = Tunnel/Resources/ProxyOneTunnel.entitlements;",
    "\t\t\t\tCODE_SIGN_STYLE = Automatic;",
    "\t\t\t\tCURRENT_PROJECT_VERSION = 1;",
    "\t\t\t\tGENERATE_INFOPLIST_FILE = NO;",
    "\t\t\t\tINFOPLIST_FILE = Tunnel/Resources/Info.plist;",
    '\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (',
    '\t\t\t\t\t"$(inherited)",',
    '\t\t\t\t\t"@executable_path/Frameworks",',
    '\t\t\t\t\t"@executable_path/../../Frameworks",',
    "\t\t\t\t);",
    "\t\t\t\tMARKETING_VERSION = 1.0;",
    f"\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_PREFIX}.proxyone.tunnel;",
    '\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";',
    "\t\t\t\tSKIP_INSTALL = YES;",
    "\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;",
    "\t\t\t\tSWIFT_VERSION = 5.0;",
    '\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";',
]
config(U["appDebug"], "Debug", APP_SETTINGS)
config(U["appRelease"], "Release", APP_SETTINGS)
config(U["extDebug"], "Debug", EXT_SETTINGS)
config(U["extRelease"], "Release", EXT_SETTINGS)
line("/* End XCBuildConfiguration section */", 2)

# XCConfigurationList
line("", 1)
line("/* Begin XCConfigurationList section */", 2)
for key, comment, dbg, rel in (
    ("projConfigList", 'Build configuration list for PBXProject "ProxyOne"', "projDebug", "projRelease"),
    ("appConfigList", 'Build configuration list for PBXNativeTarget "ProxyOne"', "appDebug", "appRelease"),
    ("extConfigList", 'Build configuration list for PBXNativeTarget "ProxyOneTunnel"', "extDebug", "extRelease"),
):
    line(f'{U[key]} /* {comment} */ = {{', 3)
    line("isa = XCConfigurationList;", 4)
    line("buildConfigurations = (", 4)
    line(f'{U[dbg]} /* Debug */,', 5)
    line(f'{U[rel]} /* Release */,', 5)
    line(");", 4)
    line("defaultConfigurationIsVisible = 0;", 4)
    line("defaultConfigurationName = Release;", 4)
    line("};", 3)
line("/* End XCConfigurationList section */", 2)

line("};", 1)
line(f"rootObject = {U['proj']} /* Project object */;", 1)
line("}")

text = "\n".join(out) + "\n"

# ---------------------------------------------------------------- scheme
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1600"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{U['appTarget']}"
               BuildableName = "ProxyOne.app"
               BlueprintName = "ProxyOne"
               ReferencedContainer = "container:ProxyOne.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{U['appTarget']}"
            BuildableName = "ProxyOne.app"
            BlueprintName = "ProxyOne"
            ReferencedContainer = "container:ProxyOne.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{U['appTarget']}"
            BuildableName = "ProxyOne.app"
            BlueprintName = "ProxyOne"
            ReferencedContainer = "container:ProxyOne.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
'''

# ---------------------------------------------------------------- 写盘
proj_dir = os.path.join(ROOT, PROJ)
scheme_dir = os.path.join(proj_dir, "xcshareddata", "xcschemes")
os.makedirs(scheme_dir, exist_ok=True)

with open(os.path.join(proj_dir, "project.pbxproj"), "w", encoding="utf-8", newline="\n") as fh:
    fh.write(text)
with open(os.path.join(scheme_dir, "ProxyOne.xcscheme"), "w", encoding="utf-8", newline="\n") as fh:
    fh.write(scheme)

print("wrote", os.path.join(proj_dir, "project.pbxproj"), len(text), "bytes")
print("wrote", os.path.join(scheme_dir, "ProxyOne.xcscheme"))
