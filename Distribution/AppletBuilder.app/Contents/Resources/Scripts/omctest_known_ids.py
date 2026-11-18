#!/usr/bin/env python3
"""Write every "id" declared in every ActionUI document in an applet bundle.

    omctest_known_ids.py <App.app> <out-file>

One id per line, deduped, in document order. omctest uses the result to answer
ui_unknown_writes: a handler that writes to an id no document declares is
writing into the void, and the window would show nothing.

The union across all documents is the known masking limitation - an id declared
in one window is accepted as known while a handler is driving another.

Only the elements the window has on THIS system count. ActionUI gives an element a
type per platform ("type:apple", "type:macos", "type:linux"); one whose type is given
only for other platforms is left out of the window there, with everything inside it,
so a handler that writes to its id on this system writes into the void.
"""

import json
import os
import sys

# The platform suffixes ActionUI's renderer on this system answers to: macOS takes
# "macos" and "apple", Linux "linux" (ActionUI's JSON guide, platform-specific keys)
PLATFORM_TOKENS = ("macos", "apple") if sys.platform == "darwin" else ("linux",)


def element_is_here(node):
    """False for an element whose type is given only for other platforms."""
    type_keys = [key for key in node if key == "type" or key.startswith("type:")]
    if not type_keys or "type" in type_keys:
        return True
    return any(("type:" + token) in node for token in PLATFORM_TOKENS)


def collect(app_path):
    found = []
    seen = set()

    def walk(node):
        if isinstance(node, dict):
            if not element_is_here(node):
                return
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
