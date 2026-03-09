import Foundation

/// Minimal POSIX socket HTTP server for OAuth callback.
/// Listens on 127.0.0.1, random high port, accepts exactly one request.
actor OAuthCallbackServer {
    private var serverFD: Int32 = -1
    private(set) var port: UInt16 = 0

    private static let timeoutSeconds: Int = 120
    private static let portRange: ClosedRange<UInt16> = 49152...65535
    private static let maxRetries = 3

    /// Bind to a random port. Must be called before `waitForCallback()`.
    func start() throws {
        for _ in 0..<Self.maxRetries {
            let randomPort = UInt16.random(in: Self.portRange)
            let fd = socket(AF_INET, SOCK_STREAM, 0)
            guard fd >= 0 else { continue }

            var reuse: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = randomPort.bigEndian
            addr.sin_addr.s_addr = inet_addr("127.0.0.1")

            let bindResult = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }

            guard bindResult == 0 else {
                close(fd)
                continue
            }

            guard listen(fd, 1) == 0 else {
                close(fd)
                continue
            }

            self.serverFD = fd
            self.port = randomPort
            return
        }
        throw GoogleAuthError.serverStartFailed
    }

    /// Wait for the OAuth callback. Returns the authorization code.
    func waitForCallback() async throws -> String {
        guard serverFD >= 0 else { throw GoogleAuthError.serverStartFailed }
        defer { stop() }

        let fd = serverFD

        return try await withTaskCancellationHandler {
            try await Task.detached { [fd] in
                // Set socket timeout
                var tv = timeval(tv_sec: Self.timeoutSeconds, tv_usec: 0)
                setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

                // Accept one connection
                var clientAddr = sockaddr_in()
                var clientLen = socklen_t(MemoryLayout<sockaddr_in>.size)
                let clientFD = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                        accept(fd, sockPtr, &clientLen)
                    }
                }

                guard clientFD >= 0 else {
                    throw GoogleAuthError.callbackTimeout
                }
                defer { close(clientFD) }

                try Task.checkCancellation()

                // Read request
                var buffer = [UInt8](repeating: 0, count: 4096)
                let bytesRead = recv(clientFD, &buffer, buffer.count, 0)
                guard bytesRead > 0,
                      let request = String(bytes: buffer[0..<bytesRead], encoding: .utf8) else {
                    throw GoogleAuthError.invalidResponse
                }

                // Parse callback
                let result = Self.parseCallback(from: request)

                // Send HTML response
                let html: String
                switch result {
                case .success:
                    html = """
                    <html><body style="font-family:system-ui;text-align:center;padding:60px">
                    <h2>✅ Connected!</h2><p>You can close this tab and return to DriveSync.</p>
                    </body></html>
                    """
                case .failure(let err):
                    html = """
                    <html><body style="font-family:system-ui;text-align:center;padding:60px">
                    <h2>❌ Error</h2><p>\(err.localizedDescription)</p>
                    <p>Please close this tab and try again in DriveSync.</p>
                    </body></html>
                    """
                }

                let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\n\(html)"
                _ = response.withCString { ptr in
                    send(clientFD, ptr, strlen(ptr), 0)
                }

                return try result.get()
            }.value
        } onCancel: {
            Task { await self.stop() }
        }
    }

    func stop() {
        if serverFD >= 0 {
            close(serverFD)
            serverFD = -1
        }
    }

    // MARK: - Private

    private static func parseCallback(from request: String) -> Result<String, Error> {
        guard let firstLine = request.split(separator: "\r\n").first,
              let urlPart = firstLine.split(separator: " ").dropFirst().first,
              let components = URLComponents(string: String(urlPart)) else {
            return .failure(GoogleAuthError.invalidResponse)
        }

        let queryItems = components.queryItems ?? []

        if let code = queryItems.first(where: { $0.name == "code" })?.value {
            return .success(code)
        }

        if let error = queryItems.first(where: { $0.name == "error" })?.value {
            return .failure(GoogleAuthError.callbackError(error))
        }

        return .failure(GoogleAuthError.invalidResponse)
    }
}
