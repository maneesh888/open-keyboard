#!/usr/bin/env bash

# The only supported legacy source is the last identity-bearing validator on main.
# These are source-code object IDs, never hashes of private configuration.
openkeyboard_prepare_live_validators() {
  local base_sha="$1" validator_root="$2" repository_root="$3"
  local name legacy_blob
  mkdir -p "$validator_root"
  for name in live-impact.sh validate-pr-live-evidence.sh; do
    git -C "$repository_root" show "$base_sha:scripts/$name" > "$validator_root/$name" || return 1
    chmod +x "$validator_root/$name"
  done
  if grep -Fq 'readonly OPEN_KEYBOARD_REDACTED_LIVE_EVIDENCE_SCHEMA=1' "$validator_root/validate-pr-live-evidence.sh"; then
    echo "Trusted base uses the private assertion schema."
    return 0
  fi
  if [[ "$base_sha" != 6619f0bb1f3aa8306a4b1dc94b2fdd514ee1f6f6 ]]; then
    echo "Unknown legacy base; migration requires the explicitly reviewed base SHA." >&2
    return 1
  fi
  legacy_blob="$(git hash-object "$validator_root/validate-pr-live-evidence.sh")"
  if [[ "$legacy_blob" != 249c196c6eb2ca94a397896e7cfd448463f463ca ]]; then
    echo "Unknown legacy live validator; a separately reviewed migration is required." >&2
    return 1
  fi
  # Preserve all trusted semantic/head/target checks. The single schema accommodation permits
  # an explicit withheld timing value; it never inserts a measurement or changes an outcome.
  python3 - "$validator_root/validate-pr-live-evidence.sh" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
s = p.read_text()
old = '! "$live_profile_latencies" =~ ^low=[0-9]+([.][0-9]{3})?s,\\ high=[0-9]+([.][0-9]{3})?s$'
new = '( "$live_profile_latencies" != "withheld" && ' + old + ' )'
assert s.count(old) == 1, 'Legacy timing schema changed'
p.write_text(s.replace(old, new))
PY
  cp "$repository_root/scripts/validate-pr-live-evidence.sh" "$validator_root/private-live-evidence.sh" || return 1
  chmod +x "$validator_root/private-live-evidence.sh" || return 1
  echo "Pinned legacy privacy migration: role assertions plus trusted semantic checks; timings withheld."
}

openkeyboard_validate_live_snapshot() (
  set -euo pipefail
  local body_file="$1" head_sha="$2" impact="$3" validator_root="$4"
  local projection=""
  if [[ ! -f "$validator_root/private-live-evidence.sh" ]]; then
    HEAD_SHA="$head_sha" LIVE_IMPACT="$impact" PR_BODY="$(< "$body_file")" \
      "$validator_root/validate-pr-live-evidence.sh"
    return
  fi

  # Validate the complete current schema first, including duplicates and prohibited fields.
  HEAD_SHA="$head_sha" LIVE_IMPACT="$impact" PR_BODY="$(< "$body_file")" \
    "$validator_root/private-live-evidence.sh" || return 1
  [[ "$impact" != none ]] || return 0
  projection="$(mktemp)"
  trap 'rm -f -- "$projection"' EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  chmod 600 "$projection"
  python3 - "$body_file" "$projection" "$impact" <<'PY'
import pathlib, sys
source, destination, impact = sys.argv[1:]
# The aliases denote public roles, not selected model identifiers. This temporary projection
# checks the trusted validator's old equality grammar; the candidate already verified assertions.
roles = 'low=LOW, high=HIGH' if impact == 'gateway-differential' else 'REFERENCE'
lines = []
for line in pathlib.Path(source).read_text().splitlines():
    if line.startswith(('- Local live verification: ', '- Live verification target: ',
                        '- Exact live-tested head: ', '- Live-model substitutions: ',
                        '- Live plain-text grammar verification: ', '- Live summarize outcomes: ',
                        '- Live continue-writing outcomes: ', '- Live baseline outcomes: ',
                        '- Live differential outcomes: ', '- Live follow-up outcomes: ',
                        '- Live operation-scoped warning contracts: ')):
        lines.append(line)
lines += ['- Required live models: ' + roles, '- Exact live-tested models: ' + roles,
          '- Live profile latencies: ' + ('withheld' if impact == 'gateway-differential' else 'not required'),
          '- No credential or gateway response body retained.',
          '- Trust boundary: local execution is contributor-attested; GitHub verifies retained exact-head evidence only.']
pathlib.Path(destination).write_text('\n'.join(lines) + '\n')
PY
  HEAD_SHA="$head_sha" LIVE_IMPACT="$impact" PR_BODY="$(< "$projection")" \
    "$validator_root/validate-pr-live-evidence.sh"
)
