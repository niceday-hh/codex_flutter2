# Reminder detail performance

The baseline is v0.9.21 (`6169648a01e27218f5abec541123282b1b79f163`).

## Changes

- Character images no longer evict themselves on every sheet dismissal. An
  insertion-ordered working set keeps at most six recently displayed assets,
  with a 6 MiB estimated RGBA budget. Trimming and memory-pressure events evict
  old entries. This budget describes tracked decoded pixels, not total app/GPU
  memory. Flutter may also evict entries under its normal cache policy.
- Character metadata starts loading alongside application initialization.
- Native task state continues loading while a detail is open. Voice, selection,
  and task updates defer the covered home rebuild until dismissal; the modal's
  own acknowledgement, postpone and edit actions remain active. Repeated events
  coalesce into one home refresh. No microphone lifecycle changes are included.
- The outer detail scroll view uses independently painted sliver children rather
  than a single long column. The separate long-text viewport and pinned edit
  button remain. Original images, day/night palettes, gradients and framing are
  unchanged; no additional images or runtime blur are introduced.

## Correctness and visual checks

The test suite checks decoded-cache survival after dismissal, bounded retention,
memory-pressure clearing, no covered-home rebuild on opening or native state
updates, and delivery of the latest task data after dismissal. Small-screen
tests use actual outer-viewport gestures to reach lazily created audio actions;
dragging the nested text viewport is a different operation.

Six screenshots cover light/dark themes with banner, portrait and missing-art
voices. The screenshot harness substitutes its bundled Chinese font; phone text
uses the platform font.

## AOT emulator experiment

`.github/workflows/detail-performance.yml` builds the same profile test harness
around baseline and current Flutter UI. A plain Android wrapper and mocked native
channel deliberately isolate rendering from scheduling, ASR/TTS, recording and
system dialogs. These are **not shipping APKs**. Production Flutter pages, image
assets, local theme generation and detail navigation are used in both versions.

Both run sequentially on the same Android 15 x86_64 emulator with KVM and
SwiftShader, with animations enabled. For each home/history route and each voice
115 (banner), 228 (portrait), 803 (no artwork), the harness opens and closes the
detail three times. It records opening, outer-content scrolling and nested-text
scrolling separately: 54 measurements per revision. Text, dimensions and gesture
durations are identical. Metadata is loaded before navigation in both builds.

`SchedulerBinding.addTimingsCallback` supplies real engine build/raster timings;
timestamp filtering excludes frames outside each measured action. The harness
waits for batched delivery, then persists every sample rather than merely a test
runtime or an average FPS. `tool/summarize_detail_benchmark.py` reports medians,
90th percentiles and frame counts above 16.67/8.33 ms. Those thresholds describe
work duration, not a direct measurement of presented FPS.

Visit zero means the first open in that route/voice group, not necessarily a
process-wide cold cache. Repeated visits are reported separately. Shader caches,
host scheduling and software GPU rendering can affect results; emulator timings
do not establish real-phone frame rates or microphone contention behavior.

Run on a connected device with the normal Flutter environment:

```sh
flutter test integration_test/detail_performance_test.dart --profile -d DEVICE_ID
```

For the standalone emulator procedure, follow the workflow's plain-wrapper
build, install and `tool/run_detail_benchmark.py` steps. The regular application
build continues to use `tool/bootstrap.sh` and the production native wrapper.
