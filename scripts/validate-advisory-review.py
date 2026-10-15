#!/usr/bin/env python3
"""Validate a private advisory record, never review evidence or merge readiness."""

import json
import os
from pathlib import Path
import re
import stat
import sys

STATUSES = {"pending", "completed", "failed", "unavailable", "not-applicable"}
ROUTES = {
    "code-review": {"app-code-review", "github-code-review", "local-review"},
    "security-review": {"local-security", "github-security-review", "security-cloud", "none"},
}


def require(condition):
    if not condition:
        raise ValueError("Invalid advisory record")


def text(value):
    return isinstance(value, str) and bool(value.strip())


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result)
        result[key] = value
    return result


def validate(record, base, head):
    for revision in (base, head):
        require(isinstance(revision, str) and re.fullmatch(r"[0-9a-f]{40}", revision))
    require(isinstance(record, dict) and set(record) == {"schema_version", "base", "head", "reviews"})
    require(type(record["schema_version"]) is int and record["schema_version"] == 1)
    require(record["base"] == base and record["head"] == head)
    reviews = record["reviews"]
    require(isinstance(reviews, list) and len(reviews) == 2)
    seen = set()
    counts = []
    for review in reviews:
        require(isinstance(review, dict) and set(review) == {
            "kind", "route", "status", "scope", "reason", "report_reference", "inspected", "coverage", "findings"
        })
        kind, route, status = review["kind"], review["route"], review["status"]
        require(isinstance(kind, str) and kind in ROUTES and kind not in seen)
        seen.add(kind)
        require(isinstance(route, str) and route in ROUTES[kind])
        require(isinstance(status, str) and status in STATUSES)
        require(text(review["scope"]) and text(review["reason"]))
        require(type(review["inspected"]) is bool and isinstance(review["findings"], list))
        if status == "not-applicable":
            require(kind == "security-review" and route == "none")
        if route == "none":
            require(status == "not-applicable")
        if status == "completed":
            require(review["inspected"] and text(review["report_reference"]) and text(review["coverage"]))
        else:
            require(not review["inspected"] and not review["findings"])
            require(review["report_reference"] is None and review["coverage"] is None)
        identifiers = set()
        for finding in review["findings"]:
            require(isinstance(finding, dict) and set(finding) == {
                "id", "disposition", "rationale", "evidence", "requirement_id"
            })
            require(all(text(value) for value in finding.values()))
            require(finding["id"] not in identifiers)
            identifiers.add(finding["id"])
            require(finding["disposition"] in {"open", "fixed", "rejected"})
        counts.append((kind, status, sum(f["disposition"] == "open" for f in review["findings"])))
    return counts


def main():
    require(len(sys.argv) == 4)
    path = Path(sys.argv[1])
    # Never print private contents or parse errors. Referenced reports are not opened.
    info = path.lstat()
    require(stat.S_ISREG(info.st_mode) and info.st_uid == os.getuid())
    require(stat.S_IMODE(info.st_mode) == 0o600)
    record = json.loads(path.read_text(), object_pairs_hook=unique_object)
    counts = validate(record, sys.argv[2], sys.argv[3])
    for kind, status, unresolved in counts:
        print(f"{kind}: {status}; open findings: {unresolved}")
    print("Advisory record structure valid; not evidence verification or merge authorization.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, TypeError, KeyError):
        sys.exit("Advisory record rejected: check schema, exact revisions, status, and private file permissions.")
