#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
test_https_path.py —— 完整复现「iPhone 上浮现 App 拉订阅状态」这条链路。

和 e2e_test.py 的区别：
    e2e_test.py       只覆盖明文 HTTP（reverse 模式），证明改写逻辑本身没问题；
    test_https_path.py 覆盖 **HTTPS + CONNECT + 证书信任**，也就是 iPhone 上
                       真正发生的那条路：

        iPhone ──HTTPS CONNECT──▶ mitmdump(我们的 CA 签证书)
                 ◀──JSON 已改写──  └─▶ 上游 RevenueCat

为了让「上游」可控又不依赖真 RevenueCat 的 API Key，本测试用
`--map-remote` 把 api.revenuecat.com 映射到本地假 RevenueCat，
其余部分（CONNECT、TLS、Host 头、路径、响应改写）与真机完全一致。

跑法：
    python test_https_path.py            # 自动起假 RC + mitmdump，用完自动清理
    python test_https_path.py --keep     # 保留进程，便于手工排查
"""

from __future__ import annotations

import json
import os
import socket
import ssl
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
PLUGIN = os.path.join(HERE, "floaty_unlock.py")
FAKE_RC = os.path.join(HERE, "fake_revenuecat.py")

MITMDUMP = None
for cand in (
    os.path.join(sys.executable, "..", "Scripts", "mitmdump.exe"),
    "mitmdump",
):
    if cand == "mitmdump":
        MITMDUMP = cand
        break
    p = os.path.abspath(cand)
    if os.path.exists(p):
        MITMDUMP = p
        break

RC_HOST = "api.revenuecat.com"

_fails = []


def check(name, cond, detail=""):
    print("  %s  %s%s" % ("PASS" if cond else "FAIL", name,
                           ("  -> " + detail) if detail else ""))
    if not cond:
        _fails.append(name)
    return cond


def free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    p = s.getsockname()[1]
    s.close()
    return p


def wait_port(host, port, timeout=25):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            c = socket.create_connection((host, port), timeout=1)
            c.close()
            return True
        except OSError:
            time.sleep(0.3)
    return False


# ---------------------------------------------------------------------------
# 底层 HTTP 客户端（刻意不用 urllib：它的 no_proxy 会绕过 127.0.0.1）
# ---------------------------------------------------------------------------

def http_via_proxy(proxy_host, proxy_port, target_host, target_port, path,
                   host_header, timeout=20):
    """明文 HTTP 正向代理请求（absolute-URI）。"""
    s = socket.create_connection((proxy_host, proxy_port), timeout=timeout)
    try:
        req = "GET http://%s:%d%s HTTP/1.1\r\nHost: %s\r\n" % (
            target_host, target_port, path, host_header)
        req += ("User-Agent: Floaty/1.1.0\r\nAccept: application/json\r\n"
                "Connection: close\r\n\r\n")
        s.sendall(req.encode())
        chunks = []
        while True:
            b = s.recv(65536)
            if not b:
                break
            chunks.append(b)
    finally:
        s.close()
    raw = b"".join(chunks)
    head, _, body = raw.partition(b"\r\n\r\n")
    lines = head.decode("iso-8859-1").split("\r\n")
    hdrs = {}
    for line in lines[1:]:
        if ":" in line:
            k, v = line.split(":", 1)
            hdrs[k.strip().lower()] = v.strip()
    return lines[0], hdrs, body


def https_via_proxy(proxy_host, proxy_port, target_host, target_port, path,
                    host_header, cafile, timeout=20):
    """HTTPS 正向代理请求（CONNECT + TLS）。返回 (status, headers, body)。"""
    s = socket.create_connection((proxy_host, proxy_port), timeout=timeout)
    s.sendall(("CONNECT %s:%d HTTP/1.1\r\nHost: %s:%d\r\n\r\n"
               % (target_host, target_port, target_host, target_port)).encode())
    buf = b""
    while b"\r\n\r\n" not in buf:
        b = s.recv(1)
        if not b:
            raise RuntimeError("CONNECT 被拒: %r" % buf)
        buf += b
    status_line = buf.split(b"\r\n\r\n")[0].decode("iso-8859-1").split("\r\n")[0]
    if " 200 " not in status_line:
        s.close()
        raise RuntimeError("CONNECT 失败: %s" % status_line)

    ctx = ssl.create_default_context(cafile=cafile)
    ctx.check_hostname = True
    ctx.verify_mode = ssl.CERT_REQUIRED
    ss = ctx.wrap_socket(s, server_hostname=host_header)
    try:
        cert = ss.getpeercert()
        issuer = dict(x[0] for x in cert.get("issuer", []))
        subject = dict(x[0] for x in cert.get("subject", []))
        ss.sendall(("GET %s HTTP/1.1\r\nHost: %s\r\n"
                    "User-Agent: Floaty/1.1.0\r\nAccept: application/json\r\n"
                    "Connection: close\r\n\r\n" % (path, host_header)).encode())
        chunks = []
        while True:
            b = ss.recv(65536)
            if not b:
                break
            chunks.append(b)
    finally:
        ss.close()
    raw = b"".join(chunks)
    head, _, body = raw.partition(b"\r\n\r\n")
    lines = head.decode("iso-8859-1").split("\r\n")
    hdrs = {}
    for line in lines[1:]:
        if ":" in line:
            k, v = line.split(":", 1)
            hdrs[k.strip().lower()] = v.strip()
    return lines[0], hdrs, body, status_line, issuer, subject


# ---------------------------------------------------------------------------
# 测试主体
# ---------------------------------------------------------------------------

def assert_unlocked(body, hdrs, label):
    try:
        d = json.loads(body.decode("utf-8"))
    except Exception as e:
        check("%s 响应可解析为 JSON" % label, False, "%s / %r" % (e, body[:200]))
        return
    p = d["subscriber"]["entitlements"]["pro"]
    check("%s is_active = True" % label, p.get("is_active") is True,
          repr(p.get("is_active")))
    check("%s expires_date = 2099" % label,
          str(p.get("expires_date", "")).startswith("2099"),
          str(p.get("expires_date")))
    check("%s will_renew = False" % label, p.get("will_renew") is False)
    check("%s verification 已摘除" % label, "verification" not in p)
    check("%s verification_data 已摘除" % label, "verification_data" not in p)
    check("%s active_entitlements 已填充" % label,
          "pro" in d["subscriber"].get("active_entitlements", []),
          repr(d["subscriber"].get("active_entitlements")))
    check("%s ETag 已剥离" % label, "etag" not in hdrs)


def main():
    keep = "--keep" in sys.argv
    if not MITMDUMP:
        print("SKIP：找不到 mitmdump，无法运行本测试")
        return 0

    rc_port = free_port()
    proxy_port = free_port()
    confdir = tempfile.mkdtemp(prefix="floaty_https_")
    ca = os.path.join(confdir, "mitmproxy-ca-cert.pem")

    print("== 启动假 RevenueCat :%d ==" % rc_port)
    rc = subprocess.Popen([sys.executable, FAKE_RC, str(rc_port)],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print("== 启动 mitmdump 正向代理 :%d（map-remote → 假 RC）==" % proxy_port)
    mp = subprocess.Popen(
        [MITMDUMP, "-s", PLUGIN,
         "--listen-host", "127.0.0.1", "--listen-port", str(proxy_port),
         "--set", "confdir=" + confdir,
         "--map-remote",
         "|https://api\\.revenuecat\\.com/(.*)|http://127.0.0.1:%d/\\1" % rc_port,
         "--set", "termlog_verbosity=warn"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    try:
        if not wait_port("127.0.0.1", rc_port) or \
           not wait_port("127.0.0.1", proxy_port):
            print("FAIL：服务未能启动")
            return 1
        # CA 是异步生成的，多等一会儿
        for _ in range(40):
            if os.path.exists(ca):
                break
            time.sleep(0.25)
        check("mitmproxy CA 已生成", os.path.exists(ca), ca)

        print()
        print("== A. 明文 HTTP 经正向代理（直连假 RC）==")
        status, hdrs, body = http_via_proxy(
            "127.0.0.1", proxy_port, "127.0.0.1", rc_port,
            "/v1/subscribers/test-user", RC_HOST)
        check("HTTP 200", status.startswith("HTTP/1.1 200"), status)
        assert_unlocked(body, hdrs, "HTTP")

        print()
        print("== B. HTTPS 经正向代理（CONNECT + TLS，Host=api.revenuecat.com）==")
        status, hdrs, body, cstatus, issuer, subject = https_via_proxy(
            "127.0.0.1", proxy_port, RC_HOST, 443,
            "/v1/subscribers/test-user", RC_HOST, ca)
        check("CONNECT 隧道建立", cstatus.startswith("HTTP/1.1 200"), cstatus)
        check("证书由 mitmproxy CA 签发（证明流量已解密）",
              issuer.get("organizationName") == "mitmproxy",
              "CN=%s issuer=%s" % (subject.get("commonName"),
                                   issuer.get("organizationName")))
        check("HTTP 200", status.startswith("HTTP/1.1 200"), status)
        assert_unlocked(body, hdrs, "HTTPS")

        print()
        print("== C. HTTPS 下 /v1/products 必须保持原样 ==")
        status, hdrs, body, _c, _i, _s = https_via_proxy(
            "127.0.0.1", proxy_port, RC_HOST, 443,
            "/v1/products", RC_HOST, ca)
        try:
            d2 = json.loads(body.decode("utf-8"))
        except Exception as e:
            check("products 响应可解析", False, str(e))
            d2 = {}
        items = d2.get("items", [])
        check("产品列表未被改写",
              len(items) == 2 and all("is_active" not in i for i in items),
              json.dumps(d2, ensure_ascii=False)[:160])

        print()
        print("== D. 非 RevenueCat host 必须保持原样 ==")
        status, hdrs, body = http_via_proxy(
            "127.0.0.1", proxy_port, "127.0.0.1", rc_port,
            "/v1/subscribers/test-user", "api.some-vendor.com")
        try:
            d3 = json.loads(body.decode("utf-8"))
        except Exception:
            d3 = {}
        p3 = d3.get("subscriber", {}).get("entitlements", {}).get("pro", {})
        check("非 RC host 保持 is_active=False", p3.get("is_active") is False,
              repr(p3.get("is_active")))
        check("非 RC host 保留 verification", "verification" in p3)

    finally:
        if not keep:
            for p in (mp, rc):
                try:
                    p.terminate()
                    p.wait(timeout=5)
                except Exception:
                    pass
        else:
            print("\n(--keep：mitmdump pid=%s, 假 RC pid=%s, confdir=%s)"
                  % (mp.pid, rc.pid, confdir))

    print()
    if _fails:
        print("存在 FAIL ❌ : %s" % ", ".join(_fails))
        return 1
    print("全部通过 ✅")
    return 0


if __name__ == "__main__":
    sys.exit(main())
