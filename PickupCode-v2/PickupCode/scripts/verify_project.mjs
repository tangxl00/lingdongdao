#!/usr/bin/env node
/**
 * 工程静态一致性验证（无 Xcode 环境下做最大程度的静态核对）。
 *
 * 检查项：
 *  1. pbxproj 括号配平、对象 ID 定义/引用一致
 *  2. PBXFileReference 指向的文件真实存在
 *  3. PBXBuildFile 的 fileRef 均已定义
 *  4. 磁盘上的 .swift 文件全部被某个 Sources phase 收录（App / Widget / Kit 三处）
 *  5. 每个 target 的 @main 唯一
 *  6. Info.plist 关键键（URL scheme / NSSupportsLiveActivities / 扩展点）
 *  7. xcscheme XML 结构
 *
 * 用法：node scripts/verify_project.mjs
 */
import { readFileSync, existsSync, readdirSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const errors = [];
const warnings = [];

const err = (m) => errors.push(m);
const warn = (m) => warnings.push(m);

// ---------- 1. pbxproj ----------
const pbx = readFileSync(join(ROOT, "PickupCode.xcodeproj", "project.pbxproj"), "utf8");

let depth = 0;
for (const ch of pbx) {
  if (ch === "{") depth++;
  else if (ch === "}") depth--;
  if (depth < 0) break;
}
if (depth !== 0) err(`pbxproj 括号不配平（最终深度 ${depth}）`);

const defined = new Set([...pbx.matchAll(/^\t\t([0-9A-F]{24}) /gm)].map((m) => m[1]));
if (defined.size === 0) err("未解析到任何 pbxproj 对象定义");

for (const m of pbx.matchAll(/isa = PBXBuildFile; fileRef = ([0-9A-F]{24})/g)) {
  if (!defined.has(m[1])) err(`PBXBuildFile 引用了未定义的 fileRef ${m[1]}`);
}

// group path 映射
const groupPaths = new Map();
for (const m of pbx.matchAll(/([0-9A-F]{24}) \/\* .+? \*\/ = \{\s*isa = PBXGroup;(.*?)\};/gs)) {
  const [, gid, body] = m;
  const pm = body.match(/path = (.+?);/);
  if (pm) groupPaths.set(gid, pm[1]);
  else if (gid === "000000000000000000000002") groupPaths.set(gid, "");
}

// fileRef → group
const refGroup = new Map();
for (const m of pbx.matchAll(/([0-9A-F]{24}) \/\* .+? \*\/ = \{\s*isa = PBXGroup;.*?children = \((.*?)\);/gs)) {
  const [, gid, body] = m;
  for (const child of body.matchAll(/([0-9A-F]{24}) /g)) {
    if (!refGroup.has(child[1])) refGroup.set(child[1], gid);
  }
}

// 文件存在性
const fileRefs = new Map();
for (const m of pbx.matchAll(/([0-9A-F]{24}) \/\* (.+?) \*\/ = \{isa = PBXFileReference;(.*?)\};/g)) {
  const [, oid, name, body] = m;
  const pm = body.match(/path = (.+?);/);
  fileRefs.set(oid, { name, path: pm ? pm[1].replace(/^"|"$/g, "") : null });
}
for (const [oid, ref] of fileRefs) {
  if (!ref.path) continue;
  if (ref.path.endsWith(".app") || ref.path.endsWith(".appex")) continue; // 构建产物
  const parent = groupPaths.get(refGroup.get(oid, "000000000000000000000002")) ?? "";
  if (!existsSync(join(ROOT, parent, ref.path))) {
    err(`文件引用 ${oid} (${parent}/${ref.path}) 在磁盘上不存在`);
  }
}

// ---------- 2. Sources phase 覆盖 ----------
// PBXBuildFile id → fileRef id
const buildFileToRef = new Map();
for (const m of pbx.matchAll(/([0-9A-F]{24}) \/\* .+? \*\/ = \{isa = PBXBuildFile; fileRef = ([0-9A-F]{24})/g)) {
  buildFileToRef.set(m[1], m[2]);
}

const sourcesPhases = [];
for (const m of pbx.matchAll(/([0-9A-F]{24}) \/\* Sources \*\/ = \{\s*isa = PBXSourcesBuildPhase;.*?files = \((.*?)\);/gs)) {
  const refs = [];
  for (const bf of m[2].matchAll(/([0-9A-F]{24}) /g)) {
    const ref = buildFileToRef.get(bf[1]);
    if (ref) refs.push(ref);
  }
  sourcesPhases.push(refs);
}
if (sourcesPhases.length !== 2) err(`期望 2 个 Sources phase，实际 ${sourcesPhases.length}`);

const appSources = new Set(sourcesPhases[0] ?? []);
const widgetSources = new Set(sourcesPhases[1] ?? []);

function swiftFiles(dir) {
  const out = [];
  for (const entry of readdirSync(join(ROOT, dir), { withFileTypes: true })) {
    if (entry.isFile() && entry.name.endsWith(".swift")) out.push(join(dir, entry.name));
  }
  return out;
}

const appDirFiles = swiftFiles("PickupCodeApp");
const widgetDirFiles = swiftFiles("PickupCodeWidget");
const kitDirFiles = swiftFiles("PickupCodeKit");

// 反查 fileRef id
const refByName = new Map();
for (const [oid, ref] of fileRefs) refByName.set(ref.name, oid);

for (const rel of appDirFiles) {
  const name = rel.split(/[\\/]/).pop();
  const oid = refByName.get(name);
  if (!oid) err(`App 源文件 ${rel} 未在 pbxproj 中声明`);
  else if (!appSources.has(oid)) err(`App 源文件 ${rel} 未加入主 App 的 Sources build phase`);
}
for (const rel of widgetDirFiles) {
  const name = rel.split(/[\\/]/).pop();
  const oid = refByName.get(name);
  if (!oid) err(`Widget 源文件 ${rel} 未在 pbxproj 中声明`);
  else if (!widgetSources.has(oid)) err(`Widget 源文件 ${rel} 未加入 Widget 的 Sources build phase`);
}
for (const rel of kitDirFiles) {
  const name = rel.split(/[\\/]/).pop();
  const oid = refByName.get(name);
  if (!oid) err(`Kit 源文件 ${rel} 未在 pbxproj 中声明`);
  else {
    if (!appSources.has(oid)) err(`Kit 源文件 ${rel} 未加入主 App 的 Sources build phase`);
    if (!widgetSources.has(oid)) err(`Kit 源文件 ${rel} 未加入 Widget 的 Sources build phase`);
  }
}

// ---------- 3. @main 唯一性 ----------
const readAll = (files) => files.map((f) => readFileSync(join(ROOT, f), "utf8")).join("\n");
const appText = readAll(appDirFiles);
const widgetText = readAll(widgetDirFiles);
if ((appText.match(/@main/g) ?? []).length !== 1) err(`主 App 的 @main 数量为 ${(appText.match(/@main/g) ?? []).length}（应为 1）`);
if ((widgetText.match(/@main/g) ?? []).length !== 1) err(`Widget 的 @main 数量为 ${(widgetText.match(/@main/g) ?? []).length}（应为 1）`);

// ---------- 4. Widget 不引用 App 独有类型 ----------
for (const sym of ["FloatyStore", "AutoAddEngine", "BoardActivityManager", "ReminderScheduler"]) {
  if (widgetText.includes(sym)) err(`Widget target 引用了主 App 独有类型 ${sym}`);
}

// ---------- 5. Info.plist 关键键 ----------
const appPlist = readFileSync(join(ROOT, "PickupCodeApp", "Info.plist"), "utf8");
if (!appPlist.includes("<string>floaty</string>")) err("主 App Info.plist 未注册 floaty URL scheme");
if (!/<key>NSSupportsLiveActivities<\/key>\s*<true\/>/.test(appPlist)) err("主 App Info.plist 缺少 NSSupportsLiveActivities");
if (!appPlist.includes("<string>shortcuts</string>")) err("主 App Info.plist 缺少 LSApplicationQueriesSchemes=[shortcuts]");

const widgetPlist = readFileSync(join(ROOT, "PickupCodeWidget", "Info.plist"), "utf8");
if (!widgetPlist.includes("com.apple.widgetkit-extension")) err("Widget 扩展点声明错误");

// ---------- 6. URL 契约 ----------
const kitText = readAll(kitDirFiles);
if (!kitText.includes('static let urlScheme = "floaty"')) warn("Kit 中缺少 floaty scheme 常量");
if (!appText.includes("makeDoneURL") && !kitText.includes("makeDoneURL")) warn("缺少 done 深链");
if (!widgetText.includes("floaty://done")) warn("Widget 侧缺少完成按钮的 done 深链");

// ---------- 7. ProAccess（无付费墙） ----------
if (!/enum ProAccess/.test(kitText)) err("缺少 ProAccess（付费能力开关）");
if (!/static let isPro: Bool = true/.test(kitText)) err("ProAccess.isPro 未置为 true（应永久免费）");
if (/import RevenueCat|import StoreKit/.test(appText + kitText + widgetText)) err("工程中仍存在 RevenueCat / StoreKit 依赖");

// ---------- 8. xcscheme ----------
const schemePath = join(ROOT, "PickupCode.xcodeproj", "xcshareddata", "xcschemes", "PickupCode.xcscheme");
if (!existsSync(schemePath)) err("缺少共享 xcscheme");
else {
  const scheme = readFileSync(schemePath, "utf8");
  if (!scheme.includes("BuildableName")) err("xcscheme 内容异常");
  const opens = (scheme.match(/<g /g) ?? []).length;
  const closes = (scheme.match(/<\/g>/g) ?? []).length;
  if (opens !== closes) err("xcscheme XML 标签不配平");
}

// ---------- 9. CI workflow ----------
const wf = join(ROOT, "..", "..", ".github", "workflows", "build.yml");
if (!existsSync(wf)) warn("仓库根缺少 .github/workflows/build.yml");
else {
  const yml = readFileSync(wf, "utf8");
  if (!yml.includes("PickupCode.xcodeproj")) warn("CI 未引用 PickupCode.xcodeproj");
  if (!yml.includes("upload-artifact")) warn("CI 未上传 artifact");
}

// ---------- 输出 ----------
console.log(`对象定义数: ${defined.size}`);
console.log(`App 源文件: ${appDirFiles.length}  Widget: ${widgetDirFiles.length}  Kit: ${kitDirFiles.length}`);
console.log(`错误: ${errors.length}`);
for (const e of errors) console.log(`  [ERROR] ${e}`);
console.log(`警告: ${warnings.length}`);
for (const w of warnings) console.log(`  [WARN] ${w}`);
process.exit(errors.length ? 1 : 0);
