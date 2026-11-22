import 'package:flutter_test/flutter_test.dart';
import 'package:timed_memo/sheet_coordinator.dart';

void main() {
  test('SheetCoordinator prevents duplicate opens and allows independent handoffs', () {
    final coordinator = SheetCoordinator();
    var notifications = 0;
    coordinator.addListener(() => notifications++);

    expect(coordinator.hasAnyOpen, isFalse);
    expect(coordinator.tryOpen(MemoSheetKind.detail), isTrue);
    expect(coordinator.tryOpen(MemoSheetKind.detail), isFalse);
    expect(coordinator.isOpen(MemoSheetKind.detail), isTrue);
    expect(coordinator.hasAnyOpen, isTrue);

    // Detail -> Editor handoff while detail is popping.
    expect(coordinator.tryOpen(MemoSheetKind.editor), isTrue);
    coordinator.close(MemoSheetKind.detail);
    expect(coordinator.isOpen(MemoSheetKind.detail), isFalse);
    expect(coordinator.isOpen(MemoSheetKind.editor), isTrue);
    expect(coordinator.hasAnyOpen, isTrue);

    coordinator.close(MemoSheetKind.editor);
    expect(coordinator.hasAnyOpen, isFalse);
    expect(notifications, 4);
    coordinator.dispose();
  });
}
