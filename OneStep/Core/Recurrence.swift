import Foundation

enum RecurrenceRules {
    static func valid(_ task: TaskEntry) -> Bool {
        guard ["none","daily","weekly","monthly","weekdays"].contains(task.repeatRule ?? "none"), (1...365).contains(task.repeatEvery ?? 1), (1...31).contains(task.repeatMonthDay ?? 1) else { return false }
        if let days = task.repeatWeekdays { return !days.isEmpty && days.count <= 7 && days.allSatisfy { (1...7).contains($0) } }
        return true
    }
    static func next(_ task: TaskEntry, now: Date, calendar: Calendar = .current) -> Date? {
        guard valid(task), let due = task.dueAt, let rule = task.repeatRule, rule != "none" else { return nil }
        let every = task.repeatEvery ?? 1, anchor = task.repeatAnchor ?? due
        let clock = calendar.dateComponents([.hour,.minute,.second], from: due)
        func on(_ day: Date) -> Date { calendar.date(bySettingHour:clock.hour!, minute:clock.minute!,second:clock.second!,of:day,matchingPolicy:.nextTime,repeatedTimePolicy:.first,direction:.forward)! }
        if rule == "monthly" {
            let a = calendar.dateComponents([.year,.month,.day], from:anchor), n = calendar.dateComponents([.year,.month], from:now)
            let delta = (n.year!-a.year!)*12+n.month!-a.month!
            let start = max(0,delta/every)
            for i in start...(start+2) {
                let first = calendar.date(from:DateComponents(year:a.year,month:a.month!+i*every,day:1))!
                let last = calendar.range(of:.day,in:.month,for:first)!.count
                let day = calendar.date(byAdding:.day,value:min(task.repeatMonthDay ?? a.day!,last)-1,to:first)!
                let candidate = on(day)
                if candidate > now && candidate > due { return candidate }
            }
            return nil
        }
        if rule == "weekdays" {
            let weekday = (calendar.component(.weekday,from:anchor)+5)%7+1
            let monday = calendar.date(byAdding:.day,value:1-weekday,to:calendar.startOfDay(for:anchor))!
            let start = calendar.startOfDay(for:max(due,now))
            for i in 0..<(every*7+8) {
                let day = calendar.date(byAdding:.day,value:i,to:start)!, candidate = on(day)
                let difference = calendar.dateComponents([.day],from:monday,to:day).day!
                if (task.repeatWeekdays ?? [1,2,3,4,5]).contains((calendar.component(.weekday,from:day)+5)%7+1), (difference/7)%every == 0, candidate > now, candidate > due { return candidate }
            }
            return nil
        }
        let days = every*(rule == "weekly" ? 7:1)
        let elapsed = calendar.dateComponents([.day],from:calendar.startOfDay(for:due),to:calendar.startOfDay(for:now)).day!
        let steps = max(1,elapsed/days)
        var candidate = on(calendar.date(byAdding:.day,value:steps*days,to:due)!)
        if candidate <= now { candidate = on(calendar.date(byAdding:.day,value:(steps+1)*days,to:due)!) }
        return candidate
    }
}
