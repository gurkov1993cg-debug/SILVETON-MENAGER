#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$(pwd)"
BUILD_DIR="$ROOT/build-local"
OBJ_DIR="$BUILD_DIR/obj"
APP_DIR="$BUILD_DIR/SILVETON Manager.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
OUT_DIR="$ROOT/artifact-local"
ZIP_PATH="$OUT_DIR/SILVETON-MANAGER-iMac2011-x86_64.zip"

if ! command -v xcrun >/dev/null 2>&1; then
  echo "ERROR: Xcode Command Line Tools are required."
  exit 1
fi

CXX="$(xcrun -f clang++)"
SDK="$(xcrun --sdk macosx --show-sdk-path)"

rm -rf "$BUILD_DIR" "$OUT_DIR"
mkdir -p "$OBJ_DIR" "$MACOS_DIR" "$OUT_DIR"

COMMON=(
  -std=c++17
  -arch x86_64
  -mmacosx-version-min=10.13
  -isysroot "$SDK"
  -I"$ROOT/include"
  -O2
)

CORE_SOURCES=(
  src/core/AudioExporter.cpp
  src/core/AudioFileLoader.cpp
  src/core/KorgImporter.cpp
  src/core/MediaPathPolicy.cpp
  src/core/ObjectManager.cpp
  src/core/SampleConverter.cpp
  src/core/SampleEditor.cpp
  src/core/SampleEditorRegions.cpp
  src/core/SoundEditor.cpp
  src/core/SvBankBuilder.cpp
  src/core/SvBankFormat.cpp
  src/core/SvBankReader.cpp
  src/core/SampleHash.cpp
)

APP_SOURCES=(
  src/app/main.mm
  src/app/AppDelegate.mm
  src/app/AppUnsavedChanges.mm
  src/app/BankFileCommands.mm
  src/app/ConverterController.mm
  src/app/FinalGUITheme.mm
  src/app/GUIIntegration.mm
  src/app/MediaController.mm
  src/app/MediaUnsavedGuard.mm
  src/app/WorkflowController.mm
  src/app/ObjectManagerController.mm
  src/app/MainWindowController.mm
  src/app/WaveformInteraction.mm
  src/app/SampleAuditionPlayer.mm
  src/app/MultisampleEditorController.mm
  src/app/BankOrganizerController.mm
  src/app/SoundEditorController.mm
  src/app/ManagerDocument.mm
  src/app/ManagerDocumentBankIO.mm
  src/app/ManagerDocumentConverter.mm
  src/app/ManagerDocumentDirty.mm
  src/app/ManagerDocumentObjects.mm
)

OBJECTS=()
index=0
for src in "${CORE_SOURCES[@]}"; do
  obj="$OBJ_DIR/core_${index}.o"
  echo "[CORE] $src"
  "$CXX" "${COMMON[@]}" -Wall -Wextra -Wpedantic -Wshadow -Wconversion -Werror -c "$ROOT/$src" -o "$obj"
  OBJECTS+=("$obj")
  index=$((index + 1))
done

index=0
for src in "${APP_SOURCES[@]}"; do
  obj="$OBJ_DIR/app_${index}.o"
  echo "[APP ] $src"
  "$CXX" "${COMMON[@]}" -fobjc-arc -c "$ROOT/$src" -o "$obj"
  OBJECTS+=("$obj")
  index=$((index + 1))
done

EXE="$MACOS_DIR/SILVETON Manager"
echo "[LINK] SILVETON Manager"
"$CXX" -arch x86_64 -mmacosx-version-min=10.13 -isysroot "$SDK" \
  "${OBJECTS[@]}" \
  -framework AppKit \
  -framework Foundation \
  -framework CoreFoundation \
  -framework AudioToolbox \
  -framework QuartzCore \
  -o "$EXE"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>SILVETON Manager</string>
  <key>CFBundleIdentifier</key><string>com.silveton.manager</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>SILVETON Manager</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>10.13</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

plutil -lint "$APP_DIR/Contents/Info.plist"

ARCHS="$(lipo -archs "$EXE")"
if [ "$ARCHS" != "x86_64" ]; then
  echo "ERROR: Expected x86_64, got: $ARCHS"
  exit 1
fi

echo "[VERIFY] architecture: $ARCHS"
if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_DIR"
  codesign --verify --deep --strict --verbose=2 "$APP_DIR"
fi

rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"
shasum -a 256 "$ZIP_PATH" | tee "$OUT_DIR/SHA256.txt"

echo
echo "BUILD COMPLETE"
echo "APP: $APP_DIR"
echo "ZIP: $ZIP_PATH"
open "$APP_DIR" || true
open "$OUT_DIR" || true
