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
