#!/bin/bash
# thin_with_plan.sh - apply a persisted thinning plan to an embedded Python, then
# verify by re-running the plan's traced workloads.
#
# Part of the Python-Embedding toolkit. This is the APPLY half of the plan-driven
# workflow:
#
#   1. PLAN  - analyze_python_deps.py --print plan  ->  a committable JSON plan
#   2. APPLY - thin_with_plan.sh --plan <plan.json> ->  performs the removal
#
# The plan lists module names (not absolute paths), so apply resolves them against the
# CURRENT distribution. That makes it idempotent and re-applicable: if a fresh Python
# was installed into the app (wiping a previously thinned dist), just re-run apply with
# the same committed plan to thin it again.
#
# SAFETY MODEL (same as thin_with_closure.sh)
#   - Back up the whole Python dir before touching it.
#   - Delete exactly what the plan names (modules resolved to paths + orphaned dylibs),
#     plus include/ and bytecode and an optional arch slice per the plan's options.
#   - Re-run every trace command recorded in the plan; if any raises
#     ImportError/Traceback, RESTORE the backup and exit non-zero. (Skip with --skip-verify
#     when the workload can't run here, e.g. a committed plan on a different machine.)
#
# USAGE
#   thin_with_plan.sh --python <PYDIR> --plan <plan.json> [--dry-run] [--skip-verify]
#                     [--verify-prepare CMD]
#
# This script knows nothing about how the consuming app is laid out. If a plan's workload
# is a set of entry-point scripts that must be re-run somewhere staged, supply
# --verify-prepare CMD: it runs after the deletions and prints extra analyzer arguments
# (one per line) on stdout - typically --python/--root/--sandbox-profile pointing at a
# copy of the app made post-thinning. Without it, verification runs in place.
#
# Run AFTER (re)installing the app's Python; a reinstall restores the full distribution.

set -uo pipefail

SCRIPT_DIR="$(CDPATH= cd -P -- "$(/usr/bin/dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ANALYZER="$SCRIPT_DIR/analyze_python_deps.py"
THINNER="$SCRIPT_DIR/thin_python_distribution.sh"
[ -f "$ANALYZER" ] || { echo "Error: analyze_python_deps.py not found next to this script"; exit 1; }
# Checked as well as ANALYZER: this script runs without `set -e`, so a missing helper
# used to print one line to stderr, skip the include/bytecode/arch work entirely, and
# still report "Success" over a distribution that was only half thinned.
[ -x "$THINNER" ] || { echo "Error: thin_python_distribution.sh not found next to this script"; exit 1; }

PYDIR=""
PLAN=""
VERIFY_PREPARE=""
DRYRUN=false
SKIP_VERIFY=false

while [ $# -gt 0 ]; do
    case "$1" in
        --python)      PYDIR="$2"; shift 2 ;;
        --plan)        PLAN="$2"; shift 2 ;;
        --verify-prepare) VERIFY_PREPARE="$2"; shift 2 ;;
        --dry-run)     DRYRUN=true; shift ;;
        --skip-verify) SKIP_VERIFY=true; shift ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

[ -n "$PYDIR" ] && [ -d "$PYDIR" ] || { echo "Error: --python <dir> required (the embedded Python distribution)"; exit 1; }

# Canonicalized before anything derives a path from it, for the same reason packages.dir
# is. The backup path is $PYDIR plus a suffix, and BSD `cp -R` implies -P: handed a
# SYMLINK it copies the link, so a symlinked --python made the "backup" a second name for
# the live distribution and the first deletion took both, with nothing to restore from.
# `//` is the root on Darwin and `pwd -P` preserves exactly two leading slashes, so it is
# folded by hand - canonicalization is the one thing that does not fold it.
PYDIR_REAL="$(CDPATH= cd -P -- "$PYDIR" 2>/dev/null && pwd -P)"
if [ -z "$PYDIR_REAL" ]; then
    # With the reason, the way the plan decoder above keeps its own. An unsearchable
    # ANCESTOR does not reach here: stat fails on it, so `[ -d ]` above rejects it
    # first. What reaches here is the target directory itself refusing to be entered,
    # and bash names it - which "could not resolve" on its own does not. (bash prefixes
    # this script and a line number to its message; the operator's path is at the end.)
    PYDIR_ERR="$(CDPATH= cd -P -- "$PYDIR" 2>&1 >/dev/null)"
    echo "Error: could not resolve --python directory: $PYDIR"
    [ -n "$PYDIR_ERR" ] && printf '%s\n' "$PYDIR_ERR"
    exit 1
fi
case "$PYDIR_REAL" in
    //) PYDIR_REAL="/" ;;
esac
if [ "$PYDIR_REAL" = "/" ]; then
    echo "Error: --python resolves to the root directory; refusing: $PYDIR"
    exit 1
fi
PYDIR="$PYDIR_REAL"
[ -n "$PLAN" ] && [ -f "$PLAN" ] || { echo "Error: --plan <plan.json> required (a thinning plan)"; exit 1; }
PYBIN="$PYDIR/bin/python3"
[ -x "$PYBIN" ] || { echo "Error: $PYBIN not found/executable"; exit 1; }

# Every interpreter this script starts reads the distribution's own stdlib, and
# CPython caches bytecode next to the source it imports - inside the very tree
# being measured, thinned and (with remove.bytecode) stripped of exactly that. A
# caller that already set a prefix keeps it; a developer running this by hand gets
# one rather than a dirtied distribution.
export PYTHONPYCACHEPREFIX="${PYTHONPYCACHEPREFIX:-${TMPDIR:-/tmp}/thin_with_plan_pyc}"

size_kb() { /usr/bin/du -sk "$1" 2>/dev/null | /usr/bin/cut -f1; }
fmt_mb() { /usr/bin/awk -v kb="${1:-0}" 'BEGIN { printf "%.1f MB", kb/1024 }'; }
calc_size() { fmt_mb "$(size_kb "$1")"; }

# Total size, in KB, of a newline-separated list of paths. Measured with du rather
# than added up from the plan, because the plan names modules and what a removal
# actually frees is what those modules occupy in THIS distribution. The entries are
# top-level module paths, none inside another, so nothing is counted twice; xargs
# chunks a long list and the sum survives the split.
paths_kb() { # <newline-separated paths>
    local total
    total=$(printf '%s\n' "$1" | /usr/bin/grep . | /usr/bin/tr '\n' '\0' \
        | /usr/bin/xargs -0 /usr/bin/du -sk 2>/dev/null \
        | /usr/bin/awk '{ sum += $1 } END { printf "%d", sum }')
    printf '%s' "${total:-0}"
}

# Read scalar/array fields out of the JSON plan with the embedded interpreter (json
# is always present pre-thinning, and never removed).
plan_get() { "$PYBIN" - "$PLAN" "$1" <<'PY'
import json, sys
plan = json.load(open(sys.argv[1]))
key = sys.argv[2]
def get(d, path):
    for k in path.split("."):
        d = d.get(k) if isinstance(d, dict) else None
    return d
v = get(plan, key)
if isinstance(v, list):
    print("\n".join(str(x) for x in v))
elif isinstance(v, bool):
    print("1" if v else "0")
elif v is not None:
    print(v)
PY
}

# plan_get prints nothing both for "the key is absent" and for "the interpreter
# could not run", and the summary below reads those the same way - it would report
# "nothing else comes off" for a plan asking for headers, bytecode and a slice. So
# the plan is read once, up front, where a failure can still be told apart.
# Exit 3 distinguishes "read it, and it is not a plan" - valid JSON that is a list
# or a string parses happily here and then dies inside the analyzer, several lines
# of traceback away from anything that names the file.
PLAN_ERR="$("$PYBIN" -c 'import json, sys
d = json.load(open(sys.argv[1]))
sys.exit(0 if isinstance(d, dict) else 3)' "$PLAN" 2>&1 >/dev/null)"
PLAN_RC=$?
if [ "$PLAN_RC" -eq 3 ]; then
    echo "Error: not a thinning plan (a JSON object was expected): $PLAN"
    exit 1
elif [ "$PLAN_RC" -ne 0 ]; then
    # With the decoder's own message: "Expecting ',' delimiter: line 41 column 5"
    # is the difference between finding the typo and re-reading the whole file.
    echo "Error: $PYBIN could not read the plan: $PLAN"
    [ -n "$PLAN_ERR" ] && printf '%s\n' "$PLAN_ERR"
    exit 1
fi

ARCH="$(plan_get arch)"
INCLUDE_HEADERS="$(plan_get remove.include_headers)"
BYTECODE="$(plan_get remove.bytecode)"

DYLIBS=()
while IFS= read -r d; do [ -n "$d" ] && DYLIBS+=("$d"); done < <(plan_get remove.dylibs)

# An entry is a path relative to the distribution and is deleted with rm, so one
# that could climb out of it - "../../..", or an absolute path - is refused rather
# than resolved. A plan is a committed, hand-editable file.
for d in ${DYLIBS[@]+"${DYLIBS[@]}"}; do
    case "$d" in
        /*|..|../*|*/..|*/../*)
            echo "Error: remove.dylibs entry leaves the distribution: $d"
            exit 1
            ;;
    esac
done

# Resolve the plan's module names to deletable paths in THIS distribution.
#
# Status checked, both here and below. An analyzer that dies (a plan that is valid
# JSON but not a plan object gets it as far as an AttributeError) returns an empty
# capture, and an unchecked empty capture is indistinguishable from "this plan
# removes nothing": the dry run then reports a tidy "0 modules, 61.3 MB -> 61.3 MB"
# under a traceback, and an apply with --skip-verify deletes nothing, throws the
# backup away and prints Success.
REMOVABLE_PATHS="$("$PYBIN" "$ANALYZER" --python "$PYDIR" --plan "$PLAN" --print removable-paths)"
ANALYZER_RC=$?
if [ "$ANALYZER_RC" -ne 0 ]; then
    echo "Error: the analyzer could not resolve this plan's removals (exit $ANALYZER_RC): $PLAN"
    exit 1
fi
REMOVE_COUNT=$(printf '%s\n' "$REMOVABLE_PATHS" | grep -c .)

# Packages removals come ONLY from packages.remove, which the audit leaves empty. So
# this is normally nothing at all, and is non-empty only because a human reviewed an
# orphan candidate and moved it in. An empty answer here is the normal case and exits
# 0; a non-zero status means something the caller needs to hear, which is why its
# stderr is no longer discarded - "packages.remove but no --packages dir" was being
# thrown away along with it.
PKG_PATHS="$("$PYBIN" "$ANALYZER" --python "$PYDIR" --plan "$PLAN" --print packages-remove-paths)"
ANALYZER_RC=$?
if [ "$ANALYZER_RC" -ne 0 ]; then
    echo "Error: the analyzer could not resolve this plan's Packages removals (exit $ANALYZER_RC): $PLAN"
    exit 1
fi
PKG_COUNT=$(printf '%s\n' "$PKG_PATHS" | grep -c .)
PKGDIR="$("$PYBIN" -c 'import json,sys;p=json.load(open(sys.argv[1])).get("packages") or {};print(p.get("dir") or "")' "$PLAN")"
PKGDIR_RC=$?
if [ "$PKGDIR_RC" -ne 0 ]; then
    echo "Error: could not read packages.dir from the plan (exit $PKGDIR_RC): $PLAN"
    exit 1
fi

# Shape first, on the string the PLAN carries - BEFORE any resolution. Resolving
# first would promote a relative "Packages" to an absolute path against whatever
# directory the apply happens to run in, and this refusal would never fire again.
#
# Only when something is actually going to be removed from it. Then it is backed up
# with cp -Rp, emptied of what packages.remove names, and removed whole by restore(),
# so a relative or climbing path would aim all three somewhere nobody asked for. When
# packages.remove is empty - the normal state, since the audit reports rather than
# decides - the directory is only ever echoed, and a relative --packages argument is
# a perfectly ordinary way to have run the analyzer.
if [ "$PKG_COUNT" -gt 0 ]; then
    case "$PKGDIR" in
        ..|../*|*/..|*/../*)
            echo "Error: packages.dir must not climb out of itself: $PKGDIR"
            exit 1
            ;;
    esac
    case "$PKGDIR" in
        /*) ;;
        *)  echo "Error: packages.dir must be an absolute path to remove from: $PKGDIR"
            exit 1
            ;;
    esac
fi

# Then canonicalized, because "$PKGDIR.thinbak" and restore()'s rm are only as sane
# as this string: a trailing slash puts the backup INSIDE the directory it is backing
# up, where restore()'s own rm destroys it before the move.
if [ -n "$PKGDIR" ]; then
    PKGDIR_REAL="$(CDPATH= cd -P -- "$PKGDIR" 2>/dev/null && pwd -P)"
    # Only when it resolved. A packages.dir that does not exist is not an error here
    # - nothing is removed from it - and the summary still names what the plan said.
    [ -n "$PKGDIR_REAL" ] && PKGDIR="$PKGDIR_REAL"
    # POSIX lets an implementation give exactly two leading slashes their own meaning,
    # and Darwin does: "cd -P // && pwd -P" prints "//", not "/". It is the one root
    # spelling canonicalization does not fold, so fold it here.
    [ "$PKGDIR" = "//" ] && PKGDIR="/"

    # Not gated on PKG_COUNT: the root is never a packages directory whatever the plan
    # asks, and every path derived from it - the backup at "${PKGDIR%/}.thinbak", the
    # recovery advice the exit trap prints - is nonsense that names "/".
    if [ "$PKGDIR" = "/" ]; then
        echo "Error: packages.dir must not be the filesystem root"
        exit 1
    fi
fi

echo "Plan   : $PLAN"
echo "Python : $("$PYBIN" --version 2>&1)  ($PYDIR)"
echo "Remove : $REMOVE_COUNT modules"
[ "$PKG_COUNT" -gt 0 ] && echo "         + $PKG_COUNT entry/entries from Packages (explicitly listed in packages.remove)"
[ ${#DYLIBS[@]} -gt 0 ] && echo "         + ${#DYLIBS[@]} orphaned dylib(s): ${DYLIBS[*]}"
[ "$INCLUDE_HEADERS" = "1" ] && echo "         + include/ headers"
[ "$BYTECODE" = "1" ] && echo "         + bytecode (.pyc)"
[ -n "$ARCH" ] && echo "         + slice to single arch -> $ARCH"

if $DRYRUN; then
    echo
    echo "=== DRY RUN - module paths that would be removed (top 40) ==="
    printf '%s\n' "$REMOVABLE_PATHS" | sed "s#^$PYDIR/##" | sort | head -40
    [ "$REMOVE_COUNT" -gt 40 ] && echo "  ... ($((REMOVE_COUNT - 40)) more)"

    # Every number below is measured now, on the untouched distribution: one size
    # line on its own said neither which tree it described nor whether thinning had
    # happened, and "current" read as "what you are left with" to anyone who had
    # just asked what a removal would cost.
    CUR_KB="$(size_kb "$PYDIR")"
    REMOVE_KB="$(paths_kb "$REMOVABLE_PATHS")"

    # The dylibs live inside $PYDIR and the apply deletes them unconditionally, so
    # they are part of what the estimate has to account for - not one more unmeasured
    # extra. Only the ones that are actually there: a plan can name a dylib a later
    # Python build no longer ships.
    DYLIB_PATHS=""
    DYLIB_PRESENT=0
    for d in ${DYLIBS[@]+"${DYLIBS[@]}"}; do
        if [ -e "$PYDIR/$d" ]; then
            DYLIB_PATHS="${DYLIB_PATHS}${PYDIR}/${d}
"
            DYLIB_PRESENT=$(( DYLIB_PRESENT + 1 ))
        fi
    done
    DYLIB_KB="$(paths_kb "$DYLIB_PATHS")"

    LEFT_KB=$(( CUR_KB - REMOVE_KB - DYLIB_KB ))
    [ "$LEFT_KB" -lt 0 ] && LEFT_KB=0

    echo
    echo "=== DRY RUN SUMMARY - nothing was removed; the distribution is untouched ==="
    echo "  Embedded Python now : $(fmt_mb "$CUR_KB")"
    echo "                        $PYDIR"
    echo "  Modules to remove   : $REMOVE_COUNT, occupying $(fmt_mb "$REMOVE_KB")"
    if [ ${#DYLIBS[@]} -gt 0 ]; then
        # Counted as they are on disk, not as the plan names them: a plan written
        # against an older Python can name a dylib this build no longer ships, and
        # a size that covered two files under a heading that said three would be
        # the one number here nobody could reconcile.
        if [ "$DYLIB_PRESENT" -eq ${#DYLIBS[@]} ]; then
            echo "  Orphaned dylibs     : $DYLIB_PRESENT, occupying $(fmt_mb "$DYLIB_KB")"
        else
            echo "  Orphaned dylibs     : $DYLIB_PRESENT of ${#DYLIBS[@]} still present, occupying $(fmt_mb "$DYLIB_KB")"
        fi
    fi
    if [ "$PKG_COUNT" -gt 0 ]; then
        # A separate tree from the interpreter, so its size is reported separately
        # rather than folded into a total that would then describe neither.
        echo "  Packages to remove  : $PKG_COUNT entry/entries, occupying $(fmt_mb "$(paths_kb "$PKG_PATHS")")"
        echo "                        under $PKGDIR"
    fi
    # Same shape as the line a real run ends on, so the two can be compared.
    echo "  Estimated result    : $(fmt_mb "$CUR_KB") -> about $(fmt_mb "$LEFT_KB")"

    # Everything above is measured. What is left runs after the deletions and takes
    # more off, by an amount nothing can know without doing it - so it is named
    # rather than guessed at, and the estimate stands as an upper bound.
    EXTRAS=""
    [ "$INCLUDE_HEADERS" = "1" ] && EXTRAS="${EXTRAS}, include/ headers"
    [ "$BYTECODE" = "1" ] && EXTRAS="${EXTRAS}, bytecode (.pyc)"
    [ -n "$ARCH" ] && EXTRAS="${EXTRAS}, the non-$ARCH half of every universal binary"
    if [ -n "$EXTRAS" ]; then
        echo "                        smaller again once these go: ${EXTRAS#, }"
    fi
    echo
    echo "Run the same command without --dry-run to apply this plan."
    exit 0
fi

BACKUP="${PYDIR%/}.thinbak"
PKGDIR_BAK="${PKGDIR%/}.thinbak"

# An existing backup means a previous run died between "delete" and "verify". The live
# dist is then already thinned and the backup is the ONLY pristine copy - overwriting it
# here would back up the damaged tree and destroy the good one, silently, while
# reporting success. Refuse instead, and say how to recover.
if [ -e "$BACKUP" ]; then
    echo "Error: a backup already exists at $BACKUP"
    echo "A previous apply did not finish, so the live distribution may be half-thinned"
    echo "and this backup is the only pristine copy. Restore it first:"
    echo "  rm -rf \"$PYDIR\" && mv \"$BACKUP\" \"$PYDIR\""
    [ -n "$PKGDIR" ] && [ -e "$PKGDIR_BAK" ] && \
        echo "  rm -rf \"$PKGDIR\" && mv \"$PKGDIR_BAK\" \"$PKGDIR\""
    exit 1
fi

# Tested on its own, and unconditionally: Packages is backed up only when the plan names
# a package to remove, so a leftover from an earlier run would sit there unmentioned by
# every later apply whose plan happens to remove none - and be silently overwritten by
# the first one that does.
if [ -n "$PKGDIR" ] && [ -e "$PKGDIR_BAK" ]; then
    echo "Error: a Packages backup already exists at $PKGDIR_BAK"
    echo "A previous apply did not finish, so $PKGDIR may be half-thinned and this"
    echo "backup is the only pristine copy. Restore it first:"
    echo "  rm -rf \"$PKGDIR\" && mv \"$PKGDIR_BAK\" \"$PKGDIR\""
    exit 1
fi

# Installed BEFORE anything is deleted. Previously the signal traps went up only just
# before verification, so Ctrl-C during the delete loop left a half-thinned dist and no
# word about the backup that could undo it.
restore() {
    /bin/rm -rf "$PYDIR"
    # Checked on the directory rather than on rm's status, and checked at all because
    # mv cannot report this one: moving the backup ONTO a directory that survived the
    # rm puts it INSIDE that directory and still exits 0, so the pristine copy ends up
    # nested in the half-thinned tree while the caller is told "Restored."
    if [ -e "$PYDIR" ]; then
        echo "FATAL: could not remove $PYDIR, so the backup cannot be moved back."
        echo "       The pristine copy is intact at:"
        echo "         $BACKUP"
        echo "       Remove $PYDIR by hand, then: mv \"$BACKUP\" \"$PYDIR\""
        return 1
    fi
    /bin/mv "$BACKUP" "$PYDIR"
    local mv_rc=$?
    if [ "$mv_rc" -ne 0 ]; then
        # The one failure nothing else can recover from: the live tree is deleted and
        # the pristine copy did not move back. Said loudly, and INTERRUPTED is left
        # true so the EXIT trap still names the backup rather than falling silent.
        # (For the Packages failure below, $BACKUP has already moved back, so the
        # trap's own test is false there - that path relies on the message and on
        # the trap's separate PKG_BACKUP branch.)
        echo "FATAL: could not restore $PYDIR from $BACKUP (mv exit $mv_rc)."
        echo "       The distribution is NOT in place. Move it back by hand:"
        echo "         mv \"$BACKUP\" \"$PYDIR\""
        return 1
    fi
    if [ -n "${PKG_BACKUP:-}" ] && [ -d "$PKG_BACKUP" ]; then
        /bin/rm -rf "$PKGDIR"
        # Same nesting hazard as above, same reason it has to be tested here.
        if [ -e "$PKGDIR" ]; then
            echo "FATAL: could not remove $PKGDIR, so its backup cannot be moved back."
            echo "       The pristine copy is intact at:"
            echo "         $PKG_BACKUP"
            echo "       Remove $PKGDIR by hand, then: mv \"$PKG_BACKUP\" \"$PKGDIR\""
            return 1
        fi
        /bin/mv "$PKG_BACKUP" "$PKGDIR"
        local pkg_rc=$?
        if [ "$pkg_rc" -ne 0 ]; then
            echo "FATAL: could not restore $PKGDIR from $PKG_BACKUP (mv exit $pkg_rc)."
            echo "         mv \"$PKG_BACKUP\" \"$PKGDIR\""
            return 1
        fi
    fi
    INTERRUPTED=false
    return 0
}

INTERRUPTED=true
BACKUP_OK=false
PKG_BACKUP_CAND=""
# Whether anything has been taken out yet. The trap cannot tell "stopped before the
# first deletion" from "stopped halfway through" without it, and it used to tell every
# operator on both paths that the distribution "may be partly thinned".
THINNING_STARTED=false
on_exit() {
    [ -n "${VWORK:-}" ] && /bin/rm -rf "$VWORK"
    # A backup whose copy never finished - disk full, an unreadable file, or a Ctrl-C
    # that the INT trap turns into an exit before cp's own status is ever tested. It
    # cannot be reached with anything deleted, because BACKUP_OK goes true the instant
    # the copy returns and the first removal is after that, so the fragment is junk.
    # Leaving it would make the NEXT run refuse and then name it as the only pristine
    # copy, of a tree it never actually held.
    if ! $BACKUP_OK && [ -e "$BACKUP" ]; then
        /bin/rm -rf "$BACKUP"
    fi
    # Same for the Packages fragment. PKG_BACKUP is set only after its copy succeeds,
    # so a candidate path that exists while PKG_BACKUP is empty is a partial copy - and
    # it can only be OUR partial copy, since a pre-existing one is refused up front.
    if [ -z "${PKG_BACKUP:-}" ] && [ -n "${PKG_BACKUP_CAND:-}" ] && [ -e "$PKG_BACKUP_CAND" ]; then
        /bin/rm -rf "$PKG_BACKUP_CAND"
    fi
    if $INTERRUPTED && $BACKUP_OK && [ -d "$BACKUP" ]; then
        echo
        if $THINNING_STARTED; then
            echo "Interrupted with a backup still on disk. The distribution may be partly"
            echo "thinned. Restore it with:"
            echo "  rm -rf \"$PYDIR\" && mv \"$BACKUP\" \"$PYDIR\""
        else
            echo "Stopped before the first deletion, so the distribution is untouched and"
            echo "the backup is a faithful copy of it. The next run refuses while the backup"
            echo "is there, so clear it - either of these is safe:"
            echo "  rm -rf \"$BACKUP\""
            echo "  rm -rf \"$PYDIR\" && mv \"$BACKUP\" \"$PYDIR\""
        fi
    fi
    # Named separately, and tested on its own: Packages is a different tree with a
    # different backup, and an interrupt - or a restore that got the interpreter back
    # but not this - used to leave it on disk with nothing in the transcript saying so.
    if [ -n "${PKG_BACKUP:-}" ] && [ -d "$PKG_BACKUP" ]; then
        echo
        # Read together with the message above, so it answers the same question: this
        # backup is made before the first deletion too, so "untouched" is true of both
        # trees or of neither.
        if $THINNING_STARTED; then
            echo "The Packages backup is still on disk. Restore it with:"
            echo "  rm -rf \"$PKGDIR\" && mv \"$PKG_BACKUP\" \"$PKGDIR\""
        else
            echo "Nothing was removed from $PKGDIR either, and its backup is still on"
            echo "disk. Either of these is safe:"
            echo "  rm -rf \"$PKG_BACKUP\""
            echo "  rm -rf \"$PKGDIR\" && mv \"$PKG_BACKUP\" \"$PKGDIR\""
        fi
    fi
}
trap on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

echo
echo "Backing up -> $BACKUP"
/bin/cp -Rp "$PYDIR" "$BACKUP"
if [ $? -ne 0 ]; then
    # The fragment cp leaves behind is cleared by the exit trap, which also covers the
    # Ctrl-C that never reaches this test.
    echo "Backup failed; aborting."
    exit 1
fi
# Only now. cp -R creates the destination directory before it starts filling it, so a
# copy that died partway leaves something that -d cannot tell from a good backup - and
# the exit trap would then advise deleting an untouched distribution and moving the
# fragment into its place.
BACKUP_OK=true
BEFORE="$(calc_size "$PYDIR")"

# Packages is a separate tree from the interpreter, so it needs its own backup before
# anything is taken out of it - restoring $PYDIR would not put it back.
PKG_BACKUP=""
if [ "$PKG_COUNT" -gt 0 ] && [ -n "$PKGDIR" ] && [ -d "$PKGDIR" ]; then
    # A candidate path, not yet a backup: PKG_BACKUP is what the trap and restore()
    # act on, so it is set after the copy succeeds, not before it starts.
    # A pre-existing backup here is refused up front, before the exit trap is armed, so
    # by the time this runs the path is free and anything found at it later is ours.
    PKG_BACKUP_CAND="$PKGDIR_BAK"
    /bin/cp -Rp "$PKGDIR" "$PKG_BACKUP_CAND"
    if [ $? -ne 0 ]; then
        echo "Packages backup failed; aborting."
        exit 1
    fi
    PKG_BACKUP="$PKG_BACKUP_CAND"
    echo "Backing up -> $PKG_BACKUP"
fi

# Set before the first rm, not after it: an interrupt inside the loop must read as
# "partly thinned", and the loop is the first thing that modifies the distribution.
THINNING_STARTED=true
echo "Deleting $REMOVE_COUNT out-of-closure modules..."
printf '%s\n' "$REMOVABLE_PATHS" | while IFS= read -r pth; do
    [ -n "$pth" ] && /bin/rm -rf "$pth"
done
for d in ${DYLIBS[@]+"${DYLIBS[@]}"}; do
    if [ -e "$PYDIR/$d" ]; then echo "  removing orphaned $d"; /bin/rm -f "$PYDIR/$d"; fi
done

if [ "$PKG_COUNT" -gt 0 ]; then
    echo "Deleting $PKG_COUNT reviewed entry/entries from Packages..."
    printf '%s\n' "$PKG_PATHS" | while IFS= read -r pth; do
        [ -n "$pth" ] && { echo "  removing $(/usr/bin/basename "$pth")"; /bin/rm -rf "$pth"; }
    done
fi

if [ "$INCLUDE_HEADERS" = "1" ] || [ "$BYTECODE" = "1" ]; then
    COMPONENTS=()
    [ "$INCLUDE_HEADERS" = "1" ] && COMPONENTS+=("include")
    [ "$BYTECODE" = "1" ] && COMPONENTS+=("pyc")
    echo "Removing ${COMPONENTS[*]}..."
    # Captured rather than discarded: the thinner reports per-file failures and its
    # own summary on STDOUT, so >/dev/null left "Error: ... failed; restoring." as
    # the only thing an operator saw after a run of several minutes.
    THINNER_OUT="$("$THINNER" "$PYDIR" ${COMPONENTS[@]+"${COMPONENTS[@]}"} 2>&1)"
    THINNER_RC=$?
    if [ "$THINNER_RC" -ne 0 ]; then
        printf '%s\n' "$THINNER_OUT"
        echo "Error: removing ${COMPONENTS[*]} failed; restoring."
        restore
        exit 1
    fi
fi
if [ -n "$ARCH" ]; then
    echo "Slicing universal Mach-O -> $ARCH..."
    # Unchecked, this silently left a universal binary behind while the plan recorded a
    # single-arch app - a claim nobody could see was false.
    THINNER_OUT="$("$THINNER" --arch "$ARCH" "$PYDIR" 2>&1)"
    THINNER_RC=$?
    if [ "$THINNER_RC" -ne 0 ]; then
        printf '%s\n' "$THINNER_OUT"
        echo "Error: arch slicing failed; restoring."
        restore
        exit 1
    fi
fi

# --- VERIFY: re-run every traced workload; any import failure -> restore + fail ---
# Verification runs in analyze_python_deps.py (Python subprocess timeouts, exit-code
# aware) - NOT a `timeout` binary, which macOS lacks. It must be driven by a FULL
# interpreter: the just-thinned one may have lost json/argparse and could not run the
# analyzer. The backup is that full interpreter (same version); the traces themselves
# still run under the thinned $PYBIN.
VWORK=""

if $SKIP_VERIFY; then
    echo
    echo "Skipping verification (--skip-verify)."
else
    echo
    echo "Verifying: re-running traced workload(s) against the thinned interpreter..."
    VERIFY_PY="$BACKUP/bin/python3"
    [ -x "$VERIFY_PY" ] || VERIFY_PY="/usr/bin/python3"
    VARGS=(--plan "$PLAN" --verify)
    VERIFY_PYDIR="$PYDIR"

    # A plan whose workload is a set of ENTRY POINT SCRIPTS has to re-run them, and only
    # the caller knows how to stage that safely - which directory is the app root, where
    # its interpreter and dependencies sit inside it, what a sandbox profile for it needs
    # to allow. So the caller supplies a hook instead of this script guessing a layout.
    #
    # --verify-prepare CMD runs CMD after the deletions and reads extra analyzer
    # arguments from its stdout, one per line, e.g.
    #     --python /tmp/x/App/py
    #     --root /tmp/x/App
    #     --sandbox-profile /tmp/x/p.sb
    # Anything CMD stages (typically a copy of the app, made AFTER thinning so it shares
    # the thinned interpreter) is its own to clean up.
    #
    # Without the hook, verification runs in place against $PYDIR. That is the whole
    # story for an imports-only plan: its workload is a generated import probe, which
    # has no app layout to reproduce.
    if [ -n "$VERIFY_PREPARE" ]; then
        # eval, not bare expansion. The hook is a COMMAND LINE, so its producer quotes
        # arguments that contain spaces - and an unquoted $VERIFY_PREPARE word-splits
        # without quote removal, leaving the quotes as literal characters and splitting
        # the path anyway. Measured: an app path with a space made the hook exit 2 and
        # the apply abort-and-restore on every run, so the app could never be thinned.
        # Stderr is NOT discarded: the hook's own diagnostic is the only clue to why.
        PREP_OUT="$(eval "$VERIFY_PREPARE")"
        if [ $? -ne 0 ]; then
            echo "Error: --verify-prepare command failed; cannot verify."; restore; exit 1
        fi
        PREP_ARGS=()
        while IFS= read -r line; do
            [ -n "$line" ] && PREP_ARGS+=("$line")
        done <<< "$PREP_OUT"
        if [ ${#PREP_ARGS[@]} -gt 0 ]; then
            VARGS+=("${PREP_ARGS[@]}")
            # The hook may override --python; let its value win by appending ours first.
            case " ${PREP_ARGS[*]} " in
                *" --python "*) VERIFY_PYDIR="" ;;
            esac
            echo "  (verification staged by --verify-prepare)"
        fi
    fi
    [ -n "$VERIFY_PYDIR" ] && VARGS=(--python "$VERIFY_PYDIR" "${VARGS[@]}")
    "$VERIFY_PY" "$ANALYZER" "${VARGS[@]}"
    if [ $? -ne 0 ]; then
        echo
        echo "Verification FAILED - the plan removed a module a traced path needs."
        echo "Restoring backup..."
        restore
        restore_rc=$?
        # restore() says FATAL and returns non-zero when the distribution did not come
        # back. Announcing "Restored." over that would be the worst line in the file.
        if [ "$restore_rc" -eq 0 ]; then
            echo "Restored. Edit the plan's remove.modules (keep the missing one) or re-plan, then retry."
        fi
        exit 1
    fi
fi

# Verified (or deliberately skipped): the backups have done their job and the EXIT
# handler must stop advertising a restore that is no longer needed or possible.
INTERRUPTED=false
/bin/rm -rf "$BACKUP"
[ -n "$PKG_BACKUP" ] && /bin/rm -rf "$PKG_BACKUP"
AFTER="$(calc_size "$PYDIR")"
echo
echo "Success. Embedded Python: $BEFORE -> $AFTER"
