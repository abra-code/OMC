#!/usr/bin/env python3
"""Render a human-readable summary of a MainMenu.json menu-bar document.

A MainMenu.json is a top-level JSON array of menu-bar elements (CommandMenu,
CommandGroup, RemoveMenu, RemoveItem) — not an ActionUI view — so it cannot be
rendered by ActionUIViewer.  AppletBuilder's Preview shows this textual summary
instead.
"""

import json
import sys

_MOD_SYMBOLS = {
    "command": "⌘", "shift": "⇧", "option": "⌥",
    "control": "⌃", "capslock": "⇪",
}


def _shortcut(props):
    sc = props.get("keyboardShortcut")
    if not isinstance(sc, dict):
        return ""
    key = sc.get("key", "")
    if not key:
        return ""
    mods = sc.get("modifiers", ["command"])
    prefix = "".join(_MOD_SYMBOLS.get(str(m).lower(), str(m)) for m in mods) \
        if isinstance(mods, list) else ""
    return f"  [{prefix}{key.upper()}]"


def _render_children(children, indent):
    lines = []
    for child in children or []:
        if not isinstance(child, dict):
            continue
        ctype = child.get("type")
        props = child.get("properties", {}) or {}
        if ctype == "Button":
            title = props.get("title", "(untitled)")
            cid = props.get("commandID") or props.get("actionID")
            tag = f"  → {cid}" if cid else ""
            lines.append(f"{indent}• {title}{_shortcut(props)}{tag}")
        elif ctype in ("Divider", "Separator"):
            lines.append(f"{indent}──────")
        else:
            lines.append(f"{indent}• <{ctype}>")
    return lines


def summarize(data):
    out = [
        "MainMenu.json — menu-bar customization (not a view)",
        "",
        "The standard menus (App, File, Edit, Format, Window, Help) are always",
        "present. The elements below add, modify, or remove items on top of them.",
        "",
    ]
    if not isinstance(data, list):
        out.append("(Expected a top-level JSON array of menu elements.)")
        return "\n".join(out)
    if not data:
        out.append("(empty — the applet uses the standard menu bar unchanged)")
    for el in data:
        if not isinstance(el, dict):
            out.append(f"• <invalid element: {el!r}>")
            continue
        etype = el.get("type")
        props = el.get("properties", {}) or {}
        children = el.get("children")
        if etype == "CommandMenu":
            name = props.get("name", "(unnamed)")
            extra = "   (auto-populated from Command.json)" if props.get("autoPopulate") else ""
            out.append(f'Menu  "{name}"{extra}')
            out += _render_children(children, "    ")
        elif etype == "CommandGroup":
            placement = props.get("placement", "after")
            target = props.get("placementTarget", "help")
            out.append(f"Group  {placement} {target}")
            out += _render_children(children, "    ")
        elif etype == "RemoveMenu":
            out.append(f'Remove menu  "{props.get("name", "?")}"')
        elif etype == "RemoveItem":
            menu = props.get("menu")
            scope = f"{menu} ▸ " if menu else ""
            out.append(f'Remove item  {scope}"{props.get("title", "?")}"')
        else:
            out.append(f"• <unknown type: {etype}>")
        out.append("")
    return "\n".join(out).rstrip() + "\n"


def main():
    if len(sys.argv) < 2:
        print("usage: menubar_summary.py <MainMenu.json>", file=sys.stderr)
        sys.exit(2)
    try:
        with open(sys.argv[1], encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        print(f"Cannot read menu-bar JSON: {e}", file=sys.stderr)
        sys.exit(1)
    print(summarize(data))


if __name__ == "__main__":
    main()
