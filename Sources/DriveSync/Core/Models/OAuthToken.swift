import Foundation

struct OAuthToken: Codable {
    let accessToken: String
    let refreshToken: String?
    let tokenType: String
    let expiresIn: Int
    let scope: String?
    let issuedAt: Date

    var expiresAt: Date {
        issuedAt.addingTimeInterval(TimeInterval(expiresIn))
    }

    var isExpired: Bool {
        Date.now >= expiresAt
    }

    /// Token needs refresh when less than 5 minutes remain
    var needsRefresh: Bool {
        Date.now >= expiresAt.addingTimeInterval(-300)
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case scope
        case issuedAt = "issued_at"
    }
}
