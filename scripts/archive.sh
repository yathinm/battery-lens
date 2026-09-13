#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DIR="${ROOT_DIR}/DerivedData-Release"
ARCHIVE_PATH="${ROOT_DIR}/build/BatteryLens.xcarchive"
EXPORT_PATH="${ROOT_DIR}/build/export"

mkdir -p "${ROOT_DIR}/build"
xcodebuild archive \
  -project "${ROOT_DIR}/BatteryLens.xcodeproj" \
  -scheme BatteryLens \
  -configuration Release \
  -derivedDataPath "${DERIVED_DIR}" \
  -archivePath "${ARCHIVE_PATH}"

xcodebuild -exportArchive \
  -archivePath "${ARCHIVE_PATH}" \
  -exportOptionsPlist "${ROOT_DIR}/ExportOptions.plist" \
  -exportPath "${EXPORT_PATH}"

echo "Exported signed application to ${EXPORT_PATH}"
