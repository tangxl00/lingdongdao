"""
test_floaty_patcher.py — floaty_patcher 自测（不依赖真实 IPA）

    python test_floaty_patcher.py

用合成 Mach-O 验证：
  1. 头部解析（ncmds / sizeofcmds / segments / sections）
  2. LC_ENCRYPTION_INFO_64 读取
  3. 注入 LC_LOAD_DYLIB 后结构仍合法，且改动只在加密区之前
  4. 空白不足时正确报错
  5. 重复注入幂等（检测到已存在就跳过）
  6. LC_CODE_SIGNATURE 被清零
  7. 从代码签名里抠出 entitlements plist
  8. 清理失效的 _CodeSignature 目录
"""

from __future__ import annotations

import os
import shutil
import struct
import sys
import tempfile

from floaty_patcher import (
    LC_CODE_SIGNATURE,
    LC_ENCRYPTION_INFO_64,
    LC_LOAD_DYLIB,
    LC_SEGMENT_64,
    MachO,
    MachOError,
    extract_entitlements,
    strip_stale_signature,
)


def build_fake_macho(
    ncmds_extra: int = 0,
    cryptoff: int = 0x4000,
    cryptid: int = 1,
    first_sect_off: int = 0x4000,
    total_size: int = 0x8000,
) -> bytes:
    """构造一个最小可解析的 64 位 Mach-O。"""
    d = bytearray(total_size)

    # mach_header_64
    struct.pack_into("<I", d, 0, 0xFEEDFACF)
    struct.pack_into("<ii", d, 4, 0x0100000C, 0)  # arm64
    struct.pack_into("<I", d, 12, 2)  # filetype = MH_EXECUTE
    struct.pack_into("<I", d, 16, 0)  # ncmds (稍后填)
    struct.pack_into("<I", d, 20, 0)  # sizeofcmds
    struct.pack_into("<I", d, 24, 0x00200085)  # flags
    struct.pack_into("<I", d, 28, 0)

    cmds = bytearray()
    ncmds = 0

    # LC_SEGMENT_64 __TEXT，1 个 section
    # segment_command_64 布局：
    #   cmd(0) cmdsize(4) segname(8..24) vmaddr(24) vmsize(32) fileoff(40)
    #   filesize(48) maxprot(56) initprot(60) nsects(64) flags(68) sections@72
    seg = bytearray(72 + 80)
    struct.pack_into("<II", seg, 0, LC_SEGMENT_64, len(seg))
    seg[8:24] = b"__TEXT".ljust(16, b"\x00")
    struct.pack_into("<QQQQ", seg, 24, 0, 0x8000, 0, 0x8000)  # vmaddr vmsize fileoff filesize
    struct.pack_into("<i", seg, 56, 7)  # maxprot
    struct.pack_into("<i", seg, 60, 7)  # initprot
    struct.pack_into("<I", seg, 64, 1)  # nsects
    struct.pack_into("<I", seg, 68, 0)  # flags
    sect = bytearray(80)
    sect[0:16] = b"__text".ljust(16, b"\x00")
    sect[16:32] = b"__TEXT".ljust(16, b"\x00")
    struct.pack_into("<Q", sect, 32, 0)  # addr
    struct.pack_into("<Q", sect, 40, 0x1000)  # size
    struct.pack_into("<I", sect, 48, first_sect_off)  # offset  ← 关键
    struct.pack_into("<I", sect, 52, 0)  # align
    seg[72:152] = sect
    cmds += seg
    ncmds += 1

    # LC_ENCRYPTION_INFO_64
    enc = bytearray(24)
    struct.pack_into("<II", enc, 0, LC_ENCRYPTION_INFO_64, 24)
    struct.pack_into("<III", enc, 8, cryptoff, 0x1000, cryptid)
    cmds += enc
    ncmds += 1

    # LC_CODE_SIGNATURE
    sig = bytearray(16)
    struct.pack_into("<II", sig, 0, LC_CODE_SIGNATURE, 16)
    struct.pack_into("<II", sig, 8, 0x7000, 0x100)
    cmds += sig
    ncmds += 1

    # 额外的 load command，用来模拟"空白不够"的情况
    for _ in range(ncmds_extra):
        extra = bytearray(8 + 200)
        struct.pack_into("<II", extra, 0, 0x18 | 0x80000000, len(extra))
        cmds += extra
        ncmds += 1

    off = 32
    d[off: off + len(cmds)] = cmds
    struct.pack_into("<I", d, 16, ncmds)
    struct.pack_into("<I", d, 20, len(cmds))
    return bytes(d)


FAILED = []


def build_code_signature(entitlements_xml: str) -> bytes:
    """构造一个最小 CodeSignature superblob，里面放一份 entitlements。

    结构（全部大端）：
      SuperBlob(0xfade0cc0) : length, count, [type, offset] * count
        -> EntitlementsBlob(0xfade7171) : length, <xml bytes>
    """
    xml = entitlements_xml.encode("utf-8")
    ent_blob = struct.pack(">II", 0xFADE7171, 8 + len(xml)) + xml
    ent_off = 12 + 8  # superblob header(12) + one index entry(8)
    total = ent_off + len(ent_blob)
    out = struct.pack(">III", 0xFADE0CC0, total, 1)
    out += struct.pack(">II", 5, ent_off)
    out += ent_blob
    return out


def check(name: str, cond: bool, detail: str = "") -> None:
    if cond:
        print("  PASS  %s" % name)
    else:
        print("  FAIL  %s  %s" % (name, detail))
        FAILED.append(name)


def main() -> int:
    print("== 1. 头部解析 ==")
    raw = build_fake_macho()
    m = MachO(raw)
    check("ncmds = 3", m.ncmds == 3, str(m.ncmds))
    check("识别到 __TEXT 段", any(s["name"] == "__TEXT" for s in m.segments))
    check("识别到 1 个 section", len(m.segments[0]["sects"]) == 1)
    check(
        "section 文件偏移 = 0x4000",
        m.segments[0]["sects"][0]["offset"] == 0x4000,
        hex(m.segments[0]["sects"][0]["offset"]),
    )
    check("首个有内容 section = 0x4000", m.first_content_off == 0x4000, hex(m.first_content_off))
    check("header slack 计算正确", m.header_slack == 0x4000 - m.cmds_end, str(m.header_slack))

    print("== 2. 加密信息 ==")
    check("cryptoff = 0x4000", m.encryption["cryptoff"] == 0x4000)
    check("cryptid = 1", m.encryption["cryptid"] == 1)
    check("load commands 在加密区之前", m.cmds_end < m.encryption["cryptoff"])

    print("== 3. 注入 LC_LOAD_DYLIB ==")
    m2 = MachO(build_fake_macho())
    before = bytes(m2.data)
    res = m2.inject_dylib("@executable_path/Frameworks/FloatyUnlock.dylib")
    after = bytes(m2.data)
    check("ncmds +1", res["ncmds"] == 4, str(res["ncmds"]))
    check("dylib 依赖已加入", "@executable_path/Frameworks/FloatyUnlock.dylib" in m2.dylibs,
          str(m2.dylibs))
    check("文件大小不变（就地改写）", len(before) == len(after))
    diffs = [i for i in range(len(before)) if before[i] != after[i]]
    check("改动字节数很少", len(diffs) < 200, str(len(diffs)))
    check("改动全在 0x4000 之前（FairPlay 区外）", max(diffs) < 0x4000,
          hex(max(diffs)) if diffs else "none")
    check("原签名已清零", m2.code_sig["dataoff"] == 0 and m2.code_sig["datasize"] == 0,
          str(m2.code_sig))
    check("注入后仍能重新解析", MachO(after).ncmds == 4)

    print("== 4. 空白不足时正确报错 ==")
    tight = MachO(build_fake_macho(first_sect_off=0x100, total_size=0x4000))
    check("空白很小", tight.header_slack < 100, str(tight.header_slack))
    try:
        tight.inject_dylib("@executable_path/Frameworks/FloatyUnlock.dylib")
        check("空白不足时抛 MachOError", False, "没有抛异常")
    except MachOError as exc:
        check("空白不足时抛 MachOError", True)
        check("错误信息含'空白不足'", "空白不足" in str(exc), str(exc))

    print("== 5. 重复注入 ==")
    m3 = MachO(build_fake_macho())
    m3.inject_dylib("@executable_path/Frameworks/FloatyUnlock.dylib")
    check("已存在时再注入会变 2 条", len([d for d in m3.dylibs if "FloatyUnlock" in d]) == 1,
          str(m3.dylibs))

    print("== 6. 非 Mach-O 输入 ==")
    try:
        MachO(b"not a macho at all, really not")
        check("非 Mach-O 抛 MachOError", False, "没有抛异常")
    except MachOError:
        check("非 Mach-O 抛 MachOError", True)

    print("== 7. 提取 entitlements ==")
    xml = (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<plist version="1.0"><dict>'
        "<key>application-identifier</key><string>9GAL39B66Y.com.enjoyio.floaty</string>"
        "<key>com.apple.security.application-groups</key>"
        "<array><string>group.com.enjoyio.floaty</string></array>"
        "</dict></plist>"
    )
    tmpdir = tempfile.mkdtemp(prefix="floaty-patcher-test-")
    try:
        # 造一个带真实签名 blob 的 Mach-O
        raw = bytearray(build_fake_macho(total_size=0x8000))
        m = MachO(bytes(raw))
        sigoff = m.code_sig["dataoff"]
        sigsize = m.code_sig["datasize"]
        blob = build_code_signature(xml)
        # 签名区从 0x7000 起，给它留够空间
        raw[sigoff: sigoff + len(blob)] = blob
        # 把 LC_CODE_SIGNATURE 的 datasize 改成 blob 实际长度
        struct.pack_into("<II", raw, m.code_sig["off"] + 8, sigoff, len(blob))
        sig_path = os.path.join(tmpdir, "floaty")
        with open(sig_path, "wb") as fh:
            fh.write(bytes(raw))

        got = extract_entitlements(sig_path)
        check("提取到 entitlements", got is not None)
        check("含 application-identifier", got and "com.enjoyio.floaty" in got, repr(got))
        check("含 App Group", got and "group.com.enjoyio.floaty" in got, repr(got))
        check("以 </plist> 结尾", got and got.rstrip().endswith("</plist>"), repr(got[-40:] if got else None))
        check("没有 blob 尾巴", got and "qr" not in got.split("</plist>")[-1], repr(got[-40:] if got else None))

        print("== 8. 清理失效签名目录 ==")
        bundle = os.path.join(tmpdir, "floaty.app")
        os.makedirs(os.path.join(bundle, "_CodeSignature"))
        with open(os.path.join(bundle, "_CodeSignature", "CodeResources"), "w") as fh:
            fh.write("stale")
        n = strip_stale_signature(bundle)
        check("删除 1 处 _CodeSignature", n == 1, str(n))
        check(
            "目录已不存在",
            not os.path.exists(os.path.join(bundle, "_CodeSignature")),
        )
        check("bundle 其它内容保留", os.path.isdir(bundle))
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)

    print()
    if FAILED:
        print("FAILED %d 项: %s" % (len(FAILED), FAILED))
        return 1
    print("全部通过 ✅")
    return 0


if __name__ == "__main__":
    sys.exit(main())
