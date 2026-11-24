// ============================================================================
//  floaty_qx.resource.conf 结构校验
//
//    node test_resource_conf.js
//
//  为什么单独测：
//    QX 的资源文件是「一键导入」的入口，一旦格式错（比如用了 /* */ 注释、
//    段名拼错、规则缺 requires-body），用户拉下来会静默失败 ——
//    规则显示已启用但根本不生效，非常难排查。
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
// 1. 段结构
// ---------------------------------------------------------------------------
console.log("== 1. 段结构 ==");
const sections = [...txt.matchAll(/^\[(\w+)\]/gm)].map((m) => m[1]);
check("有 [MITM] 段", sections.includes("MITM"), sections.join(","));
check("有 [rewrite] 段", sections.includes("rewrite"), sections.join(","));

// ---------------------------------------------------------------------------
// 2. 注释风格：QX 只认 # ; // —— 有 /* */ 会解析失败
// ---------------------------------------------------------------------------
console.log("== 2. 注释风格 ==");
check("没有块注释 /* */", !/\/\*|\*\//.test(txt));

// ---------------------------------------------------------------------------
// 3. MITM 域名
// ---------------------------------------------------------------------------
console.log("== 3. MITM 域名 ==");
const mitmLine = txt.split("\n").find((l) => l.trim().startsWith("hostname"));
check("有 hostname 行", !!mitmLine, "缺失");
if (mitmLine) {
  check("含 api.revenuecat.com", mitmLine.includes("api.revenuecat.com"), mitmLine);
  check("含 api.revenuecat.biz", mitmLine.includes("api.revenuecat.biz"), mitmLine);
}

// ---------------------------------------------------------------------------
// 4. 规则行
// ---------------------------------------------------------------------------
console.log("== 4. 规则行 ==");
const rules = txt
  .split("\n")
  .filter((l) => l.trim())
  .filter((l) => !l.trim().startsWith("#"))
  .filter((l) => !l.trim().startsWith(";"))
  .filter((l) => !l.trim().startsWith("//"))
  .filter((l) => !l.trim().startsWith("["))
  .filter((l) => !l.trim().startsWith("hostname"));

check("恰好 1 条规则", rules.length === 1, "实际 " + rules.length + " 条");
const rule = rules[0] || "";

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
const m = rule.match(/^(\^https\S+)/);
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
// 6. 镜像地址（镜像挂了用户就拉不到）
// ---------------------------------------------------------------------------
console.log("== 6. 镜像地址 ==");
const mirrors = [
  "https://gcore.jsdelivr.net/gh/tangxl00/lingdongdao@main",
  "https://fastly.jsdelivr.net/gh/tangxl00/lingdongdao@main",
  "https://ghproxy.net/https://raw.githubusercontent.com/tangxl00/lingdongdao/main",
];
mirrors.forEach((m) => {
  check("注释里列了镜像 " + m.split("/")[2], txt.includes(m));
});

console.log("");
if (fail === 0) {
  console.log("全部通过 ✅");
  process.exit(0);
}
console.log("有 " + fail + " 项错误 ❌");
process.exit(1);
