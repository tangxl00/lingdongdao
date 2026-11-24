"""
floaty_unlock.py — 浮现 (Floaty) 付费墙解锁 mitmproxy 插件

原理
----
浮现 (com.enjoyio.floaty) 的订阅判定完全走 RevenueCat SDK：

    Purchases.configure(apiKey)
      -> CustomerInfo.entitlements[requiredEntitlementIdentifier].isActive
      -> PaywallPresenter.presentPaywallIfNeeded()

RevenueCat 的 /v1/subscribers/{app_user_id} 响应里带着每个权益的
`is_active` / `expires_date`。App 拿到的是 HTTP JSON，
所以在链路层把权益改成"永久有效"即可 —— **App 本体一个字节都不用改**，
功能与布局 100% 保留。

本插件做三件事：
  1. 识别 RevenueCat 的订阅/权益响应；
  2. 把每个权益改成 is_active=true、expires_date=2099；
  3. 把 entitlement verification 置为 notRequested，避免 SDK 用签名校验
     把被改过的 JSON 判定为 "failed"（enforced 模式下会反过来把 isActive 压回 false）。

用法
----
    mitmdump -s floaty_unlock.py --listen-port 8080
    # 或交互模式
    mitmproxy -s floaty_unlock.py --listen-port 8080

然后在 iPhone 上把 Wi-Fi 代理指向本机 8080，并信任 mitmproxy 的 CA 证书。
"""

from __future__ import annotations

import json
import re
from typing import Any, Dict, Iterable, List, Optional

from mitmproxy import ctx, http

# ---------------------------------------------------------------------------
# 常量
# ---------------------------------------------------------------------------

# RevenueCat 的 API host（SDK 默认走这几个）
RC_HOST_PATTERNS = (
    re.compile(r"(^|\.)revenuecat\.com$", re.I),
    re.compile(r"(^|\.)revenuecat\.biz$", re.I),
)

# 需要改写的路径（订阅者/权益相关）。
RC_PATH_HINTS = (
    "/v1/subscribers",
    "/v1/customer",
    "/subscribers",
)

# 明确**不改**的路径：App 要靠它们显示套餐列表，改了会破坏付费页 UI。
RC_PATH_EXCLUDE = (
    "/v1/products",
    "/v1/offerings",
    "/products",
    "/offerings",
)

# 永久有效日期
FAR_FUTURE = "2099-12-31T23:59:59Z"

# 统计
STATS = {
    "matched": 0,
    "rewritten": 0,
    "entitlements_granted": 0,
}


# ---------------------------------------------------------------------------
# 核心改写逻辑（纯函数，可单测）
# ---------------------------------------------------------------------------

def _entitlement_containers(root: Dict[str, Any]) -> Iterable[Dict[str, Any]]:
    """Yield 那些可能直接挂着 `entitlements` 的字典节点。

    RevenueCat 的 /v1/subscribers 响应实测有三种形状：
        {"subscriber": {"entitlements": {...}}}          # 新版
        {"customer_info": {"entitlements": {...}}}       # 旧版
        {"entitlements": {...}}                         # 某些 SDK 版本
    全部一起处理，避免漏。
    """
    if not isinstance(root, dict):
        return
    for key in ("subscriber", "customer_info", "subscriber_info"):
        node = root.get(key)
        if isinstance(node, dict):
            yield node
    yield root


def _neutralize_verification(ent: Dict[str, Any]) -> None:
    """把 entitlement 的 verification 置成"未请求"。

    RevenueCat 支持 entitlement verification（服务端签名）。如果 App 开了
    enforced 模式，SDK 会用本地公钥校验 entitlement 载荷；我们改了 JSON 就会
    校验失败，SDK 反而把 isActive 压成 false。这里直接把 verification 摘掉，
    SDK 会退回到"不校验"的行为。

    注意：verification 相关字段在 JSON 里是 snake_case，SDK 用
    convertFromSnakeCase 解码，所以字段名保持 snake_case 即可。
    """
    ent.pop("verification", None)
    ent.pop("verification_data", None)


def unlock_entitlements(root: Any) -> tuple[bool, int]:
    """把响应 JSON 里的所有权益改成永久有效。

    返回 (是否发生改写, 被解锁的权益个数)。
    """
    changed = False
    granted = 0

    for container in _entitlement_containers(root):
        ents = container.get("entitlements")
        if not isinstance(ents, dict):
            continue
        for _eid, ent in ents.items():
            if not isinstance(ent, dict):
                continue
            already = bool(ent.get("is_active")) and str(
                ent.get("expires_date") or ""
            ) >= FAR_FUTURE
            ent["is_active"] = True
            ent["will_renew"] = False
            ent["expires_date"] = FAR_FUTURE
            ent["grace_period_expires_date"] = FAR_FUTURE
            _neutralize_verification(ent)
            if not already:
                granted += 1
            changed = True

        # RevenueCat 还有一处 `active_entitlements` 列表（部分版本）。
        # 新注册用户的这个字段是空数组 []，必须一并填上，
        # 否则 SDK 可能走另一条"看 active_entitlements 是否为空"的判断分支。
        if isinstance(container.get("active_entitlements"), list):
            new_active = list(ents.keys())
            if container["active_entitlements"] != new_active:
                container["active_entitlements"] = new_active
                changed = True

    return changed, granted


def is_revenuecat_request(host: str, path: str) -> bool:
    """判断是否是需要改写的 RevenueCat 请求。

    host 必须是 revenuecat.com / revenuecat.biz；
    path 必须命中 RC_PATH_HINTS，且不能命中 RC_PATH_EXCLUDE
    （套餐/产品列表要保持原样，否则付费页会显示不出来）。
    """
    if not host:
        return False
    if not any(p.search(host) for p in RC_HOST_PATTERNS):
        return False
    if not path:
        return False
    low = path.lower()
    if any(x in low for x in RC_PATH_EXCLUDE):
        return False
    return any(hint in low for hint in RC_PATH_HINTS)


def _target_host(flow: http.HTTPFlow) -> str:
    """尽最大努力取出"真实目标 host"。

    不同代理模式下 mitmproxy 的 host 表现不一样：
      * 正向代理（iPhone 设代理）→ host_header 就是原目标，最准；
      * reverse 模式             → Host 被改写成上游，除非开 keep_host_header；
      * 透明模式                → host 是 IP，得靠 host_header。

    所以这里把所有候选都取出来，任一命中就算数 —— 宁可多改写也不能漏改。
    """
    req = flow.request
    candidates = []
    try:
        hh = req.headers.get("host") or req.host_header
    except Exception:
        hh = None
    if hh:
        # host header 可能是 "api.revenuecat.com:443"
        candidates.append(hh.split(":", 1)[0].strip().lower())
    for attr in ("pretty_host", "host"):
        try:
            v = getattr(req, attr, None)
            if v:
                candidates.append(str(v).split(":", 1)[0].strip().lower())
        except Exception:
            pass
    for c in candidates:
        if c and any(p.search(c) for p in RC_HOST_PATTERNS):
            return c
    return candidates[0] if candidates else ""



# ---------------------------------------------------------------------------
# mitmproxy 插件
# ---------------------------------------------------------------------------

class FloatyUnlock:
    """把 RevenueCat 的权益响应改写成"永久 Pro"。"""

    # 在 flow 上缓存"这条流是不是 RevenueCat 权益请求"。
    # 原因：request 阶段看到的 Host 是客户端原始 Host，而 response 阶段
    # mitmproxy 可能已经把它改写过（reverse 模式、--map-remote 都会改 Host），
    # 只靠 response 阶段重新判定会漏掉这类流。
    META_KEY = "floaty_unlock_rc_match"

    def load(self, loader):  # noqa: D401 - mitmproxy hook
        ctx.log.info("[floaty_unlock] 已加载：拦截 RevenueCat 订阅响应并授予永久 Pro")

    def request(self, flow: http.HTTPFlow) -> None:
        host = _target_host(flow)
        path = flow.request.path or ""
        flow.request.headers["X-Floaty-Unlock"] = "1"
        if is_revenuecat_request(host, path):
            flow.metadata[self.META_KEY] = True
            ctx.log.info("[floaty_unlock] 命中 RevenueCat 请求: %s%s" % (host, path))

    def response(self, flow: http.HTTPFlow) -> None:
        path = flow.request.path or ""
        matched = bool(flow.metadata.get(self.META_KEY))
        if not matched:
            host = _target_host(flow)
            matched = is_revenuecat_request(host, path)
        if not matched:
            return

        STATS["matched"] += 1

        body = flow.response.content
        if not body:
            return

        ctype = (flow.response.headers.get("content-type") or "").lower()
        if "json" not in ctype:
            # RevenueCat 有时返回 application/json;charset=utf-8，兜底再试一次
            if not body.lstrip()[:1] == b"{":
                return

        try:
            data = json.loads(body.decode("utf-8"))
        except Exception:
            return

        if not isinstance(data, dict):
            return

        changed, granted = unlock_entitlements(data)
        if not changed:
            return

        new_body = json.dumps(data, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        flow.response.content = new_body
        flow.response.headers["content-length"] = str(len(new_body))
        # 去掉可能存在的签名头，改了 body 之后签名必然对不上
        for h in ("etag", "ETag", "x-signature", "X-Signature"):
            if h in flow.response.headers:
                del flow.response.headers[h]

        STATS["rewritten"] += 1
        STATS["entitlements_granted"] += granted
        ctx.log.warn(
            "[floaty_unlock] 已改写响应，授予 %d 个权益（累计 %d 个）"
            % (granted, STATS["entitlements_granted"])
        )


addons = [FloatyUnlock()]
