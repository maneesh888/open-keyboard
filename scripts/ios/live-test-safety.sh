#!/usr/bin/env bash

openkeyboard_restore_booted_simulator() {
  local simulator="$1"

  xcrun simctl boot "$simulator" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$simulator" -b >/dev/null
}

openkeyboard_primary_checkout_root() {
  local repository_root="$1"
  local common_directory canonical_common_directory primary_checkout
  local canonical_primary_checkout primary_git_directory

  common_directory="$(
    git -C "$repository_root" \
      rev-parse --path-format=absolute --git-common-dir 2>/dev/null
  )" || {
    echo "Live verification requires a Git checkout." >&2
    return 1
  }
  canonical_common_directory="$(realpath "$common_directory")" || {
    echo "Live verification could not resolve the Git common directory." >&2
    return 1
  }

  case "$canonical_common_directory" in
    */.git) ;;
    *)
      echo "Live verification requires a primary checkout with a .git directory." >&2
      return 1
      ;;
  esac

  primary_checkout="${canonical_common_directory%/.git}"
  canonical_primary_checkout="$(realpath "$primary_checkout")" || {
    echo "Live verification could not resolve the primary checkout." >&2
    return 1
  }
  primary_git_directory="$(
    git -C "$canonical_primary_checkout" \
      rev-parse --path-format=absolute --git-dir 2>/dev/null
  )" || {
    echo "Live verification could not validate the primary checkout." >&2
    return 1
  }
  primary_git_directory="$(realpath "$primary_git_directory")" || return 1
  if [[ "$primary_git_directory" != "$canonical_common_directory" ]]; then
    echo "Live verification could not validate the primary checkout's Git directory." >&2
    return 1
  fi

  printf '%s\n' "$canonical_primary_checkout"
}

openkeyboard_require_local_seed_file() {
  local repository_root="$1"
  local requested_path="$2"
  local primary_checkout seed_root expected_seed candidate candidate_parent
  local canonical_seed_root canonical_candidate_parent canonical_file relative_path

  primary_checkout="$(openkeyboard_primary_checkout_root "$repository_root")" || return 1
  seed_root="$primary_checkout/.agent/local-seeds"
  expected_seed="$seed_root/openkeyboard-gateway.env"

  if [[ ! -d "$seed_root" ]]; then
    echo "Live gateway seed file is missing: $expected_seed" >&2
    return 1
  fi
  canonical_seed_root="$(realpath "$seed_root")" || return 1
  if [[ "$canonical_seed_root" != "$seed_root" ]]; then
    echo "Live verification requires .agent/local-seeds to remain inside the primary checkout." >&2
    return 1
  fi

  case "$requested_path" in
    /*) candidate="$requested_path" ;;
    *) candidate="$primary_checkout/$requested_path" ;;
  esac

  candidate_parent="$(dirname "$candidate")"
  canonical_candidate_parent="$(realpath "$candidate_parent" 2>/dev/null)" || {
    echo "Live verification requires a canonical seed beneath the primary checkout's .agent/local-seeds/." >&2
    return 1
  }
  case "$canonical_candidate_parent" in
    "$canonical_seed_root"|"$canonical_seed_root"/*) ;;
    *)
      echo "Live verification requires a canonical seed beneath the primary checkout's .agent/local-seeds/." >&2
      return 1
      ;;
  esac

  if [[ ! -e "$candidate" && ! -L "$candidate" ]]; then
    echo "Live gateway seed file is missing: $canonical_candidate_parent/$(basename "$candidate")" >&2
    return 1
  fi
  if [[ ! -f "$candidate" ]]; then
    echo "Live verification requires a regular local seed file." >&2
    return 1
  fi
  canonical_file="$(realpath "$candidate")" || {
    echo "Live verification refuses an unresolved seed symlink." >&2
    return 1
  }

  case "$canonical_file" in
    "$canonical_seed_root"/*) ;;
    *)
      echo "Live verification requires a canonical seed beneath the primary checkout's .agent/local-seeds/." >&2
      return 1
      ;;
  esac

  relative_path="${canonical_file#"$primary_checkout"/}"
  if git -C "$primary_checkout" ls-files --error-unmatch -- "$relative_path" >/dev/null 2>&1; then
    echo "Live verification refuses a tracked seed file." >&2
    return 1
  fi
  if ! git -C "$primary_checkout" check-ignore --quiet -- "$relative_path"; then
    echo "Live verification requires an ignored local seed file." >&2
    return 1
  fi

  printf '%s\n' "$canonical_file"
}

openkeyboard_trim_seed_value() {
  local value="$1"

  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

openkeyboard_is_allowed_simulator_seed_key() {
  case "$1" in
    OPEN_KEYBOARD_SIMULATOR_GATEWAY_URL|OPEN_KEYBOARD_SIMULATOR_API_KEY|OPEN_KEYBOARD_SIMULATOR_MODEL)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

openkeyboard_load_simulator_gateway_seed() {
  local seed_file="$1"
  local line line_number key value
  line_number=0

  unset \
    OPEN_KEYBOARD_SIMULATOR_GATEWAY_URL \
    OPEN_KEYBOARD_SIMULATOR_API_KEY \
    OPEN_KEYBOARD_SIMULATOR_MODEL

  while IFS= read -r line || [[ -n "$line" ]]; do
    line_number=$((line_number + 1))
    line="$(openkeyboard_trim_seed_value "$line")"

    if [[ -z "$line" || "$line" == \#* ]]; then
      continue
    fi

    if [[ "$line" == export[[:space:]]* ]]; then
      line="$(openkeyboard_trim_seed_value "${line#export}")"
    fi

    if [[ "$line" != *=* ]]; then
      echo "Invalid seed file line $line_number: expected KEY=value" >&2
      return 2
    fi

    key="$(openkeyboard_trim_seed_value "${line%%=*}")"
    value="$(openkeyboard_trim_seed_value "${line#*=}")"

    if [[ ! "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      echo "Invalid seed variable name on line $line_number" >&2
      return 2
    fi

    if ! openkeyboard_is_allowed_simulator_seed_key "$key"; then
      echo "Unsupported seed variable on line $line_number: $key" >&2
      return 2
    fi

    if [[ ${#value} -ge 2 && "$value" == \"*\" && "$value" == *\" ]]; then
      value="${value:1:${#value}-2}"
    elif [[ ${#value} -ge 2 && "$value" == \'*\' && "$value" == *\' ]]; then
      value="${value:1:${#value}-2}"
    fi

    printf -v "$key" '%s' "$value"
  done < "$seed_file"
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
