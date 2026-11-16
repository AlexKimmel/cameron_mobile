import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:planner/planner.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalHealthBriefing implements BriefingHealth {
  LocalHealthBriefing({Health? health}) : _health = health ?? Health();

  static bool get supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static const _enabledKey = 'planner.healthBriefing.enabled';
  static const _sleepTypes = [
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_REM,
  ];
  static const _types = [
    HealthDataType.STEPS,
    ..._sleepTypes,
    HealthDataType.WORKOUT,
  ];

  final Health _health;
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  Future<void>? _configuration;

  Future<void> _configure() => _configuration ??= _health.configure();

  @override
  Future<bool> isEnabled() async =>
      await _preferences.getBool(_enabledKey) ?? false;

  @override
  Future<bool> requestAccess() async {
    await _configure();
    if (!kIsWeb && Platform.isAndroid) {
      final activityRecognition = await Permission.activityRecognition
          .request();
      if (!activityRecognition.isGranted) return false;
    }

    final allowed = await _health.requestAuthorization(
      _types,
      permissions: List.filled(_types.length, HealthDataAccess.READ),
    );
    if (allowed && !kIsWeb && Platform.isAndroid) {
      try {
        await _health.requestHealthDataInBackgroundAuthorization();
      } catch (_) {
        // Scheduled briefings can fall back to planner data alone.
      }
    }
    if (allowed) await _preferences.setBool(_enabledKey, true);
    return allowed;
  }

  @override
  Future<void> disable() => _preferences.setBool(_enabledKey, false);

  @override
  Future<String?> readContext(DateTime now) async {
    if (!await isEnabled()) return null;
    try {
      await _configure();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final sleepStart = now.subtract(const Duration(hours: 24));
      final points = _health.removeDuplicates(
        await _health.getHealthDataFromTypes(
          types: [..._sleepTypes, HealthDataType.WORKOUT],
          startTime: sleepStart,
          endTime: now,
        ),
      );
      final steps = await _health.getTotalStepsInInterval(startOfDay, now);
      final sleepMinutes = _sleepMinutes(points, sleepStart, now);
      final workouts = points
          .where((point) => point.type == HealthDataType.WORKOUT)
          .length;
      final details = <String>[
        if (steps != null) '$steps steps today',
        if (sleepMinutes > 0)
          '${_duration(sleepMinutes)} recorded sleep in the past 24 hours',
        if (workouts > 0)
          '$workouts recorded ${workouts == 1 ? 'workout' : 'workouts'} in the past 24 hours',
      ];
      return details.isEmpty ? null : details.join('; ');
    } catch (_) {
      // Health data can be unavailable while the device is locked or access
      // has been removed in the platform Health app. Briefings still work.
      return null;
    }
  }

  static int _sleepMinutes(
    List<HealthDataPoint> points,
    DateTime start,
    DateTime end,
  ) {
    final intervals =
        points
            .where((point) => _sleepTypes.contains(point.type))
            .map(
              (point) => (
                point.dateFrom.isBefore(start) ? start : point.dateFrom,
                point.dateTo.isAfter(end) ? end : point.dateTo,
              ),
            )
            .where((interval) => interval.$2.isAfter(interval.$1))
            .toList()
          ..sort((a, b) => a.$1.compareTo(b.$1));

    var total = Duration.zero;
    DateTime? intervalStart;
    DateTime? intervalEnd;
    for (final interval in intervals) {
      if (intervalStart == null || interval.$1.isAfter(intervalEnd!)) {
        if (intervalStart != null) {
          total += intervalEnd!.difference(intervalStart);
        }
        intervalStart = interval.$1;
        intervalEnd = interval.$2;
      } else if (interval.$2.isAfter(intervalEnd)) {
        intervalEnd = interval.$2;
      }
    }
    if (intervalStart != null) {
      total += intervalEnd!.difference(intervalStart);
    }
    return total.inMinutes;
  }

  static String _duration(int minutes) {
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    return hours == 0 ? '${remainder}m' : '${hours}h ${remainder}m';
  }
}
