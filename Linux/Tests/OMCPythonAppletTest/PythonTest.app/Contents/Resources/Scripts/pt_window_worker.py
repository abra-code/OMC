"""Started by pt.window.init.sh after the window opens: reads field 2 of the window through omc.py
(the ActionUI remote bridge), writes it back changed and closes the window with OK
(omc_dialog_control), then logs what it read and the interpreter it ran on."""

import os
import sys
import time

time.sleep(1)  # the init handler returns first; the window is then open

lines = ["window.worker.python3:" + os.path.realpath(sys.executable)]
try:
    import omc
    window = omc.window()
    value = window.get_string(2)
    window.set_string(2, value + " via omc.py")
    time.sleep(0.5)
    window.terminate_ok()
    lines.append("window.worker.read:" + value)
except Exception as error:  # the test reports what failed
    lines.append("window.worker.error:%s: %s" % (type(error).__name__, error))

with open(os.environ["PYTHONTEST_LOG"], "a") as log:
    log.write("\n".join(lines) + "\n")
