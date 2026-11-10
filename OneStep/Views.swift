import SwiftUI
import UIKit

private enum EditorRoute: Identifiable {
    case task(TaskEntry?), routine(RoutineStep?), settings
    var id: String {
        switch self {
        case .task(let task): return "task-\(task?.id.uuidString ?? "new")"
        case .routine(let step): return "routine-\(step?.id.uuidString ?? "new")"
        case .settings: return "settings"
        }
    }
}

struct RootView: View {
    @Environment(PlannerStore.self) private var store
    @State private var editor: EditorRoute?

    var body: some View {
        @Bindable var bindings = store
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            TabView(selection: $bindings.selectedTab) {
                Tab("Now", systemImage: "sparkle", value: 0) {
                    NavigationStack {
                        NowView(now: timeline.date, addTask: { editor = .task(nil) })
                            .toolbar { settingsButton }
                    }
                }
                Tab("Tasks", systemImage: "checklist", value: 1) {
                    NavigationStack {
                        TaskListView(edit: { editor = .task($0) })
                            .toolbar {
                                ToolbarItem(placement: .primaryAction) {
                                    Button("Add task", systemImage: "plus") { editor = .task(nil) }
                                }
                            }
                    }
                }
                Tab("Routines", systemImage: "sunrise", value: 2) {
                    NavigationStack {
                        RoutineListView(now: timeline.date, edit: { editor = .routine($0) })
                            .toolbar {
                                ToolbarItem(placement: .topBarLeading) { EditButton() }
                                ToolbarItem(placement: .primaryAction) {
                                    Button("Add step", systemImage: "plus") { editor = .routine(nil) }
                                }
                            }
                    }
                }
                Tab("History", systemImage: "clock", value: 3) {
                    NavigationStack { HistoryView() }
                }
            }
            .task(id: PlannerRules.dayKey(timeline.date)) { await store.refresh() }
        }
        .tint(.teal)
        .sheet(item: $editor) { route in
            switch route {
            case .task(let task): TaskEditor(task: task)
            case .routine(let step): RoutineEditor(step: step)
            case .settings: ReminderSettingsView()
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let feedback = store.feedback {
                HStack {
                    Text(feedback).font(.subheadline)
                    Spacer()
                    Button("Dismiss", systemImage: "xmark") { store.feedback = nil }.labelStyle(.iconOnly)
                }
                .padding().background(.regularMaterial)
            }
        }
        .alert("Something needs attention", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            store.focusedItem = nil
            Task { await store.refresh() }
        }
    }

    @ToolbarContentBuilder
    private var settingsButton: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button("Reminder settings", systemImage: "bell") { editor = .settings }
        }
    }
}

private struct NowView: View {
    @Environment(PlannerStore.self) private var store
    let now: Date
    let addTask: () -> Void

    private var next: ActionItem? {
        if let focused = store.focusedItem, focused.day == nil || focused.day == PlannerRules.dayKey(now) { return focused }
        return PlannerRules.nextAction(store.state, now: now)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(now, format: .dateTime.weekday(.wide).month().day()).foregroundStyle(.secondary)
                    Text("One thing at a time.").font(.largeTitle.bold())
                    Text("You can start from here.").foregroundStyle(.secondary)
                }
                if let item = next {
                    VStack(alignment: .leading, spacing: 20) {
                        Label(item.kind == .routine ? "ROUTINE · NEXT STEP" : "YOUR NEXT STEP",
                              systemImage: item.kind == .routine ? "sunrise" : "circle")
                            .font(.caption.weight(.semibold)).foregroundStyle(.teal)
                        Text(item.title).font(.title.bold()).fixedSize(horizontal: false, vertical: true)
                        if !item.notes.isEmpty { Text(item.notes).foregroundStyle(.secondary) }
                        if let due = item.scheduledAt {
                            HStack {
                                Image(systemName: "clock")
                                Text(due <= now ? "Ready when you are" : "Coming up")
                                Text(due, style: .time)
                            }.font(.subheadline).foregroundStyle(.secondary)
                        }
                        Button { store.complete(item) } label: {
                            Label("Done", systemImage: "checkmark").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 10)
                        }.modifier(PrimaryGlassButton())
                        Button("Snooze 10 minutes") { store.snooze(item) }
                            .buttonStyle(.bordered).frame(maxWidth: .infinity).controlSize(.large)
                        if item.kind == .routine {
                            Button("Skip today") { store.complete(item, skip: true) }
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 28))
                } else {
                    ContentUnavailableView("A little breathing room", systemImage: "leaf",
                        description: Text("Nothing needs your attention right now. Snoozed steps will return when they're ready."))
                }
                Button(action: addTask) {
                    Label("Capture a thought", systemImage: "plus").frame(maxWidth: .infinity).padding(.vertical, 8)
                }.buttonStyle(.bordered).controlSize(.large)
                Button("See all tasks") { store.selectedTab = 1 }.frame(maxWidth: .infinity).padding(.vertical, 8)
                Text("OneStep · 0.1.0 beta").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }.padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Now")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PrimaryGlassButton: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) { content.buttonStyle(.glassProminent).controlSize(.large) }
        else { content.buttonStyle(.borderedProminent).controlSize(.large) }
    }
}

private struct TaskListView: View {
    @Environment(PlannerStore.self) private var store
    let edit: (TaskEntry) -> Void
    private var tasks: [TaskEntry] {
        store.state.tasks.filter { $0.completedAt == nil }.sorted {
            ($0.snoozedUntil ?? $0.dueAt ?? .distantFuture) < ($1.snoozedUntil ?? $1.dueAt ?? .distantFuture)
        }
    }

    var body: some View {
        List {
            ForEach(tasks) { task in
                Button { edit(task) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(task.title).font(.headline).foregroundStyle(.primary)
                        if let date = task.snoozedUntil ?? task.dueAt {
                            Text(date, format: .dateTime.month().day().hour().minute()).font(.subheadline).foregroundStyle(.secondary)
                        } else { Text("Whenever you're ready").font(.subheadline).foregroundStyle(.secondary) }
                    }.padding(.vertical, 8)
                }
                .swipeActions(edge: .leading) {
                    Button("Done", systemImage: "checkmark") { store.complete(PlannerRules.taskAction(task)) }.tint(.teal)
                }
                .swipeActions(edge: .trailing) {
                    Button("Delete", systemImage: "trash", role: .destructive) { store.deleteTask(task) }
                }
            }
        }
        .overlay { if tasks.isEmpty { ContentUnavailableView("Room for a fresh start", systemImage: "checklist", description: Text("Tap + to capture your first task.")) } }
        .navigationTitle("Tasks")
    }
}

private struct RoutineListView: View {
    @Environment(PlannerStore.self) private var store
    let now: Date
    let edit: (RoutineStep) -> Void

    var body: some View {
        List {
            Section {
                Text("The same gentle structure, every day. Done and Skip only affect today.").foregroundStyle(.secondary)
            }
            ForEach(store.state.routines.sorted { $0.position < $1.position }) { step in
                let record = PlannerRules.record(step, on: now, in: store.state)
                let item = PlannerRules.routineAction(step, on: now, state: store.state)
                VStack(alignment: .leading, spacing: 12) {
                    Button { edit(step) } label: {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(step.title).font(.headline).foregroundStyle(.primary)
                                Text(PlannerRules.scheduledTime(step, on: now), style: .time).foregroundStyle(.secondary)
                                if let snooze = record?.snoozedUntil, snooze > now {
                                    Text("Snoozed until \(snooze.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if let status = record?.status {
                                Label(status == .done ? "Done" : "Skipped", systemImage: status == .done ? "checkmark.circle.fill" : "forward.end")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else { Image(systemName: "pencil").foregroundStyle(.secondary) }
                        }.padding(.vertical, 4)
                    }.buttonStyle(.plain)
                    if record?.status == nil {
                        ViewThatFits(in: .horizontal) {
                            HStack {
                                Button("Done") { store.complete(item) }.buttonStyle(.borderedProminent)
                                Button("Snooze") { store.snooze(item) }.buttonStyle(.bordered)
                                Button("Skip today") { store.complete(item, skip: true) }.buttonStyle(.bordered)
                            }
                            VStack(alignment: .leading) {
                                Button("Done") { store.complete(item) }.buttonStyle(.borderedProminent)
                                Button("Snooze 10 minutes") { store.snooze(item) }.buttonStyle(.bordered)
                                Button("Skip today") { store.complete(item, skip: true) }.buttonStyle(.bordered)
                            }
                        }.controlSize(.large)
                    }
                }
                .padding(.vertical, 6)
                .swipeActions {
                    Button("Delete step", systemImage: "trash", role: .destructive) { store.deleteRoutine(step) }
                }
            }
            .onMove { store.moveRoutines(from: $0, to: $1) }
            if store.state.routines.isEmpty {
                Text("Start small. Add one daily step with +, then build your routine at your own pace.").foregroundStyle(.secondary)
            }
        }.navigationTitle("Routines")
    }
}

private struct TaskEditor: View {
    @Environment(PlannerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let task: TaskEntry?
    @State private var title: String
    @State private var notes: String
    @State private var hasDate: Bool
    @State private var dueAt: Date
    @State private var reminder: Bool

    init(task: TaskEntry?) {
        self.task = task
        _title = State(initialValue: task?.title ?? "")
        _notes = State(initialValue: task?.notes ?? "")
        _hasDate = State(initialValue: task?.dueAt != nil)
        _dueAt = State(initialValue: task?.dueAt ?? Date().addingTimeInterval(3600))
        _reminder = State(initialValue: task?.reminderEnabled ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("One thing to do") { TextField("What would you like to do?", text: $title, axis: .vertical).textInputAutocapitalization(.sentences) }
                Section("Optional") {
                    TextField("A little context", text: $notes, axis: .vertical).lineLimit(3...6)
                    Toggle("Set a due time", isOn: $hasDate)
                    if hasDate {
                        DatePicker("When", selection: $dueAt)
                        Toggle("Remind me", isOn: $reminder)
                        if reminder {
                            Text("One reminder when due, then one follow-up after 10 minutes. Snoozing replaces both with one reminder.").font(.footnote).foregroundStyle(.secondary)
                            if dueAt <= Date() { Text("This time has passed. Missed alerts aren't replayed; choose a future time for a new reminder.").font(.footnote).foregroundStyle(.secondary) }
                        }
                    }
                }
                if let task {
                    Section {
                        Button("Mark done") { store.complete(PlannerRules.taskAction(task)); dismiss() }
                    }
                }
            }
            .navigationTitle(task == nil ? "Capture a thought" : "Edit task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if store.saveTask(id: task?.id, title: title, notes: notes, dueAt: hasDate ? dueAt : nil, reminder: reminder) { dismiss() }
                    }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let error = store.errorMessage { Text(error).font(.footnote).padding().background(.regularMaterial) }
            }
        }
    }
}

private struct RoutineEditor: View {
    @Environment(PlannerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let step: RoutineStep?
    @State private var title: String
    @State private var time: Date

    init(step: RoutineStep?) {
        self.step = step
        _title = State(initialValue: step?.title ?? "")
        _time = State(initialValue: step.map { PlannerRules.scheduledTime($0, on: Date()) } ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("A small daily step") {
                    TextField("For example, fill my water bottle", text: $title, axis: .vertical)
                    DatePicker("Every day at", selection: $time, displayedComponents: .hourAndMinute)
                }
                Section {
                    Text("You'll get a reminder at this time and one follow-up 10 minutes later. Done or Skip cancels today's follow-up.")
                    Text("Changing this template updates future days. Today's completed steps and your history stay saved.")
                }.font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle(step == nil ? "Add routine step" : "Edit daily step")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { if store.saveRoutine(id: step?.id, title: title, time: time) { dismiss() } }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let error = store.errorMessage { Text(error).font(.footnote).padding().background(.regularMaterial) }
            }
        }
    }
}

private struct HistoryView: View {
    @Environment(PlannerStore.self) private var store

    var body: some View {
        List {
            Section("Completed tasks") {
                ForEach(store.state.tasks.filter { $0.completedAt != nil }.sorted { $0.completedAt! > $1.completedAt! }) { task in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(task.title)
                        if let completed = task.completedAt { Text(completed, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary) }
                    }
                    .swipeActions { Button("Undo") { store.undoTask(task) }.tint(.teal) }
                }
            }
            Section("Daily routine history") {
                ForEach(store.state.days.filter { $0.status != nil }.sorted { $0.updatedAt > $1.updatedAt }) { record in
                    VStack(alignment: .leading, spacing: 6) {
                        Label(record.title, systemImage: record.status == .done ? "checkmark.circle" : "forward.end")
                        Text("\(record.day) · \(record.status == .done ? "Done" : "Skipped")").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .overlay {
            if !store.state.tasks.contains(where: { $0.completedAt != nil }) && !store.state.days.contains(where: { $0.status != nil }) {
                ContentUnavailableView("Your own pace", systemImage: "leaf", description: Text("Completed tasks and daily steps will appear here. No streaks to maintain."))
            }
        }
        .navigationTitle("History")
    }
}

private struct ReminderSettingsView: View {
    @Environment(PlannerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Form {
                Section("Reminders") {
                    switch store.notificationStatus {
                    case .notDetermined:
                        Text("Enable reminders when you're ready. Your tasks work either way.")
                        Button("Enable reminders") { Task { await store.enableNotifications() } }
                    case .denied:
                        Text("Reminders are off in iPhone Settings.")
                        Button("Open iPhone Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
                    default:
                        Label("Reminders allowed", systemImage: "bell.badge")
                        Button("Open notification settings") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
                    }
                    Text("This beta uses ordinary notifications. Silent mode, Focus, and your notification settings can silence or delay them.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Scheduling coverage") {
                    if let until = store.coverageUntil {
                        Text("Reminders queued through \(until.formatted(date: .abbreviated, time: .shortened)).")
                        Text("\(store.scheduledCount) alerts queued. Open OneStep regularly to extend coverage.").font(.footnote).foregroundStyle(.secondary)
                        if store.omittedCount > 0 { Text("The iPhone notification queue is full. Later reminders will be added when you reopen the app.").font(.footnote) }
                    } else { Text("Enable reminders, then refresh to check coverage.") }
                    Button("Refresh reminders") { Task { await store.refresh() } }
                    Text("The beta queues up to 60 alerts, looking 14 days ahead for routines. It can't refill that queue while completely closed. Time-zone changes are applied when you reopen it.").font(.footnote).foregroundStyle(.secondary)
                    if let error = store.errorMessage { Text(error).font(.footnote) }
                }
                Section("Offline beta") {
                    Text("All tasks and routines stay on this iPhone. Updating over the app preserves its data; deleting the app removes it.")
                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0") · Build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")")
                    Text("Timers, Live Activities, backup/import, and syncing are coming later.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Reminder settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
