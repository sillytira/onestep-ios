import Foundation
import Observation
import SwiftData
import UserNotifications

/// A versioned document keeps the beta's persistence schema small and stable.
/// Tasks and dated routine records retain independent UUIDs inside the document.
@Model
final class PlannerDocument {
    @Attribute(.unique) var key: String
    var payload: Data

    init(payload: Data) {
        key = "primary"
        self.payload = payload
    }
}

@MainActor
@Observable
final class PlannerStore {
    static var shared: PlannerStore?
    private(set) var state: PlannerState
    var errorMessage: String?
    var notificationStatus: UNAuthorizationStatus = .notDetermined
    var coverageUntil: Date?
    var timeSensitiveAvailable = false
    var scheduledCount = 0
    var omittedCount = 0
    var focusedItem: ActionItem?
    var selectedTab = 0
    var feedback: String?
    var liveRunning = false
    var liveMessage: String?
    var guidedRoutine = false

    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let document: PlannerDocument
    @ObservationIgnored private let notifications = NotificationScheduler()
    @ObservationIgnored private let delegate = NotificationDelegate()
    @ObservationIgnored private let dayActivity = DayActivityController()
    @ObservationIgnored private var refreshRunning = false
    @ObservationIgnored private var refreshRequested = false

    init(inMemory: Bool = false, storeURL: URL? = nil) throws {
        let configuration: ModelConfiguration
        if let storeURL {
            configuration = ModelConfiguration(url: storeURL, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        }
        container = try ModelContainer(for: PlannerDocument.self, configurations: configuration)
        context = ModelContext(container)
        context.autosaveEnabled = false
        let documents = try context.fetch(FetchDescriptor<PlannerDocument>())
        if let existing = documents.first(where: { $0.key == "primary" }) {
            document = existing
            let decoded = try JSONDecoder().decode(PlannerState.self, from: existing.payload)
            guard decoded.schemaVersion == 1 else { throw StoreError.newerSchema }
            state = decoded
        } else {
            let initialState = PlannerState()
            state = initialState
            document = PlannerDocument(payload: try JSONEncoder().encode(initialState))
            context.insert(document)
            try context.save()
        }
        delegate.onOpen = { [weak self] reference in self?.open(reference) }
        UNUserNotificationCenter.current().delegate = delegate
        if !inMemory && storeURL == nil { Self.shared = self }
    }

    enum StoreError: LocalizedError {
        case newerSchema
        var errorDescription: String? { "This data was saved by a newer version. Install that version to continue. Your data has not been reset." }
    }

    @discardableResult
    func commit(_ next: PlannerState) -> Bool {
        do {
            document.payload = try JSONEncoder().encode(next)
            try context.save()
            state = next
            focusedItem = nil
            Task { await refresh() }
            return true
        } catch {
            context.rollback()
            errorMessage = "Couldn't save that change. Please try again. \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func saveTask(id: UUID?, title: String, notes: String, dueAt: Date?, reminder: Bool, colorName: String = "blue", repeatRule: String? = nil, steps: [String]? = nil, listName: String? = nil) -> Bool {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return false }
        var next = state
        if let id, let index = next.tasks.firstIndex(where: { $0.id == id }) {
            next.tasks[index].title = cleanTitle
            next.tasks[index].notes = notes
            next.tasks[index].dueAt = dueAt
            next.tasks[index].reminderEnabled = dueAt != nil && reminder
            next.tasks[index].snoozedUntil = nil
            next.tasks[index].colorName = colorName
        } else {
            next.tasks.append(TaskEntry(title: cleanTitle, notes: notes, dueAt: dueAt,
                                        reminderEnabled: dueAt != nil && reminder, colorName: colorName))
        }
        if let index = next.tasks.firstIndex(where: { id == nil ? $0.id == next.tasks.last?.id : $0.id == id }) {
            next.tasks[index].repeatRule = dueAt == nil ? nil : repeatRule
            next.tasks[index].listName = listName
            if let steps {
                let old = next.tasks[index].microsteps ?? []
                next.tasks[index].microsteps = steps.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map { title in
                    old.first(where: { $0.title == title }) ?? SmallStep(title: title)
                }
            }
        }
        return commit(next)
    }

    @discardableResult
    func saveRoutine(id: UUID?, title: String, time: Date, colorName: String = "violet") -> Bool {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return false }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        var next = state
        if let id, let index = next.routines.firstIndex(where: { $0.id == id }) {
            next.routines[index].title = cleanTitle
            next.routines[index].hour = parts.hour!
            next.routines[index].minute = parts.minute!
            next.routines[index].colorName = colorName
            // Editing a schedule also clears today's old snooze, but keeps completed history.
            let key = PlannerRules.dayKey(Date())
            if let recordIndex = next.days.firstIndex(where: { $0.stepID == id && $0.day == key }) {
                next.days[recordIndex].snoozedUntil = nil
            }
        } else {
            let position = (next.routines.map(\.position).max() ?? -1) + 1
            next.routines.append(RoutineStep(title: cleanTitle, hour: parts.hour!, minute: parts.minute!, position: position, colorName: colorName))
        }
        return commit(next)
    }

    func deleteTask(_ task: TaskEntry) {
        var next = state
        next.tasks.removeAll { $0.id == task.id }
        if next.focusSession?.action.sourceID == task.id { next.focusSession = nil }
        _ = commit(next)
    }

    func deleteRoutine(_ step: RoutineStep) {
        var next = state
        next.routines.removeAll { $0.id == step.id }
        if next.focusSession?.action.sourceID == step.id { next.focusSession = nil }
        // Dated records include the old title and survive template deletion.
        _ = commit(next)
    }

    func moveRoutines(from source: IndexSet, to destination: Int) {
        var next = state
        var sorted = next.routines.sorted { $0.position < $1.position }
        let moving = source.sorted().map { sorted[$0] }
        for index in source.sorted(by: >) { sorted.remove(at: index) }
        let insertion = destination - source.filter { $0 < destination }.count
        sorted.insert(contentsOf: moving, at: insertion)
        for index in sorted.indices { sorted[index].position = index }
        next.routines = sorted
        _ = commit(next)
    }

    func complete(_ item: ActionItem, skip: Bool = false) {
        var next = state
        if next.focusSession?.action.id == item.id { next.focusSession = nil }
        if item.kind == .task {
            guard let index = next.tasks.firstIndex(where: { $0.id == item.sourceID && $0.completedAt == nil }) else { return }
            next.tasks[index].completedAt = Date()
            next.tasks[index].snoozedUntil = nil
            if let rule = next.tasks[index].repeatRule, let due = next.tasks[index].dueAt,
               rule == "daily" || rule == "weekly" {
                var copy = next.tasks[index]
                copy.id = UUID(); copy.repeatParentID = item.sourceID
                copy.completedAt = nil; copy.createdAt = Date()
                copy.microsteps = copy.microsteps?.map { SmallStep(title: $0.title) }
                var date = due
                repeat { date = Calendar.current.date(byAdding: .day, value: rule == "daily" ? 1 : 7, to: date)! } while date <= Date()
                copy.dueAt = date
                next.tasks.append(copy)
            }
        } else {
            setRecord(item, state: &next, status: skip ? .skipped : .done, snooze: nil)
        }
        if commit(next) {
            feedback = skip ? "Skipped for today. Tomorrow stays the same." : "Done. One thing less to carry."
            if guidedRoutine, item.kind == .routine {
                focusedItem = state.routines.sorted { $0.position < $1.position }
                    .first { let record = PlannerRules.record($0, on: Date(), in: state); return record?.status == nil && (record?.snoozedUntil ?? .distantPast) <= Date() }
                    .map { PlannerRules.routineAction($0, on: Date(), state: state) }
                if focusedItem == nil { guidedRoutine = false }
            }
        }
    }

    func snooze(_ item: ActionItem, minutes: Int = 10) {
        var next = state
        if next.focusSession?.action.id == item.id { next.focusSession = nil }
        var until = Date().addingTimeInterval(Double(minutes) * 60)
        if item.kind == .task {
            guard let index = next.tasks.firstIndex(where: { $0.id == item.sourceID }) else { return }
            next.tasks[index].snoozedUntil = until
        } else {
            // Today-only snoozes never become tomorrow's reminders.
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))!
            until = min(until, tomorrow.addingTimeInterval(-1))
            setRecord(item, state: &next, status: nil, snooze: until)
        }
        if commit(next) { feedback = "Set aside for a little while." }
    }

    func undoRoutine(_ id: UUID) { _ = commit(PlannerRules.undoRoutine(id, in: state, now: Date())) }
    func rescheduleRoutine(_ id: UUID, to date: Date) -> Bool {
        let next = PlannerRules.rescheduleRoutine(id, to: date, in: state, now: Date())
        guard next != state else { errorMessage = "Choose a future time today for an incomplete step."; return false }
        return commit(next)
    }
    func undoTask(_ task: TaskEntry) {
        var next = state
        guard let index = next.tasks.firstIndex(where: { $0.id == task.id }) else { return }
        next.tasks[index].completedAt = nil
        next.tasks.removeAll { $0.repeatParentID == task.id && $0.completedAt == nil }
        _ = commit(next)
    }

    private func setRecord(_ item: ActionItem, state: inout PlannerState, status: DailyStatus?, snooze: Date?) {
        let key = item.day ?? PlannerRules.dayKey(Date())
        guard key == PlannerRules.dayKey(Date()) else { return }
        let record = DailyRecord(stepID: item.sourceID, day: key, title: item.title,
                                 status: status, snoozedUntil: snooze, updatedAt: Date())
        if let index = state.days.firstIndex(where: { $0.stepID == item.sourceID && $0.day == key }) {
            state.days[index] = record
        } else { state.days.append(record) }
    }

    func enableNotifications() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            await refresh()
        } catch { errorMessage = "Couldn't enable reminders: \(error.localizedDescription)" }
    }

    @discardableResult
    func startFocus(_ item: ActionItem, until: Date, durationBased: Bool = true) -> Bool {
        let now = Date()
        guard until > now, until.timeIntervalSince(now) <= 8 * 3600,
              let current = PlannerRules.currentAction(for: item, in: state, now: now) else {
            errorMessage = "Choose a future finish time within the next eight hours."
            return false
        }
        var next = state
        next.focusSession = FocusSession(action: current, startedAt: now, endsAt: until, durationBased: durationBased)
        return commit(next)
    }

    func stopFocus() {
        var next = state
        next.focusSession = nil
        _ = commit(next)
    }

    func togglePause() {
        var next = state
        guard var timer = next.focusSession, timer.durationBased == true else { return }
        if let remaining = timer.pausedRemaining {
            timer.startedAt = Date(); timer.endsAt = Date().addingTimeInterval(remaining); timer.pausedRemaining = nil
        } else {
            guard timer.endsAt > Date() else { return }
            timer.pausedRemaining = max(1, timer.endsAt.timeIntervalSinceNow)
        }
        next.focusSession = timer; _ = commit(next)
    }

    func toggleSmallStep(taskID: UUID, stepID: UUID) {
        var next = state
        guard let i = next.tasks.firstIndex(where: { $0.id == taskID }),
              let j = next.tasks[i].microsteps?.firstIndex(where: { $0.id == stepID }) else { return }
        next.tasks[i].microsteps?[j].done.toggle(); _ = commit(next)
    }

    func exportData() throws -> Data {
        try JSONEncoder().encode(TransferDocument(state: state))
    }

    /// Always save the outgoing document before a confirmed snapshot replacement.
    func importDocument(_ transfer: TransferDocument) -> Bool {
        do {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("Recovery", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try exportData().write(to: directory.appendingPathComponent("before-import-\(UUID().uuidString).json"), options: [.atomic, .completeFileProtection])
            var imported = transfer.state
            imported.focusSession = nil // A timer belongs to the device that started it.
            return commit(imported)
        } catch { errorMessage = "Import stopped because a recovery backup couldn't be saved. \(error.localizedDescription)"; return false }
    }

    func startLiveActivity() async {
        do {
            try dayActivity.start(state)
            await dayActivity.update(state)
            liveRunning = dayActivity.isRunning
            liveMessage = liveRunning ? "Your current step is on the Lock Screen." : nil
        } catch { liveMessage = error.localizedDescription }
    }

    func stopLiveActivity() async {
        await dayActivity.stop()
        liveRunning = false
        liveMessage = nil
    }

    /// Serialize reconciliations so an older plan can never finish after a newer edit.
    func refresh() async {
        refreshRequested = true
        guard !refreshRunning else { return }
        refreshRunning = true
        defer { refreshRunning = false }
        while refreshRequested {
            refreshRequested = false
            await dayActivity.update(state)
            liveRunning = dayActivity.isRunning
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationStatus = settings.authorizationStatus
            timeSensitiveAvailable = settings.timeSensitiveSetting == .enabled
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                coverageUntil = nil
                continue
            }
            do {
                let plan = PlannerRules.reminderPlan(state, now: Date())
                try await notifications.apply(plan, timeSensitive: state.preferences?.timeSensitive == true && timeSensitiveAvailable)
                coverageUntil = plan.coverageUntil
                scheduledCount = plan.reminders.count
                omittedCount = plan.omittedCount
            } catch {
                coverageUntil = nil
                errorMessage = "Your change is saved, but some reminders couldn't be scheduled. Open reminder settings to retry. \(error.localizedDescription)"
            }
        }
    }

    private func open(_ reference: NotificationReference) {
        selectedTab = 0
        if reference.kind == "task", let task = state.tasks.first(where: { $0.id.uuidString == reference.id && $0.completedAt == nil }) {
            focusedItem = PlannerRules.taskAction(task)
        } else if reference.day == PlannerRules.dayKey(Date()),
                  let step = state.routines.first(where: { $0.id.uuidString == reference.id }),
                  PlannerRules.record(step, on: Date(), in: state)?.status == nil {
            focusedItem = PlannerRules.routineAction(step, on: Date(), state: state)
        }
    }
}
