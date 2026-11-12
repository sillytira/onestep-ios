import ActivityKit
import WidgetKit
import SwiftUI

@main
struct OneStepLiveBundle: WidgetBundle {
    var body: some Widget { OneStepDayActivity(); OneStepShortcutsWidget() }
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
                        ActivityCountdown(state: context.state)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: context.state.isRoutine ? "sunrise.fill" : "sparkle").foregroundStyle(palette.color)
            } compactTrailing: {
                if let start = context.state.timerStartedAt, let end = context.state.timerEndsAt {
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
    let context: ActivityViewContext<DayActivityAttributes>
    private var palette: ItemPalette { .resolve(context.state.colorName, routine: context.state.isRoutine) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("OneStep · \(context.attributes.dayLabel)", systemImage: "sparkle")
                    .font(.caption.weight(.semibold)).foregroundStyle(palette.color)
                Spacer()
                if context.isStale { Text("Tap to refresh").font(.caption).foregroundStyle(.secondary) }
            }
            HStack(alignment: .top, spacing: 12) {
                ColorBadge(palette: palette, symbol: context.state.isRoutine ? "sunrise.fill" : "checklist")
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.state.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                    Text(context.state.subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            ActivityCountdown(state: context.state)
            Text("Updated \(context.state.snapshotAt, style: .relative) ago").font(.caption2).foregroundStyle(.secondary)
            if let id = context.state.actionID {
                HStack {
                    Button("Done", intent: DayActionIntent(id)).tint(ItemPalette.mint.color)
                    Button("Snooze", intent: DayActionIntent(id, snooze: true)).tint(ItemPalette.amber.color)
                }.buttonStyle(.bordered)
            }
            if context.state.totalSteps > 0 {
                HStack(spacing: 12) {
                    ProgressView(value: Double(context.state.completedSteps), total: Double(max(1, context.state.totalSteps)))
                        .tint(ItemPalette.mint.color)
                    Text("\(context.state.completedSteps)/\(context.state.totalSteps) routine steps")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 3).fill(palette.color).frame(width: 4).padding(.vertical, 16) }
    }
}

private struct ActivityCountdown: View {
    let state: DayActivityAttributes.ContentState
    var body: some View {
        if let start = state.timerStartedAt, let end = state.timerEndsAt {
            HStack {
                Label("Focus time", systemImage: "timer").font(.caption)
                Spacer()
                Text(timerInterval: start...max(start, end), countsDown: true).font(.title3.bold()).monospacedDigit()
            }.foregroundStyle(ItemPalette.resolve(state.colorName).color)
        } else if let due = state.scheduledAt {
            HStack {
                Label("Scheduled", systemImage: "clock").font(.caption)
                Spacer()
                Text(due, style: .time).font(.subheadline.weight(.semibold))
            }.foregroundStyle(.secondary)
        }
    }
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
