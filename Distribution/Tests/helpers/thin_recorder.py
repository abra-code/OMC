"""Stand-in for thin_applet_python.py, for 50-thin-python.test.sh.

The phase under test assembles arguments for the front end and runs it through
the applet's own interpreter; running the REAL one would take minutes per case
and needs a whole applet with a working embedded Python. So lib.build.sh names
the front end through AB_THIN_PYTHON_TOOL and this records what it was called
with, one tab-separated line of argv per invocation.

It also honors the half of the front end's contract the phase depends on: a
successful `plan` leaves the plan file it was told to write. Without that, the
plan-and-apply chain and the remembered-plan fallback would both be asserting
against a file that never appeared.

  THIN_RECORD      where to append the argv lines (required)
  THIN_RECORD_RC   exit code to report, default 0 - the failing-phase cases
"""

import json
import os
import sys

args = sys.argv[1:]

record = os.environ.get("THIN_RECORD")
if not record:
    sys.stderr.write("thin_recorder.py: THIN_RECORD is not set\n")
    raise SystemExit(90)

with open(record, "a") as f:
    f.write("\t".join(args) + "\n")

rc = int(os.environ.get("THIN_RECORD_RC", "0"))

if rc == 0 and args and args[0] == "plan" and "--plan" in args:
    plan_path = args[args.index("--plan") + 1]
    with open(plan_path, "w") as f:
        json.dump({"schema": "python-embedding/thinning-plan@2",
                   "remove": {"modules": []}}, f)

# Printed so a test can also prove the transcript reaches the log.
sys.stdout.write("thin_recorder: %s\n" % (args[0] if args else "(no verb)"))
raise SystemExit(rc)
