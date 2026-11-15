import 'package:material_ui/material_ui.dart';
import 'package:planner/planner.dart';

import 'design.dart';

class BriefingScreen extends StatelessWidget {
  const BriefingScreen({
    super.key,
    required this.now,
    required this.tasks,
    required this.summary,
    required this.loading,
    this.onRetry,
    this.onEditFocus,
    required this.activities,
    required this.onEdit,
  });

  final DateTime now;
  final List<PlannerTask> tasks;
  final String? summary;
  final bool loading;
  final VoidCallback? onRetry;
  final VoidCallback? onEditFocus;
  final List<String> activities;
  final ValueChanged<PlannerTask> onEdit;

  @override
  Widget build(BuildContext context) {
    final today = dayKey(now);
    final active = tasks.where((task) => task.day == today && !task.done);
    final timed = active.where((task) => task.startMinute != null).toList()
      ..sort((a, b) => a.startMinute!.compareTo(b.startMinute!));
    final focus = active.fold(0, (total, task) => total + task.duration);
    final palette = context.palette;
    final period = BriefingSlot.current(now)?.period;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            Pill(
              MaterialLocalizations.of(context).formatFullDate(now),
              icon: Icons.today_outlined,
            ),
            if (onEditFocus != null)
              TextButton.icon(
                onPressed: onEditFocus,
                icon: const Icon(Icons.tune),
                label: const Text('Briefing focus'),
              ),
          ],
        ),
        if (loading)
          const LinearProgressIndicator(semanticsLabel: 'Updating briefing'),
        if (onRetry != null)
          TextButton(onPressed: onRetry, child: const Text('Retry briefing')),
        if (summary case final text?) ...[
          const SizedBox(height: 14),
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [
                  palette.primaryContainer,
                  palette.surface,
                  palette.tertiaryContainer,
                ],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.auto_awesome,
                        color: palette.primary,
                        size: 17,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          switch (period) {
                            BriefingPeriod.morning => 'Morning',
                            BriefingPeriod.midday => 'Midday',
                            BriefingPeriod.evening => 'Evening',
                            null => 'Briefing',
                          },
                          style: context.type.labelLarge!.copyWith(
                            color: palette.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(text, style: context.type.bodyLarge),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        SectionHeading(
          'Timeline',
          trailing: focus > 0
              ? Pill(
                  '${durationLabel(focus)} focus',
                  icon: Icons.timer_outlined,
                )
              : null,
        ),
        const SizedBox(height: 8),
        if (timed.isEmpty)
          Panel(
            radius: 20,
            child: Text(
              'No timed tasks',
              style: context.type.bodyMedium!.copyWith(
                color: palette.onSurfaceVariant,
              ),
            ),
          )
        else
          Stack(
            children: [
              Positioned(
                left: 13,
                top: 22,
                bottom: 34,
                width: 2,
                child: ColoredBox(color: palette.outlineVariant),
              ),
              Column(
                children: [
                  for (final task in timed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _TimelineEntry(
                        task: task,
                        onTap: () => onEdit(task),
                      ),
                    ),
                ],
              ),
            ],
          ),
        if (activities.isNotEmpty) ...[
          const SizedBox(height: 16),
          const SectionHeading('Recent actions'),
          const SizedBox(height: 8),
          for (final activity in activities.take(4))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Panel(
                radius: 18,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Icon(Icons.check, size: 18, color: palette.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(activity, style: context.type.bodyMedium),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _TimelineEntry extends StatelessWidget {
  const _TimelineEntry({required this.task, required this.onTap});

  final PlannerTask task;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final start = task.startMinute!;
    final end = start + task.duration;
    final high = task.priority == TaskPriority.high;
    final palette = context.palette;
    final color = high ? palette.primary : palette.secondary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: IconBadge(
            high ? Icons.flag_outlined : Icons.schedule,
            size: 28,
            color: color,
            foreground: palette.onPrimary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Panel(
            radius: 22,
            padding: EdgeInsets.zero,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          task.duration == 0
                              ? context.clock(start)
                              : '${context.clock(start)} – ${context.clock(end)}${end >= 1440 ? ' (+1 day)' : ''}',
                          style: context.type.labelSmall!.copyWith(
                            color: color,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      task.title,
                      style: context.type.titleSmall!.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (task.notes.isNotEmpty)
                      Text(
                        task.notes,
                        style: context.type.bodySmall!.copyWith(
                          color: palette.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
