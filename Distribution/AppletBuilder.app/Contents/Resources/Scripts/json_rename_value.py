#!/usr/bin/env python3
"""Replace every string value equal to <old> with <new>, in place, in a JSON file.

    json_rename_value.py <file.json> <old> <new>

Used when renaming an applet: a Command.json holds the app's name in several
places (NAME, window titles, chained command ids) and they all have to move
together. Only whole string VALUES are replaced - never a substring, and never a
key - so a name that happens to appear inside a longer sentence is left alone.

Rewritten with indent=2 and a trailing newline, matching the formatting
AppletBuilder's prettify produces, so a rename does not show up as a whole-file
reformat in the next diff.
"""

import json
import sys


def walk(node, old, new):
    if isinstance(node, dict):
        return {key: walk(value, old, new) for key, value in node.items()}
    if isinstance(node, list):
        return [walk(value, old, new) for value in node]
    return new if node == old else node


def main():
    if len(sys.argv) != 4:
        print("usage: json_rename_value.py <file.json> <old> <new>", file=sys.stderr)
        sys.exit(2)
    path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
    with open(path) as handle:
        data = json.load(handle)
    with open(path, "w") as handle:
        json.dump(walk(data, old, new), handle, ensure_ascii=False, indent=2)
        handle.write("\n")


if __name__ == "__main__":
    main()
