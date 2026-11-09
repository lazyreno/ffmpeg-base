#!/usr/bin/env python3
"""Avoid the Windows process command-line limit in FFmpeg shared-library links."""

import sys
from pathlib import Path


old = b"\t$(Q)echo $$(filter %.o,$$^) > $$@.objs\n"
new = b"\t$(Q)$$(file >$$@.objs,$$(filter %.o,$$^))\n"
library = Path(sys.argv[1]) / "ffbuild" / "library.mak"
contents = library.read_bytes()
if contents.count(old) != 1:
    raise SystemExit(f"Expected FFmpeg response-file recipe was not found exactly once: {library}")
library.write_bytes(contents.replace(old, new))
