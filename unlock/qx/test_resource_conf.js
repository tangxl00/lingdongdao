// ============================================================================
//  floaty_qx.resource.conf 结构校验（按 Quantumult X 的真实语法）
//
//    node test_resource_conf.js
//
//  三次踩坑记录（这个测试就是防这三次重演）：
//    ① 第一版：资源文件里写了 [MITM] / [rewrite] 段头 → QX 报 problem
//       （远程资源只接受纯规则行）
//    ② 第二版：加了 requires-body=true / max-size=131072
//       → QX 报"内容无效"（这两个是 **Surge/Loon** 的参数，QX 不认）
//    ③ 第三版：注释里带 912 个中文字符 → QX 对非 ASCII 解析不稳定
//
//  QX 的 rewrite 规则语法只有四段，就这四个空格分隔的部分：
//      <url-regex>  url  <action>  <script-or-target>
//  其中 action 为 script-response-body 时，QX **自动**处理响应体，
//  不需要任何附加参数。
// ============================================================================

const fs = require("fs");
const path = require("path");

const confPath = path.join(__dirname, "floaty_qx.resource.conf");
const txt = fs.readFileSync(confPath, "utf8");
const buf = fs.readFileSync(confPath);

let fail = 0;
function check(name, cond, detail) {
  if (!cond) fail++;
  console.log("  " + (cond ? "PASS" : "FAIL") + "  " + name +
              (detail && !cond ? "   -> " + detail : ""));
}

// ---------------------------------------------------------------------------
// 1. 不能有段头（远程资源只接受纯规则行）
// ---------------------------------------------------------------------------
console.log("== 1. 不能有段头 ==");
const sectionHeaders = [...txt.matchAll(/^\s*\[[^\]]+\]\s*$/gm)].map((m) =>
  m[0].trim());
check("没有任何方括号段头", sectionHeaders.length === 0,
      "发现: " + sectionHeaders.join(" "));

// ---------------------------------------------------------------------------
// 2. 不能有 hostname 行
// ---------------------------------------------------------------------------
console.log("== 2. 不能有 hostname 行 ==");
const hostLines = txt.split("\n").filter((l) => /^\s*hostname\s*=/i.test(l));
check("没有 hostname = 行", hostLines.length === 0, hostLines.join(" | "));

// ---------------------------------------------------------------------------
// 3. 编码：纯 ASCII / 无 BOM / 无 CRLF
// ---------------------------------------------------------------------------
console.log("== 3. 编码 ==");
const nonAscii = [...txt].filter((c) => c.charCodeAt(0) > 127);
check("纯 ASCII（无中文/全角）", nonAscii.length === 0,
      "发现 " + nonAscii.length + " 个非 ASCII 字符");
check("无 UTF-8 BOM",
      !(buf[0] === 0xef && buf[1] === 0xbb && buf[2] === 0xbf));
check("无 CRLF（统一 LF）", buf.indexOf(Buffer.from("\r\n")) === -1);
check("没有块注释 /* */", !/\/\*|\*\//.test(txt));

// ---------------------------------------------------------------------------
// 4. 规则行：必须恰好 4 段，且不能有 Surge/Loon 的附加参数
// ---------------------------------------------------------------------------
console.log("== 4. 规则行语法 ==");
const rules = txt
  .split("\n")
  .filter((l) => l.trim())
  .filter((l) => !l.trim().startsWith("#"))
  .filter((l) => !l.trim().startsWith(";"))
  .filter((l) => !l.trim().startsWith("//"));

check("恰好 1 条规则", rules.length === 1, "实际 " + rules.length + " 条");
const rule = (rules[0] || "").trim();
const parts = rule.split(/\s+/);

check("恰好 4 段（regex url action script）", parts.length === 4,
      "实际 " + parts.length + " 段: " + JSON.stringify(parts.slice(0, 6)));
check("第 2 段是 url", parts[1] === "url", parts[1]);
check("第 3 段是 script-response-body", parts[2] === "script-response-body",
      parts[2]);
check("第 4 段是绝对 URL", /^https?:\/\//.test(parts[3] || ""), parts[3]);

// ★ 关键：这些都是 Surge/Loon 的参数，QX 会判"内容无效"
console.log("  -- QX 不认的 Surge/Loon 参数 --");
check("没有 requires-body", !/requires-body/i.test(rule),
      "算 Surge/Loon 参数，QX 会报内容无效");
check("没有 max-size", !/max-size/i.test(rule),
      "算 Surge/Loon 参数，QX 会报内容无效");
check("没有 tag=", !/\btag\s*=/i.test(rule),
      "算 Surge/Loon 参数，QX 会报内容无效");
check("规则里没有任何逗号参数", !/,/.test(rule),
      "逗号分隔的参数是 Surge/Loon 写法");

check("指向 floaty_qx.js", /floaty_qx\.js/.test(rule));
check("脚本 URL 用固定 commit（非 @main）", !/@main\//.test(rule),
      "用 @main 会拿到 CDN 缓存的旧版");

// ---------------------------------------------------------------------------
// 5. 正则行为
// ---------------------------------------------------------------------------
console.log("== 5. 正则行为 ==");
const re = new RegExp(parts[0]);
const must = [
  "https://api.revenuecat.com/v1/subscribers/abc",
  "https://api.revenuecat.com/v1/subscribers/abc?x=1",
  "https://api.revenuecat.com/v1/subscribers",
  "https://api.revenuecat.com/v1/subscribers?x=1",
  "https://api.revenuecat.com/v1/subscribers/",
  "https://api.revenuecat.com/v1/customer/abc",
  "https://api.revenuecat.com/v1/customer/abc?x=1",
  "https://api.revenuecat.biz/v1/subscribers/abc",
  "http://api.revenuecat.com/v1/subscribers/abc",
];
const mustNot = [
  "https://api.revenuecat.com/v1/products",
  "https://api.revenuecat.com/v1/products?x=1",
  "https://api.revenuecat.com/v1/offerings",
  "https://api.revenuecat.com/v1/subscribersfoo/abc",
  "https://api.revenuecat.com.evil.net/v1/subscribers/a",
  "https://example.com/v1/subscribers/abc",
  "https://api.revenuecat.com/v2/subscribers/abc",
];
must.forEach((u) => check("命中 " + u.replace("https://", ""), re.test(u)));
mustNot.forEach((u) =>
  check("不命中 " + u.replace("https://", ""), !re.test(u)));

// ---------------------------------------------------------------------------
// 6. 逐行可解析性
// ---------------------------------------------------------------------------
console.log("== 6. 逐行可解析性 ==");
const badLines = [];
txt.split("\n").forEach((line, i) => {
  const s = line.trim();
  if (!s) return;
  if (s.startsWith("#") || s.startsWith(";") || s.startsWith("//")) return;
  const p = s.split(/\s+/);
  if (p.length !== 4) {
    badLines.push((i + 1) + ": " + p.length + " 段");
  }
});
check("所有非注释行都是 4 段规则", badLines.length === 0,
      badLines.join(" | "));

console.log("");
if (fail === 0) {
  console.log("全部通过 ✅");
  process.exit(0);
}
console.log("有 " + fail + " 项错误 ❌");
process.exit(1);
