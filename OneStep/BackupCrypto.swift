import Foundation
import CryptoKit
import CommonCrypto
import Security

enum BackupCrypto {
    static let iterations = 600000, maximum = 8*1024*1024
    struct Envelope: Codable { let format: String; let version: Int; let kdf: String; let iterations: Int; let salt: String; let nonce: String; let data: String }
    static func key(_ password: String,_ salt: Data) throws -> SymmetricKey {
        let bytes = Array(password.utf8); guard bytes.count <= 1024 else { throw TransferError.invalid }
        var output = [UInt8](repeating:0,count:32)
        let status = bytes.withUnsafeBytes { p in salt.withUnsafeBytes { s in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),p.bindMemory(to:Int8.self).baseAddress,bytes.count,s.bindMemory(to:UInt8.self).baseAddress,salt.count,CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),UInt32(iterations),&output,32)
        }}
        guard status == kCCSuccess else { throw TransferError.invalid }; return SymmetricKey(data:Data(output))
    }
    static func seal(_ clear: Data,password: String) throws -> Data {
        guard password.count >= 12, password.utf8.count <= 1024, clear.count <= maximum else { throw CryptoFailure.password }
        var bytes = [UInt8](repeating:0,count:16)
        guard SecRandomCopyBytes(kSecRandomDefault,16,&bytes) == errSecSuccess else { throw TransferError.invalid }
        let salt = Data(bytes), box = try AES.GCM.seal(clear,using:key(password,salt),authenticating:Data("OneStepEncrypted:1".utf8))
        let nonce = box.nonce.withUnsafeBytes { Data($0) }
        return try JSONEncoder().encode(Envelope(format:"OneStepEncrypted",version:1,kdf:"PBKDF2-HMAC-SHA256",iterations:iterations,salt:salt.base64EncodedString(),nonce:nonce.base64EncodedString(),data:(box.ciphertext+box.tag).base64EncodedString()))
    }
    static func open(_ data: Data,password: String) throws -> Data {
        do {
            guard data.count <= 12*1024*1024 else { throw TransferError.invalid }
            let e = try JSONDecoder().decode(Envelope.self,from:data)
            guard e.format == "OneStepEncrypted", e.version == 1, e.kdf == "PBKDF2-HMAC-SHA256", e.iterations == iterations,
                  let salt = Data(base64Encoded:e.salt), salt.count == 16, let nonce = Data(base64Encoded:e.nonce), nonce.count == 12,
                  let bytes = Data(base64Encoded:e.data), bytes.count >= 16, bytes.count <= maximum+16 else { throw TransferError.invalid }
            let box = try AES.GCM.SealedBox(nonce:AES.GCM.Nonce(data:nonce),ciphertext:bytes.dropLast(16),tag:bytes.suffix(16))
            return try AES.GCM.open(box,using:key(password,salt),authenticating:Data("OneStepEncrypted:1".utf8))
        } catch { throw CryptoFailure.damaged }
    }
    static func encrypted(_ data: Data) -> Bool { ((try? JSONSerialization.jsonObject(with:data)) as? [String:Any])?["format"] as? String == "OneStepEncrypted" }
    enum CryptoFailure: LocalizedError, Equatable {
        case password, damaged
        var errorDescription: String? { self == .password ? "Use a passphrase of 12–1,024 characters." : "Wrong passphrase or damaged encrypted backup. Nothing was replaced." }
    }
}
