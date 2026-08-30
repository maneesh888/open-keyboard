#!/usr/bin/env bash

openkeyboard_repository_git() (
  local git_environment_name

  # Git exports repository-local variables while running hooks. Clear them so
  # -C selects the repository supplied by this helper instead of the hook's
  # linked-worktree Git directory.
  while IFS= read -r git_environment_name; do
    unset "$git_environment_name"
  done < <(command git rev-parse --local-env-vars)

  command git "$@"
)

openkeyboard_relaunch_with_simulator_lock() {
  local repository_root="$1"
  shift
  local common_directory lock_file

  if [[ "${OPEN_KEYBOARD_SIMULATOR_LOCK_HELD:-}" == "1" ]]; then
    return 0
  fi

  common_directory="$(
    openkeyboard_repository_git -C "$repository_root" \
      rev-parse --path-format=absolute --git-common-dir
  )" || return 1
  lock_file="$common_directory/openkeyboard-simulator-test.lock"

  OPEN_KEYBOARD_SIMULATOR_LOCK_HELD=1 exec ruby -e '
    lock_path = ARGV.shift
    lock = File.open(lock_path, File::RDWR | File::CREAT, 0600)
    unless lock.flock(File::LOCK_EX | File::LOCK_NB)
      warn "Another OpenKeyboard Simulator route is active; waiting for it to finish."
      lock.flock(File::LOCK_EX)
    end
    lock.close_on_exec = false
    exec("/bin/bash", *ARGV)
  ' "$lock_file" "$@"
}

openkeyboard_require_sensitive_live_simulator_ownership() {
  local simulator="${1:-}"

  if [[ "${SENSITIVE_LIVE_SIMULATOR_OWNED:-false}" != "true" || \
        "$simulator" != "${SENSITIVE_LIVE_SIMULATOR:-}" || \
        ! "$simulator" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]; then
    echo "Refusing to operate on a simulator not owned by this live workflow." >&2
    return 1
  fi
}

openkeyboard_delete_sensitive_live_simulator() {
  local owned_simulator

  if [[ -z "${SENSITIVE_LIVE_SIMULATOR:-}" && \
        "${SENSITIVE_LIVE_SIMULATOR_OWNED:-false}" == "false" ]]; then
    return 0
  fi
  if ! openkeyboard_require_sensitive_live_simulator_ownership "${SENSITIVE_LIVE_SIMULATOR:-}"; then
    return 1
  fi
  owned_simulator="${SENSITIVE_LIVE_SIMULATOR:-}"

  xcrun simctl shutdown "$owned_simulator" >/dev/null 2>&1 || true
  if ! xcrun simctl delete "$owned_simulator" >/dev/null 2>&1; then
    echo "Failed to delete the disposable live-test simulator." >&2
    return 1
  fi
  SENSITIVE_LIVE_SIMULATOR=""
  SENSITIVE_LIVE_SIMULATOR_OWNED="false"
}

openkeyboard_cleanup_live_evidence_file() {
  local evidence_file="${1:-}"

  if [[ -n "$evidence_file" ]]; then
    rm -f -- "$evidence_file"
  fi
}

openkeyboard_exit_after_live_evidence_signal() {
  local signal_status="$1"
  local evidence_file="${2:-}"

  trap - EXIT HUP INT TERM
  openkeyboard_cleanup_live_evidence_file "$evidence_file"
  exit "$signal_status"
}

openkeyboard_primary_checkout_root() {
  local repository_root="$1"
  local common_directory canonical_common_directory primary_checkout
  local canonical_primary_checkout primary_git_directory

  common_directory="$(
    openkeyboard_repository_git -C "$repository_root" \
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
    openkeyboard_repository_git -C "$canonical_primary_checkout" \
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

openkeyboard_path_mode() {
  local path="$1"
  local path_mode

  path_mode="$(stat -f '%Lp' "$path" 2>/dev/null)" || \
    path_mode="$(stat -c '%a' "$path" 2>/dev/null)" || {
      echo "Live verification could not validate local seed permissions." >&2
      return 1
    }
  if [[ ! "$path_mode" =~ ^[0-7]{3,4}$ ]]; then
    echo "Live verification could not validate local seed permissions." >&2
    return 1
  fi

  printf '%s\n' "$path_mode"
}

openkeyboard_path_owner() {
  local path="$1"
  local path_owner

  path_owner="$(stat -f '%u' "$path" 2>/dev/null)" || \
    path_owner="$(stat -c '%u' "$path" 2>/dev/null)" || {
      echo "Live verification could not validate local seed ownership." >&2
      return 1
    }
  if [[ ! "$path_owner" =~ ^[0-9]+$ ]]; then
    echo "Live verification could not validate local seed ownership." >&2
    return 1
  fi

  printf '%s\n' "$path_owner"
}

openkeyboard_require_no_extended_acl() {
  local path="$1"
  local acl_listing permission_listing permission_token

  if acl_listing="$(LC_ALL=C command ls -lde -- "$path" 2>/dev/null)"; then
    if [[ "$acl_listing" == *$'\n'* ]]; then
      echo "Live verification refuses local seed paths with extended access-control entries." >&2
      return 1
    fi
    return 0
  fi

  permission_listing="$(LC_ALL=C command ls -ld -- "$path" 2>/dev/null)" || {
    echo "Live verification could not validate local seed access controls." >&2
    return 1
  }
  permission_token="${permission_listing%%[[:space:]]*}"
  if [[ "$permission_token" == *+ ]]; then
    echo "Live verification refuses local seed paths with extended access-control entries." >&2
    return 1
  fi
}

openkeyboard_require_private_seed_permissions() {
  local seed_file="$1"
  local file_mode file_owner current_owner

  file_mode="$(openkeyboard_path_mode "$seed_file")" || return 1
  file_owner="$(openkeyboard_path_owner "$seed_file")" || return 1
  current_owner="$(id -u)"
  if [[ "$file_owner" != "$current_owner" ]]; then
    echo "Live verification requires the local seed file to be owned by the current user." >&2
    return 1
  fi
  if (( (8#$file_mode & 077) != 0 || (8#$file_mode & 0400) == 0 || (8#$file_mode & 0111) != 0 )); then
    echo "Live verification requires local seed permissions to block group and other access (for example, chmod 600)." >&2
    return 1
  fi
  openkeyboard_require_no_extended_acl "$seed_file"
}

openkeyboard_require_trusted_seed_directory() {
  local directory="$1"
  local directory_mode directory_owner current_owner

  directory_mode="$(openkeyboard_path_mode "$directory")" || return 1
  directory_owner="$(openkeyboard_path_owner "$directory")" || return 1
  current_owner="$(id -u)"
  if [[ "$directory_owner" != "$current_owner" ]]; then
    echo "Live verification requires the local seed directory to be owned by the current user." >&2
    return 1
  fi
  if (( (8#$directory_mode & 022) != 0 )); then
    echo "Live verification refuses local seed directories writable by group or other users." >&2
    return 1
  fi
  openkeyboard_require_no_extended_acl "$directory"
}

openkeyboard_require_trusted_seed_directory_chain() {
  local primary_checkout="$1"
  local candidate_parent="$2"
  local directory="$candidate_parent"

  while true; do
    openkeyboard_require_trusted_seed_directory "$directory" || return 1
    if [[ "$directory" == "$primary_checkout" ]]; then
      break
    fi
    directory="$(dirname "$directory")"
    case "$directory" in
      "$primary_checkout"|"$primary_checkout"/*) ;;
      *)
        echo "Live verification could not validate the local seed directory chain." >&2
        return 1
        ;;
    esac
  done
}

openkeyboard_require_local_seed_file() {
  local repository_root="$1"
  local requested_path="$2"
  local execution_checkout primary_checkout seed_root expected_seed candidate candidate_parent
  local canonical_seed_root canonical_candidate_parent canonical_file relative_path

  execution_checkout="$(openkeyboard_repository_git -C "$repository_root" rev-parse --show-toplevel 2>/dev/null)" || {
    echo "Live verification requires a Git checkout." >&2
    return 1
  }
  execution_checkout="$(realpath "$execution_checkout")" || return 1
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
  if [[ "$requested_path" =~ (^|/)\.\.(/|$) ]]; then
    echo "Live verification refuses traversal in a local seed path." >&2
    return 1
  fi

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
  openkeyboard_require_trusted_seed_directory_chain \
    "$primary_checkout" \
    "$canonical_candidate_parent" || return 1

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
  openkeyboard_require_private_seed_permissions "$canonical_file" || return 1

  relative_path="${canonical_file#"$primary_checkout"/}"
  if openkeyboard_repository_git -C "$primary_checkout" ls-files --error-unmatch -- "$relative_path" >/dev/null 2>&1 || \
      openkeyboard_repository_git -C "$execution_checkout" ls-files --error-unmatch -- "$relative_path" >/dev/null 2>&1; then
    echo "Live verification refuses a tracked seed file." >&2
    return 1
  fi
  if ! openkeyboard_repository_git -C "$primary_checkout" check-ignore --quiet -- "$relative_path" || \
      ! openkeyboard_repository_git -C "$execution_checkout" check-ignore --quiet -- "$relative_path"; then
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

openkeyboard_require_exact_live_model() {
  local tested_model="$1"
  local required_model="$2"

  if ! openkeyboard_is_safe_model_id "$tested_model"; then
    echo "Live verification requires one safe, non-empty seed model ID." >&2
    return 1
  fi
  if ! openkeyboard_is_safe_model_id "$required_model"; then
    echo "The required live model must be one safe, non-empty model ID." >&2
    return 1
  fi
  if [[ "$required_model" != "model-agnostic" && "$tested_model" != "$required_model" ]]; then
    echo "The seeded live model does not match the exact required model." >&2
    return 1
  fi
}

openkeyboard_is_safe_model_id() {
  local model_id="$1"

  [[ ${#model_id} -le 255 && "$model_id" =~ ^[A-Za-z0-9][A-Za-z0-9._:/+-]*$ ]]
}

openkeyboard_unset_simulator_gateway_profiles() {
  unset \
    OPEN_KEYBOARD_SIMULATOR_GATEWAY_URL \
    OPEN_KEYBOARD_SIMULATOR_API_KEY \
    OPEN_KEYBOARD_SIMULATOR_MODEL \
    OPEN_KEYBOARD_SIMULATOR_LOW_GATEWAY_URL \
    OPEN_KEYBOARD_SIMULATOR_LOW_API_KEY \
    OPEN_KEYBOARD_SIMULATOR_LOW_MODEL \
    OPEN_KEYBOARD_SIMULATOR_HIGH_GATEWAY_URL \
    OPEN_KEYBOARD_SIMULATOR_HIGH_API_KEY \
    OPEN_KEYBOARD_SIMULATOR_HIGH_MODEL \
    OPEN_KEYBOARD_SIMULATOR_LEGACY_GATEWAY_URL \
    OPEN_KEYBOARD_SIMULATOR_LEGACY_API_KEY \
    OPEN_KEYBOARD_SIMULATOR_LEGACY_MODEL \
    OPEN_KEYBOARD_SIMULATOR_LEGACY_PROFILE_STATE \
    OPEN_KEYBOARD_SIMULATOR_SELECTED_PROFILE
}

openkeyboard_simulator_gateway_profile_state() {
  local profile="$1"
  local prefix url_name api_key_name model_name configured_count=0

  case "$profile" in
    legacy)
      if [[ -n "${OPEN_KEYBOARD_SIMULATOR_LEGACY_PROFILE_STATE:-}" ]]; then
        printf '%s\n' "$OPEN_KEYBOARD_SIMULATOR_LEGACY_PROFILE_STATE"
        return 0
      fi
      prefix="OPEN_KEYBOARD_SIMULATOR"
      ;;
    low) prefix="OPEN_KEYBOARD_SIMULATOR_LOW" ;;
    high) prefix="OPEN_KEYBOARD_SIMULATOR_HIGH" ;;
    *)
      echo "Unsupported simulator gateway profile role." >&2
      return 2
      ;;
  esac
  url_name="${prefix}_GATEWAY_URL"
  api_key_name="${prefix}_API_KEY"
  model_name="${prefix}_MODEL"

  [[ -n "${!url_name:-}" ]] && configured_count=$((configured_count + 1))
  [[ -n "${!api_key_name:-}" ]] && configured_count=$((configured_count + 1))
  [[ -n "${!model_name:-}" ]] && configured_count=$((configured_count + 1))

  case "$configured_count" in
    0) printf '%s\n' "absent" ;;
    3) printf '%s\n' "complete" ;;
    *) printf '%s\n' "partial" ;;
  esac
}

openkeyboard_validate_simulator_gateway_profiles() {
  local profile state prefix model_name model_id complete_count=0

  for profile in legacy low high; do
    state="$(openkeyboard_simulator_gateway_profile_state "$profile")" || return 2
    if [[ "$state" == "partial" ]]; then
      echo "Simulator gateway profile '$profile' is partial; URL, API key, and model are required together." >&2
      return 2
    fi
    if [[ "$state" == "complete" ]]; then
      complete_count=$((complete_count + 1))
      case "$profile" in
        legacy) prefix="OPEN_KEYBOARD_SIMULATOR" ;;
        low) prefix="OPEN_KEYBOARD_SIMULATOR_LOW" ;;
        high) prefix="OPEN_KEYBOARD_SIMULATOR_HIGH" ;;
      esac
      model_name="${prefix}_MODEL"
      model_id="${!model_name}"
      if ! openkeyboard_is_safe_model_id "$model_id"; then
        echo "Simulator gateway profile '$profile' has an unsafe model ID." >&2
        return 2
      fi
    fi
  done

  if [[ "$complete_count" -eq 0 ]]; then
    echo "The simulator gateway seed must define at least one complete credential profile." >&2
    return 2
  fi
}

openkeyboard_require_two_profile_gateway_seed() {
  local low_state high_state
  low_state="$(openkeyboard_simulator_gateway_profile_state low)" || return 2
  high_state="$(openkeyboard_simulator_gateway_profile_state high)" || return 2
  if [[ "$low_state" != "complete" || "$high_state" != "complete" ]]; then
    echo "Two-profile live verification requires complete low and high simulator gateway profiles." >&2
    return 2
  fi
  if [[ "$OPEN_KEYBOARD_SIMULATOR_LOW_MODEL" == "$OPEN_KEYBOARD_SIMULATOR_HIGH_MODEL" ]]; then
    echo "Two-profile live verification requires distinct low and high model IDs." >&2
    return 2
  fi
}

openkeyboard_select_simulator_gateway_profile() {
  local profile="$1"
  local prefix state url_name api_key_name model_name

  case "$profile" in
    legacy)
      if [[ -n "${OPEN_KEYBOARD_SIMULATOR_LEGACY_PROFILE_STATE:-}" ]]; then
        prefix="OPEN_KEYBOARD_SIMULATOR_LEGACY"
      else
        prefix="OPEN_KEYBOARD_SIMULATOR"
      fi
      ;;
    low) prefix="OPEN_KEYBOARD_SIMULATOR_LOW" ;;
    high) prefix="OPEN_KEYBOARD_SIMULATOR_HIGH" ;;
    *)
      echo "Simulator gateway profile selection must be legacy, low, or high." >&2
      return 2
      ;;
  esac
  state="$(openkeyboard_simulator_gateway_profile_state "$profile")" || return 2
  if [[ "$state" != "complete" ]]; then
    echo "The requested simulator gateway profile is not completely configured." >&2
    return 2
  fi

  url_name="${prefix}_GATEWAY_URL"
  api_key_name="${prefix}_API_KEY"
  model_name="${prefix}_MODEL"
  printf -v OPEN_KEYBOARD_SIMULATOR_GATEWAY_URL '%s' "${!url_name}"
  printf -v OPEN_KEYBOARD_SIMULATOR_API_KEY '%s' "${!api_key_name}"
  printf -v OPEN_KEYBOARD_SIMULATOR_MODEL '%s' "${!model_name}"
  OPEN_KEYBOARD_SIMULATOR_SELECTED_PROFILE="$profile"
}

openkeyboard_select_reference_simulator_gateway_profile() {
  local high_state legacy_state
  high_state="$(openkeyboard_simulator_gateway_profile_state high)" || return 2
  legacy_state="$(openkeyboard_simulator_gateway_profile_state legacy)" || return 2

  if [[ "$high_state" == "complete" ]]; then
    openkeyboard_select_simulator_gateway_profile high
  elif [[ "$legacy_state" == "complete" ]]; then
    openkeyboard_select_simulator_gateway_profile legacy
  else
    echo "Ordinary live verification requires the high profile or the legacy fallback profile." >&2
    return 2
  fi
}

openkeyboard_is_allowed_simulator_seed_key() {
  case "$1" in
    OPEN_KEYBOARD_SIMULATOR_GATEWAY_URL|\
    OPEN_KEYBOARD_SIMULATOR_API_KEY|\
    OPEN_KEYBOARD_SIMULATOR_MODEL|\
    OPEN_KEYBOARD_SIMULATOR_LOW_GATEWAY_URL|\
    OPEN_KEYBOARD_SIMULATOR_LOW_API_KEY|\
    OPEN_KEYBOARD_SIMULATOR_LOW_MODEL|\
    OPEN_KEYBOARD_SIMULATOR_HIGH_GATEWAY_URL|\
    OPEN_KEYBOARD_SIMULATOR_HIGH_API_KEY|\
    OPEN_KEYBOARD_SIMULATOR_HIGH_MODEL)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

openkeyboard_load_simulator_gateway_seed() {
  local seed_file="$1"
  local line line_number key value seen_keys legacy_state
  line_number=0
  seen_keys=$'\n'

  openkeyboard_unset_simulator_gateway_profiles

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
      openkeyboard_unset_simulator_gateway_profiles
      return 2
    fi

    key="$(openkeyboard_trim_seed_value "${line%%=*}")"
    value="$(openkeyboard_trim_seed_value "${line#*=}")"

    if [[ ! "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      echo "Invalid seed variable name on line $line_number" >&2
      openkeyboard_unset_simulator_gateway_profiles
      return 2
    fi

    if ! openkeyboard_is_allowed_simulator_seed_key "$key"; then
      echo "Unsupported seed variable on line $line_number: $key" >&2
      openkeyboard_unset_simulator_gateway_profiles
      return 2
    fi

    if [[ "$seen_keys" == *$'\n'"$key"$'\n'* ]]; then
      echo "Duplicate seed variable on line $line_number: $key" >&2
      openkeyboard_unset_simulator_gateway_profiles
      return 2
    fi
    seen_keys+="$key"$'\n'

    if [[ ${#value} -ge 2 && "$value" == \"*\" && "$value" == *\" ]]; then
      value="${value:1:${#value}-2}"
    elif [[ ${#value} -ge 2 && "$value" == \'*\' && "$value" == *\' ]]; then
      value="${value:1:${#value}-2}"
    fi

    printf -v "$key" '%s' "$value"
  done < "$seed_file"

  if ! openkeyboard_validate_simulator_gateway_profiles; then
    openkeyboard_unset_simulator_gateway_profiles
    return 2
  fi

  legacy_state="$(openkeyboard_simulator_gateway_profile_state legacy)" || {
    openkeyboard_unset_simulator_gateway_profiles
    return 2
  }
  OPEN_KEYBOARD_SIMULATOR_LEGACY_PROFILE_STATE="$legacy_state"
  if [[ "$legacy_state" == "complete" ]]; then
    OPEN_KEYBOARD_SIMULATOR_LEGACY_GATEWAY_URL="$OPEN_KEYBOARD_SIMULATOR_GATEWAY_URL"
    OPEN_KEYBOARD_SIMULATOR_LEGACY_API_KEY="$OPEN_KEYBOARD_SIMULATOR_API_KEY"
    OPEN_KEYBOARD_SIMULATOR_LEGACY_MODEL="$OPEN_KEYBOARD_SIMULATOR_MODEL"
  fi
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

openkeyboard_assert_passing_test_summary_count() {
  local expected_count="$1"

  if [[ ! "$expected_count" =~ ^[1-9][0-9]*$ ]]; then
    echo "Live verification requires a positive expected test count." >&2
    return 2
  fi
  ruby -rjson -e '
    expected_count = Integer(ARGV.fetch(0), 10)
    summary = JSON.parse(STDIN.read)
    expected = {
      "result" => "Passed",
      "totalTestCount" => expected_count,
      "passedTests" => expected_count,
      "failedTests" => 0,
      "skippedTests" => 0,
      "expectedFailures" => 0
    }
    mismatches = expected.reject { |key, value| summary[key] == value }
    unless mismatches.empty?
      warn "Live verification did not execute the exact expected passing test count."
      exit 1
    end
  ' "$expected_count"
}

openkeyboard_classify_low_differential_test_summary() {
  ruby -rjson -e '
    summary = JSON.parse(STDIN.read)
    passed = {
      "result" => "Passed",
      "totalTestCount" => 1,
      "passedTests" => 1,
      "failedTests" => 0,
      "skippedTests" => 0,
      "expectedFailures" => 0
    }
    diagnostic = {
      "result" => "Skipped",
      "totalTestCount" => 1,
      "passedTests" => 0,
      "failedTests" => 0,
      "skippedTests" => 1,
      "expectedFailures" => 0
    }
    if passed.all? { |key, value| summary[key] == value }
      puts "expected-model-capability"
    elsif diagnostic.all? { |key, value| summary[key] == value }
      puts "diagnostic-boundary-not-established"
    else
      warn "Low-profile differential verification requires one pass or one explicit diagnostic skip."
      exit 1
    end
  '
}

openkeyboard_live_differential_outcomes_verified() {
  local low_baseline="$1"
  local high_baseline="$2"
  local low_differential="$3"
  local high_differential="$4"
  local low_follow_up="$5"
  local high_follow_up="$6"
  local warning_contracts="$7"

  [[ "$low_baseline" == "passed" ]] &&
    [[ "$high_baseline" == "passed" ]] &&
    [[ "$low_differential" == "expected-model-capability" ]] &&
    [[ "$high_differential" == "passed" ]] &&
    [[ "$low_follow_up" == "passed" ]] &&
    [[ "$high_follow_up" == "passed" ]] &&
    [[ "$warning_contracts" == "verified" ]]
}

openkeyboard_finish_live_differential_run() {
  local execution_mode="$1"
  shift

  if [[ "$execution_mode" != "verification" && "$execution_mode" != "diagnostic" ]]; then
    echo "Live differential execution mode must be verification or diagnostic." >&2
    return 2
  fi
  if [[ "$#" -ne 7 ]]; then
    echo "Live differential completion requires seven outcome values." >&2
    return 2
  fi

  if openkeyboard_live_differential_outcomes_verified "$@"; then
    if [[ "$execution_mode" == "diagnostic" ]]; then
      echo "LIVE_VERIFIED: targeted two-profile diagnostic run complete; required outcomes were verified."
    else
      echo "LIVE_VERIFIED: targeted two-profile live-model differential verification passed."
    fi
    return 0
  fi

  if [[ "$execution_mode" == "diagnostic" ]]; then
    echo "LIVE_UNVERIFIED: targeted two-profile diagnostic run complete; this is not verification."
    return 0
  fi

  echo "LIVE_UNVERIFIED: targeted two-profile live-model differential verification failed; required outcomes were unverified." >&2
  return 1
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

openkeyboard_assert_passing_xcresult_count() {
  local result_bundle="$1"
  local expected_count="$2"
  local summary_file

  summary_file="$(dirname "$result_bundle")/test-summary.json"
  xcrun xcresulttool get test-results summary \
    --path "$result_bundle" \
    --compact > "$summary_file"
  if ! openkeyboard_assert_passing_test_summary_count "$expected_count" < "$summary_file"; then
    rm -f -- "$summary_file"
    return 1
  fi
  rm -f -- "$summary_file"
}

openkeyboard_format_live_diagnostic_attachment() {
  local role="$1"
  local attachment_file="$2"

  if [[ "$role" != "low" && "$role" != "high" ]]; then
    echo "Live diagnostic evidence requires a canonical low or high role." >&2
    return 2
  fi
  if [[ ! -f "$attachment_file" ]]; then
    echo "Live diagnostic evidence attachment is missing." >&2
    return 1
  fi

  ruby - "$role" "$attachment_file" <<'RUBY'
role = ARGV.fetch(0)
path = ARGV.fetch(1)
expected_capabilities = %w[transport grammar rewrite translation]
rows = File.readlines(path, chomp: true).map do |line|
  match = line.match(
    /\ALIVE_GATEWAY_DIAGNOSTIC role=(low|high) capability=(transport|grammar|rewrite|translation) status=(passed|failed) latency_ms=([0-9]+)\z/
  )
  abort "Live diagnostic attachment contains malformed or unsafe evidence." unless match
  abort "Live diagnostic attachment contains the wrong profile role." unless match[1] == role
  [match[2], match[3], Integer(match[4], 10)]
end
abort "Live diagnostic attachment must contain exactly four capability rows." unless rows.length == 4
abort "Live diagnostic attachment capabilities are missing, duplicated, or reordered." unless rows.map(&:first) == expected_capabilities

outcomes = rows.map { |capability, status, _| "#{capability}=#{status}" }.join(", ")
latencies = rows.map { |capability, _, latency| "#{capability}=#{latency}ms" }.join(", ")
puts "diagnostic_outcomes_#{role}=#{outcomes}"
puts "diagnostic_latencies_#{role}=#{latencies}"
RUBY
}

openkeyboard_extract_live_diagnostic_evidence() {
  local result_bundle="$1"
  local role="$2"
  local export_dir manifest_file attachment_name attachment_file

  export_dir="$(dirname "$result_bundle")/live-diagnostics-$role"
  mkdir -p "$export_dir"
  xcrun xcresulttool export attachments \
    --path "$result_bundle" \
    --output-path "$export_dir" >/dev/null
  manifest_file="$export_dir/manifest.json"
  [[ -f "$manifest_file" ]] || {
    echo "Live diagnostic attachment manifest is missing." >&2
    return 1
  }

  attachment_name="$(ruby -rjson - "$manifest_file" "$role" <<'RUBY'
manifest = JSON.parse(File.read(ARGV.fetch(0)))
role = ARGV.fetch(1)
matches = manifest.flat_map do |test|
  next [] unless test.fetch("testIdentifier", "").include?("LiveModelDifferentialTests/testConfiguredProfileDifferentialContract")
  test.fetch("attachments", []).select do |attachment|
    attachment.fetch("suggestedHumanReadableName", "").start_with?("live-gateway-diagnostics-#{role}")
  end
end
abort "Expected exactly one retained live diagnostic attachment." unless matches.length == 1
name = matches.first.fetch("exportedFileName")
abort "Live diagnostic attachment filename is unsafe." unless File.basename(name) == name
puts name
RUBY
)" || return 1
  attachment_file="$export_dir/$attachment_name"
  openkeyboard_format_live_diagnostic_attachment "$role" "$attachment_file"
}

openkeyboard_classify_low_differential_xcresult() {
  local result_bundle="$1"
  local summary_file outcome

  summary_file="$(dirname "$result_bundle")/test-summary.json"
  xcrun xcresulttool get test-results summary \
    --path "$result_bundle" \
    --compact > "$summary_file"
  if ! outcome="$(openkeyboard_classify_low_differential_test_summary < "$summary_file")"; then
    rm -f -- "$summary_file"
    return 1
  fi
  rm -f -- "$summary_file"
  printf '%s\n' "$outcome"
}
