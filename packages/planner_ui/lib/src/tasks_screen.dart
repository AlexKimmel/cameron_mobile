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
    required this.search,
    required this.onFilterChanged,
    required this.canEdit,
    required this.onEdit,
    required this.onReschedule,
    required this.onToggle,
    required this.onStepToggle,
  });

  final List<PlannerTask> tasks;
  final String today;
  final TaskFilter filter;
  final TextEditingController search;
  final ValueChanged<TaskFilter> onFilterChanged;
  final bool canEdit;
  final ValueChanged<PlannerTask> onEdit;
  final ValueChanged<PlannerTask> onReschedule;
  final ValueChanged<PlannerTask> onToggle;
  final void Function(PlannerTask, int) onStepToggle;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: search,
        builder: (context, value, _) => _buildTasks(context, value.text),
      );

  Widget _buildTasks(BuildContext context, String query) {
    final filterMotion = context.reduceMotion
        ? ChipAnimationStyle(
            selectAnimation: AnimationStyle.noAnimation,
            avatarDrawerAnimation: AnimationStyle.noAnimation,
            enableAnimation: AnimationStyle.noAnimation,
          )
        : null;
    final normalized = query.trim().toLowerCase();
    final terms = normalized.isEmpty
        ? const <String>[]
        : normalized.split(RegExp(r'\s+'));
    final searching = terms.isNotEmpty;
    final matching = tasks.where((task) {
      if (!filter.matches(task)) return false;
      if (!searching) return true;
      final text = '${task.title}\n${task.notes}'.toLowerCase();
      return terms.every(text.contains);
    }).toList();
    final open = matching.where((task) => !task.done).toList()
      ..sort((a, b) {
        final dateOrder = a.day.compareTo(b.day);
        if (dateOrder != 0) return dateOrder;
        final timeOrder = (a.startMinute ?? 1440).compareTo(
          b.startMinute ?? 1440,
        );
        if (timeOrder != 0) return timeOrder;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    final byDate = <String, List<PlannerTask>>{};
    for (final task in open) {
      byDate.putIfAbsent(task.day, () => []).add(task);
    }
    final scheduled = byDate.remove(today) ?? const [];
    final overdue = byDate.entries.where(
      (entry) => entry.key.compareTo(today) < 0,
    );
    final upcoming = byDate.entries.where(
      (entry) => entry.key.compareTo(today) > 0,
    );
    final doneToday = matching
        .where((task) => task.completedOn == today)
        .toList();
    final doneEarlier =
        matching
            .where((task) => task.done && task.completedOn != today)
            .toList()
          ..sort((a, b) => b.completedOn!.compareTo(a.completedOn!));
    final focus = scheduled.fold(0, (sum, task) => sum + task.duration);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: search,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: 'Search tasks',
            hintText: 'Search titles and notes',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    onPressed: search.clear,
                    tooltip: 'Clear task search',
                    icon: const Icon(Icons.clear),
                  ),
          ),
        ),
        const SizedBox(height: 8),
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
                chipAnimationStyle: filterMotion,
                onSelected: (_) => onFilterChanged(option),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (matching.isEmpty)
          Panel(
            child: Text(
              searching
                  ? 'No tasks match your search'
                  : filter == TaskFilter.all
                  ? 'No tasks yet'
                  : 'No matching tasks',
              style: context.type.bodyMedium,
            ),
          )
        else ...[
          if (overdue.isNotEmpty) ...[
            const SectionHeading('Overdue', icon: Icons.error_outline),
            for (final entry in overdue) ..._dateGroup(context, entry),
            const SizedBox(height: 8),
          ],
          if (!searching || scheduled.isNotEmpty) ...[
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
          ],
          if (upcoming.isNotEmpty) ...[
            const SizedBox(height: 16),
            const SectionHeading('Upcoming'),
            for (final entry in upcoming) ..._dateGroup(context, entry),
          ],
          if (doneToday.isNotEmpty)
            _completed(context, 'Completed', doneToday, expanded: searching),
          if (doneEarlier.isNotEmpty)
            _completed(
              context,
              'Previously completed',
              doneEarlier,
              showDate: true,
              expanded: searching,
            ),
        ],
      ],
    );
  }

  List<Widget> _dateGroup(
    BuildContext context,
    MapEntry<String, List<PlannerTask>> group,
  ) => [
    Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
      child: Semantics(
        header: true,
        child: Text(
          MaterialLocalizations.of(context)
              .formatFullDate(DateTime.parse(group.key)),
          style: context.type.labelLarge,
        ),
      ),
    ),
    for (final task in group.value) _card(task),
  ];

  Widget _card(PlannerTask task) => Padding(
    key: ValueKey(task.id),
    padding: const EdgeInsets.only(bottom: 8),
    child: _TaskCard(
      task: task,
      onEdit: canEdit ? () => onEdit(task) : null,
      onReschedule: canEdit ? () => onReschedule(task) : null,
      onToggle: canEdit ? () => onToggle(task) : null,
      onStepToggle: canEdit ? (index) => onStepToggle(task, index) : null,
    ),
  );

  Widget _completed(
    BuildContext context,
    String title,
    List<PlannerTask> tasks, {
    bool showDate = false,
    bool expanded = false,
  }) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Panel(
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        key: PageStorageKey((title, expanded)),
        initiallyExpanded: expanded,
        expansionAnimationStyle: context.reducedMotionStyle,
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
              ),
              title: Text(
                task.title,
                style: const TextStyle(decoration: TextDecoration.lineThrough),
              ),
              subtitle: showDate
                  ? Text(
                      MaterialLocalizations.of(context)
                          .formatShortDate(DateTime.parse(task.completedOn!)),
                    )
                  : null,
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
    required this.onEdit,
    required this.onReschedule,
    required this.onToggle,
    required this.onStepToggle,
  });

  final PlannerTask task;
  final VoidCallback? onEdit;
  final VoidCallback? onReschedule;
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
                child: Semantics(
                  button: onEdit != null,
                  hint: onEdit == null ? null : 'Edit task',
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: plannerTapTarget,
                    ),
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
                                task.occurrence != null ||
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
                                    Pill(
                                      context.clock(time),
                                      icon: Icons.schedule,
                                    ),
                                  if (task.duration > 0)
                                    Pill(
                                      durationLabel(task.duration),
                                      icon: Icons.timer_outlined,
                                    ),
                                  if (task.occurrence != null)
                                    const Pill('Repeats', icon: Icons.repeat),
                                  if (task.origin != TaskOrigin.manual)
                                    Tooltip(
                                      message:
                                          task.origin == TaskOrigin.assistant
                                          ? 'AI suggested'
                                          : 'Tool action',
                                      child: IconBadge(
                                        task.origin == TaskOrigin.assistant
                                            ? Icons.auto_awesome
                                            : Icons.terminal,
                                        size: 22,
                                        color: palette.secondaryContainer,
                                        foreground:
                                            palette.onSecondaryContainer,
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
                ),
              ),
              IconButton(
                tooltip: 'Reschedule ${task.title}',
                onPressed: onReschedule,
                icon: const Icon(Icons.event_outlined),
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
                minTileHeight: plannerTapTarget,
                expansionAnimationStyle: context.reducedMotionStyle,
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
