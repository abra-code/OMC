"""A .py command: logs the interpreter that runs it and what the embedded Python gives it, one
"key:value" line each, for run.sh to check."""

import os
import ssl
import sys

lines = []
lines.append("py.executable:" + os.path.realpath(sys.executable))
lines.append("py.prefix:" + os.path.realpath(sys.prefix))
packages = os.path.join(os.environ.get("OMC_APP_BUNDLE_PATH", ""), "Contents", "Library", "Packages")
lines.append("py.packages-on-path:" + ("yes" if packages in sys.path else "no"))
lines.append("py.pycache-prefix:" + (sys.pycache_prefix or ""))
lines.append("py.openssl:" + ssl.OPENSSL_VERSION)
# The certificate hook (Python-Embedding's _pyembed_ca) finds the system's CA bundle
context = ssl.create_default_context()
lines.append("py.ca-certificates:" + str(context.cert_store_stats().get("x509_ca", 0)))
try:
    import omc
    lines.append("py.omc:" + os.path.realpath(omc.__file__))
except Exception as error:  # the test reports what failed
    lines.append("py.omc:error %s: %s" % (type(error).__name__, error))

with open(os.environ["PYTHONTEST_LOG"], "a") as log:
    log.write("\n".join(lines) + "\n")
