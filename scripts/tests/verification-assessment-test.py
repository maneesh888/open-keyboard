#!/usr/bin/env python3
"""Exercise assessment freshness and evidence linkage against real Git histories."""
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
spec = importlib.util.spec_from_file_location("assessment", ROOT / "scripts/verification-assessment.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class AssessmentTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.env = dict(os.environ)
        names = subprocess.check_output(["git", "rev-parse", "--local-env-vars"], cwd=ROOT).decode().splitlines()
        for name in names:
            self.env.pop(name, None)
            os.environ.pop(name, None)
        self.git("init", "-q")
        self.git("config", "user.name", "Verification Fixture")
        self.git("config", "user.email", "fixture@example.invalid")
        self.git("config", "core.hooksPath", "/dev/null")
        self.path = "OpenKeyboard/Models/AppConfig.swift"
        self.write(self.path, "struct AppConfig {}\n")
        self.base = self.commit()
        self.write(self.path, 'struct AppConfig { static let keyboardFullAccessKey = "fullAccess" }\n')
        self.candidate = self.commit()

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.root), *args], env=self.env, stderr=subprocess.DEVNULL).decode().strip()

    def write(self, path, content):
        file = self.root / path
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(content)

    def commit(self):
        self.git("add", "-A")
        self.git("commit", "-qm", "fixture")
        return self.git("rev-parse", "HEAD")

    def draft(self, target="none"):
        paths = self.git("diff", "--name-only", "--no-renames", self.base, "HEAD").splitlines()
        return {"schema": 1, "base": self.base, "live_impact": target,
                "rationale": "Only the shared Full Access hint changes; no request, model, or parser behavior changes.",
                "requirement_id": "R2",
                "proof": "Focused Full Access regression and normal Settings-to-Home simulator observation verify this change.",
                "changes": {p: {"before": module.entry(str(self.root), self.base, p),
                                "after": module.entry(str(self.root), "HEAD", p)}
                            for p in paths if p != module.PATH}}

    def assess(self, data=None):
        self.write(module.PATH, json.dumps(self.draft() if data is None else data))
        return self.commit()

    def classify(self, head=None, expected=0):
        result = subprocess.run([str(ROOT / "scripts/live-impact.sh"), self.base, head or self.git("rev-parse", "HEAD")],
            env={**self.env, "OPEN_KEYBOARD_REPOSITORY_ROOT": str(self.root)}, capture_output=True, text=True)
        if expected == 0:
            self.assertEqual(result.returncode, 0, result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout)
        return result.stdout.strip()

    def test_shared_file_requires_assessment_to_reduce_gate(self):
        self.assertEqual(self.classify(), "gateway-differential")
        self.assess()
        self.assertEqual(self.classify(), "none")

    def test_focused_gateway_can_replace_unrelated_differential(self):
        self.assess(self.draft("gateway"))
        self.assertEqual(self.classify(), "gateway")

    def test_later_edit_invalidates_assessment(self):
        self.assess()
        self.write(self.path, "let retryCount = 8\n")
        self.commit()
        self.classify(expected=1)

    def test_added_path_invalidates_assessment(self):
        self.assess()
        self.write("OpenKeyboard/Services/NetworkManager.swift", "let retryCount = 8\n")
        self.commit()
        self.classify(expected=1)

    def test_chmod_invalidates_assessment(self):
        self.assess()
        (self.root / self.path).chmod(0o755)
        self.commit()
        self.classify(expected=1)

    def test_rename_and_delete_are_bound(self):
        self.git("mv", self.path, "OpenKeyboard/Models/Renamed.swift")
        self.commit()
        self.assess()
        self.assertEqual(self.classify(), "none")
        (self.root / "OpenKeyboard/Models/Renamed.swift").unlink()
        self.commit()
        self.classify(expected=1)

    def test_changed_base_rejected(self):
        data = self.draft()
        data["base"] = self.candidate
        self.assess(data)
        self.classify(expected=1)

    def test_inherited_assessment_does_not_exempt_new_changes(self):
        self.base = self.assess()
        self.write(self.path, "let retryCount = 8\n")
        self.commit()
        self.assertEqual(self.classify(), "gateway-differential")

    def test_deleted_assessment_restores_default(self):
        self.assess()
        (self.root / module.PATH).unlink()
        self.commit()
        self.assertEqual(self.classify(), "gateway-differential")

    def test_dependency_change_cannot_be_exempted(self):
        self.write(".gitmodules", "changed dependency\n")
        self.commit()
        self.assess()
        self.classify(expected=1)

    def test_malformed_and_duplicate_fields_rejected(self):
        for raw in ('{}', '{"schema":1,"schema":1}', '[]', '{bad'):
            self.write(module.PATH, raw)
            self.commit()
            self.classify(expected=1)

    def test_unknown_field_and_empty_rationale_rejected(self):
        for field, value in (("unknown", True), ("rationale", ""), ("live_impact", "skip")):
            data = self.draft()
            data[field] = value
            self.assess(data)
            self.classify(expected=1)

    def test_worktree_assessment_does_not_change_committed_classification(self):
        self.write(module.PATH, json.dumps(self.draft()))
        self.assertEqual(self.classify(self.candidate), "gateway-differential")

    def test_workflow_checks_both_assessment_snapshots(self):
        head = self.assess()
        blob = module.entry(str(self.root), head, module.PATH)["oid"]
        valid = f"| R2 | Applicability | Correct scope | Diff review | assessment {blob} | VERIFIED |\n"
        step = subprocess.check_output(["ruby", "-ryaml", "-e",
            'puts YAML.load_file(ARGV[0])["jobs"]["required-live-verification"]["steps"].find { |s| s["name"] == "Enforce event and current exact-head live evidence" }["run"]',
            str(ROOT / ".github/workflows/live.yml")]).decode()
        event, current = self.root / "event.md", self.root / "current.md"
        for event_body, current_body, succeeds in ((valid, valid, True), ("", valid, False), (valid, "", False)):
            event.write_text(event_body)
            current.write_text(current_body)
            result = subprocess.run(["bash", "-e", "-o", "pipefail", "-c", step],
                env={**self.env, "PR_BASE_SHA": self.base, "EVENT_HEAD_SHA": head,
                     "GITHUB_WORKSPACE": str(self.root), "VALIDATOR_ROOT": str(ROOT / "scripts"),
                     "LIVE_IMPACT": "none", "EVENT_BODY_FILE": str(event), "CURRENT_BODY_FILE": str(current)},
                capture_output=True, text=True)
            self.assertEqual(result.returncode == 0, succeeds, result.stderr + result.stdout)

    def test_pr_requires_exact_assessment_in_named_evidence_row(self):
        head = self.assess()
        blob = module.entry(str(self.root), head, module.PATH)["oid"]
        body = self.root / "body.md"
        body.write_text(f"| R2 | Applicability | Correct scope | Diff review | assessment {blob} | VERIFIED |\n")
        self.assertEqual(module.resolve(str(self.root), self.base, head, "gateway-differential", str(body)), "none")
        for invalid in ("", body.read_text().replace(blob, "stale"), body.read_text() * 2,
                        body.read_text().replace("R2", "R1")):
            body.write_text(invalid)
            with self.assertRaises(ValueError):
                module.resolve(str(self.root), self.base, head, "gateway-differential", str(body))


if __name__ == "__main__":
    unittest.main()
