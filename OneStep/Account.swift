import Foundation
import Observation

/// Optional hosted identity only. Planner data is never sent to this service.
@MainActor @Observable final class OnlineAccount {
    var projectURL = UserDefaults.standard.string(forKey: "authURL") ?? ""
    var publicKey = UserDefaults.standard.string(forKey: "authPublicKey") ?? ""
    var email = ""
    var code = ""
    var message = ""
    var busy = false

    func request(_ path: String, body: [String: String]) async throws -> [String: Any] {
        guard let url = URL(string: projectURL), url.scheme == "https", let host = url.host,
              host.hasSuffix(".supabase.co"), !publicKey.isEmpty,
              !publicKey.hasPrefix("sb_secret_") else { throw TransferError.invalid }
        var request = URLRequest(url: url.appendingPathComponent("auth/v1/\(path)"))
        request.httpMethod = "POST"; request.timeoutInterval = 20
        request.setValue(publicKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
            throw NSError(domain: "OneStep", code: 1, userInfo: [NSLocalizedDescriptionKey: "Sign-in failed. Check the project settings, email code, and service availability."])
        }
        return (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    func sendCode() async {
        busy = true; defer { busy = false }
        do {
            _ = try await request("otp", body: ["email": email])
            UserDefaults.standard.set(projectURL, forKey: "authURL"); UserDefaults.standard.set(publicKey, forKey: "authPublicKey")
            message = "Check your email for the code. The Supabase email template must include the token."
        } catch { message = error.localizedDescription }
    }

    func verify(store: PlannerStore) async {
        busy = true; defer { busy = false }
        do {
            let result = try await request("verify", body: ["email": email, "token": code, "type": "email"])
            guard let user = result["user"] as? [String: Any], let id = user["id"] as? String, let uuid = UUID(uuidString: id) else { throw TransferError.invalid }
            var next = store.state; next.profile = LocalProfile(id: uuid, name: email)
            if store.commit(next) { message = "Account verified. Your planner stays local; sign-in does not upload or sync it." }
            // No access/refresh tokens persisted: offline profile is sufficient for this beta.
        } catch { message = error.localizedDescription }
    }
}
