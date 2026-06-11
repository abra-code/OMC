#!/usr/bin/env python3
"""
Heuristic check: is a JSON file an ActionUI declaration?

ActionUI JSON has a root dictionary whose values are element dicts containing
a "type" key.  Returns exit code 0 if the file matches, 1 otherwise.

Usage:
    is_actionui_json.py <file.json>
"""

from __future__ import annotations

import json
import sys


def is_actionui(path: str) -> bool:
    try:
        with open(path) as f:
            data = json.load(f)
        if isinstance(data, dict):
            for v in data.values():
                if isinstance(v, dict) and "type" in v:
                    return True
    except Exception:
        pass
    return False


def main() -> None:
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <file.json>", file=sys.stderr)
        sys.exit(1)
    sys.exit(0 if is_actionui(sys.argv[1]) else 1)


if __name__ == "__main__":
    main()
