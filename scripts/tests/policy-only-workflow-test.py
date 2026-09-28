#!/usr/bin/env python3
"""Execute the real workflow's policy decision against adversarial Git histories."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
STEP = subprocess.check_output([
    "ruby", "-ryaml", "-e",
    'puts YAML.load_file(ARGV[0]).fetch("jobs").fetch("required-live-verification").fetch("steps").find { |s| s["name"] == "Classify exact-head live impact" }.fetch("run")',
    str(ROOT / ".github/workflows/live.yml"),
]).decode()
POLICY = STEP.split("<<'PY_POLICY'\n", 1)[1].split("\nPY_POLICY", 1)[0]


class PolicyWorkflowTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / "repo"
        self.root.mkdir()
        self.env = dict(os.environ)
        for name in subprocess.check_output(["git", "rev-parse", "--local-env-vars"], cwd=ROOT).decode().splitlines():
            self.env.pop(name, None)
        self.git("init", "-q")
        self.git("config", "user.name", "Fixture")
        self.git("config", "user.email", "fixture@example.invalid")
        self.git("config", "core.hooksPath", "/dev/null")
        self.write("AGENTS.md", "base policy\n")
        self.write("OpenKeyboard/App.swift", "shipping\n")
        self.write("scripts/live-impact.sh", "candidate must not run\n", 0o755)
        self.base = self.commit()
        self.write("AGENTS.md", "revised policy\n")
        self.validator = Path(self.tmp.name) / "trusted"
        self.validator.mkdir()
        self.write_validator('echo gateway-differential')
        self.env.update(PR_BASE_SHA=self.base, VALIDATOR_ROOT=str(self.validator),
                        GITHUB_WORKSPACE=str(self.root), GITHUB_ENV=str(Path(self.tmp.name) / "env"))

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.root), *args], env=self.env, stderr=subprocess.DEVNULL).decode().strip()

    def write(self, path, value, mode=0o644):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(value)
        target.chmod(mode)

    def write_validator(self, command):
        target = self.validator / "live-impact.sh"
        target.write_text('#!/bin/bash\nset -e\n' + command + '\n')
        target.chmod(0o755)

    def commit(self):
        self.git("add", "-A")
        self.git("commit", "--allow-empty", "-qm", "fixture")
        return self.git("rev-parse", "HEAD")

    def classify(self, expected="gateway-differential", error=False):
        self.env["PR_HEAD_SHA"] = self.commit()
        result = subprocess.run(["bash", "-e", "-o", "pipefail", "-c", STEP], cwd=self.root,
                                env=self.env, capture_output=True, text=True)
        if error:
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(Path(self.env["GITHUB_ENV"]).exists())
        else:
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(Path(self.env["GITHUB_ENV"]).read_text(), f"LIVE_IMPACT={expected}\n")

    def test_policy_modification(self):
        self.classify("none")

    def test_designated_additions(self):
        for path in ("docs/VERIFICATION_APPLICABILITY.md", "scripts/verification-assessment.py",
                     "scripts/tests/verification-assessment-test.py", "scripts/tests/policy-only-workflow-test.py"):
            self.write(path, "new policy\n")
        self.classify("none")

    def test_mixed_shipping(self):
        self.write("OpenKeyboard/App.swift", "changed shipping\n")
        self.classify()

    def test_unknown_path(self):
        self.write("scripts/new-policy.sh", "unknown\n")
        self.classify()

    def test_configuration_and_assessment(self):
        for path in (".github/verification-assessment.json", "config.env", ".gitmodules"):
            with self.subTest(path=path):
                self.write(path, "{}\n")
                self.classify()
                Path(self.env["GITHUB_ENV"]).unlink()

    def test_deleted_policy(self):
        (self.root / "AGENTS.md").unlink()
        self.classify()

    def test_rename_shipping_to_policy(self):
        self.git("mv", "OpenKeyboard/App.swift", "docs-new.md")
        self.classify()

    def test_rename_policy_to_unknown(self):
        self.git("mv", "AGENTS.md", "other.md")
        self.classify()

    def test_shipping_replaced_by_designated_policy(self):
        (self.root / "docs").mkdir()
        self.git("mv", "OpenKeyboard/App.swift", "docs/VERIFICATION_APPLICABILITY.md")
        self.classify()

    def test_executable_mode_change(self):
        (self.root / "AGENTS.md").chmod(0o755)
        self.classify()

    def test_symlink(self):
        (self.root / "AGENTS.md").unlink()
        (self.root / "AGENTS.md").symlink_to("OpenKeyboard/App.swift")
        self.classify()

    def test_gitlink(self):
        (self.root / "AGENTS.md").unlink()
        self.git("update-index", "--add", "--cacheinfo", f"160000,{self.base},AGENTS.md")
        self.git("commit", "-qm", "gitlink fixture")
        (self.root / "AGENTS.md").mkdir()
        self.classify()

    def test_newline_path(self):
        self.write("AGENTS.md\nshipping.swift", "unknown\n")
        self.classify()

    def test_empty_diff(self):
        self.write("AGENTS.md", "base policy\n")
        self.classify()

    def test_invalid_base(self):
        self.env["PR_BASE_SHA"] = "0" * 40
        self.classify(error=True)

    def test_trusted_classifier_failure_not_overridden(self):
        self.write_validator("exit 37")
        self.classify(error=True)

    def test_trusted_classifier_invalid_not_overridden(self):
        self.write_validator("echo invalid")
        self.classify(error=True)

    def test_candidate_classifier_not_executed(self):
        self.write("scripts/live-impact.sh", "#!/bin/bash\necho none\n", 0o755)
        self.write("OpenKeyboard/App.swift", "shipping change\n")
        self.classify()

    def shadow_module(self):
        return ('def check_output(args):\n'
                f'    if args[1] == "merge-base": return {self.base.encode()!r}\n'
                '    return b":100644 100644 a b M\\0AGENTS.md\\0"\n')

    def test_checkout_module_shadowing(self):
        self.write("subprocess.py", self.shadow_module())
        self.write("OpenKeyboard/App.swift", "shipping change\n")
        self.classify()

    def test_pythonpath_module_injection(self):
        injection = Path(self.tmp.name) / "injection"
        injection.mkdir()
        (injection / "subprocess.py").write_text(self.shadow_module())
        self.env["PYTHONPATH"] = str(injection)
        self.write("OpenKeyboard/App.swift", "shipping change\n")
        self.classify()

    def test_incomplete_diff_enumeration(self):
        for raw in (b":100644 100644 a b M\0", b":100644 100644 a b M\0AGENTS.md", b"invalid\0AGENTS.md\0"):
            with self.subTest(raw=raw), patch.dict(os.environ, PR_BASE_SHA=self.base, PR_HEAD_SHA=self.base):
                with patch("subprocess.check_output", side_effect=[self.base.encode(), raw]):
                    with self.assertRaises(SystemExit):
                        exec(POLICY, {})


if __name__ == "__main__":
    unittest.main()
