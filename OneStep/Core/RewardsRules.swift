import Foundation

enum AccountSessionRules {
    static let reconnectMessage = "Your sign-in session expired. Open Bank → Account → Reconnect this account. Your planner, pending XP and family link are kept."
    static func token(_ value: Any?) -> String? {
        guard let text = value as? String, !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { return nil }; return text
    }
    static func claims(_ session: [String:Any]?) -> [String:Any] {
        guard let access = token(session?["access_token"]),access.utf8.count <= 16384 else { return [:] }
        let parts = access.components(separatedBy:".");guard parts.count == 3 else { return [:] }
        var text = parts[1].replacingOccurrences(of:"-",with:"+").replacingOccurrences(of:"_",with:"/")
        text += String(repeating:"=",count:(4-text.count%4)%4)
        guard let data = Data(base64Encoded:text) else { return [:] }
        return (try? JSONSerialization.jsonObject(with:data)) as? [String:Any] ?? [:]
    }
    // Hints are used for local identity/expiry, never to grant server permissions.
    static func userID(_ session: [String:Any]?) -> String? { token((session?["user"] as? [String:Any])?["id"]) ?? token(claims(session)["sub"]) }
    static func email(_ session: [String:Any]?) -> String? { token((session?["user"] as? [String:Any])?["email"]) ?? token(claims(session)["email"]) }
    static func expiry(_ session: [String:Any]?) -> Double {
        let value = (session?["expires_at"] ?? claims(session)["exp"]) as? NSNumber
        let seconds = value?.doubleValue ?? 0;return seconds.isFinite ? seconds:0
    }
    static func validated(_ response: Any) throws -> [String:Any] {
        guard var result = response as? [String:Any],token(result["access_token"]) != nil,token(result["refresh_token"]) != nil,
              token((result["user"] as? [String:Any])?["id"]) != nil else { throw error("Sign-in returned an incomplete session. Try signing in again; no saved account or planner data was replaced.") }
        let saved = expiry(result)
        let duration = (result["expires_in"] as? NSNumber)?.doubleValue ?? 3600
        result["expires_at"] = saved > 0 ? saved:Date().timeIntervalSince1970 + (duration.isFinite && duration > 0 ? duration:3600)
        return result
    }
    static func error(_ text: String = reconnectMessage) -> NSError { NSError(domain:"OneStepSession",code:1,userInfo:[NSLocalizedDescriptionKey:text]) }
}
struct AccountHTTPFailure: LocalizedError {
    let status: Int
    let code: String
    let message: String
    var errorDescription: String? { message }
    var invalidRefresh: Bool {
        let value = (code+" "+message).lowercased()
        return [400,401,403].contains(status) && ["refresh token","refresh_token","invalid_grant","session_not_found"].contains { value.contains($0) }
    }
}

enum ShieldLeaseRules {
    static func shouldShield(enabled: Bool, expiry: Date?, now: Date) -> Bool {
        enabled && (expiry ?? .distantPast) <= now
    }
    static func monitorEnd(for expiry: Date) -> Date { expiry.addingTimeInterval(2) }
}

