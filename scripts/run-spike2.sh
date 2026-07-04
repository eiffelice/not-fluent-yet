#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift run spike2-pasteback "$@"
