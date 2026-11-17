import 'localization.dart';
import 'package:flutter/material.dart';
import 'model.dart';
import 'services.dart';

List<Json> calendarTasks(Json state, DateTime day, {bool archived = false}) =>
    rows(state, 'tasks')
        .where(
          (t) =>
              (archived || t['archived'] != true) &&
              dateOf(t['dueAt']) != null &&
              dayKey(dateOf(t['dueAt'])!) == dayKey(day),
        )
        .toList()
      ..sort((a, b) => (a['dueAt'] as num).compareTo(b['dueAt'] as num));

class CalendarPage extends StatefulWidget {
  final Planner planner;
  final void Function(Json) edit;
  const CalendarPage({super.key, required this.planner, required this.edit});
  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime selected = DateTime.now();
  String view = 'month';
  bool archived = false;
  DateTime shift(int amount) => view == 'month'
      ? DateTime(selected.year, selected.month + amount, 1)
      : DateTime(
          selected.year,
          selected.month,
          selected.day + amount * (view == 'week' ? 7 : 1),
        );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const LText('Planner'),
      actions: [
        TextButton(
          onPressed: () => setState(() => selected = DateTime.now()),
          child: const LText('Today'),
        ),
      ],
    ),
    body: AnimatedBuilder(
      animation: widget.planner,
      builder: (context, _) {
        final state = widget.planner.state;
        final dates = view == 'month'
            ? List.generate(
                DateTime(selected.year, selected.month + 1, 0).day,
                (i) => DateTime(selected.year, selected.month, i + 1),
              )
            : List.generate(
                view == 'week' ? 7 : 1,
                (i) => DateTime(
                  selected.year,
                  selected.month,
                  selected.day -
                      (view == 'week' ? selected.weekday - 1 : 0) +
                      i,
                ),
              );
        final scheduled = calendarTasks(state, selected, archived: archived);
        final unscheduled = rows(state, 'tasks')
            .where(
              (t) =>
                  dateOf(t['dueAt']) == null &&
                  (archived || t['archived'] != true),
            )
            .toList();
        Widget taskTile(Json task) => Card(
          child: ListTile(
            onTap: () => widget.edit(task),
            leading: Icon(
              task['completedAt'] != null
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: task['completedAt'] != null
                  ? const Color(0xff6bdfbd)
                  : null,
            ),
            title: Text(task['title'] as String),
            subtitle: Text(
              dateOf(task['dueAt']) == null
                  ? 'No due date'
                  : MaterialLocalizations.of(context).formatTimeOfDay(
                      TimeOfDay.fromDateTime(dateOf(task['dueAt'])!),
                    ),
            ),
            trailing: task['rewardPoints'] != null
                ? Text('${task['rewardPoints']} pt')
                : null,
          ),
        );
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'day', label: LText('Day')),
                ButtonSegment(value: 'week', label: LText('Week')),
                ButtonSegment(value: 'month', label: LText('Month')),
              ],
              selected: {view},
              onSelectionChanged: (v) => setState(() => view = v.first),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton(
                  tooltip: 'Previous',
                  onPressed: () => setState(() => selected = shift(-1)),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    MaterialLocalizations.of(context).formatMonthYear(selected),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Next',
                  onPressed: () => setState(() => selected = shift(1)),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            if (view == 'month')
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 7,
                childAspectRatio: .85,
                children: [
                  for (var i = 0; i < (dates.first.weekday - 1); i++)
                    const SizedBox(),
                  for (final day in dates)
                    InkWell(
                      onTap: () => setState(() => selected = day),
                      borderRadius: BorderRadius.circular(14),
                      child: Semantics(
                        label: MaterialLocalizations.of(
                          context,
                        ).formatFullDate(day),
                        selected: dayKey(day) == dayKey(selected),
                        child: Container(
                          margin: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: dayKey(day) == dayKey(selected)
                                ? Theme.of(context).colorScheme.primaryContainer
                                : null,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('${day.day}'),
                              if (calendarTasks(
                                state,
                                day,
                                archived: archived,
                              ).isNotEmpty)
                                const Icon(Icons.circle, size: 5),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            if (view == 'week')
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final day in dates)
                      Padding(
                        padding: const EdgeInsets.all(3),
                        child: ChoiceChip(
                          label: Text(
                            '${MaterialLocalizations.of(context).narrowWeekdays[day.weekday % 7]}\n${day.day}',
                          ),
                          selected: dayKey(day) == dayKey(selected),
                          onSelected: (_) => setState(() => selected = day),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Text(
              MaterialLocalizations.of(context).formatFullDate(selected),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const LText('Include archived tasks'),
              value: archived,
              onChanged: (v) => setState(() => archived = v),
            ),
            if (scheduled.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: LText('No tasks due this day.'),
              ),
            ...scheduled.map(taskTile),
            const SizedBox(height: 12),
            const LText(
              'Daily routines',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            for (final step
                in rows(state, 'routines')..sort(
                  (a, b) =>
                      (a['position'] as int).compareTo(b['position'] as int),
                ))
              ListTile(
                leading: Icon(
                  record(state, step, selected)?['status'] == 'done'
                      ? Icons.check_circle_outline
                      : Icons.wb_twilight,
                ),
                title: Text(step['title'] as String),
                subtitle: Text(
                  '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay(hour: step['hour'] as int, minute: step['minute'] as int))} · ${record(state, step, selected)?['status'] ?? 'Daily'}',
                ),
              ),
            const SizedBox(height: 20),
            const LText(
              'Tasks without a due date',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            ...unscheduled.map(taskTile),
          ],
        );
      },
    ),
  );
}
