import 'package:flutter/foundation.dart';

/// Identifies modal sheets coordinated from [MemoHome].
enum MemoSheetKind {
  detail,
  editor,
  settings,
  taskLibrary,
}

/// Centralizes modal sheet open/close tracking so [MemoHome] does not rely on
/// scattered boolean flags while still allowing intentional handoffs (such as
/// opening the editor while the detail sheet is dismissing).
class SheetCoordinator extends ChangeNotifier {
  final Set<MemoSheetKind> _open = <MemoSheetKind>{};

  bool get hasAnyOpen => _open.isNotEmpty;
  bool isOpen(MemoSheetKind kind) => _open.contains(kind);

  bool tryOpen(MemoSheetKind kind) {
    if (!_open.add(kind)) return false;
    notifyListeners();
    return true;
  }

  void close(MemoSheetKind kind) {
    if (!_open.remove(kind)) return;
    notifyListeners();
  }
}
