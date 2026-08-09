#!/usr/bin/env python3
"""Print shell assignments for every control an ActionUI document declares.

Used by omctest's omc_control_defaults, which evals the output to put a mock
window into the state a freshly opened one has.

    omctest_control_defaults.py <document.json> <schemas-dir>

Which element types carry a value, and which of their properties declares its
initial state, are both read from the ActionUI element schemas that ship in
AppletBuilder rather than restated here - the same reason a test lib imports an
applet's view ids instead of retyping them. A new value-bearing element type
starts working the day its schema lands.

The dispatch is by PROPERTY name, not by element type: a schema says an element
is observable as a value, and the property it holds that value in is one of a
small stable set whose conversion rules are the only thing hardcoded below.
"""

import glob
import json
import os
import shlex
import sys

# Ordered: TextField declares both "text" and "value", and "text" is the one the
# user sees in the box.
#
# This is the one part that is NOT derived from the schemas. A schema says an
# element is observable as a value, but not which of its properties declares the
# initial one, so the mapping lives here - and a value-bearing type whose
# property is missing from this tuple would otherwise be dropped in silence.
# unmapped_types below exists to make that impossible.
VALUE_PROPERTIES = (
    "isOn",             # Toggle
    "text",             # Text, TextField, SecureField, TextEditor
    "value",            # Slider, Stepper, Gauge
    "selection",        # TabView
    "selectedColor",    # ColorPicker
    "selectedDate",     # DatePicker
    "options",          # Picker - the odd one, resolved by picker_default
)


def load_schemas(schemas_dir):
    """Return (type -> property that declares its initial value, unmapped types)."""
    initial_property = {}
    unmapped_types = set()
    for schema_path in sorted(glob.glob(os.path.join(schemas_dir, "*.json"))):
        try:
            with open(schema_path) as handle:
                schema = json.load(handle)
        except Exception:
            continue
        if not isinstance(schema, dict):
            continue
        # "observable.value" is the schema's way of saying the engine exports
        # this element as OMC_ACTIONUI_VIEW_<id>_VALUE. Elements observable only
        # through "states.*" (DisclosureGroup, ProgressView) are deliberately
        # not included.
        observable = schema.get("observable") or {}
        if "value" not in observable:
            continue
        own = schema.get("ownProperties") or {}
        for candidate in VALUE_PROPERTIES:
            if candidate in own:
                initial_property[schema.get("type")] = candidate
                break
        else:
            # Observable as a value, but none of its properties is one this
            # extractor knows how to read. Most such types are fine and must not
            # warn: Table, List, WebView and friends are observable through
            # their CONTENT, and declare no initial value at all.
            #
            # The ones worth catching are those that clearly do declare one and
            # are merely unmapped - the "selected<Thing>" shape, which is how
            # ColorPicker and DatePicker spell theirs. A new element following
            # that convention is reported rather than silently dropped.
            if any(name.startswith("selected") for name in own):
                unmapped_types.add(schema.get("type"))
    return initial_property, unmapped_types


def picker_default(options):
    """A Picker delivers the selected option's tag when options are declared as
    {"title", "tag"} dictionaries, and its 1-based index when they are plain
    strings. {"section": ...} entries are headers - they carry no tag and are
    never delivered, so the default is the first option that actually can be."""
    if not isinstance(options, list):
        return None
    for index, option in enumerate(options):
        if isinstance(option, dict):
            if "tag" in option:
                return str(option["tag"])
            continue
        return str(index + 1)
    return None


def declared_value(element_type, properties, initial_property):
    prop = initial_property.get(element_type)
    if prop is None:
        return None
    if prop not in properties:
        # An OMITTED property is still a declared default wherever the schema
        # gives it one, and getting this wrong is not cosmetic: six of
        # QuickPDF's toggles ship off by saying nothing at all, and a test that
        # leaves them unset is testing a window with six controls missing.
        # Where omission has no defined meaning - a Slider with no value, a
        # Picker with no options - there is nothing honest to invent.
        if prop == "isOn":
            return "false"
        if prop == "text":
            return ""
        return None
    raw = properties[prop]
    if prop == "isOn":
        return "true" if raw else "false"
    if prop == "options":
        return picker_default(raw)
    if isinstance(raw, bool):
        return "true" if raw else "false"
    return str(raw)


def collect(doc_path, initial_property, unmapped_types):
    out = []
    seen = set()

    def walk(node):
        if isinstance(node, dict):
            element_id = node.get("id")
            is_int_id = isinstance(element_id, int) and not isinstance(element_id, bool)
            if is_int_id and element_id < 0:
                # OMC_ACTIONUI_VIEW_-5_VALUE is not a legal shell identifier,
                # and emitting it in the hope that the eval complains does NOT
                # work: bash treats it as a command rather than an assignment,
                # prints "command not found", carries on, and eval still reports
                # the status of the LAST statement. So the call would claim
                # success having silently skipped a control.
                #
                # Belt and braces rather than the only line of defense: the
                # bundle validator already refuses a hand-written negative id
                # ("negative IDs are auto-generated; do not set them manually"),
                # and `appletbuilder test` validates before running anything, so
                # a document like this cannot reach here through the normal
                # path. It can in standalone mode, which skips validation.
                sys.stderr.write(
                    "omctest: %s declares a negative id %d, which cannot be a "
                    "view variable - skipped\n" % (doc_path, element_id))
            elif is_int_id:
                properties = node.get("properties") or {}
                if node.get("type") in unmapped_types and properties:
                    # Loud, and naming the id, rather than one control quietly
                    # missing from an otherwise successful call.
                    sys.stderr.write(
                        "omctest: %s id %d carries a value this harness cannot "
                        "read - add its property to VALUE_PROPERTIES in "
                        "omctest_control_defaults.py\n"
                        % (node.get("type"), element_id))
                value = declared_value(node.get("type"), properties, initial_property)
                # An id declared twice in one document is the document's
                # problem, not this script's; first one wins so the output is
                # deterministic.
                if value is not None and element_id not in seen:
                    seen.add(element_id)
                    out.append(
                        "OMC_ACTIONUI_VIEW_%d_VALUE=%s; export OMC_ACTIONUI_VIEW_%d_VALUE"
                        % (element_id, shlex.quote(value), element_id))
            for child in node.values():
                walk(child)
        elif isinstance(node, list):
            for child in node:
                walk(child)

    with open(doc_path) as handle:
        walk(json.load(handle))
    return out, len(seen)


def main():
    if len(sys.argv) != 3:
        print("usage: omctest_control_defaults.py <document.json> <schemas-dir>",
              file=sys.stderr)
        sys.exit(2)
    doc_path, schemas_dir = sys.argv[1], sys.argv[2]
    initial_property, unmapped_types = load_schemas(schemas_dir)
    out, applied = collect(doc_path, initial_property, unmapped_types)
    out.append("OMCTEST_DEFAULTS_APPLIED=$((OMCTEST_DEFAULTS_APPLIED + %d))" % applied)
    sys.stdout.write("\n".join(out))


if __name__ == "__main__":
    main()
