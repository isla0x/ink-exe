#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
app_build_number="${1:-12}"
flutter pub get
flutter build ipa --release --build-name=2.0.0 --build-number="$app_build_number"
open build/ios/archive/Runner.xcarchive
