enum RepeatFrequency { daily, weekly, monthly }

class RepeatRule {
  RepeatRule({
    required this.frequency,
    this.interval = 1,
    Set<int> weekdays = const {},
    this.until,
  }) : weekdays = Set.unmodifiable(weekdays) {
    if (interval < 1 || interval > 366) {
      throw const FormatException('Choose a repeat interval from 1 to 366.');
    }
    if (until != null) {
      final end = DateTime.tryParse('${until!}T00:00:00Z');
      if (end == null || end.toIso8601String().substring(0, 10) != until) {
        throw const FormatException('Choose a valid repeat end date.');
      }
    }
    if (weekdays.any((day) => day < 1 || day > 7) ||
        (frequency != RepeatFrequency.weekly && weekdays.isNotEmpty)) {
      throw const FormatException('Choose weekdays only for a weekly repeat.');
    }
  }

  final RepeatFrequency frequency;
  final int interval;
  final Set<int> weekdays;
  final String? until;

  /// All date arithmetic uses UTC midnights so a daylight-saving change
  /// cannot move a recurrence to the preceding or following local date.
  Iterable<DateTime> from(DateTime start, DateTime earliest) sync* {
    final anchor = DateTime.utc(start.year, start.month, start.day);
    final candidate = DateTime.utc(earliest.year, earliest.month, earliest.day);
    final floor = candidate.isBefore(anchor) ? anchor : candidate;
    final cutoff = until == null ? null : DateTime.parse('${until!}T00:00:00Z');
    bool withinEnd(DateTime date) => cutoff == null || !date.isAfter(cutoff);

    switch (frequency) {
      case RepeatFrequency.daily:
        final days = floor.difference(anchor).inDays;
        final offset = (days + interval - 1) ~/ interval * interval;
        for (
          var date = anchor.add(Duration(days: offset));
          withinEnd(date);
          date = date.add(Duration(days: interval))
        ) {
          yield date;
        }
      case RepeatFrequency.weekly:
        final anchorWeek = anchor.subtract(Duration(days: anchor.weekday - 1));
        final weekdays = this.weekdays.isEmpty
            ? [anchor.weekday]
            : (this.weekdays.toList()..sort());
        final week = floor.difference(anchorWeek).inDays ~/ 7;
        for (
          var first = anchorWeek.add(
            Duration(days: week ~/ interval * interval * 7),
          );
          withinEnd(first);
          first = first.add(Duration(days: interval * 7))
        ) {
          for (final weekday in weekdays) {
            final date = first.add(Duration(days: weekday - 1));
            if (!date.isBefore(floor) && withinEnd(date)) yield date;
          }
        }
      case RepeatFrequency.monthly:
        final elapsed =
            (floor.year - anchor.year) * 12 + floor.month - anchor.month;
        for (
          var offset = elapsed ~/ interval * interval;
          ;
          offset += interval
        ) {
          final month = DateTime.utc(anchor.year, anchor.month + offset);
          final last = DateTime.utc(month.year, month.month + 1, 0).day;
          final date = DateTime.utc(
            month.year,
            month.month,
            anchor.day.clamp(1, last),
          );
          if (!withinEnd(date)) return;
          if (!date.isBefore(floor)) yield date;
        }
    }
  }

  Map<String, Object?> toJson() => {
    'frequency': frequency.name,
    'interval': interval,
    if (weekdays.isNotEmpty) 'weekdays': weekdays.toList()..sort(),
    if (until != null) 'until': until,
  };

  factory RepeatRule.fromJson(Map<String, dynamic> json) => RepeatRule(
    frequency: RepeatFrequency.values.byName(json['frequency'] as String),
    interval: json['interval'] as int,
    weekdays: (json['weekdays'] as List?)?.cast<int>().toSet() ?? const {},
    until: json['until'] as String?,
  );
}

class TaskOccurrence {
  const TaskOccurrence({required this.seriesId, required this.originalDay});

  final String seriesId;
  final String originalDay;

  Map<String, Object?> toJson() => {
    'series': seriesId,
    'originalDay': originalDay,
  };

  factory TaskOccurrence.fromJson(Map<String, dynamic> json) => TaskOccurrence(
    seriesId: json['series'] as String,
    originalDay: json['originalDay'] as String,
  );
}
