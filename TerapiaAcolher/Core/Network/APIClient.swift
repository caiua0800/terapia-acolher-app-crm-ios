import Foundation

/// Configuração de ambiente da API.
enum AppConfig {
    /// Backend de produção (para desenvolvimento local, trocar por http://localhost:3000).
    static var apiBaseURL: URL {
        URL(string: "https://acolher-api.ccypher.com.br")!
    }
}

/// Erro de API com a mensagem PT-BR vinda do backend.
struct APIError: Error, LocalizedError {
    let statusCode: Int
    let message: String

    var errorDescription: String? { message }
    var isUnauthorized: Bool { statusCode == 401 }
}

/// Cliente HTTP tipado — async/await, JSON, Bearer automático e
/// renovação de sessão em 401 (refresh + retry uma vez).
final class APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Fornecidos pelo SessionStore no boot.
    var accessTokenProvider: () -> String? = { nil }
    var refreshHandler: (() async -> Bool)? = nil
    var onSessionExpired: () -> Void = {}

    private init() {
        session = URLSession(configuration: .default)
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        // Backend serializa datas ISO-8601 com frações de segundo.
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            if let date = Self.isoFractional.date(from: value) ?? Self.iso.date(from: value) {
                return date
            }
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Data inválida: \(value)"
            ))
        }
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso = ISO8601DateFormatter()

    // MARK: - Métodos públicos

    func get<Response: Decodable>(_ path: String, query: [String: String?] = [:]) async throws -> Response {
        try await request(path: path, method: "GET", query: query, body: Optional<Int>.none)
    }

    func post<Body: Encodable, Response: Decodable>(_ path: String, body: Body?) async throws -> Response {
        try await request(path: path, method: "POST", body: body)
    }

    func post<Response: Decodable>(_ path: String) async throws -> Response {
        try await request(path: path, method: "POST", body: Optional<Int>.none)
    }

    func patch<Body: Encodable, Response: Decodable>(_ path: String, body: Body?) async throws -> Response {
        try await request(path: path, method: "PATCH", body: body)
    }

    func patch<Response: Decodable>(_ path: String) async throws -> Response {
        try await request(path: path, method: "PATCH", body: Optional<Int>.none)
    }

    func put<Body: Encodable, Response: Decodable>(_ path: String, body: Body?) async throws -> Response {
        try await request(path: path, method: "PUT", body: body)
    }

    func delete<Response: Decodable>(_ path: String) async throws -> Response {
        try await request(path: path, method: "DELETE", body: Optional<Int>.none)
    }

    /// DELETE com corpo — o desregistro de aparelho manda o token no body.
    func delete<Body: Encodable, Response: Decodable>(
        _ path: String,
        body: Body
    ) async throws -> Response {
        try await request(path: path, method: "DELETE", body: body)
    }

    /// Upload multipart (arquivos, avatar, importação).
    func upload<Response: Decodable>(
        _ path: String,
        fileData: Data,
        fileName: String,
        mimeType: String,
        fieldName: String = "file",
        extraFields: [String: String] = [:]
    ) async throws -> Response {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        for (key, value) in extraFields {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(value)\r\n")
        }
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\nContent-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n")

        return try await rawRequest(
            path: path,
            method: "POST",
            query: [:],
            bodyData: body,
            contentType: "multipart/form-data; boundary=\(boundary)",
            allowRetry: true
        )
    }

    // MARK: - Núcleo

    private func request<Body: Encodable, Response: Decodable>(
        path: String,
        method: String,
        query: [String: String?] = [:],
        body: Body?
    ) async throws -> Response {
        let bodyData = try body.map { try encoder.encode($0) }
        return try await rawRequest(
            path: path,
            method: method,
            query: query,
            bodyData: bodyData,
            contentType: "application/json",
            allowRetry: true
        )
    }

    private func rawRequest<Response: Decodable>(
        path: String,
        method: String,
        query: [String: String?],
        bodyData: Data?,
        contentType: String,
        allowRetry: Bool
    ) async throws -> Response {
        var components = URLComponents(
            url: AppConfig.apiBaseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        let items = query.compactMap { key, value in value.map { URLQueryItem(name: key, value: $0) } }
        if !items.isEmpty { components.queryItems = items }

        var urlRequest = URLRequest(url: components.url!)
        urlRequest.httpMethod = method
        urlRequest.httpBody = bodyData
        if bodyData != nil {
            urlRequest.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        if let token = accessTokenProvider() {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let urlError as URLError where urlError.code == .cancelled {
            // Task do SwiftUI cancelada (refresh interrompido, troca de aba/tela
            // com load em voo) — não é falha real; propaga como cancelamento
            // pros view models ignorarem em vez de mostrar alerta de erro.
            throw CancellationError()
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        // O próprio refresh nunca dispara refresh (evita recursão infinita
        // quando o refresh token está expirado/revogado).
        let isRefreshCall = path == "auth/refresh"
        if status == 401, allowRetry, !isRefreshCall, let refreshHandler {
            if await refreshHandler() {
                return try await rawRequest(
                    path: path, method: method, query: query,
                    bodyData: bodyData, contentType: contentType, allowRetry: false
                )
            }
            onSessionExpired()
        }

        guard (200 ..< 300).contains(status) else {
            throw APIError(statusCode: status, message: Self.extractMessage(from: data, status: status))
        }
        if data.isEmpty, let empty = EmptyResponse() as? Response {
            return empty
        }
        return try decoder.decode(Response.self, from: data)
    }

    private static func extractMessage(from data: Data, status: Int) -> String {
        struct ErrorBody: Decodable {
            let message: MessageValue?
            enum MessageValue: Decodable {
                case text(String), list([String])
                init(from decoder: Decoder) throws {
                    let container = try decoder.singleValueContainer()
                    if let text = try? container.decode(String.self) { self = .text(text); return }
                    self = .list((try? container.decode([String].self)) ?? [])
                }
                var joined: String {
                    switch self {
                    case let .text(text): text
                    case let .list(items): items.joined(separator: "\n")
                    }
                }
            }
        }
        if let parsed = try? JSONDecoder().decode(ErrorBody.self, from: data), let message = parsed.message {
            return message.joined
        }
        return "Algo deu errado (código \(status)). Tente de novo."
    }
}

/// Pra endpoints que devolvem corpo vazio ou irrelevante.
struct EmptyResponse: Decodable {}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
