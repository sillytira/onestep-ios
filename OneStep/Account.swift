import Foundation

/// Public client configuration; never place privileged keys or enrollment codes here.
enum OnlineAccount {
    static func isPublicKey(_ key: String) -> Bool {
        if key.hasPrefix("sb_publishable_") { return true }
        let parts = key.split(separator: ".")
        guard parts.count == 3 else { return false }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload), let claims = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return false }
        return claims["role"] as? String == "anon"
    }

}

enum PublicService {
    static let url = "https://zibmxjwfamimyclcwubi.supabase.co"
    static let key = "sb_publishable_TOsTyzcdGyeSDE1-60ChGw_TxAhOh_T"
}
