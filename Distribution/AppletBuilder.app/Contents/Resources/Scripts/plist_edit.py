#!/usr/bin/env python3
"""plist_edit.py - Edit a command file's data in JSON.

Called by the plist_edit() shell function in lib.plist.sh, for the command file operations: on
a Command.json directly, on a legacy Command.plist (macOS only) through the JSON plutil makes of
it. The Info.plist operations are not here: lib.plist.sh makes them with plister.

Usage: plist_edit.py <json_file> <operation> [args...]

Read-only operations (the file is not written; command_text() in lib.plist.sh):
  print_command <index>   the command at <index> of COMMAND_LIST as indented JSON
                          on stdout; exit 1 when there is no such command
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
    }
    read_only = read_only_ops.get(operation)
    if read_only:
        sys.exit(read_only(data, args))

    ops = {
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
