import 'package:flutter_test/flutter_test.dart';
import 'package:planner/planner.dart';

void main() {
  test('Undo restores just the damaged records and preserves later edits', () {
    const first = PlannerTask(
      id: 'first',
      title: 'Original',
      day: '2026-11-15',
    );
    const deleted = PlannerTask(
      id: 'deleted',
      title: 'Deleted',
      day: '2026-11-15',
    );
    const other = PlannerTask(id: 'other', title: 'Other', day: '2026-11-17');
    const newTask = PlannerTask(id: 'new', title: 'Added', day: '2026-11-20');
    final renamed = first.copyWith(title: 'Renamed');
    final undo = TaskUndo.between(
      [first, deleted, other],
      [renamed, other, newTask],
    )!;

    final updated = other.copyWith(notes: 'Added after the original action');
    expect(undo.restore([renamed, updated, newTask]), [
      first,
      deleted,
      updated,
    ]);
    expect(
      undo.restore([renamed.copyWith(title: 'New edit'), updated, newTask]),
      isNull,
    );
    expect(TaskUndo.between([first], [first.copyWith()]), isNull);
  });
}
