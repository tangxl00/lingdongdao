"""
e2e_test.py — 端到端验证：启动真实 mitmdump + 真实 fake RevenueCat，
通过代理发真实 HTTP 请求，断言响应已被解锁。

    python e2e_test.py

覆盖：
  1. /v1/subscribers  -> 权益被改成永久有效
  2. /v1/customer     -> 旧版形状也被改
  3. /v1/products     -> 不被改写（App 还要显示套餐列表）
  4. /v1/offerings    -> 不被改写
  5. ETag 头被剥离（因为 body 变了）

注意：这里**刻意不用 urllib**。
  * urllib 的 ProxyHandler 会读环境变量 no_proxy，本机 no_proxy 含 127.0.0.1
    → 请求直接绕过代理，根本进不了 mitmdump；
  * urllib 走正向代理时发的是 absolute-URI（GET http://host/path），
    mitmdump 的 reverse 模式据此路由，路径判断会和预期不一致。
所以改用裸 socket 手写 HTTP，与 test_https_path.py 保持同一套发包方式。
"""

from __future__ import annotations

import json
import os
import socket
import subprocess
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import fake_revenuecat  # noqa: E402

PROXY_PORT = 18080
FAKE_PORT = 18899
MITMDUMP = None


def find_mitmdump() -> str:
    global MITMDUMP
    if MITMDUMP:
        return MITMDUMP
    import shutil

    cand = shutil.which("mitmdump")
    if cand:
        MITMDUMP = cand
        return cand
    # 退回到 Scripts 目录
    py = sys.executable
    scripts = os.path.join(os.path.dirname(os.executable), "Scripts", "mitmdump.exe")
    if os.path.exists(scripts):
        MITMDUMP = scripts
        return scripts
    raise RuntimeError("找不到 mitmdump，请先 pip install mitmproxy")


def wait_port(host: str, port: int, timeout: float = 25.0) -> bool:
    end = time.time() + timeout
    while time.time() < end:
        try:
            with socket.create_connection((host, port), timeout=1.0):
                return True
        except OSError:
            time.sleep(0.3)
    return False


def http_get_via_proxy(path: str, host_header: str,
                       proxy_port: int = PROXY_PORT) -> tuple[int, dict, dict]:
    """通过 mitm 代理发一个 origin-form 请求，并伪装 Host 头。

    用裸 socket 而不是 urllib：
      - urllib 会因环境变量 no_proxy 绕过代理；
      - urllib 走正向代理时发 absolute-URI，与 reverse 模式的路由不一致。
    """
    s = socket.create_connection(("127.0.0.1", proxy_port), timeout=20)
    try:
        req = "GET %s HTTP/1.1\r\nHost: %s\r\n" % (path, host_header)
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
    status = int(lines[0].split()[1]) if len(lines[0].split()) > 1 else 0
    headers = {}
    for line in lines[1:]:
        if ":" in line:
            k, v = line.split(":", 1)
            headers[k.strip().lower()] = v.strip()
    try:
        data = json.loads(body.decode("utf-8"))
    except Exception:
        data = {}
    return status, data, headers


FAILED: list = []


def check(name: str, cond: bool, detail: str = "") -> None:
    if cond:
        print("  PASS  %s" % name)
    else:
        print("  FAIL  %s  %s" % (name, detail))
        FAILED.append(name)


def main() -> int:
    # 1. 起 fake RevenueCat
    fake = fake_revenuecat.ThreadingHTTPServer(("127.0.0.1", FAKE_PORT), fake_revenuecat.Handler)
    t = threading.Thread(target=fake.serve_forever, daemon=True)
    t.start()
    print("[e2e] fake RevenueCat on 127.0.0.1:%d" % FAKE_PORT)

    # 2. 起 mitmdump（reverse 模式转发到 fake 服务，保留原始 Host 头）
    mitmdump = find_mitmdump()
    cmd = [
        mitmdump,
        "--listen-host", "127.0.0.1",
        "--listen-port", str(PROXY_PORT),
        "--mode", "reverse:http://127.0.0.1:%d@%d" % (FAKE_PORT, PROXY_PORT),
        "-s", os.path.join(HERE, "floaty_unlock.py"),
        "--set", "keep_host_header=true",
        "--set", "termlog_verbosity=info",
        "--set", "flow_detail=0",
    ]
    print("[e2e] starting: %s" % " ".join(cmd))
    proc = subprocess.Popen(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8",
        errors="replace",
    )
    log_lines: list = []

    def pump() -> None:
        for line in proc.stdout:
            log_lines.append(line.rstrip())

    threading.Thread(target=pump, daemon=True).start()

    try:
        if not wait_port("127.0.0.1", PROXY_PORT):
            print("[e2e] mitmdump 未能在超时内监听")
            print("\n".join(log_lines[-40:]))
            return 1
        print("[e2e] mitmdump up on 127.0.0.1:%d" % PROXY_PORT)
        time.sleep(1.5)

        print("== 1. /v1/subscribers (新版形状) ==")
        status, data, headers = http_get_via_proxy(
            "/v1/subscribers/test-user", "api.revenuecat.com"
        )
        ent = data.get("subscriber", {}).get("entitlements", {}).get("pro", {})
        check("HTTP 200", status == 200, str(status))
        check("is_active = True", ent.get("is_active") is True, json.dumps(ent))
        check("expires_date = 2099", str(ent.get("expires_date")) == "2099-12-31T23:59:59Z",
              str(ent.get("expires_date")))
        check("will_renew = False", ent.get("will_renew") is False)
        check("verification 已摘除", "verification" not in ent, json.dumps(ent))
        check("verification_data 已摘除", "verification_data" not in ent)
        check(
            "active_entitlements 已填充",
            data.get("subscriber", {}).get("active_entitlements") == ["pro"],
            str(data.get("subscriber", {}).get("active_entitlements")),
        )
        check("ETag 已剥离", "etag" not in {k.lower() for k in headers}, str(headers))

        print("== 2. /v1/customer (旧版形状) ==")
        status, data, headers = http_get_via_proxy(
            "/v1/customer/test-user", "api.revenuecat.com"
        )
        ent = data.get("customer_info", {}).get("entitlements", {}).get("floaty_pro", {})
        check("HTTP 200", status == 200, str(status))
        check("is_active = True", ent.get("is_active") is True, json.dumps(ent))
        check("expires_date = 2099", str(ent.get("expires_date")) == "2099-12-31T23:59:59Z")

        print("== 3. /v1/products 不被改写 ==")
        status, data, headers = http_get_via_proxy(
            "/v1/products", "api.revenuecat.com"
        )
        check("HTTP 200", status == 200, str(status))
        check("产品列表原样保留", len(data.get("items", [])) == 2, json.dumps(data))

        print("== 4. /v1/offerings 不被改写 ==")
        status, data, headers = http_get_via_proxy(
            "/v1/offerings", "api.revenuecat.com"
        )
        check("HTTP 200", status == 200, str(status))
        check("offering 结构原样", data.get("current", {}).get("offering_id") == "default",
              json.dumps(data))

        print("== 5. 非 RevenueCat host 不被改写 ==")
        status, data, headers = http_get_via_proxy(
            "/v1/subscribers/test-user", "example.com"
        )
        ent = data.get("subscriber", {}).get("entitlements", {}).get("pro", {})
        check("未授权 host 保持 is_active=False", ent.get("is_active") is False, json.dumps(ent))

    finally:
        proc.terminate()
        try:
            proc.wait(timeout=8)
        except subprocess.TimeoutExpired:
            proc.kill()
        fake.shutdown()

    print()
    print("---- mitmdump 日志（尾部）----")
    for line in log_lines[-25:]:
        print("  " + line)

    print()
    if FAILED:
        print("FAILED %d 项: %s" % (len(FAILED), FAILED))
        return 1
    print("端到端全部通过 ✅")
    return 0


if __name__ == "__main__":
    sys.exit(main())
