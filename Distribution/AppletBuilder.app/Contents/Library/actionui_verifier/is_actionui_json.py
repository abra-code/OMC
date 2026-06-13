#!/usr/bin/env python3
"""
Heuristic check: is a JSON file an ActionUI declaration?

An ActionUI document's root is a single element object carrying a `type`
(optionally platform-suffixed, e.g. "type:macos") that names the element. This
mirrors the verifier, which treats the root as a bare element and requires a
`type` field. Files without a top-level `type` — Command.json, Info.plist-style
data, arbitrary config JSON — are not ActionUI.

Returns exit code 0 if the file looks like ActionUI, 1 otherwise.

Usage:
    is_actionui_json.py <file.json>
"""

from __future__ import annotations

import json
import re
import sys


def _strip_jsonc(text: str) -> str:
    """Strip trailing commas before } or ] — matches the verifier's leniency."""
    return re.sub(r',(\s*[}\]])', r'\1', text)


def is_actionui(path: str) -> bool:
    try:
        with open(path, encoding="utf-8") as f:
            data = json.loads(_strip_jsonc(f.read()))
    except Exception:
        return False
    if not isinstance(data, dict):
        return False
    # The root is a bare element: it carries `type` (or a platform-suffixed
    # `type:<platform>`) whose value names an element type.
    for key, value in data.items():
        if (key == "type" or key.startswith("type:")) and isinstance(value, str) and value:
            return True
    return False


def main() -> None:
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <file.json>", file=sys.stderr)
        sys.exit(1)
    sys.exit(0 if is_actionui(sys.argv[1]) else 1)


if __name__ == "__main__":
    main()
