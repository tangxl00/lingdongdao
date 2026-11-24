// ============================================================================
// test_floaty_qx.js — 在模拟的 Quantumult X 运行环境里验证 floaty_qx.js
//
//   node test_floaty_qx.js
//
// 做法：把 floaty_qx.js 读进来，在一个提供 $response / $request 的沙箱里执行，
// 再用 fake_revenuecat.py 里的真实响应形状逐一断言。
// ============================================================================
"use strict";

const fs = require("fs");
const path = require("path");
const vm = require("vm");

const SCRIPT = path.join(__dirname, "floaty_qx.js");
const src = fs.readFileSync(SCRIPT, "utf8");

let failed = 0;

function check(name, cond, detail) {
  if (cond) {
    console.log("  PASS  " + name);
  } else {
    console.log("  FAIL  " + name + "  " + (detail === undefined ? "" : detail));
    failed++;
  }
}

/** 在模拟 QX 环境里执行脚本，返回被改写后的 $response */
function runScript(body, statusCode) {
  const $response = { body: body, statusCode: statusCode === undefined ? 200 : statusCode };
  const $request = { url: "https://api.revenuecat.com/v1/subscribers/test-user", method: "GET" };
  const sandbox = {
    $response: $response,
    $request: $request,
    $done: function () {},
    console: console,
    JSON: JSON,
    Object: Object,
    Array: Array,
    String: String,
    Number: Number,
    Boolean: Boolean,
    Date: Date,
    Math: Math,
    RegExp: RegExp,
    Error: Error,
    parseInt: parseInt,
    parseFloat: parseFloat,
    isNaN: isNaN,
    encodeURIComponent: encodeURIComponent,
    decodeURIComponent: decodeURIComponent,
  };
  vm.createContext(sandbox);
  vm.runInContext(src, sandbox, { filename: "floaty_qx.js" });
  return $response;
}

// ---- 真实 RevenueCat 响应形状（与 fake_revenuecat.py 保持一致）--------------
const SUBSCRIBER = {
  request_date: "2026-11-24T00:00:00Z",
  request_date_ms: 1792790400000,
  subscriber: {
    entitlements: {
      pro: {
        expires_date: "2026-12-01T00:00:00Z",
        grace_period_expires_date: null,
        product_identifier: "floaty_pro_lifetime",
        is_active: false,
        will_renew: false,
        verification: "verified",
        verification_data: "a1b2c3d4",
      },
    },
    active_entitlements: [],
    first_seen: "2026-01-01T00:00:00Z",
  },
};

const CUSTOMER_INFO = {
  customer_info: {
    entitlements: {
      floaty_pro: {
        expires_date: "2026-11-30T00:00:00Z",
        is_active: false,
        will_renew: true,
        verification: "verified",
      },
    },
    active_entitlements: [],
  },
};

const PRODUCTS = { items: [{ identifier: "floaty_pro_lifetime", product_type: "NON_CONSUMABLE" }] };

// ============================================================================
console.log("== 1. /v1/subscribers (新版形状) ==");
{
  const resp = runScript(JSON.stringify(SUBSCRIBER), 200);
  const d = JSON.parse(resp.body);
  const ent = d.subscriber.entitlements.pro;
  check("is_active = true", ent.is_active === true, JSON.stringify(ent));
  check("expires_date = 2099", ent.expires_date === "2099-12-31T23:59:59Z", ent.expires_date);
  check("will_renew = false", ent.will_renew === false, String(ent.will_renew));
  check("verification 已摘除", !("verification" in ent), JSON.stringify(ent));
  check("verification_data 已摘除", !("verification_data" in ent));
  check(
    "active_entitlements 已填充",
    Array.isArray(d.subscriber.active_entitlements) && d.subscriber.active_entitlements.indexOf("pro") >= 0,
    JSON.stringify(d.subscriber.active_entitlements)
  );
  check("product_identifier 保留", ent.product_identifier === "floaty_pro_lifetime", ent.product_identifier);
  check("request_date 未被动", d.request_date === "2026-11-24T00:00:00Z", d.request_date);
}

console.log("== 2. /v1/customer (旧版形状) ==");
{
  const resp = runScript(JSON.stringify(CUSTOMER_INFO), 200);
  const d = JSON.parse(resp.body);
  const ent = d.customer_info.entitlements.floaty_pro;
  check("is_active = true", ent.is_active === true, JSON.stringify(ent));
  check("expires_date = 2099", ent.expires_date === "2099-12-31T23:59:59Z", ent.expires_date);
  check("will_renew = false", ent.will_renew === false, String(ent.will_renew));
  check("verification 已摘除", !("verification" in ent));
}

console.log("== 3. /v1/products 不被改写 ==");
{
  const resp = runScript(JSON.stringify(PRODUCTS), 200);
  check("body 原样保留", resp.body === JSON.stringify(PRODUCTS), resp.body);
}

console.log("== 4. 非 JSON 响应不炸 ==");
{
  let err = null;
  try {
    const resp = runScript("<html>blocked</html>", 200);
    check("body 原样返回", resp.body === "<html>blocked</html>", resp.body);
  } catch (e) {
    err = e;
  }
  check("未抛异常", err === null, err ? String(err) : "");
}

console.log("== 5. 404 未注册用户 → 合成已注册且有效 ==");
{
  const resp = runScript(JSON.stringify({ error: "not found" }), 404);
  const d = JSON.parse(resp.body);
  check("statusCode 改为 200", resp.statusCode === 200, String(resp.statusCode));
  check("存在 subscriber.entitlements", !!(d.subscriber && d.subscriber.entitlements), JSON.stringify(d));
  const ent = d.subscriber.entitlements.pro;
  check("pro.is_active = true", ent && ent.is_active === true, JSON.stringify(ent));
  check("floaty_pro.is_active = true",
    d.subscriber.entitlements.floaty_pro && d.subscriber.entitlements.floaty_pro.is_active === true,
    JSON.stringify(d.subscriber.entitlements));
  check("active_entitlements 非空", d.subscriber.active_entitlements.length > 0,
    JSON.stringify(d.subscriber.active_entitlements));
}

console.log("== 6. 空 body 不炸 ==");
{
  let err = null;
  try {
    const resp = runScript("", 200);
    check("body 仍为空", resp.body === "", resp.body);
  } catch (e) {
    err = e;
  }
  check("未抛异常", err === null, err ? String(err) : "");
}

console.log();
if (failed) {
  console.log("FAILED " + failed + " 项");
  process.exit(1);
}
console.log("QX 脚本全部通过 ✅");
