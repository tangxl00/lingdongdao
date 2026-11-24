#!/usr/bin/env python3
"""
package_unlocked_ipa.py — 把原版 Floaty IPA 打包成「已注入解锁 dylib」的 IPA

流程
----
1. 解包原版 IPA
2. 把 FloatyUnlock.dylib 放进 App.app/Frameworks/
3. 用 floaty_patcher 给主二进制和扩展都注入 LC_LOAD_DYLIB
   （原二进制是 FairPlay 加密的，补丁只动 load commands 区，不碰 __TEXT）
4. 重打包成 IPA

签名说明
--------
改动二进制后原签名必然失效，必须重新签名才能装。
  * 越狱设备 + TrollStore：TrollStore 会自动假签，直接装即可
  * 越狱设备 + ldid：用原版 entitlements 假签：
        ldid -S<entitlements.plist> Payload/floaty.app/floaty
        ldid -S<entitlements.plist> Payload/floaty.app/PlugIns/floatyLiveActivity.appex/floatyLiveActivity
    （entitlements 里有 group.com.enjoyio.floaty，保留它 Live Activity 才能用）
  * 普通侧载：用自己的证书重签，但这样会丢掉 App Group，
    Live Activity / 灵动岛 / 小组件会失效 —— 完整功能请走 TrollStore

用法
----
    python package_unlocked_ipa.py \
        --ipa "E:\\...\\浮现_1.1.0.ipa" \
        --dylib "FloatyUnlock.dylib" \
        --out "E:\\work\\floaty-unlocked.ipa"
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
import zipfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "patcher"))

from floaty_patcher import MachO, find_macho_files, process_binary  # noqa: E402

DEFAULT_DYLIB_PATH = "@executable_path/Frameworks/FloatyUnlock.dylib"


def die(msg: str, code: int = 1):
    print("[x] %s" % msg, file=sys.stderr)
    sys.exit(code)


def locate_app(payload_dir: str) -> str:
    """在 Payload/ 下找到 .app 目录。"""
    for entry in os.listdir(payload_dir):
        full = os.path.join(payload_dir, entry)
        if entry.endswith(".app") and os.path.isdir(full):
            return full
    die("Payload 下没有找到 .app")


def extract(ipa: str, workdir: str) -> str:
    print("[*] 解包 %s" % ipa)
    with zipfile.ZipFile(ipa) as zf:
        zf.extractall(workdir)
    payload = os.path.join(workdir, "Payload")
    if not os.path.isdir(payload):
        die("IPA 里没有 Payload/")
    return locate_app(payload)


def install_dylib(app_dir: str, dylib_src: str) -> str:
    frameworks = os.path.join(app_dir, "Frameworks")
    os.makedirs(frameworks, exist_ok=True)
    dst = os.path.join(frameworks, "FloatyUnlock.dylib")
    shutil.copy2(dylib_src, dst)
    print("[*] dylib -> %s" % dst)
    return dst


def patch_binaries(app_dir: str, dylib_install_path: str) -> int:
    binaries = find_macho_files(app_dir)
    print("[*] 找到 %d 个 Mach-O" % len(binaries))
    bad = 0
    for b in binaries:
        try:
            process_binary(b, dylib_install_path, dry_run=False)
        except Exception as exc:
            print("    [x] %s: %s" % (b, exc))
            bad += 1

    # 复查
    print("[*] 复查:")
    for b in binaries:
        try:
            m = MachO(open(b, "rb").read())
        except Exception as exc:
            print("    [x] %s 无法解析: %s" % (b, exc))
            bad += 1
            continue
        ok = dylib_install_path in m.dylibs
        rel = os.path.relpath(b, app_dir)
        print("    %-58s %s" % (rel, "OK" if ok else "缺失!"))
        if not ok:
            bad += 1
    return bad


def repack(payload_dir: str, out_ipa: str) -> None:
    print("[*] 重打包 -> %s" % out_ipa)
    if os.path.exists(out_ipa):
        os.remove(out_ipa)
    with zipfile.ZipFile(out_ipa, "w", zipfile.ZIP_DEFLATED) as zf:
        for root, _dirs, files in os.walk(payload_dir):
            for f in files:
                full = os.path.join(root, f)
                rel = os.path.relpath(full, os.path.dirname(payload_dir))
                zf.write(full, rel.replace(os.sep, "/"))
    print("[*] 完成：%.2f MB" % (os.path.getsize(out_ipa) / 1024 / 1024))


def main() -> int:
    ap = argparse.ArgumentParser(description="把原版 Floaty IPA 打包成已注入解锁 dylib 的 IPA")
    ap.add_argument("--ipa", required=True, help="原版 IPA 路径")
    ap.add_argument("--dylib", required=True, help="已编译好的 FloatyUnlock.dylib")
    ap.add_argument("--out", required=True, help="输出 IPA 路径")
    ap.add_argument("--dylib-install-path", default=DEFAULT_DYLIB_PATH,
                    help="写进 LC_LOAD_DYLIB 的路径（默认 @executable_path/Frameworks/...）")
    args = ap.parse_args()

    if not os.path.exists(args.ipa):
        die("IPA 不存在: %s" % args.ipa)
    if not os.path.exists(args.dylib):
        die("dylib 不存在: %s" % args.dylib)

    workdir = tempfile.mkdtemp(prefix="floaty-unlock-")
    try:
        app_dir = extract(args.ipa, workdir)
        print("[*] app = %s" % app_dir)
        install_dylib(app_dir, args.dylib)
        bad = patch_binaries(app_dir, args.dylib_install_path)
        if bad:
            die("有 %d 个文件处理失败，未打包" % bad)
        payload_dir = os.path.join(workdir, "Payload")
        repack(payload_dir, args.out)
        print("")
        print("下一步（越狱设备）：")
        print("  1) 用 TrollStore 安装本 IPA（会自动假签）")
        print("  2) 或 ldid 假签（需保留原 entitlements，含 group.com.enjoyio.floaty）")
        print("  3) 打开 App，App 沙盒 tmp/floaty_unlock_hits.txt 有记录即说明 dylib 生效")
        return 0
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
