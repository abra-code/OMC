#!/usr/bin/env python3
"""
Unit tests for the ActionUI JSON verifier.

Covers the platform-suffix helpers, the cross-platform (authoring) and
--platform (deployment) validation modes, the `platforms` schema annotation,
and the command-line surface (flag parsing, recursion, exit codes).

Run:
    python3 test_validate_actionui.py
    python3 -m unittest -v
"""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

_HERE = Path(__file__).parent
sys.path.insert(0, str(_HERE))

from verifier import SchemaLoader, ElementValidator  # noqa: E402
from verifier.platform_filter import (  # noqa: E402
    PLATFORM_FAMILIES,
    split_platform_suffix,
    platform_matches,
    platforms_include,
)

_SCHEMAS = _HERE / "schemas"
_VALIDATOR = _HERE / "validate_actionui.py"


def _validate(doc: dict, platform: str | None = None):
    """Validate an in-memory element tree; returns the issue list."""
    validator = ElementValidator(SchemaLoader(_SCHEMAS), target_platform=platform)
    return validator.validate(doc, "test", set())


def _errors(issues):
    return [i for i in issues if i.severity == "error"]


def _warnings(issues):
    return [i for i in issues if i.severity == "warning"]


def _msg(issues):
    return " | ".join(str(i) for i in issues)


class PlatformHelperTests(unittest.TestCase):
    def test_split_platform_suffix(self):
        self.assertEqual(split_platform_suffix("text"), ("text", None))
        self.assertEqual(split_platform_suffix("text:ios"), ("text", "ios"))
        # Splits on the LAST colon only.
        self.assertEqual(split_platform_suffix("a:b:ios"), ("a:b", "ios"))

    def test_umbrella_token_matches_members(self):
        self.assertTrue(platform_matches("apple", "ios"))
        self.assertTrue(platform_matches("apple", "macos"))
        self.assertTrue(platform_matches("android", "androidtv"))

    def test_concrete_token_is_not_an_umbrella(self):
        # 'ios' must not match the generic 'apple' umbrella token.
        self.assertFalse(platform_matches("ios", "apple"))
        self.assertFalse(platform_matches("android", "ios"))

    def test_exact_match(self):
        self.assertTrue(platform_matches("android", "android"))

    def test_platforms_include(self):
        self.assertTrue(platforms_include(["android"], "android"))
        self.assertTrue(platforms_include(["apple"], "macos"))
        self.assertFalse(platforms_include(["android"], "ios"))

    def test_families_are_disjoint_and_cover_suffixes(self):
        # apple and android families do not overlap.
        self.assertTrue(PLATFORM_FAMILIES["apple"].isdisjoint(PLATFORM_FAMILIES["android"]))


class CrossPlatformModeTests(unittest.TestCase):
    """Default mode: no --platform. The document is authored for all platforms."""

    def test_valid_document_is_clean(self):
        doc = {
            "type": "VStack",
            "properties": {"spacing": 12, "padding": 16},
            "children": [
                {"type": "Text", "properties": {"text": "hi", "frame": {"width": 100}}},
            ],
        }
        issues = _validate(doc)
        self.assertEqual(issues, [], _msg(issues))

    def test_frame_is_canonical_sizing(self):
        doc = {"type": "Text", "properties": {"text": "x", "frame": {"width": 200, "height": 40}}}
        self.assertEqual(_errors(_validate(doc)), [])
        self.assertEqual(_warnings(_validate(doc)), [])

    def test_frame_infinity_is_accepted(self):
        doc = {"type": "Text", "properties": {"text": "x", "frame": {"maxWidth": "infinity"}}}
        self.assertEqual(_errors(_validate(doc)), [], _msg(_validate(doc)))

    def test_top_level_width_is_not_a_property(self):
        # Regression guard: there is no top-level width/height (not SwiftUI).
        doc = {"type": "Text", "properties": {"text": "x", "width": 100}}
        warns = _warnings(_validate(doc))
        self.assertEqual(len(warns), 1, _msg(_validate(doc)))
        self.assertIn("width", str(warns[0]))
        self.assertIn("not a known property", str(warns[0]))

    def test_android_only_property_unsuffixed_warns(self):
        doc = {"type": "Text", "properties": {"text": "x", "weight": 1}}
        warns = _warnings(_validate(doc))
        self.assertEqual(len(warns), 1, _msg(_validate(doc)))
        self.assertIn("platform-specific", str(warns[0]))
        self.assertEqual(_errors(_validate(doc)), [])

    def test_android_only_property_suffixed_is_clean(self):
        doc = {"type": "Text", "properties": {"text": "x", "weight:android": 1}}
        self.assertEqual(_validate(doc), [], _msg(_validate(doc)))

    def test_android_only_property_wrong_suffix_warns(self):
        doc = {"type": "Text", "properties": {"text": "x", "weight:macos": 1}}
        warns = _warnings(_validate(doc))
        self.assertEqual(len(warns), 1, _msg(_validate(doc)))
        self.assertIn("not available on 'macos'", str(warns[0]))

    def test_common_property_may_be_suffixed_without_warning(self):
        doc = {"type": "Text", "properties": {"text": "base", "text:ios": "ios"}}
        self.assertEqual(_validate(doc), [], _msg(_validate(doc)))

    def test_unknown_property_warns(self):
        doc = {"type": "Text", "properties": {"text": "x", "bogus": 1}}
        warns = _warnings(_validate(doc))
        self.assertEqual(len(warns), 1)
        self.assertIn("not a known property", str(warns[0]))

    def test_frame_bad_value_is_error(self):
        doc = {"type": "Text", "properties": {"text": "x", "frame": {"width": "wide"}}}
        self.assertTrue(_errors(_validate(doc)), _msg(_validate(doc)))

    def test_missing_type_is_error(self):
        self.assertTrue(_errors(_validate({"properties": {"text": "x"}})))

    def test_unknown_type_is_error(self):
        self.assertTrue(_errors(_validate({"type": "Nope"})))

    def test_duplicate_id_is_error(self):
        doc = {
            "type": "VStack",
            "children": [
                {"type": "Text", "id": 5, "properties": {"text": "a"}},
                {"type": "Text", "id": 5, "properties": {"text": "b"}},
            ],
        }
        self.assertTrue(any("duplicate" in str(i) for i in _errors(_validate(doc))))


class DeploymentModeTests(unittest.TestCase):
    """--platform <p>: validate as if shipped to one platform."""

    def test_android_only_property_active_on_android(self):
        doc = {"type": "Text", "properties": {"text": "x", "weight:android": 1}}
        self.assertEqual(_validate(doc, platform="android"), [])

    def test_other_platform_variant_is_dropped(self):
        # weight:android is irrelevant for an iOS build — dropped, not warned.
        doc = {"type": "Text", "properties": {"text": "x", "weight:android": 1}}
        self.assertEqual(_validate(doc, platform="ios"), [])

    def test_base_android_only_property_warns_on_ios(self):
        doc = {"type": "Text", "properties": {"text": "x", "weight": 1}}
        warns = _warnings(_validate(doc, platform="ios"))
        self.assertEqual(len(warns), 1, _msg(_validate(doc, platform="ios")))
        self.assertIn("not available on target platform 'ios'", str(warns[0]))

    def test_base_android_only_property_ok_on_android(self):
        doc = {"type": "Text", "properties": {"text": "x", "weight": 1}}
        self.assertEqual(_validate(doc, platform="android"), [])

    def test_other_platform_text_variant_dropped(self):
        doc = {"type": "Text", "properties": {"text:ios": "only ios"}}
        # On android the ios variant is dropped; the unsuffixed/required check
        # should not fire for a common optional property like text.
        self.assertEqual(_errors(_validate(doc, platform="android")), [])

    def test_umbrella_suffix_applies_to_member_platform(self):
        # weight:android applies to androidtv via the android umbrella.
        doc = {"type": "Text", "properties": {"text": "x", "weight:android": 1}}
        self.assertEqual(_validate(doc, platform="androidtv"), [])


class CliTests(unittest.TestCase):
    def _run(self, *args):
        return subprocess.run(
            [sys.executable, str(_VALIDATOR), *args],
            capture_output=True, text=True,
        )

    def _write(self, dirpath: Path, name: str, doc: dict) -> Path:
        p = dirpath / name
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(json.dumps(doc))
        return p

    def test_valid_file_exits_zero(self):
        with tempfile.TemporaryDirectory() as d:
            f = self._write(Path(d), "ok.json", {"type": "Text", "properties": {"text": "x"}})
            r = self._run(str(f))
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            self.assertIn("All files valid", r.stdout)

    def test_unknown_platform_errors(self):
        with tempfile.TemporaryDirectory() as d:
            f = self._write(Path(d), "ok.json", {"type": "Text", "properties": {"text": "x"}})
            r = self._run("--platform", "bogus", str(f))
            self.assertEqual(r.returncode, 2)
            self.assertIn("unknown platform", (r.stdout + r.stderr).lower())

    def test_strict_elevates_warnings(self):
        with tempfile.TemporaryDirectory() as d:
            # base android-only weight -> warning in cross-platform mode
            f = self._write(Path(d), "w.json", {"type": "Text", "properties": {"text": "x", "weight": 1}})
            normal = self._run(str(f))
            strict = self._run("--strict", str(f))
            self.assertEqual(normal.returncode, 2)   # warnings only
            self.assertEqual(strict.returncode, 1)   # elevated to failure

    def test_recursive_descends_into_subdirs(self):
        with tempfile.TemporaryDirectory() as d:
            self._write(Path(d), "sub/nested.json", {"type": "Text", "properties": {"text": "x"}})
            # Non-recursive: top-level glob finds nothing.
            flat = self._run(str(d))
            self.assertIn("No *.json files", flat.stdout + flat.stderr)
            # Recursive: the nested file is found and validated.
            rec = self._run("-r", str(d))
            self.assertEqual(rec.returncode, 0, rec.stdout + rec.stderr)
            self.assertIn("All files valid", rec.stdout)

    def test_invalid_json_file_exits_one(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "bad.json"
            p.write_text("{ not valid ")
            r = self._run(str(p))
            self.assertEqual(r.returncode, 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
