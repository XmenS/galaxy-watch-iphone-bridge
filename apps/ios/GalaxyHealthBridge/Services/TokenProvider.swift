import Foundation

actor TokenProvider {
    private let store: LocalStore
    private let baseURL: URL

    static let keychain = TokenProvider(store: LocalStore(),
                                        baseURL: URL(string: "https://api.galaxyhealthbridge.dev")!)

    init(store: LocalStore, baseURL: URL) {
        self.store = store
        self.baseURL = baseURL
    }

    func currentAccessToken() async throws -> String {
        if let access = store.accessToken, !isExpired(access) { return access }
        return try await refresh()
    }

    private func refresh() async throws -> String {
        guard let refreshToken = store.refreshToken else { throw ApiError.transport }

        var req = URLRequest(url: baseURL.appendingPathComponent("/v1/auth/refresh"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["refresh_token": refreshToken])

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ApiError.status(code: (resp as? HTTPURLResponse)?.statusCode ?? -1,
                                  body: String(data: data, encoding: .utf8))
        }
        let pair = try ApiClient.decoder.decode(ApiClient.TokenPair.self, from: data)
        store.accessToken = pair.accessToken
        store.refreshToken = pair.refreshToken
        return pair.accessToken
    }

    /// Best-effort expiry parsing of a JWT exp claim. Returns true for malformed tokens
    /// so we re-issue safely on any parse error.
    private func isExpired(_ jwt: String) -> Bool {
        let parts = jwt.split(separator: ".")
        guard parts.count == 3 else { return true }
        let payload = String(parts[1])
        var padded = payload
        while padded.count % 4 != 0 { padded += "=" }
        guard let data = Data(base64Encoded: padded.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = json["exp"] as? TimeInterval
        else { return true }
        return Date(timeIntervalSince1970: exp) <= Date().addingTimeInterval(30) // 30s skew
    }
}
