// ============================================================================
//  floaty_qx.resource.conf 结构校验（按 QX 远程 rewrite 资源的真实规范）
//
//    node test_resource_conf.js
//
//  血的教训：
//    第一版测试断言「必须有 [MITM] / [rewrite] 段头」—— 这是错的。
//    QX 的远程 rewrite 资源是**逐行解析的纯规则列表**，段头和 hostname =
//    行都无法识别，导入时会直接报 "1 problem in sub-resource"。
//    所以本测试现在断言的是「**不能**有段头和 hostname 行」。
// ============================================================================

const fs = require("fs");
const path = require("path");

const confPath = path.join(__dirname, "floaty_qx.resource.conf");
const txt = fs.readFileSync(confPath, "utf8");

let fail = 0;
function check(name, cond, detail) {
  if (!cond) fail++;
  console.log("  " + (cond ? "PASS" : "FAIL") + "  " + name +
              (detail && !cond ? "   -> " + detail : ""));
}

// ---------------------------------------------------------------------------
// 1. 绝不能出现段头（QX 远程资源不认）
// ---------------------------------------------------------------------------
console.log("== 1. 不能有段头（否则 QX 报 problem in sub-resource） ==");
const sectionHeaders = [...txt.matchAll(/^\s*\[[^\]]+\]\s*$/gm)].map((m) =>
  m[0].trim());
check("没有 [rewrite] 段头", !sectionHeaders.some((s) => /\[rewrite\]/i.test(s)),
      sectionHeaders.join(" "));
check("没有 [MITM] 段头", !sectionHeaders.some((s) => /\[MITM\]/i.test(s)),
      sectionHeaders.join(" "));
check("完全没有方括号段头", sectionHeaders.length === 0,
      "发现: " + sectionHeaders.join(" "));

// ---------------------------------------------------------------------------
// 2. 不能有 hostname = 行（那是 .conf 配置文件才有的）
// ---------------------------------------------------------------------------
console.log("== 2. 不能有 hostname 行 ==");
const hostLines = txt.split("\n").filter((l) =>
  /^\s*hostname\s*=/i.test(l));
check("没有 hostname = 行", hostLines.length === 0, hostLines.join(" | "));

// ---------------------------------------------------------------------------
// 3. 注释风格：QX 只认 # ; // —— 有 /* */ 会解析失败
// ---------------------------------------------------------------------------
console.log("== 3. 注释风格 ==");
check("没有块注释 /* */", !/\/\*|\*\//.test(txt));

// ---------------------------------------------------------------------------
// 4. 有效规则行
// ---------------------------------------------------------------------------
console.log("== 4. 规则行 ==");
const rules = txt
  .split("\n")
  .filter((l) => l.trim())
  .filter((l) => !l.trim().startsWith("#"))
  .filter((l) => !l.trim().startsWith(";"))
  .filter((l) => !l.trim().startsWith("//"))
  .filter((l) => !l.trim().startsWith("["));

check("恰好 1 条规则", rules.length === 1, "实际 " + rules.length + " 条");
const rule = rules[0] || "";

check("形如 <url-regex> url <action>", /^\^?\S+\s+url\s+\S+/.test(rule),
      rule.slice(0, 80));
check("含 script-response-body", /script-response-body/.test(rule));
check("含 requires-body=true", /requires-body\s*=\s*true/.test(rule),
      "缺了 QX 不会把响应体交给脚本");
check("含 max-size", /max-size\s*=\s*\d+/.test(rule), "大响应会被截断");
check("含 tag", /tag=/.test(rule));
check("指向 floaty_qx.js", /floaty_qx\.js/.test(rule));
check("脚本 URL 是绝对地址", /script-response-body\s+https?:\/\//.test(rule),
      "QX 不认相对路径");

// ---------------------------------------------------------------------------
// 5. 正则行为
// ---------------------------------------------------------------------------
console.log("== 5. 正则行为 ==");
const m = rule.match(/^(\S+)\s+url\s+/);
check("能抓到正则", !!m);
if (m) {
  const re = new RegExp(m[1]);
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
}

// ---------------------------------------------------------------------------
// 6. 文件必须能逐行安全解析（模拟 QX 的逐行读取）
// ---------------------------------------------------------------------------
console.log("== 6. 逐行可解析性 ==");
let badLines = [];
txt.split("\n").forEach((line, i) => {
  const s = line.trim();
  if (!s) return;
  if (s.startsWith("#") || s.startsWith(";") || s.startsWith("//")) return;
  // 非注释行必须是 <regex> url <action> 形式
  if (!/^\S+\s+url\s+\S+/.test(s)) {
    badLines.push((i + 1) + ": " + s.slice(0, 60));
  }
});
check("所有非注释行都是合法规则", badLines.length === 0, badLines.join(" | "));

console.log("");
if (fail === 0) {
  console.log("全部通过 ✅");
  process.exit(0);
}
console.log("有 " + fail + " 项错误 ❌");
process.exit(1);
