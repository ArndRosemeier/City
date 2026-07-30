#!/usr/bin/env python3
"""Deprecated entry point — use tools/gen_room_prop_catalog.py."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

if __name__ == "__main__":
	script = Path(__file__).with_name("gen_room_prop_catalog.py")
	raise SystemExit(subprocess.call([sys.executable, str(script)]))
