#!/usr/bin/env python3
"""
Self-tests for the `omc` Python module.

The module lives (canonically) in the AppletBuilder bundle at
  Distribution/AppletBuilder.app/Contents/Library/Packages/omc.py
and AppletBuilder copies it, with actionui_remote.py beside it, into every applet
that embeds Python and has Python command handlers. This script runs the unittest
suite against that shipped copy, so the self-tests track exactly what ships.

What it does: drives the module's two halves against stand-ins - the ActionUI verbs
against actionui_remote_testing.FakeServer, asserted from the server's own request
log, and the OMC verbs against stub helper tools that record their argv. Both are
asserted from the far side rather than from the caller, because the failure that
matters here is a call that silently does nothing.

It pins the EXACT test count for the same reason run_tests.py does next door: a
green report with fewer checks than expected is the bug worth catching.

Requires the sibling ActionUI checkout for actionui_remote_testing.py, and exits 2
rather than 0 when it is absent: a green run that executed nothing is the failure
this script exists to prevent.

Run:   python3 Tools/omc_python_tests/run_tests.py
Exit:  0 = all passed, 1 = one or more failures, 2 = could not run.
"""
from __future__ import annotations

import os
import subprocess
import sys

EXPECTED_TEST_COUNT = 35

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(os.path.dirname(HERE))
PACKAGES = os.path.join(REPO_ROOT, "Distribution", "AppletBuilder.app",
                        "Contents", "Library", "Packages")
ACTIONUI_TESTING = os.path.join(REPO_ROOT, "..", "ActionUI", "ActionUIRemote", "Python",
                                "actionui_remote_testing.py")


def main() -> int:
    for required in (os.path.join(PACKAGES, "omc.py"),
                     os.path.join(PACKAGES, "actionui_remote.py")):
        if not os.path.exists(required):
            print("ERROR: missing %s" % required)
            print("       The shipped modules are what these tests exercise.")
            return 2

    if not os.path.exists(ACTIONUI_TESTING):
        print("ERROR: %s not found." % ACTIONUI_TESTING)
        print("       These tests drive the module against ActionUI's fake host, which lives in")
        print("       the sibling ActionUI checkout. Clone it beside this repo to run them.")
        # Deliberately NOT a zero exit. A machine without the checkout would otherwise report a
        # green run having executed nothing, which is the same silent no-run the count pin below
        # exists to catch - and the more likely one, since it needs no code change to happen.
        return 2

    # -v so the count below is parsed from unittest's own report rather than assumed.
    completed = subprocess.run([sys.executable, "-m", "unittest", "-v", "test_omc"],
                               cwd=HERE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    output = completed.stdout.decode("utf-8", "replace")
    sys.stdout.write(output)

    if completed.returncode != 0:
        print("\nFAILED: unittest reported failures.")
        return 1

    ran = 0
    for line in output.splitlines():
        if line.startswith("Ran ") and " test" in line:
            try:
                ran = int(line.split()[1])
            except (IndexError, ValueError):
                ran = 0

    if ran != EXPECTED_TEST_COUNT:
        print("\nFAILED: expected %d tests, unittest ran %d." % (EXPECTED_TEST_COUNT, ran))
        print("        If tests were added or removed on purpose, update EXPECTED_TEST_COUNT")
        print("        in %s." % os.path.relpath(__file__, REPO_ROOT))
        return 1

    print("\nAll %d tests passed." % ran)
    return 0


if __name__ == "__main__":
    sys.exit(main())
