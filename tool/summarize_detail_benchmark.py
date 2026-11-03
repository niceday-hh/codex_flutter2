"""Summarize UI/raster durations, without presenting emulator numbers as phone FPS."""
import json
import math
from pathlib import Path
import statistics


def percentile(values, fraction):
    ordered = sorted(values)
    return ordered[max(0, math.ceil(len(ordered) * fraction) - 1)] / 1000


def summarize(document):
    groups = {}
    for row in document['measurements']:
        # Keep first and repeated opens separate. visit=0 means first visit in
        # this route/voice group, not necessarily a process-wide cold cache.
        key = f"{row['route']}/{row['speaker']}/{row['phase']}/{'first' if row['visit'] == 0 else 'repeat'}"
        sample = groups.setdefault(key, {'ui': [], 'raster': []})
        sample['ui'].extend(row['ui_us'])
        sample['raster'].extend(row['raster_us'])
    result = {}
    for key, sample in groups.items():
        ui, raster = sample['ui'], sample['raster']
        result[key] = {'frames': len(ui), 'ui_p50_ms': statistics.median(ui) / 1000,
            'ui_p90_ms': percentile(ui, .9), 'raster_p50_ms': statistics.median(raster) / 1000,
            'raster_p90_ms': percentile(raster, .9),
            'over_16_67_ms': sum(max(a, b) > 16667 for a, b in zip(ui, raster)),
            'over_8_33_ms': sum(max(a, b) > 8333 for a, b in zip(ui, raster))}
    return result


if __name__ == '__main__':
    reports = {name: summarize(json.loads(Path(f'detail-{name}.json').read_text()))
               for name in ('baseline', 'optimized')}
    Path('detail-comparison.json').write_text(json.dumps(reports, indent=2))
    for key in reports['baseline']:
        before, after = reports['baseline'][key], reports['optimized'][key]
        print(f"{key}: UI p90 {before['ui_p90_ms']:.2f} -> {after['ui_p90_ms']:.2f} ms; "
              f"raster p90 {before['raster_p90_ms']:.2f} -> {after['raster_p90_ms']:.2f} ms")
