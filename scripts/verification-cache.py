#!/usr/bin/env python3
"""Private, same-head verification receipts. A cache miss never means a pass."""

import argparse
import contextlib
import fcntl
import hashlib
import hmac
import json
import os
from pathlib import Path
import platform
import re
import secrets
import stat
import subprocess
import sys
import tempfile
import time

SCHEMA = 1
MAX_AGE = 24 * 60 * 60
BUILD_ENV = (
    "PATH", "DEVELOPER_DIR", "SDKROOT", "TOOLCHAINS", "JAVA_HOME",
    "ANDROID_HOME", "ANDROID_SDK_ROOT", "GRADLE_USER_HOME", "KONAN_DATA_DIR",
    "SWIFT_EXEC", "CC", "CXX", "ARCHS", "CONFIGURATION", "CFLAGS", "CPPFLAGS",
    "CXXFLAGS", "LDFLAGS", "SWIFTFLAGS", "CPATH", "LIBRARY_PATH", "NODE_OPTIONS",
    "MACOSX_DEPLOYMENT_TARGET", "IPHONEOS_DEPLOYMENT_TARGET", "JAVA_TOOL_OPTIONS",
    "JDK_JAVA_OPTIONS", "GRADLE_OPTS", "KOTLIN_OPTS",
)
STAGES = {
    "contract", "core", "build", "deterministic-ui", "warning-contracts",
    "provider-openai", "provider-anthropic", "provider-openrouter", "provider-gateway",
    "profile-low", "profile-high", "reference-low", "reference-high", "reference-legacy",
}
DIAGNOSTICS = re.compile(
    r"diagnostic_outcomes_(low|high)=transport=passed, grammar=passed, "
    r"rewrite=passed, translation=(passed|failed)"
)


class CacheError(Exception):
    pass


def encoded(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def repository_environment():
    environment = os.environ.copy()
    # Hook-local Git variables must not redirect either fingerprinting or execution.
    for name in ("GIT_DIR", "GIT_COMMON_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE",
                 "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_PREFIX",
                 "GIT_CONFIG", "GIT_CONFIG_PARAMETERS", "GIT_CONFIG_COUNT", "GIT_IMPLICIT_WORK_TREE",
                 "GIT_GRAFT_FILE", "GIT_NO_REPLACE_OBJECTS", "GIT_REPLACE_REF_BASE", "GIT_SHALLOW_FILE"):
        environment.pop(name, None)
    for name in list(environment):
        if name.startswith(("GIT_CONFIG_KEY_", "GIT_CONFIG_VALUE_")):
            environment.pop(name)
    return environment


def output(command, cwd=None):
    environment = repository_environment() if command[0] == "git" else os.environ.copy()
    return subprocess.check_output(command, cwd=cwd, env=environment,
                                   stderr=subprocess.DEVNULL).decode().strip()


def private(path, directory=False):
    info = path.lstat()
    expected = 0o700 if directory else 0o600
    if (info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != expected
            or not (stat.S_ISDIR(info.st_mode) if directory else stat.S_ISREG(info.st_mode))
            or (not directory and info.st_nlink != 1)):
        raise CacheError("unsafe private state")
    if sys.platform == "darwin":
        listing = output(["/bin/ls", "-lde", str(path)])
        if re.search(r"^\s*\d+:", listing, re.MULTILINE):
            raise CacheError("extended ACL on private state")


def read_private(path):
    private(path)
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, "rb") as stream:
        opened = os.fstat(stream.fileno())
        current = path.lstat()
        if (opened.st_dev, opened.st_ino) != (current.st_dev, current.st_ino):
            raise CacheError("private state changed while opening")
        return stream.read()


def write_private(path, data):
    if path.exists() or path.is_symlink():
        private(path)
    fd, temporary = tempfile.mkstemp(prefix=".receipt-", dir=path.parent)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def toolchain():
    # Runtime identifiers/builds matter; lastUsage and other volatile inventory do not.
    runtimes = json.loads(output(["xcrun", "simctl", "list", "runtimes", "--json"]))
    versions = {
        "xcode": output(["xcodebuild", "-version"]),
        "swift": output(["xcrun", "swift", "--version"]),
        "host": platform.platform(),
        "python": platform.python_version(),
        "runtimes": sorted(
            (r["identifier"], r.get("buildversion"), r.get("isAvailable"))
            for r in runtimes["runtimes"]
        ),
    }
    for name, command in (("node", ["node", "--version"]), ("java", ["java", "-version"])):
        try:
            result = subprocess.run(command, capture_output=True, check=False)
            versions[name] = [result.returncode, result.stdout.decode(errors="replace"),
                              result.stderr.decode(errors="replace")]
        except FileNotFoundError:
            versions[name] = "not-installed"
    return versions


def snapshot(repo, seed_paths):
    head = output(["git", "rev-parse", "HEAD"], repo)
    if not re.fullmatch(r"[0-9a-f]{40}", head):
        raise CacheError("invalid head")
    expected_head = os.environ.get("OPEN_KEYBOARD_VERIFICATION_EXPECTED_SHA", head)
    if expected_head != head:
        raise CacheError("verification head changed")
    if output(["git", "status", "--porcelain", "--untracked-files=all"], repo):
        return None
    base_ref = (os.environ.get("OPEN_KEYBOARD_CHECK_BASE_REF")
                or os.environ.get("OPEN_KEYBOARD_LIVE_BASE_REF") or "origin/main")
    base = output(["git", "rev-parse", "--verify", base_ref + "^{commit}"], repo)
    state = {"schema": SCHEMA, "head": head, "base": base,
             "toolchain": toolchain(),
             "environment": {name: os.environ.get(name) for name in BUILD_ENV}}
    # Only the keyed digest is retained. Seed bytes and environment values never leave memory.
    seed_data = []
    for path in seed_paths:
        seed_data.append([str(path), read_private(path).hex()])
    state["private_inputs"] = seed_data
    return state


class Cache:
    def __init__(self, repo):
        self.repo = Path(repo).resolve()
        if Path(output(["git", "rev-parse", "--show-toplevel"], self.repo)).resolve() != self.repo:
            raise CacheError("verification repository root mismatch")
        common = Path(output(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"], self.repo))
        self.root = common / "openkeyboard-verification-cache"
        self.root.mkdir(mode=0o700, exist_ok=True)
        private(self.root, directory=True)
        with self.locked():
            self.key()

    @contextlib.contextmanager
    def locked(self, stage=None):
        if stage is not None and stage not in STAGES:
            raise CacheError("unknown verification stage")
        lock = self.root / ("lock" if stage is None else "run-" + stage + ".lock")
        fd = os.open(lock, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
        try:
            private(lock)
            fcntl.flock(fd, fcntl.LOCK_EX)
            yield
        finally:
            os.close(fd)

    def key(self):
        path = self.root / "key"
        if not path.exists() and not path.is_symlink():
            fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
            with os.fdopen(fd, "wb") as stream:
                stream.write(secrets.token_bytes(32))
        key = read_private(path)
        if len(key) != 32:
            raise CacheError("invalid receipt key")
        return key

    def binding(self, seeds):
        state = snapshot(self.repo, seeds)
        return None if state is None else hmac.new(self.key(), encoded(state), hashlib.sha256).hexdigest()

    def location(self, binding, stage):
        if stage not in STAGES:
            raise CacheError("unknown verification stage")
        if not re.fullmatch(r"[0-9a-f]{64}", binding):
            raise CacheError("invalid binding")
        return self.root / (binding + "-" + stage + ".json")

    def remove(self, binding, stage):
        path = self.location(binding, stage)
        if path.exists() or path.is_symlink():
            private(path)
            path.unlink()

    def get(self, binding, stage):
        path = self.location(binding, stage)
        if not path.exists() and not path.is_symlink():
            return None
        raw = read_private(path)
        try:
            envelope = json.loads(raw)
            if set(envelope) != {"record", "mac"}:
                return None
            record = envelope["record"]
            expected = hmac.new(self.key(), encoded(record), hashlib.sha256).hexdigest()
            if not hmac.compare_digest(expected, envelope["mac"]):
                return None
            if set(record) != {"schema", "binding", "stage", "created", "value"}:
                return None
            age = time.time() - record["created"]
            if (record["schema"] != SCHEMA or record["binding"] != binding
                    or record["stage"] != stage or not 0 <= age <= MAX_AGE):
                return None
            validate_value(stage, record["value"])
            return record["value"]
        except (ValueError, TypeError, KeyError, CacheError):
            return None

    def put(self, binding, stage, value):
        validate_value(stage, value)
        record = {"schema": SCHEMA, "binding": binding, "stage": stage,
                  "created": time.time(), "value": value}
        envelope = {"record": record,
                    "mac": hmac.new(self.key(), encoded(record), hashlib.sha256).hexdigest()}
        write_private(self.location(binding, stage), encoded(envelope))


def validate_value(stage, value):
    if stage in {"profile-low", "profile-high"}:
        match = DIAGNOSTICS.fullmatch(value)
        if not match or stage != "profile-" + match[1]:
            raise CacheError("invalid profile receipt")
    elif value != "passed":
        raise CacheError("only passing outcomes can be retained")


def context_file(path):
    context = json.loads(read_private(path))
    if set(context) != {"repo", "seeds", "binding", "fresh"}:
        raise CacheError("invalid verification context")
    return context


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="operation", required=True)
    init = sub.add_parser("context")
    init.add_argument("repo", type=Path)
    init.add_argument("file", type=Path)
    init.add_argument("seeds", nargs="*", type=Path)
    for name in ("get", "put", "invalidate"):
        command = sub.add_parser(name)
        command.add_argument("context", type=Path)
        command.add_argument("stage", choices=sorted(STAGES))
        if name == "put":
            command.add_argument("value", nargs="?", default="passed")
    run = sub.add_parser("run")
    run.add_argument("repo", type=Path)
    run.add_argument("stage", choices=sorted(STAGES))
    run.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.operation == "context":
        cache = Cache(args.repo)
        seeds = [p.resolve() for p in args.seeds]
        with cache.locked():
            binding = cache.binding(seeds)
            write_private(args.file, encoded({"repo": str(cache.repo),
                          "seeds": [str(p) for p in seeds], "binding": binding,
                          "fresh": os.environ.get("OPEN_KEYBOARD_VERIFICATION_FRESH") == "1"}))
        return 0
    if args.operation == "run":
        cache = Cache(args.repo)
        command = args.command[1:] if args.command[:1] == ["--"] else args.command
        expected_commands = {
            "contract": [str(cache.repo / "scripts/check-semantic-prompt-contract.sh")],
            "core": [str(cache.repo / "scripts/ios/test.sh"), "core"],
            "build": [str(cache.repo / "scripts/ios/test.sh"), "build"],
            "deterministic-ui": [str(cache.repo / "scripts/ios/test.sh"), "deterministic-ui"],
        }
        expected = expected_commands.get(args.stage)
        if not command or expected is None or [str(Path(command[0]).resolve()), *command[1:]] != expected:
            raise CacheError("command does not match verification stage")
        command = expected
        # Never hold the receipt-metadata lock while a command waits for the Simulator
        # lock: live routes hold the Simulator lock before accessing their receipts.
        with cache.locked(args.stage):
            binding = cache.binding([])
            if binding is not None:
                if os.environ.get("OPEN_KEYBOARD_VERIFICATION_FRESH") != "1" and cache.get(binding, args.stage):
                    print("Reusing same-head passing verification: " + args.stage, flush=True)
                    return 0
                cache.remove(binding, args.stage)
            status = subprocess.run(command, cwd=cache.repo, env=repository_environment(), check=False).returncode
            if status:
                return status if status > 0 else 128 - status
            if binding is not None:
                if cache.binding([]) != binding:
                    raise CacheError("verification inputs changed during execution")
                cache.put(binding, args.stage, "passed")
        return 0
    context = context_file(args.context)
    if context["binding"] is None:
        return 1 if args.operation == "get" else 0
    cache = Cache(context["repo"])
    with cache.locked():
        binding = cache.binding([Path(p) for p in context["seeds"]])
        if binding != context["binding"]:
            raise CacheError("verification inputs changed during execution")
        if args.operation == "invalidate":
            cache.remove(binding, args.stage)
        elif args.operation == "get":
            value = None if context["fresh"] else cache.get(binding, args.stage)
            if value is None:
                # A forced rerun must invalidate an older pass before a new failure can occur.
                cache.remove(binding, args.stage)
                return 1
            print(value)
        else:
            cache.put(binding, args.stage, args.value)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (CacheError, OSError, ValueError, subprocess.SubprocessError):
        # Exceptions may contain private paths/inputs. Never expose them in retained output.
        print("Verification receipt validation failed; no cached pass was accepted.", file=sys.stderr)
        sys.exit(2)
