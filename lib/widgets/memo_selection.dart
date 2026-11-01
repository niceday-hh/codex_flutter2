import 'package:flutter/widgets.dart';

/// Batch selection, one instance per page.
///
/// It used to be a plain `Set<int>` field on the home screen, which meant the
/// history page — a separate route that reuses the same row builder — toggled
/// ids on the home state without ever rebuilding itself: long-pressing a row
/// changed nothing on screen, and the action bar only appeared after backing
/// out to the home tab. A notifier gives each page its own set and its own
/// rebuild signal, while the row builder stays one piece of code.
class MemoSelection extends ChangeNotifier {
  final Set<int> _ids = <int>{};

  Set<int> get ids => Set<int>.unmodifiable(_ids);
  bool get active => _ids.isNotEmpty;
  int get length => _ids.length;
  bool contains(int id) => _ids.contains(id);

  void toggle(int id) {
    if (!_ids.remove(id)) _ids.add(id);
    notifyListeners();
  }

  /// Drop ids that are no longer in the list (deleted, archived, or filtered
  /// out by a search) so the bar cannot claim a row that is gone.
  void retain(Iterable<int> keep) {
    final live = keep.toSet();
    final before = _ids.length;
    _ids.removeWhere((id) => !live.contains(id));
    if (_ids.length != before) notifyListeners();
  }

  void removeAll(Iterable<int> gone) {
    final drop = gone.toSet();
    final before = _ids.length;
    _ids.removeWhere(drop.contains);
    if (_ids.length != before) notifyListeners();
  }

  /// Select-all / select-none for the visible rows.
  void setAll(Iterable<int> ids) {
    final next = ids.toSet();
    if (next.length == _ids.length && next.containsAll(_ids)) return;
    _ids
      ..clear()
      ..addAll(next);
    notifyListeners();
  }

  void clear() {
    if (_ids.isEmpty) return;
    _ids.clear();
    notifyListeners();
  }
}
