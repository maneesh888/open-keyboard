#!/usr/bin/env python3
"""Validate a diff-bound applicability decision; never execute assessment content.

The independent PR reviewer decides whether the rationale is correct. This validator
checks freshness, complete scope, and linkage to a requirement the reviewer must assess.
"""
import json
import re
import subprocess
import sys

PATH = ".github/verification-assessment.json"
TARGETS = {"none": 0, "gateway": 1, "gateway-differential": 2}


def git(root, *args):
    return subprocess.check_output(["git", "-C", root, *args], stderr=subprocess.DEVNULL)


def entry(root, revision, path):
    raw = git(root, "ls-tree", "-z", revision, "--", path)
    if not raw:
        return None
    records = raw.rstrip(b"\0").split(b"\0")
    if len(records) != 1:
        raise ValueError("Assessment path must identify exactly one file")
    metadata, name = records[0].split(b"\t", 1)
    mode, kind, oid = metadata.decode().split()
    if name.decode() != path or kind not in {"blob", "commit"}:
        raise ValueError("Assessment path is not a file or gitlink")
    return {"mode": mode, "oid": oid}


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate assessment field")
        result[key] = value
    return result


def resolve(root, base, head, default, body_file=None):
    if default not in TARGETS:
        raise ValueError("Unknown default live impact")
    base = git(root, "merge-base", base, head).decode().strip()
    head = git(root, "rev-parse", "--verify", head + "^{commit}").decode().strip()
    before, after = entry(root, base, PATH), entry(root, head, PATH)
    # An inherited assessment applies only to its original PR. Deletion uses defaults.
    if after is None or before == after:
        return default
    if after["mode"] != "100644":
        raise ValueError("Assessment must be an ordinary non-executable JSON file")
    raw = git(root, "show", head + ":" + PATH)
    if len(raw) > 128 * 1024:
        raise ValueError("Assessment exceeds size limit")
    data = json.loads(raw, object_pairs_hook=unique_object)
    if not isinstance(data, dict) or set(data) != {
        "schema", "base", "live_impact", "rationale", "requirement_id", "proof", "changes"
    }:
        raise ValueError("Assessment fields do not match schema")
    if type(data["schema"]) is not int or data["schema"] != 1 or data["base"] != base:
        raise ValueError("Assessment schema or merge base is stale")
    if data["live_impact"] not in TARGETS:
        raise ValueError("Unsupported assessed live impact")
    for field in ("rationale", "proof"):
        if not isinstance(data[field], str) or len(data[field].strip()) < 40:
            raise ValueError("Assessment needs a specific rationale and alternative proof")
    if not isinstance(data["requirement_id"], str) or not re.fullmatch(r"R[1-9][0-9]*", data["requirement_id"]):
        raise ValueError("Assessment must name a PR requirement ID")
    paths = git(root, "diff", "--no-renames", "--name-only", "-z", base, head).decode().split("\0")
    expected = {
        path: {"before": entry(root, base, path), "after": entry(root, head, path)}
        for path in paths if path and path != PATH
    }
    if not expected or data["changes"] != expected:
        raise ValueError("Assessment must bind every changed path, mode, and blob; regenerate after changes")
    # Dependency/contract changes always need the full live gate, even with an assessment.
    if any(path == ".gitmodules" or path.startswith("Vendor/") for path in expected):
        if data["live_impact"] != "gateway-differential":
            raise ValueError("Dependency and canonical contract changes require differential live verification")
    if body_file is not None:
        with open(body_file, encoding="utf-8") as stream:
            body = stream.read()
        rows = [line for line in body.splitlines() if line.strip().startswith("|")]
        matches = []
        for row in rows:
            cells = [cell.strip() for cell in row.strip().strip("|").split("|")]
            if cells and cells[0] == data["requirement_id"]:
                matches.append(cells)
        if len(matches) != 1 or len(matches[0]) != 6 or after["oid"] not in matches[0][4]:
            raise ValueError("PR must link the exact assessment blob in its named requirement evidence row")
    print("Verification applicability: " + data["live_impact"] +
          "; independent review required for " + data["requirement_id"] +
          "; assessment blob " + after["oid"], file=sys.stderr)
    return data["live_impact"]


def draft(root, base, head, target, requirement, rationale, proof):
    base = git(root, "merge-base", base, head).decode().strip()
    paths = git(root, "diff", "--no-renames", "--name-only", "-z", base, head).decode().split("\0")
    return {"schema": 1, "base": base, "live_impact": target,
            "requirement_id": requirement, "rationale": rationale, "proof": proof,
            "changes": {path: {"before": entry(root, base, path), "after": entry(root, head, path)}
                        for path in paths if path and path != PATH}}


if __name__ == "__main__":
    try:
        if len(sys.argv) == 9 and sys.argv[1] == "--draft":
            print(json.dumps(draft(*sys.argv[2:]), indent=2, sort_keys=True))
            sys.exit(0)
        if len(sys.argv) not in (5, 6):
            raise ValueError("Usage: verification-assessment.py ROOT BASE HEAD DEFAULT [PR_BODY_FILE]")
        print(resolve(*sys.argv[1:]))
    except (ValueError, TypeError, KeyError, OSError, subprocess.CalledProcessError) as error:
        print("Invalid verification assessment: " + str(error), file=sys.stderr)
        sys.exit(1)
