#!/usr/bin/env bash

# These helpers run inside the repository Simulator lock. A miss only schedules execution.
# Do not forward seed-backed environment values to receipt housekeeping tools.
openkeyboard_verification_receipt() (
  set +x
  set +a
  openkeyboard_unset_seed_backed_live_ambient_inputs
  openkeyboard_unset_simulator_gateway_profiles
  exec python3 -I "$REPO_ROOT/scripts/verification-cache.py" "$@"
)

openkeyboard_resume_context() {
  verification_context="$SENSITIVE_LIVE_WORKSPACE/verification-context.json"
  openkeyboard_verification_receipt context "$REPO_ROOT" "$verification_context" "$@" || exit $?
}

openkeyboard_resume_lookup() {
  local stage="$1" status
  if verification_cached_value="$(openkeyboard_verification_receipt get "$verification_context" "$stage")"; then
    echo "Reusing same-head passing verification: $stage"
    return 0
  else
    status=$?
    if [[ "$status" != 1 ]]; then
      exit "$status"
    fi
    return 1
  fi
}

openkeyboard_resume_save() {
  openkeyboard_verification_receipt put "$verification_context" "$@" || exit $?
}

openkeyboard_resume_invalidate() {
  openkeyboard_verification_receipt invalidate "$verification_context" "$1" || exit $?
}

openkeyboard_prepare_live_test_artifacts() {
  if [[ -z "${SENSITIVE_LIVE_SIMULATOR:-}" ]]; then
    create_sensitive_live_simulator "iPhone 16"
    destination="$(simulator_destination "$SENSITIVE_LIVE_SIMULATOR")"
  fi
  if [[ -n "${xctestrun:-}" && -f "$xctestrun" ]]; then
    return 0
  fi
  derived_data="$SENSITIVE_LIVE_WORKSPACE/DerivedData"
  echo "Building the required live-test artifacts once."
  run_xcodebuild xcodebuild build-for-testing \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "$destination" \
    -configuration Debug \
    -derivedDataPath "$derived_data" \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO
  xctestrun="$(find "$derived_data/Build/Products" -name '*.xctestrun' -print -quit)"
  if [[ -z "$xctestrun" ]]; then
    echo "Live-test artifacts did not produce an xctestrun file." >&2
    exit 1
  fi
  chmod 600 "$xctestrun"
}
