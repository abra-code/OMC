#!/usr/bin/env python3
"""Helper for omctest's ActionUI remote bridge assertions.

Two jobs the shell cannot do cleanly on its own:

  called <log> <method> [json-subset]
      Count requests for <method> in the fake host's JSONL request log. With a
      JSON object as the third argument, only requests whose params contain
      every one of its key/value pairs are counted, so a test can say "setValue
      was called for view 101" rather than only "setValue was called".

  elements <App.app>
      Print "<id>:<type>" for every element the applet's ActionUI documents
      declare, so the fake host can be seeded with them. Without this the fake
      answers 1002 (unknown view) for every element and a handler cannot write
      anything - the fake models a real window, and a real window's elements come
      from its JSON.

  windows <App.app>
      Print the basename of every ActionUI document, one per line. omc_window_switch
      mints a uuid from the name it is given and the documented convention is to name
      the document, so the harness seeds a window for each.

  value <log> <window> <view-id> [elements-file]
      Print the value the applet last wrote to an element, from the same log.
      Deliberately derived from the log rather than asked of the running server:
      a query would itself be logged, and then "how many reads did the applet
      make" would count the harness's own. It also matches what ui_value means
      next door - what the applet wrote, not what a host later did with it.

      The log records a request BEFORE the host dispatches it, so a write the host
      refused is in there too. With <elements-file> - the ids the host was seeded
      with - a write to an element that does not exist is skipped, which is the
      refusal that actually happens. A write refused for any other reason is still
      reported; see the guide.

Exit 0 on success, 2 on a usage error.
Prints nothing but the answer on stdout; diagnostics go to stderr.
"""

import json
import os
import sys


def count_calls(log_path, method, subset_json):
    if not os.path.exists(log_path):
        return 0

    subset = None
    if subset_json:
        try:
            subset = json.loads(subset_json)
        except ValueError as err:
            sys.stderr.write("omctest_bridge: not JSON: %s (%s)\n" % (subset_json, err))
            sys.exit(2)
        if not isinstance(subset, dict):
            sys.stderr.write("omctest_bridge: the params filter must be a JSON object, got %s\n"
                             % type(subset).__name__)
            sys.exit(2)

    count = 0
    with open(log_path) as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except ValueError:
                continue        # a partial trailing line while the fake is still writing
            if not isinstance(entry, dict) or entry.get("method") != method:
                continue
            if subset is not None:
                params = entry.get("params")
                if not isinstance(params, dict):
                    continue
                # Compare decoded values, so 101 and "101" do not accidentally match and
                # key order in the filter does not matter.
                if any(key not in params or params[key] != value
                       for key, value in subset.items()):
                    continue
            count += 1
    return count


def collect_elements(app_path):
    """Every id/type pair in the applet's ActionUI documents, in document order.

    Traversal matches omctest_known_ids.py deliberately - the two answers describe the
    same set of elements and would be confusing if they disagreed about which documents
    count. An element with an id but no type is reported as "Element": the fake only
    needs the id to exist, and inventing a type would be worse than admitting ignorance.
    """
    found = []
    seen = set()

    def walk(node):
        if isinstance(node, dict):
            raw = node.get("id")
            if isinstance(raw, (str, int)) and not isinstance(raw, bool):
                text = str(raw)
                if text.lstrip("-").isdigit() and text not in seen:
                    seen.add(text)
                    kind = node.get("type")
                    # Conservative: the caller passes these through an unquoted shell
                    # argument list, and a type is an element name in practice. Anything
                    # with a space or a metacharacter in it is not one, and is reported
                    # as the generic type rather than trusted.
                    if not (isinstance(kind, str) and kind.isalnum()):
                        kind = "Element"
                    found.append((text, kind))
            for value in node.values():
                walk(value)
        elif isinstance(node, list):
            for value in node:
                walk(value)

    resources = os.path.join(app_path, "Contents", "Resources")
    for dirpath, _dirnames, filenames in os.walk(resources):
        if not dirpath.endswith(".lproj"):
            continue
        for name in sorted(filenames):
            if not name.endswith(".json"):
                continue
            try:
                with open(os.path.join(dirpath, name)) as handle:
                    walk(json.load(handle))
            except (OSError, ValueError):
                continue
    return found


# The methods that set an element's value, newest write wins. setValueString carries the
# same value under the same key, so both are read the same way.
_VALUE_METHODS = ("actionui.setValue", "actionui.setValueString")


def collect_documents(app_path):
    """Every ActionUI document's basename, without extension, in a stable order."""
    names = []
    seen = set()
    resources = os.path.join(app_path, "Contents", "Resources")
    for dirpath, _dirnames, filenames in os.walk(resources):
        if not dirpath.endswith(".lproj"):
            continue
        for name in sorted(filenames):
            if not name.endswith(".json"):
                continue
            stem = name[:-len(".json")]
            if stem not in seen:
                seen.add(stem)
                names.append(stem)
    return names


def read_value(log_path, window, view_id, elements_path=None):
    """The value last written to <view-id> of <window>, or "" if it never was."""
    if not os.path.exists(log_path):
        return ""

    # An element the host was never told about answers 1002, so a write to it never
    # took effect however it looks in the log.
    if elements_path and os.path.exists(elements_path):
        with open(elements_path) as handle:
            known = {line.split(":", 1)[0].strip() for line in handle if line.strip()}
        if str(view_id) not in known:
            return ""

    try:
        wanted = int(view_id)
    except ValueError:
        sys.stderr.write("omctest_bridge: not a view id: %s\n" % view_id)
        sys.exit(2)

    value = ""
    with open(log_path) as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except ValueError:
                continue
            if not isinstance(entry, dict) or entry.get("method") not in _VALUE_METHODS:
                continue
            params = entry.get("params")
            if not isinstance(params, dict):
                continue
            if params.get("window") != window:
                continue
            try:
                if int(params.get("viewID")) != wanted:
                    continue
            except (TypeError, ValueError):
                continue
            # A write to a part of an element - a table row's cell - is not a write to
            # the element, and conflating them would report a cell as the whole value.
            part = params.get("viewPartID", 0)
            if not isinstance(part, int) or isinstance(part, bool) or part != 0:
                continue
            raw = params.get("value")
            # Text as text; anything else as the JSON it arrived as, so a caller can
            # compare a number or a list without a second encoding rule to remember.
            value = raw if isinstance(raw, str) else json.dumps(raw)
    return value


def main(argv):
    if len(argv) < 2:
        sys.stderr.write(__doc__)
        return 2

    action = argv[1]
    if action == "called":
        if len(argv) not in (4, 5):
            sys.stderr.write("usage: omctest_bridge.py called <log> <method> [json-subset]\n")
            return 2
        sys.stdout.write("%d\n" % count_calls(argv[2], argv[3], argv[4] if len(argv) == 5 else None))
        return 0

    if action == "elements":
        if len(argv) != 3:
            sys.stderr.write("usage: omctest_bridge.py elements <App.app>\n")
            return 2
        for view_id, kind in collect_elements(argv[2]):
            sys.stdout.write("%s:%s\n" % (view_id, kind))
        return 0

    if action == "windows":
        if len(argv) != 3:
            sys.stderr.write("usage: omctest_bridge.py windows <App.app>\n")
            return 2
        for name in collect_documents(argv[2]):
            sys.stdout.write("%s\n" % name)
        return 0

    if action == "value":
        if len(argv) not in (5, 6):
            sys.stderr.write("usage: omctest_bridge.py value <log> <window> <view-id> [elements]\n")
            return 2
        sys.stdout.write(read_value(argv[2], argv[3], argv[4],
                                    argv[5] if len(argv) == 6 else None))
        return 0

    sys.stderr.write("omctest_bridge: unknown action %s\n" % action)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
