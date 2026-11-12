import Foundation

/// A deliberately small data format: no scripts, HTML, URLs, or executable code.
struct ContentCatalog: Codable, Equatable {
    var format: String
    var schema: Int
    var revision: Int
    var minAppVersion: String
    var message: String
    var packs: [ContentPack]
    func validated() throws -> Self {
        let version = minAppVersion.split(separator: ".", omittingEmptySubsequences: false).compactMap { Int($0) }
        let compatible = minAppVersion.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression) != nil && version.count == 3 && version.allSatisfy { $0 >= 0 } && version.lexicographicallyPrecedes([0, 6, 1])
        guard format == "OneStepContent", schema == 1, revision > 0,
              message.count <= 500, packs.count <= 50,
              Set(packs.map(\.id)).count == packs.count,
              compatible else { throw ContentError.invalid }
        for pack in packs {
            guard !pack.id.isEmpty, pack.id.count <= 60, pack.id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }),
                  !pack.title.isEmpty, pack.title.count <= 100, pack.description.count <= 500,
                  !pack.steps.isEmpty, pack.steps.count <= 30 else { throw ContentError.invalid }
            for step in pack.steps {
                guard !step.title.isEmpty, step.title.count <= 200, (0...23).contains(step.hour), (0...59).contains(step.minute),
                      ["blue", "violet", "mint", "coral", "rose", "amber"].contains(step.colorName) else { throw ContentError.invalid }
            }
        }
        return self
    }
    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 64 * 1024 else { throw ContentError.invalid }
        return try JSONDecoder().decode(Self.self, from: data).validated()
    }
    func installing(_ pack: ContentPack, in original: PlannerState) -> PlannerState {
        var state = original
        guard packs.contains(pack), state.contentPacks?.contains(pack.id) != true, state.routines.count + pack.steps.count <= 1000 else { return state }
        var position = (state.routines.map(\.position).max() ?? -1) + 1
        for step in pack.steps {
            state.routines.append(RoutineStep(title: step.title, hour: step.hour, minute: step.minute, position: position, colorName: step.colorName))
            position += 1
        }
        state.contentPacks = (state.contentPacks ?? []) + [pack.id]
        return state
    }
}
struct ContentPack: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var description: String
    var steps: [ContentStep]
}
struct ContentStep: Codable, Equatable {
    var title: String
    var hour: Int
    var minute: Int
    var colorName: String
}
enum ContentError: Error { case invalid }
