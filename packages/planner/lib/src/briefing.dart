import 'task.dart';
import 'tools.dart';

enum BriefingPeriod {
  morning(
    7,
    'Write the morning briefing. Name the first timed task and the most important open priority, if present.',
  ),
  midday(
    12,
    'Write the midday briefing. Note what was completed today and name the most important remaining task.',
  ),
  evening(
    18,
    'Write the evening briefing. Note what was completed today and what remains open. Mention the first task tomorrow if it is scheduled.',
  );

  const BriefingPeriod(this.hour, this.prompt);

  final int hour;
  final String prompt;
}

class BriefingSlot {
  const BriefingSlot(this.start, this.period);

  final DateTime start;
  final BriefingPeriod period;

  String get id => '${dayKey(start)}-${period.name}';

  static BriefingSlot? current(DateTime now) {
    for (final period in BriefingPeriod.values.reversed) {
      final start = _at(now, period);
      if (!start.isAfter(now)) return BriefingSlot(start, period);
    }
    return null;
  }

  static BriefingSlot next(DateTime now) {
    for (final period in BriefingPeriod.values) {
      final start = _at(now, period);
      if (start.isAfter(now)) return BriefingSlot(start, period);
    }
    final first = BriefingPeriod.values.first;
    return BriefingSlot(
      DateTime(now.year, now.month, now.day + 1, first.hour),
      first,
    );
  }

  static DateTime _at(DateTime day, BriefingPeriod period) =>
      DateTime(day.year, day.month, day.day, period.hour);
}

abstract interface class BriefingStore {
  Future<String?> read(BriefingSlot slot);
  Future<void> save(BriefingSlot slot, String summary);
}

class BriefingService {
  const BriefingService({required this.store, required this.assistant});

  final BriefingStore store;
  final PlannerAssistant assistant;

  Future<String?> refresh(DateTime now, List<PlannerTask> tasks) async {
    final slot = BriefingSlot.current(now);
    if (slot == null) return null;

    final existing = await store.read(slot);
    if (existing != null) return existing;

    final today = dayKey(now);
    final tomorrow = dayKey(DateTime(now.year, now.month, now.day + 1));
    final relevant = tasks
        .where(
          (task) =>
              task.day == today ||
              task.completedOn == today ||
              (slot.period == BriefingPeriod.evening &&
                  task.day == tomorrow &&
                  !task.done),
        )
        .toList();
    if (relevant.isEmpty) return null;

    final reply = await assistant.ask(
      '${slot.period.prompt} Use only the planner data. Use at most two short sentences and no heading.',
      tasks: relevant,
      now: now,
      readOnly: true,
    );
    final summary = reply.text.trim();
    if (summary.isEmpty) return null;
    await store.save(slot, summary);
    return summary;
  }
}
