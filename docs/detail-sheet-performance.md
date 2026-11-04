# Reminder detail performance

The baseline is v0.9.21 (`6169648a01e27218f5abec541123282b1b79f163`).

## Changes

- Character images no longer evict themselves on every sheet dismissal. An
  insertion-ordered working set keeps at most six recently displayed assets,
  with a 6 MiB estimated RGBA budget. Trimming and memory-pressure events evict
  old entries. This budget describes tracked decoded pixels, not total app/GPU
  memory. Flutter may also evict entries under its normal cache policy.
- Native task state continues loading while a detail is open. Voice, selection,
  task updates and home entrance completion defer the covered home rebuild until
  dismissal; the modal's
  own acknowledgement, postpone and edit actions remain active. Repeated events
  coalesce into one home refresh. No microphone lifecycle changes are included.
- The outer detail retains its original scroll view, column and paint structure.
  The small number of blocks remain mounted, preserving nested text offsets and
  audio ownership without a lazy list or additional keep-alive state.
  The long-text viewport and pinned edit
  button remain. Original images, day/night palettes, gradients and framing are
  unchanged; no additional images or runtime blur are introduced.

## Correctness and visual checks

The test suite checks decoded-cache survival after dismissal, bounded retention,
memory-pressure clearing, no covered-home rebuild on opening or native state
updates, and delivery of the latest task data after dismissal. Small-screen
tests use actual outer-viewport gestures to reach audio actions;
dragging the nested text viewport is a different operation.

Six screenshots cover light/dark themes with banner, portrait and missing-art
voices. The screenshot harness substitutes its bundled Chinese font; phone text
uses the platform font.

## AOT emulator experiment

### Renderer-specific cache limitation

The benchmark logs identify Impeller OpenGLES. In the project's pinned Flutter
3.35.7 engine, both
[GPUSurfaceGLImpeller](https://github.com/flutter/flutter/blob/3.35.7/engine/src/flutter/shell/gpu/gpu_surface_gl_impeller.cc)
and
[GPUSurfaceVulkanImpeller](https://github.com/flutter/flutter/blob/3.35.7/engine/src/flutter/shell/gpu/gpu_surface_vulkan_impeller.cc)
return `false` from `EnableRasterCache()`. A repaint boundary can isolate display
list recording, but it does not thereby guarantee a cached bitmap of all image
and gradient layers on this renderer. A small source WebP does not remove the
screen-sized blending workload. This helps explain why extra paint boundaries
did not consistently improve this experiment; it does not prove the cause on an
unprofiled phone.

This is separate from Flutter's decoded `ImageCache`: retaining the selected
asset still avoids unnecessary decoding and image/texture preparation on repeat
visits. No global renderer switch, framebuffer snapshots or extra image files
are introduced by the shipping implementation.

### First experiment and implementation choice

[Run 41568990937](https://github.com/niceday-hh/codex_flutter2/actions/runs/41568990937)
passed all 108 captures (54 per revision), using optimized commit
`076e5b765081adcfa668d8106d1d767e51e040bc`. Its raw samples and comparison are
preserved in [iteration-1](performance/detail-sheet/iteration-1/).

That experiment used a sliver list. Repeated home/banner opening UI P90 improved
from 28.61 to 10.07 ms, but the first banner open had a 1055.86 ms UI outlier
(baseline P90 68.29 ms), and some nested-text UI P90 values increased. Those
results do not justify declaring every interaction faster. Software raster P90
was hundreds of milliseconds even without source changes, so these values must
not be interpreted as phone performance.

The second experiment kept the original column but added per-block repaint
boundaries. [Run 41583849879](https://github.com/niceday-hh/codex_flutter2/actions/runs/41583849879)
also passed 108 captures, with optimized commit
`0615018d0f8aff8b2f6ad6c6a3e1281d88c6abb6` running before baseline. Its samples
are in [iteration-2](performance/detail-sheet/iteration-2/). It did not demonstrate
a consistent raster improvement either (for example, repeated home/banner raster
P90 260.32 -> 281.61 ms). Initial UI outliers and order-dependent results prevent
an unconditional performance claim.

The shipping implementation therefore restores original painting and metadata
loading too. Only bounded image retention and covered-home rebuild coalescing
remain, supported directly by behavior tests. Continuous scrolling is not marked
as solved. The final rendering experiment still runs optimized before baseline
with identical fixtures; results cannot establish real-phone FPS.

`.github/workflows/detail-performance.yml` builds the same profile test harness
around baseline and current Flutter UI. A plain Android wrapper and mocked native
channel deliberately isolate rendering from scheduling, ASR/TTS, recording and
system dialogs. These are **not shipping APKs**. Production Flutter pages, image
assets, local theme generation and detail navigation are used in both versions.

Both run sequentially on the same Android 15 x86_64 Pixel 5 emulator with KVM and
SwiftShader, with animations enabled. For each home/history route and each voice
115 (banner), 228 (portrait), 803 (no artwork), the harness opens and closes the
detail three times. It records opening, outer-content scrolling and nested-text
scrolling separately: 54 measurements per revision. Text, dimensions and gesture
durations are identical. Metadata is loaded before navigation in both builds.

`SchedulerBinding.addTimingsCallback` supplies real engine build/raster timings.
The harness drains previous batches before each action and waits for late raster
completions afterwards, without comparing engine timestamps to a different clock.
It persists every sample rather than merely a test
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

## Shipping-scope experiment

[Run 41586064724](https://github.com/niceday-hh/codex_flutter2/actions/runs/41586064724)
passed all 108 captures for baseline versus commit
`359d428b8d9daa655f23f365a32b826ec35bd98c`, with original paint/layout and only
decoded-image retention plus covered-home update coalescing. All original records
are preserved in [final](performance/detail-sheet/final/).

The results **do not establish a consistent latency or FPS improvement** on this
software GPU. For example, repeated home/banner opening UI P90 was 8.79 ->
11.33 ms and raster P90 262.76 -> 334.45 ms; repeated history/portrait opening UI
P90 was 7.09 -> 5.19 ms and raster P90 194.04 -> 192.56 ms. The first optimized
banner opening also contained a 730.68 ms UI P90 outlier. Those negative and
mixed measurements are retained, not discarded. Cold process/font/GPU work,
late timing batches and host scheduling limit action-level causal conclusions.

Retaining the two shipping changes is justified by the directly checked removal
of redundant work: decoded images survive sheet dismissal within bounded memory,
and native/voice updates do not rebuild the covered home and its tabs. The
shipping widget regression also opens at 300 ms while the entrance is active,
covering its completion callback. This last callback guard is outside the profile
harness's measured windows, which begin after startup has settled.

Continuous-scroll jank and first-ever opening latency remain unresolved on a
real phone. Further work should begin with a physical-device trace; do not infer
that changing source resolution, more repaint boundaries, or a global renderer
switch is a verified remedy from these emulator numbers.

## Baked backdrop layers

The detail sheet used to paint four full-screen gradient fills on every frame:
two radial halos, a horizontal left-to-right wash and a vertical bottom fade.
They are now rendered once off-screen into two textures — an opaque underlay
(surface colour plus both halos) and an alpha overlay (the two linear ramps) —
with the character art unchanged between them.

Two layers rather than one is deliberate: the horizontal wash sits *above* the
art, so folding the art into the underlay would change what covers it.

Software-raster timings from `flutter_tester` (393×760 logical, 2× density,
median of five, art included) are **not** a raster win:

| Stack | Per-frame paint |
|---|---|
| four gradients + art | ≈6.8 ms |
| two baked textures + art | ≈6.7 ms |

A CPU rasteriser samples a texture and evaluates a gradient at roughly the same
per-pixel cost. On a tile-based phone GPU the relevant difference is overdraw:
four alpha blends become one opaque write plus one alpha blend. That claim has
to be checked with the profile harness on a device; no number from this
software renderer should be read as FPS.

What the change does verify in-repo:

- **Pixel identity.** Over the same art, the baked pair differs from the live
  gradients by at most 4/255 on a 3× surface, with 0.02% of subpixels above
  3/255 (ramp shoulders only). A 1.5× bake reaches 116/255 and is rejected, so
  the cache bakes at 2×.
- **Live swap.** The sheet starts on the painters, then rebuilds on textures
  once the offscreen render lands, keeping identical geometry
  (`test/backdrop_bake_test.dart`).
- **Bounded retention.** Three entries, 28 MiB, LRU; the last entry is never
  evicted, since one phone-sized pair can exceed the budget by itself.

### Storage

`ui.Image` lives in engine memory. Persisting it would cost a PNG encode
(hundreds of milliseconds for a phone-sized sheet), a decode and a texture
upload on the next launch, keyed by theme, size and density — more work than
the offscreen render it replaces, and stale as soon as any of those change.
Nothing is written to disk.

### Async and prewarm

`Picture.toImage` records on the UI thread (microseconds) and rasterises on the
raster thread, so the bake never blocks Dart. It cannot move to an isolate:
`ui.Picture` is not transferable and the offscreen surface belongs to the
engine. `HomePage` asks the cache to bake the next two tasks' backdrops 600 ms
after the list settles; by the time a sheet opens the textures are usually
already there. A missed prewarm falls back to the painters for the entrance and
swaps in when the bake lands, so the first frame never waits.
