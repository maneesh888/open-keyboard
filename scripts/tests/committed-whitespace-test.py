#!/usr/bin/env python3
"""Prove committed documentation whitespace is checked on a clean checkout."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


VALIDATOR = Path(__file__).resolve().parents[1] / "verify-committed-whitespace.sh"


class CommittedWhitespaceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = os.environ.copy()
        for name in subprocess.check_output(("git", "rev-parse", "--local-env-vars")).decode().splitlines():
            self.env.pop(name, None)
        self.env["OPEN_KEYBOARD_REPOSITORY_ROOT"] = str(self.root)
        self.git("init", "-q")
        self.git("config", "user.name", "Fixture")
        self.git("config", "user.email", "fixture@example.invalid")
        self.git("config", "core.hooksPath", "/dev/null")
        self.write("docs/plans/feature.md", "clean\n")
        self.base = self.commit()
        self.env["OPEN_KEYBOARD_CHECK_BASE_REF"] = self.base

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

    def validate(self):
        return subprocess.run(("bash", str(VALIDATOR)), cwd=self.root, env=self.env,
                              capture_output=True, text=True)

    def test_clean_committed_documentation_passes(self):
        self.write("docs/plans/feature.md", "clean revision\n")
        self.commit()
        self.assertEqual(self.validate().returncode, 0)

    def test_committed_trailing_whitespace_fails_on_clean_head(self):
        self.write("docs/plans/feature.md", "trailing space \n")
        self.commit()
        self.assertEqual(self.git("status", "--porcelain"), "")
        result = self.validate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("trailing whitespace", result.stdout + result.stderr)

    def test_unknown_base_fails_closed(self):
        self.env["OPEN_KEYBOARD_CHECK_BASE_REF"] = "0" * 40
        self.assertNotEqual(self.validate().returncode, 0)


if __name__ == "__main__":
    unittest.main()
