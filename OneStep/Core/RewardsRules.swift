import Foundation

enum ShieldLeaseRules {
    static func shouldShield(enabled: Bool, expiry: Date?, now: Date) -> Bool {
        enabled && (expiry ?? .distantPast) <= now
    }
    static func monitorEnd(for expiry: Date) -> Date { expiry.addingTimeInterval(2) }
}
