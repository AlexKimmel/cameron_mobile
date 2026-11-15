import 'package:material_ui/material_ui.dart';
import 'package:planner/planner.dart';

import 'design.dart';

enum TaskFilter {
  all('All tasks', Icons.list_alt),
  assistant('AI suggested', Icons.auto_awesome),
  tool('Tool actions', Icons.terminal);

  const TaskFilter(this.label, this.icon);

  final String label;
  final IconData icon;

  bool matches(PlannerTask task) => switch (this) {
    all => true,
    assistant => task.origin == TaskOrigin.assistant,
    tool => task.origin == TaskOrigin.tool,
  };
}

class TasksScreen extends StatelessWidget {
  const TasksScreen({
    super.key,
    required this.tasks,
    required this.today,
    required this.filter,
    required this.onFilterChanged,
    required this.canEdit,
    required this.onEdit,
    required this.onToggle,
    required this.onStepToggle,
  });

  final List<PlannerTask> tasks;
  final String today;
  final TaskFilter filter;
  final ValueChanged<TaskFilter> onFilterChanged;
  final bool canEdit;
  final ValueChanged<PlannerTask> onEdit;
  final ValueChanged<PlannerTask> onToggle;
  final void Function(PlannerTask, int) onStepToggle;

  @override
  Widget build(BuildContext context) {
    final matching = tasks.where(filter.matches).toList();
    final scheduled =
        matching.where((task) => !task.done && task.day == today).toList()
          ..sort(
            (a, b) => (a.startMinute ?? 1440).compareTo(b.startMinute ?? 1440),
          );
    final other =
        matching.where((task) => !task.done && task.day != today).toList()
          ..sort((a, b) => a.day.compareTo(b.day));
    final doneToday = matching
        .where((task) => task.completedOn == today)
        .toList();
    final doneEarlier = matching
        .where((task) => task.done && task.completedOn != today)
        .toList();
    final focus = scheduled.fold(0, (sum, task) => sum + task.duration);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final option in TaskFilter.values)
              ChoiceChip(
                avatar: Icon(option.icon, size: 16),
                label: Text(option.label),
                selected: filter == option,
                showCheckmark: false,
                onSelected: (_) => onFilterChanged(option),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (matching.isEmpty)
          Panel(
            child: Text(
              filter == TaskFilter.all ? 'No tasks yet' : 'No matching tasks',
              style: context.type.bodyMedium,
            ),
          )
        else ...[
          SectionHeading(
            'Today',
            trailing: focus > 0
                ? Pill(
                    '${durationLabel(focus)} focus',
                    icon: Icons.timer_outlined,
                  )
                : null,
          ),
          const SizedBox(height: 8),
          if (scheduled.isEmpty)
            Panel(
              child: Text('No tasks today', style: context.type.bodyMedium),
            ),
          for (final task in scheduled) _card(task),
          if (other.isNotEmpty) ...[
            const SizedBox(height: 16),
            const SectionHeading('Other days'),
            const SizedBox(height: 8),
            for (final task in other) _card(task, showDay: true),
          ],
          if (doneToday.isNotEmpty) _completed(context, 'Completed', doneToday),
          if (doneEarlier.isNotEmpty)
            _completed(context, 'Previously completed', doneEarlier),
        ],
      ],
    );
  }

  Widget _card(PlannerTask task, {bool showDay = false}) => Padding(
    key: ValueKey(task.id),
    padding: const EdgeInsets.only(bottom: 8),
    child: _TaskCard(
      task: task,
      showDay: showDay,
      onEdit: canEdit ? () => onEdit(task) : null,
      onToggle: canEdit ? () => onToggle(task) : null,
      onStepToggle: canEdit ? (index) => onStepToggle(task, index) : null,
    ),
  );

  Widget _completed(
    BuildContext context,
    String title,
    List<PlannerTask> tasks,
  ) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Panel(
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        key: PageStorageKey(title),
        leading: Icon(
          Icons.task_alt,
          color: context.palette.secondary,
          size: 20,
        ),
        title: Text('$title · ${tasks.length}', style: context.type.titleSmall),
        shape: const Border(),
        collapsedShape: const Border(),
        children: [
          for (final task in tasks)
            ListTile(
              leading: IconButton.filled(
                icon: const Icon(Icons.check, size: 16),
                tooltip: 'Reopen ${task.title}',
                onPressed: canEdit ? () => onToggle(task) : null,
                visualDensity: VisualDensity.compact,
              ),
              title: Text(
                task.title,
                style: const TextStyle(decoration: TextDecoration.lineThrough),
              ),
              onTap: canEdit ? () => onEdit(task) : null,
            ),
        ],
      ),
    ),
  );
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.showDay,
    required this.onEdit,
    required this.onToggle,
    required this.onStepToggle,
  });

  final PlannerTask task;
  final bool showDay;
  final VoidCallback? onEdit;
  final VoidCallback? onToggle;
  final ValueChanged<int>? onStepToggle;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final high = task.priority == TaskPriority.high;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                tooltip: 'Complete ${task.title}',
                onPressed: onToggle,
                icon: Icon(
                  Icons.circle_outlined,
                  color: palette.secondary,
                  size: 24,
                ),
              ),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: onEdit,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 2, 0, 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.title,
                          style: context.type.titleSmall!.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (task.notes.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            task.notes,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: context.type.bodySmall!.copyWith(
                              color: palette.onSurfaceVariant,
                            ),
                          ),
                        ],
                        if (high ||
                            task.startMinute != null ||
                            task.duration > 0 ||
                            showDay ||
                            task.origin != TaskOrigin.manual) ...[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              if (high)
                                Pill(
                                  'High',
                                  color: palette.errorContainer,
                                  foreground: palette.onErrorContainer,
                                ),
                              if (task.startMinute case final time?)
                                Pill(context.clock(time), icon: Icons.schedule),
                              if (task.duration > 0)
                                Pill(
                                  durationLabel(task.duration),
                                  icon: Icons.timer_outlined,
                                ),
                              if (showDay)
                                Pill(
                                  MaterialLocalizations.of(
                                    context,
                                  ).formatShortDate(DateTime.parse(task.day)),
                                ),
                              if (task.origin != TaskOrigin.manual)
                                Tooltip(
                                  message: task.origin == TaskOrigin.assistant
                                      ? 'AI suggested'
                                      : 'Tool action',
                                  child: IconBadge(
                                    task.origin == TaskOrigin.assistant
                                        ? Icons.auto_awesome
                                        : Icons.terminal,
                                    size: 22,
                                    color: palette.secondaryContainer,
                                    foreground: palette.onSecondaryContainer,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (task.steps.isNotEmpty) ...[
            const SizedBox(height: 8),
            Panel(
              color: palette.surfaceContainer,
              radius: 16,
              padding: EdgeInsets.zero,
              child: ExpansionTile(
                shape: const Border(),
                collapsedShape: const Border(),
                dense: true,
                minTileHeight: 44,
                leading: Icon(
                  Icons.checklist,
                  size: 18,
                  color: palette.primary,
                ),
                title: Text(
                  '${task.steps.length} sub-${task.steps.length == 1 ? 'step' : 'steps'}',
                  style: context.type.labelMedium!.copyWith(
                    color: palette.primary,
                  ),
                ),
                children: [
                  for (final (index, step) in task.steps.indexed)
                    CheckboxListTile(
                      dense: true,
                      value: step.done,
                      title: Text(
                        step.title,
                        style: TextStyle(
                          decoration: step.done
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      onChanged: onStepToggle == null
                          ? null
                          : (_) => onStepToggle!(index),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
