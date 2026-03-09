import Foundation
import Network
import AppKit

struct GoogleAccountInfo {
    let email: String
    let storageUsed: Int64
    let storageTotal: Int64
    let folders: [GoogleDriveFolder]
}

struct GoogleDriveFolder: Identifiable, Hashable {
    let id: String
    let name: String
}

final class GoogleAuthService: Sendable {
    private let httpClient: HTTPClient
    private let tokenStore: TokenStore
    private let callbackServer: OAuthCallbackServer

    private static let authURL = "https://accounts.google.com/o/oauth2/v2/auth"
    private static let tokenURL = "https://oauth2.googleapis.com/token"
    private static let userInfoURL = "https://www.googleapis.com/oauth2/v2/userinfo"
    private static let driveAboutURL = "https://www.googleapis.com/drive/v3/about?fields=storageQuota"
    private static let driveFoldersURL = "https://www.googleapis.com/drive/v3/files?q=mimeType%3D'application/vnd.google-apps.folder'+and+'root'+in+parents+and+trashed%3Dfalse&fields=files(id,name)&orderBy=name&pageSize=100"
    private static let revokeURL = "https://oauth2.googleapis.com/revoke"
    private static let scopes = "openid email https://www.googleapis.com/auth/drive"

    init(httpClient: HTTPClient, tokenStore: TokenStore) {
        self.httpClient = httpClient
        self.tokenStore = tokenStore
        self.callbackServer = OAuthCallbackServer()
    }

    // MARK: - Connect

    func connect() async throws -> GoogleAccountInfo {
        try await checkNetwork()
        try Task.checkCancellation()

        // Start local callback server and wait until ready
        try await callbackServer.start()
        let port = await callbackServer.port

        // Open browser for OAuth consent
        let redirectURI = "http://127.0.0.1:\(port)/callback"
        let authURLString = Self.buildAuthURL(redirectURI: redirectURI)
        guard let url = URL(string: authURLString) else {
            await callbackServer.stop()
            throw GoogleAuthError.serverStartFailed
        }

        _ = await MainActor.run { NSWorkspace.shared.open(url) }
        try Task.checkCancellation()

        // Wait for callback
        let code: String
        do {
            code = try await callbackServer.waitForCallback()
        } catch is CancellationError {
            await callbackServer.stop()
            throw GoogleAuthError.cancelled
        }

        try Task.checkCancellation()

        // Exchange code for tokens
        let token = try await exchangeCode(code, redirectURI: redirectURI)
        try await tokenStore.save(token)
        try Task.checkCancellation()

        // Validate scopes — warn if Drive scope missing
        if let scope = token.scope, !scope.contains("drive") {
            await LogManager.shared.warn("Token missing Drive scope! Granted: \(scope). Drive API may not be enabled in GCP Console.")
        }

        // Fetch account info
        return try await fetchAccountInfo(accessToken: token.accessToken)
    }

    // MARK: - Disconnect

    func disconnect() async throws {
        if let token = try await tokenStore.load() {
            // Revoke token (best-effort, ignore errors)
            _ = try? await revokeToken(token.accessToken)
        }
        try await tokenStore.delete()
    }

    // MARK: - Refresh

    func refreshIfNeeded() async throws -> OAuthToken? {
        guard let token = try await tokenStore.load() else { return nil }
        guard token.needsRefresh else { return token }
        guard let refreshToken = token.refreshToken else {
            try await tokenStore.delete()
            throw GoogleAuthError.sessionExpired
        }

        await LogManager.shared.debug("Refreshing access token...")
        do {
            let newToken = try await refreshAccessToken(refreshToken: refreshToken)
            try await tokenStore.save(newToken)
            await LogManager.shared.info("Token refreshed successfully")
            return newToken
        } catch {
            await LogManager.shared.warn("Token refresh failed: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Load on Startup

    func loadOnStartup() async throws -> GoogleAccountInfo? {
        guard var token = try await tokenStore.load() else { return nil }

        // Warn if saved token lacks Drive scope
        if let scope = token.scope, !scope.contains("drive") {
            await LogManager.shared.warn("Saved token missing Drive scope — storage/folders unavailable. Reconnect to fix.")
        }

        if token.needsRefresh {
            guard let refreshed = try await refreshIfNeeded() else {
                try await tokenStore.delete()
                return nil
            }
            token = refreshed
        }

        return try await fetchAccountInfo(accessToken: token.accessToken)
    }

    // MARK: - Private: Network Check

    private func checkNetwork() async throws {
        let satisfied = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "network-check")
            nonisolated(unsafe) var resumed = false

            monitor.pathUpdateHandler = { path in
                monitor.cancel()
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: path.status == .satisfied)
            }
            monitor.start(queue: queue)

            queue.asyncAfter(deadline: .now() + 2) {
                monitor.cancel()
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: false)
            }
        }

        guard satisfied else { throw GoogleAuthError.noInternet }
    }

    // MARK: - Private: Auth URL

    private static func buildAuthURL(redirectURI: String) -> String {
        var components = URLComponents(string: authURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Secrets.googleClientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        return components.url!.absoluteString
    }

    // MARK: - Private: Token Exchange

    private func exchangeCode(_ code: String, redirectURI: String) async throws -> OAuthToken {
        var request = URLRequest(url: URL(string: Self.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "code=\(code)",
            "client_id=\(Secrets.googleClientId)",
            "client_secret=\(Secrets.googleClientSecret)",
            "redirect_uri=\(redirectURI)",
            "grant_type=authorization_code",
        ].joined(separator: "&")
        request.httpBody = Data(body.utf8)

        let (data, response) = try await httpClient.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw GoogleAuthError.tokenExchangeFailed(code)
        }

        let decoded = try JSONDecoder().decode(TokenExchangeResponse.self, from: data)
        return OAuthToken(
            accessToken: decoded.accessToken,
            refreshToken: decoded.refreshToken,
            tokenType: decoded.tokenType,
            expiresIn: decoded.expiresIn,
            scope: decoded.scope,
            issuedAt: Date.now
        )
    }

    // MARK: - Private: Refresh Token

    private func refreshAccessToken(refreshToken: String) async throws -> OAuthToken {
        var request = URLRequest(url: URL(string: Self.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "refresh_token=\(refreshToken)",
            "client_id=\(Secrets.googleClientId)",
            "client_secret=\(Secrets.googleClientSecret)",
            "grant_type=refresh_token",
        ].joined(separator: "&")
        request.httpBody = Data(body.utf8)

        let (data, response) = try await httpClient.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GoogleAuthError.invalidResponse }

        if http.statusCode == 400 || http.statusCode == 401 {
            try await tokenStore.delete()
            throw GoogleAuthError.sessionExpired
        }

        guard http.statusCode == 200 else {
            throw GoogleAuthError.tokenExchangeFailed(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(TokenExchangeResponse.self, from: data)
        return OAuthToken(
            accessToken: decoded.accessToken,
            refreshToken: decoded.refreshToken ?? refreshToken, // Google may not return refresh_token on refresh
            tokenType: decoded.tokenType,
            expiresIn: decoded.expiresIn,
            scope: decoded.scope,
            issuedAt: Date.now
        )
    }

    // MARK: - Private: Revoke Token

    private func revokeToken(_ accessToken: String) async throws {
        var request = URLRequest(url: URL(string: Self.revokeURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("token=\(accessToken)".utf8)

        _ = try await httpClient.data(for: request)
    }

    // MARK: - Private: Fetch Account Info

    private func fetchAccountInfo(accessToken: String) async throws -> GoogleAccountInfo {
        // Fetch user info — this is critical, must succeed
        var userReq = URLRequest(url: URL(string: Self.userInfoURL)!)
        userReq.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (userData, userResp) = try await httpClient.data(for: userReq)
        guard let userHTTP = userResp as? HTTPURLResponse, userHTTP.statusCode == 200 else {
            let code = (userResp as? HTTPURLResponse)?.statusCode ?? 0
            throw GoogleAuthError.userInfoFailed(code)
        }
        let userInfo = try JSONDecoder().decode(UserInfoResponse.self, from: userData)

        // Fetch drive storage info — graceful degradation if Drive API not enabled
        var storageUsed: Int64 = 0
        var storageTotal: Int64 = 0
        do {
            var driveReq = URLRequest(url: URL(string: Self.driveAboutURL)!)
            driveReq.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            let (driveData, driveResp) = try await httpClient.data(for: driveReq)
            if let driveHTTP = driveResp as? HTTPURLResponse, driveHTTP.statusCode == 200,
               let driveInfo = try? JSONDecoder().decode(DriveAboutResponse.self, from: driveData) {
                storageUsed = Int64(driveInfo.storageQuota.usage) ?? 0
                storageTotal = driveInfo.storageQuota.limit.flatMap(Int64.init) ?? 0
            } else {
                let code = (driveResp as? HTTPURLResponse)?.statusCode ?? 0
                await LogManager.shared.warn("Drive storage API returned HTTP \(code) — storage info unavailable")
            }
        } catch {
            await LogManager.shared.warn("Drive storage fetch failed: \(error.localizedDescription)")
        }

        // Fetch root-level folders — also graceful degradation
        var folders: [GoogleDriveFolder] = []
        do {
            var foldersReq = URLRequest(url: URL(string: Self.driveFoldersURL)!)
            foldersReq.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            let (foldersData, foldersResp) = try await httpClient.data(for: foldersReq)
            if let foldersHTTP = foldersResp as? HTTPURLResponse, foldersHTTP.statusCode == 200,
               let fileList = try? JSONDecoder().decode(DriveFileListResponse.self, from: foldersData) {
                folders = fileList.files.map { GoogleDriveFolder(id: $0.id, name: $0.name) }
            } else {
                let code = (foldersResp as? HTTPURLResponse)?.statusCode ?? 0
                await LogManager.shared.warn("Drive folders API returned HTTP \(code) — folder list unavailable")
            }
        } catch {
            await LogManager.shared.warn("Drive folders fetch failed: \(error.localizedDescription)")
        }

        return GoogleAccountInfo(
            email: userInfo.email,
            storageUsed: storageUsed,
            storageTotal: storageTotal,
            folders: folders
        )
    }
}
