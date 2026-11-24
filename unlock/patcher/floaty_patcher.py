"""
floaty_patcher.py — 在 FairPlay 加密的 Mach-O 头部空白区插入 LC_LOAD_DYLIB

为什么能这么做
--------------
FairPlay 加密的是 __TEXT 段（cryptoff=0x4000 之后）。Mach-O 头 + load commands
区域在 cryptoff 之前，是**明文**，且 load commands 结束位置到第一个有内容的
section 之间有一段天然的对齐空隙（header padding）。

实测：
    主二进制  floaty              : load commands 结束 0x21c0，首个 section 0x4000 → 7744 字节空白
    扩展      floatyLiveActivity  : load commands 结束 0x15b0，首个 section 0x4000 → 5552 字节空白

把一条 LC_LOAD_DYLIB 写进这段空白 → 二进制多一个 dylib 依赖，
运行时 dyld 会加载我们的解锁库。**不碰加密的 __TEXT，一个字节都不改。**

改了什么
--------
  * mach_header_64.ncmds      += 1
  * mach_header_64.sizeofcmds += cmdsize
  * 空白区写入 LC_LOAD_DYLIB（含路径字符串）
  * LC_CODE_SIGNATURE 的 dataoff/datasize 清零（改动头会让原签名失效，
    必须重新签名：TrollStore 假签或 ldid）

用法
----
    python floaty_patcher.py --bundle "E:\\work\\floaty\\x\\Payload\\floaty.app" \\
        --dylib-path "@executable_path/Frameworks/FloatyUnlock.dylib" --dry-run

    python floaty_patcher.py --bundle "..." --dylib-path "..." --out "E:\\work\\out\\floaty.app"

    python floaty_patcher.py --binary "..." --dylib-path "..." --out "..."
"""

from __future__ import annotations

import argparse
import os
import shutil
import struct
import sys
from typing import Dict, List, Optional, Tuple

# ---------------------------------------------------------------------------
# Mach-O 常量
# ---------------------------------------------------------------------------

MH_MAGIC_64 = 0xFEEDFACF
MH_CIGAM_64 = 0xCFFAEDFE

LC_LOAD_DYLIB = 0xC
LC_CODE_SIGNATURE = 0x1D
LC_ENCRYPTION_INFO_64 = 0x2C
LC_SEGMENT_64 = 0x19

LC_REQ_DYLD = 0x80000000

# load command 类型 -> 是否带 dylib 路径（用于统一扫描）
LC_LOAD_DYLIB_CMDS = {LC_LOAD_DYLIB, 0x18 | LC_REQ_DYLD, 0x1F | LC_REQ_DYLD}


class MachOError(Exception):
    pass


class MachO:
    """只读解析 + 原地打补丁（字节级）。"""

    def __init__(self, data: bytes) -> None:
        self.data = bytearray(data)
        self._parse()

    # -- 解析 -------------------------------------------------------------
    def _parse(self) -> None:
        d = self.data
        if len(d) < 32:
            raise MachOError("文件太小，不是 Mach-O")
        magic = struct.unpack_from("<I", d, 0)[0]
        if magic == MH_CIGAM_64:
            raise MachOError("只支持小端 64 位 Mach-O")
        if magic != MH_MAGIC_64:
            raise MachOError("不是 64 位 Mach-O (magic=0x%08X)" % magic)

        # mach_header_64: magic(0) cputype(4) cpusubtype(8) filetype(12)
        #                  ncmds(16) sizeofcmds(20) flags(24) reserved(28)
        self.cputype, self.cpusubtype = struct.unpack_from("<ii", d, 4)
        (
            self.filetype,
            self.ncmds,
            self.sizeofcmds,
            self.flags,
            self.reserved,
        ) = struct.unpack_from("<IIIII", d, 12)

        self.commands: List[Dict] = []
        off = 32
        end = 32 + self.sizeofcmds
        if end > len(d):
            raise MachOError("load commands 区越界")
        for _ in range(self.ncmds):
            if off + 8 > end:
                raise MachOError("load command 越界")
            cmd, cmdsize = struct.unpack_from("<II", d, off)
            if cmdsize < 8 or off + cmdsize > end:
                raise MachOError("load command 尺寸非法")
            self.commands.append({"cmd": cmd, "cmdsize": cmdsize, "off": off})
            off += cmdsize

        self.cmds_end = off
        self.segments: List[Dict] = []
        self.code_sig: Optional[Dict] = None
        self.encryption: Optional[Dict] = None
        self.dylibs: List[str] = []
        self.first_content_off: Optional[int] = None

        for c in self.commands:
            cmd = c["cmd"]
            if cmd == LC_SEGMENT_64:
                segname = bytes(self.data[c["off"] + 8: c["off"] + 24]).split(b"\x00")[0].decode(
                    "ascii", "replace"
                )
                vmaddr, vmsize, fileoff, filesize = struct.unpack_from(
                    "<QQQQ", self.data, c["off"] + 24
                )
                nsects = struct.unpack_from("<I", self.data, c["off"] + 64)[0]
                sect_off = c["off"] + 72
                sects = []
                for i in range(nsects):
                    so = sect_off + i * 80
                    sname = bytes(self.data[so: so + 16]).split(b"\x00")[0].decode("ascii", "replace")
                    seg = bytes(self.data[so + 16: so + 32]).split(b"\x00")[0].decode("ascii", "replace")
                    # section_64: sectname[16] segname[16] addr(Q@32) size(Q@40)
                    #            offset(I@48) align(I@52) reloff(I@56) nreloc(I@60) ...
                    s_size = struct.unpack_from("<Q", self.data, so + 40)[0]
                    s_off = struct.unpack_from("<I", self.data, so + 48)[0]
                    sects.append({"name": sname, "seg": seg, "offset": s_off, "size": s_size})
                    if s_size > 0 and s_off != 0:
                        if self.first_content_off is None or s_off < self.first_content_off:
                            self.first_content_off = s_off
                self.segments.append(
                    {
                        "name": segname,
                        "vmaddr": vmaddr,
                        "vmsize": vmsize,
                        "fileoff": fileoff,
                        "filesize": filesize,
                        "sects": sects,
                    }
                )
            elif cmd == LC_CODE_SIGNATURE:
                dataoff, datasize = struct.unpack_from("<II", self.data, c["off"] + 8)
                self.code_sig = {"off": c["off"], "dataoff": dataoff, "datasize": datasize}
            elif cmd == LC_ENCRYPTION_INFO_64:
                cryptoff, cryptsize, cryptid = struct.unpack_from("<III", self.data, c["off"] + 8)
                self.encryption = {"cryptoff": cryptoff, "cryptsize": cryptsize, "cryptid": cryptid}
            elif cmd in LC_LOAD_DYLIB_CMDS:
                name_off = struct.unpack_from("<I", self.data, c["off"] + 8)[0]
                raw = bytes(self.data[c["off"] + name_off: c["off"] + c["cmdsize"]])
                self.dylibs.append(raw.split(b"\x00")[0].decode("utf-8", "replace"))

        if self.first_content_off is None:
            self.first_content_off = len(self.data)

    # -- 报告 -------------------------------------------------------------
    @property
    def header_slack(self) -> int:
        """load commands 结束位置到第一个有内容 section 之间的空白字节数。"""
        return self.first_content_off - self.cmds_end

    def describe(self) -> str:
        lines = [
            "  ncmds=%d sizeofcmds=0x%X" % (self.ncmds, self.sizeofcmds),
            "  load commands 结束 : 0x%X" % self.cmds_end,
            "  首个有内容 section : 0x%X" % self.first_content_off,
            "  头部可用空白       : %d 字节" % self.header_slack,
        ]
        if self.encryption:
            e = self.encryption
            lines.append(
                "  FairPlay           : cryptoff=0x%X cryptsize=0x%X cryptid=%d"
                % (e["cryptoff"], e["cryptsize"], e["cryptid"])
            )
            if self.cmds_end > e["cryptoff"]:
                lines.append("  ⚠ load commands 落在加密区之后 —— 不可用本方案")
            else:
                lines.append(
                    "  ✓ load commands 在加密区之前（0x%X < 0x%X），可安全写入"
                    % (self.cmds_end, e["cryptoff"])
                )
        if self.code_sig:
            cs = self.code_sig
            lines.append(
                "  代码签名           : dataoff=0x%X datasize=0x%X" % (cs["dataoff"], cs["datasize"])
            )
        lines.append("  已有 dylib 依赖    : %d 个" % len(self.dylibs))
        return "\n".join(lines)

    # -- 补丁 -------------------------------------------------------------
    def inject_dylib(self, path: str) -> Dict:
        """在头部空白区插入一条 LC_LOAD_DYLIB。返回操作摘要。"""
        name = path.encode("utf-8") + b"\x00"
        cmdsize = 24 + len(name)
        cmdsize = (cmdsize + 7) & ~7  # 8 字节对齐

        if cmdsize > self.header_slack:
            raise MachOError(
                "头部空白不足：需要 %d 字节，只有 %d 字节" % (cmdsize, self.header_slack)
            )

        target = self.cmds_end
        buf = bytearray(cmdsize)
        struct.pack_into("<II", buf, 0, LC_LOAD_DYLIB, cmdsize)
        struct.pack_into("<I", buf, 8, 24)          # name.offset
        struct.pack_into("<I", buf, 12, 0)          # timestamp
        struct.pack_into("<I", buf, 16, 0x10000)    # current_version (1.0.0)
        struct.pack_into("<I", buf, 20, 0x10000)    # compatibility_version (1.0.0)
        buf[24:24 + len(name)] = name

        # 先写 load command（末尾），再改 header 的两个计数
        self.data[target: target + cmdsize] = buf
        struct.pack_into("<I", self.data, 16, self.ncmds + 1)
        struct.pack_into("<I", self.data, 20, self.sizeofcmds + cmdsize)

        stripped_sig = False
        if self.code_sig:
            # 改动头部 => 原签名失效，清零签名命令，让重新签名工具接手
            struct.pack_into("<II", self.data, self.code_sig["off"] + 8, 0, 0)
            stripped_sig = True

        self._parse()  # 重新解析确认结构合法
        return {
            "path": path,
            "cmdsize": cmdsize,
            "at": target,
            "ncmds": self.ncmds,
            "sizeofcmds": self.sizeofcmds,
            "signature_stripped": stripped_sig,
        }


# ---------------------------------------------------------------------------
# IPA / bundle 处理
# ---------------------------------------------------------------------------

def find_macho_files(bundle_dir: str) -> List[str]:
    """找出 bundle 里所有 Mach-O 可执行文件。"""
    out = []
    for root, _dirs, files in os.walk(bundle_dir):
        for f in files:
            p = os.path.join(root, f)
            try:
                if os.path.getsize(p) < 4096:
                    continue
                with open(p, "rb") as fh:
                    if fh.read(4) == b"\xcf\xfa\xed\xfe":  # MH_MAGIC_64 LE
                        out.append(p)
            except OSError:
                continue
    return out


def is_encrypted(data: bytes) -> Optional[Dict]:
    """快速读出 LC_ENCRYPTION_INFO_64。"""
    try:
        m = MachO(data)
    except Exception:
        return None
    return m.encryption


def process_binary(path: str, dylib_path: str, dry_run: bool = False) -> Dict:
    with open(path, "rb") as fh:
        data = fh.read()
    m = MachO(data)
    print("[*] %s" % path)
    print(m.describe())

    if m.encryption and m.encryption["cryptid"] != 0:
        print("    (cryptid=%d，FairPlay 加密；只改头部，不碰 __TEXT)" % m.encryption["cryptid"])

    if dylib_path in m.dylibs:
        print("    → 已存在该 dylib 依赖，跳过")
        return {"skipped": True, "path": path}

    if dry_run:
        cmdsize = (24 + len(dylib_path.encode("utf-8")) + 1 + 7) & ~7
        print("    → [dry-run] 将插入 LC_LOAD_DYLIB %d 字节到 0x%X" % (cmdsize, m.cmds_end))
        return {"dry_run": True, "path": path}

    res = m.inject_dylib(dylib_path)
    with open(path, "wb") as fh:
        fh.write(bytes(m.data))
    print(
        "    → 已插入 LC_LOAD_DYLIB（%d 字节 @ 0x%X），ncmds=%d，原签名%s"
        % (
            res["cmdsize"],
            res["at"],
            res["ncmds"],
            "已清零" if res["signature_stripped"] else "未涉及",
        )
    )
    return res


def verify_binary(path: str, expect_dylib: str) -> bool:
    with open(path, "rb") as fh:
        data = fh.read()
    m = MachO(data)
    ok = expect_dylib in m.dylibs
    # 确认没有动到 section 内容：所有 section 的 offset/size 未变（重新解析成功即说明结构合法）
    print(
        "    校验: dylib 依赖 %s, ncmds=%d, 空白=%d 字节"
        % ("✓ 已注入" if ok else "✗ 缺失", m.ncmds, m.header_slack)
    )
    return ok


def process_bundle(bundle: str, dylib_path: str, out_dir: Optional[str], dry_run: bool) -> int:
    if not os.path.isdir(bundle):
        print("bundle 不存在: %s" % bundle)
        return 2

    target_bundle = bundle
    if out_dir:
        if os.path.exists(out_dir):
            shutil.rmtree(out_dir)
        shutil.copytree(bundle, out_dir)
        target_bundle = out_dir
        print("[*] 已复制 bundle -> %s" % out_dir)

    binaries = find_macho_files(target_bundle)
    if not binaries:
        print("没找到 Mach-O 可执行文件")
        return 2

    print("[*] 发现 %d 个 Mach-O:" % len(binaries))
    for b in binaries:
        print("    - %s" % os.path.relpath(b, target_bundle))

    all_ok = True
    for b in binaries:
        try:
            process_binary(b, dylib_path, dry_run=dry_run)
        except MachOError as exc:
            print("    ✗ 失败: %s" % exc)
            all_ok = False

    if not dry_run:
        print("[*] 重新校验:")
        for b in binaries:
            if not verify_binary(b, dylib_path):
                all_ok = False

    return 0 if all_ok else 1


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(description="给 FairPlay 加密的 Mach-O 注入 LC_LOAD_DYLIB")
    ap.add_argument("--bundle", help="App bundle 目录（含 Info.plist）")
    ap.add_argument("--binary", help="单个 Mach-O 文件")
    ap.add_argument("--dylib-path", required=True, help="要注入的 dylib 路径（写进 LC_LOAD_DYLIB）")
    ap.add_argument("--out", help="输出目录（bundle 模式）或输出文件（binary 模式）")
    ap.add_argument("--dry-run", action="store_true", help="只报告不写盘")
    args = ap.parse_args(argv)

    if args.bundle:
        return process_bundle(args.bundle, args.dylib_path, args.out, args.dry_run)

    if args.binary:
        if not os.path.exists(args.binary):
            print("文件不存在: %s" % args.binary)
            return 2
        if args.dry_run:
            process_binary(args.binary, args.dylib_path, dry_run=True)
            return 0
        res = process_binary(args.binary, args.dylib_path, dry_run=False)
        if isinstance(res, dict) and res.get("skipped"):
            return 0
        if args.out:
            shutil.copy2(args.binary, args.out)
            print("[*] 已复制到 %s" % args.out)
        return 0

    ap.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())
