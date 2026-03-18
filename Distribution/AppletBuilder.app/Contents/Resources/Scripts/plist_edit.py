#!/usr/bin/env python3
"""plist_edit.py - Edit plist data via JSON intermediate format.

Called by plist_edit() shell function in lib.builder.sh.
The shell function handles plist <-> JSON conversion.
This script operates on the JSON file directly.

Usage: plist_edit.py <json_file> <operation> [args...]
"""

import json
import sys


def main():
    if len(sys.argv) < 3:
        print("Usage: plist_edit.py <json_file> <operation> [args...]", file=sys.stderr)
        sys.exit(1)

    json_path = sys.argv[1]
    operation = sys.argv[2]
    args = sys.argv[3:]

    with open(json_path) as f:
        data = json.load(f)

    ops = {
        'set_keys': op_set_keys,
        'append_service': op_append_service,
        'update_service': op_update_service,
        'remove_service': op_remove_service,
        'append_command': op_append_command,
        'remove_command': op_remove_command,
        'replace_command': op_replace_command,
    }

    func = ops.get(operation)
    if not func:
        print(f"Unknown operation: {operation}", file=sys.stderr)
        sys.exit(1)

    func(data, args)

    with open(json_path, 'w') as f:
        json.dump(data, f, ensure_ascii=False)


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
    svc.pop('NSSendTypes', None)
    svc.pop('NSSendFileTypes', None)
    if inp == 'text':
        svc['NSSendTypes'] = ['NSStringPboardType']
    else:
        svc['NSSendTypes'] = ['NSFilenamesPboardType']


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
