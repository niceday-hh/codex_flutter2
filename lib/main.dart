import 'dart:async';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'asr.dart';
import 'reminder.dart';
import 'reminder_search.dart';
import 'voice_parser.dart';
import 'speech.dart';
import 'reminder_audio.dart';
import 'speech_options.dart';
import 'task_library.dart';
import 'voice_flow.dart';
import 'app_error.dart';
import 'design_tokens.dart';
import 'voice_page.dart';
import 'voice_groups_page.dart';
import 'app_style.dart';
import 'settings_page.dart';
import 'voice_catalog.dart';
import 'vibration_picker.dart';
import 'widgets/widgets.dart';
export 'vibration_picker.dart' show chooseVibration, vibrationLabel;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MemoApp());
}

/// Platform text theme used as the merge base, so CJK/Arabic fallback keeps
/// working. `black` decides the baseline foreground: the dark theme starts from
/// white, so any style that does not set its own colour still reads.
TextTheme _platformTextTheme(Brightness brightness) {
  final typography = Typography.material2021(platform: defaultTargetPlatform);
  return brightness == Brightness.light ? typography.black : typography.white;
}

TextTheme _memoTextTheme(TextTheme base, MemoType t) => TextTheme(
  displayLarge: base.displayLarge?.merge(t.display),
  headlineLarge: base.headlineLarge?.merge(t.display),
  headlineSmall: base.headlineSmall?.merge(t.title),
  titleLarge: base.titleLarge?.merge(t.title),
  titleMedium: base.titleMedium?.merge(t.headline),
  bodyLarge: base.bodyLarge?.merge(t.subtitle),
  bodyMedium: base.bodyMedium?.merge(t.body),
  bodySmall: base.bodySmall?.merge(t.caption),
  labelLarge: base.labelLarge?.merge(t.button),
  labelMedium: base.labelMedium?.merge(t.overline),
  labelSmall: base.labelSmall?.merge(t.caption),
);

class MemoApp extends StatelessWidget {
  const MemoApp({super.key});

  ThemeData _theme(Brightness brightness) {
    final tokens = brightness == Brightness.dark ? MemoTokens.dark : MemoTokens.light;
    final c = tokens.colors;
    final t = tokens.text;
    final base = _platformTextTheme(brightness);
    // On a light brand fill the label is white; on the lighter dark-mode brand
    // fill it has to go dark, or it drops under 4.5:1.
    final onBrandFill = brightness == Brightness.dark ? c.canvas : Colors.white;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(seedColor: c.brand500, surface: c.surface, brightness: brightness),
      scaffoldBackgroundColor: c.canvas,
      extensions: [tokens],
      // Every token style is merged onto the platform text theme instead of
      // replacing it. A bare `TextStyle` has no `fontFamily`, and anything that
      // resolves a style straight into a `DefaultTextStyle` — buttons, dialogs,
      // chips — then falls back to the engine default, which in the test harness
      // has no CJK glyphs at all. Merging keeps the platform family while the
      // tokens keep control of size, weight, height and colour.
      textTheme: _memoTextTheme(base, t),
      appBarTheme: AppBarTheme(backgroundColor: c.canvas, foregroundColor: c.ink, centerTitle: true,
        elevation: 0, scrolledUnderElevation: 0,
        systemOverlayStyle: brightness == Brightness.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        titleTextStyle: base.titleLarge?.merge(t.headline)),
      inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: c.brand50,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(MemoRadius.lg),
          borderSide: BorderSide(color: c.outline)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(MemoRadius.lg),
          borderSide: BorderSide(color: c.outline)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(MemoRadius.lg),
          borderSide: BorderSide(color: c.brand600, width: 1.6))),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
        backgroundColor: c.brand500, foregroundColor: onBrandFill, elevation: 0,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MemoRadius.lg)))),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
        foregroundColor: c.brand700, side: BorderSide(color: c.brand200),
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MemoRadius.md)))),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating, elevation: 0),
      dialogTheme: DialogThemeData(backgroundColor: c.surface, elevation: 0),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: c.surface, surfaceTintColor: Colors.transparent),
    );
  }

  @override Widget build(BuildContext context) => MaterialApp(
    title: '超级提醒', debugShowCheckedModeBanner: false,
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    themeMode: ThemeMode.system,
    // Status and navigation bar icons follow the theme instead of being fixed
    // to dark-on-light, which made them invisible once the page went dark.
    builder: (context, child) {
      final dark = Theme.of(context).brightness == Brightness.dark;
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: dark ? MemoPalette.dark.canvas : MemoPalette.light.canvas,
          systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
          systemNavigationBarDividerColor: Colors.transparent,
          systemStatusBarContrastEnforced: false, systemNavigationBarContrastEnforced: false),
        child: child!,
      );
    },
    home: const MemoHome(),
  );
}

class MemoHome extends StatefulWidget {
  const MemoHome({super.key});
  @override State<MemoHome> createState() => _MemoHomeState();
}

class _MemoHomeState extends State<MemoHome> with WidgetsBindingObserver, TickerProviderStateMixin {
  final store = MemoStore();
  int tab = 0;
  bool loading = true;
  String? error;
  late final voice = VoiceFlow(capture: OfflineVoiceCapture(asr), store: store,
    openVoicePage: () { if (mounted) setState(() => tab = 2); }, onSaved: reload);
  DialogRoute<void>? _voiceDialog;
  bool _dialogScheduled = false, _wasPaused = false, _entryPending = true;
  bool _initialized = false, _foreground = true, _checkingEntry = false, _entryAgain = false, _suppressVoiceEntry = false;
  bool _taskLibraryOpen = false, _settingsSheetOpen = false, _detailOpen = false, _editorOpen = false;
  ValueNotifier<Reminder>? _detailSelection;
  final _settingsMessenger = GlobalKey<ScaffoldMessengerState>();
  GlobalKey? _settingsTargetKey;
  String? _settingsTargetTitle;
  int _entryEpoch = 0, _lifecycleEpoch = 0;
  DateTime selectedDate = DateTime.now();
  DateTime calendarMonth = DateTime(DateTime.now().year, DateTime.now().month);
  /// Ids picked in batch mode. Non-empty means the list is in selection
  /// mode: taps toggle instead of opening, and the app bar swaps to actions.
  final Set<int> _picked = {};
  bool get _selecting => _picked.isNotEmpty;

  // Motion. One controller for the whole app: the first screen resolves in
  // half a second, then nothing ticks. Tab switches deliberately have no
  // content transition — see the note in build().
  late final AnimationController _enter;
  final Map<int, Animation<double>> _revealCache = {};
  bool _entered = false;

  Animation<double> _revealAt(int i) => _revealCache.putIfAbsent(i, () {
    final begin = (i.clamp(0, MemoMotion.enterMaxItems) * MemoMotion.enterStep)
      .clamp(0.0, 1.0 - MemoMotion.enterSpan);
    return CurvedAnimation(parent: _enter,
      curve: Interval(begin, begin + MemoMotion.enterSpan, curve: MemoMotion.curve));
  });

  Widget _reveal(int i, Widget child) =>
    _enter.isCompleted ? child : MemoReveal(animation: _revealAt(i), child: child);

  void _playEntrance() {
    if (_entered) return;
    _entered = true;
    _enter.forward(from: 0);
  }

  @override void initState() {
    super.initState(); WidgetsBinding.instance.addObserver(this);
    _enter = AnimationController(vsync: this, duration: MemoMotion.enter)
      ..addStatusListener((s) { if (s == AnimationStatus.completed && mounted) setState(() {}); });
    asr.setForeground(true);
    voice.addListener(_voiceChanged);
    native.setMethodCallHandler((call) async {
      if (call.method == 'openReminder') {
        _suppressVoiceEntry = true; _entryPending = false; _entryEpoch++;
        _pauseForNavigation(); await reload(); if (mounted) openById(call.arguments as int);
      }
      if (call.method == 'voiceEntry') {
        if (voice.active || voice.pending != null) return;
        _suppressVoiceEntry = false; _entryPending = true; _entryEpoch++;
        await _maybeStartHandsFree();
      }
      if (call.method == 'speechPreviewEnded') speech.previewEnded(call.arguments as int);
      if (call.method == 'speechPreviewFailed') speech.previewEnded(call.arguments as int, error: '音频播放失败，请重试');
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
    } catch (e) { toast(niceError(e), error: true); }
    finally {
      _checkingEntry = false;
      if (_entryAgain) {
        _entryAgain = false;
        if (_canStartHandsFree) unawaited(_maybeStartHandsFree());
      }
    }
  }
  bool get _canStartHandsFree => mounted && _initialized && _foreground && _entryPending &&
    !_suppressVoiceEntry && !_taskLibraryOpen && !_settingsSheetOpen && !_detailOpen && !_editorOpen && !voice.active && voice.pending == null &&
    store.defaults['handsFree'] == true && !Navigator.of(context).canPop();
  void _warmManualTab() {
    if (!mounted || !_foreground || tab != 2 || voice.active) return;
    unawaited(asr.prewarm().catchError((Object _) {}));
  }
  void _selectTab(int i) {
    if (i == tab) return;
    HapticFeedback.selectionClick();
    _entryPending = false; _entryEpoch++; speech.stopPreview();
    final stopped = voice.active || voice.pending != null ? voice.pause(keepDraft: false) : Future<void>.value();
    setState(() { tab = i; _picked.clear(); });
    unawaited(stopped.then((_) async {
      if (!mounted || !_foreground || tab != i || voice.active) return;
      if (i == 2) _warmManualTab();
    }).catchError((Object e) { toast(niceError(e), error: true); }));
  }
  void _shiftMonth(int delta) {
    HapticFeedback.selectionClick();
    setState(() => calendarMonth = DateTime(calendarMonth.year, calendarMonth.month + delta));
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
    for (final a in _revealCache.values) { if (a is CurvedAnimation) a.dispose(); }
    _revealCache.clear();
    _enter.dispose();
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
          barrierColor: context.colors.ink.withValues(alpha: .20),
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
        _playEntrance();
      }
    } catch (e) {
      if (mounted) {
        if (_settingsSheetOpen) { loading = false; error = niceError(e); toast(error!, error: true); }
        else { setState(() { loading = false; error = niceError(e); }); }
      }
    }
  }
  Widget _selectionBar() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
    child: Material(color: context.colors.brand100, borderRadius: BorderRadius.circular(MemoRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
        child: Row(children: [
          Text('已选 ${_picked.length} 条', style: context.text.label.copyWith(color: context.colors.brand800)),
          const Spacer(),
          TextButton(onPressed: _archivePicked, child: const Text('完成')),
          TextButton(onPressed: _deletePicked,
            child:  Text('删除', style: TextStyle(color: context.colors.danger))),
          IconButton(tooltip: '取消选择', onPressed: () => setState(_picked.clear),
            icon: const Icon(Icons.close_rounded, size: 20)),
        ]))));
  void toast(String s, {bool error = false}) {
    if (!mounted) return;
    final local = _settingsMessenger.currentState;
    final messenger = local != null && ModalRoute.of(local.context)?.isCurrent == true
      ? local : ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(memoSnackBar(s, error: error));
  }
  void _pauseForNavigation() {
    _entryPending = false; _entryEpoch++; speech.stopPreview();
    unawaited(voice.pause(keepDraft: false).catchError((Object e) { toast(niceError(e), error: true); }));
  }
  void _togglePick(Reminder r) {
    HapticFeedback.selectionClick();
    setState(() { if (!_picked.remove(r.id)) _picked.add(r.id); });
  }
  Future<void> _archivePicked() async {
    final ids = [..._picked];
    if (ids.isEmpty) return;
    HapticFeedback.mediumImpact();
    setState(_picked.clear);
    try { await store.archiveAll(ids); await reload(); toast('已保留 ${ids.length} 条到历史任务'); }
    catch (e) { toast(niceError(e), error: true); }
  }
  Future<void> _deletePicked() async {
    final ids = [..._picked];
    if (ids.isEmpty) return;
    final yes = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: Text('删除 ${ids.length} 条提醒？'), content: const Text('删除后，这些提醒及剩余重提醒都会取消。'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
        TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('删除'))]));
    if (yes != true) return;
    HapticFeedback.mediumImpact();
    setState(_picked.clear);
    try { await store.deleteAll(ids); await reload(); toast('已删除 ${ids.length} 条'); }
    catch (e) { toast(niceError(e), error: true); }
  }
  Future<void> _openSearch() async {
    if (!mounted) return;
    _pauseForNavigation();
    final picked = await Navigator.of(context).push<Reminder>(
      MaterialPageRoute(builder: (_) => ReminderSearchPage(reminders: store.reminders)));
    if (picked != null && mounted) await viewReminder(picked);
  }
  Future<void> edit([Reminder? existing]) async {
    if (!mounted || _editorOpen) return;
    _editorOpen = true; _pauseForNavigation();
    try {
      final draft = existing == null ? store.draft() : Reminder.fromJson({...existing.toJson()});
      draft.enabled = true;
      draft.completed = false;
      draft.archived = false;
      if (existing != null && (existing.archived || existing.completed) && draft.repeat == 'none' && !draft.date.isAfter(DateTime.now())) {
        draft.date = DateTime.now().add(const Duration(hours: 1));
      }
      final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => ReminderEditor(reminder: draft, store: store)));
      if (saved == true) {
        HapticFeedback.lightImpact();
        if (mounted && existing != null && (existing.archived || existing.completed)) {
          Navigator.of(context).popUntil((route) => route.isFirst);
          setState(() => tab = 0);
        }
        await reload();
        // Duplicate-time warning, not a block: people do schedule two things
        // for the same minute on purpose, they just do not want to find out
        // when both fire at once.
        final same = store.reminders.where((x) => !x.completed && !x.archived && x.enabled
          && x.date.year == draft.date.year && x.date.month == draft.date.month
          && x.date.day == draft.date.day && x.date.hour == draft.date.hour
          && x.date.minute == draft.date.minute).length;
        toast(same > 1 ? '提醒已保存 · 同一时间还有 ${same - 1} 条' : '提醒已保存');
      }
    } finally { _editorOpen = false; }
  }
  void openById(int id) {
    final matches = store.reminders.where((r) => r.id == id);
    if (matches.isEmpty) return;
    if (_editorOpen) { toast('请先完成当前编辑，再打开提醒'); return; }
    final selection = _detailSelection;
    if (selection != null) { selection.value = matches.first; return; }
    viewReminder(matches.first);
  }
  Future<void> viewReminder(Reminder r) async {
    if (!mounted || _detailOpen || _editorOpen) return;
    _detailOpen = true; _pauseForNavigation();
    final selection = _detailSelection = ValueNotifier(r);
    try {
      await showModalBottomSheet<void>(context: context, isScrollControlled: true,
        backgroundColor: Colors.white, showDragHandle: true,
        builder: (sheetContext) => ValueListenableBuilder<Reminder>(valueListenable: selection,
          builder: (_, current, _) => ReminderDetail(key: ValueKey(current.id), reminder: current, onAck: () async {
          HapticFeedback.lightImpact();
          await store.ack(current);
          if (sheetContext.mounted) Navigator.pop(sheetContext);
          await reload();
        }, onEdit: () { Navigator.pop(sheetContext); edit(current); })));
    } finally { _detailOpen = false; _detailSelection = null; selection.dispose(); }
  }
  Future<void> remove(Reminder r) async {
    final yes = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('删除提醒？'), content: const Text('删除后，本条提醒及剩余重提醒都会取消。'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
        TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('删除'))]));
    if (yes == true) {
      HapticFeedback.mediumImpact();
      try { await store.delete(r.id); await reload(); } catch (e) { toast(niceError(e), error: true); }
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
    HapticFeedback.mediumImpact();
    try {
      if (action == 'archive') { await store.archive(r.id); toast('已保留到历史任务，可编辑后复用'); }
      else { await store.delete(r.id); toast('任务已删除'); }
      await reload();
    } catch (e) { toast(niceError(e), error: true); }
  }
  Future<void> taskLibrary() async {
    if (!mounted || _taskLibraryOpen) return;
    // Acquire before any await; the page must not wait for a cold ASR load.
    _taskLibraryOpen = true; _entryPending = false; _entryEpoch++;
    unawaited(voice.pause(keepDraft: false).catchError((Object e) { toast(niceError(e), error: true); }));
    try {
      await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => TaskLibraryPage(
        store: store, card: reminderCard)));
    } finally { _taskLibraryOpen = false; }
    if (mounted) await reload();
  }
  @override Widget build(BuildContext context) => Scaffold(
    body: MemoGlow(child: SafeArea(child: Column(children: [
      if (_selecting) _selectionBar(),
      if (voice.active && voice.pending == null && tab != 2) Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Material(color: context.colors.brand100, borderRadius: BorderRadius.circular(MemoRadius.lg),
          clipBehavior: Clip.antiAlias,
          child: ListTile(dense: true,
            leading:  Icon(Icons.mic_none_rounded, color: context.colors.brand700, size: 20),
            title: Text(voice.message, style: context.text.label.copyWith(color: context.colors.brand800)),
            subtitle: voice.phase == VoicePhase.commands
              ? ValueListenableBuilder<int>(valueListenable: voice.countdown,
                  builder: (_, seconds, __) => Text('剩余 $seconds 秒', style: context.text.caption))
              : null,
            trailing: IconButton(tooltip: '停止预听', onPressed: voice.cancel,
              icon: const Icon(Icons.close_rounded, size: 20))))),
      Expanded(child: loading ? const Center(child: CircularProgressIndicator())
      : error != null ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(error!), TextButton(onPressed: reload, child: const Text('重新加载'))]))
      // No fade or slide between tabs. Any `Opacity` below 1 makes Flutter
      // rasterise the entire page into an offscreen buffer every frame, and a
      // moving `Transform` repaints that whole subtree with it — 200ms of that
      // on a scrolling list is exactly the stutter this was supposed to avoid.
      // The switch signal is the navigation bar's indicator (Material 3 already
      // animates it) plus the selection tick; both cost nothing to paint.
      //
      // Each tab gets its own layer instead: a banner or a snackbar appearing
      // over the list no longer repaints the calendar sitting behind it.
      : IndexedStack(index: tab, children: [
        RepaintBoundary(child: homePage()),
        RepaintBoundary(child: calendarPage()),
        TickerMode(enabled: tab == 2, child: RepaintBoundary(child: VoicePage(flow: voice))),
        RepaintBoundary(child: settingsPage()),
      ])),
    ]))),
    floatingActionButton: !loading && error == null && !_selecting && (tab == 0 || tab == 1)
      ? FloatingActionButton(onPressed: () => edit(), backgroundColor: context.colors.brand500,
          foregroundColor: Colors.white, tooltip: '新建提醒', child: const Icon(Icons.add_rounded, size: 32)) : null,
    bottomNavigationBar: SafeArea(top: false, child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(MemoRadius.xxl),
          border: Border.all(color: context.colors.line),
          boxShadow: MemoShadow.card,
        ),
        child: ClipRRect(borderRadius: BorderRadius.circular(MemoRadius.xxl), child: NavigationBar(
          backgroundColor: context.colors.surface, surfaceTintColor: Colors.transparent,
          height: 72, labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          selectedIndex: tab, indicatorColor: context.colors.brand100,
          onDestinationSelected: _selectTab, destinations: const [
            NavigationDestination(icon: Icon(Icons.description_outlined), selectedIcon: Icon(Icons.description_rounded), label: '备忘录'),
            NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month_rounded), label: '日历'),
            NavigationDestination(icon: Icon(Icons.mic_none_rounded), selectedIcon: Icon(Icons.mic_rounded), label: '语音'),
            NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings_rounded), label: '设置'),
          ])),
      ))),
  );
  Widget header(String title, String subtitle, {Widget? trailing}) =>
    MemoPageHeader(title: title, subtitle: subtitle, trailing: trailing);
  Widget homePage() {
    final list = store.reminders.where((r) => !r.archived).toList()..sort((a, b) {
      if (a.unread != b.unread) return a.unread ? -1 : 1;
      return a.displayDate.compareTo(b.displayDate);
    });
    final active = list.where((r) => !r.completed && (r.enabled || r.unread)).toList();
    final paused = list.where((r) => !r.enabled && !r.completed && !r.unread).toList();
    final now = DateTime.now();
    final historyCount = store.reminders.where((r) => r.archived || r.completed).length;
    final today = DateTime(now.year, now.month, now.day);
    // Day buckets instead of one long list. The section is the unit people
    // scan for ("what is left today"), and a pinned header keeps it on screen
    // while the group scrolls under it.
    String bucketOf(DateTime d) {
      final diff = DateTime(d.year, d.month, d.day).difference(today).inDays;
      if (diff <= 0) return '今天';
      if (diff == 1) return '明天';
      if (diff < 7) return '本周';
      return '更晚';
    }
    final groups = <String, List<Reminder>>{};
    for (final r in active) { (groups[bucketOf(r.displayDate)] ??= []).add(r); }

    return RefreshIndicator(onRefresh: reload, child: CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(), slivers: [
      SliverList.list(children: [
        header('备忘录', '把重要的事，交给提醒', trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(icon: const Icon(Icons.search_rounded), tooltip: '搜索提醒', onPressed: _openSearch),
          IconButton(icon: const Icon(Icons.inventory_2_outlined), tooltip: '历史任务', onPressed: taskLibrary),
        ])),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: Text(
          '${now.month}月${now.day}日  周${weekdays[now.weekday - 1]}', style: const TextStyle(fontWeight: FontWeight.w600))),
        const SizedBox(height: 16),
        if (active.isNotEmpty && !_selecting) _reveal(0, heroCard(active.first, now)),
        if (store.status['notifications'] != true || store.status['exact'] != true) permissionBanner(),
        if (active.isEmpty) MemoEmptyState(art: const MemoEmptyArt(), icon: Icons.edit_note_rounded,
          title: '留一点空间，给重要的事', subtitle: '点击下方按钮，或用语音创建第一条提醒',
          actionLabel: '新建提醒', onAction: () => edit()),
      ]),
      for (final label in const ['今天', '明天', '本周', '更晚'])
        if (groups[label] case final items?) SliverMainAxisGroup(slivers: [
          SliverPersistentHeader(pinned: true, delegate: _GroupHeader(label, items.length)),
          SliverList.builder(itemCount: items.length,
            itemBuilder: (_, i) => _reveal(i + 1, reminderCard(items[i]))),
        ]),
      SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 0), child: MemoCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), onTap: taskLibrary, child: Row(children: [
         Icon(Icons.history_rounded, color: context.colors.brand500, size: 22),
        const SizedBox(width: MemoSpace.md),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('历史任务 · $historyCount 条', style: context.text.subtitle),
          const SizedBox(height: 2),
          Text('完成或主动保留的任务统一收纳，支持搜索和复用', style: context.text.caption),
        ])),
         Icon(Icons.chevron_right_rounded, color: context.colors.muted, size: 20),
      ])))),
      if (paused.isNotEmpty) SliverToBoxAdapter(child: section('未启用', '${paused.length} 条')),
      SliverList.builder(itemCount: paused.length, itemBuilder: (_, i) => _reveal(i + 1, reminderCard(paused[i]))),
      const SliverToBoxAdapter(child: SizedBox(height: 90)),
    ]));
  }
  /// The one gradient in the app. Its palette depends on the hour, so opening
  /// the app at 23:00 does not look identical to opening it at 09:00.
  Widget heroCard(Reminder r, DateTime now) => Padding(padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Container(decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(MemoRadius.xxl),
      boxShadow: MemoShadow.hero),
      child: Material(type: MaterialType.transparency, child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: MemoColor.heroGradientFor(now.hour)),
          borderRadius: const BorderRadius.all(Radius.circular(MemoRadius.xxl))),
        child: InkWell(onTap: () => _selecting ? _togglePick(r) : viewReminder(r),
          borderRadius: BorderRadius.circular(MemoRadius.xxl),
          child: Stack(children: [
            Positioned.fill(child: IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(MemoRadius.xxl)),
              gradient: LinearGradient(begin: Alignment.topCenter, end: const Alignment(0, .68),
                colors: [MemoColor.heroSheen, MemoColor.heroSheenEnd]))))),
            Padding(padding: const EdgeInsets.fromLTRB(22, 20, 22, 21),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(r.unread ? Icons.mark_email_unread_outlined : Icons.notifications_active_outlined,
                  color: context.colors.onBrand, size: 18),
                const SizedBox(width: MemoSpace.sm),
                Text(r.unread ? '待确认提醒' : '下一条提醒',
                  style: context.text.label.copyWith(color: context.colors.onBrand)),
                const Spacer(),
                 Icon(Icons.arrow_forward_rounded, color: context.colors.onBrand, size: 20)]),
              const SizedBox(height: MemoSpace.md),
              Text(r.time, style: context.text.heroTime),
              const SizedBox(height: 9),
              Text(r.text, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.heroTitle),
              const SizedBox(height: 13),
              Text(dateLabel(r.displayDate) + (r.repeat != 'none' ? ' · ${r.repeatLabel}' : ''),
                style: context.text.caption.copyWith(color: context.colors.onBrandSoft, letterSpacing: .2)),
            ])),
          ]))))));
  Key? settingKey(String title) => title == _settingsTargetTitle ? _settingsTargetKey : null;
  Widget section(String title, String subtitle) =>
    KeyedSubtree(key: settingKey(title), child: MemoSectionHeader(title, trailing: subtitle));
  Widget permissionBanner() => Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
    child: MemoBanner(icon: Icons.info_outline_rounded,
      text: '请在设置中开启通知与精确定时权限', onTap: () => _selectTab(3)));
  Widget reminderCard(Reminder r) {
    // One status chip, everything else folds into a single meta line. The card
    // used to carry up to three pills; three pills is noise, and noise is what
    // made the list read as a wall instead of a sequence.
    final status = r.completed || r.archived ? '已结束'
      : !r.enabled ? '未启用'
      : r.unread ? '未读 ${r.attempts}/${r.totalCount}' : null;
    final meta = StringBuffer(dateLabel(r.displayDate));
    if (!r.completed && !r.archived && r.repeat != 'none') meta.write(' · ${r.repeatLabel}');
    if (r.speechState != 'off') {
      meta.write(' · ${r.speechState == 'ready' ? '语音就绪' : r.speechState == 'preparing' ? '语音准备中' : '语音待准备'}');
    }
    final picked = _picked.contains(r.id);
    final card = Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 10), child: MemoCard(
      selected: picked,
      padding: const EdgeInsets.fromLTRB(14, 13, 6, 13),
      onTap: _selecting ? () => _togglePick(r) : () => viewReminder(r),
      onLongPress: () => _togglePick(r),
      child: Row(children: [
        if (_selecting) Padding(padding: const EdgeInsets.only(right: 10),
          child: Icon(picked ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            color: picked ? context.colors.brand600 : context.colors.outline, size: 22))
        else Container(width: 4, height: 52, decoration: BoxDecoration(
          color: r.completed ? context.colors.lineStrong : r.unread ? context.colors.amber : context.colors.brand500,
          borderRadius: BorderRadius.circular(MemoRadius.pill))),
        const SizedBox(width: MemoSpace.md),
        Text(r.time, style: r.completed ? context.text.cardTime.copyWith(color: context.colors.muted) : context.text.cardTime),
        const SizedBox(width: MemoSpace.md), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(r.text, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: r.completed ? context.text.cardTitle.copyWith(color: context.colors.muted) : context.text.cardTitle),
          const SizedBox(height: 5), Row(children: [
            if (status != null) ...[MemoTag(status, emphasized: r.unread), const SizedBox(width: 6)],
            Flexible(child: Text(meta.toString(), maxLines: 1, overflow: TextOverflow.ellipsis,
              style: context.text.caption)),
          ]),
        ])),
        if (_selecting) const SizedBox(width: 10)
        else PopupMenuButton<String>(tooltip: '更多操作', onSelected: (v) async {
          if (v == 'edit') { await edit(r); }
          else if (v == 'archive') { await finishTask(r); }
          else { await remove(r); }
        }, itemBuilder: (_) => [PopupMenuItem(value: 'edit', child: Text(r.archived || r.completed ? '编辑并复用' : '编辑')),
          if (!r.archived && !r.completed) const PopupMenuItem(value: 'archive', child: Text('结束并保留')),
          const PopupMenuItem(value: 'delete', child: Text('删除'))]),
      ])));
    // Swipe is disabled while picking: a horizontal drag would otherwise fight
    // the selection gesture and dismiss cards the user meant to tick.
    if (r.archived || r.completed || _selecting) return card;
    return Dismissible(key: ValueKey('task-${r.id}-${r.activeOccurrence}-${r.attempts}'), direction: DismissDirection.endToStart,
      background: const SizedBox.shrink(),
      secondaryBackground: Container(margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
        padding: const EdgeInsets.symmetric(horizontal: MemoSpace.xl), alignment: Alignment.centerRight,
        decoration: BoxDecoration(color: context.colors.brand100, borderRadius: BorderRadius.circular(MemoRadius.xl)),
        child:  Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.archive_outlined, color: context.colors.brand700, size: 20), SizedBox(width: 6),
          Text('保留 / 删除', style: TextStyle(color: context.colors.brand700, fontWeight: FontWeight.w600,
            fontSize: 14)),
        ])),
      confirmDismiss: (_) async {
        await finishTask(r);
        return false;
      }, child: card);
  }
  // Marks for the visible month, computed once per (data, month) pair instead of
  // scanning every reminder inside all 42 grid cells on every rebuild.
  List<Reminder>? _marksSource;
  DateTime? _marksMonth;
  Set<int> _marks = const <int>{};
  Set<int> _monthMarks(DateTime first, int count) {
    if (identical(_marksSource, store.reminders) && _marksMonth == first) return _marks;
    final marks = <int>{};
    for (var d = 1; d <= count; d++) {
      final date = DateTime(first.year, first.month, d);
      if (store.reminders.any((r) => calendarOccursOn(r, date))) marks.add(d);
    }
    _marksSource = store.reminders; _marksMonth = first; _marks = marks;
    return marks;
  }
  Widget calendarPage() {
    final first = DateTime(calendarMonth.year, calendarMonth.month);
    final count = DateTime(first.year, first.month + 1, 0).day;
    final offset = first.weekday - 1;
    final marks = _monthMarks(first, count);
    final list = store.reminders.where((r) => calendarOccursOn(r, selectedDate)).toList()..sort((a, b) => a.time.compareTo(b.time));
    final active = list.where((r) => !r.completed && !r.archived).toList();
    final history = list.where((r) => r.completed || r.archived).toList();
    return CustomScrollView(slivers: [SliverList.list(children: [
      header('提醒日历', '每一天，都安排得刚刚好'),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: MemoCard(child: Column(children: [
        Row(children: [Expanded(child: Align(alignment: Alignment.centerLeft,
            child: AnimatedSwitcher(duration: MemoMotion.fast, transitionBuilder: (child, t) =>
              FadeTransition(opacity: t, child: child),
              child: Text('${first.year}年${first.month}月', key: ValueKey('${first.year}-${first.month}'),
                style: context.text.title)))),
          IconButton(tooltip: '上个月', onPressed: () => _shiftMonth(-1), icon: const Icon(Icons.chevron_left_rounded)),
          IconButton(tooltip: '下个月', onPressed: () => _shiftMonth(1), icon: const Icon(Icons.chevron_right_rounded))]),
        Row(children: weekdays.map((s) => Expanded(child: Center(child: Text(s, style: context.text.caption)))).toList()),
        const SizedBox(height: MemoSpace.md),
        Material(type: MaterialType.transparency, child: GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, mainAxisSpacing: 4),
          itemCount: ((count + offset) / 7).ceil() * 7,
          itemBuilder: (_, i) {
            final d = i - offset + 1;
            if (d < 1 || d > count) return const SizedBox.shrink();
            final date = DateTime(first.year, first.month, d);
            final selected = sameDay(date, selectedDate);
            final today = sameDay(date, DateTime.now());
            final has = marks.contains(d);
            final radius = BorderRadius.circular(MemoRadius.md);
            return Ink(
              decoration: BoxDecoration(
                color: selected ? context.colors.brand500 : Colors.transparent,
                borderRadius: radius,
              ),
              child: InkWell(
                onTap: () { HapticFeedback.selectionClick(); setState(() => selectedDate = date); },
                borderRadius: radius,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('$d', style: TextStyle(
                      color: selected ? Colors.white : today ? context.colors.brand700 : context.colors.ink,
                      fontWeight: selected || today ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 14, fontFeatures: MemoText.tabular)),
                    const SizedBox(height: 3),
                    Container(width: 4, height: 4, decoration: BoxDecoration(shape: BoxShape.circle,
                      color: has ? selected ? Colors.white : context.colors.brand500 : Colors.transparent)),
                  ],
                ),
              ),
            );
          })),
      ]))),
      section('${selectedDate.month}月${selectedDate.day}日', '${list.length} 个提醒'),
      if (list.isEmpty) MemoEmptyState(icon: Icons.event_available_rounded,
        title: '这一天还没有提醒', subtitle: '点击 + 添加一件值得记住的事',
        actionLabel: '新建提醒', onAction: () => edit()),
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
      unawaited(voice.pause(keepDraft: false).catchError((Object e) { toast(niceError(e), error: true); }));
    }
    String? action;
    try {
      action = await showModalBottomSheet<String>(context: context, isScrollControlled: true,
        useSafeArea: true, backgroundColor: Colors.transparent, barrierColor: context.colors.ink.withValues(alpha: .20),
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
      'speechVariation' => '声音 ${d['speechNoiseScale'] ?? .6} · 节奏 ${d['speechNoiseScaleW'] ?? .668}',
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
        } catch (e) { toast(niceError(e), error: true); }
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
          catch (e) { await reload(); toast(niceError(e), error: true); return; }
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
      ListTile(key: settingKey('本机离线'), leading:  Icon(Icons.shield_outlined, color: context.colors.brand500), title: const Text('本机离线'),
        subtitle: const Text('录音只在本机识别'), trailing: const MemoTag('已内置')),
    ]),
    settingsHint('无需联网。首次准备或从后台返回时，可能需要稍候。'),
    Padding(padding: const EdgeInsets.fromLTRB(20, 24, 20, 4), child: FilledButton.tonalIcon(key: settingKey('试用免手输入'),
      onPressed: () => _settingsAction(sheetContext, 'voice'),
      style: FilledButton.styleFrom(backgroundColor: context.colors.brand100, foregroundColor: context.colors.brand500),
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
        leading:  Icon(Icons.graphic_eq, color: context.colors.brand500), title: const Text('语音准备状态'), subtitle: Text(value))),
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
          catch (e) { await reload(); toast(niceError(e), error: true); }
        }),
      ListTile(leading:  Icon(Icons.shield_outlined, color: context.colors.brand500), key: settingKey('提醒服务状态'), title: const Text('提醒服务状态'),
        subtitle: Text(store.status['reliableMode'] == false ? '可靠模式已关闭，仍保留系统闹钟'
          : store.status['guardianRunning'] == true ? '正在维护待触发提醒'
          : ((store.status['pending'] as Map?)?['count'] as int? ?? 0) == 0 ? '没有待触发任务，无需常驻运行'
          : '尚未检测到运行，请检查下方系统提示')),
      if ((store.status['guardianError'] as String? ?? '').isNotEmpty) Padding(padding: const EdgeInsets.all(16),
        child: Text(store.status['guardianError'] as String, style:  TextStyle(color: context.colors.muted, fontSize: 12))),
    ]),
    section('隐私与提醒权限', ''),
    settingsGroup([
      ListTile(leading:  Icon(Icons.notifications_none, color: context.colors.brand500), key: settingKey('通知权限'), title: const Text('通知权限'),
        subtitle: Text(store.status['notifications'] == true ? '已开启' : '未开启，请在提醒自检中授权')),
      ListTile(key: settingKey('锁屏内容保护'), leading:  Icon(Icons.lock_outline, color: context.colors.brand500), title: const Text('锁屏内容保护'),
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
        leading:  Icon(Icons.inventory_2_outlined, color: context.colors.brand500), trailing: const Icon(Icons.chevron_right), onTap: () => _settingsAction(sheetContext, 'history')),
      SwitchListTile(key: settingKey('划掉通知后询问整理方式'), title: const Text('划掉通知后询问整理方式'),
        subtitle: const Text('划掉通知先结束本轮，再询问保留或删除；不选择时保留记录与循环，自检自动清理时不再询问'),
        value: store.status['cleanupPrompts'] as bool? ?? true, onChanged: (v) async {
          try { await native.invokeMethod('cleanupPrompts', v); await reload(); toast('整理方式设置已保存'); } catch (e) { toast(niceError(e), error: true); }
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
          try { await native.invokeMethod('testAutoDelete', v); await reload(); toast('测试提醒清理设置已保存'); } catch (e) { toast(niceError(e), error: true); }
        }),
      settingRow(Icons.notifications_active_outlined, '15秒后发送测试提醒', '使用当前默认样式；语音未就绪时使用备用提醒', () async {
        final allowed = await native.invokeMethod<bool>('requestNotifications');
        if (allowed == false) { toast('请先开启通知权限后再测试'); return; }
        await native.invokeMethod('testReminder');
        toast('测试提醒已设置，请返回桌面等待15秒');
        await reload();
      }),
      ListTile(key: settingKey('系统闹钟排程'), leading:  Icon(Icons.alarm_on, color: context.colors.brand500), title: const Text('系统闹钟排程'),
        subtitle: Text(store.status['exact'] == true ? '精确定时已可用，状态栏可能显示下一闹钟' : '尚未允许精确定时，提醒不会静默降级')),
      ListTile(key: settingKey('最近实际触发'), leading:  Icon(Icons.schedule, color: context.colors.brand500), title: const Text('最近实际触发'),
        subtitle: Text(eventTime(store.status['lastReceived']))),
      ListTile(key: settingKey('最近恢复排程'), leading:  Icon(Icons.restart_alt, color: context.colors.brand500), title: const Text('最近恢复排程'),
        subtitle: Text(eventTime(store.status['lastRestored']))),
      settingRow(Icons.bug_report_outlined, '导出提醒诊断', '包含排程、启动前快照与进程退出原因；不含备忘正文', () async {
        final ok = await native.invokeMethod<bool>('exportDiagnostics');
        if (ok == true) { toast('诊断已导出，可用于排查后台提醒问题'); }
      }),
      notificationStylesList(),
      ListTile(key: settingKey('固定发布签名'), leading:  Icon(Icons.security, color: context.colors.brand500), title: const Text('固定发布签名'),
        subtitle: const Text('同一固定签名的版本可覆盖更新，数据保存在本机')),
    ]),
    section('使用提示', ''), Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: MemoCard(child:  Text(
      '• 手动划掉系统通知或点击已读后结束本轮重提醒；App 中结束并保留会停用后续提醒。点开通知、横幅自动收起不算已读。\n\n'
      '• 达到总次数后停止再次提醒，但仍保留未读状态。下一次每日／每周提醒重新计数。\n\n'
      '• 荣耀手机请检查应用启动管理，允许自启动与后台运行。系统休眠、勿扰模式、强行停止会影响提醒和亮屏。\n\n'
      '• 提醒使用系统闹钟排程；从最近任务划掉不需要重新打开 App。系统强行停止会阻止提醒，需要手动再打开。\n\n'
      '• 横幅和锁屏通知最终受系统通道设置控制。请用提醒自检测试，并检查允许横幅、锁屏通知和勿扰设置。',
      style: TextStyle(color: context.colors.muted, fontSize: 13, height: 1.7)))),
    if ((store.status['lastError'] as String? ?? '').isNotEmpty) Padding(padding: const EdgeInsets.all(24),
      child: Text('最近的系统提示：${store.status['lastError']}', style:  TextStyle(color: context.colors.muted, fontSize: 12))),
    ],
  };
  Widget defaultSpeechOptions() {
    final config = Reminder(
      speechMode: store.defaults['speechMode'] as String? ?? 'off',
      speechVoice: store.defaults['speechVoice'] as String? ?? '228',
      speechRate: (store.defaults['speechRate'] as num?)?.toDouble() ?? 1.0,
      speechNoiseScale: (store.defaults['speechNoiseScale'] as num?)?.toDouble() ?? .6,
      speechNoiseScaleW: (store.defaults['speechNoiseScaleW'] as num?)?.toDouble() ?? .668,
      speechHideLocked: store.defaults['speechHideLocked'] as bool? ?? true,
      speechRepeat: store.defaults['speechRepeat'] as bool? ?? true,
      speechRandom: store.defaults['speechRandom'] as bool? ?? false,
      speechRandomLanguage: store.defaults['speechRandomLanguage'] as String? ?? 'all',
      speechRandomGender: store.defaults['speechRandomGender'] as String? ?? 'all',
      speechRandomGroup: store.defaults['speechRandomGroup'] as String? ?? '');
    return SpeechOptions(groups: store.voiceGroups, defaultSettings: true, reminder: config, defaults: store.defaults, onChanged: () async {
      store.defaults.addAll({'speechMode': config.speechMode, 'speechVoice': config.speechVoice,
        'speechNoiseScale': config.speechNoiseScale, 'speechNoiseScaleW': config.speechNoiseScaleW,
        'speechRate': config.speechRate, 'speechHideLocked': config.speechHideLocked, 'speechRepeat': config.speechRepeat,
        'speechRandom': config.speechRandom, 'speechRandomLanguage': config.speechRandomLanguage, 'speechRandomGender': config.speechRandomGender, 'speechRandomGroup': config.speechRandomGroup});
      await persistDefaults();
    });
  }
  Future<void> persistDefaults() async {
    try { await store.saveDefaults(); await reload(); toast('设置已保存'); }
    catch (e) { await reload(); toast(niceError(e), error: true); }
  }
  Widget notificationStylesList() {
    final styles = (store.status['notificationStyles'] as List? ?? [])
      .map((v) => Map<String, dynamic>.from(v as Map)).toList()
      ..sort((a, b) => (b['isDefault'] == true ? 1 : 0).compareTo(a['isDefault'] == true ? 1 : 0));
    final hidden = store.status['hiddenChannelCount'] as int? ?? 0;
    return ExpansionTile(key: settingKey('通知样式') ?? const PageStorageKey('notification-styles'),
      leading:  Icon(Icons.tune_rounded, color: context.colors.brand500),
      title: Text('通知样式（${styles.length}种）'), subtitle: const Text('按展示、振动和铃声分组'),
      children: [
         Padding(padding: EdgeInsets.fromLTRB(18, 0, 18, 8),
          child: Text('同一样式共用系统设置，修改会影响关联的所有备忘。', style: TextStyle(color: context.colors.muted, fontSize: 12))),
        ...styles.map((style) => settingRow(Icons.notifications_outlined, style['name'] as String? ?? '通知样式',
          '${style['isDefault'] == true ? '新建默认 · ' : ''}关联 ${style['count'] ?? 0} 条备忘\n'
          '${style['systemOverridden'] == true ? '系统设置与应用偏好不同' : channelImportanceLabel(style['importance'] as int? ?? 0)}'
          '${style['actualVibration'] is String ? '\n${style['actualVibration']}' : ''}'
          '${style['vibrationMismatch'] == true ? '\n振动节奏有差异，请打开本组系统设置检查' : ''}',
          () => native.invokeMethod('channelSettings', style['id']))),
        if (hidden > 0) Padding(padding: const EdgeInsets.all(16), child: Text(
          '已隐藏 $hidden 个无引用的历史通道，手机系统中的原设置仍保留。',
          style:  TextStyle(color: context.colors.muted, fontSize: 12))),
      ]);
  }
  Widget settingsGroup(List<Widget> children) => Padding(padding: const EdgeInsets.symmetric(horizontal: 20),
    child: MemoCard(shadow: false, padding: const EdgeInsets.symmetric(vertical: 4), child: Column(children: children)));
  Widget settingsHint(String text) => MemoHint(text, padding: const EdgeInsets.fromLTRB(24, 10, 24, 0));
  Widget settingRow(IconData icon, String title, String value, Future<void> Function() action) => SettingsActionTile(
    key: settingKey(title), icon: icon, title: title, value: value, highlighted: title == _settingsTargetTitle,
    action: () async {
      try { await action(); } catch (e) { toast(niceError(e), error: true); }
    });
}

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
        trailing: e.key == current ?  Icon(Icons.check_rounded, color: context.colors.brand500) : null,
        onTap: () => Navigator.pop(c, e.key))),
    ])));

class NotificationDisplayOptions extends StatelessWidget {
  final String presentation, lockscreen;
  final bool defaultSettings;
  final ValueChanged<String> onPresentationChanged, onLockscreenChanged;
  const NotificationDisplayOptions({super.key, required this.presentation, required this.lockscreen,
    required this.onPresentationChanged, required this.onLockscreenChanged, this.defaultSettings = false});
  @override Widget build(BuildContext context) => Column(children: [
    ListTile(leading:  Icon(Icons.view_agenda_outlined, color: context.colors.brand500),
      title: Text(defaultSettings ? '默认展示方式' : '展示方式'),
      subtitle: Text(presentations[presentation] ?? presentations['banner']!), trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final v = await chooseNotificationOption(context, '通知展示方式', presentations, presentation);
        if (v != null && context.mounted) { onPresentationChanged(v); }
      }),
    ListTile(leading:  Icon(Icons.lock_outline, color: context.colors.brand500),
      title: Text(defaultSettings ? '默认锁屏显示' : '锁屏显示'),
      subtitle: Text(lockscreens[lockscreen] ?? lockscreens['private']!), trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final v = await chooseNotificationOption(context, '锁屏显示方式', lockscreens, lockscreen);
        if (v != null && context.mounted) { onLockscreenChanged(v); }
      }),
     Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Text('实际显示受系统设置控制。隐藏正文时，请同时在系统通知设置中关闭“显示敏感内容”；解锁后由系统显示正文。', style: TextStyle(color: context.colors.muted, fontSize: 12))),
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
  bool busy = false;
  Future<void> _ack() async {
    if (busy) return;
    setState(() => busy = true);
    try { await widget.onAck(); } catch (e) {
      if (mounted) {
        setState(() => busy = false);
        ScaffoldMessenger.of(context).showSnackBar(memoSnackBar(niceError(e), error: true));
      }
    }
  }
  @override Widget build(BuildContext context) {
    final r = widget.reminder;
    return SafeArea(child: SingleChildScrollView(padding: EdgeInsets.fromLTRB(24, 0, 24, 28 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: MemoSpace.sm),
        Text(r.time, style:  TextStyle(fontSize: 42, height: 1.1, fontWeight: FontWeight.w700,
          color: context.colors.brand500, fontFeatures: MemoText.tabular)),
        const SizedBox(height: 2),
        Text('${dateLabel(r.displayDate)} · ${r.repeatLabel}', style: context.text.body.copyWith(color: context.colors.muted)),
        const SizedBox(height: MemoSpace.xl),
        ConstrainedBox(constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.35),
          child: SingleChildScrollView(child: Text(r.text, style: context.text.title.copyWith(height: 1.45)))),
        const SizedBox(height: MemoSpace.xl),
        if (r.unread) ...[
          Text('已提醒 ${r.attempts}/${r.totalCount} 次', style: context.text.caption),
          const SizedBox(height: MemoSpace.sm),
          MemoSlideToConfirm(
            label: '向右滑动，确认已读',
            icon: Icons.done_all_rounded,
            enabled: !busy,
            onConfirm: _ack,
          ),
        ] else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: context.colors.brand50, borderRadius: BorderRadius.circular(MemoRadius.md)),
            child: Row(children: [
               Icon(Icons.notifications_none_rounded, size: 18, color: context.colors.brand700),
              const SizedBox(width: MemoSpace.sm),
              Expanded(child: Text('到时会通过系统通知提醒你', style: context.text.label)),
            ]),
          ),
        const SizedBox(height: MemoSpace.xl),
        ReminderAudioPanel(key: ValueKey('audio-${r.id}'), reminder: r),
        const SizedBox(height: MemoSpace.lg),
        OutlinedButton(onPressed: busy ? null : widget.onEdit,
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: const Text('编辑提醒')),
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
    if (error != null) { ScaffoldMessenger.of(context).showSnackBar(memoSnackBar(error, error: true)); return; }
    setState(() => saving = true);
    try {
      await native.invokeMethod('requestNotifications');
      if (r.repeat == 'none' && !r.date.isAfter(DateTime.now())) { throw StateError('确认期间时间已到，请重新选择时间或明确重新计时'); }
      await widget.store.save(r);
      HapticFeedback.lightImpact();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) { setState(() => saving = false); ScaffoldMessenger.of(context).showSnackBar(memoSnackBar(niceError(e), error: true)); }
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
        MemoCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(!r.dateConfirmed ? '日期无效，请手动选择日期' : !r.timeConfirmed ? '请手动选择有效时间' : r.repeat == 'none' && !r.date.isAfter(DateTime.now()) ? '目标时间已过期，请修改或明确重新计时' : '请确认识别出的时间和内容', style:  TextStyle(color: context.colors.danger)),
          if (widget.voice!.settings.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(widget.voice!.settings.join(' · '))),
          if (widget.voice!.relativeDelay != null) ...[
            Text(manualTime ? '已手动修改，按下方日期和时间提醒' : '以 ${countdownReference!.hour}:${countdownReference!.minute.toString().padLeft(2, '0')}:${countdownReference!.second.toString().padLeft(2, '0')} 为基准计时，目标为 ${r.date.year}年${r.date.month}月${r.date.day}日 ${r.preciseTime}'),
            TextButton(onPressed: () => setState(() { countdownReference = DateTime.fromMillisecondsSinceEpoch(DateTime.now().millisecondsSinceEpoch); r.date = countdownReference!.add(widget.voice!.relativeDelay!); r.dateConfirmed = true; r.timeConfirmed = true; manualTime = false; }), child: const Text('从现在起重新计时')),
          ],
        ])), const SizedBox(height: 14),
      ],
      MemoCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('提醒内容', style: TextStyle(fontWeight: FontWeight.w600)), const SizedBox(height: 12),
        TextField(controller: text, minLines: 2, maxLines: 5, maxLength: 2000,
          decoration: const InputDecoration(hintText: '写下一件重要的事…')),
      ])), const SizedBox(height: 14),
      MemoCard(padding: const EdgeInsets.symmetric(vertical: 5), child: Column(children: [
        ListTile(leading:  Icon(Icons.calendar_today_outlined, color: context.colors.brand500), title: const Text('日期'),
          trailing: Text(r.dateConfirmed ? '${r.date.year}年${r.date.month}月${r.date.day}日' : '请选择有效日期'), onTap: pickDate),
        ListTile(leading:  Icon(Icons.schedule_rounded, color: context.colors.brand500), title: const Text('时间'), trailing: Text(r.timeConfirmed ? r.preciseTime : '请选择时间'), onTap: pickTime),
      ])), const SizedBox(height: 14),
      MemoCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('重复', style: TextStyle(fontWeight: FontWeight.w600)), const SizedBox(height: 14),
        SizedBox(width: double.infinity, child: SegmentedButton<String>(showSelectedIcon: false,
          segments: const [ButtonSegment(value: 'none', label: Text('仅一次')), ButtonSegment(value: 'daily', label: Text('每天')), ButtonSegment(value: 'weekly', label: Text('每周'))],
          selected: {r.repeat}, onSelectionChanged: (v) => setState(() { r.repeat = v.first; if (r.repeat == 'weekly' && r.days.isEmpty) r.days = [r.date.weekday]; }))),
        if (r.repeat == 'weekly') ...[const SizedBox(height: 16), Wrap(spacing: 8, runSpacing: 8, children: List.generate(7, (i) => FilterChip(
          label: Text(weekdays[i]), selected: r.days.contains(i + 1), onSelected: (v) => setState(() { if (v) { r.days.add(i + 1); } else { r.days.remove(i + 1); } }))))],
      ])), const SizedBox(height: 14),
      MemoCard(padding: const EdgeInsets.symmetric(vertical: 5), child: Column(children: [
        const ListTile(title: Text('提醒方式', style: TextStyle(fontWeight: FontWeight.w700))),
        NotificationDisplayOptions(presentation: r.presentation, lockscreen: r.lockscreen,
          onPresentationChanged: (v) => setState(() => r.presentation = v),
          onLockscreenChanged: (v) => setState(() => r.lockscreen = v)),
        ListTile(leading:  Icon(Icons.tune_rounded, color: context.colors.brand500), title: const Text('这条提醒的系统通知设置'),
          subtitle: const Text('请选择允许横幅／悬浮通知；相同样式共用系统设置。亮屏卡片增强可在设置开启'), trailing: const Icon(Icons.open_in_new_rounded),
          onTap: () async {
            try { await widget.store.openNotificationSettings(r); }
            catch (e) { if (context.mounted) { ScaffoldMessenger.of(context).showSnackBar(memoSnackBar(niceError(e), error: true)); } }
          }),
        SwitchListTile(title: const Text('尝试亮屏'), subtitle: const Text('保持锁屏，遵循手机系统限制'), value: r.wakeScreen, onChanged: (v) => setState(() => r.wakeScreen = v)),
        ListTile(leading:  Icon(Icons.vibration, color: context.colors.brand500), title: const Text('振动'), subtitle: Text(vibrationLabel(r.vibration)),
          trailing: const Icon(Icons.chevron_right), onTap: () async {
            final v = await chooseVibration(context, r.vibration); if (v != null && mounted) setState(() => r.vibration = v);
          }),
        SwitchListTile(title: const Text('铃声'), value: r.sound, onChanged: (v) => setState(() => r.sound = v)),
        if (r.sound) ListTile(leading:  Icon(Icons.music_note_outlined, color: context.colors.brand500), title: const Text('从系统选择铃声'),
          subtitle: Text(r.ringtone.isEmpty ? '系统默认' : '已选择系统铃声'), trailing: const Icon(Icons.chevron_right), onTap: () async {
            try { final v = await native.invokeMethod<String>('pickRingtone', r.ringtone); if (v != null && mounted) setState(() => r.ringtone = v); }
            catch (e) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(memoSnackBar(niceError(e), error: true)); }
          }),
      ])), const SizedBox(height: 14),
      MemoCard(padding: const EdgeInsets.symmetric(vertical: 5), child: Column(children: [
        const ListTile(title: Text('语音播报', style: TextStyle(fontWeight: FontWeight.w700))),
        SpeechOptions(groups: widget.store.voiceGroups, reminder: r, defaults: widget.store.defaults, onChanged: () async { if (mounted) setState(() {}); }),
      ])), const SizedBox(height: 14),
      MemoCard(padding: const EdgeInsets.symmetric(vertical: 5), child: Column(children: [
        const ListTile(title: Text('未读再次提醒', style: TextStyle(fontWeight: FontWeight.w700)), subtitle: Text('手动划掉通知或滑动确认后停止')),
        ListTile(leading:  Icon(Icons.timer_outlined, color: context.colors.brand500), title: const Text('时间间隔'), trailing: Text('${r.intervalMinutes} 分钟'), onTap: () async {
          final n = await numberDialog(context, '再次提醒间隔（分钟）', r.intervalMinutes, 1, 1440);
          if (n != null && mounted) setState(() => r.intervalMinutes = n);
        }),
        ListTile(leading:  Icon(Icons.repeat_rounded, color: context.colors.brand500), title: const Text('总次数（含首次）'), trailing: Text('${r.totalCount} 次'), onTap: () async {
          final n = await numberDialog(context, '提醒总次数（包含第一次）', r.totalCount, 1, 20);
          if (n != null && mounted) setState(() => r.totalCount = n);
        }),
      ])), const SizedBox(height: 24),
      FilledButton(onPressed: saving ? null : save, child: Text(saving ? '正在保存…' : '保存提醒')),
      const SizedBox(height: 14),  Text('到达次数上限后仍保留未读状态。编辑会重新安排这条提醒。', textAlign: TextAlign.center, style: TextStyle(color: context.colors.muted, fontSize: 12)),
    ]),
  );
}


bool calendarOccursOn(Reminder r, DateTime date) => r.completed || r.archived ? sameDay(historyCalendarDate(r), date) : occursOn(r, date);

DateTime historyCalendarDate(Reminder r) => r.historyScheduledAt > 0 ? DateTime.fromMillisecondsSinceEpoch(r.historyScheduledAt) : r.activeOccurrence > 0 ? DateTime.fromMillisecondsSinceEpoch(r.activeOccurrence) : r.date;

/// Pinned day header. It is opaque on purpose: a translucent header would let
/// cards scroll through it, and `context.colors.canvas` matches the page behind.
class _GroupHeader extends SliverPersistentHeaderDelegate {
  final String label;
  final int count;
  const _GroupHeader(this.label, this.count);

  @override double get minExtent => 44;
  @override double get maxExtent => 44;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => Container(
    height: 44, color: context.colors.canvas,
    padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
    alignment: Alignment.bottomLeft,
    child: Row(children: [
      Text(label, style: context.text.caption.copyWith(fontWeight: FontWeight.w700, color: context.colors.ink, letterSpacing: .4)),
      const SizedBox(width: 8),
      Text('$count', style: context.text.caption.copyWith(color: context.colors.muted)),
    ]));

  @override bool shouldRebuild(_GroupHeader old) => old.label != label || old.count != count;
}
