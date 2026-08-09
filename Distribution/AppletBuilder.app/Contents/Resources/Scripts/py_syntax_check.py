#!/usr/bin/env python3
"""Report a Python file's syntax errors without importing or running it.

    py_syntax_check.py <script.py>

Exits 0 when the file parses, 1 with a one-line message on stderr when it does
not. Used by AppletBuilder's script validation, which is the .py counterpart of
`sh -n` for shell handlers - parsing only, so a handler with import-time side
effects is not executed just to be checked.
"""

import ast
import sys


def main():
    if len(sys.argv) != 2:
        print("usage: py_syntax_check.py <script.py>", file=sys.stderr)
        sys.exit(2)
    path = sys.argv[1]
    try:
        with open(path) as handle:
            source = handle.read()
    except OSError as e:
        print("cannot read %s: %s" % (path, e), file=sys.stderr)
        sys.exit(1)
    try:
        ast.parse(source, filename=path)
    except SyntaxError as e:
        print("%s (line %s, column %s)" % (e.msg, e.lineno, e.offset), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
