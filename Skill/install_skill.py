#!/usr/bin/env python3
"""
OMC Skill Installer
===================
Deploy a built skill flavor to a target location.

The `claude` flavor installs as a Claude Code skill directory (SKILL.md + docs).
The `capable` and `lite` flavors install as a single concatenated SKILL.md file,
intended to be pasted into a system prompt or attached as a document.

If the requested flavor has not been built yet, build_skill.py is invoked automatically.

Usage:
    # Install the claude flavor into the current project's .claude/skills/omc/
    python3 Skill/install_skill.py claude

    # Install the claude flavor at the user level (~/.claude/skills/omc/)
    python3 Skill/install_skill.py claude --user

    # Install the claude flavor into a specific Claude Code project
    python3 Skill/install_skill.py claude --dest /path/to/project

    # Write the capable / lite flavor SKILL.md to a file
    python3 Skill/install_skill.py capable --out omc-capable.md
    python3 Skill/install_skill.py lite    --out omc-lite.md

    # Or print to stdout (for piping)
    python3 Skill/install_skill.py capable --print
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DIST_DIR = REPO_ROOT / "Skill" / "dist"
BUILD_SCRIPT = REPO_ROOT / "Skill" / "build_skill.py"
SKILL_NAME = "omc"


def ensure_built(flavor: str) -> Path:
    src = DIST_DIR / flavor
    if not (src / "SKILL.md").exists():
        print(f"[info] {flavor} flavor not built yet; running build_skill.py…")
        subprocess.run(
            [sys.executable, str(BUILD_SCRIPT), "--flavor", flavor],
            check=True,
        )
    if not (src / "SKILL.md").exists():
        print(f"error: build did not produce {src / 'SKILL.md'}", file=sys.stderr)
        sys.exit(1)
    return src


def install_claude(src: Path, dest_root: Path, force: bool) -> None:
    """Install the claude flavor as a Claude Code skill directory."""
    target = dest_root / ".claude" / "skills" / SKILL_NAME
    if target.exists():
        if not force:
            print(f"error: {target} already exists. Re-run with --force to overwrite.",
                  file=sys.stderr)
            sys.exit(1)
        shutil.rmtree(target)
    target.parent.mkdir(parents=True, exist_ok=True)

    shutil.copytree(src, target)
    print(f"installed → {target}")
    print()
    print("Next steps:")
    print(f"  • Restart Claude Code (or run /skills reload) so it picks up {SKILL_NAME}.")
    print(f"  • Reference docs live in {target}/docs/.")


def install_single_file(src: Path, out: Path | None, do_print: bool) -> None:
    """Install capable/lite flavor as a single SKILL.md file."""
    skill_md = (src / "SKILL.md").read_text(encoding="utf-8")

    if do_print:
        sys.stdout.write(skill_md)
        return

    if out is None:
        print("error: specify --out FILE or --print", file=sys.stderr)
        sys.exit(2)

    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(skill_md, encoding="utf-8")
    print(f"wrote → {out}")
    print()
    print("Usage:")
    print("  • Paste the file's contents into the target model's system prompt, OR")
    print("  • Attach the file as a document/context input.")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Install a built OMC skill flavor to a target location.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "flavor",
        choices=["claude", "capable", "lite"],
        help="Which flavor to install",
    )
    parser.add_argument(
        "--dest",
        type=Path,
        help="Destination root for claude flavor (defaults to current directory). "
             "The skill is written to <dest>/.claude/skills/omc/.",
    )
    parser.add_argument(
        "--user",
        action="store_true",
        help="Install claude flavor at user level (~/.claude/skills/omc/).",
    )
    parser.add_argument(
        "--out",
        type=Path,
        help="Output file path for capable/lite flavor.",
    )
    parser.add_argument(
        "--print",
        dest="do_print",
        action="store_true",
        help="Print capable/lite flavor SKILL.md to stdout instead of writing to a file.",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Overwrite an existing claude skill directory.",
    )
    args = parser.parse_args()

    src = ensure_built(args.flavor)

    if args.flavor == "claude":
        if args.user and args.dest:
            print("error: --user and --dest are mutually exclusive", file=sys.stderr)
            sys.exit(2)
        if args.user:
            dest_root = Path.home()
        elif args.dest:
            dest_root = args.dest.expanduser().resolve()
        else:
            dest_root = Path.cwd()
        install_claude(src, dest_root, args.force)
    else:
        install_single_file(src, args.out, args.do_print)


if __name__ == "__main__":
    main()
