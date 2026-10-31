#!/usr/bin/env python3
"""Renders the soldier review sheets (tools/inspect_soldiers.gd) under the shared render lock.
Usage: python3 tools/inspect_soldiers.py [deaths|poses]"""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import dev
dev.engine(["--script", "res://tools/inspect_soldiers.gd", "--", *sys.argv[1:]], "soldier-inspection", rendered=True)
