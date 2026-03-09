import Foundation

enum GoogleAuthError: LocalizedError, Equatable {
    case noInternet
    case serverStartFailed
    case callbackTimeout
    case callbackError(String)
    case tokenExchangeFailed(Int)
    case userInfoFailed(Int)
    case driveInfoFailed(Int)
    case sessionExpired
    case cancelled
    case invalidResponse

    var errorDescription: String? { userMessage }

    var userMessage: String {
        switch self {
        case .noInternet:
            "No internet connection. Please check your network and try again."
        case .serverStartFailed:
            "Failed to start local callback server. Please try again."
        case .callbackTimeout:
            "Connection timed out. Please try again."
        case .callbackError(let msg):
            "Google returned an error: \(msg)"
        case .tokenExchangeFailed(let code):
            "Failed to exchange authorization code (HTTP \(code))."
        case .userInfoFailed(let code):
            "Failed to fetch account info (HTTP \(code))."
        case .driveInfoFailed(let code):
            "Failed to fetch storage info (HTTP \(code))."
        case .sessionExpired:
            "Session expired. Please reconnect your Google account."
        case .cancelled:
            "Connection cancelled."
        case .invalidResponse:
            "Received an invalid response from Google."
        }
    }
}
