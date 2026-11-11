import SwiftUI

struct FocusTimerSheet: View {
    @Environment(PlannerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let item: ActionItem
    @State private var minutes = 15
    @State private var useFinishTime = false
    @State private var finishAt = Date().addingTimeInterval(900)
    @State private var showLive = true
    @State private var confirmReplacement = false
    private var palette: ItemPalette { .resolve(item.colorName, routine: item.kind == .routine) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(item.title, systemImage: "timer").font(.headline).foregroundStyle(palette.color)
                    Text("Give this one thing a little space. Your task's due time stays unchanged.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section("How much time?") {
                    Toggle("Finish at a specific time", isOn: $useFinishTime)
                    if useFinishTime {
                        DatePicker("Finish by", selection: $finishAt, in: Date()...Date().addingTimeInterval(8 * 3600))
                        if let due = item.scheduledAt, due > Date(), due.timeIntervalSinceNow <= 8 * 3600 {
                            Button("Use this item's scheduled time") { finishAt = due }
                        }
                    } else {
                        Picker("Minutes", selection: $minutes) {
                            ForEach([5, 10, 15, 25, 45, 60], id: \.self) { value in Text("\(value) minutes").tag(value) }
                        }.pickerStyle(.wheel)
                    }
                }
                Section {
                    Toggle("Show on Lock Screen", isOn: $showLive)
                    Text("The countdown continues while the app is closed. An expiry notification needs reminder permission. A Live Activity session can last up to eight hours.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if store.state.focusSession != nil {
                        Text("Starting this timer will replace your current timer.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Button("Start focus") {
                        if store.state.focusSession != nil { confirmReplacement = true } else { start() }
                    }.font(.headline)
                }
                if let error = store.errorMessage { Section { Text(error).font(.footnote) } }
            }
            .navigationTitle("A little focus time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .confirmationDialog("Replace your current timer?", isPresented: $confirmReplacement, titleVisibility: .visible) {
                Button("Replace timer") { start() }
                Button("Keep current timer", role: .cancel) { }
            }
        }.tint(palette.color)
    }

    private func start() {
        let end = useFinishTime ? finishAt : Date().addingTimeInterval(Double(minutes) * 60)
        guard store.startFocus(item, until: end, durationBased: !useFinishTime) else { return }
        Task {
            if store.notificationStatus == .notDetermined { await store.enableNotifications() }
            if showLive { await store.startLiveActivity() }
        }
        dismiss()
    }
}
