import ActivityKit
import WidgetKit
import SwiftUI

@main
struct OneStepLiveBundle: WidgetBundle {
    var body: some Widget { OneStepDayActivity(); OneStepShortcutsWidget(); OneStepNextActionWidget() }
}

struct OneStepDayActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DayActivityAttributes.self) { context in
            DayActivityView(context: context)
                .activityBackgroundTint(Color(uiColor: .systemBackground))
                .activitySystemActionForegroundColor(.primary)
                .widgetURL(URL(string: "onestep://now"))
        } dynamicIsland: { context in
            let palette = ItemPalette.resolve(context.state.colorName, routine: context.state.isRoutine)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("OneStep", systemImage: "sparkle").foregroundStyle(palette.color)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.totalSteps > 0 { Text("\(context.state.completedSteps)/\(context.state.totalSteps)").monospacedDigit() }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.state.title).font(.headline).lineLimit(2)
                        if let detail=context.state.detail { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).privacySensitive() }
                        LiveActivityTime(state: context.state)
                        if let left=context.state.tasksRemaining { Text("Tasks left: " + String(left)).font(.caption2).foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: context.state.isRoutine ? "sunrise.fill" : "sparkle").foregroundStyle(palette.color)
            } compactTrailing: {
                if context.state.timerPausedRemaining != nil { Image(systemName:"pause.fill").foregroundStyle(palette.color) }
                else if let start = context.state.timerStartedAt, let end = context.state.timerEndsAt {
                    Text(timerInterval: start...max(start, end), countsDown: true).monospacedDigit().frame(maxWidth: 64)
                } else { Image(systemName: "checkmark.circle").foregroundStyle(palette.color) }
            } minimal: {
                Image(systemName: "sparkle").foregroundStyle(palette.color)
            }
            .widgetURL(URL(string: "onestep://now"))
            .keylineTint(palette.color)
        }
    }
}

private struct DayActivityView: View {
    let context:ActivityViewContext<DayActivityAttributes>
    var body:some View { DayActivityCard(state:context.state,dayLabel:context.attributes.dayLabel,isStale:context.isStale) }
}

private struct ShortcutEntry: TimelineEntry { let date: Date }
private struct ShortcutProvider: TimelineProvider {
    func placeholder(in context: Context) -> ShortcutEntry { ShortcutEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (ShortcutEntry) -> Void) { completion(placeholder(in: context)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ShortcutEntry>) -> Void) { completion(Timeline(entries: [placeholder(in: context)], policy: .never)) }
}
private struct OneStepShortcutsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OneStepShortcuts", provider: ShortcutProvider()) { _ in ShortcutsWidgetView() }
            .configurationDisplayName("OneStep shortcuts")
            .description("Open your next action, routines, a new task, or focus timer. Private tasks stay inside OneStep.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
private struct ShortcutsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("OneStep", systemImage: "sparkle").font(.headline).foregroundStyle(ItemPalette.violet.color)
            if family == .systemSmall {
                Text("One thing at a time.").font(.subheadline)
                Label("Open Now", systemImage: "arrow.up.right")
            } else {
                HStack(spacing: 18) {
                    Link(destination: URL(string: "onestep://now")!) { Label("Now", systemImage: "sparkle") }
                    Link(destination: URL(string: "onestep://routines")!) { Label("Routine", systemImage: "sunrise") }
                    Link(destination: URL(string: "onestep://add")!) { Label("Add", systemImage: "plus") }
                    Link(destination: URL(string: "onestep://timer")!) { Label("Timer", systemImage: "timer") }
                }.font(.caption).labelStyle(.titleAndIcon)
            }
        }.containerBackground(.fill.tertiary, for: .widget)
            .widgetURL(URL(string: "onestep://now"))
    }
}

private struct NextProvider: TimelineProvider {
    func placeholder(in context: Context) -> ShortcutEntry { ShortcutEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (ShortcutEntry) -> Void) { completion(placeholder(in: context)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ShortcutEntry>) -> Void) { completion(Timeline(entries: [placeholder(in: context)], policy: .after(Date().addingTimeInterval(900)))) }
}
private struct OneStepNextActionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OneStepNextAction", provider: NextProvider()) { _ in
            VStack(alignment: .leading, spacing: 10) {
                Label("OneStep", systemImage: "sparkle").font(.headline)
                Text(WidgetSnapshotStore.read()?.title ?? "Open OneStep for your next action").font(.headline).privacySensitive()
                if let snapshot = WidgetSnapshotStore.read() { Text("Updated \(snapshot.at, style: .relative) ago").font(.caption) }
                else { Text("Open to refresh").font(.caption) }
            }.containerBackground(.fill.tertiary, for: .widget).widgetURL(URL(string: "onestep://now"))
        }.configurationDisplayName("Next action").description("An optional private snapshot, shared only by a provisioned OneStep app.").supportedFamilies([.systemSmall,.systemMedium])
    }
}
