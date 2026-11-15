#!/usr/bin/env python3
"""Tests for AppletBuilder's Scripts/plist_edit.py: the --plist mode Linux uses for an Info.plist
(no plutil there), in XML and binary, and the Services operations, which keep a service's own
file types when its title or command is saved. Runs on macOS and Linux; not an omctest file (the
suite runs *.test.sh).

Usage: python3 Distribution/Tests/test-plist-edit.py
"""

import json
import os
import plistlib
import subprocess
import sys
import tempfile
import unittest

EDITOR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "AppletBuilder.app", "Contents", "Resources", "Scripts", "plist_edit.py")


def sample_services():
    return [
        {"NSMenuItem": {"default": "Show Path"}, "NSUserData": "demo.show", "NSSendFileTypes": ["public.item"]},
        {"NSMenuItem": {"default": "Folders Only"}, "NSUserData": "demo.show", "NSSendFileTypes": ["public.folder"],
         "NSSendTypes": ["NSFilenamesPboardType"]},
        {"NSMenuItem": {"default": "Upper Case"}, "NSUserData": "text.upper", "NSSendTypes": ["NSStringPboardType"]},
    ]


class PlistEditTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()

    def tearDown(self):
        self.temporary.cleanup()

    def run_editor(self, *arguments):
        environment = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
        return subprocess.run([sys.executable, EDITOR] + list(arguments), env=environment, capture_output=True, text=True)

    def info_plist(self, fmt):
        path = os.path.join(self.temporary.name, "Info.plist")
        with open(path, "wb") as file:
            plistlib.dump({"CFBundleName": "Demo", "CFBundleIdentifier": "com.example.Demo", "NSServices": sample_services()}, file, fmt=fmt, sort_keys=False)
        return path

    def read_plist(self, path):
        with open(path, "rb") as file:
            header = file.read(8)
            file.seek(0)
            return header.startswith(b"bplist"), plistlib.load(file)

    def edit(self, path, *arguments):
        result = self.run_editor("--plist", path, *arguments)
        self.assertEqual(result.returncode, 0, result.stderr)
        return self.read_plist(path)

    def test_a_plist_is_edited_in_its_own_format(self):
        for fmt, binary in ((plistlib.FMT_XML, False), (plistlib.FMT_BINARY, True)):
            path = self.info_plist(fmt)
            is_binary, data = self.edit(path, "set_keys", "CFBundleVersion", "6.0.0", "CFBundleName", "Renamed")
            self.assertEqual(is_binary, binary)
            self.assertEqual((data["CFBundleVersion"], data["CFBundleName"]), ("6.0.0", "Renamed"))
            self.assertEqual(list(data.keys())[:2], ["CFBundleName", "CFBundleIdentifier"], "key order kept")

    def test_saving_a_title_keeps_the_services_own_file_types(self):
        path = self.info_plist(plistlib.FMT_XML)
        _, data = self.edit(path, "update_service", "1", "Folders Only, Renamed", "demo.show", "files")
        service = data["NSServices"][1]
        self.assertEqual(service["NSMenuItem"]["default"], "Folders Only, Renamed")
        self.assertEqual(service["NSSendFileTypes"], ["public.folder"], "a folders-only service stays one")
        self.assertEqual(service["NSSendTypes"], ["NSFilenamesPboardType"])
        _, data = self.edit(path, "update_service", "0", "Show Path", "demo.other", "files")
        self.assertEqual(data["NSServices"][0]["NSSendFileTypes"], ["public.item"])
        self.assertEqual(data["NSServices"][0]["NSUserData"], "demo.other")
        self.assertNotIn("NSSendTypes", data["NSServices"][0])

    def test_saving_keeps_types_the_picker_cannot_show(self):
        # The Input picker shows "text" only for NSStringPboardType first (services.selected.sh),
        # so a save with the picker as shown must keep the types as they are
        path = os.path.join(self.temporary.name, "Info.plist")
        odd = [{"NSMenuItem": {"default": "Modern Text"}, "NSUserData": "t", "NSSendTypes": ["public.utf8-plain-text"]},
               {"NSMenuItem": {"default": "Mixed"}, "NSUserData": "m", "NSSendTypes": ["NSStringPboardType", "NSFilenamesPboardType"]}]
        with open(path, "wb") as file:
            plistlib.dump({"NSServices": odd}, file)
        _, data = self.edit(path, "update_service", "0", "Modern Text, Renamed", "t", "files")
        self.assertEqual(data["NSServices"][0]["NSSendTypes"], ["public.utf8-plain-text"])
        _, data = self.edit(path, "update_service", "1", "Mixed, Renamed", "m", "text")
        self.assertEqual(data["NSServices"][1]["NSSendTypes"], ["NSStringPboardType", "NSFilenamesPboardType"])

    def test_changing_the_input_kind_sets_its_types(self):
        path = self.info_plist(plistlib.FMT_XML)
        _, data = self.edit(path, "update_service", "0", "Show Path", "demo.show", "text")
        self.assertEqual(data["NSServices"][0]["NSSendTypes"], ["NSStringPboardType"])
        self.assertNotIn("NSSendFileTypes", data["NSServices"][0])
        _, data = self.edit(path, "update_service", "2", "Upper Case", "text.upper", "text")
        self.assertEqual(data["NSServices"][2]["NSSendTypes"], ["NSStringPboardType"], "a text service saved as text")
        _, data = self.edit(path, "update_service", "2", "Upper Case", "text.upper", "files")
        self.assertEqual(data["NSServices"][2]["NSSendTypes"], ["NSFilenamesPboardType"])

    def test_services_are_added_and_removed(self):
        path = self.info_plist(plistlib.FMT_BINARY)
        _, data = self.edit(path, "append_service", "New Service", "demo.show")
        self.assertEqual(len(data["NSServices"]), 4)
        self.assertEqual(data["NSServices"][3]["NSSendTypes"], ["NSFilenamesPboardType"])
        _, data = self.edit(path, "remove_service", "0")
        self.assertEqual([item["NSMenuItem"]["default"] for item in data["NSServices"]], ["Folders Only", "Upper Case", "New Service"])

    def test_a_json_command_file_is_edited_as_before(self):
        path = os.path.join(self.temporary.name, "Command.json")
        with open(path, "w") as file:
            json.dump({"COMMAND_LIST": [{"NAME": "A", "COMMAND_ID": "a"}]}, file)
        result = self.run_editor(path, "append_command", "Demo")
        self.assertEqual(result.returncode, 0, result.stderr)
        with open(path) as file:
            self.assertEqual(len(json.load(file)["COMMAND_LIST"]), 2)

    def test_bad_arguments(self):
        self.assertEqual(self.run_editor("--plist").returncode, 1)
        self.assertEqual(self.run_editor().returncode, 1)


if __name__ == "__main__":
    unittest.main()
