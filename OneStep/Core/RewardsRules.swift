import Foundation

enum ShieldLeaseRules {
    static func shouldShield(enabled: Bool, expiry: Date?, now: Date) -> Bool {
        enabled && (expiry ?? .distantPast) <= now
    }
    static func monitorEnd(for expiry: Date) -> Date { expiry.addingTimeInterval(2) }
}

/// Account-bound offline outbox. A task or routine-day can earn XP only once.
struct XPCompletion: Codable, Equatable {
    var eventKey: String
    var accountID: String
    var kind: String
    var valid: Bool {
        guard UUID(uuidString: accountID) != nil, eventKey.count <= 90 else { return false }
        let pattern = kind == "task" ? #"^task\.[0-9a-f-]{36}$"# : #"^routine\.[0-9a-f-]{36}\.[0-9]{4}-[0-9]{2}-[0-9]{2}$"#
        return ["task","routine"].contains(kind) && eventKey.range(of: pattern, options: .regularExpression) != nil
    }
}
enum XPRules {
    static func recording(_ item: ActionItem, accountID: String?, in state: PlannerState) -> PlannerState {
        guard let accountID, UUID(uuidString:accountID) != nil else { return state }
        let kind = item.kind.rawValue
        let key = "\(kind).\(item.sourceID.uuidString.lowercased())" + (item.kind == .routine ? ".\(item.day ?? "")" : "")
        let event = XPCompletion(eventKey:key, accountID:accountID.lowercased(), kind:kind)
        var next = state; var events = next.xpCompletions ?? []
        guard event.valid, events.count < 10000, !events.contains(where: { $0.eventKey == key && $0.accountID == event.accountID }) else { return state }
        events.append(event); next.xpCompletions = events; return next
    }
}
