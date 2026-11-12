import Foundation

enum AppRoute: String, Equatable {
    case now, routines, add, timer, bank, space
    init?(url: URL) {
        guard url.scheme?.lowercased() == "onestep", let host = url.host?.lowercased(), let route = Self(rawValue: host) else { return nil }
        self = route
    }
    var tab: Int {
        switch self {
        case .now, .timer: return 0
        case .add: return 1
        case .routines: return 2
        case .bank: return 3
        case .space: return 4
        }
    }
}
