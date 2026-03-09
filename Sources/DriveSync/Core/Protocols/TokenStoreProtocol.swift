import Foundation

protocol TokenStore: Sendable {
    func load() async throws -> OAuthToken?
    func save(_ token: OAuthToken) async throws
    func delete() async throws
}
