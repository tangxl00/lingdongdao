// ============================================================================
// rewrite.conf 正则匹配表测试
//
//   node test_rewrite_regex.js
//
// 为什么要单独测这个：
//   QX 的 [rewrite] 匹配的是**带 query string 的整条 URL**。
//   如果正则写成 /v1/subscribers$，那 /v1/subscribers?x=1 就匹配不到
//   → 规则看似配了却不生效，这是最容易踩的坑。
//   同时必须保证 /v1/products、/v1/offerings **不命中**
//   （改了会让付费页的套餐列表显示不出来）。
// ============================================================================

// 从 rewrite.conf 里读出来测，避免"文档和实现不一致"
const fs = require("fs");
const path = require("path");

const confPath = path.join(__dirname, "rewrite.conf");
const conf = fs.readFileSync(confPath, "utf8");

// 抓出规则整行（正则 + 后面的 all 参数）
const m = conf.match(/^(\^https\S+)\s+(url\s+script-response-body\s+\S+.*)$/m);
if (!m) {
  console.error("FAIL: rewrite.conf 里找不到 script-response-body 规则");
  process.exit(1);
}
const re = new RegExp(m[1]);
const fullRule = m[1] + " " + m[2];

const cases = [
  // [url, expected, note]
  ["https://api.revenuecat.com/v1/subscribers/abc", true, "新版 subscriber"],
  ["https://api.revenuecat.com/v1/subscribers/abc?x=1", true, "新版带 query"],
  ["https://api.revenuecat.com/v1/subscribers", true, "注册 POST（无尾斜杠）"],
  ["https://api.revenuecat.com/v1/subscribers?x=1", true, "注册 POST 带 query"],
  ["https://api.revenuecat.com/v1/subscribers/", true, "带尾斜杠"],
  ["https://api.revenuecat.com/v1/customer/abc", true, "旧版 customer"],
  ["https://api.revenuecat.com/v1/customer/abc?x=1", true, "旧版带 query"],
  ["https://api.revenuecat.biz/v1/subscribers/abc", true, "biz 域名"],
  ["http://api.revenuecat.com/v1/subscribers/abc", true, "明文 http"],

  ["https://api.revenuecat.com/v1/products", false, "products 必须不命中"],
  ["https://api.revenuecat.com/v1/products?x=1", false, "products 带 query"],
  ["https://api.revenuecat.com/v1/offerings", false, "offerings 必须不命中"],
  ["https://api.revenuecat.com/v1/subscribersfoo/abc", false, "前缀伪装"],
  ["https://api.revenuecat.com.evil.net/v1/subscribers/a", false, "域名伪装"],
  ["https://example.com/v1/subscribers/abc", false, "无关域名"],
  ["https://api.revenuecat.com/v2/subscribers/abc", false, "v2 不是目标"],
];

let fail = 0;
console.log("=== rewrite.conf 正则匹配表 ===");
console.log("规则: " + m[1]);
console.log();
cases.forEach(function (c) {
  const url = c[0], want = c[1], note = c[2];
  const got = re.test(url);
  const ok = got === want;
  if (!ok) fail++;
  console.log("  " + (ok ? "PASS" : "FAIL") + "  " + note +
              "   want=" + want + " got=" + got);
});

// 额外校验：规则里必须带 requires-body=true，否则 QX 不给 body
console.log();
const hasBody = /requires-body\s*=\s*true/.test(fullRule);
console.log("  " + (hasBody ? "PASS" : "FAIL") + "  规则含 requires-body=true");
if (!hasBody) fail++;

// 额外校验：脚本 URL 必须指向本仓库
const hasScript = /floaty_qx\.js/.test(fullRule);
console.log("  " + (hasScript ? "PASS" : "FAIL") + "  规则指向 floaty_qx.js");
if (!hasScript) fail++;

console.log();
if (fail === 0) {
  console.log("全部通过 ✅");
  process.exit(0);
} else {
  console.log("有 " + fail + " 项错误 ❌");
  process.exit(1);
}
