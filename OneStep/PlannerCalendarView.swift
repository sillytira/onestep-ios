import SwiftUI

struct PlannerCalendarView: View {
    @Environment(PlannerStore.self) private var store
    let edit: (TaskEntry) -> Void
    @State private var selected = Date()
    @State private var mode = "month"
    @State private var archived = false
    private var calendar: Calendar { var c = Calendar.current; c.firstWeekday = 2; return c }
    private var days: [Date] {
        let c = calendar
        if mode == "month" { let start = c.date(from:c.dateComponents([.year,.month],from:selected))!; return c.range(of:.day,in:.month,for:selected)!.map { c.date(byAdding:.day,value:$0-1,to:start)! } }
        if mode == "week" { let weekday = (c.component(.weekday,from:selected)+5)%7; let start = c.date(byAdding:.day,value: -weekday,to:c.startOfDay(for:selected))!; return (0..<7).map { c.date(byAdding:.day,value:$0,to:start)! } }
        return [selected]
    }
    private func tasks(_ date: Date) -> [TaskEntry] { store.state.tasks.filter { (archived || $0.archived != true) && $0.dueAt.map { calendar.isDate($0,inSameDayAs:date) } == true }.sorted { $0.dueAt! < $1.dueAt! } }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                Picker("Calendar view",selection:$mode) { Text("Day").tag("day");Text("Week").tag("week");Text("Month").tag("month") }.pickerStyle(.segmented)
                HStack {
                    Button("Previous",systemImage:"chevron.left") { shift(-1) }.labelStyle(.iconOnly)
                    Spacer();Text(selected,format:.dateTime.month(.wide).year()).font(.title2.bold());Spacer()
                    Button("Next",systemImage:"chevron.right") { shift(1) }.labelStyle(.iconOnly)
                }
                if mode == "month" {
                    LazyVGrid(columns:Array(repeating:GridItem(.flexible()),count:7)) {
                        ForEach(0..<((calendar.component(.weekday,from:days[0])+5)%7),id:\.self) { _ in Color.clear.frame(height:40) }
                        ForEach(days,id:\.self) { day in
                            Button { selected = day } label: {
                                VStack(spacing:5) { Text("\(calendar.component(.day,from:day))"); Circle().fill(tasks(day).isEmpty ? .clear : ItemPalette.mint.color).frame(width:5,height:5) }
                                    .frame(maxWidth:.infinity,minHeight:42).background(calendar.isDate(day,inSameDayAs:selected) ? ItemPalette.violet.color.opacity(0.25) : .clear,in:RoundedRectangle(cornerRadius:12))
                            }.buttonStyle(.plain).accessibilityLabel(day.formatted(date:.complete,time:.omitted))
                        }
                    }
                }
                if mode == "week" {
                    ScrollView(.horizontal) { HStack { ForEach(days,id:\.self) { day in
                        Button { selected = day } label: { VStack { Text(day,format:.dateTime.weekday(.abbreviated));Text(day,format:.dateTime.day()) }.padding(12).background(calendar.isDate(day,inSameDayAs:selected) ? ItemPalette.violet.color.opacity(0.25) : .clear,in:RoundedRectangle(cornerRadius:12)) }
                    } } }
                }
                Text(selected,format:.dateTime.weekday(.wide).day().month()).font(.headline)
                Toggle("Include archived tasks",isOn:$archived)
                if tasks(selected).isEmpty { Text("No tasks due this day.").foregroundStyle(.secondary) }
                ForEach(tasks(selected)) { task in taskRow(task) }
                Text("Daily routines").font(.headline)
                ForEach(store.state.routines.sorted { $0.position < $1.position }) { step in
                    HStack { Image(systemName:PlannerRules.record(step,on:selected,in:store.state)?.status == .done ? "checkmark.circle.fill":"sunrise");Text(step.title);Spacer();Text(PlannerRules.scheduledTime(step,on:selected),style:.time) }.padding().background(.quaternary,in:RoundedRectangle(cornerRadius:16))
                }
                Text("Tasks without a due date").font(.headline)
                ForEach(store.state.tasks.filter { $0.dueAt == nil && (archived || $0.archived != true) }) { task in taskRow(task) }
            }.padding()
        }.navigationTitle("Planner").toolbar { Button("Today") { selected = Date() } }
    }
    private func shift(_ direction: Int) { selected = calendar.date(byAdding:mode == "month" ? .month:.day,value:direction*(mode == "week" ? 7:1),to:mode == "month" ? calendar.date(from:calendar.dateComponents([.year,.month],from:selected))!:selected)! }
    private func taskRow(_ task: TaskEntry) -> some View {
        Button { edit(task) } label: { HStack { Image(systemName:task.completedAt == nil ? "circle":"checkmark.circle.fill"); VStack(alignment:.leading) { Text(task.title);if let due = task.dueAt { Text(due,style:.time).font(.caption) } };Spacer();if let points = task.rewardPoints { Text("\(points) pt").font(.caption.bold()) } }.padding().frame(maxWidth:.infinity,alignment:.leading).background(ItemPalette.blue.color.opacity(0.1),in:RoundedRectangle(cornerRadius:18)) }.buttonStyle(.plain)
    }
}
