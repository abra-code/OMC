#! /bin/sh
#
# Build OMC by building the "OMC Distribution" scheme of OMC.xcworkspace.
#
# This scheme builds Abracode.framework, OMCApplet, OMCService and OnMyCommandCM
# together with their implicit dependencies, replacing the old loop that built
# every sub-project individually (which had become hard to maintain).
#
# Usage: ./build.sh [debug|ship] [action] [--python]
#   See usage() below or run ./build.sh --help for details.

WORKSPACE="OMC.xcworkspace"
SCHEME="OMC Distribution"
PYTHON_SCHEME="OMCPythonApplet"

usage() {
	cat <<'EOF'
Usage: ./build.sh [debug|ship] [action] [--python]

Builds the "OMC Distribution" scheme of OMC.xcworkspace (Abracode.framework,
OMCApplet, OMCService and OnMyCommandCM, with their implicit dependencies).

Arguments (positional, both optional):
  configuration   case-insensitive; "debug" -> Debug, "ship" or "release" ->
                  Release (default: ship)
  action          xcodebuild action to run (default: build). One of:
                    build     compile the products (default)
                    clean     remove build products and intermediates
                    archive   build a Release archive for distribution
                    analyze   run the static analyzer
                    install   build and install the products
                    test      build and run the scheme's tests
                  (clean can be combined as a separate run, e.g. "clean" then "build")

Options:
  --python        also build the OMCPythonApplet scheme (in addition to the
                  distribution). Gated behind a flag because it compiles the
                  embedded Python from scratch and is slow; the regular
                  distribution build does not need it.
  -h, --help      show this help and exit

Examples:
  ./build.sh                 # Release build of the distribution
  ./build.sh debug           # Debug build
  ./build.sh ship clean      # clean the Release build
  ./build.sh debug build --python   # Debug build incl. the Python applet
EOF
}

BUILD_PYTHON=0
IN_CONFIG=""
IN_ACTION=""
POSITIONAL_COUNT=0

# Parse args: --python is a flag, remaining positional args are config then action.
for arg in "$@"; do
	case "$arg" in
		-h|--help)
			usage
			exit 0
			;;
		--python)
			BUILD_PYTHON=1
			;;
		--*)
			echo "Unknown option: $arg" >&2
			echo "" >&2
			usage >&2
			exit 2
			;;
		*)
			if test "$POSITIONAL_COUNT" -eq 0; then
				IN_CONFIG="$arg"
			elif test "$POSITIONAL_COUNT" -eq 1; then
				IN_ACTION="$arg"
			fi
			POSITIONAL_COUNT=`expr "$POSITIONAL_COUNT" + 1`
			;;
	esac
done

PARENT_DIR=`dirname "$0"`
cd "$PARENT_DIR" || exit 1

if test "$IN_CONFIG" = ""; then
	IN_CONFIG="ship"
fi

if test "$IN_ACTION" = ""; then
	IN_ACTION="build"
fi

# Map the configuration name to an Xcode configuration (case-insensitive).
# "ship" and "release" are synonyms for the Release configuration.
case "`echo "$IN_CONFIG" | tr '[:upper:]' '[:lower:]'`" in
	debug)
		BUILD_CONFIG="Debug"
		;;
	ship|release)
		BUILD_CONFIG="Release"
		;;
	*)
		echo "Unknown configuration: $IN_CONFIG" >&2
		echo "" >&2
		usage >&2
		exit 2
		;;
esac

build_scheme() {
	SCHEME_NAME="$1"
	echo ""
	echo "          **********************************************"
	echo "             Building '$SCHEME_NAME' ($BUILD_CONFIG)"
	echo "          **********************************************"
	echo ""
	xcodebuild \
		-workspace "$WORKSPACE" \
		-scheme "$SCHEME_NAME" \
		-configuration "$BUILD_CONFIG" \
		$IN_ACTION
	return $?
}

build_scheme "$SCHEME"
STATUS=$?
if test "$STATUS" -ne 0; then
	exit $STATUS
fi

if test "$BUILD_PYTHON" -eq 1; then
	build_scheme "$PYTHON_SCHEME"
	STATUS=$?
fi

# Propagate xcodebuild's exit code so callers / CI can detect failures
# (the old script always exited 0, masking build errors).
exit $STATUS
