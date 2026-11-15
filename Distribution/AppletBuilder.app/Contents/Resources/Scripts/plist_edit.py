#!/usr/bin/env python3
"""plist_edit.py - Edit plist data via JSON intermediate format.

Called by the plist_edit() shell function in lib.plist.sh.
The shell function handles plist <-> JSON conversion.
This script operates on the JSON file directly.

Usage: plist_edit.py [--plist] <json_file> <operation> [args...]

With --plist the file is a property list (XML or binary) instead, read and written in place with
plistlib in the format it has: Linux has no plutil for the JSON round trip.

Read-only operations (the file is not written; command_text() in lib.plist.sh):
  print_command <index>   the command at <index> of COMMAND_LIST as indented JSON
                          on stdout; exit 1 when there is no such command
"""

import json
import plistlib
import sys


def main():
    arguments = sys.argv[1:]
    # --plist: the file is a property list (XML or binary), read and written with plistlib in the
    # format it has; for Linux, which has no plutil to convert it to JSON and back
    plist_format = None
    is_plist = len(arguments) > 0 and arguments[0] == '--plist'
    if is_plist:
        arguments = arguments[1:]
    if len(arguments) < 2:
        print("Usage: plist_edit.py [--plist] <json_file> <operation> [args...]", file=sys.stderr)
        sys.exit(1)

    json_path = arguments[0]
    operation = arguments[1]
    args = arguments[2:]

    if is_plist:
        with open(json_path, 'rb') as f:
            header = f.read(8)
            f.seek(0)
            plist_format = plistlib.FMT_BINARY if header.startswith(b'bplist') else plistlib.FMT_XML
            data = plistlib.load(f)
    else:
        with open(json_path) as f:
            data = json.load(f)

    read_only_ops = {
        'print_command': op_print_command,
    }
    read_only = read_only_ops.get(operation)
    if read_only:
        sys.exit(read_only(data, args))

    ops = {
        'set_keys': op_set_keys,
        'append_service': op_append_service,
        'update_service': op_update_service,
        'remove_service': op_remove_service,
        'append_command': op_append_command,
        'append_command_full': op_append_command_full,
        'remove_command': op_remove_command,
        'replace_command': op_replace_command,
    }

    func = ops.get(operation)
    if not func:
        print(f"Unknown operation: {operation}", file=sys.stderr)
        sys.exit(1)

    func(data, args)

    if is_plist:
        with open(json_path, 'wb') as f:
            plistlib.dump(data, f, fmt=plist_format, sort_keys=False)
        return

    with open(json_path, 'w') as f:
        # Pretty-print: for a JSON command file this is the on-disk format the user
        # sees and may hand-edit; for the plist round-trip the result is reconverted
        # to xml1, so indentation is harmless there.
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write('\n')


def op_set_keys(data, args):
    """Set key-value pairs. Args: key1 value1 [key2 value2 ...]"""
    it = iter(args)
    for key in it:
        data[key] = next(it)


def op_append_service(data, args):
    """Add a new NSService entry. Args: menu_title default_cmd"""
    title, cmd = args[0], args[1]
    data.setdefault('NSServices', []).append({
        'NSMenuItem': {'default': title},
        'NSMessage': 'runOMCService',
        'NSPortName': 'OMCService',
        'NSRequiredContext': {},
        'NSReturnTypes': [],
        'NSSendTypes': ['NSFilenamesPboardType'],
        'NSUserData': cmd,
    })


def op_update_service(data, args):
    """Update service fields at index. Args: index menu_title command_id input_type"""
    idx = int(args[0])
    title, cmd, inp = args[1], args[2], args[3]
    svc = data['NSServices'][idx]
    svc['NSMenuItem'] = {'default': title}
    svc['NSUserData'] = cmd
    # The send types change only when the Input picker does: the pane saves at every field change,
    # so rewriting them each time turned a folders-only service (NSSendFileTypes public.folder,
    # which the picker cannot show) into one for any file or folder at a title edit. The service's
    # kind is read as the pane shows it (shown_input_kind), so a save from the pane that keeps the
    # picker as it was keeps the types as they were, whatever they are.
    if inp != shown_input_kind(svc):
        svc.pop('NSSendFileTypes', None)
        svc['NSSendTypes'] = ['NSStringPboardType'] if inp == 'text' else ['NSFilenamesPboardType']


def shown_input_kind(svc):
    """The Input picker's value for an NSServices item, by AppletBuilder.services.selected.sh's
    rule: "text" when its first NSSendTypes entry is NSStringPboardType, else "files"."""
    send_types = svc.get('NSSendTypes') or []
    return 'text' if send_types and send_types[0] == 'NSStringPboardType' else 'files'


def op_remove_service(data, args):
    """Remove service at index. Args: index"""
    idx = int(args[0])
    svcs = data.get('NSServices', [])
    if 0 <= idx < len(svcs):
        svcs.pop(idx)


def op_append_command(data, args):
    """Add a new command entry. Args: app_name"""
    name = args[0]
    data.setdefault('COMMAND_LIST', []).append({
        'NAME': name,
        'COMMAND_ID': name + '.new.command',
        'EXECUTION_MODE': 'exe_script_file',
    })


def op_append_command_full(data, args):
    """Add a command with all fields. Args: name command_id execution_mode activation_mode"""
    name, cmd_id, exe_mode, act_mode = args[0], args[1], args[2], args[3]
    entry = {
        'NAME': name,
        'EXECUTION_MODE': exe_mode,
        'ACTIVATION_MODE': act_mode,
    }
    if cmd_id:
        entry['COMMAND_ID'] = cmd_id
    # Add OUTPUT_WINDOW_SETTINGS for output window execution modes
    if 'output_window' in exe_mode:
        entry['OUTPUT_WINDOW_SETTINGS'] = {
            'WINDOW_TITLE': name,
            'TEXT_FONT': 'Menlo',
            'TEXT_SIZE': 11,
            'WINDOW_TYPE': 'regular',
            'WINDOW_POSITION': 'cascade',
        }
    # Add COMMAND array with hello world code for non-script-file execution modes
    if 'script_file' not in exe_mode:
        if 'applescript' in exe_mode:
            entry['COMMAND'] = [
                'display dialog "Hello World from ' + name + '"',
            ]
        elif exe_mode in ('exe_terminal', 'exe_iterm'):
            entry['COMMAND'] = [
                'echo "Hello World from ' + name + '"',
            ]
        elif 'shell_script' in exe_mode:
            entry['COMMAND'] = [
                'echo "Hello World from ' + name + '"',
            ]
        elif exe_mode == 'exe_system':
            entry['COMMAND'] = [
                'echo "Hello from ' + name + '" > "${TMPDIR:-/tmp}/hello.txt"',
            ]
    data.setdefault('COMMAND_LIST', []).append(entry)


def op_print_command(data, args):
    """Print the command at index as indented JSON, keys in file order. Args: index.
    Returns the exit status: 1 when the index names no command."""
    idx = int(args[0])
    cmds = data.get('COMMAND_LIST', [])
    if not isinstance(cmds, list) or not 0 <= idx < len(cmds):
        return 1
    print(json.dumps(cmds[idx], ensure_ascii=False, indent=4))
    return 0


def op_remove_command(data, args):
    """Remove command at index. Args: index"""
    idx = int(args[0])
    cmds = data.get('COMMAND_LIST', [])
    if 0 <= idx < len(cmds):
        cmds.pop(idx)


def op_replace_command(data, args):
    """Replace command at index with dict from a JSON file. Args: index json_file"""
    idx = int(args[0])
    with open(args[1]) as f:
        new_cmd = json.load(f)
    cmds = data.get('COMMAND_LIST', [])
    if 0 <= idx < len(cmds):
        cmds[idx] = new_cmd


if __name__ == '__main__':
    main()
