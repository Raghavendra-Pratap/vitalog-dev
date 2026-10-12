#!/usr/bin/env bash
# Local secret scan for bodyline trees. Install: brew install gitleaks
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if ! command -v gitleaks >/dev/null 2>&1; then
  echo "gitleaks not installed. Run: brew install gitleaks"
  exit 2
fi
gitleaks detect --source "$ROOT" --no-git --verbose --redact \
  --config "$ROOT/scripts/gitleaks.toml"
