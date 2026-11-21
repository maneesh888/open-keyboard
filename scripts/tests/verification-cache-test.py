#!/usr/bin/env python3
"""Regression tests for private receipts and the actual live-runner resume branches."""

import importlib.util
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
# Hooks export repository-local Git variables; temporary fixture repos must not inherit them.
for name in subprocess.check_output(["git", "rev-parse", "--local-env-vars"], cwd=ROOT).decode().splitlines():
    os.environ.pop(name, None)

spec = importlib.util.spec_from_file_location("verification_cache", ROOT / "scripts/verification-cache.py")
cache = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cache)


class ReceiptTests(unittest.TestCase):
    def setUp(self):
        self.expected_head = patch.dict(os.environ)
        self.expected_head.start()
        self.addCleanup(self.expected_head.stop)
        for name in ("OPEN_KEYBOARD_VERIFICATION_EXPECTED_SHA", "OPEN_KEYBOARD_CHECK_BASE_REF",
                     "OPEN_KEYBOARD_LIVE_BASE_REF", "OPEN_KEYBOARD_VERIFICATION_FRESH"):
            os.environ.pop(name, None)
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.area = Path(self.temporary.name)
        self.repo = self.area / "repo"
        self.repo.mkdir()
        self.git("init", "-q")
        self.git("config", "user.name", "Fixture")
        self.git("config", "user.email", "fixture@example.invalid")
        self.git("config", "commit.gpgsign", "false")
        (self.repo / "tracked").write_text("first\n")
        self.commit()
        self.git("update-ref", "refs/remotes/origin/main", "HEAD")
        self.seed = self.area / "private.env"
        self.seed.write_text("PRIVATE_CANARY=first-secret-model\n")
        self.seed.chmod(0o600)
        self.versions = {"xcode": "fixture-27.1", "runtime": "fixture-27.0"}
        self.patcher = patch.object(cache, "toolchain", lambda: self.versions)
        self.patcher.start()
        self.addCleanup(self.patcher.stop)
        self.store = cache.Cache(self.repo)

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.repo, stderr=subprocess.DEVNULL).decode().strip()

    def commit(self):
        self.git("add", ".")
        self.git("commit", "-qm", "fixture")

    def binding(self):
        return self.store.binding([self.seed])

    def test_same_head_pass_is_reusable_without_retaining_seed_values(self):
        binding = self.binding()
        self.store.put(binding, "provider-openai", "passed")
        self.assertEqual(self.store.get(binding, "provider-openai"), "passed")
        self.assertNotIn(b"first-secret-model", self.store.location(binding, "provider-openai").read_bytes())
        self.assertEqual(self.store.root.stat().st_mode & 0o777, 0o700)
        self.assertEqual((self.store.root / "key").stat().st_mode & 0o777, 0o600)

    def test_failed_missing_and_unknown_rows_cannot_be_promoted(self):
        binding = self.binding()
        self.assertIsNone(self.store.get(binding, "provider-gateway"))
        with self.assertRaises(cache.CacheError):
            self.store.put(binding, "provider-gateway", "failed")
        with self.assertRaises(cache.CacheError):
            self.store.put(binding, "skipped-test", "passed")

    def test_role_diagnostics_are_retained_exactly_and_cannot_be_swapped(self):
        binding = self.binding()
        value = "diagnostic_outcomes_low=transport=passed, grammar=passed, rewrite=passed, translation=failed"
        self.store.put(binding, "profile-low", value)
        self.assertEqual(self.store.get(binding, "profile-low"), value)
        with self.assertRaises(cache.CacheError):
            self.store.put(binding, "profile-high", value)
        with self.assertRaises(cache.CacheError):
            self.store.put(binding, "profile-low", value.replace("grammar=passed", "grammar=failed"))

    def test_commit_base_seed_toolchain_and_build_environment_invalidate(self):
        initial = self.binding()
        self.seed.write_text("PRIVATE_CANARY=other-secret-model\n")
        self.assertNotEqual(initial, self.binding())
        self.seed.write_text("PRIVATE_CANARY=first-secret-model\n")
        self.assertEqual(initial, self.binding())
        self.versions["runtime"] = "another-runtime"
        self.assertNotEqual(initial, self.binding())
        self.versions["runtime"] = "fixture-27.0"
        with patch.dict(os.environ, {"ARCHS": "changed-arch"}):
            self.assertNotEqual(initial, self.binding())
        (self.repo / "tracked").write_text("second\n")
        self.commit()
        new_head = self.binding()
        self.assertNotEqual(initial, new_head)
        self.git("update-ref", "refs/remotes/origin/main", "HEAD")
        self.assertNotEqual(new_head, self.binding())

    def test_foreign_hook_git_state_does_not_redirect_the_fingerprint(self):
        initial = self.binding()
        with patch.dict(os.environ, {"GIT_DIR": str(self.area / "unrelated"),
                                     "GIT_WORK_TREE": str(self.area),
                                     "GIT_INDEX_FILE": str(self.area / "other-index"),
                                     "GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "core.worktree",
                                     "GIT_CONFIG_VALUE_0": str(self.area)}):
            self.assertEqual(initial, self.binding())

    def test_expected_head_is_enforced_before_any_reuse(self):
        with patch.dict(os.environ, {"OPEN_KEYBOARD_VERIFICATION_EXPECTED_SHA": "0" * 40}):
            with self.assertRaises(cache.CacheError):
                self.binding()

    def test_dirty_tree_never_uses_committed_receipts(self):
        (self.repo / "untracked").write_text("not committed")
        self.assertIsNone(self.binding())
        (self.repo / "untracked").unlink()
        (self.repo / "tracked").write_text("dirty")
        self.assertIsNone(self.binding())

    def test_expired_future_corrupted_and_truncated_receipts_are_misses(self):
        binding = self.binding()
        with patch.object(cache.time, "time", return_value=100000):
            self.store.put(binding, "core", "passed")
        with patch.object(cache.time, "time", return_value=100000 + cache.MAX_AGE + 1):
            self.assertIsNone(self.store.get(binding, "core"))
        with patch.object(cache.time, "time", return_value=99999):
            self.assertIsNone(self.store.get(binding, "core"))
        self.store.put(binding, "core", "passed")
        path = self.store.location(binding, "core")
        record = json.loads(path.read_text())
        record["record"]["stage"] = "build"
        path.write_text(json.dumps(record))
        self.assertIsNone(self.store.get(binding, "core"))
        path.write_text("{")
        self.assertIsNone(self.store.get(binding, "core"))

    def test_unsafe_state_and_symlinks_are_rejected(self):
        binding = self.binding()
        self.store.put(binding, "core", "passed")
        path = self.store.location(binding, "core")
        path.chmod(0o644)
        with self.assertRaises(cache.CacheError):
            self.store.get(binding, "core")
        path.unlink()
        path.symlink_to(self.seed)
        with self.assertRaises(cache.CacheError):
            self.store.get(binding, "core")
        path.unlink()
        self.seed.chmod(0o644)
        with self.assertRaises(cache.CacheError):
            self.binding()

    def test_stage_execution_failure_and_forced_rerun_replace_old_pass(self):
        path = self.repo / "scripts/ios/test.sh"
        path.parent.mkdir(parents=True)
        path.write_text("#!/bin/bash\nexit \"${FIXTURE_STATUS:-0}\"\n")
        path.chmod(0o755)
        self.commit()
        args = ["cache", "run", str(self.repo), "core", "--", str(path), "core"]
        with patch.object(sys, "argv", args):
            self.assertEqual(cache.main(), 0)
        binding = self.store.binding([])
        self.assertEqual(self.store.get(binding, "core"), "passed")
        with patch.dict(os.environ, {"OPEN_KEYBOARD_VERIFICATION_FRESH": "1", "FIXTURE_STATUS": "7"}):
            with patch.object(sys, "argv", args):
                self.assertEqual(cache.main(), 7)
        self.assertIsNone(self.store.get(binding, "core"))

    def test_canonical_path_alias_is_the_same_stage_command(self):
        path = self.repo / "scripts/ios/test.sh"
        path.parent.mkdir(parents=True)
        path.write_text("#!/bin/bash\nexit 0\n")
        path.chmod(0o755)
        self.commit()
        alias = self.area / "alias"
        alias.symlink_to(self.repo, target_is_directory=True)
        with patch.object(sys, "argv", ["cache", "run", str(alias), "core", "--", str(alias / "scripts/ios/test.sh"), "core"]):
            self.assertEqual(cache.main(), 0)

    def test_stage_execution_does_not_hold_the_metadata_lock(self):
        child = self.area / "metadata-probe.py"
        child.write_text(
            "import importlib.util,sys\nsys.dont_write_bytecode=True\n"
            "s=importlib.util.spec_from_file_location('cache',sys.argv[1])\n"
            "m=importlib.util.module_from_spec(s);s.loader.exec_module(m)\n"
            "c=m.Cache(sys.argv[2])\n"
            "with c.locked(): pass\n")
        path = self.repo / "scripts/ios/test.sh"
        path.parent.mkdir(parents=True)
        # Fixture paths are generated internally, and argv is passed without shell expansion.
        import shlex
        path.write_text("#!/bin/bash\nexec " + " ".join(shlex.quote(v) for v in
                        [sys.executable, "-I", str(child), str(ROOT / "scripts/verification-cache.py"), str(self.repo)]) + "\n")
        path.chmod(0o755)
        self.commit()
        actual_run = subprocess.run
        def execute(command, **kwargs):
            if command[0] == str(path):
                kwargs["timeout"] = 10
            return actual_run(command, **kwargs)
        with patch.object(sys, "argv", ["cache", "run", str(self.repo), "core", "--", str(path), "core"]):
            with patch.object(cache.subprocess, "run", side_effect=execute):
                self.assertEqual(cache.main(), 0)

    def test_arbitrary_command_cannot_mint_a_passing_test_receipt(self):
        with patch.object(sys, "argv", ["cache", "run", str(self.repo), "core", "--", "true"]):
            with self.assertRaises(cache.CacheError):
                cache.main()

    def test_changed_input_during_command_cannot_save_a_pass(self):
        path = self.repo / "scripts/ios/test.sh"
        path.parent.mkdir(parents=True)
        path.write_text("#!/bin/bash\nprintf dirty > tracked\n")
        path.chmod(0o755)
        self.commit()
        binding = self.store.binding([])
        with patch.object(sys, "argv", ["cache", "run", str(self.repo), "core", "--", str(path), "core"]):
            actual_run = subprocess.run
            def execute(command, **kwargs):
                return self.changed_result() if command[0] == str(path) else actual_run(command, **kwargs)
            with patch.object(cache.subprocess, "run", side_effect=execute):
                with self.assertRaises(cache.CacheError):
                    cache.main()
        self.assertIsNone(self.store.get(binding, "core"))

    def changed_result(self):
        (self.repo / "tracked").write_text("changed during execution")
        return subprocess.CompletedProcess([], 0)


class LiveResumeTests(unittest.TestCase):
    def setUp(self):
        self.expected_head = patch.dict(os.environ)
        self.expected_head.start()
        self.addCleanup(self.expected_head.stop)
        for name in ("OPEN_KEYBOARD_VERIFICATION_EXPECTED_SHA", "OPEN_KEYBOARD_CHECK_BASE_REF",
                     "OPEN_KEYBOARD_LIVE_BASE_REF", "OPEN_KEYBOARD_VERIFICATION_FRESH"):
            os.environ.pop(name, None)
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.area = Path(self.temporary.name)
        self.repo = self.area / "repo"
        (self.repo / "scripts/ios").mkdir(parents=True)
        for name in ("scripts/verification-cache.py", "scripts/ios/verification-resume.sh", "scripts/ios/live-test-safety.sh"):
            shutil.copy(ROOT / name, self.repo / name)
        self.bin = self.repo / "bin"
        self.bin.mkdir()
        for name, content in {
            "xcodebuild": "#!/bin/bash\necho 'Xcode fixture-27.1'\n",
            "xcrun": "#!/bin/bash\nif [[ \"$1\" == simctl ]]; then echo '{\"runtimes\":[]}'; else echo swift-fixture; fi\n",
            "node": "#!/bin/bash\necho fixture-node\n", "java": "#!/bin/bash\necho fixture-java\n",
        }.items():
            p = self.bin / name
            p.write_text(content)
            p.chmod(0o755)
        self.seed = self.area / "private.env"
        self.seed.write_text("fixture-secret-identity")
        self.seed.chmod(0o600)
        helper = self.repo / "Vendor/universal-ai-connector/scripts/local-config.sh"
        helper.parent.mkdir(parents=True)
        helper.write_text('''uac_primary_checkout() { printf '%s\\n' "$REPO_ROOT"; }
uac_live_env_path() { printf '%s\\n' "$FIXTURE_SEED"; }
uac_validate_live_env_file() { return 0; }
''')
        subprocess.run(["git", "init", "-q", str(self.repo)], check=True)
        for key, value in (("user.name", "Fixture"), ("user.email", "fixture@example.invalid"), ("commit.gpgsign", "false")):
            subprocess.run(["git", "-C", str(self.repo), "config", key, value], check=True)
        subprocess.run(["git", "-C", str(self.repo), "add", "."], check=True)
        subprocess.run(["git", "-C", str(self.repo), "commit", "-qm", "fixture"], check=True)
        subprocess.run(["git", "-C", str(self.repo), "update-ref", "refs/remotes/origin/main", "HEAD"], check=True)
        self.events = self.area / "events"
        self.environment = {**os.environ, "PATH": str(self.bin) + os.pathsep + os.environ["PATH"],
                            "REPO_ROOT": str(self.repo), "FIXTURE_SEED": str(self.seed),
                            "EVENTS": str(self.events), "FIXTURE_WORK": str(self.area / "work")}
        # Host/task controls must not select a different base or force the fixture's mode.
        for key in ("OPEN_KEYBOARD_CHECK_BASE_REF", "OPEN_KEYBOARD_LIVE_BASE_REF", "OPEN_KEYBOARD_VERIFICATION_FRESH"):
            self.environment.pop(key, None)

    def run_route(self, mode, **environment):
        source = (ROOT / "scripts/ios/test.sh").read_text()
        start = source.index("  " + mode + ")\n", source.index("simulator_mode_requires_lock()"))
        end = source.index("\n    ;;", start)
        body = source[start + len("  " + mode + ")\n"):end]
        helpers = "\n".join(re.search(r"^" + name + r"\(\) \{\n.*?^\}", source, re.MULTILINE | re.DOTALL)[0]
                            for name in ("openkeyboard_unset_initial_route_controls",
                                         "openkeyboard_unset_ambient_private_live_values",
                                         "openkeyboard_unset_uac_live_provider_inputs",
                                         "openkeyboard_unset_seed_backed_live_ambient_inputs"))
        program = '''set -euo pipefail
source "$REPO_ROOT/scripts/ios/live-test-safety.sh"
source "$REPO_ROOT/scripts/ios/verification-resume.sh"
PROJECT=fixture SCHEME=fixture GREEN= RED= YELLOW= NC=
initial_uac_checkout="$REPO_ROOT" initial_provider_evidence_output=''
initial_seed_file="$FIXTURE_SEED" initial_differential_evidence_output='' initial_live_profile=reference
DEFAULT_SIMULATOR_GATEWAY_SEED_FILE="$FIXTURE_SEED"
LIVE_DIFFERENTIAL_EXECUTION_MODE="${FIXTURE_MODE:-verification}"
require_xcodebuild() { return 0; }
begin_sensitive_live_workspace() {
  SENSITIVE_LIVE_WORKSPACE="$(mktemp -d "$FIXTURE_WORK.XXXXXX")"
  SENSITIVE_LIVE_SIMULATOR='' SENSITIVE_LIVE_SIMULATOR_OWNED=false
  trap 'rm -rf -- "$SENSITIVE_LIVE_WORKSPACE"' EXIT
}
openkeyboard_primary_checkout_root() { printf '%s\\n' "$REPO_ROOT"; }
openkeyboard_require_trusted_seed_directory() { return 0; }
openkeyboard_require_local_seed_file() { printf '%s\\n' "$FIXTURE_SEED"; }
openkeyboard_require_two_profile_gateway_seed() { return 0; }
openkeyboard_load_simulator_gateway_seed() {
  OPEN_KEYBOARD_SIMULATOR_LOW_MODEL=fixture-low OPEN_KEYBOARD_SIMULATOR_HIGH_MODEL=fixture-high
}
openkeyboard_select_simulator_gateway_profile() { OPEN_KEYBOARD_SIMULATOR_MODEL="fixture-$1"; }
select_loaded_live_profile() {
  OPEN_KEYBOARD_SIMULATOR_SELECTED_PROFILE="${FIXTURE_REFERENCE_ROLE:-high}"
  OPEN_KEYBOARD_SIMULATOR_MODEL="fixture-$OPEN_KEYBOARD_SIMULATOR_SELECTED_PROFILE"
}
openkeyboard_load_uac_live_provider_profile() {
  OPEN_KEYBOARD_SIMULATOR_SELECTED_PROFILE="$1" OPEN_KEYBOARD_SIMULATOR_PROVIDER="$1"
  if [[ "$1" == gateway ]]; then OPEN_KEYBOARD_SIMULATOR_PROVIDER=openai-compatible; fi
}
create_sensitive_live_simulator() {
  printf 'create\\n' >> "$EVENTS"
  SENSITIVE_LIVE_SIMULATOR=fixture-owned SENSITIVE_LIVE_SIMULATOR_OWNED=true
}
openkeyboard_delete_sensitive_live_simulator() { SENSITIVE_LIVE_SIMULATOR='' SENSITIVE_LIVE_SIMULATOR_OWNED=false; }
simulator_destination() { printf 'platform=iOS Simulator,id=fixture-owned\\n'; }
inject_xctestrun_live_smoke_env() { return 0; }
run_xcodebuild() {
  if [[ "$2" == build-for-testing ]]; then
    printf 'build\\n' >> "$EVENTS"
    mkdir -p "$derived_data/Build/Products"
    touch "$derived_data/Build/Products/fixture.xctestrun"
    return 0
  fi
  local name=contracts
  if [[ "$*" == *LiveGatewaySmokeTests* ]]; then
    if [[ -n "${provider:-}" ]]; then name="provider-$provider"; else name="reference-$reference_role"; fi
  fi
  if [[ "$*" == *LiveModelDifferentialTests* ]]; then name="profile-$profile_role"; fi
  printf '%s\\n' "$name" >> "$EVENTS"
  [[ "$name" != "${FAIL_ROW:-}" ]]
}
openkeyboard_assert_single_passing_xcresult() { return 0; }
openkeyboard_assert_passing_xcresult_count() { return 0; }
openkeyboard_classify_low_differential_xcresult() { printf '%s' "${FIXTURE_LOW_OUTCOME:-expected-model-capability}"; }
openkeyboard_extract_live_diagnostic_evidence() {
  local grammar=passed
  if [[ "profile-$2" == "${FAIL_ROW:-}" ]]; then grammar=failed; fi
  printf 'diagnostic_outcomes_%s=transport=passed, grammar=%s, rewrite=passed, translation=passed\\n' "$2" "$grammar"
}
'''
        return subprocess.run(["bash", "-c", program + helpers + "\n" + body], cwd=self.repo,
                              env={**self.environment, **environment}, text=True, capture_output=True)

    def lines(self):
        return self.events.read_text().splitlines() if self.events.exists() else []

    def test_failed_provider_alone_is_retried_and_completed_matrix_still_required(self):
        first = self.run_route("live-provider-matrix", FAIL_ROW="provider-gateway")
        self.assertNotEqual(first.returncode, 0, first.stderr)
        self.assertEqual([v for v in self.lines() if v.startswith("provider-")],
                         ["provider-openai", "provider-anthropic", "provider-openrouter", "provider-gateway"])
        self.events.unlink()
        second = self.run_route("live-provider-matrix")
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual([v for v in self.lines() if v.startswith("provider-")], ["provider-gateway"])
        self.assertIn("provider_exact_bindings=openai=true, anthropic=true, openrouter=true, gateway=true", second.stdout)
        self.events.unlink()
        third = self.run_route("live-provider-matrix")
        self.assertEqual(third.returncode, 0, third.stderr)
        self.assertEqual(self.lines(), [], "A completed matrix must not build or allocate a Simulator again")

    def test_high_only_retry_preserves_verified_low_boundary_and_warning_contracts(self):
        first = self.run_route("live-model-differential", FAIL_ROW="profile-high")
        self.assertNotEqual(first.returncode, 0, first.stderr)
        self.assertIn("profile-low", self.lines())
        self.events.unlink()
        second = self.run_route("live-model-differential")
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(self.lines(), ["create", "build", "profile-high"])
        self.assertIn("differential_outcomes=low=expected-model-capability, high=passed", second.stdout)
        self.events.unlink()
        third = self.run_route("live-model-differential")
        self.assertEqual(third.returncode, 0, third.stderr)
        self.assertEqual(self.lines(), [])

    def test_forced_failed_provider_cannot_fall_back_to_its_older_pass(self):
        self.assertEqual(self.run_route("live-provider-matrix").returncode, 0)
        self.events.unlink()
        failure = self.run_route("live-provider-matrix", OPEN_KEYBOARD_VERIFICATION_FRESH="1", FAIL_ROW="provider-gateway")
        self.assertNotEqual(failure.returncode, 0)
        self.events.unlink()
        result = self.run_route("live-provider-matrix")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([v for v in self.lines() if v.startswith("provider-")], ["provider-gateway"])

    def test_successful_low_boundary_is_never_cached_as_expected_failure(self):
        first = self.run_route("live-model-differential", FIXTURE_LOW_OUTCOME="passed")
        self.assertNotEqual(first.returncode, 0, first.stderr)
        self.events.unlink()
        result = self.run_route("live-model-differential")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("profile-low", self.lines())
        self.assertNotIn("profile-high", self.lines())

    def test_reference_smoke_resumes_and_never_crosses_selected_roles(self):
        first = self.run_route("live-gateway-smoke", FAIL_ROW="reference-high")
        self.assertNotEqual(first.returncode, 0)
        self.events.unlink()
        second = self.run_route("live-gateway-smoke")
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(self.lines(), ["create", "build", "reference-high"])
        self.events.unlink()
        third = self.run_route("live-gateway-smoke")
        self.assertEqual(third.returncode, 0, third.stderr)
        self.assertEqual(self.lines(), [])
        fourth = self.run_route("live-gateway-smoke", FIXTURE_REFERENCE_ROLE="low")
        self.assertEqual(fourth.returncode, 0, fourth.stderr)
        self.assertEqual(self.lines(), ["create", "build", "reference-low"])

    def test_changed_seed_invalidates_every_live_row(self):
        self.assertEqual(self.run_route("live-provider-matrix").returncode, 0)
        self.events.unlink()
        self.seed.write_text("different-private-input")
        result = self.run_route("live-provider-matrix")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len([v for v in self.lines() if v.startswith("provider-")]), 4)

    def test_diagnostic_mode_cannot_populate_or_consume_profile_receipts(self):
        first = self.run_route("live-model-differential", FIXTURE_MODE="diagnostic")
        self.assertEqual(first.returncode, 0, first.stderr)
        self.events.unlink()
        second = self.run_route("live-model-differential")
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertIn("profile-low", self.lines())
        self.assertIn("profile-high", self.lines())
        self.events.unlink()
        third = self.run_route("live-model-differential", FIXTURE_MODE="diagnostic", FAIL_ROW="profile-high")
        self.assertEqual(third.returncode, 0, third.stderr)
        self.assertIn("profile-low", self.lines())
        self.assertIn("profile-high", self.lines())
        self.events.unlink()
        fourth = self.run_route("live-model-differential")
        self.assertEqual(fourth.returncode, 0, fourth.stderr)
        self.assertIn("profile-low", self.lines())
        self.assertIn("profile-high", self.lines())


if __name__ == "__main__":
    unittest.main()
