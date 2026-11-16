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

class BriefingSchedule {
  const BriefingSchedule._(this.morning, this.midday, this.evening);

  factory BriefingSchedule({
    required int morning,
    required int midday,
    required int evening,
  }) {
    final times = {morning, midday, evening};
    if (times.length != 3 ||
        times.any((minute) => minute < 0 || minute >= 1440)) {
      throw const FormatException('Choose three different briefing times.');
    }
    return BriefingSchedule._(morning, midday, evening);
  }

  static const defaults = BriefingSchedule._(7 * 60, 12 * 60, 18 * 60);

  final int morning;
  final int midday;
  final int evening;

  int minuteFor(BriefingPeriod period) => switch (period) {
    BriefingPeriod.morning => morning,
    BriefingPeriod.midday => midday,
    BriefingPeriod.evening => evening,
  };

  String get key => '$morning-$midday-$evening';

  Map<String, int> toJson() => {
    for (final period in BriefingPeriod.values) period.name: minuteFor(period),
  };

  factory BriefingSchedule.fromJson(Map<String, dynamic> json) {
    if (json['morning'] is! int ||
        json['midday'] is! int ||
        json['evening'] is! int) {
      throw const FormatException('Choose a valid time for each briefing.');
    }
    return BriefingSchedule(
      morning: json['morning'] as int,
      midday: json['midday'] as int,
      evening: json['evening'] as int,
    );
  }
}

class BriefingSlot {
  const BriefingSlot(this.start, this.period);

  final DateTime start;
  final BriefingPeriod period;

  String get id {
    final dateAndPeriod = '${dayKey(start)}-${period.name}';
    final minute = start.hour * 60 + start.minute;
    return minute == BriefingSchedule.defaults.minuteFor(period)
        ? dateAndPeriod
        : '$dateAndPeriod-$minute';
  }

  static BriefingSlot? current(
    DateTime now, {
    BriefingSchedule schedule = BriefingSchedule.defaults,
  }) {
    for (final slot in _onDate(now, schedule).reversed) {
      if (!slot.start.isAfter(now)) return slot;
    }
    return null;
  }

  static BriefingSlot next(
    DateTime now, {
    BriefingSchedule schedule = BriefingSchedule.defaults,
  }) {
    for (final slot in _onDate(now, schedule)) {
      if (slot.start.isAfter(now)) return slot;
    }
    return _onDate(DateTime(now.year, now.month, now.day + 1), schedule).first;
  }

  static List<BriefingSlot> _onDate(DateTime day, BriefingSchedule schedule) =>
      [
        for (final period in BriefingPeriod.values)
          BriefingSlot(
            DateTime(
              day.year,
              day.month,
              day.day,
              0,
              schedule.minuteFor(period),
            ),
            period,
          ),
      ]..sort((a, b) {
        final time = a.start.compareTo(b.start);
        return time == 0 ? a.period.index.compareTo(b.period.index) : time;
      });
}

abstract interface class BriefingStore {
  Future<String?> read(BriefingSlot slot, String input);
  Future<void> save(BriefingSlot slot, String input, String summary);
  Future<String> readFocus();
  Future<void> saveFocus(String focus);
  Future<BriefingSchedule> readSchedule();
  Future<void> saveSchedule(BriefingSchedule schedule);
}

class BriefingService {
  const BriefingService({required this.store, required this.assistant});

  final BriefingStore store;
  final PlannerAssistant assistant;

  Future<String?> refresh(
    DateTime now,
    List<PlannerTask> tasks, {
    BriefingSchedule? schedule,
  }) async {
    final slot = BriefingSlot.current(
      now,
      schedule: schedule ?? await store.readSchedule(),
    );
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
