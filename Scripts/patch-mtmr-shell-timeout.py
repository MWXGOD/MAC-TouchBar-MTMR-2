#!/usr/bin/env python3
"""Make MTMR shell-script timeout independent from its refresh interval.

This targets the x86_64 MTMR 0.27/build 433 binary currently installed by the
project. It replaces the interval load used by execute(_:) with a 0.5 second
constant while leaving the later refresh scheduling code untouched.
"""

from pathlib import Path
import shutil
import sys


TARGET = Path("/Applications/MTMR.app/Contents/MacOS/MTMR.original")
PATCH_OFFSET = 0x34281
ORIGINAL = bytes.fromhex("48 8b 05 90 2e 05 00 48 8b 4d a8 f2 0f 10 04 01")
PATCHED = bytes.fromhex("48 b8 00 00 00 00 00 00 e0 3f 66 48 0f 6e c0 90")


def main() -> int:
    target = Path(sys.argv[1]) if len(sys.argv) == 2 else TARGET
    if not target.is_file():
        raise SystemExit(f"target does not exist: {target}")

    data = target.read_bytes()
    if data[0x4:0x8] != b"\x07\x00\x00\x01":
        raise SystemExit("target is not the expected x86_64 Mach-O binary")

    current = data[PATCH_OFFSET:PATCH_OFFSET + len(ORIGINAL)]
    if current == PATCHED:
        print(f"already patched: {target}")
        return 0
    if current != ORIGINAL:
        raise SystemExit(
            f"unexpected bytes at 0x{PATCH_OFFSET:x}: {current.hex(' ')}"
        )

    backup = target.with_name(target.name + ".before-shell-timeout-patch")
    if not backup.exists():
        shutil.copy2(target, backup)
        print(f"backup: {backup}")

    patched = data[:PATCH_OFFSET] + PATCHED + data[PATCH_OFFSET + len(ORIGINAL):]
    target.write_bytes(patched)
    print(f"patched: {target}")
    print("shell-script timeout: 0.5s; refresh interval remains config-controlled")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
