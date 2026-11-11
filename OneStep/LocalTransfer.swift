import Foundation
import Network
import CryptoKit
import Observation
import Darwin

/// A short-lived, foreground-only encrypted snapshot sender. No discovery server.
@MainActor @Observable final class LocalTransfer {
    var invitation = ""
    var message = ""
    private var listener: NWListener?
    private var expiry: Task<Void, Never>?
    private var connections: [NWConnection] = []

    static func isPrivateIPv4(_ host: String) -> Bool {
        let p = host.split(separator: ".").compactMap { Int($0) }
        guard p.count == 4, p.allSatisfy({ (0...255).contains($0) }) else { return false }
        return p[0] == 10 || (p[0] == 192 && p[1] == 168) || (p[0] == 172 && (16...31).contains(p[1]))
    }

    static func addresses() -> [String] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        var values: [String] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else { continue }
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                let host = String(cString: buffer)
                if isPrivateIPv4(host) { values.append(host) }
            }
        }
        return values
    }

    func start(data: Data, host: String) throws {
        stop()
        guard Self.isPrivateIPv4(host), data.count <= 8 * 1024 * 1024 else { throw TransferError.invalid }
        let key = SymmetricKey(size: .bits256)
        let raw = key.withUnsafeBytes { Data($0) }
        let token = SHA256.hash(data: raw).map { String(format: "%02x", $0) }.joined()
        let sealed = try AES.GCM.seal(data, using: key).combined!
        let server = try NWListener(using: .tcp, on: .any)
        listener = server
        server.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                if case .ready = state, let port = server.port {
                    self.invitation = "onestep-transfer://\(host):\(port.rawValue)/#\(raw.base64EncodedString())"
                    self.message = "Keep this screen open. Code expires in 10 minutes. Only share it with your own device."
                }
                if case .failed(let error) = state { self.message = error.localizedDescription; self.stop() }
            }
        }
        server.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.serve(connection, token: token, payload: sealed) }
        }
        server.start(queue: .main)
        expiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(600))
            guard !Task.isCancelled else { return }
            self?.stop(); self?.message = "Transfer expired. Start another when ready."
        }
    }

    private func serve(_ connection: NWConnection, token: String, payload: Data) {
        guard connections.count < 8 else { connection.cancel(); return }
        connections.append(connection)
        connection.start(queue: .main)
        let timeout = Task { try? await Task.sleep(for: .seconds(15)); connection.cancel() }
        readHeader(connection, buffer: Data(), token: token, payload: payload, timeout: timeout)
    }

    private func readHeader(_ connection: NWConnection, buffer: Data, token: String, payload: Data, timeout: Task<Void, Never>) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self else { return }
                var bytes = buffer; if let data { bytes.append(data) }
                guard bytes.count <= 8192, error == nil else { timeout.cancel(); self.finish(connection); return }
                guard let header = String(data: bytes, encoding: .utf8), header.contains("\r\n\r\n") else {
                    if complete { timeout.cancel(); self.finish(connection) }
                    else { self.readHeader(connection, buffer: bytes, token: token, payload: payload, timeout: timeout) }
                    return
                }
                let lines = header.components(separatedBy: "\r\n")
                let authorized = lines.contains { $0.lowercased() == "authorization: bearer \(token)" }
                let ok = authorized && lines.first == "GET /snapshot HTTP/1.1"
                let body = ok ? payload : Data()
                let response = "HTTP/1.1 \(ok ? "200 OK" : "403 Forbidden")\r\nContent-Type: application/octet-stream\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
                connection.send(content: Data(response.utf8) + body, completion: .contentProcessed { _ in
                    Task { @MainActor in timeout.cancel(); self.finish(connection) }
                })
            }
        }
    }

    private func finish(_ connection: NWConnection) {
        connection.cancel(); connections.removeAll { $0 === connection }
    }

    func stop() {
        expiry?.cancel(); expiry = nil; listener?.cancel(); listener = nil
        connections.forEach { $0.cancel() }; connections.removeAll(); invitation = ""
    }

    static func receive(_ code: String) async throws -> TransferDocument {
        guard let url = URL(string: code.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme == "onestep-transfer",
              let host = url.host, isPrivateIPv4(host), let port = url.port, (1...65535).contains(port),
              let encoded = url.fragment, let raw = Data(base64Encoded: encoded), raw.count == 32 else { throw TransferError.invalid }
        var request = URLRequest(url: URL(string: "http://\(host):\(port)/snapshot")!)
        request.timeoutInterval = 20
        request.setValue("Bearer " + SHA256.hash(data: raw).map { String(format: "%02x", $0) }.joined(), forHTTPHeaderField: "Authorization")
        let config = URLSessionConfiguration.ephemeral
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let (stream, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.url?.host == host, response.expectedContentLength <= 8 * 1024 * 1024 + 28 else { throw TransferError.invalid }
        var data = Data()
        for try await byte in stream {
            data.append(byte)
            guard data.count <= 8 * 1024 * 1024 + 28 else { throw TransferError.invalid }
        }
        let clear = try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: SymmetricKey(data: raw))
        return try TransferDocument.decode(clear)
    }
}
