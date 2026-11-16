#!/usr/bin/env python3
"""plist_edit.py - Edit plist data via JSON intermediate format.

Called by the plist_edit() shell function in lib.plist.sh.
The shell function handles plist <-> JSON conversion.
This script operates on the JSON file directly.

Usage: plist_edit.py <json_file> <operation> [args...]

Read-only operations (the file is not written; command_text() in lib.plist.sh):
  print_command <index>   the command at <index> of COMMAND_LIST as indented JSON
                          on stdout; exit 1 when there is no such command
  print_service_kind <index>
                          the Services pane's Input kind of NSServices entry <index>
                          (files, folders, text or other; info_plist_service_kind() in
                          lib.plist.sh); exit 1 when there is no such service
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

    read_only_ops = {
        'print_command': op_print_command,
        'print_service_kind': op_print_service_kind,
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


# NSSendTypes entries that make a service a text service
TEXT_SEND_TYPES = {
    'NSStringPboardType',
    'public.utf8-plain-text',
    'public.plain-text',
    'public.text',
    'NSPasteboardTypeString',
}


def service_kind(svc):
    """The Services pane's Input kind of one NSServices entry, the value its Input picker shows
    (AppletBuilder.services.selected.sh) and the one op_update_service compares a save with:
      text     no file types, and NSSendTypes names a text type (TEXT_SEND_TYPES)
      folders  NSSendFileTypes is exactly public.folder, and NSSendTypes names no text type
      files    NSSendFileTypes is exactly public.item (and no text type), or no file types and
               NSSendTypes names NSFilenamesPboardType or public.file-url, or nothing at all
      other    any other NSSendFileTypes (public.image, public.folder with more, ...), or file
               types together with a text type: the picker shows it and a save keeps it, since
               the pane cannot write such a list
    A non-empty NSSendFileTypes makes a file service whatever NSSendTypes says, as the engine
    (OMCService.m, OMCApplet.cpp) takes it. An entry that is not an array counts as empty."""
    send_types = svc.get('NSSendTypes')
    if not isinstance(send_types, list):
        send_types = []
    has_text = any(isinstance(t, str) and t in TEXT_SEND_TYPES for t in send_types)
    file_types = svc.get('NSSendFileTypes')
    if not isinstance(file_types, list):
        file_types = []
    if not file_types:
        return 'text' if has_text else 'files'
    if has_text or len(file_types) != 1:
        return 'other'
    if file_types[0] == 'public.folder':
        return 'folders'
    if file_types[0] == 'public.item':
        return 'files'
    return 'other'


def op_print_service_kind(data, args):
    """Print the Input kind (service_kind) of the service at index. Args: index.
    Returns the exit status: 1 when the index names no service."""
    idx = int(args[0])
    services = data.get('NSServices', [])
    if not isinstance(services, list) or not 0 <= idx < len(services) \
            or not isinstance(services[idx], dict):
        return 1
    print(service_kind(services[idx]))
    return 0


def op_update_service(data, args):
    """Update service fields at index. Args: index menu_title command_id input_type

    The send types change only when input_type differs from the kind the service has
    (service_kind, the value the pane shows) and is one the pane can write: "files"
    (NSSendTypes NSFilenamesPboardType), "folders" (NSSendFileTypes public.folder) or "text"
    (NSSendTypes NSStringPboardType). The pane saves at every field change, the title at each
    keystroke, so rewriting the types each time turned a folders-only service into one for any
    file at a title edit. "other", an empty value or anything else keeps them."""
    idx = int(args[0])
    title, cmd, inp = args[1], args[2], args[3]
    svc = data['NSServices'][idx]
    svc['NSMenuItem'] = {'default': title}
    svc['NSUserData'] = cmd
    if inp == service_kind(svc):
        return
    if inp in ('files', 'text'):
        svc.pop('NSSendFileTypes', None)
        svc['NSSendTypes'] = ['NSStringPboardType' if inp == 'text' else 'NSFilenamesPboardType']
    elif inp == 'folders':
        svc.pop('NSSendTypes', None)
        svc['NSSendFileTypes'] = ['public.folder']


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
