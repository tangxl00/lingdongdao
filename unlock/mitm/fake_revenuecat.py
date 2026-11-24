"""
fake_revenuecat.py — 本地假 RevenueCat 服务，用于端到端验证 mitm 插件。

    python fake_revenuecat.py [port]

路由：
    GET /v1/subscribers/<id>   -> 未解锁的 subscriber 响应（is_active=false）
    GET /v1/products            -> 产品列表（插件不应改写它）
    GET /v1/offerings           -> 套餐列表（插件不应改写它）
    GET /v1/customer/<id>       -> 旧版 customer_info 形状
"""

from __future__ import annotations

import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

SUBSCRIBER = {
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
                "verification_data": "a1b2c3d4",
            }
        },
        "active_entitlements": [],
        "first_seen": "2026-01-01T00:00:00Z",
    },
}

CUSTOMER_INFO = {
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

PRODUCTS = {
    "items": [
        {"identifier": "floaty_pro_lifetime", "product_type": "NON_CONSUMABLE"},
        {"identifier": "floaty_pro_monthly", "product_type": "SUBSCRIPTION"},
    ]
}

OFFERINGS = {"current": {"offering_id": "default", "package_type": "LIFETIME"}}


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _send(self, payload: dict) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("ETag", '"should-be-stripped"')
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802
        path = self.path.split("?")[0]
        if path.startswith("/v1/subscribers"):
            self._send(SUBSCRIBER)
        elif path.startswith("/v1/customer"):
            self._send(CUSTOMER_INFO)
        elif path == "/v1/products":
            self._send(PRODUCTS)
        elif path == "/v1/offerings":
            self._send(OFFERINGS)
        else:
            self.send_response(404)
            self.send_header("Content-Length", "0")
            self.end_headers()

    def log_message(self, fmt: str, *args) -> None:
        sys.stderr.write("[fake_rc] %s - %s\n" % (self.address_string(), fmt % args))


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8899
    srv = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    sys.stderr.write("[fake_rc] listening on 127.0.0.1:%d\n" % port)
    srv.serve_forever()
