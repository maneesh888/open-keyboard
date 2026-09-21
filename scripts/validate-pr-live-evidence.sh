#!/usr/bin/env bash
set -euo pipefail

# Marker consumed by live-policy-bootstrap.sh when a pull request changes the retained evidence
# schema before the trusted base validator has learned it.
readonly OPEN_KEYBOARD_REDACTED_LIVE_EVIDENCE_SCHEMA=1

HEAD_SHA="${HEAD_SHA:-}"
LIVE_IMPACT="${LIVE_IMPACT:-}"
PR_BODY="${PR_BODY:-}"

if [[ ! "$HEAD_SHA" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Live-evidence validation needs the exact 40-character head SHA." >&2
  exit 2
fi

if [[ "$LIVE_IMPACT" != "none" && "$LIVE_IMPACT" != "gateway" && "$LIVE_IMPACT" != "gateway-differential" ]]; then
  echo "Live-impact classification returned an unsupported target." >&2
  exit 2
fi

local_live_verification=""
local_live_verification_count=0
live_verification_target=""
live_verification_target_count=0
live_tested_head=""
live_tested_head_count=0
live_model_requirement=""
live_model_requirement_count=0
live_model_identity_matches=""
live_model_identity_matches_count=0
live_model_role_distinctness=""
live_model_role_distinctness_count=0
live_model_substitutions=""
live_model_substitutions_count=0
live_provider_exact_bindings=""
live_provider_exact_bindings_count=0
live_provider_test_connection_outcomes=""
live_provider_test_connection_outcomes_count=0
live_provider_diagnostic_outcomes=""
live_provider_diagnostic_outcomes_count=0
plain_text_grammar_verification=""
plain_text_grammar_verification_count=0
live_summarize_outcomes=""
live_summarize_outcomes_count=0
live_continue_writing_outcomes=""
live_continue_writing_outcomes_count=0
live_baseline_outcomes=""
live_baseline_outcomes_count=0
live_differential_outcomes=""
live_differential_outcomes_count=0
live_follow_up_outcomes=""
live_follow_up_outcomes_count=0
live_operation_scoped_warning_contracts=""
live_operation_scoped_warning_contracts_count=0
legacy_required_models_count=0
legacy_tested_models_count=0
legacy_commitment_scheme_count=0
prohibited_raw_model_fields_count=0
prohibited_latency_fields_count=0
retention_boundary_count=0
trust_boundary_count=0
invalid_retention_boundary_count=0
invalid_trust_boundary_count=0

while IFS= read -r body_line; do
  body_line="${body_line%$'\r'}"
  case "$body_line" in
    '- Local live verification: '*)
      local_live_verification="${body_line#- Local live verification: }"
      ((local_live_verification_count += 1))
      ;;
    '- Live verification target: '*)
      live_verification_target="${body_line#- Live verification target: }"
      ((live_verification_target_count += 1))
      ;;
    '- Exact live-tested head: '*)
      live_tested_head="${body_line#- Exact live-tested head: }"
      ((live_tested_head_count += 1))
      ;;
    '- Live model requirement: '*)
      live_model_requirement="${body_line#- Live model requirement: }"
      ((live_model_requirement_count += 1))
      case "$live_model_requirement" in
        exact|model-agnostic|'not required') ;;
        *) ((prohibited_raw_model_fields_count += 1)) ;;
      esac
      ;;
    '- Live model identity matches: '*)
      live_model_identity_matches="${body_line#- Live model identity matches: }"
      ((live_model_identity_matches_count += 1))
      case "$live_model_identity_matches" in
        'not required'|reference=true|reference=false|\
        'low=true, high=true'|'low=true, high=false'|\
        'low=false, high=true'|'low=false, high=false') ;;
        *) ((prohibited_raw_model_fields_count += 1)) ;;
      esac
      ;;
    '- Live model role distinctness: '*)
      live_model_role_distinctness="${body_line#- Live model role distinctness: }"
      ((live_model_role_distinctness_count += 1))
      ;;
    '- Live-model substitutions: '*)
      live_model_substitutions="${body_line#- Live-model substitutions: }"
      ((live_model_substitutions_count += 1))
      ;;
    '- Live provider exact bindings: '*)
      live_provider_exact_bindings="${body_line#- Live provider exact bindings: }"
      ((live_provider_exact_bindings_count += 1))
      ;;
    '- Live provider Test Connection outcomes: '*)
      live_provider_test_connection_outcomes="${body_line#- Live provider Test Connection outcomes: }"
      ((live_provider_test_connection_outcomes_count += 1))
      ;;
    '- Live provider diagnostic outcomes: '*)
      live_provider_diagnostic_outcomes="${body_line#- Live provider diagnostic outcomes: }"
      ((live_provider_diagnostic_outcomes_count += 1))
      ;;
    '- Live provider matrix latency: '*|'- Live provider matrix latencies: '*|'- provider_matrix_latency='*|'- provider_matrix_latencies='*)
      ((prohibited_latency_fields_count += 1))
      ;;
    '- Live plain-text grammar verification: '*)
      plain_text_grammar_verification="${body_line#- Live plain-text grammar verification: }"
      ((plain_text_grammar_verification_count += 1))
      ;;
    '- Live summarize outcomes: '*)
      live_summarize_outcomes="${body_line#- Live summarize outcomes: }"
      ((live_summarize_outcomes_count += 1))
      ;;
    '- Live continue-writing outcomes: '*)
      live_continue_writing_outcomes="${body_line#- Live continue-writing outcomes: }"
      ((live_continue_writing_outcomes_count += 1))
      ;;
    '- Live baseline outcomes: '*)
      live_baseline_outcomes="${body_line#- Live baseline outcomes: }"
      ((live_baseline_outcomes_count += 1))
      ;;
    '- Live differential outcomes: '*)
      live_differential_outcomes="${body_line#- Live differential outcomes: }"
      ((live_differential_outcomes_count += 1))
      ;;
    '- Live follow-up outcomes: '*)
      live_follow_up_outcomes="${body_line#- Live follow-up outcomes: }"
      ((live_follow_up_outcomes_count += 1))
      ;;
    '- Live operation-scoped warning contracts: '*)
      live_operation_scoped_warning_contracts="${body_line#- Live operation-scoped warning contracts: }"
      ((live_operation_scoped_warning_contracts_count += 1))
      ;;
    '- Live profile latency: '*|'- Live profile latencies: '*|'- profile_latency='*|'- profile_latencies='*)
      ((prohibited_latency_fields_count += 1))
      ;;
    '- Live diagnostic latency: '*|'- Live diagnostic latencies: '*|'- Live diagnostic latency low: '*|'- Live diagnostic latencies low: '*|'- Live diagnostic latency high: '*|'- Live diagnostic latencies high: '*|'- diagnostic_latency_low='*|'- diagnostic_latencies_low='*|'- diagnostic_latency_high='*|'- diagnostic_latencies_high='*)
      ((prohibited_latency_fields_count += 1))
      ;;
    '- Required live model: '*|'- Required live models: '*)
      ((legacy_required_models_count += 1))
      ;;
    '- Exact live-tested model: '*|'- Exact live-tested models: '*)
      ((legacy_tested_models_count += 1))
      ;;
    '- Live model commitment: '*|'- Live model commitment scheme: '*|'- Live model HMAC: '*|'- Live model HMAC key: '*|'- hmac_sha256='*)
      ((legacy_commitment_scheme_count += 1))
      ;;
    '- No credential, private provider value, model identity, or gateway response body retained.')
      ((retention_boundary_count += 1))
      ;;
    '- No credential'*)
      ((invalid_retention_boundary_count += 1))
      ;;
    '- Trust boundary: local execution attests secret-backed exact identity comparisons; GitHub verifies retained exact-head non-sensitive assertions only.')
      ((trust_boundary_count += 1))
      ;;
    '- Trust boundary: '*)
      ((invalid_trust_boundary_count += 1))
      ;;
  esac
done <<< "$PR_BODY"

if (( legacy_required_models_count != 0 || legacy_tested_models_count != 0 || legacy_commitment_scheme_count != 0 || prohibited_raw_model_fields_count != 0 )); then
  echo "Live evidence must not retain legacy raw model fields or opaque model commitments." >&2
  exit 1
fi
if (( prohibited_latency_fields_count != 0 )); then
  echo "Live evidence must not retain provider, profile, or diagnostic timing fields." >&2
  exit 1
fi
if [[ "$LIVE_IMPACT" == "none" ]]; then
  none_field_names=(
    "Local live verification"
    "Live verification target"
    "Exact live-tested head"
    "Live model requirement"
    "Live model identity matches"
    "Live model role distinctness"
    "Live-model substitutions"
    "Live provider exact bindings"
    "Live provider Test Connection outcomes"
    "Live provider diagnostic outcomes"
    "Live plain-text grammar verification"
    "Live summarize outcomes"
    "Live continue-writing outcomes"
    "Live baseline outcomes"
    "Live differential outcomes"
    "Live follow-up outcomes"
    "Live operation-scoped warning contracts"
  )
  none_field_counts=(
    "$local_live_verification_count"
    "$live_verification_target_count"
    "$live_tested_head_count"
    "$live_model_requirement_count"
    "$live_model_identity_matches_count"
    "$live_model_role_distinctness_count"
    "$live_model_substitutions_count"
    "$live_provider_exact_bindings_count"
    "$live_provider_test_connection_outcomes_count"
    "$live_provider_diagnostic_outcomes_count"
    "$plain_text_grammar_verification_count"
    "$live_summarize_outcomes_count"
    "$live_continue_writing_outcomes_count"
    "$live_baseline_outcomes_count"
    "$live_differential_outcomes_count"
    "$live_follow_up_outcomes_count"
    "$live_operation_scoped_warning_contracts_count"
  )
  none_field_values=(
    "$local_live_verification"
    "$live_verification_target"
    "$live_tested_head"
    "$live_model_requirement"
    "$live_model_identity_matches"
    "$live_model_role_distinctness"
    "$live_model_substitutions"
    "$live_provider_exact_bindings"
    "$live_provider_test_connection_outcomes"
    "$live_provider_diagnostic_outcomes"
    "$plain_text_grammar_verification"
    "$live_summarize_outcomes"
    "$live_continue_writing_outcomes"
    "$live_baseline_outcomes"
    "$live_differential_outcomes"
    "$live_follow_up_outcomes"
    "$live_operation_scoped_warning_contracts"
  )
  for none_field_index in "${!none_field_names[@]}"; do
    if [[ "${none_field_counts[$none_field_index]}" -gt 1 ||
          ( "${none_field_counts[$none_field_index]}" -eq 1 &&
            "${none_field_values[$none_field_index]}" != "not required" ) ]]; then
      echo "No-impact pull requests may record ${none_field_names[$none_field_index]} only once as 'not required'." >&2
      exit 1
    fi
  done
  if [[ "$retention_boundary_count" -gt 1 || "$invalid_retention_boundary_count" -ne 0 ]]; then
    echo "No-impact pull requests may include the exact retention boundary at most once." >&2
    exit 1
  fi
  if [[ "$trust_boundary_count" -gt 1 || "$invalid_trust_boundary_count" -ne 0 ]]; then
    echo "No-impact pull requests may include the exact trust boundary at most once." >&2
    exit 1
  fi
  echo "This exact head does not require local gateway credentials."
  exit 0
fi
if [[ "$local_live_verification_count" -ne 1 || "$local_live_verification" != "passed" ]]; then
  echo "The pull request must record exactly one passing local live-verification field." >&2
  exit 1
fi
if [[ "$live_verification_target_count" -ne 1 || \
      ( "$live_verification_target" != "gateway" && "$live_verification_target" != "gateway-differential" ) ]]; then
  echo "The pull request must record exactly one supported gateway live-verification target." >&2
  exit 1
fi
if [[ "$live_verification_target" != "$LIVE_IMPACT" ]]; then
  echo "The recorded live-verification target does not match the exact-head impact classification." >&2
  exit 1
fi
if [[ "$live_tested_head_count" -ne 1 || \
      ! "$live_tested_head" =~ ^[0-9a-f]{40}$ || "$live_tested_head" != "$HEAD_SHA" ]]; then
  echo "The pull request must bind exactly one live-evidence record to this exact head." >&2
  exit 1
fi
if [[ "$live_model_requirement_count" -ne 1 || \
      ( "$live_model_requirement" != "exact" && "$live_model_requirement" != "model-agnostic" ) ]]; then
  echo "The pull request must record exactly one supported live model requirement class." >&2
  exit 1
fi
if [[ "$live_model_identity_matches_count" -ne 1 ]]; then
  echo "The pull request must record exactly one locally attested model-identity match field." >&2
  exit 1
fi
if [[ "$live_model_role_distinctness_count" -ne 1 ]]; then
  echo "The pull request must record exactly one model-role distinctness field." >&2
  exit 1
fi
if [[ "$live_model_substitutions_count" -ne 1 || "$live_model_substitutions" != "none" ]]; then
  echo "Live-model substitutions or fallback are not accepted as exact-model proof." >&2
  exit 1
fi

canonical_provider_bindings='openai=true, anthropic=true, openrouter=true, gateway=true'
canonical_provider_outcomes='openai=passed, anthropic=passed, openrouter=passed, gateway=passed'
if [[ "$live_provider_exact_bindings_count" -ne 1 || \
      "$live_provider_exact_bindings" != "$canonical_provider_bindings" ]]; then
  echo "Four-provider live evidence must attest exact canonical bindings in canonical order." >&2
  exit 1
fi
if [[ "$live_provider_test_connection_outcomes_count" -ne 1 || \
      "$live_provider_test_connection_outcomes" != "$canonical_provider_outcomes" ]]; then
  echo "Four-provider live evidence must record passing Test Connection outcomes in canonical order." >&2
  exit 1
fi
if [[ "$live_provider_diagnostic_outcomes_count" -ne 1 || \
      "$live_provider_diagnostic_outcomes" != "$canonical_provider_outcomes" ]]; then
  echo "Four-provider live evidence must record passing diagnostic outcomes in canonical order." >&2
  exit 1
fi
if [[ "$plain_text_grammar_verification_count" -ne 1 || "$plain_text_grammar_verification" != "verified" ]]; then
  echo "The pull request must record exactly one verified live plain-text grammar field." >&2
  exit 1
fi
if [[ "$live_summarize_outcomes_count" -ne 1 || "$live_continue_writing_outcomes_count" -ne 1 ]]; then
  echo "The pull request must record exactly one Summarize and one Continue Writing live-outcome field." >&2
  exit 1
fi

if [[ "$live_verification_target" == "gateway-differential" ]]; then
  if [[ "$live_model_requirement" != "exact" ]]; then
    echo "Differential live evidence requires the exact model requirement class." >&2
    exit 1
  fi
  if [[ "$live_model_identity_matches" != "low=true, high=true" ]]; then
    echo "Differential evidence must attest both exact role-bound model identities in canonical order." >&2
    exit 1
  fi
  if [[ "$live_model_role_distinctness" != "true" ]]; then
    echo "Differential evidence must attest distinct low and high model roles." >&2
    exit 1
  fi
  if [[ "$live_baseline_outcomes_count" -ne 1 || "$live_baseline_outcomes" != "low=passed, high=passed" ]]; then
    echo "Differential evidence must verify the baseline on both profiles." >&2
    exit 1
  fi
  if [[ "$live_summarize_outcomes" != "low=passed, high=passed" ]]; then
    echo "Differential evidence must verify Summarize on both profiles." >&2
    exit 1
  fi
  if [[ "$live_continue_writing_outcomes" != "low=passed, high=passed" ]]; then
    echo "Differential evidence must verify Continue Writing on both profiles." >&2
    exit 1
  fi
  if [[ "$live_differential_outcomes_count" -ne 1 || "$live_differential_outcomes" != "low=expected-model-capability, high=passed" ]]; then
    echo "Differential evidence must retain the expected low boundary and high success." >&2
    exit 1
  fi
  if [[ "$live_follow_up_outcomes_count" -ne 1 || "$live_follow_up_outcomes" != "low=passed, high=passed" ]]; then
    echo "Differential evidence must verify the post-boundary follow-up on both profiles." >&2
    exit 1
  fi
  if [[ "$live_operation_scoped_warning_contracts_count" -ne 1 || "$live_operation_scoped_warning_contracts" != "verified" ]]; then
    echo "Differential evidence must verify operation-scoped warning contracts." >&2
    exit 1
  fi
else
  if [[ "$live_model_identity_matches" != "reference=true" ]]; then
    echo "Ordinary gateway evidence must attest the exact seeded reference-model identity." >&2
    exit 1
  fi
  if [[ "$live_model_role_distinctness" != "not required" ]]; then
    echo "Ordinary gateway evidence must not claim differential role distinctness." >&2
    exit 1
  fi
  if [[ "$live_summarize_outcomes" != "not required" || \
        "$live_continue_writing_outcomes" != "not required" || \
        "$live_baseline_outcomes_count" -ne 1 || "$live_baseline_outcomes" != "not required" || \
        "$live_differential_outcomes_count" -ne 1 || "$live_differential_outcomes" != "not required" || \
        "$live_follow_up_outcomes_count" -ne 1 || "$live_follow_up_outcomes" != "not required" || \
        "$live_operation_scoped_warning_contracts_count" -ne 1 || "$live_operation_scoped_warning_contracts" != "not required" ]]; then
    echo "Ordinary gateway evidence must not claim the differential matrix fields." >&2
    exit 1
  fi
fi

if [[ "$retention_boundary_count" -ne 1 ]]; then
  echo "The pull request must record exactly one non-sensitive live-proof retention boundary." >&2
  exit 1
fi
if [[ "$trust_boundary_count" -ne 1 ]]; then
  echo "The pull request must record exactly one local-attestation trust boundary." >&2
  exit 1
fi

echo "Exact-head local live evidence was recorded."
echo "GitHub received only non-sensitive assertions; private live identities were compared locally and not retained."
