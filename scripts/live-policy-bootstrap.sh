#!/usr/bin/env bash

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
}

openkeyboard_write_trusted_gateway_projection() {
  local body_file="$1"
  local head_sha="$2"
  local output_file="$3"
  local body_line required_models="" tested_models=""
  local required_models_count=0 tested_models_count=0
  local required_low_model required_high_model tested_low_model tested_high_model

  if [[ ! -f "$body_file" || ! "$head_sha" =~ ^[0-9a-f]{40}$ || -z "$output_file" ]]; then
    echo "Trusted gateway projection inputs are invalid." >&2
    return 2
  fi

  while IFS= read -r body_line; do
    body_line="${body_line%$'\r'}"
    case "$body_line" in
      '- Required live models: '*)
        required_models="${body_line#- Required live models: }"
        required_models_count=$((required_models_count + 1))
        ;;
      '- Exact live-tested models: '*)
        tested_models="${body_line#- Exact live-tested models: }"
        tested_models_count=$((tested_models_count + 1))
        ;;
    esac
  done < "$body_file"

  if [[ "$required_models_count" -ne 1 || "$tested_models_count" -ne 1 ]]; then
    echo "Bootstrap differential evidence must contain one required and one tested model mapping." >&2
    return 1
  fi
  if [[ ! "$required_models" =~ ^low=([A-Za-z0-9][A-Za-z0-9._:/+-]*),\ high=([A-Za-z0-9][A-Za-z0-9._:/+-]*)$ ]]; then
    echo "Bootstrap differential required-model mapping is invalid." >&2
    return 1
  fi
  required_low_model="${BASH_REMATCH[1]}"
  required_high_model="${BASH_REMATCH[2]}"
  if [[ "$required_low_model" == "$required_high_model" ]]; then
    echo "Bootstrap differential model roles must be distinct." >&2
    return 1
  fi
  if [[ ! "$tested_models" =~ ^low=([A-Za-z0-9][A-Za-z0-9._:/+-]*),\ high=([A-Za-z0-9][A-Za-z0-9._:/+-]*)$ ]]; then
    echo "Bootstrap differential tested-model mapping is invalid." >&2
    return 1
  fi
  tested_low_model="${BASH_REMATCH[1]}"
  tested_high_model="${BASH_REMATCH[2]}"
  if [[ "$required_low_model" != "$tested_low_model" || "$required_high_model" != "$tested_high_model" ]]; then
    echo "Bootstrap differential projection refuses substituted or reversed model roles." >&2
    return 1
  fi

  umask 077
  {
    printf '%s\n' \
      '- Local live verification: passed' \
      '- Live verification target: gateway' \
      "- Exact live-tested head: $head_sha" \
      "- Required live models: $required_high_model" \
      "- Exact live-tested models: $tested_high_model" \
      '- Live-model substitutions: none' \
      '- Live plain-text grammar verification: verified' \
      '- Live baseline outcomes: not required' \
      '- Live differential outcomes: not required' \
      '- Live follow-up outcomes: not required' \
      '- Live operation-scoped warning contracts: not required' \
      '- Live profile latencies: not required' \
      '- No credential or gateway response body retained.' \
      '- Trust boundary: local execution is contributor-attested; GitHub verifies retained exact-head evidence only.'
  } > "$output_file"
  chmod 600 "$output_file"
}
