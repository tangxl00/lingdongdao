"""
floaty_unlock 的自测脚本（不依赖网络，只验证改写逻辑）。

    python test_floaty_unlock.py

覆盖：
  1. 新版 subscriber 形状
  2. 旧版 customer_info 形状
  3. 顶层 entitlements 形状
  4. 空 / 畸形响应不崩
  5. 幂等性（重复改写结果一致）
  6. host/path 匹配规则
"""

from __future__ import annotations

import copy
import json
import sys

from floaty_unlock import (
    FAR_FUTURE,
    is_revenuecat_request,
    unlock_entitlements,
)


def rc_response_active() -> dict:
    return {
        "request_date": "2026-11-24T00:00:00Z",
        "request_date_ms": 1792790400000,
        "subscriber": {
            "entitlements": {
                "pro": {
                    "expires_date": "2026-12-01T00:00:00Z",
                    "grace_period_expires_date": None,
                    "product_identifier": "floaty_pro_lifetime",
                    "is_active": False,
                    "will_renew": False,
                    "verification": "verified",
                    "verification_data": "deadbeef",
                }
            },
            "active_entitlements": [],
            "first_seen": "2026-01-01T00:00:00Z",
        },
    }


def rc_response_customer_info() -> dict:
    return {
        "customer_info": {
            "entitlements": {
                "floaty_pro": {
                    "expires_date": "2026-11-30T00:00:00Z",
                    "is_active": False,
                    "will_renew": True,
                    "verification": "verified",
                }
            },
            "active_entitlements": [],
        }
    }


def rc_response_flat() -> dict:
    return {
        "entitlements": {
            "pro": {"expires_date": None, "is_active": False, "will_renew": False}
        },
        "active_entitlements": [],
    }


def rc_response_already_pro() -> dict:
    return {
        "subscriber": {
            "entitlements": {
                "pro": {
                    "expires_date": FAR_FUTURE,
                    "is_active": True,
                    "will_renew": False,
                }
            }
        }
    }


FAILED = []


def check(name: str, cond: bool, detail: str = "") -> None:
    if cond:
        print("  PASS  %s" % name)
    else:
        print("  FAIL  %s  %s" % (name, detail))
        FAILED.append(name)


def ent_of(payload: dict) -> dict:
    for holder in ("subscriber", "customer_info", None):
        node = payload if holder is None else payload.get(holder)
        if isinstance(node, dict) and isinstance(node.get("entitlements"), dict):
            return node["entitlements"]
    return {}


def main() -> int:
    print("== 1. 新版 subscriber 形状 ==")
    p = rc_response_active()
    changed, granted = unlock_entitlements(p)
    e = ent_of(p)["pro"]
    check("响应被标记为改写", changed)
    check("授予 1 个权益", granted == 1, "got %d" % granted)
    check("is_active = True", e["is_active"] is True)
    check("expires_date = 2099", e["expires_date"] == FAR_FUTURE, e["expires_date"])
    check("will_renew = False", e["will_renew"] is False)
    check("verification 被摘除", "verification" not in e)
    check("verification_data 被摘除", "verification_data" not in e)
    check(
        "active_entitlements 已填充",
        p["subscriber"]["active_entitlements"] == ["pro"],
        str(p["subscriber"]["active_entitlements"]),
    )

    print("== 2. 旧版 customer_info 形状 ==")
    p = rc_response_customer_info()
    changed, granted = unlock_entitlements(p)
    e = ent_of(p)["floaty_pro"]
    check("响应被标记为改写", changed)
    check("授予 1 个权益", granted == 1)
    check("is_active = True", e["is_active"] is True)
    check("expires_date = 2099", e["expires_date"] == FAR_FUTURE)

    print("== 3. 顶层 entitlements 形状 ==")
    p = rc_response_flat()
    changed, granted = unlock_entitlements(p)
    e = ent_of(p)["pro"]
    check("响应被标记为改写", changed)
    check("is_active = True", e["is_active"] is True)
    check("expires_date = 2099", e["expires_date"] == FAR_FUTURE)

    print("== 4. 畸形 / 空响应 ==")
    for bad in (None, {}, [], "string", 123):
        try:
            changed, granted = unlock_entitlements(bad)
            check("畸形输入 %r 不抛异常" % (bad,), True)
        except Exception as exc:  # pragma: no cover
            check("畸形输入 %r 不抛异常" % (bad,), False, repr(exc))
    p = {"subscriber": {"entitlements": "not-a-dict"}}
    try:
        changed, granted = unlock_entitlements(p)
        check("entitlements 类型错误不抛异常", True)
    except Exception as exc:
        check("entitlements 类型错误不抛异常", False, repr(exc))

    print("== 5. 幂等性 ==")
    p = rc_response_active()
    unlock_entitlements(p)
    snapshot = json.dumps(p, sort_keys=True)
    changed2, granted2 = unlock_entitlements(p)
    check("二次改写后内容不变", json.dumps(p, sort_keys=True) == snapshot)
    check("二次改写授予数为 0", granted2 == 0, "got %d" % granted2)

    print("== 6. 已是 Pro 的响应 ==")
    p = rc_response_already_pro()
    changed, granted = unlock_entitlements(p)
    check("已 Pro 不重复计授予", granted == 0, "got %d" % granted)

    print("== 7. host / path 匹配 ==")
    cases = [
        ("api.revenuecat.com", "/v1/subscribers/abc", True),
        ("api.revenuecat.com", "/v1/subscribers/abc/entitlements", True),
        ("api.revenuecat.com", "/v1/customer/abc", True),
        ("api.revenuecat.com", "/v1/products", False),
        ("api.revenuecat.com", "/v1/offerings", False),
        ("api.revenuecat.com", "/v1/offerings/default", False),
        ("example.com", "/v1/subscribers/abc", False),
        ("", "/v1/subscribers/abc", False),
        ("api.revenuecat.com", "", False),
    ]
    for host, path, expect in cases:
        got = is_revenuecat_request(host, path)
        check("match(%s, %s) == %s" % (host, path, expect), got == expect, "got %s" % got)

    print()
    if FAILED:
        print("FAILED %d 项: %s" % (len(FAILED), FAILED))
        return 1
    print("全部通过 ✅")
    return 0


if __name__ == "__main__":
    sys.exit(main())
