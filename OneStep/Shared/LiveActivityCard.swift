import SwiftUI
import ActivityKit
import WidgetKit
import AppIntents

/// Shared with the app so simulator tests render the same Lock Screen card.
struct DayActivityCard: View {
    let state: DayActivityAttributes.ContentState
    let dayLabel: String
    var isStale = false
    private var palette: ItemPalette { .resolve(state.colorName, routine:state.isRoutine) }
    var body: some View {
        ViewThatFits(in:.vertical) {
            card(compact:false)
            card(compact:true)
        }.frame(maxHeight:160)
    }
    private func card(compact: Bool) -> some View {
        VStack(alignment:.leading,spacing:5) {
            HStack(spacing:8) {
                Label(compact ? "OneStep" : (isStale ? "OneStep \u{00B7} refresh" : "OneStep \u{00B7} \(dayLabel)"),systemImage:state.isRoutine ? "sunrise.fill" : "sparkle")
                    .font(.caption2.weight(.semibold)).foregroundStyle(palette.color).lineLimit(1)
                Spacer(minLength:4)
                LiveActivityTime(state:state).layoutPriority(1)
            }
            Text(state.title).font(.subheadline.weight(.semibold)).lineLimit(compact ? 1 : 2).privacySensitive()
            if !compact, let detail=state.detail, !detail.isEmpty {
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).privacySensitive()
            }
            if !compact { HStack(spacing:8) {
                if let done=state.tasksDone, let left=state.tasksRemaining {
                    Text("\(done) tasks done \u{00B7} \(left) left").lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength:0)
                if state.totalSteps>0 {
                    Text("Routine \(state.completedSteps)/\(state.totalSteps)\((state.skippedSteps ?? 0)>0 ? " \u{00B7} \(state.skippedSteps!) skipped" : "")")
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            }.font(.caption2).foregroundStyle(.secondary) }
            HStack(spacing:10) {
                if let id=state.actionID {
                    Button(intent:DayActionIntent(id)) { Text("Done").lineLimit(1).frame(minHeight:32) }.tint(ItemPalette.mint.color)
                    Button(intent:DayActionIntent(id,snooze:true)) { Text(compact ? "Snooze" : "Snooze \(state.snoozeMinutes ?? 10)m").lineLimit(1).frame(minHeight:32) }
                        .tint(ItemPalette.amber.color)
                        .accessibilityLabel("Snooze \(state.snoozeMinutes ?? 10) minutes")
                }
                Spacer(minLength:0)
                if !compact, state.totalSteps>0 {
                    GeometryReader { proxy in
                        let fraction=min(1,max(0,Double(state.completedSteps+(state.skippedSteps ?? 0))/Double(max(1,state.totalSteps))))
                        ZStack(alignment:.leading) {
                            Capsule().fill(Color.secondary.opacity(0.25))
                            Capsule().fill(ItemPalette.mint.color).frame(width:proxy.size.width*fraction)
                        }
                    }.frame(width:70,height:4)
                    .accessibilityElement().accessibilityLabel("Routine steps resolved").accessibilityValue("\(state.completedSteps) done, \(state.skippedSteps ?? 0) skipped, \(state.totalSteps) total")
                }
            }.buttonStyle(.bordered).controlSize(.small).font(.subheadline.weight(.semibold)).frame(minHeight:32)
        }.padding(10)
            .overlay(alignment:.leading) { RoundedRectangle(cornerRadius:3).fill(palette.color).frame(width:3).padding(.vertical,12) }
    }
}

struct LiveActivityTime: View {
    let state: DayActivityAttributes.ContentState
    var body: some View {
        Group {
            if let remaining=state.timerPausedRemaining {
                Label("Paused \(Int(max(0,remaining))/60):\(String(format:"%02d",Int(max(0,remaining))%60))",systemImage:"pause.fill")
            } else if let start=state.timerStartedAt, let end=state.timerEndsAt {
                HStack(spacing:3) { Image(systemName:"timer");Text(timerInterval:start...max(start,end),countsDown:true).frame(maxWidth:72) }
            } else if let due=state.scheduledAt {
                HStack(spacing:3) { Image(systemName:"clock");Text(due,style:.time) }
            } else { Text(state.isRoutine ? "Daily routine" : "Next action") }
        }.font(.caption.weight(.medium)).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
    }
}

