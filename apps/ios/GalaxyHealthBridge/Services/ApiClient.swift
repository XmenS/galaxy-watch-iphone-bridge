import Foundation

/// Lightweight HTTPS client for the Galaxy Health Bridge API.
/// Lifts only what the iOS companion needs — auth, device register, sample paging.
struct ApiClient {
    let baseURL: URL
    let session: URLSession
    let tokens: TokenProvider

    static func live() -> ApiClient {
        let url = URL(string: Bundle.main.object(forInfoDictionaryKey: "GHBApiBaseURL") as? String
                      ?? "https://api.galaxyhealthbridge.dev")!
        return ApiClient(baseURL: url, session: .shared, tokens: .keychain)
    }

    // MARK: – Auth
    struct TokenPair: Codable {
        let accessToken: String
        let refreshToken: String
        let accessExpiresIn: Int
        let refreshExpiresIn: Int
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case accessExpiresIn = "access_expires_in"
            case refreshExpiresIn = "refresh_expires_in"
        }
    }

    struct RedeemBody: Codable {
        let code: String
        let installId: String
        let deviceKind: String
        let deviceLabel: String?
        let pubKey: String?
        enum CodingKeys: String, CodingKey {
            case code
            case installId    = "install_id"
            case deviceKind   = "device_kind"
            case deviceLabel  = "device_label"
            case pubKey       = "pub_key"
        }
    }

    func redeemPairCode(_ body: RedeemBody) async throws -> TokenPair {
        try await post("/v1/devices/redeem", body: body, authed: false)
    }

    func login(email: String, password: String, installId: String) async throws -> TokenPair {
        struct Body: Codable {
            let email: String
            let password: String
            let installId: String
            let deviceKind = "ios"
            enum CodingKeys: String, CodingKey {
                case email, password
                case installId = "install_id"
                case deviceKind = "device_kind"
            }
        }
        return try await post("/v1/auth/login", body: Body(email: email, password: password, installId: installId), authed: false)
    }

    // MARK: – Samples
    struct SamplesPage: Codable {
        let items: [CanonicalSample]
        let nextCursor: String?
        enum CodingKeys: String, CodingKey { case items; case nextCursor = "next_cursor" }
    }

    func samples(cursor: String?, limit: Int = 500) async throws -> SamplesPage {
        var comps = URLComponents(url: baseURL.appendingPathComponent("/v1/sync/samples"),
                                  resolvingAgainstBaseURL: false)!
        var q: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor { q.append(URLQueryItem(name: "cursor", value: cursor)) }
        comps.queryItems = q
        return try await get(comps.url!)
    }

    // MARK: – HTTP
    private func get<T: Decodable>(_ url: URL) async throws -> T {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        try await sign(&req)
        return try await send(req)
    }

    private func post<B: Encodable, T: Decodable>(_ path: String, body: B, authed: Bool) async throws -> T {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try Self.encoder.encode(body)
        if authed { try await sign(&req) }
        return try await send(req)
    }

    private func sign(_ req: inout URLRequest) async throws {
        let access = try await tokens.currentAccessToken()
        req.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
    }

    private func send<T: Decodable>(_ req: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw ApiError.transport }
        if !(200..<300).contains(http.statusCode) {
            throw ApiError.status(code: http.statusCode, body: String(data: data, encoding: .utf8))
        }
        return try Self.decoder.decode(T.self, from: data)
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

enum ApiError: Error, LocalizedError {
    case transport
    case status(code: Int, body: String?)

    var errorDescription: String? {
        switch self {
        case .transport: return "Network error"
        case .status(let c, let b): return "HTTP \(c): \(b ?? "")"
        }
    }
}
