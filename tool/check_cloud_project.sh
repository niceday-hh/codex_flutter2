#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source tool/cloud_env.sh
bash tool/bootstrap.sh
python3 tool/fetch_test_runtime.py
export LD_LIBRARY_PATH="$(find tool/test-runtime -name libsherpa-onnx-c-api.so -printf '%h\n' -quit)${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
flutter analyze
flutter test --timeout=45s --fail-fast
mkdir -p tool/out
javac -d tool/out native/app/src/main/java/com/niceday/memo/Schedule.java tool/ScheduleTest.java
java -cp tool/out ScheduleTest
python3 -m unittest discover -s tool -p '*_unit_test.py' -v

# Native Android unit tests are intentionally separate from signing and release.
if [[ "${1:-}" == "--android" ]]; then
  (cd android && ./gradlew :app:testReleaseUnitTest --no-daemon --max-workers=2 -Ptarget-platform=android-arm64)
fi
