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
    private(set) var state: PlannerState
    var errorMessage: String?
    var notificationStatus: UNAuthorizationStatus = .notDetermined
    var coverageUntil: Date?
    var scheduledCount = 0
    var omittedCount = 0
    var focusedItem: ActionItem?
    var selectedTab = 0
    var feedback: String?

    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let document: PlannerDocument
    @ObservationIgnored private let notifications = NotificationScheduler()
    @ObservationIgnored private let delegate = NotificationDelegate()
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
            state = PlannerState()
            document = PlannerDocument(payload: try JSONEncoder().encode(state))
            context.insert(document)
            try context.save()
        }
        delegate.onOpen = { [weak self] reference in self?.open(reference) }
        UNUserNotificationCenter.current().delegate = delegate
    }

    enum StoreError: LocalizedError {
        case newerSchema
        var errorDescription: String? { "This data was saved by a newer version. Install that version to continue. Your data has not been reset." }
    }

    @discardableResult
    private func commit(_ next: PlannerState) -> Bool {
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
    func saveTask(id: UUID?, title: String, notes: String, dueAt: Date?, reminder: Bool) -> Bool {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return false }
        var next = state
        if let id, let index = next.tasks.firstIndex(where: { $0.id == id }) {
            next.tasks[index].title = cleanTitle
            next.tasks[index].notes = notes
            next.tasks[index].dueAt = dueAt
            next.tasks[index].reminderEnabled = dueAt != nil && reminder
            next.tasks[index].snoozedUntil = nil
        } else {
            next.tasks.append(TaskEntry(title: cleanTitle, notes: notes, dueAt: dueAt,
                                        reminderEnabled: dueAt != nil && reminder))
        }
        return commit(next)
    }

    @discardableResult
    func saveRoutine(id: UUID?, title: String, time: Date) -> Bool {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return false }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        var next = state
        if let id, let index = next.routines.firstIndex(where: { $0.id == id }) {
            next.routines[index].title = cleanTitle
            next.routines[index].hour = parts.hour!
            next.routines[index].minute = parts.minute!
            // Editing a schedule also clears today's old snooze, but keeps completed history.
            let key = PlannerRules.dayKey(Date())
            if let recordIndex = next.days.firstIndex(where: { $0.stepID == id && $0.day == key }) {
                next.days[recordIndex].snoozedUntil = nil
            }
        } else {
            let position = (next.routines.map(\.position).max() ?? -1) + 1
            next.routines.append(RoutineStep(title: cleanTitle, hour: parts.hour!, minute: parts.minute!, position: position))
        }
        return commit(next)
    }

    func deleteTask(_ task: TaskEntry) {
        var next = state
        next.tasks.removeAll { $0.id == task.id }
        _ = commit(next)
    }

    func deleteRoutine(_ step: RoutineStep) {
        var next = state
        next.routines.removeAll { $0.id == step.id }
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
        if item.kind == .task {
            guard let index = next.tasks.firstIndex(where: { $0.id == item.sourceID }) else { return }
            next.tasks[index].completedAt = Date()
            next.tasks[index].snoozedUntil = nil
        } else {
            setRecord(item, state: &next, status: skip ? .skipped : .done, snooze: nil)
        }
        if commit(next) { feedback = skip ? "Skipped for today. Tomorrow stays the same." : "Done. One thing less to carry." }
    }

    func snooze(_ item: ActionItem, minutes: Int = 10) {
        var next = state
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

    func undoTask(_ task: TaskEntry) {
        var next = state
        guard let index = next.tasks.firstIndex(where: { $0.id == task.id }) else { return }
        next.tasks[index].completedAt = nil
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

    /// Serialize reconciliations so an older plan can never finish after a newer edit.
    func refresh() async {
        refreshRequested = true
        guard !refreshRunning else { return }
        refreshRunning = true
        defer { refreshRunning = false }
        while refreshRequested {
            refreshRequested = false
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationStatus = settings.authorizationStatus
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                coverageUntil = nil
                continue
            }
            do {
                let plan = PlannerRules.reminderPlan(state, now: Date())
                try await notifications.apply(plan)
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
