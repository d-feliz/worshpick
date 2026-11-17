#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
swift test --package-path Packages/WorshpickCore
scripts/generate-project.sh
xcodebuild -project Worshpick.xcodeproj -scheme Worshpick -destination 'platform=macOS' -derivedDataPath DerivedData build -quiet
