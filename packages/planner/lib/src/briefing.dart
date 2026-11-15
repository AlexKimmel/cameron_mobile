import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'recurrence.dart';
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
  Future<String?> read(BriefingSlot slot, String input);
  Future<void> save(BriefingSlot slot, String input, String summary);
  Future<String> readFocus();
  Future<void> saveFocus(String focus);
}

class BriefingService {
  const BriefingService({required this.store, required this.assistant});

  final BriefingStore store;
  final PlannerAssistant assistant;

  Future<String?> refresh(DateTime now, List<PlannerTask> tasks) async {
    final slot = BriefingSlot.current(now);
    if (slot == null) return null;

    final today = dayKey(now);
    final tomorrow = dayKey(DateTime(now.year, now.month, now.day + 1));
    final relevant = expandTasks(tasks, now)
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

    final focus = (await store.readFocus()).trim();
    final input = sha256
        .convert(
          utf8.encode(
            jsonEncode([focus, for (final task in relevant) task.toJson()]),
          ),
        )
        .toString();
    final existing = await store.read(slot, input);
    if (existing != null) return existing;

    final reply = await assistant.ask(
      [
        slot.period.prompt,
        'Use at most two short sentences and no heading. Use only facts from the planner data.',
        if (focus.isNotEmpty)
          'Prioritize this briefing focus when relevant: ${jsonEncode(focus)}.',
      ].join(' '),
      tasks: relevant,
      now: now,
      readOnly: true,
    );
    final summary = reply.text.trim();
    if (summary.isEmpty) return null;
    await store.save(slot, input, summary);
    return summary;
  }
}
