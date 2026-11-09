#!/usr/bin/env python3
"""Align FFmpeg's Media Foundation WINVER with its local _WIN32_WINNT override."""

import sys
from pathlib import Path


old = b"#define _WIN32_WINNT 0x0602\n#endif\n\n#include \"mf_utils.h\"\n"
new = (
    b"#define _WIN32_WINNT 0x0602\n#endif\n"
    b"#if !defined(WINVER) || WINVER < 0x0602\n"
    b"#undef WINVER\n"
    b"#define WINVER 0x0602\n"
    b"#endif\n\n#include \"mf_utils.h\"\n"
)
source = Path(sys.argv[1]) / "libavcodec" / "mf_utils.c"
contents = source.read_bytes()
if contents.count(old) != 1:
    raise SystemExit(f"Expected FFmpeg Media Foundation version guard was not found exactly once: {source}")
source.write_bytes(contents.replace(old, new))
