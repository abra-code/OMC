#!/usr/bin/env python3
"""Lists a Command applet's file services for the Linux file managers' Services menu, or takes the list
away, for the current user.

The applet's Info.plist declares its services as on macOS (NSServices): each item's NSUserData is
the command it runs, NSMenuItem's "default" its title, and NSSendFileTypes the files it takes (Apple
type identifiers such as public.folder). A service for text only (NSSendTypes) is left out: a file
manager has files, not text.

install writes $XDG_DATA_HOME/command/services/<CFBundleIdentifier>.services (XDG_DATA_HOME defaults
to ~/.local/share), which the Command Workshop file manager plug-ins read: the applet's name, its program, and
per service its title, command id and MIME types, as a key file (the desktop entry format, which
GLib reads with no other library; Linux/NautilusServices/command-services-core.c):

    [Applet]
    Version=1
    Application=com.example.Find
    Name=Find
    Program=/home/me/Applications/Find.app/Contents/Linux/Find

    [Service 0]
    Title=Search Here with Find
    Command=find.new
    MimeTypes=inode/directory;

The plug-in starts the program with
"--command-service <command id> <file URIs>"; the applet runs only a command it declares so. An applet
with no file service gets no file (an earlier one is removed). AppletBuilder runs this beside
linux-app-entry.py when the applet is added to the desktop, and uninstall when it is taken off.

The Info.plist reading, the program and the type table are linux-app-entry.py's (ActionUI), found
beside this file (the framework's Support folder) or in the ActionUI checkout beside OMC.

Usage:
    command-services.py install <applet folder>
    command-services.py uninstall <applet folder | application ID>

Exit status: 0 done, 1 a step failed, 64 bad arguments or Info.plist.
"""

import importlib.util
import os
import sys
import tempfile


def load_app_entry():
    """linux-app-entry.py as a module: beside this file, else ActionUI's in the checkout beside OMC."""
    here = os.path.dirname(os.path.abspath(__file__))
    candidates = [os.path.join(here, "linux-app-entry.py"),
                  os.path.join(here, "..", "..", "ActionUI", "Scripts", "linux-app-entry.py")]
    # No __pycache__ beside it: the Support folder is inside an applet or AppletBuilder bundle (or
    # the ActionUI checkout), and Linux's Python, unlike macOS's, has no cache folder elsewhere
    sys.dont_write_bytecode = True
    for path in candidates:
        if os.path.isfile(path):
            spec = importlib.util.spec_from_file_location("linux_app_entry", path)
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            return module
    print("command-services: no linux-app-entry.py beside " + here + " or in the ActionUI checkout", file=sys.stderr)
    sys.exit(1)


app_entry = load_app_entry()
UsageError = app_entry.UsageError


def services_folder():
    return os.path.join(app_entry.data_home(), "command", "services")


def services_file(application_id):
    return os.path.join(services_folder(), application_id + ".services")


def key_file_value(value):
    """A string as a key file value (GKeyFile): backslash, line breaks and tabs escaped, and a
    leading space kept as \\s."""
    escaped = value.replace("\\", "\\\\").replace("\n", "\\n").replace("\t", "\\t").replace("\r", "\\r")
    return "\\s" + escaped[1:] if escaped.startswith(" ") else escaped


def key_file_text(application_id, name, program, services):
    """The services list as a key file (see the module's comment)."""
    lines = ["[Applet]", "Version=1", "Application=" + key_file_value(application_id), "Name=" + key_file_value(name),
             "Program=" + key_file_value(program)]
    for index, service in enumerate(services):
        lines += ["", "[Service %d]" % index, "Title=" + key_file_value(service["title"]),
                  "Command=" + key_file_value(service["command"]),
                  # A MIME type has no ";" or backslash (MIME_TYPE_PATTERN), so the list needs no escape
                  "MimeTypes=" + "".join(item + ";" for item in service["mimeTypes"])]
    return "\n".join(lines) + "\n"


def files_the_older_way(send_types):
    """NSSendTypes naming files by pasteboard type: "NSFilenamesPboardType" (AppletBuilder's file
    services) or "public.file-url"; OMCApplet's service check takes the same two."""
    return isinstance(send_types, list) and any(item in ("NSFilenamesPboardType", "public.file-url") for item in send_types)


def file_services(info, plist_path):
    """The applet's file services: [{"title", "command", "mimeTypes"}], in NSServices order. A
    malformed NSServices is a UsageError; an item that is not a file service is left out, and one
    whose types have no known MIME type is left out with a message."""
    services = info.get("NSServices", [])
    if not isinstance(services, list):
        raise UsageError(plist_path + ": NSServices is not an array")
    result = []
    for index, service in enumerate(services):
        where = plist_path + ": NSServices item " + str(index)
        if not isinstance(service, dict):
            raise UsageError(where + " is not a dictionary")
        command = service.get("NSUserData")
        identifiers = app_entry.string_array(service.get("NSSendFileTypes", []), where + " NSSendFileTypes")
        if not identifiers and files_the_older_way(service.get("NSSendTypes")):
            # Files by their older pasteboard type (as AppletBuilder writes a file service): any
            # file or folder, as macOS offers it (and as the applet's own check accepts it)
            identifiers = ["public.item"]
        if not identifiers:
            continue  # a text service, or none: not for a file manager
        if not isinstance(command, str) or not command:
            raise UsageError(where + " has no NSUserData (the command it runs)")
        menu_item = service.get("NSMenuItem", {})
        title = menu_item.get("default") if isinstance(menu_item, dict) else None
        if not isinstance(title, str) or not title.strip():
            raise UsageError(where + " has no NSMenuItem title (its \"default\")")
        mime_types = []
        unknown = []
        for identifier in identifiers:
            known = app_entry.UTI_MIME_TYPES.get(identifier)
            if known:
                mime_types.extend(item for item in known if item not in mime_types)
            else:
                unknown.append(identifier)
        if not mime_types:
            print("command-services: " + where + " (" + title + "): no MIME type known for " + ", ".join(unknown)
                  + "; the service is not listed", file=sys.stderr)
            continue
        result.append({"title": title.strip(), "command": command, "mimeTypes": mime_types})
    return result


def write_atomically(path, text):
    """The file whole or not at all: a plug-in reading it meanwhile never sees half of it."""
    folder = os.path.dirname(path)
    os.makedirs(folder, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=".command-services-", dir=folder)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as file:
            file.write(text)
        os.replace(temporary, path)
    except BaseException:
        if os.path.exists(temporary):
            os.remove(temporary)
        raise


def install(folder):
    info = app_entry.read_info(folder)
    application_id = info["CFBundleIdentifier"]
    services = file_services(info, info["plistPath"])
    path = services_file(application_id)
    if not services:
        if os.path.isfile(path):
            os.remove(path)
            print("no file services; removed " + path)
        else:
            print("no file services in " + info["plistPath"])
        return
    program = app_entry.default_program(folder, info)
    base = os.path.basename(os.path.normpath(folder))
    name = info.get("CFBundleDisplayName") or info.get("CFBundleName") or (base[:-4] if base.endswith(".app") else base)
    write_atomically(path, key_file_text(application_id, name, program, services))
    print("installed " + path)


def uninstall(application_id):
    path = services_file(application_id)
    if os.path.isfile(path):
        os.remove(path)
        print("removed " + path)
    else:
        print("no services listed for " + application_id)


def main(arguments):
    if len(arguments) != 2 or arguments[0] not in ("install", "uninstall"):
        raise UsageError("usage: command-services.py install <applet folder> | uninstall <applet folder | application ID>")
    command, folder = arguments[0], os.path.abspath(arguments[1])
    if command == "uninstall" and not os.path.isdir(folder) and app_entry.is_valid_application_id(arguments[1]):
        uninstall(arguments[1])
        return
    if not os.path.isdir(folder):
        raise UsageError(folder + " is not a folder")
    if command == "install":
        install(folder)
    else:
        uninstall(app_entry.read_info(folder)["CFBundleIdentifier"])


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except UsageError as error:
        print("command-services: " + str(error), file=sys.stderr)
        sys.exit(64)
    except OSError as error:
        print("command-services: " + str(error), file=sys.stderr)
        sys.exit(1)
