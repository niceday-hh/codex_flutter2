#!/usr/bin/env bash
# Source this file in each new shell; never store credentials here.
memo_repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export MEMO_CLOUD_ROOT="${MEMO_CLOUD_ROOT:-$memo_repo_root/.codex/toolchain}"
export FLUTTER_ROOT="$MEMO_CLOUD_ROOT/flutter"
export JAVA_HOME="$MEMO_CLOUD_ROOT/jdk"
export ANDROID_HOME="$MEMO_CLOUD_ROOT/android-sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export ANDROID_AVD_HOME="$MEMO_CLOUD_ROOT/avd"
export PUB_CACHE="$MEMO_CLOUD_ROOT/pub-cache"
export GRADLE_USER_HOME="$MEMO_CLOUD_ROOT/gradle"
export TMPDIR="$MEMO_CLOUD_ROOT/tmp"
mkdir -p "$TMPDIR"
export LD_LIBRARY_PATH="$JAVA_HOME/lib:$JAVA_HOME/lib/server:$ANDROID_HOME/emulator/lib64:$ANDROID_HOME/emulator/lib64/qt/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PATH="$FLUTTER_ROOT/bin:$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$ANDROID_HOME/cmake/3.22.1/bin:$PATH"
export FLUTTER_SUPPRESS_ANALYTICS=true
export DART_SUPPRESS_ANALYTICS=true
export MEMO_RUN_REBOOT_TESTS=0
unset memo_repo_root
