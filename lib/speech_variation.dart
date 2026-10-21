import 'package:flutter/material.dart';
import 'app_style.dart';

class SpeechVariation {
  final double noise, noiseW;
  const SpeechVariation(this.noise, this.noiseW);
}

Future<SpeechVariation?> chooseSpeechVariation(BuildContext context, {required double noise,
  required double noiseW, required bool allowDefault, required double defaultNoise, required double defaultNoiseW}) {
  var inherited = allowDefault && noise == 0 && noiseW == 0;
  var value = noise == 0 ? defaultNoise : noise, timing = noiseW == 0 ? defaultNoiseW : noiseW;
  return showModalBottomSheet<SpeechVariation>(context: context, isScrollControlled: true, showDragHandle: true,
    builder: (c) => StatefulBuilder(builder: (c, update) => SafeArea(child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24), child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('高级语音设置', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        const Text('调整同一音色的生成变化。新的参数会用于重新准备音频；选定的版本会保存并重复使用。',
          style: TextStyle(color: muted, height: 1.5)),
        if (allowDefault) SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('跟随默认参数'),
          value: inherited, onChanged: (v) => update(() => inherited = v)),
        const SizedBox(height: 20),
        Text('声音变化 · ${(inherited ? defaultNoise : value).toStringAsFixed(3)}',
          style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6), const Text('noise_scale · 影响声音细节的变化幅度，不是明确的情绪强度。',
          style: TextStyle(color: muted, fontSize: 12, height: 1.5)),
        Slider(key: const ValueKey('speech-noise'), min: .1, max: 1, divisions: 90,
          value: (inherited ? defaultNoise : value).clamp(.1, 1).toDouble(),
          label: value.toStringAsFixed(3), onChanged: inherited ? null : (v) => update(() => value = (v * 1000).round() / 1000)),
        const SizedBox(height: 12),
        Text('节奏变化 · ${(inherited ? defaultNoiseW : timing).toStringAsFixed(3)}',
          style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6), const Text('noise_scale_w · 影响音素时长的变化幅度；整体快慢仍由语速设置控制。',
          style: TextStyle(color: muted, fontSize: 12, height: 1.5)),
        Slider(key: const ValueKey('speech-noise-w'), min: .1, max: 1, divisions: 90,
          value: (inherited ? defaultNoiseW : timing).clamp(.1, 1).toDouble(),
          label: timing.toStringAsFixed(3), onChanged: inherited ? null : (v) => update(() => timing = (v * 1000).round() / 1000)),
        const SizedBox(height: 12),
        TextButton(onPressed: () => update(() { inherited = false; value = .6; timing = .668; }),
          child: const Text('恢复推荐值 0.600 / 0.668')),
        const SizedBox(height: 12),
        FilledButton(onPressed: () => Navigator.pop(c, SpeechVariation(inherited ? 0 : value, inherited ? 0 : timing)),
          child: const Text('使用这些参数')),
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
      ])))));
}
