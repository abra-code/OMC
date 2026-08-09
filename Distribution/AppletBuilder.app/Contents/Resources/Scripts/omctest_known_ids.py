#!/usr/bin/env python3
"""Write every "id" declared in every ActionUI document in an applet bundle.

    omctest_known_ids.py <App.app> <out-file>

One id per line, deduped, in document order. omctest uses the result to answer
ui_unknown_writes: a handler that writes to an id no document declares is
writing into the void, and the window would show nothing.

The union across all documents is the known masking limitation - an id declared
in one window is accepted as known while a handler is driving another.
"""

import json
import os
import sys


def collect(app_path):
    found = []
    seen = set()

    def walk(node):
        if isinstance(node, dict):
            for key, value in node.items():
                if key == "id" and isinstance(value, (str, int)) \
                        and not isinstance(value, bool):
                    text = str(value)
                    if text not in seen:
                        seen.add(text)
                        found.append(text)
                walk(value)
        elif isinstance(node, list):
            for value in node:
                walk(value)

    resources = os.path.join(app_path, "Contents", "Resources")
    for dirpath, dirnames, filenames in os.walk(resources):
        if not dirpath.endswith(".lproj"):
            continue
        for name in sorted(filenames):
            if not name.endswith(".json"):
                continue
            try:
                with open(os.path.join(dirpath, name)) as handle:
                    walk(json.load(handle))
            except Exception:
                continue
    return found


def main():
    if len(sys.argv) != 3:
        print("usage: omctest_known_ids.py <App.app> <out-file>", file=sys.stderr)
        sys.exit(2)
    app_path, out_path = sys.argv[1], sys.argv[2]
    with open(out_path, "w") as handle:
        for text in collect(app_path):
            handle.write(text + "\n")


if __name__ == "__main__":
    main()
