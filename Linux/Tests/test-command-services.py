#!/usr/bin/env python3
"""Tests for Linux/command-services.py, run as a program with XDG_DATA_HOME in a temporary folder, so
nothing reaches the user's own desktop. Runs on Linux and macOS; needs ActionUI's
Scripts/linux-app-entry.py in the checkout beside OMC (or beside command-services.py).

Usage: python3 Linux/Tests/test-command-services.py
"""

import os
import plistlib
import subprocess
import sys
import tempfile
import unittest

SCRIPT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "command-services.py")

FIND_SERVICE = {"NSMenuItem": {"default": "Search Here with Find"}, "NSMessage": "runCommandService", "NSPortName": "CommandService",
                "NSUserData": "find.new", "NSSendFileTypes": ["public.folder", "com.apple.package"]}
TEXT_SERVICE = {"NSMenuItem": {"default": "Upper Case"}, "NSMessage": "runCommandService", "NSPortName": "CommandService",
                "NSUserData": "text.upper", "NSSendTypes": ["NSStringPboardType"], "NSReturnTypes": ["NSStringPboardType"]}


def unescape(value):
    """A key file value as GKeyFile reads it: \\s \\n \\t \\r \\\\ escapes."""
    result = []
    index = 0
    while index < len(value):
        character = value[index]
        if character == "\\" and index + 1 < len(value):
            result.append({"s": " ", "n": "\n", "t": "\t", "r": "\r", "\\": "\\"}.get(value[index + 1], "\\" + value[index + 1]))
            index += 2
        else:
            result.append(character)
            index += 1
    return "".join(result)


class CommandServicesTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.data_home = os.path.join(self.temporary.name, "share")
        self.apps = os.path.join(self.temporary.name, "apps")
        os.makedirs(self.apps)

    def tearDown(self):
        self.temporary.cleanup()

    def applet(self, name, info):
        """An applet folder in the Contents layout with its program in Contents/Linux."""
        folder = os.path.join(self.apps, name)
        os.makedirs(os.path.join(folder, "Contents", "Linux"))
        with open(os.path.join(folder, "Contents", "Info.plist"), "wb") as file:
            plistlib.dump(info, file)
        program = os.path.join(folder, "Contents", "Linux", name[:-4] if name.endswith(".app") else name)
        with open(program, "w") as file:
            file.write("#!/bin/sh\n")
        os.chmod(program, 0o755)
        return folder

    def flat_applet(self, name, info):
        """An applet folder in the flat layout: Info.plist and the program at its top."""
        folder = os.path.join(self.apps, name)
        os.makedirs(os.path.join(folder, "Scripts"))
        with open(os.path.join(folder, "Info.plist"), "wb") as file:
            plistlib.dump(info, file)
        program = os.path.join(folder, name[:-4] if name.endswith(".app") else name)
        with open(program, "w") as file:
            file.write("#!/bin/sh\n")
        os.chmod(program, 0o755)
        return folder

    def run_script(self, *arguments):
        environment = dict(os.environ, XDG_DATA_HOME=self.data_home, PYTHONDONTWRITEBYTECODE="1")
        return subprocess.run([sys.executable, SCRIPT] + list(arguments), env=environment, capture_output=True, text=True)

    def listing_path(self, application_id):
        return os.path.join(self.data_home, "command", "services", application_id + ".services")

    def listing(self, application_id):
        """The key file read back, GKeyFile's way: {"version", "application", "name", "program",
        "services": [{"title", "command", "mimeTypes"}]}, values unescaped."""
        groups = {}
        order = []
        group = None
        with open(self.listing_path(application_id), encoding="utf-8") as file:
            for line in file.read().split("\n"):
                if line.startswith("[") and line.endswith("]"):
                    group = line[1:-1]
                    groups[group] = {}
                    order.append(group)
                elif "=" in line:
                    key, value = line.split("=", 1)
                    groups[group][key] = unescape(value)
        applet = groups["Applet"]
        services = [{"title": groups[name]["Title"], "command": groups[name]["Command"],
                     "mimeTypes": [item for item in groups[name]["MimeTypes"].split(";") if item]}
                    for name in order if name.startswith("Service ")]
        self.assertEqual([name for name in order if name.startswith("Service ")], ["Service %d" % i for i in range(len(services))])
        return {"version": int(applet["Version"]), "application": applet["Application"], "name": applet["Name"],
                "program": applet["Program"], "services": services}

    def test_file_services_are_listed_and_text_services_left_out(self):
        folder = self.applet("Find.app", {"CFBundleIdentifier": "com.example.Find", "CFBundleName": "Find",
                                          "NSServices": [FIND_SERVICE, TEXT_SERVICE]})
        result = self.run_script("install", folder)
        self.assertEqual(result.returncode, 0, result.stderr)
        listing = self.listing("com.example.Find")
        self.assertEqual(listing["version"], 1)
        self.assertEqual(listing["application"], "com.example.Find")
        self.assertEqual(listing["name"], "Find")
        self.assertEqual(listing["program"], os.path.join(folder, "Contents", "Linux", "Find"))
        self.assertEqual(listing["services"], [{"title": "Search Here with Find", "command": "find.new", "mimeTypes": ["inode/directory"]}],
                         "one type for both folder identifiers; the text service is not there")
        self.assertEqual([name for name in os.listdir(os.path.dirname(self.listing_path("x.y"))) if name.startswith(".")], [],
                         "no temporary file left")

    def test_a_flat_applet_is_listed_with_its_program_at_the_top(self):
        folder = self.flat_applet("Find.app", {"CFBundleIdentifier": "com.example.Find", "CFBundleName": "Find",
                                               "NSServices": [FIND_SERVICE, TEXT_SERVICE]})
        result = self.run_script("install", folder)
        self.assertEqual(result.returncode, 0, result.stderr)
        listing = self.listing("com.example.Find")
        self.assertEqual(listing["program"], os.path.join(folder, "Find"))
        self.assertEqual(listing["services"], [{"title": "Search Here with Find", "command": "find.new", "mimeTypes": ["inode/directory"]}])
        result = self.run_script("uninstall", folder)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(os.path.exists(self.listing_path("com.example.Find")))

    def test_files_the_older_way_are_any_file_or_folder(self):
        # As AppletBuilder writes a file service (plist_edit.py)
        older = {"NSMenuItem": {"default": "Show Attributes"}, "NSMessage": "runCommandService", "NSPortName": "CommandService",
                 "NSUserData": "xattr.show", "NSSendTypes": ["NSFilenamesPboardType"], "NSReturnTypes": [], "NSRequiredContext": {}}
        folder = self.applet("Xattr.app", {"CFBundleIdentifier": "com.example.Xattr", "NSServices": [older, TEXT_SERVICE]})
        result = self.run_script("install", folder)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.listing("com.example.Xattr")["services"],
                         [{"title": "Show Attributes", "command": "xattr.show", "mimeTypes": ["application/octet-stream", "inode/directory"]}])

    def test_values_are_escaped_as_a_key_file_needs(self):
        odd = dict(FIND_SERVICE, NSMenuItem={"default": "Back\\slash; tab\there"})
        folder = self.applet("Odd Name.app", {"CFBundleIdentifier": "com.example.OddName", "CFBundleName": " Spaced\nName",
                                              "NSServices": [odd]})
        result = self.run_script("install", folder)
        self.assertEqual(result.returncode, 0, result.stderr)
        with open(self.listing_path("com.example.OddName"), encoding="utf-8") as file:
            text = file.read()
        self.assertIn("Name=\\sSpaced\\nName\n", text, "a leading space and a line break escaped")
        self.assertIn("Title=Back\\\\slash; tab\\there\n", text)
        listing = self.listing("com.example.OddName")
        self.assertEqual(listing["name"], " Spaced\nName")
        self.assertEqual(listing["services"][0]["title"], "Back\\slash; tab\there")
        self.assertEqual(listing["program"], os.path.join(folder, "Contents", "Linux", "Odd Name"))

    def test_an_applet_with_no_file_service_has_no_listing(self):
        folder = self.applet("Plain.app", {"CFBundleIdentifier": "com.example.Plain", "NSServices": [FIND_SERVICE]})
        self.assertEqual(self.run_script("install", folder).returncode, 0)
        self.assertTrue(os.path.isfile(self.listing_path("com.example.Plain")))
        with open(os.path.join(folder, "Contents", "Info.plist"), "wb") as file:
            plistlib.dump({"CFBundleIdentifier": "com.example.Plain", "NSServices": [TEXT_SERVICE]}, file)
        result = self.run_script("install", folder)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(os.path.exists(self.listing_path("com.example.Plain")), "the earlier listing goes")
        with open(os.path.join(folder, "Contents", "Info.plist"), "wb") as file:
            plistlib.dump({"CFBundleIdentifier": "com.example.Plain"}, file)
        self.assertEqual(self.run_script("install", folder).returncode, 0, "no NSServices at all")
        self.assertFalse(os.path.exists(self.listing_path("com.example.Plain")))

    def test_types_with_no_known_mime_type_leave_the_service_out(self):
        unknown = dict(FIND_SERVICE, NSUserData="odd", NSSendFileTypes=["com.example.nothing"])
        mixed = dict(FIND_SERVICE, NSUserData="images", NSMenuItem={"default": "Images"}, NSSendFileTypes=["public.png", "com.example.nothing"])
        folder = self.applet("Odd.app", {"CFBundleIdentifier": "com.example.Odd", "NSServices": [unknown, mixed]})
        result = self.run_script("install", folder)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("no MIME type known for com.example.nothing", result.stderr)
        self.assertEqual(self.listing("com.example.Odd")["services"], [{"title": "Images", "command": "images", "mimeTypes": ["image/png"]}])

    def test_malformed_services_are_refused_and_leave_the_listing(self):
        folder = self.applet("Bad.app", {"CFBundleIdentifier": "com.example.Bad", "NSServices": [FIND_SERVICE]})
        self.assertEqual(self.run_script("install", folder).returncode, 0)
        cases = ({"NSServices": "find.new"}, {"NSServices": ["find.new"]},
                 {"NSServices": [dict(FIND_SERVICE, NSSendFileTypes="public.folder")]},
                 {"NSServices": [dict(FIND_SERVICE, NSUserData="")]}, {"NSServices": [dict(FIND_SERVICE, NSMenuItem={})]},
                 {"NSServices": [dict(FIND_SERVICE, NSMenuItem="Search")]})
        for case in cases:
            with open(os.path.join(folder, "Contents", "Info.plist"), "wb") as file:
                plistlib.dump(dict({"CFBundleIdentifier": "com.example.Bad"}, **case), file)
            result = self.run_script("install", folder)
            self.assertEqual(result.returncode, 64, str(case) + result.stderr)
            self.assertEqual(self.listing("com.example.Bad")["services"][0]["command"], "find.new", str(case))

    def test_uninstall_by_folder_and_by_id(self):
        folder = self.applet("Gone.app", {"CFBundleIdentifier": "com.example.Gone", "NSServices": [FIND_SERVICE]})
        self.assertEqual(self.run_script("install", folder).returncode, 0)
        result = self.run_script("uninstall", folder)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(os.path.exists(self.listing_path("com.example.Gone")))
        self.assertIn("no services listed", self.run_script("uninstall", folder).stdout)
        self.assertEqual(self.run_script("install", folder).returncode, 0)
        result = self.run_script("uninstall", "com.example.Gone")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(os.path.exists(self.listing_path("com.example.Gone")))

    def test_bad_arguments(self):
        self.assertEqual(self.run_script().returncode, 64)
        self.assertEqual(self.run_script("list", self.apps).returncode, 64)
        self.assertEqual(self.run_script("install", os.path.join(self.apps, "missing.app")).returncode, 64)


if __name__ == "__main__":
    unittest.main()
