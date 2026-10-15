#!/usr/bin/env python3
"""Exercise the real diff classifier with safe and adversarial Git histories."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


CLASSIFIER = Path(__file__).resolve().parents[1] / "verification-scope.py"


class VerificationScopeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = os.environ.copy()
        for name in subprocess.check_output(("git", "rev-parse", "--local-env-vars")).decode().splitlines():
            self.env.pop(name, None)
        self.git("init", "-q")
        self.git("config", "user.name", "Fixture")
        self.git("config", "user.email", "fixture@example.invalid")
        self.git("config", "core.hooksPath", "/dev/null")
        self.write("README.md", "hello\n")
        self.write("docs/plans/feature.md", "plan\n")
        self.write("OpenKeyboard/App.swift", "app\n")
        self.write("AGENTS.md", "policy\n")
        self.base = self.commit()

    def git(self, *args):
        return subprocess.check_output(("git", "-C", str(self.root), *args), env=self.env,
                                       stderr=subprocess.DEVNULL).decode().strip()

    def write(self, name, contents):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents)

    def commit(self):
        self.git("add", "-A")
        self.git("commit", "-qm", "fixture")
        return self.git("rev-parse", "HEAD")

    def scope(self, *args):
        return subprocess.check_output(("python3", "-I", str(CLASSIFIER), *args), cwd=self.root,
                                       env=self.env).decode().strip()

    def assert_range(self, expected):
        head = self.commit()
        self.assertEqual(self.scope("--range", self.base, head), expected)

    def test_markdown_modification_addition_deletion_and_staged(self):
        self.write("docs/plans/feature.md", "revised plan\n")
        self.write("docs/plans/new.md", "new plan\n")
        (self.root / "README.md").unlink()
        self.git("add", "-A")
        self.assertEqual(self.scope("--staged"), "docs")
        self.assert_range("docs")

    def test_source_and_mixed_change_are_full(self):
        self.write("docs/plans/feature.md", "revised plan\n")
        self.write("OpenKeyboard/App.swift", "changed app\n")
        self.assert_range("full")

    def test_existing_ordinary_documents_are_docs(self):
        for name in ("docs/AI_OPERATION_DIAGNOSTICS.md", "docs/UNIVERSAL_AI_CONNECTOR.md",
                     "docs/PROMPT_EVALS.md", "docs/TDD_BACKEND_PLAN.md"):
            with self.subTest(name=name):
                self.write(name, "ordinary documentation\n")
                self.assert_range("docs")
                self.git("reset", "--hard", self.base)

    def test_policy_and_workflow_are_full(self):
        for name in ("AGENTS.md", "docs/DEVELOPMENT_WORKFLOW.md",
                     "docs/VERIFICATION_APPLICABILITY.md", "docs/RELEASE_HARDENING.md",
                     "docs/AI_KEYBOARD_TEST_PLAN.md", "docs/new-policy.md",
                     ".github/workflows/ci.yml",
                     "scripts/check.sh", "Package.swift", ".gitmodules"):
            with self.subTest(name=name):
                self.write(name, "change\n")
                self.assert_range("full")
                self.git("reset", "--hard", self.base)

    def test_unknown_extension_is_full(self):
        self.write("docs/config.json", "{}\n")
        self.assert_range("full")

    def test_symlink_executable_and_gitlink_are_full(self):
        (self.root / "README.md").unlink()
        (self.root / "README.md").symlink_to("OpenKeyboard/App.swift")
        self.assert_range("full")
        self.git("reset", "--hard", self.base)
        (self.root / "README.md").chmod(0o755)
        self.assert_range("full")
        self.git("reset", "--hard", self.base)
        (self.root / "README.md").unlink()
        self.git("update-index", "--add", "--cacheinfo", f"160000,{self.base},README.md")
        self.assertEqual(self.scope("--staged"), "full")

    def test_rename_crossing_boundary_is_full(self):
        self.git("mv", "OpenKeyboard/App.swift", "docs/plans/source.md")
        self.assert_range("full")

    def test_empty_diff_is_full(self):
        self.assertEqual(self.scope("--staged"), "full")
        self.assertEqual(self.scope("--range", self.base, self.base), "full")

    def test_malformed_diff_is_full(self):
        import importlib.util
        sys.dont_write_bytecode = True
        spec = importlib.util.spec_from_file_location("scope", CLASSIFIER)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        malformed_oid = b":100644 100644 " + b"x" * 40 + b" " + b"x" * 40 + b" M\0README.md\0"
        for raw in (b"", b"broken\0", b":100644 100644 a b M\0",
                    b"invalid\0docs/a.md\0", malformed_oid):
            with self.subTest(raw=raw):
                self.assertEqual(module.classify(raw), "full")


if __name__ == "__main__":
    unittest.main()
