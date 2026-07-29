#!/usr/bin/env python3
"""Backward-compatible entry point — delegates to validate_combat_tables.py.

Run from repo root:
  python tools/validate_monster_combat_table.py
  python tools/validate_combat_tables.py
"""

from __future__ import annotations

import runpy
import sys
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "validate_combat_tables.py"

if __name__ == "__main__":
    sys.argv[0] = str(SCRIPT)
    runpy.run_path(str(SCRIPT), run_name="__main__")
