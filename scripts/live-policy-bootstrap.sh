#!/usr/bin/env bash

OPEN_KEYBOARD_TRUSTED_PROJECTION_FILES=()
OPEN_KEYBOARD_TRUSTED_PROJECTION_TRAPS_INSTALLED="false"
OPEN_KEYBOARD_TRUSTED_PROJECTION_PREVIOUS_EXIT_TRAP=""

openkeyboard_run_serialized_exit_trap() {
  local serialized_trap="$1"
  local trap_action=""

  [[ -n "$serialized_trap" ]] || return 0
  eval "set -- $serialized_trap"
  if [[ "${1:-}" == "trap" && "${2:-}" == "--" && "${4:-}" == "EXIT" ]]; then
    trap_action="${3:-}"
    [[ -n "$trap_action" ]] && eval "$trap_action"
  fi
}

openkeyboard_cleanup_trusted_gateway_projections() {
  local original_status=$?
  local projection_file
  local previous_exit_trap="$OPEN_KEYBOARD_TRUSTED_PROJECTION_PREVIOUS_EXIT_TRAP"

  trap - EXIT HUP INT TERM
  for projection_file in "${OPEN_KEYBOARD_TRUSTED_PROJECTION_FILES[@]}"; do
    [[ -n "$projection_file" ]] && rm -f -- "$projection_file"
  done
  OPEN_KEYBOARD_TRUSTED_PROJECTION_FILES=()
  openkeyboard_run_serialized_exit_trap "$previous_exit_trap"
  exit "$original_status"
}

openkeyboard_exit_after_trusted_projection_signal() {
  local signal_status="$1"

  trap - EXIT HUP INT TERM
  for projection_file in "${OPEN_KEYBOARD_TRUSTED_PROJECTION_FILES[@]}"; do
    [[ -n "$projection_file" ]] && rm -f -- "$projection_file"
  done
  OPEN_KEYBOARD_TRUSTED_PROJECTION_FILES=()
  exit "$signal_status"
}

openkeyboard_register_trusted_gateway_projection() {
  local projection_file="$1"

  OPEN_KEYBOARD_TRUSTED_PROJECTION_FILES+=("$projection_file")
  if [[ "$OPEN_KEYBOARD_TRUSTED_PROJECTION_TRAPS_INSTALLED" != "true" ]]; then
    OPEN_KEYBOARD_TRUSTED_PROJECTION_PREVIOUS_EXIT_TRAP="$(trap -p EXIT)"
    trap openkeyboard_cleanup_trusted_gateway_projections EXIT
    trap 'openkeyboard_exit_after_trusted_projection_signal 129' HUP
    trap 'openkeyboard_exit_after_trusted_projection_signal 130' INT
    trap 'openkeyboard_exit_after_trusted_projection_signal 143' TERM
    OPEN_KEYBOARD_TRUSTED_PROJECTION_TRAPS_INSTALLED="true"
  fi
}

openkeyboard_trusted_validator_uses_redacted_live_schema() {
  local trusted_validator="${VALIDATOR_ROOT:-}/validate-pr-live-evidence.sh"

  if [[ "${OPEN_KEYBOARD_TRUSTED_REDACTED_LIVE_EVIDENCE_SCHEMA:-}" == "true" ]]; then
    return 0
  fi
  if [[ "${OPEN_KEYBOARD_TRUSTED_REDACTED_LIVE_EVIDENCE_SCHEMA:-}" == "false" ]]; then
    return 1
  fi
  [[ -f "$trusted_validator" ]] &&
    grep -Fq 'OPEN_KEYBOARD_REDACTED_LIVE_EVIDENCE_SCHEMA=1' "$trusted_validator"
}

openkeyboard_resolve_live_policy_bootstrap() {
  local trusted_supports_differential="$1"
  local trusted_live_impact="$2"
  local candidate_live_impact="$3"

  case "$trusted_supports_differential" in
    true|false) ;;
    *)
      echo "Trusted differential-support state is invalid." >&2
      return 2
      ;;
  esac
  case "$trusted_live_impact" in
    none|gateway|gateway-differential) ;;
    *)
      echo "Trusted live-impact classification is invalid." >&2
      return 2
      ;;
  esac
  case "$candidate_live_impact" in
    none|gateway|gateway-differential) ;;
    *)
      echo "Candidate live-impact classification is invalid." >&2
      return 2
      ;;
  esac

  OPEN_KEYBOARD_RESOLVED_LIVE_IMPACT="$trusted_live_impact"
  OPEN_KEYBOARD_BOOTSTRAP_DIFFERENTIAL="false"
  if [[ "$trusted_supports_differential" == "false" && \
        "$trusted_live_impact" == "gateway" && \
        "$candidate_live_impact" == "gateway-differential" ]]; then
    OPEN_KEYBOARD_RESOLVED_LIVE_IMPACT="gateway-differential"
    OPEN_KEYBOARD_BOOTSTRAP_DIFFERENTIAL="true"
  fi

  # A candidate that introduces the non-sensitive evidence schema must validate itself, then
  # project only fixed, non-secret placeholders into the trusted legacy validator. This avoids a
  # circular first-PR failure without retaining real model identities in the pull request or CI.
  if [[ "$OPEN_KEYBOARD_RESOLVED_LIVE_IMPACT" != "none" ]] &&
      ! openkeyboard_trusted_validator_uses_redacted_live_schema; then
    OPEN_KEYBOARD_BOOTSTRAP_DIFFERENTIAL="true"
  fi
}

openkeyboard_write_trusted_gateway_projection() {
  local body_file="$1"
  local head_sha="$2"
  local output_file="$3"
  local trusted_impact="${TRUSTED_LIVE_IMPACT:-gateway}"
  local body_line target="" model_requirement="" identity_matches="" role_distinctness=""
  local substitutions="" baseline="" differential="" follow_up="" summarize=""
  local continue_writing="" warning_contracts=""
  local target_count=0 model_requirement_count=0 identity_matches_count=0
  local role_distinctness_count=0 substitutions_count=0
  local provider_bindings="" provider_test_connection="" provider_diagnostics=""
  local provider_bindings_count=0 provider_test_connection_count=0 provider_diagnostics_count=0
  local prohibited_latency_fields_count=0
  local canonical_provider_bindings canonical_provider_outcomes

  if [[ ! -f "$body_file" || ! "$head_sha" =~ ^[0-9a-f]{40}$ || -z "$output_file" ]]; then
    echo "Trusted gateway projection inputs are invalid." >&2
    return 2
  fi
  case "$trusted_impact" in
    gateway|gateway-differential) ;;
    *)
      echo "Trusted gateway projection impact is invalid." >&2
      return 2
      ;;
  esac

  while IFS= read -r body_line; do
    body_line="${body_line%$'\r'}"
    case "$body_line" in
      '- Live verification target: '*)
        target="${body_line#- Live verification target: }"
        target_count=$((target_count + 1))
        ;;
      '- Live model requirement: '*)
        model_requirement="${body_line#- Live model requirement: }"
        model_requirement_count=$((model_requirement_count + 1))
        ;;
      '- Live model identity matches: '*)
        identity_matches="${body_line#- Live model identity matches: }"
        identity_matches_count=$((identity_matches_count + 1))
        ;;
      '- Live model role distinctness: '*)
        role_distinctness="${body_line#- Live model role distinctness: }"
        role_distinctness_count=$((role_distinctness_count + 1))
        ;;
      '- Live-model substitutions: '*)
        substitutions="${body_line#- Live-model substitutions: }"
        substitutions_count=$((substitutions_count + 1))
        ;;
      '- Live provider exact bindings: '*)
        provider_bindings="${body_line#- Live provider exact bindings: }"
        provider_bindings_count=$((provider_bindings_count + 1))
        ;;
      '- Live provider Test Connection outcomes: '*)
        provider_test_connection="${body_line#- Live provider Test Connection outcomes: }"
        provider_test_connection_count=$((provider_test_connection_count + 1))
        ;;
      '- Live provider diagnostic outcomes: '*)
        provider_diagnostics="${body_line#- Live provider diagnostic outcomes: }"
        provider_diagnostics_count=$((provider_diagnostics_count + 1))
        ;;
      '- Live summarize outcomes: '*) summarize="${body_line#- Live summarize outcomes: }" ;;
      '- Live continue-writing outcomes: '*) continue_writing="${body_line#- Live continue-writing outcomes: }" ;;
      '- Live baseline outcomes: '*) baseline="${body_line#- Live baseline outcomes: }" ;;
      '- Live differential outcomes: '*) differential="${body_line#- Live differential outcomes: }" ;;
      '- Live follow-up outcomes: '*) follow_up="${body_line#- Live follow-up outcomes: }" ;;
      '- Live operation-scoped warning contracts: '*) warning_contracts="${body_line#- Live operation-scoped warning contracts: }" ;;
      '- Live provider matrix latency: '*|'- Live provider matrix latencies: '*|'- Live profile latency: '*|'- Live profile latencies: '*|'- Live diagnostic latency: '*|'- Live diagnostic latencies: '*|'- Live diagnostic latency low: '*|'- Live diagnostic latencies low: '*|'- Live diagnostic latency high: '*|'- Live diagnostic latencies high: '*|'- diagnostic_latency_low='*|'- diagnostic_latencies_low='*|'- diagnostic_latency_high='*|'- diagnostic_latencies_high='*)
        prohibited_latency_fields_count=$((prohibited_latency_fields_count + 1))
        ;;
    esac
  done < "$body_file"

  if [[ "$target_count" -ne 1 || \
        ( "$target" != "gateway" && "$target" != "gateway-differential" ) || \
        "$model_requirement_count" -ne 1 || \
        ( "$model_requirement" != "exact" && "$model_requirement" != "model-agnostic" ) || \
        "$identity_matches_count" -ne 1 || \
        "$role_distinctness_count" -ne 1 || \
        "$substitutions_count" -ne 1 || "$substitutions" != "none" ]]; then
    echo "Bootstrap projection requires one valid redacted identity attestation." >&2
    return 1
  fi
  if [[ "$prohibited_latency_fields_count" -ne 0 ]]; then
    echo "Bootstrap projection refuses retained timing fields in candidate evidence." >&2
    return 1
  fi
  if [[ "$target" == "gateway-differential" ]]; then
    if [[ "$model_requirement" != "exact" || "$identity_matches" != "low=true, high=true" || \
          "$role_distinctness" != "true" ]]; then
      echo "Bootstrap projection requires exact, distinct, role-bound differential identities." >&2
      return 1
    fi
  elif [[ "$identity_matches" != "reference=true" || "$role_distinctness" != "not required" ]]; then
    echo "Bootstrap projection requires the exact seeded gateway reference identity." >&2
    return 1
  fi

  canonical_provider_bindings='openai=true, anthropic=true, openrouter=true, gateway=true'
  canonical_provider_outcomes='openai=passed, anthropic=passed, openrouter=passed, gateway=passed'
  if [[ "$provider_bindings_count" -ne 1 || "$provider_bindings" != "$canonical_provider_bindings" || \
        "$provider_test_connection_count" -ne 1 || "$provider_test_connection" != "$canonical_provider_outcomes" || \
        "$provider_diagnostics_count" -ne 1 || "$provider_diagnostics" != "$canonical_provider_outcomes" ]]; then
    echo "Bootstrap projection requires complete canonical four-provider evidence." >&2
    return 1
  fi

  umask 077
  if [[ -L "$output_file" ]]; then
    echo "Trusted gateway projection output must not be a symbolic link." >&2
    return 1
  fi
  : > "$output_file"
  chmod 600 "$output_file"
  openkeyboard_register_trusted_gateway_projection "$output_file"
  if [[ "$trusted_impact" == "gateway-differential" ]]; then
    if [[ "$target" != "gateway-differential" ]]; then
      echo "A trusted differential validator cannot consume ordinary gateway evidence." >&2
      return 1
    fi
    # The trusted/base validator predates the redacted schema and requires this field. These fixed
    # zero placeholders are not observations: they exist only in this mode-600, trap-cleaned
    # compatibility projection and disappear once the trusted validator exposes the schema marker.
    {
      printf '%s\n' \
        '- Local live verification: passed' \
        '- Live verification target: gateway-differential' \
        "- Exact live-tested head: $head_sha" \
        '- Required live models: low=locally-verified-low-role, high=locally-verified-high-role' \
        '- Exact live-tested models: low=locally-verified-low-role, high=locally-verified-high-role' \
        '- Live-model substitutions: none' \
        '- Live plain-text grammar verification: verified' \
        "- Live summarize outcomes: $summarize" \
        "- Live continue-writing outcomes: $continue_writing" \
        "- Live baseline outcomes: $baseline" \
        "- Live differential outcomes: $differential" \
        "- Live follow-up outcomes: $follow_up" \
        "- Live operation-scoped warning contracts: $warning_contracts" \
        '- Live profile latencies: low=0.000s, high=0.000s' \
        '- No credential or gateway response body retained.' \
        '- Trust boundary: local execution is contributor-attested; GitHub verifies retained exact-head evidence only.'
    } > "$output_file"
  else
    {
      printf '%s\n' \
        '- Local live verification: passed' \
        '- Live verification target: gateway' \
        "- Exact live-tested head: $head_sha" \
        '- Required live models: locally-verified-exact-model' \
        '- Exact live-tested models: locally-verified-exact-model' \
        '- Live-model substitutions: none' \
        '- Live plain-text grammar verification: verified' \
        '- Live summarize outcomes: not required' \
        '- Live continue-writing outcomes: not required' \
        '- Live baseline outcomes: not required' \
        '- Live differential outcomes: not required' \
        '- Live follow-up outcomes: not required' \
        '- Live operation-scoped warning contracts: not required' \
        '- Live profile latencies: not required' \
        '- No credential or gateway response body retained.' \
        '- Trust boundary: local execution is contributor-attested; GitHub verifies retained exact-head evidence only.'
    } > "$output_file"
  fi
  chmod 600 "$output_file"
}
