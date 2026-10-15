#!/usr/bin/env python3
"""Prevent stale/failed advisory reviews from being represented as completed proof."""

import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/validate-advisory-review.py"
spec = importlib.util.spec_from_file_location("advisory", SCRIPT)
advisory = importlib.util.module_from_spec(spec)
spec.loader.exec_module(advisory)
BASE, HEAD = "a" * 40, "b" * 40


def fixture():
    return {"schema_version": 1, "base": BASE, "head": HEAD, "reviews": [
        {"kind": kind, "route": route, "status": "completed", "scope": "PR diff",
         "reason": "Selected route", "report_reference": "private-report", "inspected": True,
         "coverage": "Diff and supporting code inspected; runtime excluded", "findings": []}
        for kind, route in (("code-review", "app-code-review"), ("security-review", "local-security"))
    ]}


class AdvisoryTests(unittest.TestCase):
    def test_completed_empty_and_disposed_findings(self):
        record = fixture()
        self.assertEqual(len(advisory.validate(record, BASE, HEAD)), 2)
        for disposition in ("open", "fixed", "rejected"):
            record["reviews"][1]["findings"] = [{"id": "F1", "disposition": disposition,
                "rationale": "Independently investigated", "evidence": "Source and regression evidence",
                "requirement_id": "R1"}]
            self.assertEqual(advisory.validate(record, BASE, HEAD)[1][2], int(disposition == "open"))

    def test_incomplete_services_are_valid_records_not_completed_reviews(self):
        for status in ("pending", "failed", "unavailable", "not-applicable"):
            record = fixture()
            review = record["reviews"][1]
            review.update(status=status, inspected=False, report_reference=None, coverage=None)
            if status == "not-applicable":
                review["route"] = "none"
            self.assertEqual(advisory.validate(record, BASE, HEAD)[1][1], status)
            review["inspected"] = True
            with self.assertRaises(ValueError):
                advisory.validate(record, BASE, HEAD)

    def test_stale_head_and_base(self):
        for base, head in ((BASE, "c" * 40), ("c" * 40, HEAD), ("main", HEAD)):
            with self.assertRaises(ValueError):
                advisory.validate(fixture(), base, head)

    def test_missing_duplicate_unknown_and_false_completion(self):
        variants = []
        record = fixture(); record["reviews"].pop(); variants.append(record)
        record = fixture(); record["reviews"][1] = copy.deepcopy(record["reviews"][0]); variants.append(record)
        for key, value in (("status", "clean"), ("route", "project-pr-reviewer"),
                           ("inspected", False), ("inspected", "true"),
                           ("coverage", None), ("report_reference", None), ("reason", "")):
            record = fixture(); record["reviews"][0][key] = value; variants.append(record)
        record = fixture(); record["reviews"][0]["findings"] = [{"id": "F1"}]; variants.append(record)
        record = fixture(); record["reviews"][0]["status"] = "not-applicable"; variants.append(record)
        for record in variants:
            with self.subTest(record=record), self.assertRaises(ValueError):
                advisory.validate(record, BASE, HEAD)
        with self.assertRaises(ValueError):
            json.loads('{"head":"old","head":"new"}', object_pairs_hook=advisory.unique_object)

    def test_private_cli_and_no_content_leak(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "record.json"
            path.write_text(json.dumps(fixture())); path.chmod(0o600)
            def run(target=path):
                return subprocess.run((sys.executable, "-I", str(SCRIPT), str(target), BASE, HEAD),
                                      capture_output=True, text=True)
            self.assertEqual(run().returncode, 0)
            path.chmod(0o644)
            self.assertNotEqual(run().returncode, 0)
            path.chmod(0o600)
            link = Path(directory) / "link.json"; link.symlink_to(path)
            self.assertNotEqual(run(link).returncode, 0)
            path.write_text('{"PRIVATE_SENTINEL": invalid}')
            result = run()
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn("PRIVATE_SENTINEL", result.stdout + result.stderr)

    def test_guidance_preserves_gate_and_product_boundaries(self):
        guide = (ROOT / "docs/ADVISORY_REVIEW_WORKFLOW.md").read_text()
        for phrase in ("advisory rollout", "not a completed review", "not the project reviewer",
                       "validated correctness", "private", "exact-head", "not Plus"):
            self.assertIn(phrase, guide)
        for relative in ("AGENTS.md", ".codex/agents/pr-reviewer.toml",
                         ".agents/skills/review-verify-merge-pr/SKILL.md"):
            self.assertIn("docs/ADVISORY_REVIEW_WORKFLOW.md", (ROOT / relative).read_text())


if __name__ == "__main__":
    unittest.main()
