#!/usr/bin/env bash

openkeyboard_require_local_seed_file() {
  local repository_root="$1"
  local requested_path="$2"
  local canonical_root canonical_seed_root candidate canonical_file relative_path

  canonical_root="$(realpath "$repository_root")" || return 1
  canonical_seed_root="$(realpath "$canonical_root/.agent/local-seeds")" || {
    echo "Live verification requires the ignored .agent/local-seeds directory." >&2
    return 1
  }
  case "$canonical_seed_root" in
    "$canonical_root"/.agent/local-seeds) ;;
    *)
      echo "Live verification requires .agent/local-seeds to remain inside the repository." >&2
      return 1
      ;;
  esac

  case "$requested_path" in
    /*) candidate="$requested_path" ;;
    *) candidate="$canonical_root/$requested_path" ;;
  esac

  if [[ ! -f "$candidate" ]]; then
    echo "Live gateway seed file is missing." >&2
    return 1
  fi
  canonical_file="$(realpath "$candidate")" || return 1

  case "$canonical_file" in
    "$canonical_seed_root"/*) ;;
    *)
      echo "Live verification requires a canonical seed beneath .agent/local-seeds/." >&2
      return 1
      ;;
  esac

  relative_path="${canonical_file#"$canonical_root"/}"
  if ! git -C "$canonical_root" check-ignore --quiet -- "$relative_path"; then
    echo "Live verification requires an ignored local seed file." >&2
    return 1
  fi
  if git -C "$canonical_root" ls-files --error-unmatch -- "$relative_path" >/dev/null 2>&1; then
    echo "Live verification refuses a tracked seed file." >&2
    return 1
  fi

  printf '%s\n' "$canonical_file"
}

openkeyboard_assert_single_passing_test_summary() {
  ruby -rjson -e '
    summary = JSON.parse(STDIN.read)
    expected = {
      "result" => "Passed",
      "totalTestCount" => 1,
      "passedTests" => 1,
      "failedTests" => 0,
      "skippedTests" => 0,
      "expectedFailures" => 0
    }
    mismatches = expected.reject { |key, value| summary[key] == value }
    unless mismatches.empty?
      warn "Live verification requires exactly one executed, passing, non-skipped test."
      exit 1
    end
  '
}

openkeyboard_assert_single_passing_xcresult() {
  local result_bundle="$1"
  local summary_file

  summary_file="$(dirname "$result_bundle")/test-summary.json"
  xcrun xcresulttool get test-results summary \
    --path "$result_bundle" \
    --compact > "$summary_file"
  if ! openkeyboard_assert_single_passing_test_summary < "$summary_file"; then
    rm -f -- "$summary_file"
    return 1
  fi
  rm -f -- "$summary_file"
}
