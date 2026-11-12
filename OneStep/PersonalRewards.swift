import Foundation
import CryptoKit
import Observation

@MainActor @Observable final class PersonalRewards {
    static let shared = PersonalRewards()
    var message = ""
    private var busy = false
    private func syncXP(_ state: PlannerState, account: RewardsStore) async {
        guard account.signedIn, let user = account.userID else { return }
        let storage = "xp.receipts.\(user)"
        var saved = RewardsVault.read(storage).flatMap { (try? JSONSerialization.jsonObject(with:$0)) as? [String:Double] } ?? [:]
        for event in (state.xpCompletions ?? []).filter({ $0.accountID.lowercased() == user.lowercased() && $0.valid }) {
            guard account.userID == user else { break }
            if saved[event.eventKey] == -1 || (saved[event.eventKey] ?? 0) > Date().timeIntervalSince1970 { continue }
            do {
                let value = try await account.rpc("onestep_claim_xp",["event_key":event.eventKey,"event_kind":event.kind]) as? [String:Any]
                guard account.userID == user else { break }
                saved[event.eventKey] = value?["status"] as? String == "pending" ? Date().timeIntervalSince1970+60 : -1
                try RewardsVault.write(storage,JSONSerialization.data(withJSONObject:saved))
            } catch { message = "Planner saved. XP will retry when its service is available."; break }
        }
    }
    func sync(_ state: PlannerState) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        let account = RewardsStore.shared
        await account.load()
        await syncXP(state, account: account)
        guard account.signedIn, let user = account.userID, account.kind != "kids" else { return }
        let storage = "personal.receipts.\(user)"
        var receipts = RewardsVault.read(storage).flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: [String: Any]] } ?? [:]
        let tasks = state.tasks.filter { $0.rewardAccountID?.lowercased() == user.lowercased() && $0.rewardPoints != nil && $0.archived != true }.sorted { $0.createdAt > $1.createdAt }.prefix(100)
        for task in tasks {
            guard account.userID?.lowercased() == user.lowercased() else { break }
            let id = task.id.uuidString
            if receipts[id]?["done"] as? Bool == true { continue }
            if (receipts[id]?["retry"] as? Double ?? 0) > Date().timeIntervalSince1970 { continue }
            guard let points = task.rewardPoints, (0...100).contains(points), task.title.count >= 3 else { continue }
            let hash = SHA256.hash(data: Data("\(task.title)|\(points)".utf8)).map { String(format: "%02x", $0) }.joined()
            do {
                if receipts[id]?["hash"] as? String != hash {
                    _ = try await account.rpc("onestep_register_personal_task", ["client": id, "task_title": task.title, "task_points": points])
                    receipts[id] = ["hash": hash]
                }
                guard account.userID?.lowercased() == user.lowercased() else { break }
                if task.completedAt != nil, let result = try await account.rpc("onestep_complete_personal_task", ["client": id]) as? [String: Any] {
                    let pending = result["status"] as? String == "pending"
                    receipts[id]?["done"] = !pending
                    receipts[id]?["retry"] = Date().timeIntervalSince1970 + 60
                    message = pending ? "Done locally. Points are waiting for the server's anti-spam check." : "Last reward: \((result["points"] as? NSNumber)?.intValue ?? 0) points · \(result["status"] as? String ?? "recorded")."
                }
            } catch {
                receipts[id, default: [:]]["retry"] = Date().timeIntervalSince1970 + 60
                message = "Your planner is saved. Account reward sync will retry while open: \(error.localizedDescription)"
                break
            }
            try? RewardsVault.write(storage, JSONSerialization.data(withJSONObject: receipts))
        }
        let keep = Set(tasks.map { $0.id.uuidString }); receipts = receipts.filter { keep.contains($0.key) }
        try? RewardsVault.write(storage, JSONSerialization.data(withJSONObject: receipts))
    }
}
