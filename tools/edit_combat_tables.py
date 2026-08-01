#!/usr/bin/env python3
"""Deprecated entry point — use tools/edit_gamedata.py.

Forwards to the Game Data Editor so old commands keep working.
"""

from __future__ import annotations

import runpy
import sys
from pathlib import Path

if __name__ == "__main__":
    print(
        "note: tools/edit_combat_tables.py is deprecated; use tools/edit_gamedata.py",
        file=sys.stderr,
    )
    runpy.run_path(str(Path(__file__).with_name("edit_gamedata.py")), run_name="__main__")
