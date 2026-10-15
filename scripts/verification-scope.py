#!/usr/bin/env python3
"""Classify an exact Git diff for proportional deterministic verification.

Only regular Markdown documentation in reviewed locations qualifies. Every
unknown path, unusual Git mode, malformed record, or empty diff selects full.
"""

import os
from pathlib import Path
import re
import subprocess
import sys


DOCUMENTATION_FILES = {
    "README.md",
    "docs/AI_KEYBOARD_RESEARCH.md",
    "docs/AI_KEYBOARD_TODO.md",
    "docs/AI_OPERATION_DIAGNOSTICS.md",
    "docs/CI_LOG_INDEX.md",
    "docs/KEYBOARD_LAYOUT_PACKAGE_MILESTONE_PLAN.md",
    "docs/KEYBOARD_PRODUCT_COMPLETION_PLAN.md",
    "docs/M2_PROGRESS.md",
    "docs/MACOS_MILESTONE_2_PLAN.md",
    "docs/PR_PROOF_AUDIT_2026-08-14.md",
    "docs/PROMPT_EVALS.md",
    "docs/TDD_BACKEND_PLAN.md",
    "docs/TDD_STATUS.md",
    "docs/UNIVERSAL_AI_CONNECTOR.md",
    "docs/WORK_QUEUE.md",
}


def git(*args):
    return subprocess.check_output(("git", *args), stderr=subprocess.DEVNULL)


def documentation_path(path):
    if "\n" in path or "\r" in path:
        return False
    if path in DOCUMENTATION_FILES:
        return True
    parts = Path(path).parts
    return len(parts) >= 3 and parts[:2] == ("docs", "plans") and path.endswith(".md")


def classify(raw):
    records = raw.split(b"\0")
    if not records or records.pop() != b"" or not records or len(records) % 2:
        return "full"
    for index in range(0, len(records), 2):
        try:
            fields = records[index].decode("ascii").split()
            if len(fields) != 5 or not fields[0].startswith(":"):
                return "full"
            before, after, old_oid, new_oid, status = fields
            path = os.fsdecode(records[index + 1])
            if not documentation_path(path):
                return "full"
            if status == "A":
                valid = before == ":000000" and after == "100644"
            elif status == "D":
                valid = before == ":100644" and after == "000000"
            elif status == "M":
                valid = before == ":100644" and after == "100644"
            else:
                return "full"
            if (not valid or re.fullmatch(r"[0-9a-f]{40}", old_oid) is None
                    or re.fullmatch(r"[0-9a-f]{40}", new_oid) is None):
                return "full"
        except (UnicodeDecodeError, ValueError):
            return "full"
    return "docs"


def main():
    if len(sys.argv) == 2 and sys.argv[1] == "--staged":
        raw = git("diff", "--cached", "--raw", "--no-abbrev", "--no-renames", "-z", "HEAD", "--")
    elif len(sys.argv) == 4 and sys.argv[1] == "--range":
        base, head = sys.argv[2:]
        for revision in (base, head):
            git("cat-file", "-e", f"{revision}^{{commit}}")
        ancestor = git("merge-base", base, head).decode("ascii").strip()
        raw = git("diff", "--raw", "--no-abbrev", "--no-renames", "-z", ancestor, head, "--")
    else:
        raise SystemExit("Usage: verification-scope.py --staged | --range <base> <head>")
    print(classify(raw))


if __name__ == "__main__":
    try:
        main()
    except (OSError, subprocess.CalledProcessError, UnicodeDecodeError) as error:
        raise SystemExit(f"Verification scope could not inspect the exact Git diff: {error}")
