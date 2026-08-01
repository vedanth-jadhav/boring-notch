#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/swift-cli/boringNotch.app"

"$ROOT/Scripts/package_swift_cli.sh" "${1:-release}"

pkill -x boringNotch 2>/dev/null || true
open -n "$APP"

echo "Launched ${APP}"
