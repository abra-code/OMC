#!/usr/bin/env python3
"""plist_convert.py - plutil's conversions of a legacy Command.plist, and of a binary Info.plist to
XML, for Linux (no plutil there).

Called by lib.plist.sh (command_plist_*) on Linux; macOS uses plutil for the same steps. A legacy
Command.plist is edited as JSON (plist_edit.py), so it goes to JSON and back as with plutil:

  to-json <plist> <json out>          plutil -convert json -o <json out> <plist>
  to-xml <json> <plist out>           plutil -convert xml1 -o <plist out> <json>
  lint <plist>                        plutil -lint <plist> (the error on stderr, exit 1)
  extract-command <plist> <index>     the <dict> of COMMAND_LIST item <index> as XML lines,
                                      as `plutil -extract COMMAND_LIST.<index> xml1 -o -`
                                      with the XML header, DOCTYPE and <plist> lines taken off
  to-xml-in-place <plist>             plutil -convert xml1 <plist>, for a binary one only (an
                                      XML one is left untouched); the build's Info.plist step

Keys are written sorted and reals in %.17g form, as plutil writes them. A value JSON cannot hold
(a date, data) fails the conversion to JSON, as with plutil. Two things plutil takes that this
refuses, with a message, rather than change: a carriage return anywhere in the file or its
strings (the XML reader and plistlib's writer both turn it into a line feed, so a script with
Windows line endings would be rewritten), and a raw control character in a string (ESC, BEL:
CoreFoundation writes them as they are, which is not well-formed XML for Python's reader).
Exit 0 on success, 1 on any error (a message on stderr).
"""

import json
import os
import plistlib
import re
import sys
import tempfile

REAL = re.compile(rb'<real>([^<]+)</real>')
CARRIAGE_RETURN_MESSAGE = ("a carriage return, which plistlib would turn into a line feed: "
                           "edit this Command.plist on macOS, or convert it to Command.json")


def refuse_carriage_returns(value):
    """Fail when a string or key in the value holds a carriage return (CARRIAGE_RETURN_MESSAGE)."""
    if isinstance(value, str):
        if '\r' in value:
            raise ValueError(CARRIAGE_RETURN_MESSAGE)
    elif isinstance(value, dict):
        for key, item in value.items():
            refuse_carriage_returns(key)
            refuse_carriage_returns(item)
    elif isinstance(value, list):
        for item in value:
            refuse_carriage_returns(item)


def load_plist(path):
    with open(path, 'rb') as source:
        raw = source.read()
    # A raw one is read as a line feed (XML line-end handling), a &#13; as itself: both refused. In a
    # binary property list a 0x0D byte is just a byte of an offset or a number; its strings are
    # checked below like any other.
    if not raw.startswith(b'bplist') and b'\r' in raw:
        raise ValueError(CARRIAGE_RETURN_MESSAGE)
    value = plistlib.loads(raw)
    refuse_carriage_returns(value)
    return value


def plutil_real(match):
    """One <real> in CoreFoundation's %.17g form."""
    number = format(float(match.group(1)), '.17g')
    return b'<real>' + number.encode('ascii') + b'</real>'


def xml_plist(value):
    """The value as an XML plist, as plutil writes it: keys sorted, and each real in
    CoreFoundation's %.17g form (0.95 as 0.94999999999999996, 1.0 as 1) rather than plistlib's
    shortest form, so a file edited on Linux reads the same as one edited on macOS."""
    refuse_carriage_returns(value)
    payload = plistlib.dumps(value, fmt=plistlib.FMT_XML, sort_keys=True)
    return REAL.sub(plutil_real, payload)


def to_json(arguments):
    data = load_plist(arguments[0])
    text = json.dumps(data, ensure_ascii=False)
    with open(arguments[1], 'w', encoding='utf-8') as target:
        target.write(text)


def to_xml(arguments):
    with open(arguments[0], encoding='utf-8') as source:
        data = json.load(source)
    payload = xml_plist(data)
    with open(arguments[1], 'wb') as target:
        target.write(payload)


def lint(arguments):
    load_plist(arguments[0])


def to_xml_in_place(arguments):
    """A binary property list rewritten as XML in its place (an XML one is left as it is): the Linux
    file manager plug-ins read Info.plist with an XML parser. Written beside it first and then moved
    over it, so a failure leaves the original whole. A symbolic link is followed, as plutil does:
    the file it names is rewritten and the link stays."""
    path = os.path.realpath(arguments[0])
    with open(path, 'rb') as source:
        if source.read(6) != b'bplist':
            return
    payload = xml_plist(load_plist(path))
    folder = os.path.dirname(os.path.abspath(path))
    handle, temporary = tempfile.mkstemp(prefix='.plist_convert.', dir=folder)
    try:
        with os.fdopen(handle, 'wb') as target:
            target.write(payload)
        os.chmod(temporary, os.stat(path).st_mode & 0o7777)
        os.replace(temporary, path)
    except BaseException:
        os.unlink(temporary)
        raise


def extract_command(arguments):
    data = load_plist(arguments[0])
    commands = data.get('COMMAND_LIST') if isinstance(data, dict) else None
    index = int(arguments[1])
    if not isinstance(commands, list) or not 0 <= index < len(commands):
        raise ValueError(f"no command {arguments[1]} in COMMAND_LIST")
    lines = xml_plist(commands[index]).decode('utf-8').splitlines()
    # The XML header, the DOCTYPE and <plist version="1.0"> before the value, </plist> after it
    sys.stdout.write('\n'.join(lines[3:-1]) + '\n')


OPERATIONS = {
    'to-json': (to_json, 2),
    'to-xml': (to_xml, 2),
    'lint': (lint, 1),
    'extract-command': (extract_command, 2),
    'to-xml-in-place': (to_xml_in_place, 1),
}


def main():
    arguments = sys.argv[1:]
    operation = OPERATIONS.get(arguments[0]) if arguments else None
    if operation is None or len(arguments) - 1 != operation[1]:
        print("Usage: plist_convert.py to-json <plist> <json> | to-xml <json> <plist> | lint <plist> | extract-command <plist> <index> | to-xml-in-place <plist>", file=sys.stderr)
        return 1
    function = operation[0]
    try:
        function(arguments[1:])
    except Exception as error:
        print(f"plist_convert.py {arguments[0]}: {arguments[1]}: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
