import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'asr.dart';
import 'reminder.dart';
import 'voice_parser.dart';

const purple = Color(0xFF7252F6);
const ink = Color(0xFF25213A);
const muted = Color(0xFF8A859C);
const canvas = Color(0xFFF8F6FC);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.white, systemNavigationBarIconBrightness: Brightness.dark,
  ));
  runApp(const MemoApp());
}

class MemoApp extends StatelessWidget {
  const MemoApp({super.key});
  @override Widget build(BuildContext context) => MaterialApp(
    title: '定时备忘录', debugShowCheckedModeBanner: false,
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: purple, surface: Colors.white),
      scaffoldBackgroundColor: canvas,
      textTheme: const TextTheme(
        headlineLarge: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: ink),
        headlineSmall: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: ink),
        bodyLarge: TextStyle(fontSize: 16, color: ink, height: 1.5),
        bodyMedium: TextStyle(fontSize: 14, color: ink, height: 1.45),
      ),
      appBarTheme: const AppBarTheme(backgroundColor: canvas, foregroundColor: ink, centerTitle: true),
      inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: canvas,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none)),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
        backgroundColor: purple, foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)))),
    ),
    home: const MemoHome(),
  );
}

class MemoHome extends StatefulWidget {
  const MemoHome({super.key});
  @override State<MemoHome> createState() => _MemoHomeState();
}

class _MemoHomeState extends State<MemoHome> with WidgetsBindingObserver {
  final store = MemoStore();
  int tab = 0;
  bool loading = true;
  String? error;
  DateTime selectedDate = DateTime.now();
  DateTime calendarMonth = DateTime(DateTime.now().year, DateTime.now().month);

  @override void initState() {
    super.initState(); WidgetsBinding.instance.addObserver(this);
    native.setMethodCallHandler((call) async {
      if (call.method == 'openReminder') { await reload(); if (mounted) openById(call.arguments as int); }
    });
    initialize();
  }
  Future<void> initialize() async {
    try { await native.invokeMethod('restore'); } catch (_) {}
    await reload();
    try {
      final id = await native.invokeMethod<int>('initialReminderId');
      if (mounted && id != null && id > 0) openById(id);
    } catch (_) {}
  }
  @override void dispose() {
    WidgetsBinding.instance.removeObserver(this); native.setMethodCallHandler(null); super.dispose();
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) reload();
  }
  Future<void> reload() async {
    try {
      await store.load();
      if (mounted) setState(() { loading = false; error = null; });
    } catch (e) {
      if (mounted) setState(() { loading = false; error = niceError(e); });
    }
  }
  void toast(String s) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }
  Future<void> edit([Reminder? existing]) async {
    final draft = existing == null ? store.draft() : Reminder.fromJson({...existing.toJson()});
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => ReminderEditor(reminder: draft, store: store)));
    if (saved == true) { await reload(); toast('提醒已保存'); }
  }
  void openById(int id) {
    final matches = store.reminders.where((r) => r.id == id);
    if (matches.isNotEmpty) viewReminder(matches.first);
  }
  Future<void> viewReminder(Reminder r) async {
    await showModalBottomSheet<void>(context: context, isScrollControlled: true,
      backgroundColor: Colors.white, showDragHandle: true,
      builder: (sheetContext) => ReminderDetail(reminder: r, onAck: () async {
        await store.ack(r);
        if (sheetContext.mounted) Navigator.pop(sheetContext);
        await reload();
      }, onEdit: () { Navigator.pop(sheetContext); edit(r); }));
  }
  Future<void> remove(Reminder r) async {
    final yes = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('删除提醒？'), content: const Text('删除后，本条提醒及剩余重提醒都会取消。'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
        TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('删除'))]));
    if (yes == true) {
      try { await store.delete(r.id); await reload(); } catch (e) { toast(niceError(e)); }
    }
  }
  @override Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: loading ? const Center(child: CircularProgressIndicator())
      : error != null ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(error!), TextButton(onPressed: reload, child: const Text('重新加载'))]))
      : IndexedStack(index: tab, children: [homePage(), calendarPage(),
        VoicePage(store: store, onSaved: reload), settingsPage()])),
    floatingActionButton: !loading && error == null && (tab == 0 || tab == 1)
      ? FloatingActionButton(onPressed: () => edit(), backgroundColor: purple,
          foregroundColor: Colors.white, tooltip: '新建提醒', child: const Icon(Icons.add_rounded, size: 32)) : null,
    bottomNavigationBar: NavigationBar(backgroundColor: Colors.white,
      selectedIndex: tab, indicatorColor: const Color(0xFFECE5FF),
      onDestinationSelected: (i) => setState(() => tab = i), destinations: const [
        NavigationDestination(icon: Icon(Icons.description_outlined), selectedIcon: Icon(Icons.description_rounded), label: '备忘录'),
        NavigationDestination(icon: Icon(Icons.calendar_month_outlined), label: '日历'),
        NavigationDestination(icon: Icon(Icons.mic_none_rounded), selectedIcon: Icon(Icons.mic_rounded), label: '语音'),
        NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings_rounded), label: '设置'),
      ]),
  );
  Widget header(String title, String subtitle, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 22, 24, 22), child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 7), Text(subtitle, style: const TextStyle(color: muted)),
      ])), if (trailing != null) trailing,
    ]));
  Widget homePage() {
    final list = List<Reminder>.of(store.reminders)..sort((a, b) {
      if (a.unread != b.unread) return a.unread ? -1 : 1;
      return a.displayDate.compareTo(b.displayDate);
    });
    final active = list.where((r) => r.enabled || r.unread).toList();
    final complete = list.where((r) => r.completed).toList();
    final now = DateTime.now();
    return RefreshIndicator(onRefresh: reload, child: ListView(
      padding: const EdgeInsets.only(bottom: 90), physics: const AlwaysScrollableScrollPhysics(), children: [
      header('备忘录', '把重要的事，交给提醒', trailing: IconButton(
        icon: const Icon(Icons.tune_rounded), onPressed: () => setState(() => tab = 3))),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: Text(
        '${now.month}月${now.day}日  周${weekdays[now.weekday - 1]}', style: const TextStyle(fontWeight: FontWeight.w600))),
      const SizedBox(height: 16),
      if (active.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF8465FF), Color(0xFF6240E2)]),
          borderRadius: BorderRadius.circular(26), boxShadow: [BoxShadow(color: purple.withValues(alpha: 0.18), blurRadius: 20, offset: const Offset(0, 8))]),
          child: InkWell(onTap: () => viewReminder(active.first), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(active.first.unread ? Icons.mark_email_unread_outlined : Icons.notifications_active_outlined, color: Colors.white70, size: 19),
              const SizedBox(width: 8), Text(active.first.unread ? '待确认提醒' : '下一条提醒', style: const TextStyle(color: Colors.white70)),
              const Spacer(), const Icon(Icons.arrow_forward_rounded, color: Colors.white70, size: 20)]),
            const SizedBox(height: 14), Text(active.first.time, style: const TextStyle(fontSize: 38, color: Colors.white, fontWeight: FontWeight.w700)),
            const SizedBox(height: 5), Text(active.first.text, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10), Text('${dateLabel(active.first.displayDate)} · ${active.first.repeatLabel}', style: const TextStyle(color: Colors.white70)),
          ])))),
      if (store.status['notifications'] != true || store.status['exact'] != true) permissionBanner(),
      section('待办提醒', '${active.length} 条'),
      if (active.isEmpty) emptyState('留一点空间，给重要的事', '点击右下角 +，或用语音创建第一条提醒'),
      ...active.map(reminderCard),
      if (complete.isNotEmpty) ...[section('已完成', '${complete.length} 条'), ...complete.map(reminderCard)],
    ]));
  }
  Widget section(String title, String subtitle) => Padding(padding: const EdgeInsets.fromLTRB(24, 26, 24, 12),
    child: Row(children: [Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      const Spacer(), Text(subtitle, style: const TextStyle(color: muted, fontSize: 12))]));
  Widget permissionBanner() => Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
    child: InkWell(onTap: () => setState(() => tab = 3), borderRadius: BorderRadius.circular(18),
      child: Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: const Color(0xFFFFF0E4), borderRadius: BorderRadius.circular(18)),
        child: const Row(children: [Icon(Icons.info_outline, color: Color(0xFFB96C29)), SizedBox(width: 10),
          Expanded(child: Text('请在设置中开启通知与精确定时权限', style: TextStyle(fontSize: 13))), Icon(Icons.chevron_right)]))));
  Widget reminderCard(Reminder r) {
    final card = Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 12), child: Surface(
      padding: const EdgeInsets.all(16), child: InkWell(onTap: () => viewReminder(r), child: Row(children: [
        Container(width: 4, height: 46, decoration: BoxDecoration(color: r.completed ? const Color(0xFFD7D4DF)
          : r.unread ? purple : const Color(0xFFFFC598), borderRadius: BorderRadius.circular(4))),
        const SizedBox(width: 12), Text(r.time, style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700, color: r.completed ? muted : ink)),
        const SizedBox(width: 15), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(r.text, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: r.completed ? muted : ink, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6), Wrap(spacing: 5, runSpacing: 4, children: [
            Tag(r.completed ? '已完成' : r.unread ? '未读 ${r.attempts}/${r.totalCount}' : r.repeatLabel),
            Text(dateLabel(r.displayDate), style: const TextStyle(fontSize: 11, color: muted)),
          ]),
        ])), PopupMenuButton<String>(tooltip: '更多操作', onSelected: (v) => v == 'edit' ? edit(r) : remove(r),
          itemBuilder: (_) => const [PopupMenuItem(value: 'edit', child: Text('编辑')), PopupMenuItem(value: 'delete', child: Text('删除'))]),
      ]))));
    if (!r.unread) return card;
    return Dismissible(key: ValueKey('unread-${r.id}-${r.activeOccurrence}-${r.attempts}'),
      background: Container(color: const Color(0xFFECE5FF), alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 30), child: const Text('确认已读', style: TextStyle(color: purple))),
      secondaryBackground: Container(color: const Color(0xFFECE5FF), alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 30), child: const Text('确认已读', style: TextStyle(color: purple))),
      confirmDismiss: (_) async {
        try { await store.ack(r); await reload(); toast('已确认，剩余重提醒已取消'); }
        catch (e) { toast(niceError(e)); }
        return false;
      }, child: card);
  }
  Widget calendarPage() {
    final first = DateTime(calendarMonth.year, calendarMonth.month);
    final count = DateTime(first.year, first.month + 1, 0).day;
    final offset = first.weekday - 1;
    final list = store.reminders.where((r) => occursOn(r, selectedDate)).toList()..sort((a, b) => a.time.compareTo(b.time));
    return ListView(padding: const EdgeInsets.only(bottom: 90), children: [
      header('提醒日历', '每一天，都安排得刚刚好'),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Surface(child: Column(children: [
        Row(children: [Expanded(child: Text('${first.year}年${first.month}月', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
          IconButton(onPressed: () => setState(() => calendarMonth = DateTime(first.year, first.month - 1)), icon: const Icon(Icons.chevron_left)),
          IconButton(onPressed: () => setState(() => calendarMonth = DateTime(first.year, first.month + 1)), icon: const Icon(Icons.chevron_right))]),
        Row(children: weekdays.map((s) => Expanded(child: Center(child: Text(s, style: const TextStyle(color: muted))))).toList()),
        const SizedBox(height: 12),
        GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, mainAxisSpacing: 4),
          itemCount: ((count + offset) / 7).ceil() * 7,
          itemBuilder: (_, i) {
            final d = i - offset + 1;
            if (d < 1 || d > count) return const SizedBox.shrink();
            final date = DateTime(first.year, first.month, d);
            final selected = sameDay(date, selectedDate);
            final has = store.reminders.any((r) => occursOn(r, date));
            return InkWell(onTap: () => setState(() => selectedDate = date), borderRadius: BorderRadius.circular(16),
              child: Container(decoration: BoxDecoration(color: selected ? purple : Colors.transparent, borderRadius: BorderRadius.circular(16)),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text('$d', style: TextStyle(color: selected ? Colors.white : ink,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
                  const SizedBox(height: 3), Container(width: 4, height: 4, decoration: BoxDecoration(shape: BoxShape.circle,
                    color: has ? selected ? Colors.white : purple : Colors.transparent))])));
          }),
      ]))),
      section('${selectedDate.month}月${selectedDate.day}日', '${list.length} 个提醒'),
      if (list.isEmpty) emptyState('这一天还没有提醒', '点击 + 添加一件值得记住的事'),
      ...list.map(reminderCard),
    ]);
  }
  Widget settingsPage() => ListView(padding: const EdgeInsets.only(bottom: 30), children: [
    header('设置', '让提醒，更适合你'),
    Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Surface(child: Row(children: [
      Container(width: 54, height: 54, decoration: BoxDecoration(color: purple, borderRadius: BorderRadius.circular(17)),
        child: const Icon(Icons.notifications_rounded, color: Colors.white, size: 32)),
      const SizedBox(width: 16), const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('定时备忘录', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        Text('v0.1.0 · 本地保存 · 离线语音', style: TextStyle(color: muted, fontSize: 12))])),
    ]))),
    section('默认提醒', '新提醒使用这些设置'),
    settingsGroup([
      settingRow(Icons.vibration, '振动模式', vibrationLabel(store.defaults['vibration'] as String? ?? 'three'), () async {
        final v = await chooseVibration(context, store.defaults['vibration'] as String? ?? 'three');
        if (v != null) { store.defaults['vibration'] = v; await persistDefaults(); }
      }),
      SwitchListTile(title: const Text('铃声'), subtitle: const Text('到时播放系统通知铃声'),
        value: store.defaults['sound'] as bool? ?? true, onChanged: (v) async { store.defaults['sound'] = v; await persistDefaults(); }),
      settingRow(Icons.music_note_outlined, '选择系统铃声', (store.defaults['ringtone'] as String? ?? '').isEmpty ? '系统默认' : '已选择', () async {
        try {
          final uri = await native.invokeMethod<String>('pickRingtone', store.defaults['ringtone'] ?? '');
          if (uri != null) { store.defaults['ringtone'] = uri; await persistDefaults(); }
        } catch (e) { toast(niceError(e)); }
      }),
      settingRow(Icons.timer_outlined, '未读再次提醒间隔', '${store.defaults['intervalMinutes'] ?? 5} 分钟', () async {
        final n = await numberDialog(context, '再次提醒间隔（分钟）', store.defaults['intervalMinutes'] as int? ?? 5, 1, 1440);
        if (n != null) { store.defaults['intervalMinutes'] = n; await persistDefaults(); }
      }),
      settingRow(Icons.repeat_rounded, '提醒总次数', '${store.defaults['totalCount'] ?? 3} 次（含首次）', () async {
        final n = await numberDialog(context, '提醒总次数（包含第一次）', store.defaults['totalCount'] as int? ?? 3, 1, 20);
        if (n != null) { store.defaults['totalCount'] = n; await persistDefaults(); }
      }),
      SwitchListTile(title: const Text('尝试亮屏'), subtitle: const Text('不解锁屏幕，受手机系统设置影响'),
        value: store.defaults['wakeScreen'] as bool? ?? true, onChanged: (v) async { store.defaults['wakeScreen'] = v; await persistDefaults(); }),
    ]),
    section('隐私与提醒权限', ''),
    settingsGroup([
      const ListTile(leading: Icon(Icons.lock_outline, color: purple), title: Text('锁屏隐藏内容'),
        subtitle: Text('只显示有待办提醒，解锁后查看正文'), trailing: Icon(Icons.check_circle_outline, color: purple)),
      settingRow(Icons.notifications_none, '通知权限', store.status['notifications'] == true ? '已开启' : '需开启', () async {
        await native.invokeMethod('requestNotifications'); await native.invokeMethod('notificationSettings');
      }),
      settingRow(Icons.alarm_on_rounded, '精确定时权限', store.status['exact'] == true ? '已开启' : '需开启', () => native.invokeMethod('requestExact')),
      settingRow(Icons.battery_saver_outlined, '后台运行', store.status['battery'] == true ? '不受电池优化' : '检查电池优化', () => native.invokeMethod('batterySettings')),
      settingRow(Icons.phonelink_setup_rounded, '应用系统设置', '荣耀应用启动管理', () => native.invokeMethod('appSettings')),
    ]),
    section('语音', ''), settingsGroup([
      const ListTile(leading: Icon(Icons.mic_none_rounded, color: purple), title: Text('离线语音识别'),
        subtitle: Text('中文 Paraformer int8 · 录音不上传'), trailing: Tag('已内置')),
    ]),
    section('使用提示', ''), Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Surface(child: const Text(
      '• 手动划掉系统通知，或在 App 中滑动确认，才算已读。点开通知、横幅自动收起不算已读。\n\n'
      '• 达到总次数后停止再次提醒，但仍保留未读状态。下一次每日／每周提醒重新计数。\n\n'
      '• 荣耀手机请检查应用启动管理，允许自启动与后台运行。系统休眠、勿扰模式、强行停止会影响提醒和亮屏。\n\n'
      '• 未授权精确定时会使用系统近似定时；深度休眠时短间隔重提醒可能延迟。',
      style: TextStyle(color: muted, fontSize: 13, height: 1.7)))),
    if ((store.status['lastError'] as String? ?? '').isNotEmpty) Padding(padding: const EdgeInsets.all(24),
      child: Text('最近的系统提示：${store.status['lastError']}', style: const TextStyle(color: muted, fontSize: 12))),
  ]);
  Future<void> persistDefaults() async {
    try { await store.saveDefaults(); if (mounted) setState(() {}); }
    catch (e) { toast(niceError(e)); }
  }
  Widget settingsGroup(List<Widget> children) => Padding(padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Surface(padding: const EdgeInsets.symmetric(vertical: 4), child: Column(children: children)));
  Widget settingRow(IconData icon, String title, String value, Future<void> Function() action) => ListTile(
    leading: Icon(icon, color: purple), title: Text(title), subtitle: Text(value, style: const TextStyle(color: muted, fontSize: 12)),
    trailing: const Icon(Icons.chevron_right, color: muted), onTap: () async {
      try { await action(); await reload(); } catch (e) { toast(niceError(e)); }
    });
}

class Surface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const Surface({super.key, required this.child, this.padding = const EdgeInsets.all(20)});
  @override Widget build(BuildContext context) => Container(padding: padding, decoration: BoxDecoration(
    color: Colors.white, borderRadius: BorderRadius.circular(22),
    border: Border.all(color: const Color(0xFFF0EDF6)),
    boxShadow: const [BoxShadow(color: Color(0x060E0824), blurRadius: 14, offset: Offset(0, 5))]), child: child);
}
class Tag extends StatelessWidget {
  final String text;
  const Tag(this.text, {super.key});
  @override Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: const Color(0xFFF0EBFF), borderRadius: BorderRadius.circular(8)),
    child: Text(text, style: const TextStyle(fontSize: 11, color: purple)));
}
Widget emptyState(String title, String subtitle) => Padding(padding: const EdgeInsets.all(28), child: Column(children: [
  Container(padding: const EdgeInsets.all(24), decoration: const BoxDecoration(color: Color(0xFFEEE8FF), shape: BoxShape.circle),
    child: const Icon(Icons.notifications_none_rounded, color: purple, size: 45)),
  const SizedBox(height: 20), Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
  const SizedBox(height: 8), Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: muted, fontSize: 13)),
]));
String dateLabel(DateTime d) => '${d.month}月${d.day}日';
bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
bool occursOn(Reminder r, DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  final anchor = DateTime(r.date.year, r.date.month, r.date.day);
  if (r.repeat == 'none') return sameDay(r.date, d);
  if (!r.enabled || day.isBefore(anchor)) return false;
  return r.repeat == 'daily' || r.days.contains(d.weekday);
}
String niceError(Object e) => e is PlatformException ? e.message ?? '操作失败，请重试' : '操作失败：$e';
const vibrations = {'system': '系统默认', 'off': '关闭', 'once': '振动一次', 'twice': '振动两次', 'three': '振动三次', 'strong': '长振动两次'};
String vibrationLabel(String value) => vibrations[value] ?? '振动三次';
Future<String?> chooseVibration(BuildContext context, String current) => showModalBottomSheet<String>(
  context: context, showDragHandle: true, builder: (c) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Padding(padding: EdgeInsets.all(12), child: Text('振动模式', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
    ...vibrations.entries.map((e) => ListTile(title: Text(e.value),
      trailing: e.key == current ? const Icon(Icons.check_rounded, color: purple) : null,
      onTap: () => Navigator.pop(c, e.key))),
  ])));
Future<int?> numberDialog(BuildContext context, String title, int current, int min, int max) async {
  final controller = TextEditingController(text: '$current');
  String? error;
  final value = await showDialog<int>(context: context, builder: (c) => StatefulBuilder(builder: (c, set) => AlertDialog(
    title: Text(title), content: TextField(controller: controller, keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(helperText: '$min–$max', errorText: error)),
    actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
      TextButton(onPressed: () {
        final n = int.tryParse(controller.text);
        if (n == null || n < min || n > max) { set(() => error = '请输入 $min–$max'); return; }
        Navigator.pop(c, n);
      }, child: const Text('确定'))])));
  // Let the dialog finish its reverse transition before disposing its controller.
  Future<void>.delayed(const Duration(milliseconds: 400), controller.dispose);
  return value;
}

class ReminderDetail extends StatefulWidget {
  final Reminder reminder;
  final Future<void> Function() onAck;
  final VoidCallback onEdit;
  const ReminderDetail({super.key, required this.reminder, required this.onAck, required this.onEdit});
  @override State<ReminderDetail> createState() => _ReminderDetailState();
}
class _ReminderDetailState extends State<ReminderDetail> {
  double slide = 0;
  bool busy = false;
  @override Widget build(BuildContext context) {
    final r = widget.reminder;
    return SafeArea(child: Padding(padding: EdgeInsets.fromLTRB(24, 0, 24, 28 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(r.time, style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w700, color: purple)),
        Text('${dateLabel(r.displayDate)} · ${r.repeatLabel}', style: const TextStyle(color: muted)),
        const SizedBox(height: 18), ConstrainedBox(constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.35),
          child: SingleChildScrollView(child: Text(r.text, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w600)))),
        const SizedBox(height: 20),
        if (r.unread) ...[
          Text('已提醒 ${r.attempts}/${r.totalCount} 次 · 向右滑动确认已读', style: const TextStyle(color: muted)),
          Slider(value: slide, onChanged: busy ? null : (v) => setState(() => slide = v), onChangeEnd: (v) async {
            if (v < 0.9) { setState(() => slide = 0); return; }
            setState(() => busy = true);
            try { await widget.onAck(); } catch (e) {
              if (mounted) { setState(() { busy = false; slide = 0; }); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(niceError(e)))); }
            }
          }),
        ] else const Text('到时会通过系统通知提醒你', style: TextStyle(color: muted)),
        const SizedBox(height: 10), OutlinedButton(onPressed: busy ? null : widget.onEdit, child: const Text('编辑提醒')),
      ])));
  }
}

class ReminderEditor extends StatefulWidget {
  final Reminder reminder;
  final MemoStore store;
  const ReminderEditor({super.key, required this.reminder, required this.store});
  @override State<ReminderEditor> createState() => _ReminderEditorState();
}
class _ReminderEditorState extends State<ReminderEditor> {
  late final TextEditingController text;
  bool saving = false;
  Reminder get r => widget.reminder;
  @override void initState() { super.initState(); text = TextEditingController(text: r.text); }
  @override void dispose() { text.dispose(); super.dispose(); }
  Future<void> save() async {
    if (saving) return;
    r.text = text.text.trim();
    String? error;
    if (r.text.isEmpty) error = '请输入提醒内容';
    else if (r.repeat == 'weekly' && r.days.isEmpty) error = '请选择重复星期';
    else if (r.repeat == 'none' && !r.date.isAfter(DateTime.now())) error = '请选择未来的日期和时间';
    if (error != null) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error))); return; }
    setState(() => saving = true);
    try {
      await native.invokeMethod('requestNotifications');
      await widget.store.save(r);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) { setState(() => saving = false); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(niceError(e)))); }
    }
  }
  Future<void> pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context,
      initialDate: r.date.isBefore(now) ? now : r.date,
      firstDate: DateTime(now.year, now.month, now.day), lastDate: DateTime(now.year + 10, 12, 31));
    if (d != null && mounted) setState(() => r.date = DateTime(d.year, d.month, d.day, r.date.hour, r.date.minute));
  }
  Future<void> pickTime() async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(r.date),
      builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: child!));
    if (t != null && mounted) setState(() => r.date = DateTime(r.date.year, r.date.month, r.date.day, t.hour, t.minute));
  }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(r.id == 0 ? '新建提醒' : '编辑提醒'), actions: [TextButton(onPressed: saving ? null : save, child: const Text('保存'))]),
    body: ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 24), children: [
      Surface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('提醒内容', style: TextStyle(fontWeight: FontWeight.w600)), const SizedBox(height: 12),
        TextField(controller: text, minLines: 2, maxLines: 5, maxLength: 2000,
          decoration: const InputDecoration(hintText: '写下一件重要的事…')),
      ])), const SizedBox(height: 14),
      Surface(padding: const EdgeInsets.symmetric(vertical: 5), child: Column(children: [
        ListTile(leading: const Icon(Icons.calendar_today_outlined, color: purple), title: const Text('日期'),
          trailing: Text('${r.date.year}年${r.date.month}月${r.date.day}日'), onTap: pickDate),
        ListTile(leading: const Icon(Icons.schedule_rounded, color: purple), title: const Text('时间'), trailing: Text(r.time), onTap: pickTime),
      ])), const SizedBox(height: 14),
      Surface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('重复', style: TextStyle(fontWeight: FontWeight.w600)), const SizedBox(height: 14),
        SizedBox(width: double.infinity, child: SegmentedButton<String>(showSelectedIcon: false,
          segments: const [ButtonSegment(value: 'none', label: Text('仅一次')), ButtonSegment(value: 'daily', label: Text('每天')), ButtonSegment(value: 'weekly', label: Text('每周'))],
          selected: {r.repeat}, onSelectionChanged: (v) => setState(() { r.repeat = v.first; if (r.repeat == 'weekly' && r.days.isEmpty) r.days = [r.date.weekday]; }))),
        if (r.repeat == 'weekly') ...[const SizedBox(height: 16), Wrap(spacing: 8, runSpacing: 8, children: List.generate(7, (i) => FilterChip(
          label: Text(weekdays[i]), selected: r.days.contains(i + 1), onSelected: (v) => setState(() { if (v) { r.days.add(i + 1); } else { r.days.remove(i + 1); } })))],
      ])), const SizedBox(height: 14),
      Surface(padding: const EdgeInsets.symmetric(vertical: 5), child: Column(children: [
        const ListTile(title: Text('提醒方式', style: TextStyle(fontWeight: FontWeight.w700))),
        const ListTile(leading: Icon(Icons.notifications_none_rounded, color: purple), title: Text('小型系统弹窗'), subtitle: Text('锁屏隐藏正文，不全屏显示')),
        SwitchListTile(title: const Text('尝试亮屏'), subtitle: const Text('保持锁屏，遵循手机系统限制'), value: r.wakeScreen, onChanged: (v) => setState(() => r.wakeScreen = v)),
        ListTile(leading: const Icon(Icons.vibration, color: purple), title: const Text('振动'), subtitle: Text(vibrationLabel(r.vibration)),
          trailing: const Icon(Icons.chevron_right), onTap: () async {
            final v = await chooseVibration(context, r.vibration); if (v != null && mounted) setState(() => r.vibration = v);
          }),
        SwitchListTile(title: const Text('铃声'), value: r.sound, onChanged: (v) => setState(() => r.sound = v)),
        if (r.sound) ListTile(leading: const Icon(Icons.music_note_outlined, color: purple), title: const Text('从系统选择铃声'),
          subtitle: Text(r.ringtone.isEmpty ? '系统默认' : '已选择系统铃声'), trailing: const Icon(Icons.chevron_right), onTap: () async {
            try { final v = await native.invokeMethod<String>('pickRingtone', r.ringtone); if (v != null && mounted) setState(() => r.ringtone = v); }
            catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(niceError(e)))); }
          }),
      ])), const SizedBox(height: 14),
      Surface(padding: const EdgeInsets.symmetric(vertical: 5), child: Column(children: [
        const ListTile(title: Text('未读再次提醒', style: TextStyle(fontWeight: FontWeight.w700)), subtitle: Text('手动划掉通知或滑动确认后停止')),
        ListTile(leading: const Icon(Icons.timer_outlined, color: purple), title: const Text('时间间隔'), trailing: Text('${r.intervalMinutes} 分钟'), onTap: () async {
          final n = await numberDialog(context, '再次提醒间隔（分钟）', r.intervalMinutes, 1, 1440);
          if (n != null && mounted) setState(() => r.intervalMinutes = n);
        }),
        ListTile(leading: const Icon(Icons.repeat_rounded, color: purple), title: const Text('总次数（含首次）'), trailing: Text('${r.totalCount} 次'), onTap: () async {
          final n = await numberDialog(context, '提醒总次数（包含第一次）', r.totalCount, 1, 20);
          if (n != null && mounted) setState(() => r.totalCount = n);
        }),
      ])), const SizedBox(height: 24),
      FilledButton(onPressed: saving ? null : save, child: Text(saving ? '正在保存…' : '保存提醒')),
      const SizedBox(height: 14), const Text('到达次数上限后仍保留未读状态。编辑会重新安排这条提醒。', textAlign: TextAlign.center, style: TextStyle(color: muted, fontSize: 12)),
    ]),
  );
}

class VoicePage extends StatefulWidget {
  final MemoStore store;
  final Future<void> Function() onSaved;
  const VoicePage({super.key, required this.store, required this.onSaved});
  @override State<VoicePage> createState() => _VoicePageState();
}
class _VoicePageState extends State<VoicePage> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController animation;
  final text = TextEditingController();
  bool recording = false, busy = false;
  Timer? timer;
  int seconds = 0;
  String? warning;
  @override void initState() {
    super.initState(); WidgetsBinding.instance.addObserver(this);
    animation = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat();
  }
  @override void dispose() {
    timer?.cancel(); animation.dispose(); text.dispose(); WidgetsBinding.instance.removeObserver(this);
    native.invokeMethod('cancelRecording'); super.dispose();
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.paused || state == AppLifecycleState.detached) && recording) {
      timer?.cancel(); native.invokeMethod('cancelRecording');
      if (mounted) setState(() { recording = false; warning = '录音已暂停，请重新录音'; });
    }
  }
  Future<void> microphone() async {
    if (busy) return;
    if (recording) { await finish(); return; }
    setState(() => busy = true);
    try {
      await native.invokeMethod('startRecording');
      if (!mounted) return;
      setState(() { recording = true; busy = false; seconds = 0; warning = null; });
      timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || !recording) return;
        setState(() => seconds++);
        if (seconds >= 45) finish();
      });
    } catch (e) { if (mounted) setState(() { busy = false; warning = niceError(e); }); }
  }
  Future<void> finish() async {
    if (!recording) return;
    timer?.cancel(); setState(() { recording = false; busy = true; });
    try {
      final path = await native.invokeMethod<String>('stopRecording');
      if (path == null) throw StateError('没有录音，请重试');
      final result = await transcribe(path);
      if (mounted) setState(() { text.text = result; warning = result.trim().isEmpty ? '没有听清，请靠近麦克风再试一次' : null; });
    } catch (e) { if (mounted) setState(() => warning = niceError(e)); }
    finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> confirm() async {
    final parsed = parseVoice(text.text, defaults: widget.store.draft());
    if (parsed.warning != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(parsed.warning!)));
    }
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => ReminderEditor(reminder: parsed.reminder, store: widget.store)));
    if (saved == true) { await widget.onSaved(); if (mounted) setState(() { text.clear(); warning = '提醒已保存'; }); }
  }
  @override Widget build(BuildContext context) => ListView(padding: const EdgeInsets.fromLTRB(24, 26, 24, 30), children: [
    Row(children: [Expanded(child: Text('语音新建', style: Theme.of(context).textTheme.headlineLarge)), const Tag('离线识别')]),
    const SizedBox(height: 8), const Text('说出时间和事情，剩下的交给提醒', style: TextStyle(color: muted)),
    const SizedBox(height: 30), SizedBox(height: 200, child: Center(child: AnimatedBuilder(animation: animation, builder: (_, child) => Stack(alignment: Alignment.center, children: [
      Container(width: 168 + (recording ? animation.value * 18 : 0), height: 168 + (recording ? animation.value * 18 : 0),
        decoration: const BoxDecoration(color: Color(0xFFF0EBFF), shape: BoxShape.circle)),
      Container(width: 142, height: 142, decoration: const BoxDecoration(color: Color(0xFFE5DBFF), shape: BoxShape.circle)),
      Semantics(button: true, label: recording ? '停止录音并识别' : '开始录音', child: InkWell(onTap: busy ? null : microphone, borderRadius: BorderRadius.circular(70),
        child: Container(width: 116, height: 116, decoration: const BoxDecoration(shape: BoxShape.circle,
          gradient: LinearGradient(colors: [Color(0xFF9A79FF), Color(0xFF6740F2)], begin: Alignment.topLeft, end: Alignment.bottomRight)),
          child: busy ? const Padding(padding: EdgeInsets.all(37), child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
            : Icon(recording ? Icons.stop_rounded : Icons.mic_rounded, color: Colors.white, size: 48)))),
    ])))),
    Text(busy ? '正在本地识别…' : recording ? '正在聆听… ${seconds}s' : '点击开始说话', textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
    const SizedBox(height: 18), AnimatedBuilder(animation: animation, builder: (_, child) => SizedBox(height: 38,
      child: CustomPaint(painter: WavePainter(recording ? animation.value : 0, recording)))),
    const SizedBox(height: 24), Surface(child: TextField(controller: text, minLines: 3, maxLines: 6,
      onChanged: (_) => setState(() {}), decoration: const InputDecoration(hintText: '例如：每周三上午九点，提醒我参加项目例会', border: InputBorder.none, filled: false))),
    const SizedBox(height: 16), if (warning != null) Padding(padding: const EdgeInsets.only(bottom: 16), child: Text(warning!, style: const TextStyle(color: muted))),
    FilledButton(onPressed: text.text.trim().isEmpty || busy || recording ? null : confirm, child: const Text('确认并设置提醒')),
    const SizedBox(height: 12), OutlinedButton(onPressed: busy ? null : microphone, child: Text(recording ? '结束录音' : '重新录音')),
    const SizedBox(height: 20), const Text('识别后请确认日期、时间和内容。支持明天、几月几号、每天、工作日及每周几。录音最长45秒，识别后自动删除。',
      textAlign: TextAlign.center, style: TextStyle(color: muted, fontSize: 12, height: 1.6)),
  ]);
}
class WavePainter extends CustomPainter {
  final double phase;
  final bool active;
  WavePainter(this.phase, this.active);
  @override void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = purple.withValues(alpha: active ? 0.8 : 0.35)..strokeWidth = 3..strokeCap = StrokeCap.round;
    for (var i = 0; i < 33; i++) {
      final x = size.width / 2 + (i - 16) * 7;
      final amplitude = 3 + (active ? 13 : 6) * (math.sin(i * 1.7 + phase * math.pi * 2).abs());
      canvas.drawLine(Offset(x, size.height / 2 - amplitude), Offset(x, size.height / 2 + amplitude), paint);
    }
  }
  @override bool shouldRepaint(WavePainter oldDelegate) => oldDelegate.phase != phase || oldDelegate.active != active;
}
