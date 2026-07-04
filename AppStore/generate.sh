#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is not installed. Install it with: brew install xcodegen" >&2
  exit 1
fi

xcodegen generate
echo ""
echo "Generated TranslateStore.xcodeproj — open it in Xcode to configure your Apple Developer"
echo "Team under Signing & Capabilities before archiving."
