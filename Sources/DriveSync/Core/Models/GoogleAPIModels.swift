import Foundation

/// Google OAuth token exchange response
struct TokenExchangeResponse: Decodable {
    let accessToken: String
    let expiresIn: Int
    let refreshToken: String?
    let scope: String?
    let tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
        case tokenType = "token_type"
    }
}

/// Google userinfo endpoint response
struct UserInfoResponse: Decodable {
    let email: String
}

/// Google Drive about endpoint response
struct DriveAboutResponse: Decodable {
    let storageQuota: StorageQuota

    struct StorageQuota: Decodable {
        let limit: String?
        let usage: String
    }
}

/// Google Drive file list response
struct DriveFileListResponse: Decodable {
    let files: [DriveFile]

    struct DriveFile: Decodable {
        let id: String
        let name: String
    }
}
