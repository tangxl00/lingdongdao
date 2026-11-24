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
from typing import List, Tuple

for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "patcher"))

from floaty_patcher import (  # noqa: E402
    MachO,
    extract_entitlements,
    find_macho_files,
    process_binary,
    strip_stale_signature,
)

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
    """把 dylib 放进 App 和每个 appex 各自的 Frameworks/。

    @executable_path 是「当前可执行文件所在目录」，主 App 和 appex 各自不同，
    所以两份都要放，否则 appex 加载 dylib 时会找不到。
    """
    targets = [app_dir]
    plugins_dir = os.path.join(app_dir, "PlugIns")
    if os.path.isdir(plugins_dir):
        for entry in os.listdir(plugins_dir):
            p = os.path.join(plugins_dir, entry)
            if entry.endswith(".appex") and os.path.isdir(p):
                targets.append(p)

    for t in targets:
        frameworks = os.path.join(t, "Frameworks")
        os.makedirs(frameworks, exist_ok=True)
        dst = os.path.join(frameworks, "FloatyUnlock.dylib")
        shutil.copy2(dylib_src, dst)
        print("[*] dylib -> %s" % os.path.relpath(dst, app_dir))
    return os.path.join(targets[0], "Frameworks", "FloatyUnlock.dylib")


def patch_binaries(app_dir: str, dylib_install_path: str) -> int:
    # 我们注入进去的 dylib 本身不能再被注入一次自己
    binaries = find_macho_files(app_dir, exclude=["FloatyUnlock.dylib"])
    print("[*] 找到 %d 个 Mach-O（已跳过 FloatyUnlock.dylib）" % len(binaries))
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


def dump_entitlements(app_dir: str, out_dir: str) -> List[Tuple[str, str]]:
    """把每个可执行文件的原始 entitlements 抠出来，写成 ldid 可用的 plist。

    返回 [(相对路径, entitlements 文件路径), ...]
    """
    out: List[Tuple[str, str]] = []
    os.makedirs(out_dir, exist_ok=True)
    for b in find_macho_files(app_dir, exclude=["FloatyUnlock.dylib"]):
        xml = extract_entitlements(b)
        if not xml:
            continue
        name = os.path.basename(b) + ".entitlements.plist"
        dst = os.path.join(out_dir, name)
        with open(dst, "w", encoding="utf-8") as fh:
            fh.write(xml)
        rel = os.path.relpath(b, app_dir)
        out.append((rel, dst))
        print("[*] entitlements -> %s (%s)" % (os.path.basename(dst), rel))
    return out


def write_ldid_script(app_dir: str, ent_list: List[Tuple[str, str]], out_path: str) -> None:
    """生成一份可直接在设备上跑的 ldid 假签脚本。

    脚本内容刻意保持纯 ASCII：设备端 /bin/sh 与各种编辑器的编码环境不可控，
    中文注释可能在传输中被破坏，导致 shell 语法出错。
    """
    lines = [
        "#!/bin/sh",
        "# Auto-generated: re-sign Floaty binaries, preserving original entitlements.",
        "# The original entitlements contain group.com.enjoyio.floaty,",
        "# which is required for the Lock Screen / Live Activity board.",
        "set -e",
        'cd "$(dirname "$0")"',
        "",
    ]
    for rel, ent in ent_list:
        ent_name = os.path.basename(ent)
        lines.append('ldid -S"%s" "%s"' % (ent_name, rel.replace(os.sep, "/")))
    lines.append('echo "re-sign done"')
    with open(out_path, "w", encoding="ascii", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")
    os.chmod(out_path, 0o755)
    print("[*] 假签脚本 -> %s" % out_path)


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

        # 注意顺序：必须先抠原始 entitlements —— 打补丁会把 LC_CODE_SIGNATURE 清零，
        # 之后再抠就什么都找不到了
        ent_list = dump_entitlements(app_dir, os.path.join(app_dir, "_unlock"))
        if not ent_list:
            die("没能从原版二进制里提取 entitlements，无法安全重签")

        install_dylib(app_dir, args.dylib)
        bad = patch_binaries(app_dir, args.dylib_install_path)
        if bad:
            die("有 %d 个文件处理失败，未打包" % bad)

        # 注入后原签名必然失效：清掉旧签名目录，并生成 ldid 假签脚本
        strip_stale_signature(app_dir)
        write_ldid_script(app_dir, ent_list, os.path.join(app_dir, "_unlock", "resign.sh"))

        payload_dir = os.path.join(workdir, "Payload")
        repack(payload_dir, args.out)
        print("")
        print("下一步（越狱设备）：")
        print("  1) 用 TrollStore 安装本 IPA（会自动假签）")
        print("  2) 或手动 ldid 假签：Payload/floaty.app/_unlock/resign.sh 已在包内")
        print("  3) 打开 App，App 沙盒 tmp/floaty_unlock_hits.txt 有记录即说明 dylib 生效")
        return 0
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
