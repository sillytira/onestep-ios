import Foundation

/// Shared file/LAN format. Dates use Swift's seconds since 2001-01-01 UTC.
struct TransferDocument: Codable {
    var format = "OneStep"
    var formatVersion = 1
    var exportedAt = Date()
    var state: PlannerState

    static func decode(_ data: Data) throws -> TransferDocument {
        guard data.count <= 8 * 1024 * 1024 else { throw TransferError.invalid }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.format == "OneStep", value.formatVersion == 1, value.state.schemaVersion == 1,
              value.state.tasks.count <= 10000, value.state.routines.count <= 1000,
              Set(value.state.tasks.map(\.id)).count == value.state.tasks.count,
              Set(value.state.routines.map(\.id)).count == value.state.routines.count,
              value.state.routines.allSatisfy({ (0...23).contains($0.hour) && (0...59).contains($0.minute) }) else { throw TransferError.invalid }
        return value
    }
}

enum TransferError: LocalizedError {
    case invalid
    var errorDescription: String? { "This isn't a supported OneStep backup or transfer. Nothing was replaced." }
}
