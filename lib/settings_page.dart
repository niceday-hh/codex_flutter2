import 'package:flutter/material.dart';
import 'app_style.dart';

enum SettingsCategory { reminders, voiceInput, speech, background, data, help }

class SettingsSection {
  final SettingsCategory category;
  final String title, subtitle, keywords;
  final IconData icon;
  const SettingsSection(this.category, this.title, this.subtitle, this.icon, this.keywords);
  bool matches(String query) => '$title $subtitle $keywords'.toLowerCase().contains(query.toLowerCase());
}

const settingsSections = [
  SettingsSection(SettingsCategory.reminders, '提醒与通知', '铃声、振动与再次提醒', Icons.notifications_none_rounded,
    '默认展示方式 默认锁屏显示 默认样式 系统设置 振动模式 铃声 选择系统铃声 未读再次提醒间隔 提醒总次数 尝试亮屏 亮屏弹窗增强'),
  SettingsSection(SettingsCategory.voiceInput, '语音录入', '免手预听与自动停录', Icons.mic_none_rounded,
    '离线语音识别 打开应用后预听语音指令 连续安静后自动结束录音 自动停录等待 静音等待 试用免手输入 本机离线'),
  SettingsSection(SettingsCategory.speech, '语音播报', '音色、语速与角色组', Icons.volume_up_outlined,
    '我的角色组 音色 语速 随机 分组 锁屏播报 语音准备状态 重新准备提醒语音 VITS'),
  SettingsSection(SettingsCategory.background, '后台与权限', '可靠提醒与系统授权', Icons.shield_outlined,
    '可靠提醒模式 提醒服务状态 通知权限 锁屏内容保护 精确定时权限 后台运行 电池优化 应用系统设置 荣耀应用启动管理'),
  SettingsSection(SettingsCategory.data, '任务与数据', '历史记录、备份与导入', Icons.storage_outlined,
    '历史任务 划掉通知后询问整理方式 导出备忘录 合并导入备忘录 数据迁移'),
  SettingsSection(SettingsCategory.help, '帮助与诊断', '提醒自检与使用帮助', Icons.help_outline_rounded,
    '检查系统通知与锁屏设置 测试提醒完成后自动删除 15秒后发送测试提醒 系统闹钟排程 最近实际触发 最近恢复排程 导出提醒诊断 通知样式 固定发布签名 使用提示'),
];

class SettingsPage extends StatefulWidget {
  final Future<void> Function(SettingsSection) onOpen;
  final String version;
  const SettingsPage({super.key, required this.onOpen, required this.version});
  @override State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final search = TextEditingController();
  @override void dispose() { search.dispose(); super.dispose(); }
  Widget _group(List<SettingsSection> sections) => Container(
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFEFEFF4))),
    child: Column(children: [for (var i = 0; i < sections.length; i++) ...[
      if (i > 0) const Divider(height: 1, indent: 76, endIndent: 18, color: Color(0xFFF0EFF5)),
      ListTile(key: ValueKey('settings-${sections[i].category.name}'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(width: 43, height: 43, decoration: BoxDecoration(color: lavender, borderRadius: BorderRadius.circular(14)),
          child: Icon(sections[i].icon, color: purple, size: 24)),
        title: Text(sections[i].title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        subtitle: Padding(padding: const EdgeInsets.only(top: 4), child: Text(sections[i].subtitle,
          style: const TextStyle(color: muted, fontSize: 12, height: 1.5))),
        trailing: const Icon(Icons.chevron_right_rounded, color: muted, size: 21),
        onTap: () { FocusScope.of(context).unfocus(); widget.onOpen(sections[i]); }),
    ]]));
  Widget _label(String title) => Padding(padding: const EdgeInsets.fromLTRB(4, 26, 4, 10),
    child: Text(title, style: const TextStyle(color: muted, fontSize: 12, fontWeight: FontWeight.w600)));
  @override Widget build(BuildContext context) {
    final query = search.text.trim();
    final matches = settingsSections.where((s) => s.matches(query)).toList();
    return ListView(key: const PageStorageKey('settings-overview'), padding: const EdgeInsets.fromLTRB(22, 26, 22, 24), children: [
      Text('设置', style: Theme.of(context).textTheme.headlineLarge), const SizedBox(height: 8),
      const Text('让提醒，更适合你。', style: TextStyle(color: muted)), const SizedBox(height: 24),
      TextField(key: const ValueKey('settings-search'), controller: search, onChanged: (_) => setState(() {}),
        decoration: InputDecoration(hintText: '搜索设置', prefixIcon: const Icon(Icons.search_rounded, color: muted),
          suffixIcon: query.isEmpty ? null : IconButton(tooltip: '清空搜索', icon: const Icon(Icons.close_rounded),
            onPressed: () { search.clear(); setState(() {}); }),
          contentPadding: const EdgeInsets.symmetric(vertical: 12), fillColor: const Color(0xFFEEEDF3))),
      if (query.isEmpty) ...[
        _label('偏好设置'), _group(settingsSections.take(4).toList()),
        _label('管理与支持'), _group(settingsSections.skip(4).toList()),
      ] else ...[
        _label('搜索结果 · ${matches.length} 个分类'),
        if (matches.isNotEmpty) _group(matches)
        else const Padding(padding: EdgeInsets.symmetric(vertical: 36), child: Text('没有找到相关设置，试试“铃声”或“语音”。',
          textAlign: TextAlign.center, style: TextStyle(color: muted))),
      ],
      const SizedBox(height: 24), Text('超级提醒 · ${widget.version}', textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 11, color: muted)),
    ]);
  }
}

class SettingsSheet extends StatelessWidget {
  final SettingsSection section;
  final Listenable changes;
  final List<Widget> Function(BuildContext) items;
  const SettingsSheet({super.key, required this.section, required this.changes, required this.items});
  @override Widget build(BuildContext context) => DraggableScrollableSheet(
    initialChildSize: .88, minChildSize: .55, maxChildSize: .97, expand: false,
    builder: (context, controller) => FrostedPanel(child: Column(children: [
      Padding(padding: const EdgeInsets.only(top: 10, bottom: 10), child: Container(width: 34, height: 4,
        decoration: BoxDecoration(color: const Color(0xFFD5D2DF), borderRadius: BorderRadius.circular(4)))),
      Padding(padding: const EdgeInsets.fromLTRB(23, 0, 14, 14), child: Row(children: [
        Expanded(child: Text(section.title, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800))),
        IconButton.filledTonal(tooltip: '关闭设置分类', onPressed: () {
          if (ModalRoute.of(context)?.isCurrent == true) Navigator.pop(context);
        },
          style: IconButton.styleFrom(backgroundColor: lavender, foregroundColor: muted), icon: const Icon(Icons.close_rounded)),
      ])),
      Expanded(child: AnimatedBuilder(animation: changes, builder: (context, _) => ListView(
        key: ValueKey('settings-sheet-${section.category.name}'), controller: controller,
        padding: const EdgeInsets.only(bottom: 32), children: items(context)))),
    ])));
}
