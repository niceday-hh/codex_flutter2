import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'app_style.dart';
import 'app_error.dart';
import 'reminder.dart';

const vibrations = {'system': '系统默认', 'off': '关闭', 'once': '振动一次', 'twice': '振动两次', 'three': '振动三次', 'strong': '长振动两次'};
const vibrationHints = {
  'system': '节奏和次数由系统决定，不导入“三次”节奏', 'off': '不请求通知振动',
  'once': '1次250毫秒短振动', 'twice': '2次250毫秒短振动，间隔200毫秒',
  'three': '3次200毫秒短振动，每次间隔200毫秒', 'strong': '2次700毫秒长振动，间隔250毫秒',
};
String vibrationLabel(String value) => vibrations[value] ?? '振动三次';

Future<String?> chooseVibration(BuildContext context, String current) => showModalBottomSheet<String>(
  context: context, showDragHandle: true, isScrollControlled: true,
  builder: (_) => VibrationPicker(current: current));

class VibrationPicker extends StatefulWidget {
  final String current;
  const VibrationPicker({super.key, required this.current});
  @override State<VibrationPicker> createState() => _VibrationPickerState();
}
class _VibrationPickerState extends State<VibrationPicker> {
  String message = '点击右侧图标试振，试振不会更改当前选择。';
  String? active;
  bool failed = false;
  Timer? done;
  @override void dispose() { done?.cancel(); super.dispose(); }
  Future<void> _preview(String mode, String label) async {
    if (active != null) return;
    setState(() { active = mode; failed = false; message = '正在试振：$label…'; });
    try {
      final response = await native.invokeMethod<String>('previewVibration', mode);
      if (response == null) throw StateError('试振没有返回结果，请重试');
      final result = jsonDecode(response) as Map<String, dynamic>;
      if (result['requested'] != true) throw StateError('试振请求未完成，请重试');
      if (!mounted) return;
      done = Timer(Duration(milliseconds: ((result['durationMs'] as num?)?.toInt() ?? 1000).clamp(1, 2000).toInt()), () {
        if (!mounted) return;
        setState(() { active = null; message = '已发送$label试振请求。没有感到振动？请检查手机的提醒振动和勿扰中的闹钟设置。'; });
      });
    } catch (error) {
      if (mounted) setState(() { active = null; failed = true; message = niceError(error); });
    }
  }
  @override Widget build(BuildContext context) => SafeArea(child: ConstrainedBox(
    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .85),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Padding(padding: EdgeInsets.all(12), child: Text('振动模式', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
      Semantics(liveRegion: true, child: Container(width: double.infinity,
        margin: const EdgeInsets.fromLTRB(20, 2, 20, 12), padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: failed ? const Color(0xFFFFEFE5) : lavender, borderRadius: BorderRadius.circular(16)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(failed ? Icons.info_outline : active != null ? Icons.vibration : Icons.check_circle_outline,
            color: failed ? const Color(0xFFA75A28) : purple, size: 21), const SizedBox(width: 10),
          Expanded(child: Text(message, key: const ValueKey('vibration-feedback'), style: const TextStyle(fontSize: 13, height: 1.5))),
        ]))),
      Flexible(child: SingleChildScrollView(child: Column(children: vibrations.entries.map((e) => ListTile(
        title: Text(e.value), subtitle: Text(vibrationHints[e.key]!, style: const TextStyle(fontSize: 12)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (e.key == widget.current) const Icon(Icons.check_rounded, color: purple),
          if (e.key != 'system' && e.key != 'off') IconButton(tooltip: '试振${e.value}',
            icon: active == e.key ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.vibration, color: purple),
            onPressed: active == null ? () => _preview(e.key, e.value) : null),
        ]), onTap: () => Navigator.pop(context, e.key))).toList()))),
      const Padding(padding: EdgeInsets.fromLTRB(20, 10, 20, 20), child: Text(
        '试振和实际提醒使用相同的振动用途，由系统振动与勿扰中的闹钟设置决定。实际提醒还受通知通道设置控制；系统默认节奏请用15秒通知测试。',
        style: TextStyle(color: muted, fontSize: 12, height: 1.5))),
    ])));
}
