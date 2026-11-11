import SwiftUI
import UIKit

private enum EditorRoute: Identifiable {
    case task(TaskEntry?), routine(RoutineStep?), focus(ActionItem), settings
    var id: String {
        switch self {
        case .task(let task): return "task-\(task?.id.uuidString ?? "new")"
        case .routine(let step): return "routine-\(step?.id.uuidString ?? "new")"
        case .focus(let item): return "focus-\(item.id)"
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
                        NowView(now: timeline.date, addTask: { editor = .task(nil) }, startFocus: { editor = .focus($0) })
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
                Tab("Notes", systemImage: "note.text", value: 4) {
                    NavigationStack { NotesView() }
                }
            }
            .task(id: PlannerRules.dayKey(timeline.date)) { await store.refresh() }
        }
        .tint(tabPalette.color)
        .preferredColorScheme(.dark)
        .sheet(item: $editor) { route in
            switch route {
            case .task(let task): TaskEditor(task: task)
            case .routine(let step): RoutineEditor(step: step)
            case .focus(let item): FocusTimerSheet(item: item)
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
                .padding().background(ItemPalette.mint.color.opacity(0.12))
            }
        }
        .alert("Something needs attention", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            store.focusedItem = nil
            Task { await store.refresh() }
        }
        .onOpenURL { url in
            if url.scheme == "onestep" { store.selectedTab = 0; store.focusedItem = nil }
        }
    }

    private var tabPalette: ItemPalette {
        switch store.selectedTab { case 1: return .blue; case 2: return .violet; case 3: return .amber; default: return .mint }
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
    let startFocus: (ActionItem) -> Void

    private var next: ActionItem? {
        if store.state.focusSession != nil { return PlannerRules.nextAction(store.state, now: now) }
        if let focused = store.focusedItem, focused.day == nil || focused.day == PlannerRules.dayKey(now) { return focused }
        return PlannerRules.nextAction(store.state, now: now)
    }

    private var palette: ItemPalette { .resolve(next?.colorName, routine: next?.kind == .routine) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Label { Text(now, format: .dateTime.weekday(.wide).month().day()) } icon: { Image(systemName: "sun.max.fill") }
                        .font(.subheadline.weight(.medium)).foregroundStyle(ItemPalette.amber.color)
                    Text("One thing at a time.").font(store.state.focusSession == nil ? .largeTitle.bold() : .title2.bold())
                    if store.state.focusSession == nil { Text("You can start from here.").foregroundStyle(.secondary) }
                }
                if let item = next {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            ColorBadge(palette: palette, symbol: item.kind == .routine ? "sunrise.fill" : "checklist")
                            Spacer()
                            Text(item.kind == .routine ? "DAILY ROUTINE" : "TASK")
                                .font(.caption.weight(.bold)).foregroundStyle(palette.color)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(palette.color.opacity(0.13), in: Capsule())
                        }
                        Text(item.title).font(.title.bold()).fixedSize(horizontal: false, vertical: true)
                        if !item.notes.isEmpty, item.kind == .task {
                            Text(item.notes).font(.subheadline).foregroundStyle(.secondary)
                                .lineLimit(store.state.focusSession == nil ? nil : 2)
                        }
                        if let due = item.scheduledAt {
                            HStack {
                                Image(systemName: "clock")
                                Text(due <= now ? "Ready when you are" : "Coming up")
                                Text(due, style: .time)
                            }.font(.subheadline).foregroundStyle(.secondary)
                        }
                        if let session = store.state.focusSession, session.action.id == item.id {
                            VStack(alignment: .leading, spacing: 10) {
                                Label(session.endsAt <= now ? "Time is up — ready to finish?" : "Your focus time", systemImage: "timer")
                                    .font(.subheadline.weight(.semibold))
                                if let remaining = session.pausedRemaining {
                                    Text("Paused · \(Int(remaining) / 60)m \(Int(remaining) % 60)s").font(.title2.monospacedDigit())
                                } else {
                                    Text(timerInterval: session.startedAt...max(session.startedAt, session.endsAt), countsDown: true)
                                        .font(.system(.largeTitle, design: .rounded, weight: .bold)).monospacedDigit()
                                }
                                if session.durationBased == true {
                                    Button(session.pausedRemaining == nil ? "Pause timer" : "Resume timer") { store.togglePause() }
                                }
                                Button("Stop timer") { store.stopFocus() }.font(.subheadline)
                            }.padding().frame(maxWidth: .infinity, alignment: .leading)
                                .background(palette.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
                        } else {
                            Button { startFocus(item) } label: {
                                Label("Start a timer", systemImage: "timer").frame(maxWidth: .infinity)
                            }.buttonStyle(.bordered).controlSize(.large)
                        }
                        if let task = store.state.tasks.first(where: { item.kind == .task && $0.id == item.sourceID }) {
                            ForEach(task.microsteps ?? []) { step in
                                Button { store.toggleSmallStep(taskID: task.id, stepID: step.id) } label: {
                                    Label(step.title, systemImage: step.done ? "checkmark.circle.fill" : "circle").frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                                }.tint(step.done ? ItemPalette.mint.color : palette.color)
                            }
                        }
                        Button { store.complete(item) } label: {
                            Label("Done", systemImage: "checkmark").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 10)
                        }.modifier(PrimaryGlassButton()).tint(ItemPalette.mint.color)
                        Button("Snooze \(store.state.preferences?.snoozeMinutes ?? 10) minutes") { store.snooze(item, minutes: store.state.preferences?.snoozeMinutes ?? 10) }
                            .buttonStyle(.bordered).frame(maxWidth: .infinity).controlSize(.large).tint(ItemPalette.amber.color)
                        if item.kind == .routine {
                            Button("Skip today") { store.complete(item, skip: true) }
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 28))
                    .overlay { RoundedRectangle(cornerRadius: 28).stroke(palette.color.opacity(0.35), lineWidth: 1.5) }
                    .tint(palette.color)
                } else {
                    ContentUnavailableView("A little breathing room", systemImage: "leaf",
                        description: Text("Nothing needs your attention right now. Snoozed steps will return when they're ready."))
                }
                VStack(alignment: .leading, spacing: 12) {
                    Label("Your day, at a glance", systemImage: "lock.rectangle.on.rectangle").font(.headline)
                        .foregroundStyle(ItemPalette.violet.color)
                    Text("Keep your next action and focus countdown on the Lock Screen.").font(.subheadline).foregroundStyle(.secondary)
                    if store.liveRunning {
                        Button("Remove from Lock Screen") { Task { await store.stopLiveActivity() } }
                    } else {
                        Button("Show my day on Lock Screen") { Task { await store.startLiveActivity() } }
                            .buttonStyle(.borderedProminent)
                    }
                    if let message = store.liveMessage { Text(message).font(.footnote).foregroundStyle(.secondary) }
                    Text("Updates when you use OneStep. Countdown keeps ticking while locked. Sessions last up to 8 hours.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(ItemPalette.violet.color.opacity(0.09), in: RoundedRectangle(cornerRadius: 24))
                .tint(ItemPalette.violet.color)
                Button(action: addTask) {
                    Label("Capture a thought", systemImage: "plus").frame(maxWidth: .infinity).padding(.vertical, 8)
                }.buttonStyle(.bordered).controlSize(.large).tint(ItemPalette.coral.color)
                Button("See all tasks") { store.selectedTab = 1 }.frame(maxWidth: .infinity).padding(.vertical, 8)
                Text("OneStep · \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.0") beta")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }.padding(20)
        }
        .background {
            LinearGradient(colors: [palette.color.opacity(0.10), Color(uiColor: .systemGroupedBackground), ItemPalette.rose.color.opacity(0.07)],
                           startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
        }
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
    @State private var search = ""
    @State private var showArchived = false
    private var tasks: [TaskEntry] {
        store.state.tasks.filter { $0.completedAt == nil && ($0.archived == true) == showArchived && (search.isEmpty || ($0.title + " " + $0.notes + " " + ($0.listName ?? "")).localizedCaseInsensitiveContains(search)) }.sorted {
            if ($0.pinned == true) != ($1.pinned == true) { return $0.pinned == true }
            return ($0.snoozedUntil ?? $0.dueAt ?? .distantFuture) < ($1.snoozedUntil ?? $1.dueAt ?? .distantFuture)
        }
    }

    var body: some View {
        List {
            Toggle("Show archived", isOn: $showArchived)
            ForEach(tasks) { task in
                Button { edit(task) } label: {
                    HStack(alignment: .top, spacing: 14) {
                        ColorBadge(palette: .resolve(task.colorName), symbol: "checklist")
                        VStack(alignment: .leading, spacing: 6) {
                        Text(task.title).font(.headline).foregroundStyle(.primary)
                        if let list = task.listName, !list.isEmpty { Text(list).font(.caption).foregroundStyle(ItemPalette.violet.color) }
                        if let date = task.snoozedUntil ?? task.dueAt {
                            Text(date, format: .dateTime.month().day().hour().minute()).font(.subheadline).foregroundStyle(.secondary)
                        } else { Text("Whenever you're ready").font(.subheadline).foregroundStyle(.secondary) }
                        }
                    }.padding(.vertical, 8)
                }
                .listRowBackground(ItemPalette.resolve(task.colorName).color.opacity(0.07))
                .swipeActions(edge: .leading) {
                    Button("Done", systemImage: "checkmark") { store.complete(PlannerRules.taskAction(task)) }.tint(ItemPalette.mint.color)
                }
                .swipeActions(edge: .trailing) {
                    Button("Delete", systemImage: "trash", role: .destructive) { store.deleteTask(task) }
                    Button(task.archived == true ? "Unarchive" : "Archive") { var next = store.state; if let i = next.tasks.firstIndex(where: { $0.id == task.id }) { next.tasks[i].archived = !(task.archived ?? false); if next.focusSession?.action.sourceID == task.id { next.focusSession = nil }; _ = store.commit(next) } }.tint(.gray)
                }
                .contextMenu { Button(task.pinned == true ? "Unpin" : "Pin") { var next = store.state; if let i = next.tasks.firstIndex(where: { $0.id == task.id }) { next.tasks[i].pinned = !(task.pinned ?? false); _ = store.commit(next) } } }
            }
        }
        .listRowSpacing(10)
        .overlay { if tasks.isEmpty { ContentUnavailableView("Room for a fresh start", systemImage: "checklist", description: Text("Tap + to capture your first task.")) } }
        .navigationTitle("Tasks")
        .searchable(text: $search, prompt: "Tasks, notes, and lists")
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
                Button("Start a guided routine") {
                    if let step = store.state.routines.sorted(by: { $0.position < $1.position }).first(where: { PlannerRules.record($0, on: now, in: store.state)?.status == nil }) {
                        store.focusedItem = PlannerRules.routineAction(step, on: now, state: store.state); store.selectedTab = 0
                    }
                }
            }
            ForEach(store.state.routines.sorted { $0.position < $1.position }) { step in
                let record = PlannerRules.record(step, on: now, in: store.state)
                let item = PlannerRules.routineAction(step, on: now, state: store.state)
                VStack(alignment: .leading, spacing: 12) {
                    Button { edit(step) } label: {
                        HStack(alignment: .top) {
                            ColorBadge(palette: .resolve(step.colorName, routine: true), symbol: "sunrise.fill")
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
                                Button("Done") { store.complete(item) }.buttonStyle(.borderedProminent).tint(ItemPalette.mint.color)
                                Button("Snooze") { store.snooze(item) }.buttonStyle(.bordered).tint(ItemPalette.amber.color)
                                Button("Skip today") { store.complete(item, skip: true) }.buttonStyle(.bordered).tint(ItemPalette.resolve(step.colorName, routine: true).color)
                            }
                            VStack(alignment: .leading) {
                                Button("Done") { store.complete(item) }.buttonStyle(.borderedProminent).tint(ItemPalette.mint.color)
                                Button("Snooze 10 minutes") { store.snooze(item) }.buttonStyle(.bordered).tint(ItemPalette.amber.color)
                                Button("Skip today") { store.complete(item, skip: true) }.buttonStyle(.bordered)
                            }
                        }.controlSize(.large)
                    }
                }
                .padding(.vertical, 6)
                .listRowBackground(ItemPalette.resolve(step.colorName, routine: true).color.opacity(record?.status == nil ? 0.08 : 0.03))
                .swipeActions {
                    Button("Delete step", systemImage: "trash", role: .destructive) { store.deleteRoutine(step) }
                }
            }
            .onMove { store.moveRoutines(from: $0, to: $1) }
            if store.state.routines.isEmpty {
                Text("Start small. Add one daily step with +, then build your routine at your own pace.").foregroundStyle(.secondary)
            }
        }.listRowSpacing(10).navigationTitle("Routines")
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
    @State private var colorName: String
    @State private var repeatRule: String
    @State private var steps: String
    @State private var listName: String

    init(task: TaskEntry?) {
        self.task = task
        _title = State(initialValue: task?.title ?? "")
        _notes = State(initialValue: task?.notes ?? "")
        _hasDate = State(initialValue: task?.dueAt != nil)
        _dueAt = State(initialValue: task?.dueAt ?? Date().addingTimeInterval(3600))
        _reminder = State(initialValue: task?.reminderEnabled ?? true)
        _colorName = State(initialValue: task?.colorName ?? "blue")
        _repeatRule = State(initialValue: task?.repeatRule ?? "none")
        _steps = State(initialValue: (task?.microsteps ?? []).map(\.title).joined(separator: "\n"))
        _listName = State(initialValue: task?.listName ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("One thing to do") { TextField("What would you like to do?", text: $title, axis: .vertical).textInputAutocapitalization(.sentences) }
                Section("Make it recognizable") { PalettePicker(selection: $colorName) }
                Section("Make it smaller") {
                    TextField("One small step per line", text: $steps, axis: .vertical).lineLimit(3...8)
                    Button("Help me find a first step") { if steps.isEmpty { steps = "Get what I need\nDo just the first two minutes\nChoose the next small step" } }
                    Text("Edit these into steps that fit your task. No AI service or internet is used.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Organization") { TextField("List name (optional)", text: $listName) }
                Section("Optional") {
                    TextField("A little context", text: $notes, axis: .vertical).lineLimit(3...6)
                    Toggle("Set a due time", isOn: $hasDate)
                    if hasDate {
                        DatePicker("When", selection: $dueAt)
                        Toggle("Remind me", isOn: $reminder)
                        Picker("Repeat after completion", selection: $repeatRule) {
                            Text("Never").tag("none"); Text("Daily").tag("daily"); Text("Weekly").tag("weekly")
                        }
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
                        if store.saveTask(id: task?.id, title: title, notes: notes, dueAt: hasDate ? dueAt : nil, reminder: reminder, colorName: colorName, repeatRule: repeatRule == "none" ? nil : repeatRule, steps: steps.components(separatedBy: .newlines), listName: listName) { dismiss() }
                    }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let error = store.errorMessage { Text(error).font(.footnote).padding().background(.regularMaterial) }
            }
        }.tint(ItemPalette.resolve(colorName).color)
    }
}

private struct RoutineEditor: View {
    @Environment(PlannerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let step: RoutineStep?
    @State private var title: String
    @State private var time: Date
    @State private var colorName: String

    init(step: RoutineStep?) {
        self.step = step
        _title = State(initialValue: step?.title ?? "")
        _time = State(initialValue: step.map { PlannerRules.scheduledTime($0, on: Date()) } ?? Date())
        _colorName = State(initialValue: step?.colorName ?? "violet")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("A small daily step") {
                    TextField("For example, fill my water bottle", text: $title, axis: .vertical)
                    DatePicker("Every day at", selection: $time, displayedComponents: .hourAndMinute)
                }
                Section("Make it recognizable") { PalettePicker(selection: $colorName) }
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
                    Button("Save") { if store.saveRoutine(id: step?.id, title: title, time: time, colorName: colorName) { dismiss() } }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let error = store.errorMessage { Text(error).font(.footnote).padding().background(.regularMaterial) }
            }
        }.tint(ItemPalette.resolve(colorName, routine: true).color)
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
                Section("Data, devices, and accounts") { NavigationLink("Backups, Wi-Fi transfer, and accounts") { DataToolsView() } }
                Section("Reminder preferences") {
                    Toggle("One follow-up after 10 minutes", isOn: preference(\.followup, fallback: true))
                    Picker("Snooze length", selection: preference(\.snoozeMinutes, fallback: 10)) { ForEach([5, 10, 20, 30, 60], id: \.self) { Text("\($0) minutes").tag($0) } }
                    Toggle("Quiet hours: 22:00–08:00", isOn: Binding(get: { store.state.preferences?.quietStart != nil }, set: { value in var next = store.state; var prefs = next.preferences ?? ReminderPreferences(); prefs.quietStart = value ? 22 : nil; prefs.quietEnd = value ? 8 : nil; next.preferences = prefs; _ = store.commit(next) }))
                    Text("Quiet hours omit routine and task alerts; a timer you start still alerts. Alerts are never saved up for the morning.").font(.footnote)
                }
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
                    Text("Focus timers, backups, and direct Wi-Fi snapshot transfers work offline. Online sign-in is optional; it does not sync your planner.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Reminder settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func preference<T>(_ path: WritableKeyPath<ReminderPreferences, T>, fallback: T) -> Binding<T> {
        Binding(get: { store.state.preferences?[keyPath: path] ?? fallback }, set: { value in var next = store.state; var prefs = next.preferences ?? ReminderPreferences(); prefs[keyPath: path] = value; next.preferences = prefs; _ = store.commit(next) })
    }
}
