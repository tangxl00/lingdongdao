// ============================================================================
// Floaty Unlock — Quantumult X 响应体重写脚本
// 作用：把 RevenueCat 返回的权益状态改写成「永久有效」，从而解锁 Floaty Pro。
// 原理：Floaty 的付费判定是
//        CustomerInfo.entitlements[requiredEntitlementIdentifier].isActive
//        （RevenueCat SDK），响应完全由服务端 JSON 决定 → 客户端侧改写即可。
// 用法：见同目录 README.md，需要配合 Quantumult X 的 MITM 证书。
// ============================================================================

// 兜底权益 ID：若服务端返回体里没有 entitlements 字段，则用这些 ID 造一份。
// Floaty 实际使用的 ID 会同时出现在正常响应里（见 active_entitlements 补全逻辑）。
const FALLBACK_ENTITLEMENTS = ["pro", "floaty_pro"];
const EXPIRES_DATE = "2099-12-31T23:59:59Z";
const DEBUG = false;

function log() {
  if (!DEBUG) return;
  try {
    console.log("[floaty-unlock] " + Array.prototype.join.call(arguments, " "));
  } catch (e) {}
}

// 把单个 entitlement 对象改成「永久有效」
function activateEntitlement(ent) {
  if (!ent || typeof ent !== "object") return;
  ent.is_active = true;
  ent.expires_date = EXPIRES_DATE;
  ent.will_renew = false;
  ent.renewal_date = null;
  // verification / verification_data 是 RevenueCat 的服务端签名校验字段，
  // 客户端不校验，但摘掉可以避免客户端二次拒绝。
  delete ent.verification;
  delete ent.verification_data;
  delete ent.ownership_type;
}

// 新版形状：{ subscriber: { entitlements: {...}, active_entitlements: [...] } }
function patchSubscriber(sub) {
  if (!sub || typeof sub !== "object") return [];
  if (!sub.entitlements || typeof sub.entitlements !== "object") {
    sub.entitlements = {};
  }
  const ids = Object.keys(sub.entitlements);
  ids.forEach(function (id) {
    activateEntitlement(sub.entitlements[id]);
  });
  // 服务端可能没给 entitlements（未注册用户），补一份兜底
  FALLBACK_ENTITLEMENTS.forEach(function (id) {
    if (!sub.entitlements[id]) {
      sub.entitlements[id] = { is_active: true, expires_date: EXPIRES_DATE, will_renew: false };
      ids.push(id);
    }
  });
  // active_entitlements 是 SDK 判断 isActive 的直接来源
  sub.active_entitlements = ids;
  return ids;
}

// 旧版形状：{ customer_info: { entitlements: {...} } }
function patchCustomerInfo(ci) {
  if (!ci || typeof ci !== "object") return [];
  if (!ci.entitlements || typeof ci.entitlements !== "object") {
    ci.entitlements = {};
  }
  const ids = Object.keys(ci.entitlements);
  ids.forEach(function (id) {
    activateEntitlement(ci.entitlements[id]);
  });
  FALLBACK_ENTITLEMENTS.forEach(function (id) {
    if (!ci.entitlements[id]) {
      ci.entitlements[id] = { is_active: true, expires_date: EXPIRES_DATE, will_renew: false };
      ids.push(id);
    }
  });
  ci.active_entitlements = ids;
  return ids;
}

function main() {
  var raw = $response.body;
  if (!raw) {
    log("empty body, skip");
    return;
  }

  var data;
  try {
    data = JSON.parse(raw);
  } catch (e) {
    log("not json, skip");
    return;
  }
  if (!data || typeof data !== "object") return;

  var touched = [];

  // ---- 新版：/v1/subscribers/{app_user_id} -------------------------------
  if (data.subscriber) {
    touched = touched.concat(patchSubscriber(data.subscriber));
    // SubscriberResponse 有时也带顶层 entitlements
    if (data.entitlements && typeof data.entitlements === "object") {
      Object.keys(data.entitlements).forEach(function (id) {
        activateEntitlement(data.entitlements[id]);
      });
    }
  }

  // ---- 旧版：/v1/customer/{app_user_id} ---------------------------------
  if (data.customer_info) {
    touched = touched.concat(patchCustomerInfo(data.customer_info));
  }

  // ---- 顶层 entitlements 形状（少数接口） --------------------------------
  if (!data.subscriber && !data.customer_info && data.entitlements) {
    Object.keys(data.entitlements).forEach(function (id) {
      activateEntitlement(data.entitlements[id]);
    });
    touched = touched.concat(Object.keys(data.entitlements));
  }

  // ---- 404：用户还没在 RevenueCat 注册，SDK 会走注册流程。
  // 直接合成一份「已注册 + 永久有效」的用户，避免 App 反复拉起付费页。
  if ($response.statusCode === 404 || data.error) {
    var id = "floaty-unlocked-user";
    var made = {
      subscriber: {
        subscriber_id: id,
        first_seen: EXPIRES_DATE,
        last_seen: EXPIRES_DATE,
        entitlements: {},
        active_entitlements: [],
        subscriptions: {},
        non_subscriptions: {}
      }
    };
    touched = touched.concat(patchSubscriber(made.subscriber));
    // 404 也返回 200，否则 SDK 走错误分支
    $response.statusCode = 200;
    data = made;
  }

  if (!touched.length) {
    log("nothing patched");
    return;
  }

  $response.body = JSON.stringify(data);
  log("patched entitlements:", touched.join(","));
}

main();
