"""The window's END_OK_SUBCOMMAND_ID, a .py command: logs the field's value the engine read from
the closed window, as omc.context() and the environment give it."""

import os

lines = ["window.ok.env:" + os.environ.get("OMC_ACTIONUI_VIEW_2_VALUE", "")]
try:
    import omc
    lines.append("window.ok.omc:" + str(omc.context().view_value(2)))
except Exception as error:  # the test reports what failed
    lines.append("window.ok.omc:error %s: %s" % (type(error).__name__, error))

with open(os.environ["PYTHONTEST_LOG"], "a") as log:
    log.write("\n".join(lines) + "\n")
