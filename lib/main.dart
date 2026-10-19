import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'asr.dart';
import 'reminder.dart';
import 'voice_parser.dart';
import 'speech.dart';
import 'speech_options.dart';
import 'task_library.dart';
import 'voice_flow.dart';
import 'app_error.dart';
import 'voice_page.dart';
import 'voice_groups_page.dart';
import 'app_style.dart';
import 'settings_page.dart';
import 'voice_catalog.dart';
import 'vibration_picker.dart';
export 'vibration_picker.dart' show chooseVibration, vibrationLabel;
export 'app_style.dart' show purple, ink, muted, canvas;

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
    title: '超级提醒', debugShowCheckedModeBanner: false,
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
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
        foregroundColor: purple, side: BorderSide(color: purple.withValues(alpha: .60)),
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)))),
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
  late final voice = VoiceFlow(capture: OfflineVoiceCapture(asr), store: store,
    openVoicePage: () { if (mounted) setState(() => tab = 2); }, onSaved: reload);
  DialogRoute<void>? _voiceDialog;
  bool _dialogScheduled = false, _wasPaused = false, _entryPending = true;
  bool _initialized = false, _foreground = true, _checkingEntry = false, _entryAgain = false, _suppressVoiceEntry = false;
  bool _taskLibraryOpen = false, _settingsSheetOpen = false;
  final _settingsMessenger = GlobalKey<ScaffoldMessengerState>();
  GlobalKey? _settingsTargetKey;
  String? _settingsTargetTitle;
  int _entryEpoch = 0, _lifecycleEpoch = 0;
  DateTime selectedDate = DateTime.now();
  DateTime calendarMonth = DateTime(DateTime.now().year, DateTime.now().month);

  @override void initState() {
    super.initState(); WidgetsBinding.instance.addObserver(this);
    asr.setForeground(true);
    voice.addListener(_voiceChanged);
    native.setMethodCallHandler((call) async {
      if (call.method == 'openReminder') {
        _suppressVoiceEntry = true; _entryPending = false; _entryEpoch++;
        await voice.cancel(); await reload(); if (mounted) openById(call.arguments as int);
      }
      if (call.method == 'voiceEntry') {
        if (voice.active || voice.pending != null) return;
        _suppressVoiceEntry = false; _entryPending = true; _entryEpoch++;
        await _maybeStartHandsFree();
      }
      if (call.method == 'stateChanged') { await reload(); }
      if (call.method == 'prepareSpeech') { await speech.preparePending(retry: true); }
    });
    initialize();
  }
  Future<void> initialize() async {
    try { await native.invokeMethod('restore'); } catch (_) {}
    await reload();
    int? id;
    try { id = await native.invokeMethod<int>('initialReminderId'); } catch (_) {}
    if (!mounted) return;
    _initialized = true;
    if (id != null && id > 0) { _suppressVoiceEntry = true; _entryPending = false; openById(id); }
    else { await _maybeStartHandsFree(); }
    unawaited(speech.preparePending());
  }
  Future<void> _maybeStartHandsFree() async {
    if (_checkingEntry) { _entryAgain = true; return; }
    if (!_canStartHandsFree) return;
    _checkingEntry = true;
    final ticket = _entryEpoch;
    try {
      if (await native.invokeMethod<bool>('voiceEntryAllowed') == true &&
          ticket == _entryEpoch && _canStartHandsFree) {
        _entryPending = false;
        setState(() => tab = 0);
        await voice.startCommands();
      }
    } catch (e) { toast(niceError(e)); }
    finally {
      _checkingEntry = false;
      if (_entryAgain) {
        _entryAgain = false;
        if (_canStartHandsFree) unawaited(_maybeStartHandsFree());
      }
    }
  }
  bool get _canStartHandsFree => mounted && _initialized && _foreground && _entryPending &&
    !_suppressVoiceEntry && !_taskLibraryOpen && !_settingsSheetOpen && !voice.active && voice.pending == null &&
    store.defaults['handsFree'] == true && !Navigator.of(context).canPop();
  void _warmManualTab() {
    if (!mounted || !_foreground || tab != 2 || voice.active) return;
    unawaited(asr.prewarm().catchError((Object _) {}));
  }
  void _selectTab(int i) {
    if (i == tab) return;
    _entryPending = false; _entryEpoch++; speech.stopPreview();
    final stopped = voice.active || voice.pending != null ? voice.pause(keepDraft: false) : Future<void>.value();
    setState(() => tab = i);
    unawaited(stopped.then((_) async {
      if (!mounted || !_foreground || tab != i || voice.active) return;
      if (i == 2) _warmManualTab();
    }).catchError((Object e) { toast(niceError(e)); }));
  }
  Future<void> _pauseForBackground() async {
    final ticket = ++_lifecycleEpoch;
    asr.setForeground(false);
    try { await voice.pause(); } catch (_) {}
    finally { if (!_foreground && ticket == _lifecycleEpoch) asr.release(); }
  }
  @override void dispose() {
    voice.removeListener(_voiceChanged); voice.dispose();
    asr.setForeground(false); asr.release();
    WidgetsBinding.instance.removeObserver(this); native.setMethodCallHandler(null); super.dispose();
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _foreground = false; _wasPaused = true; _suppressVoiceEntry = false;
      _entryPending = false; _entryEpoch++;
      unawaited(_pauseForBackground());
    }
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      _lifecycleEpoch++; asr.setForeground(true);
      if (_wasPaused) { _wasPaused = false; _entryPending = true; _entryEpoch++; }
      unawaited(reload().then((_) async { await _maybeStartHandsFree(); _warmManualTab(); }));
    }
  }
  @override void didHaveMemoryPressure() { asr.release(); }
  void _voiceChanged() {
    if (!mounted) return;
    setState(() {});
    if (_dialogScheduled) return;
    _dialogScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _dialogScheduled = false;
      if (!mounted) return;
      if (voice.pending == null) {
        final route = _voiceDialog; _voiceDialog = null;
        if (route != null && route.isActive) Navigator.of(context).removeRoute(route);
      } else if (_voiceDialog == null) {
        final route = DialogRoute<void>(context: context, barrierDismissible: false,
          barrierColor: ink.withValues(alpha: .20),
          builder: (_) => VoiceConfirmation(flow: voice, onEdit: _editVoiceDraft));
        _voiceDialog = route;
        Navigator.of(context).push(route).whenComplete(() { if (identical(_voiceDialog, route)) _voiceDialog = null; });
      }
    });
  }
  Future<void> _editVoiceDraft() async {
    final parsed = voice.pending;
    if (parsed == null || voice.phase == VoicePhase.saving) return;
    await voice.cancel();
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) =>
      ReminderEditor(reminder: parsed.reminder, store: store, voice: parsed)));
    if (saved == true) await reload();
  }
  Future<void> reload() async {
    try {
      await store.load();
      if (mounted) {
        if (_settingsSheetOpen) { loading = false; error = null; }
        else { setState(() { loading = false; error = null; }); }
      }
    } catch (e) {
      if (mounted) {
        if (_settingsSheetOpen) { loading = false; error = niceError(e); toast(error!); }
        else { setState(() { loading = false; error = niceError(e); }); }
      }
    }
  }
  void toast(String s) {
    if (!mounted) return;
    final local = _settingsMessenger.currentState;
    final messenger = local != null && ModalRoute.of(local.context)?.isCurrent == true
      ? local : ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(s), behavior: SnackBarBehavior.floating));
  }
  Future<void> edit([Reminder? existing]) async {
    await voice.pause(keepDraft: false);
    if (!mounted) return;
    final draft = existing == null ? store.draft() : Reminder.fromJson({...existing.toJson()});
    draft.enabled = true;
    draft.completed = false;
    draft.archived = false;
    if (existing != null && (existing.archived || existing.completed) && draft.repeat == 'none' && !draft.date.isAfter(DateTime.now())) {
      draft.date = DateTime.now().add(const Duration(hours: 1));
    }
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => ReminderEditor(reminder: draft, store: store)));
    if (saved == true) {
      if (mounted && existing != null && (existing.archived || existing.completed)) {
        Navigator.of(context).popUntil((route) => route.isFirst);
        setState(() => tab = 0);
      }
      await reload(); toast('提醒已保存');
    }
  }
  void openById(int id) {
    final matches = store.reminders.where((r) => r.id == id);
    if (matches.isNotEmpty) viewReminder(matches.first);
  }
  Future<void> viewReminder(Reminder r) async {
    await voice.pause(keepDraft: false);
    if (!mounted) return;
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
  Future<void> finishTask(Reminder r) async {
    final action = await showDialog<String>(context: context, builder: (c) => AlertDialog(
      title: const Text('结束后如何处理？'),
      content: Text(r.repeat == 'none'
        ? '保留到历史会停止提醒并保留内容，以后可编辑复用；删除会移除这条任务。'
        : '保留或删除都会停止本次及以后的循环提醒；保留到历史后可编辑重新启用。'),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
        TextButton(onPressed: () => Navigator.pop(c, 'delete'), child: const Text('删除任务')),
        FilledButton(onPressed: () => Navigator.pop(c, 'archive'), child: const Text('保留到历史'))]));
    if (action == null) return;
    try {
      if (action == 'archive') { await store.archive(r.id); toast('已保留到历史任务，可编辑后复用'); }
      else { await store.delete(r.id); toast('任务已删除'); }
      await reload();
    } catch (e) { toast(niceError(e)); }
  }
  Future<void> taskLibrary() async {
    if (!mounted || _taskLibraryOpen) return;
    // Acquire before any await; the page must not wait for a cold ASR load.
    _taskLibraryOpen = true; _entryPending = false; _entryEpoch++;
    unawaited(voice.pause(keepDraft: false).catchError((Object e) { toast(niceError(e)); }));
    try {
      await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => TaskLibraryPage(
        store: store, card: reminderCard)));
    } finally { _taskLibraryOpen = false; }
    if (mounted) await reload();
  }
  @override Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: Column(children: [
      if (voice.active && voice.pending == null && tab != 2) Material(color: const Color(0xFFECE5FF), child: ListTile(
        dense: true, leading: const Icon(Icons.mic_none), title: Text(voice.message),
        subtitle: voice.phase == VoicePhase.commands ? Text('剩余 ${voice.secondsLeft} 秒') : null,
        trailing: IconButton(tooltip: '停止预听', onPressed: voice.cancel, icon: const Icon(Icons.close)))),
      Expanded(child: loading ? const Center(child: CircularProgressIndicator())
      : error != null ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(error!), TextButton(onPressed: reload, child: const Text('重新加载'))]))
      : IndexedStack(index: tab, children: [homePage(), calendarPage(),
        TickerMode(enabled: tab == 2, child: VoicePage(flow: voice)), settingsPage()])),
    ])),
    floatingActionButton: !loading && error == null && (tab == 0 || tab == 1)
      ? FloatingActionButton(onPressed: () => edit(), backgroundColor: purple,
          foregroundColor: Colors.white, tooltip: '新建提醒', child: const Icon(Icons.add_rounded, size: 32)) : null,
    bottomNavigationBar: SafeArea(top: false, child: Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFF0EDF6))),
      child: ClipRRect(borderRadius: BorderRadius.circular(26), child: NavigationBar(backgroundColor: Colors.white,
      height: 72,
      selectedIndex: tab, indicatorColor: const Color(0xFFECE5FF),
      onDestinationSelected: _selectTab, destinations: const [
        NavigationDestination(icon: Icon(Icons.description_outlined), selectedIcon: Icon(Icons.description_rounded), label: '备忘录'),
        NavigationDestination(icon: Icon(Icons.calendar_month_outlined), label: '日历'),
        NavigationDestination(icon: Icon(Icons.mic_none_rounded), selectedIcon: Icon(Icons.mic_rounded), label: '语音'),
        NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings_rounded), label: '设置'),
      ])))),
  );
  Widget header(String title, String subtitle, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 22, 24, 22), child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 7), Text(subtitle, style: const TextStyle(color: muted)),
      ])), if (trailing != null) trailing,
    ]));
  Widget homePage() {
    final list = store.reminders.where((r) => !r.archived).toList()..sort((a, b) {
      if (a.unread != b.unread) return a.unread ? -1 : 1;
      return a.displayDate.compareTo(b.displayDate);
    });
    final active = list.where((r) => !r.completed && (r.enabled || r.unread)).toList();
    final paused = list.where((r) => !r.enabled && !r.completed && !r.unread).toList();
    final now = DateTime.now();
    final historyCount = store.reminders.where((r) => r.archived || r.completed).length;
    return RefreshIndicator(onRefresh: reload, child: CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(), slivers: [SliverList.list(children: [
      header('备忘录', '把重要的事，交给提醒', trailing: IconButton(
        icon: const Icon(Icons.inventory_2_outlined), tooltip: '历史任务', onPressed: taskLibrary)),
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
      ]),
      SliverList.builder(itemCount: active.length, itemBuilder: (_, i) => reminderCard(active[i])),
      SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 0), child: Surface(child: Column(children: [
        ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.history, color: purple),
          title: Text('历史任务 · $historyCount 条'), subtitle: const Text('完成或主动保留的任务统一收纳，支持搜索和复用'),
          trailing: const Icon(Icons.chevron_right), onTap: taskLibrary),
      ])))),
      if (paused.isNotEmpty) SliverToBoxAdapter(child: section('未启用', '${paused.length} 条')),
      SliverList.builder(itemCount: paused.length, itemBuilder: (_, i) => reminderCard(paused[i])),
      const SliverToBoxAdapter(child: SizedBox(height: 90)),
    ]));
  }
  Key? settingKey(String title) => title == _settingsTargetTitle ? _settingsTargetKey : null;
  Widget section(String title, String subtitle) => Padding(key: settingKey(title), padding: const EdgeInsets.fromLTRB(24, 26, 24, 12),
    child: Row(children: [Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      const Spacer(), Text(subtitle, style: const TextStyle(color: muted, fontSize: 12))]));
  Widget permissionBanner() => Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
    child: InkWell(onTap: () => _selectTab(3), borderRadius: BorderRadius.circular(18),
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
            if (r.speechState != 'off') Tag(r.speechState == 'ready' ? '语音已就绪' : r.speechState == 'preparing' ? '语音准备中' : '语音待准备'),
            Tag(r.completed || r.archived ? '已结束' : !r.enabled ? '未启用' : r.unread ? '未读 ${r.attempts}/${r.totalCount}' : r.repeatLabel),
            Text(dateLabel(r.displayDate), style: const TextStyle(fontSize: 11, color: muted)),
          ]),
        ])), PopupMenuButton<String>(tooltip: '更多操作', onSelected: (v) async {
          if (v == 'edit') { await edit(r); }
          else if (v == 'archive') { await finishTask(r); }
          else { await remove(r); }
        }, itemBuilder: (_) => [PopupMenuItem(value: 'edit', child: Text(r.archived || r.completed ? '编辑并复用' : '编辑')),
          if (!r.archived && !r.completed) const PopupMenuItem(value: 'archive', child: Text('结束并保留')),
          const PopupMenuItem(value: 'delete', child: Text('删除'))]),
      ]))));
    if (r.archived || r.completed) return card;
    return Dismissible(key: ValueKey('task-${r.id}-${r.activeOccurrence}-${r.attempts}'), direction: DismissDirection.endToStart,
      background: Container(color: const Color(0xFFECE5FF), alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 30), child: const Text('完成并整理', style: TextStyle(color: purple))),
      secondaryBackground: Container(color: const Color(0xFFECE5FF), alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 30), child: const Text('保留 / 删除', style: TextStyle(color: purple))),
      confirmDismiss: (_) async {
        await finishTask(r);
        return false;
      }, child: card);
  }
  Widget calendarPage() {
    final first = DateTime(calendarMonth.year, calendarMonth.month);
    final count = DateTime(first.year, first.month + 1, 0).day;
    final offset = first.weekday - 1;
    final list = store.reminders.where((r) => calendarOccursOn(r, selectedDate)).toList()..sort((a, b) => a.time.compareTo(b.time));
    final active = list.where((r) => !r.completed && !r.archived).toList();
    final history = list.where((r) => r.completed || r.archived).toList();
    return CustomScrollView(slivers: [SliverList.list(children: [
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
            final has = store.reminders.any((r) => calendarOccursOn(r, date));
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
    ]),
      if (active.isNotEmpty) SliverToBoxAdapter(child: section('待提醒与暂停', '')),
      SliverList.builder(itemCount: active.length, itemBuilder: (_, i) => reminderCard(active[i])),
      if (history.isNotEmpty) SliverToBoxAdapter(child: section('当天历史任务', '按保留的计划日期整理')),
      SliverList.builder(itemCount: history.length, itemBuilder: (_, i) => reminderCard(history[i])),
      const SliverToBoxAdapter(child: SizedBox(height: 90)),
    ]);
  }
  Widget settingsPage() => SettingsPage(onOpen: _openSettingsSection, currentValue: _settingValue,
    version: (store.status['version'] as String? ?? '').isEmpty ? '本机离线' : 'v${store.status['version']}');
  void _settingsAction(BuildContext sheetContext, String action) {
    if (ModalRoute.of(sheetContext)?.isCurrent == true) Navigator.pop(sheetContext, action);
  }
  Future<void> _openSettingsSection(SettingsSection section, {SettingsEntry? target}) async {
    if (!mounted || _settingsSheetOpen) return;
    _settingsSheetOpen = true; _entryPending = false; _entryEpoch++;
    _settingsTargetTitle = target?.anchor;
    _settingsTargetKey = target == null ? null : GlobalKey();
    if (voice.active || voice.pending != null) {
      unawaited(voice.pause(keepDraft: false).catchError((Object e) { toast(niceError(e)); }));
    }
    String? action;
    try {
      action = await showModalBottomSheet<String>(context: context, isScrollControlled: true,
        useSafeArea: true, backgroundColor: Colors.transparent, barrierColor: ink.withValues(alpha: .20),
        builder: (_) => SettingsSheet(section: section, changes: store,
          messengerKey: _settingsMessenger, targetKey: _settingsTargetKey, target: target,
          items: (sheetContext) => _settingsItems(section.category, sheetContext)));
    } finally {
      _settingsSheetOpen = false; _entryPending = false; _entryEpoch++;
      _settingsTargetTitle = null; _settingsTargetKey = null;
      if (mounted) setState(() {});
    }
    if (!mounted) return;
    if (action == 'history') await taskLibrary();
    if (action == 'voice' && _foreground) { setState(() => tab = 0); await voice.startCommands(); }
  }
  String _settingValue(SettingsEntry entry) {
    final d = store.defaults, s = store.status;
    String toggle(bool value) => value ? '已开启' : '已关闭';
    return switch (entry.id) {
      'presentation' => d['presentation'] == 'drawer' ? '仅通知栏' : '横幅和通知栏',
      'lockscreen' => d['lockscreen'] == 'hidden' ? '不在锁屏显示' : '隐藏正文',
      'vibration' => vibrationLabel(d['vibration'] as String? ?? 'three'),
      'sound' => toggle(d['sound'] as bool? ?? true),
      'ringtone' => (d['ringtone'] as String? ?? '').isEmpty ? '系统默认' : '已选择铃声',
      'interval' => '${d['intervalMinutes'] ?? 5} 分钟',
      'count' => '${d['totalCount'] ?? 3} 次（含首次）',
      'wake' => toggle(d['wakeScreen'] as bool? ?? true),
      'popup' => s['popupEnabled'] != true ? '已关闭' : s['popupPermission'] == true ? '已开启' : '等待悬浮窗授权',
      'handsFree' => toggle(d['handsFree'] as bool? ?? false),
      'autoStop' => toggle(d['voiceAutoStop'] as bool? ?? true),
      'silence' => '${d['voiceSilenceSeconds'] ?? 5} 秒',
      'offline' => '已内置 · 无需联网',
      'groups' => '${store.voiceGroups.length} 个角色组',
      'speechMode' => toggle(d['speechMode'] == 'on'),
      'speechVoice' => d['speechRandom'] == true ? '随机音色' : speechVoiceLabel(d['speechVoice'] as String? ?? '228'),
      'speechRandom' => toggle(d['speechRandom'] as bool? ?? false),
      'speechGroup' => (d['speechRandomGroup'] as String? ?? '').isEmpty ? '全部角色' : '已选择角色组',
      'speechSource' => voiceLanguages[d['speechRandomLanguage'] ?? 'all'] ?? '不限配音来源',
      'speechGender' => voiceGenders[d['speechRandomGender'] ?? 'all'] ?? '不限角色性别',
      'speechPreview' => d['speechRandom'] == true ? '试听随机音色' : '试听固定音色',
      'speechRate' => '${d['speechRate'] ?? 1.0} 倍速',
      'speechLock' => d['speechHideLocked'] == false ? '允许播报正文' : '隐藏播报正文',
      'speechRepeat' => toggle(d['speechRepeat'] as bool? ?? true),
      'speechStatus' || 'prepareSpeech' => speech.status.value,
      'reliable' => toggle(s['reliableMode'] as bool? ?? true),
      'service' => s['guardianRunning'] == true ? '正在维护提醒' : '当前未运行',
      'notifications' => s['notifications'] == true ? '已授权' : '未授权',
      'exact' || 'schedule' => s['exact'] == true ? '精确定时已可用' : '需授权',
      'battery' => s['battery'] == true ? '不受电池优化' : '请检查系统设置',
      'history' => '${store.reminders.where((r) => r.archived || r.completed).length} 条记录',
      'cleanup' => toggle(s['cleanupPrompts'] as bool? ?? true),
      'testDelete' => toggle(s['testAutoDelete'] as bool? ?? true),
      'test' => '按当前默认样式测试一次',
      'lastReceived' => eventTime(s['lastReceived']),
      'lastRestored' => eventTime(s['lastRestored']),
      'styles' => '${(s['notificationStyles'] as List? ?? []).length} 种样式',
      'signing' => '固定签名 · 支持覆盖更新',
      _ => '点击前往查看',
    };
  }
  List<Widget> _settingsItems(SettingsCategory category, BuildContext sheetContext) => switch (category) {
    SettingsCategory.reminders => [
    section('默认提醒', '新提醒使用这些设置'),
    settingsGroup([
      NotificationDisplayOptions(defaultSettings: true,
        presentation: store.defaults['presentation'] as String? ?? 'banner',
        lockscreen: store.defaults['lockscreen'] as String? ?? 'private',
        onPresentationChanged: (v) async { store.defaults['presentation'] = v; await persistDefaults(); },
        onLockscreenChanged: (v) async { store.defaults['lockscreen'] = v; await persistDefaults(); }),
      settingRow(Icons.tune_rounded, '默认样式的系统设置', '管理此样式的横幅与锁屏权限',
        () => store.openNotificationSettings(store.draft())),
      settingRow(Icons.vibration, '振动模式', vibrationLabel(store.defaults['vibration'] as String? ?? 'three'), () async {
        final v = await chooseVibration(context, store.defaults['vibration'] as String? ?? 'three');
        if (v != null) { store.defaults['vibration'] = v; await persistDefaults(); }
      }),
      SwitchListTile(key: settingKey('铃声'), title: const Text('铃声'), subtitle: const Text('到时播放系统通知铃声'),
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
      SwitchListTile(key: settingKey('尝试亮屏'), title: const Text('尝试亮屏'), subtitle: const Text('不解锁屏幕，受手机系统设置影响'),
        value: store.defaults['wakeScreen'] as bool? ?? true, onChanged: (v) async { store.defaults['wakeScreen'] = v; await persistDefaults(); }),
    ]),
    section('亮屏弹窗', '在其他应用或桌面也显示提醒小卡片'),
    settingsGroup([
      SwitchListTile(key: settingKey('亮屏弹窗增强'), title: const Text('亮屏弹窗增强'),
        subtitle: Text(store.status['popupEnabled'] == true
          ? store.status['popupPermission'] == true ? '已授权：仅解锁亮屏显示，10秒自动收起，未读仍会重试' : '等待悬浮窗授权：请重新开启并在系统页面允许'
          : '开启后需允许“显示在其他应用上层”；锁屏不显示浮窗正文'),
        value: store.status['popupEnabled'] as bool? ?? false,
        onChanged: (enabled) async {
          try { await native.invokeMethod('popupMode', enabled); await reload(); }
          catch (e) { await reload(); toast(niceError(e)); return; }
          toast(enabled ? store.status['popupPermission'] == true ? '亮屏弹窗增强已开启' : '已保存，请在系统页面允许悬浮窗权限' : '亮屏弹窗增强已关闭');
        }),
      const ListTile(subtitle: Text('适用于“横幅和通知栏”提醒。点击已读或横向滑动确认；收起及自动消失均保持未读。系统横幅仍需在对应通知样式中允许，部分应用可限制悬浮窗。')),
      if ((store.status['popupError'] as String? ?? '').isNotEmpty)
        Padding(padding: const EdgeInsets.all(16), child: Text(store.status['popupError'] as String)),
    ]),
    ],
    SettingsCategory.voiceInput => [
    section('免手操作', ''), settingsGroup([
      SwitchListTile(key: settingKey('打开应用后预听'), title: const Text('打开应用后预听'),
        subtitle: const Text('从桌面或其他应用返回后预听15秒'),
        value: store.defaults['handsFree'] as bool? ?? false,
        onChanged: (v) async { store.defaults['handsFree'] = v; await persistDefaults(); }),
    ]),
    settingsHint('说“开始录音”后进入正式录入。切换Tab不会重新开麦，编辑和待确认内容不被打断。'),
    section('录音', ''), settingsGroup([
      SwitchListTile(key: settingKey('静音后自动结束'), title: const Text('静音后自动结束'),
        subtitle: const Text('说完后自动进入确认'),
        value: store.defaults['voiceAutoStop'] as bool? ?? true,
        onChanged: (v) async { store.defaults['voiceAutoStop'] = v; await persistDefaults(); }),
      settingRow(Icons.timer_outlined, '自动停录等待', "${store.defaults['voiceSilenceSeconds'] ?? 5} 秒", () async {
        final seconds = await showDialog<int>(context: context, builder: (c) => SimpleDialog(title: const Text('连续无声多久后停录'),
          children: [for (var i = 3; i <= 10; i++) SimpleDialogOption(onPressed: () => Navigator.pop(c, i), child: Text('$i 秒'))]));
        if (seconds != null) { store.defaults['voiceSilenceSeconds'] = seconds; await persistDefaults(); }
      }),
    ]),
    settingsHint('单次录音最长45秒，确认过程不播放语音。'),
    section('识别方式', ''), settingsGroup([
      ListTile(key: settingKey('本机离线'), leading: const Icon(Icons.shield_outlined, color: purple), title: const Text('本机离线'),
        subtitle: const Text('录音只在本机识别'), trailing: const Tag('已内置')),
    ]),
    settingsHint('无需联网。首次准备或从后台返回时，可能需要稍候。'),
    Padding(padding: const EdgeInsets.fromLTRB(20, 24, 20, 4), child: FilledButton.tonalIcon(key: settingKey('试用免手输入'),
      onPressed: () => _settingsAction(sheetContext, 'voice'),
      style: FilledButton.styleFrom(backgroundColor: lavender, foregroundColor: purple),
      icon: const Icon(Icons.mic_none_rounded), label: const Text('试用免手输入'))),
    ],
    SettingsCategory.speech => [
    section('离线语音播报', 'VITS-MNN · 804个音色条目'), settingsGroup([
      settingRow(Icons.groups_outlined, '我的角色组', '${store.voiceGroups.length} 个组 · 创建专属随机音色范围', () async {
        await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => VoiceGroupsPage(store: store)));
        await reload();
      }),
      defaultSpeechOptions(),
      ValueListenableBuilder<String>(valueListenable: speech.status, builder: (_, value, child) => ListTile(key: settingKey('语音准备状态'),
        leading: const Icon(Icons.graphic_eq, color: purple), title: const Text('语音准备状态'), subtitle: Text(value))),
      settingRow(Icons.refresh, '重新准备提醒语音', '补齐未完成的音频，不改变提醒时间', () async {
        await speech.preparePending(retry: true); await reload(); toast(speech.status.value);
      }),
      if (((store.status['speech'] as Map?)?['error'] as String? ?? '').isNotEmpty)
        ListTile(subtitle: Text((store.status['speech'] as Map)['error'] as String)),
    ]),
    ],
    SettingsCategory.background => [
    section('后台可靠性', '增强最近任务关闭后的提醒维护'),
    settingsGroup([
      SwitchListTile(key: settingKey('可靠提醒模式'), title: const Text('可靠提醒模式'),
        subtitle: const Text('有待触发任务时显示静默常驻通知，提高后台可靠性；不能绕过系统强行停止'),
        value: store.status['reliableMode'] as bool? ?? true,
        onChanged: (enabled) async {
          try { await native.invokeMethod('reliableMode', enabled); await reload(); toast(enabled ? '可靠提醒模式已开启' : '可靠提醒模式已关闭'); }
          catch (e) { await reload(); toast(niceError(e)); }
        }),
      ListTile(leading: const Icon(Icons.shield_outlined, color: purple), key: settingKey('提醒服务状态'), title: const Text('提醒服务状态'),
        subtitle: Text(store.status['reliableMode'] == false ? '可靠模式已关闭，仍保留系统闹钟'
          : store.status['guardianRunning'] == true ? '正在维护待触发提醒'
          : ((store.status['pending'] as Map?)?['count'] as int? ?? 0) == 0 ? '没有待触发任务，无需常驻运行'
          : '尚未检测到运行，请检查下方系统提示')),
      if ((store.status['guardianError'] as String? ?? '').isNotEmpty) Padding(padding: const EdgeInsets.all(16),
        child: Text(store.status['guardianError'] as String, style: const TextStyle(color: muted, fontSize: 12))),
    ]),
    section('隐私与提醒权限', ''),
    settingsGroup([
      ListTile(leading: const Icon(Icons.notifications_none, color: purple), key: settingKey('通知权限'), title: const Text('通知权限'),
        subtitle: Text(store.status['notifications'] == true ? '已开启' : '未开启，请在提醒自检中授权')),
      ListTile(key: settingKey('锁屏内容保护'), leading: const Icon(Icons.lock_outline, color: purple), title: const Text('锁屏内容保护'),
        subtitle: const Text('使用系统锁屏隐私保护，解锁自动显示正文；不使用全屏通知')),
      settingRow(Icons.alarm_on_rounded, '精确定时权限', store.status['exact'] == true ? '已开启' : '需开启', () => native.invokeMethod('requestExact')),
      settingRow(Icons.battery_saver_outlined, '后台运行', store.status['battery'] == true ? '不受电池优化' : '检查电池优化', () => native.invokeMethod('batterySettings')),
      settingRow(Icons.phonelink_setup_rounded, '应用系统设置', '荣耀应用启动管理', () => native.invokeMethod('appSettings')),
    ]),
    ],
    SettingsCategory.data => [
    section('任务整理', '完成记录自动收起，保留以后使用'),
    settingsGroup([
      ListTile(key: settingKey('历史任务'), title: const Text('历史任务'), subtitle: const Text('完成与主动保留的记录合并显示；编辑保存后重新启用'),
        leading: const Icon(Icons.inventory_2_outlined, color: purple), trailing: const Icon(Icons.chevron_right), onTap: () => _settingsAction(sheetContext, 'history')),
      SwitchListTile(key: settingKey('划掉通知后询问整理方式'), title: const Text('划掉通知后询问整理方式'),
        subtitle: const Text('划掉通知先结束本轮，再询问保留或删除；不选择时保留记录与循环，自检自动清理时不再询问'),
        value: store.status['cleanupPrompts'] as bool? ?? true, onChanged: (v) async {
          try { await native.invokeMethod('cleanupPrompts', v); await reload(); toast('整理方式设置已保存'); } catch (e) { toast(niceError(e)); }
        }),
    ]),
    section('数据迁移', ''), settingsGroup([
      settingRow(Icons.file_upload_outlined, '导出备忘录', '保存到你选择的位置', () async {
        final ok = await native.invokeMethod<bool>('exportBackup');
        if (ok == true) { toast('备份已保存，包含提醒内容，请妥善保管'); }
      }),
      settingRow(Icons.file_download_outlined, '合并导入备忘录', '保留现有数据，过期的单次任务转入历史', () async {
        final proceed = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
          title: const Text('合并导入备忘录'),
          content: const Text('导入会新增记录，不覆盖现有提醒。过去的单次任务会归入历史任务；铃声使用新手机的系统默认。重复导入会新增重复记录。'),
          actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('选择文件'))]));
        if (proceed != true) { return; }
        await native.invokeMethod('requestNotifications');
        final count = await native.invokeMethod<int>('importBackup');
        if (count != null) { unawaited(speech.preparePending()); await reload(); toast('已合并导入 $count 条提醒'); }
      }),
    ]),
    ],
    SettingsCategory.help => [
    section('提醒自检', ''), settingsGroup([
      settingRow(Icons.view_agenda_outlined, '检查系统通知与锁屏设置', '查看应用通知总开关；各样式可在下方单独管理', () async {
        if (store.status['notifications'] != true) { await native.invokeMethod('requestNotifications'); }
        await native.invokeMethod('notificationSettings');
      }),
      SwitchListTile(key: settingKey('测试提醒完成后自动删除'), title: const Text('测试提醒完成后自动删除'),
        subtitle: const Text('仅作用于新建的15秒自检提醒；确认或划掉通知后删除，未确认时保留。普通备忘录不受影响。'),
        value: store.status['testAutoDelete'] as bool? ?? true, onChanged: (v) async {
          try { await native.invokeMethod('testAutoDelete', v); await reload(); toast('测试提醒清理设置已保存'); } catch (e) { toast(niceError(e)); }
        }),
      settingRow(Icons.notifications_active_outlined, '15秒后发送测试提醒', '使用当前默认样式；语音未就绪时使用备用提醒', () async {
        final allowed = await native.invokeMethod<bool>('requestNotifications');
        if (allowed == false) { toast('请先开启通知权限后再测试'); return; }
        await native.invokeMethod('testReminder');
        toast('测试提醒已设置，请返回桌面等待15秒');
        await reload();
      }),
      ListTile(key: settingKey('系统闹钟排程'), leading: const Icon(Icons.alarm_on, color: purple), title: const Text('系统闹钟排程'),
        subtitle: Text(store.status['exact'] == true ? '精确定时已可用，状态栏可能显示下一闹钟' : '尚未允许精确定时，提醒不会静默降级')),
      ListTile(key: settingKey('最近实际触发'), leading: const Icon(Icons.schedule, color: purple), title: const Text('最近实际触发'),
        subtitle: Text(eventTime(store.status['lastReceived']))),
      ListTile(key: settingKey('最近恢复排程'), leading: const Icon(Icons.restart_alt, color: purple), title: const Text('最近恢复排程'),
        subtitle: Text(eventTime(store.status['lastRestored']))),
      settingRow(Icons.bug_report_outlined, '导出提醒诊断', '包含排程、启动前快照与进程退出原因；不含备忘正文', () async {
        final ok = await native.invokeMethod<bool>('exportDiagnostics');
        if (ok == true) { toast('诊断已导出，可用于排查后台提醒问题'); }
      }),
      notificationStylesList(),
      ListTile(key: settingKey('固定发布签名'), leading: const Icon(Icons.security, color: purple), title: const Text('固定发布签名'),
        subtitle: const Text('同一固定签名的版本可覆盖更新，数据保存在本机')),
    ]),
    section('使用提示', ''), Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Surface(child: const Text(
      '• 手动划掉系统通知或点击已读后结束本轮重提醒；App 中结束并保留会停用后续提醒。点开通知、横幅自动收起不算已读。\n\n'
      '• 达到总次数后停止再次提醒，但仍保留未读状态。下一次每日／每周提醒重新计数。\n\n'
      '• 荣耀手机请检查应用启动管理，允许自启动与后台运行。系统休眠、勿扰模式、强行停止会影响提醒和亮屏。\n\n'
      '• 提醒使用系统闹钟排程；从最近任务划掉不需要重新打开 App。系统强行停止会阻止提醒，需要手动再打开。\n\n'
      '• 横幅和锁屏通知最终受系统通道设置控制。请用提醒自检测试，并检查允许横幅、锁屏通知和勿扰设置。',
      style: TextStyle(color: muted, fontSize: 13, height: 1.7)))),
    if ((store.status['lastError'] as String? ?? '').isNotEmpty) Padding(padding: const EdgeInsets.all(24),
      child: Text('最近的系统提示：${store.status['lastError']}', style: const TextStyle(color: muted, fontSize: 12))),
    ],
  };
  Widget defaultSpeechOptions() {
    final config = Reminder(
      speechMode: store.defaults['speechMode'] as String? ?? 'off',
      speechVoice: store.defaults['speechVoice'] as String? ?? '228',
      speechRate: (store.defaults['speechRate'] as num?)?.toDouble() ?? 1.0,
      speechHideLocked: store.defaults['speechHideLocked'] as bool? ?? true,
      speechRepeat: store.defaults['speechRepeat'] as bool? ?? true,
      speechRandom: store.defaults['speechRandom'] as bool? ?? false,
      speechRandomLanguage: store.defaults['speechRandomLanguage'] as String? ?? 'all',
      speechRandomGender: store.defaults['speechRandomGender'] as String? ?? 'all',
      speechRandomGroup: store.defaults['speechRandomGroup'] as String? ?? '');
    return SpeechOptions(groups: store.voiceGroups, defaultSettings: true, reminder: config, defaults: store.defaults, onChanged: () async {
      store.defaults.addAll({'speechMode': config.speechMode, 'speechVoice': config.speechVoice,
        'speechRate': config.speechRate, 'speechHideLocked': config.speechHideLocked, 'speechRepeat': config.speechRepeat,
        'speechRandom': config.speechRandom, 'speechRandomLanguage': config.speechRandomLanguage, 'speechRandomGender': config.speechRandomGender, 'speechRandomGroup': config.speechRandomGroup});
      await persistDefaults();
    });
  }
  Future<void> persistDefaults() async {
    try { await store.saveDefaults(); await reload(); toast('设置已保存'); }
    catch (e) { await reload(); toast(niceError(e)); }
  }
  Widget notificationStylesList() {
    final styles = (store.status['notificationStyles'] as List? ?? [])
      .map((v) => Map<String, dynamic>.from(v as Map)).toList()
      ..sort((a, b) => (b['isDefault'] == true ? 1 : 0).compareTo(a['isDefault'] == true ? 1 : 0));
    final hidden = store.status['hiddenChannelCount'] as int? ?? 0;
    return ExpansionTile(key: settingKey('通知样式') ?? const PageStorageKey('notification-styles'),
      leading: const Icon(Icons.tune_rounded, color: purple),
      title: Text('通知样式（${styles.length}种）'), subtitle: const Text('按展示、振动和铃声分组'),
      children: [
        const Padding(padding: EdgeInsets.fromLTRB(18, 0, 18, 8),
          child: Text('同一样式共用系统设置，修改会影响关联的所有备忘。', style: TextStyle(color: muted, fontSize: 12))),
        ...styles.map((style) => settingRow(Icons.notifications_outlined, style['name'] as String? ?? '通知样式',
          '${style['isDefault'] == true ? '新建默认 · ' : ''}关联 ${style['count'] ?? 0} 条备忘\n'
          '${style['systemOverridden'] == true ? '系统设置与应用偏好不同' : channelImportanceLabel(style['importance'] as int? ?? 0)}'
          '${style['actualVibration'] is String ? '\n${style['actualVibration']}' : ''}'
          '${style['vibrationMismatch'] == true ? '\n振动节奏有差异，请打开本组系统设置检查' : ''}',
          () => native.invokeMethod('channelSettings', style['id']))),
        if (hidden > 0) Padding(padding: const EdgeInsets.all(16), child: Text(
          '已隐藏 $hidden 个无引用的历史通道，手机系统中的原设置仍保留。',
          style: const TextStyle(color: muted, fontSize: 12))),
      ]);
  }
  Widget settingsGroup(List<Widget> children) => Padding(padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Surface(padding: const EdgeInsets.symmetric(vertical: 4), child: Column(children: children)));
  Widget settingsHint(String text) => Padding(padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
    child: Text(text, style: const TextStyle(color: muted, fontSize: 12, height: 1.6)));
  Widget settingRow(IconData icon, String title, String value, Future<void> Function() action) => SettingsActionTile(
    key: settingKey(title), icon: icon, title: title, value: value, highlighted: title == _settingsTargetTitle,
    action: () async {
      try { await action(); } catch (e) { toast(niceError(e)); }
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
String eventTime(dynamic stamp) {
  if (stamp is! int || stamp <= 0) { return '暂无记录'; }
  final d = DateTime.fromMillisecondsSinceEpoch(stamp);
  return '${d.month}月${d.day}日 ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';
}
String dateLabel(DateTime d) => '${d.month}月${d.day}日';
bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
bool occursOn(Reminder r, DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  final anchor = DateTime(r.date.year, r.date.month, r.date.day);
  if (r.repeat == 'none') return sameDay(r.date, d);
  if (!r.enabled || day.isBefore(anchor)) return false;
  return r.repeat == 'daily' || r.days.contains(d.weekday);
}
const presentations = {'banner': '横幅和通知栏', 'drawer': '仅通知栏'};
const lockscreens = {'private': '隐藏正文', 'hidden': '不在锁屏显示'};
String channelImportanceLabel(int importance) => switch (importance) {
  0 => '系统通道已关闭',
  >= 4 => '系统通道：横幅优先级',
  3 => '系统通道：通知栏优先级',
  _ => '系统通道：静默或低重要性',
};
Future<String?> chooseNotificationOption(BuildContext context, String title, Map<String, String> options, String current) =>
  showModalBottomSheet<String>(context: context, showDragHandle: true, builder: (c) => SafeArea(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(padding: const EdgeInsets.all(12), child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
      ...options.entries.map((e) => ListTile(title: Text(e.value),
        trailing: e.key == current ? const Icon(Icons.check_rounded, color: purple) : null,
        onTap: () => Navigator.pop(c, e.key))),
    ])));

class NotificationDisplayOptions extends StatelessWidget {
  final String presentation, lockscreen;
  final bool defaultSettings;
  final ValueChanged<String> onPresentationChanged, onLockscreenChanged;
  const NotificationDisplayOptions({super.key, required this.presentation, required this.lockscreen,
    required this.onPresentationChanged, required this.onLockscreenChanged, this.defaultSettings = false});
  @override Widget build(BuildContext context) => Column(children: [
    ListTile(leading: const Icon(Icons.view_agenda_outlined, color: purple),
      title: Text(defaultSettings ? '默认展示方式' : '展示方式'),
      subtitle: Text(presentations[presentation] ?? presentations['banner']!), trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final v = await chooseNotificationOption(context, '通知展示方式', presentations, presentation);
        if (v != null && context.mounted) { onPresentationChanged(v); }
      }),
    ListTile(leading: const Icon(Icons.lock_outline, color: purple),
      title: Text(defaultSettings ? '默认锁屏显示' : '锁屏显示'),
      subtitle: Text(lockscreens[lockscreen] ?? lockscreens['private']!), trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final v = await chooseNotificationOption(context, '锁屏显示方式', lockscreens, lockscreen);
        if (v != null && context.mounted) { onLockscreenChanged(v); }
      }),
    const Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Text('实际显示受系统设置控制。隐藏正文时，请同时在系统通知设置中关闭“显示敏感内容”；解锁后由系统显示正文。', style: TextStyle(color: muted, fontSize: 12))),
  ]);
}
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
              if (mounted && context.mounted) { setState(() { busy = false; slide = 0; }); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(niceError(e)))); }
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
  final ParsedVoice? voice;
  const ReminderEditor({super.key, required this.reminder, required this.store, this.voice});
  @override State<ReminderEditor> createState() => _ReminderEditorState();
}
class _ReminderEditorState extends State<ReminderEditor> {
  late final TextEditingController text;
  bool saving = false, manualTime = false;
  DateTime? countdownReference;
  Reminder get r => widget.reminder;
  @override void initState() { super.initState(); text = TextEditingController(text: r.text); countdownReference = widget.voice?.reference; }
  @override void dispose() { text.dispose(); super.dispose(); }
  Future<void> save() async {
    if (saving) return;
    r.text = text.text.trim();
    r.enabled = true;
    r.completed = false;
    String? error;
    if (r.text.isEmpty) { error = '请输入提醒内容'; }
    else if (!r.dateConfirmed) { error = '识别的日期无效，请点选日期确认'; }
    else if (!r.timeConfirmed) { error = '请点选时间确认，系统不会替你设置默认时间'; }
    else if (r.repeat == 'weekly' && r.days.isEmpty) { error = '请选择重复星期'; }
    else if (r.repeat == 'none' && !r.date.isAfter(DateTime.now())) { error = '请选择未来的日期和时间'; }
    if (error != null) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error))); return; }
    setState(() => saving = true);
    try {
      await native.invokeMethod('requestNotifications');
      if (r.repeat == 'none' && !r.date.isAfter(DateTime.now())) { throw StateError('确认期间时间已到，请重新选择时间或明确重新计时'); }
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
    if (d != null && mounted) setState(() { r.date = DateTime(d.year, d.month, d.day, r.date.hour, r.date.minute, r.date.second, r.date.millisecond); r.dateConfirmed = true; manualTime = true; });
  }
  Future<void> pickTime() async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(r.date),
      builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: child!));
    if (t != null && mounted) setState(() { r.date = DateTime(r.date.year, r.date.month, r.date.day, t.hour, t.minute); r.timeConfirmed = true; manualTime = true; });
  }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(r.id == 0 ? '新建提醒' : '编辑提醒'), actions: [TextButton(onPressed: saving ? null : save, child: const Text('保存'))]),
    body: ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 24), children: [
      if (widget.voice != null) ...[
        Surface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(!r.dateConfirmed ? '日期无效，请手动选择日期' : !r.timeConfirmed ? '请手动选择有效时间' : r.repeat == 'none' && !r.date.isAfter(DateTime.now()) ? '目标时间已过期，请修改或明确重新计时' : '请确认识别出的时间和内容', style: const TextStyle(color: purple)),
          if (widget.voice!.settings.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(widget.voice!.settings.join(' · '))),
          if (widget.voice!.relativeDelay != null) ...[
            Text(manualTime ? '已手动修改，按下方日期和时间提醒' : '以 ${countdownReference!.hour}:${countdownReference!.minute.toString().padLeft(2, '0')}:${countdownReference!.second.toString().padLeft(2, '0')} 为基准计时，目标为 ${r.date.year}年${r.date.month}月${r.date.day}日 ${r.preciseTime}'),
            TextButton(onPressed: () => setState(() { countdownReference = DateTime.fromMillisecondsSinceEpoch(DateTime.now().millisecondsSinceEpoch); r.date = countdownReference!.add(widget.voice!.relativeDelay!); r.dateConfirmed = true; r.timeConfirmed = true; manualTime = false; }), child: const Text('从现在起重新计时')),
          ],
        ])), const SizedBox(height: 14),
      ],
      Surface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('提醒内容', style: TextStyle(fontWeight: FontWeight.w600)), const SizedBox(height: 12),
        TextField(controller: text, minLines: 2, maxLines: 5, maxLength: 2000,
          decoration: const InputDecoration(hintText: '写下一件重要的事…')),
      ])), const SizedBox(height: 14),
      Surface(padding: const EdgeInsets.symmetric(vertical: 5), child: Column(children: [
        ListTile(leading: const Icon(Icons.calendar_today_outlined, color: purple), title: const Text('日期'),
          trailing: Text(r.dateConfirmed ? '${r.date.year}年${r.date.month}月${r.date.day}日' : '请选择有效日期'), onTap: pickDate),
        ListTile(leading: const Icon(Icons.schedule_rounded, color: purple), title: const Text('时间'), trailing: Text(r.timeConfirmed ? r.preciseTime : '请选择时间'), onTap: pickTime),
      ])), const SizedBox(height: 14),
      Surface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('重复', style: TextStyle(fontWeight: FontWeight.w600)), const SizedBox(height: 14),
        SizedBox(width: double.infinity, child: SegmentedButton<String>(showSelectedIcon: false,
          segments: const [ButtonSegment(value: 'none', label: Text('仅一次')), ButtonSegment(value: 'daily', label: Text('每天')), ButtonSegment(value: 'weekly', label: Text('每周'))],
          selected: {r.repeat}, onSelectionChanged: (v) => setState(() { r.repeat = v.first; if (r.repeat == 'weekly' && r.days.isEmpty) r.days = [r.date.weekday]; }))),
        if (r.repeat == 'weekly') ...[const SizedBox(height: 16), Wrap(spacing: 8, runSpacing: 8, children: List.generate(7, (i) => FilterChip(
          label: Text(weekdays[i]), selected: r.days.contains(i + 1), onSelected: (v) => setState(() { if (v) { r.days.add(i + 1); } else { r.days.remove(i + 1); } }))))],
      ])), const SizedBox(height: 14),
      Surface(padding: const EdgeInsets.symmetric(vertical: 5), child: Column(children: [
        const ListTile(title: Text('提醒方式', style: TextStyle(fontWeight: FontWeight.w700))),
        NotificationDisplayOptions(presentation: r.presentation, lockscreen: r.lockscreen,
          onPresentationChanged: (v) => setState(() => r.presentation = v),
          onLockscreenChanged: (v) => setState(() => r.lockscreen = v)),
        ListTile(leading: const Icon(Icons.tune_rounded, color: purple), title: const Text('这条提醒的系统通知设置'),
          subtitle: const Text('请选择允许横幅／悬浮通知；相同样式共用系统设置。亮屏卡片增强可在设置开启'), trailing: const Icon(Icons.open_in_new_rounded),
          onTap: () async {
            try { await widget.store.openNotificationSettings(r); }
            catch (e) { if (context.mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(niceError(e)))); } }
          }),
        SwitchListTile(title: const Text('尝试亮屏'), subtitle: const Text('保持锁屏，遵循手机系统限制'), value: r.wakeScreen, onChanged: (v) => setState(() => r.wakeScreen = v)),
        ListTile(leading: const Icon(Icons.vibration, color: purple), title: const Text('振动'), subtitle: Text(vibrationLabel(r.vibration)),
          trailing: const Icon(Icons.chevron_right), onTap: () async {
            final v = await chooseVibration(context, r.vibration); if (v != null && mounted) setState(() => r.vibration = v);
          }),
        SwitchListTile(title: const Text('铃声'), value: r.sound, onChanged: (v) => setState(() => r.sound = v)),
        if (r.sound) ListTile(leading: const Icon(Icons.music_note_outlined, color: purple), title: const Text('从系统选择铃声'),
          subtitle: Text(r.ringtone.isEmpty ? '系统默认' : '已选择系统铃声'), trailing: const Icon(Icons.chevron_right), onTap: () async {
            try { final v = await native.invokeMethod<String>('pickRingtone', r.ringtone); if (v != null && mounted) setState(() => r.ringtone = v); }
            catch (e) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(niceError(e)))); }
          }),
      ])), const SizedBox(height: 14),
      Surface(padding: const EdgeInsets.symmetric(vertical: 5), child: Column(children: [
        const ListTile(title: Text('语音播报', style: TextStyle(fontWeight: FontWeight.w700))),
        SpeechOptions(groups: widget.store.voiceGroups, reminder: r, defaults: widget.store.defaults, onChanged: () async { if (mounted) setState(() {}); }),
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


bool calendarOccursOn(Reminder r, DateTime date) => r.completed || r.archived ? sameDay(historyCalendarDate(r), date) : occursOn(r, date);

DateTime historyCalendarDate(Reminder r) => r.historyScheduledAt > 0 ? DateTime.fromMillisecondsSinceEpoch(r.historyScheduledAt) : r.activeOccurrence > 0 ? DateTime.fromMillisecondsSinceEpoch(r.activeOccurrence) : r.date;
