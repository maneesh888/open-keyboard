#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE="$(mktemp -d)"
trap 'rm -rf -- "$FIXTURE"' EXIT
ruby - "$ROOT/.github/workflows/live.yml" "$FIXTURE" <<'RUBY'
require 'yaml'
jobs = YAML.load_file(ARGV[0]).fetch('jobs')
route = jobs.fetch('live-policy-routing').fetch('steps').find { |x| x['id'] == 'route' }
guard = jobs.fetch('required-live-verification').fetch('steps').first
abort 'Approval must precede checkout' unless guard['name'] == 'Verify actual migration approval before candidate checkout'
File.write(File.join(ARGV[1], 'route.sh'), route.fetch('run'))
File.write(File.join(ARGV[1], 'guard.sh'), guard.fetch('run'))
abort 'Required live check must remain independent' if jobs.fetch('required-live-verification').key?('needs')
abort 'Missing conditional migration job' unless jobs.fetch('migration-approval')['if'] == "needs.live-policy-routing.outputs.migration_ready == 'true'"
abort 'Unsafe migration environment routing' unless jobs.fetch('migration-approval')['environment'] == '${{ needs.live-policy-routing.outputs.environment }}'
RUBY
mkdir -p "$FIXTURE/bin"
cat > "$FIXTURE/bin/gh" <<'MOCK'
#!/bin/bash
set -euo pipefail
case "$2" in
  */environments/live-policy-migration)
    [[ "$SCENARIO" != missing ]] || exit 1
    if [[ "$SCENARIO" == unprotected ]]; then
      echo '{"id":201,"name":"live-policy-migration","protection_rules":[]}'
    elif [[ "$SCENARIO" == wrong-reviewer ]]; then
      echo '{"id":201,"name":"live-policy-migration","protection_rules":[{"type":"required_reviewers","reviewers":[{"type":"User","reviewer":{"id":2}}]}]}'
    else
      echo '{"id":201,"name":"live-policy-migration","protection_rules":[{"type":"required_reviewers","reviewers":[{"type":"User","reviewer":{"id":1}}]}]}'
    fi ;;
  */approvals)
    case "$SCENARIO" in
      no-approval) echo '[]' ;;
      conflicting) echo '[{"state":"approved","user":{"id":1},"environments":[{"id":201,"name":"live-policy-migration"}]},{"state":"rejected","user":{"id":1},"environments":[{"id":201,"name":"live-policy-migration"}]}]' ;;
      recreated) echo '[{"state":"approved","user":{"id":1},"environments":[{"id":200,"name":"live-policy-migration"}]}]' ;;
      wrong-approver) echo '[{"state":"approved","user":{"id":2},"environments":[{"id":201,"name":"live-policy-migration"}]}]' ;;
      rejected) echo '[{"state":"rejected","user":{"id":1},"environments":[{"id":201,"name":"live-policy-migration"}]}]' ;;
      wrong-environment) echo '[{"state":"approved","user":{"id":1},"environments":[{"name":"live-policy"}]}]' ;;
      *) echo '[{"state":"approved","user":{"id":1},"environments":[{"id":201,"name":"live-policy-migration"}]}]' ;;
    esac ;;
  */actions/runs/10)
    if [[ "$SCENARIO" == wrong-head ]]; then
      echo '{"head_sha":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","event":"pull_request"}'
    else
      echo '{"head_sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","event":"pull_request"}'
    fi ;;
  *) exit 2 ;;
esac
MOCK
chmod +x "$FIXTURE/bin/gh"
export PATH="$FIXTURE/bin:$PATH" RUNNER_TEMP="$FIXTURE" GITHUB_OUTPUT="$FIXTURE/outputs"
export GITHUB_REPOSITORY=fixture/repo GITHUB_RUN_ID=10 OWNER_ID=1 ROUTING_RESULT=success
export PR_BASE_SHA=6619f0bb1f3aa8306a4b1dc94b2fdd514ee1f6f6
export PR_HEAD_SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
for scenario in valid missing unprotected wrong-reviewer no-approval wrong-approver rejected wrong-environment wrong-head conflicting recreated; do
  export SCENARIO="$scenario"
  : > "$GITHUB_OUTPUT"
  bash -e -o pipefail "$FIXTURE/route.sh" > "$FIXTURE/output" 2>&1
  selected="$(sed -n 's/^environment=//p' "$GITHUB_OUTPUT" | tail -1)"
  export MIGRATION_READY="$(sed -n 's/^migration_ready=//p' "$GITHUB_OUTPUT" | tail -1)"
  case "$scenario" in
    missing|unprotected|wrong-reviewer)
      [[ "$selected" == live-policy && "$MIGRATION_READY" == false ]] || {
        echo "Missing protection would implicitly create or select an unsafe environment." >&2; exit 1;
      } ;;
    *) [[ "$selected" == live-policy-migration && "$MIGRATION_READY" == true ]] ;;
  esac
  result=0
  bash -e -o pipefail "$FIXTURE/guard.sh" >> "$FIXTURE/output" 2>&1 || result=$?
  if [[ "$scenario" == valid ]]; then
    [[ "$result" == 0 ]] || { echo "Valid migration approval refused." >&2; exit 1; }
  elif [[ "$result" == 0 ]]; then
    echo "Invalid migration authority accepted: $scenario" >&2; exit 1
  fi
done
# Normal trusted-base operation selects the existing environment without probing/creating migration.
export PR_BASE_SHA=cccccccccccccccccccccccccccccccccccccccc SCENARIO=missing
: > "$GITHUB_OUTPUT"
bash -e -o pipefail "$FIXTURE/route.sh" >/dev/null
[[ "$(sed -n 's/^environment=//p' "$GITHUB_OUTPUT" | tail -1)" == live-policy ]]
echo "Live migration approval regression tests passed (mock GitHub)."
