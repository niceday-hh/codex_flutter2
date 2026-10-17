#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Generate only the standard platform wrapper, never overwrite application code.
if [[ ! -f android/gradlew ]]; then
  platform_temp="$(mktemp -d)"
  trap 'rm -rf "$platform_temp"' EXIT
  flutter create --platforms=android --android-language=java --project-name=timed_memo --org=com.niceday --no-pub "$platform_temp/platform"
  mkdir -p android
  cp -R "$platform_temp/platform/android/." android/
  rm -rf android/app/src/main/java android/app/src/main/kotlin
fi
cp -R native/. android/
mkdir -p assets/models assets/tts assets/vad
touch assets/models/.keep
python3 tool/fetch_mnn.py
python3 tool/fetch_vad.py
flutter pub get
