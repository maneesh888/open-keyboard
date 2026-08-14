#!/usr/bin/env bash
set -euo pipefail

HEAD_SHA="${HEAD_SHA:-}"
LIVE_IMPACT="${LIVE_IMPACT:-}"
PR_BODY="${PR_BODY:-}"

if [[ ! "$HEAD_SHA" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Live-evidence validation needs the exact 40-character head SHA." >&2
  exit 2
fi

if [[ "$LIVE_IMPACT" == "none" ]]; then
  echo "This exact head does not require local gateway credentials."
  exit 0
fi

if [[ "$LIVE_IMPACT" != "gateway" ]]; then
  echo "Live-impact classification returned an unsupported target." >&2
  exit 2
fi

local_live_verification=""
local_live_verification_count=0
live_verification_target=""
live_verification_target_count=0
live_tested_head=""
live_tested_head_count=0
required_live_models=""
required_live_models_count=0
exact_live_tested_models=""
exact_live_tested_models_count=0
live_model_substitutions=""
live_model_substitutions_count=0
retention_boundary_count=0
trust_boundary_count=0
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
    '- Required live models: '*)
      required_live_models="${body_line#- Required live models: }"
      ((required_live_models_count += 1))
      ;;
    '- Exact live-tested models: '*)
      exact_live_tested_models="${body_line#- Exact live-tested models: }"
      ((exact_live_tested_models_count += 1))
      ;;
    '- Live-model substitutions: '*)
      live_model_substitutions="${body_line#- Live-model substitutions: }"
      ((live_model_substitutions_count += 1))
      ;;
    '- No credential or gateway response body retained.')
      ((retention_boundary_count += 1))
      ;;
    '- Trust boundary: local execution is contributor-attested; GitHub verifies retained exact-head evidence only.')
      ((trust_boundary_count += 1))
      ;;
  esac
done <<< "$PR_BODY"

if [[ "$local_live_verification_count" -ne 1 || "$local_live_verification" != "passed" ]]; then
  echo "The pull request must record exactly one passing local live-verification field." >&2
  exit 1
fi
if [[ "$live_verification_target_count" -ne 1 || "$live_verification_target" != "gateway" ]]; then
  echo "The pull request must record exactly one gateway live-verification target." >&2
  exit 1
fi
if [[ "$live_tested_head_count" -ne 1 ]]; then
  echo "The pull request must record exactly one exact live-tested head." >&2
  exit 1
fi
if [[ ! "$live_tested_head" =~ ^[0-9a-f]{40}$ || "$live_tested_head" != "$HEAD_SHA" ]]; then
  echo "Local live evidence is not bound to this exact head." >&2
  exit 1
fi
if [[ "$required_live_models_count" -ne 1 || -z "$required_live_models" || "$required_live_models" == "not required" ]]; then
  echo "The pull request must record exactly one required live-model coverage field." >&2
  exit 1
fi
if [[ "$exact_live_tested_models_count" -ne 1 || -z "$exact_live_tested_models" || "$exact_live_tested_models" == "not required" || "$exact_live_tested_models" == "none" ]]; then
  echo "The pull request must record exactly one non-empty exact live-tested model field." >&2
  exit 1
fi
if [[ "$live_model_substitutions_count" -ne 1 || "$live_model_substitutions" != "none" ]]; then
  echo "Live-model substitutions or fallback are not accepted as exact-model proof." >&2
  exit 1
fi
if [[ "$required_live_models" != "model-agnostic" && "$required_live_models" != "$exact_live_tested_models" ]]; then
  echo "Exact live-tested models do not match the required model coverage." >&2
  exit 1
fi
if [[ "$retention_boundary_count" -ne 1 ]]; then
  echo "The pull request must record exactly one live-proof retention boundary." >&2
  exit 1
fi
if [[ "$trust_boundary_count" -ne 1 ]]; then
  echo "The pull request must record exactly one live-proof trust boundary." >&2
  exit 1
fi

echo "Exact-head local live evidence was recorded."
echo "GitHub did not receive gateway credentials."
