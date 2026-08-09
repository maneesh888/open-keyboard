#!/usr/bin/env bash
set -euo pipefail

ROOT="${OPEN_KEYBOARD_REPOSITORY_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

SECRET_PATTERNS=(
  -e 'sk-[A-Za-z0-9_-]{20,}'
  -e 'gh[pousr]_[A-Za-z0-9]{30,}'
  -e 'Authorization:[[:space:]]*Bearer[[:space:]]+[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{8,}'
  -e '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----'
)

if ! command -v rg >/dev/null 2>&1; then
  echo "ripgrep (rg) is required for the repository secret scan." >&2
  exit 2
fi

if command -v git >/dev/null 2>&1 &&
  git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  while IFS= read -r -d '' tracked_private_input; do
    case "$tracked_private_input" in
      *.example)
        ;;
      *)
        echo "A private input file is tracked and must be removed from the Git index." >&2
        exit 1
        ;;
    esac
  done < <(
    git -C "$ROOT" ls-files -z -- \
      ':(glob)**/.env' \
      ':(glob)**/.env.*' \
      ':(glob)**/*.seed.local.env' \
      ':(glob).agent/local-seeds/**'
  )

  tracked_scan_status=0
  git -C "$ROOT" grep \
    --quiet \
    --ignore-case \
    --extended-regexp \
    -I \
    "${SECRET_PATTERNS[@]}" \
    -- . || tracked_scan_status=$?

  case "$tracked_scan_status" in
    0)
      echo "Potential secret material found in a tracked file." >&2
      exit 1
      ;;
    1)
      ;;
    *)
      echo "Tracked-file secret scan could not complete (git grep exit $tracked_scan_status)." >&2
      exit "$tracked_scan_status"
      ;;
  esac
fi

scan_status=0
rg --quiet \
  --no-config \
  --no-ignore \
  --hidden \
  --glob '!.git/**' \
  --glob '!.agent/**' \
  --glob '!.ci-results/**' \
  --glob '!.derived-*/**' \
  --glob '!DerivedData/**' \
  --glob '!build/**' \
  --glob '!**/.build/**' \
  --glob '!reports/**' \
  --glob '!*.xcresult/**' \
  --glob '!scripts/ios/openkeyboard-gateway.seed.env.example' \
  "${SECRET_PATTERNS[@]}" \
  "$ROOT" || scan_status=$?

case "$scan_status" in
  0)
    echo "Potential secret material found." >&2
    exit 1
    ;;
  1)
    ;;
  *)
    echo "Repository secret scan could not complete (rg exit $scan_status)." >&2
    exit "$scan_status"
    ;;
esac

echo "Secret scan passed."
