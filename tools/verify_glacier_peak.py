#!/usr/bin/env python3
"""Verify the rebuilt Glacier Peak against its saved Godot physics/navigation.

The retired rotunda/gondola layout's hand-calculated AABB grid is intentionally
not reused: it could not detect errors in this map's actual sculpted terrain.
Use the integration suite for capsule movement along complete navigation paths.
"""
from __future__ import annotations
import argparse
import json
import shutil
import sys
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--out', type=Path)
    args = parser.parse_args()
    root = args.repo.resolve()
    sys.path.insert(0, str(root / 'tools'))
    from dev import engine
    engine(['--script', 'res://tools/glacier_geometry_probe.gd'], 'glacier-overhaul-geometry')
    report = root / '.artifacts/glacier_overhaul/geometry.json'
    result = json.loads(report.read_text())
    if args.out:
        args.out.mkdir(parents=True, exist_ok=True)
        target = args.out / 'geometry.json'
        if target.resolve() != report.resolve():
            shutil.copy2(report, target)
    print(f"GLACIER GEOMETRY: {result['passed']} passed, {result['failed']} failed")
    if result['failed']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
