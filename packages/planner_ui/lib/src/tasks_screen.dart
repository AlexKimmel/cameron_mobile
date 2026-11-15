import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:planner/planner.dart';

import 'design.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({
    super.key,
    required this.tasks,
    required this.today,
    required this.onEdit,
    required this.onToggle,
    required this.onStepToggle,
  });

  final List<PlannerTask> tasks;
  final String today;
  final ValueChanged<PlannerTask> onEdit;
  final ValueChanged<PlannerTask> onToggle;
  final void Function(PlannerTask, int) onStepToggle;

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  int _filter = 0;

  @override
  Widget build(BuildContext context) {
    final tasks = widget.tasks.where(
      (task) => switch (_filter) {
        1 => task.origin == TaskOrigin.assistant || task.steps.isNotEmpty,
        2 => task.origin == TaskOrigin.tool,
        _ => true,
      },
    );
    final today = widget.today;
    final scheduled =
        tasks.where((task) => !task.done && task.day == today).toList()..sort(
          (a, b) => (a.startMinute ?? 1440).compareTo(b.startMinute ?? 1440),
        );
    final other =
        tasks.where((task) => !task.done && task.day != today).toList()
          ..sort((a, b) => a.day.compareTo(b.day));
    final doneToday = tasks.where((task) => task.completedOn == today).toList();
    final doneEarlier = tasks
        .where((task) => task.done && task.completedOn != today)
        .toList();
    final focus = scheduled.fold(0, (sum, task) => sum + task.duration);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Panel(
            radius: 30,
            padding: const EdgeInsets.all(4),
            color: context.palette.surfaceContainer,
            child: M3EButtonGroup(
              semanticLabel: 'Filter tasks',
              selectedIndex: _filter,
              selectionRequired: true,
              size: M3EButtonSize.sm,
              style: M3EButtonStyle.tonal,
              decoration: M3EButtonDecoration(
                backgroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? context.palette.primary
                      : context.palette.surfaceContainer,
                ),
                foregroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? context.palette.onPrimary
                      : context.palette.onSurfaceVariant,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                iconSize: 16,
                textStyle: context.type.labelMedium,
                selectedRadius: 22,
                unselectedRadius: 22,
              ),
              onSelectedIndexChanged: (value) =>
                  setState(() => _filter = value!),
              actions: [
                for (final (index, item) in const [
                  (Icons.task_alt, 'All tasks'),
                  (Icons.auto_awesome, 'AI suggested'),
                  (Icons.terminal, 'Tool actions'),
                ].indexed)
                  M3EButtonGroupAction(
                    icon: Icon(item.$1),
                    label: index == _filter ? Text(item.$2) : null,
                    semanticLabel: item.$2,
                    tooltip: index == _filter ? null : item.$2,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
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
            child: Text(
              _filter == 0 ? 'No tasks today' : 'No matching tasks',
              style: context.type.bodyMedium,
            ),
          ),
        for (final task in scheduled) _card(task),
        if (other.isNotEmpty) ...[
          const SizedBox(height: 16),
          const SectionHeading('Other days'),
          const SizedBox(height: 8),
          for (final task in other) _card(task, showDay: true),
        ],
        if (doneToday.isNotEmpty) _completed('Completed', doneToday),
        if (doneEarlier.isNotEmpty)
          _completed('Previously completed', doneEarlier),
      ],
    );
  }

  Widget _card(PlannerTask task, {bool showDay = false}) => Padding(
    key: ValueKey(task.id),
    padding: const EdgeInsets.only(bottom: 8),
    child: _TaskCard(
      task: task,
      showDay: showDay,
      onEdit: () => widget.onEdit(task),
      onToggle: () => widget.onToggle(task),
      onStepToggle: (index) => widget.onStepToggle(task, index),
    ),
  );

  Widget _completed(String title, List<PlannerTask> tasks) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Panel(
      padding: EdgeInsets.zero,
      child: ExpansionTile(
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
                onPressed: () => widget.onToggle(task),
                visualDensity: VisualDensity.compact,
              ),
              title: Text(
                task.title,
                style: const TextStyle(decoration: TextDecoration.lineThrough),
              ),
              onTap: () => widget.onEdit(task),
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
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final ValueChanged<int> onStepToggle;

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
                  Icons.auto_awesome,
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
                      onChanged: (_) => onStepToggle(index),
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
