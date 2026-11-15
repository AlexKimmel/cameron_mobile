import 'task.dart';

abstract interface class PlannerOnboarding {
  Future<bool> hasSeenWelcome();
  Future<void> markWelcomeSeen();
}

List<PlannerTask> samplePlannerDay(DateTime now) {
  final day = dayKey(now);
  return [
    PlannerTask(
      id: 'sample-$day-focus',
      title: 'Plan a focus session',
      day: day,
      notes: 'Pick one priority and set aside a short block of time.',
      startMinute: 10 * 60,
      duration: 30,
      priority: TaskPriority.high,
    ),
    PlannerTask(
      id: 'sample-$day-checklist',
      title: 'Get ready for tomorrow',
      day: day,
      steps: const [
        TaskStep('Review open tasks'),
        TaskStep('Choose one priority'),
      ],
    ),
    PlannerTask(
      id: 'sample-$day-break',
      title: 'Take a short break',
      day: day,
      startMinute: 14 * 60,
      duration: 15,
    ),
  ];
}
