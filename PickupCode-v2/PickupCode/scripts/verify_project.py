#!/usr/bin/env python3
"""工程静态一致性验证（沙箱无 Xcode，无法真实编译；此脚本做最大程度的静态核对）。"""
import plistlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
errors, warnings = [], []


def err(msg):
    errors.append(msg)


def warn(msg):
    warnings.append(msg)


# ---------- 1. pbxproj 解析与引用一致性 ----------
pbx = (ROOT / "PickupCode.xcodeproj" / "project.pbxproj").read_text(encoding="utf-8")

# 1a. 括号配平
depth = 0
for ch in pbx:
    if ch == "{":
        depth += 1
    elif ch == "}":
        depth -= 1
    if depth < 0:
        err("pbxproj 括号不配平（多余的 '}'）")
        break
if depth != 0:
    err(f"pbxproj 括号不配平（最终深度 {depth}）")

# 1b. 提取全部定义的对象 ID 与全部被引用的 ID
defined = set(re.findall(r"^\t\t([0-9A-F]{24}) ", pbx, re.M))
if not defined:
    err("未能在 pbxproj 中解析到任何对象定义（24 位 hex ID）")

# 1c. ID 长度检查（pbxproj 中出现的 24 位 hex 字符串必须都是合法对象）
hex24 = set(re.findall(r"\b[0-9A-F]{24}\b", pbx))
bad_len = set(re.findall(r"\b[0-9A-F]{25,}\b", pbx))
if bad_len:
    err(f"发现长度异常的伪 UUID（≥25 位）: {sorted(bad_len)}")

# 引用但未定义 / 定义但从未引用（顶层对象 rootObject 与注释除外）
unreferenced = defined - hex24
for oid in sorted(unreferenced):
    warn(f"对象 {oid} 已定义但未被任何其他对象引用（若为容器/配置对象可忽略）")

# 1d. 每个文件引用的文件真实存在（group path + file path 相对工程根解析）
# 先建立 group id -> 目录路径 映射
group_paths = {}
for m in re.finditer(r"([0-9A-F]{24}) /\* .+? \*/ = \{\s*isa = PBXGroup;(.*?)\};", pbx, re.S):
    gid, body = m.groups()
    pm = re.search(r"path = (.+?);", body)
    if pm:
        group_paths[gid] = pm.group(1)
    elif gid == "000000000000000000000002":
        group_paths[gid] = ""  # mainGroup

# 建立 fileRef -> 所在 group 的映射（在 children 列表里出现）
ref_group = {}
for m in re.finditer(r"([0-9A-F]{24}) /\* .+? \*/ = \{\s*isa = PBXGroup;.*?children = \((.*?)\);", pbx, re.S):
    gid, body = m.groups()
    for child in re.findall(r"([0-9A-F]{24}) ", body):
        ref_group.setdefault(child, gid)

for m in re.finditer(r"([0-9A-F]{24}) /\* (.+?) \*/ = \{isa = PBXFileReference;[^}]*?(?:path = (.+?);)", pbx):
    oid, name, path = m.groups()
    if not path:
        continue
    if "BUILT_PRODUCTS_DIR" in pbx and (path.startswith("PickupCode.app") or path.startswith("PickupCodeWidget.appex")):
        continue  # 构建产物
    parent = group_paths.get(ref_group.get(oid, "000000000000000000000002"), "")
    f = ROOT / parent / path
    if not f.exists():
        err(f"文件引用 {oid} ({parent}/{path}) 在磁盘上不存在")

# 1e. 每个 PBXBuildFile 的 fileRef 均已定义
for m in re.finditer(r"isa = PBXBuildFile; fileRef = ([0-9A-F]{24})", pbx):
    if m.group(1) not in defined:
        err(f"PBXBuildFile 引用了未定义的 fileRef {m.group(1)}")

# 1f. target 依赖与 product 引用
for m in re.finditer(r"target = ([0-9A-F]{24}) /\* PickupCodeWidget \*/", pbx):
    if m.group(1) not in defined:
        err("PBXTargetDependency 引用了未定义的 widget target")

# ---------- 2. Info.plist / entitlements XML 合法性 ----------
for p in [ROOT / "PickupCodeApp" / "Info.plist",
          ROOT / "PickupCodeWidget" / "Info.plist",
          ROOT / "PickupCodeApp" / "PickupCodeApp.entitlements",
          ROOT / "PickupCodeWidget" / "PickupCodeWidget.entitlements"]:
    try:
        with open(p, "rb") as fh:
            plistlib.load(fh)
    except Exception as e:  # noqa: BLE001
        err(f"{p.name} 解析失败: {e}")

# ---------- 3. 关键配置存在性 ----------
main_plist = plistlib.loads((ROOT / "PickupCodeApp" / "Info.plist").read_bytes())
if main_plist.get("NSSupportsLiveActivities") is not True:
    err("主 App Info.plist 缺少 NSSupportsLiveActivities = YES")
schemes = [s for t in main_plist.get("CFBundleURLTypes", []) for s in t.get("CFBundleURLSchemes", [])]
if "pickupcode" not in schemes:
    err(f"主 App URL scheme 注册错误: {schemes}")
widget_plist = plistlib.loads((ROOT / "PickupCodeWidget" / "Info.plist").read_bytes())
ext = widget_plist.get("NSExtension", {}).get("NSExtensionPointIdentifier")
if ext != "com.apple.widgetkit-extension":
    err(f"Widget 扩展点声明错误: {ext}")

# INFOPLIST_FILE / CODE_SIGN_ENTITLEMENTS 指向的文件存在（排除 GENERATE_INFOPLIST_FILE）
for m in re.finditer(r"(?<!GENERATE_)(INFOPLIST_FILE|CODE_SIGN_ENTITLEMENTS) = (.+?);", pbx):
    key, rel = m.groups()
    if not (ROOT / rel).exists():
        err(f"{key} 指向的 {rel} 不存在")

# ---------- 4. 源码层面符号交叉核对 ----------
app_sources = list((ROOT / "PickupCodeApp").glob("*.swift"))
widget_sources = list((ROOT / "PickupCodeWidget").glob("*.swift"))
kit_sources = list((ROOT / "PickupCodeKit").glob("*.swift"))
if len(app_sources) != 6 or len(widget_sources) != 4 or len(kit_sources) != 3:
    warn(f"源码文件数量与预期不符：App {len(app_sources)}/6, Widget {len(widget_sources)}/4, Kit {len(kit_sources)}/3")

all_swift = {p: p.read_text(encoding="utf-8") for p in app_sources + widget_sources + kit_sources}
app_text = "\n".join(all_swift[p] for p in app_sources)
widget_text = "\n".join(all_swift[p] for p in widget_sources)

# 4a. 主 App 独有符号不应泄漏进 Widget
for sym in ["LiveActivityManager", "HistoryStore", "URLSchemeHandler"]:
    if sym in widget_text:
        err(f"Widget target 引用了主 App 独有类型 {sym}（会导致编译失败）")

# 4b. @main 唯一性
for scope, text, who in [("app", app_text, "主 App"), ("widget", widget_text, "Widget")]:
    n = text.count("@main")
    if n != 1:
        err(f"{who} target @main 数量为 {n}（应为 1）")

# 4c. URL 契约字符串一致
if 'static let scheme = "pickupcode"' not in app_text:
    warn("未找到 scheme 常量定义 pickupcode")
for text in (app_text, widget_text):
    if "pickupcode://done?code=" not in text:
        warn("某 target 缺少 done 深链")

# 4d. 常量一致性（App Group / 前缀）
kit_text = "\n".join(all_swift[p] for p in kit_sources)
if 'group.com.yourteam.pickupcode' not in kit_text:
    err("PickupCodeKit 中缺少 App Group 常量")

# 4e. README/SHORTCUTS 契约核对
readme = (ROOT / "README.md").read_text(encoding="utf-8")
shortcuts = (ROOT / "SHORTCUTS.md").read_text(encoding="utf-8")
for doc, name in [(readme, "README.md"), (shortcuts, "SHORTCUTS.md")]:
    for token in ["pickupcode://show", "未知驿站"]:
        if token not in doc:
            warn(f"{name} 缺少契约说明 {token}")
if "Xcode" not in readme:
    err("README 缺少 Xcode 本地编译章节")
if "GitHub Actions" not in readme and "ios-build.yml" not in readme:
    err("README 缺少云端编译附录说明")

workflow = ROOT / ".github" / "workflows" / "ios-build.yml"
if not workflow.exists():
    err("缺少 .github/workflows/ios-build.yml")

# ---------- 5. xcscheme XML 合法性 ----------
import xml.etree.ElementTree as ET

try:
    ET.fromstring((ROOT / "PickupCode.xcodeproj" / "xcshareddata" / "xcschemes" / "PickupCode.xcscheme").read_text(encoding="utf-8"))
except Exception as e:  # noqa: BLE001
    err(f"xcscheme XML 解析失败: {e}")

# ---------- 结果 ----------
print(f"对象定义数: {len(defined)}")
print(f"错误: {len(errors)}")
for e in errors:
    print(f"  [ERROR] {e}")
print(f"警告: {len(warnings)}")
for w in warnings:
    print(f"  [WARN] {w}")
sys.exit(1 if errors else 0)
