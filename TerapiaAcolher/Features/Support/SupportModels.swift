import Foundation
import UniformTypeIdentifiers

// MARK: - Suporte — DTOs do terapeuta
//
// Contrato: backend/docs/SUPORTE.md. Prefixo `Sup*` reservado a este módulo.
//
// Todo enum que vem do servidor é tolerante: um valor novo cai em `.unknown`
// em vez de derrubar a decodificação da conversa inteira. O app instalado no
// aparelho do terapeuta não pode quebrar porque o backend ganhou um tipo novo
// de mensagem ou de status.

enum SupTicketStatus: Decodable, Equatable {
    case open, inProgress, resolved
    case unknown(String)

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "OPEN": self = .open
        case "IN_PROGRESS": self = .inProgress
        case "RESOLVED": self = .resolved
        default: self = .unknown(raw)
        }
    }

    var isResolved: Bool { self == .resolved }

    var label: String {
        switch self {
        case .open: "AGUARDANDO"
        case .inProgress: "EM ATENDIMENTO"
        case .resolved: "FINALIZADO"
        case .unknown: "ATENDIMENTO"
        }
    }
}

enum SupSenderRole: Decodable, Equatable {
    case therapist, admin, system
    case unknown(String)

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "THERAPIST": self = .therapist
        case "ADMIN": self = .admin
        case "SYSTEM": self = .system
        default: self = .unknown(raw)
        }
    }
}

enum SupMessageType: Decodable, Equatable {
    case text, image, video, audio, file, system
    case unknown(String)

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "TEXT": self = .text
        case "IMAGE": self = .image
        case "VIDEO": self = .video
        case "AUDIO": self = .audio
        case "FILE": self = .file
        case "SYSTEM": self = .system
        default: self = .unknown(raw)
        }
    }
}

enum SupWaitingFor: Decodable, Equatable {
    case admin, therapist
    case unknown(String)

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "ADMIN": self = .admin
        case "THERAPIST": self = .therapist
        default: self = .unknown(raw)
        }
    }
}

/// Assuntos do "Como podemos ajudar?". O servidor também aceita sem categoria.
enum SupCategory: String, CaseIterable, Identifiable, Encodable {
    case conta = "CONTA"
    case agenda = "AGENDA"
    case pacientes = "PACIENTES"
    case prontuarios = "PRONTUARIOS"
    case financeiro = "FINANCEIRO"
    case gateway = "GATEWAY"
    case assinatura = "ASSINATURA"
    case aplicativo = "APLICATIVO"
    case outro = "OUTRO"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .conta: "Conta e acesso"
        case .agenda: "Agenda"
        case .pacientes: "Pacientes"
        case .prontuarios: "Prontuários"
        case .financeiro: "Fluxo de caixa"
        case .gateway: "Acolher Financeiro"
        case .assinatura: "Assinatura"
        case .aplicativo: "Aplicativo"
        case .outro: "Outro assunto"
        }
    }

    var icon: String {
        switch self {
        case .conta: "person.crop.circle"
        case .agenda: "calendar"
        case .pacientes: "person.2"
        case .prontuarios: "doc.text"
        case .financeiro: "dollarsign"
        case .gateway: "building.columns"
        case .assinatura: "creditcard"
        case .aplicativo: "iphone"
        case .outro: "ellipsis.bubble"
        }
    }

    static func label(for raw: String?) -> String? {
        raw.flatMap { SupCategory(rawValue: $0)?.label }
    }
}

struct SupPerson: Decodable, Equatable {
    let id: String?
    let name: String
}

struct SupAttachment: Decodable, Equatable {
    var url: String
    var expiresAt: Date?
    let contentType: String
    let sizeBytes: Int?
    let name: String?
    let durationMs: Int?
    let width: Int?
    let height: Int?

    var resolvedURL: URL? { URL(string: url) }

    /// Falta menos de um minuto pra URL vencer: renovar antes de abrir ou tocar.
    var isExpiringSoon: Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSinceNow < 60
    }
}

struct SupMessage: Decodable, Identifiable, Equatable {
    let id: String
    let ticketId: String
    let clientId: String?
    let type: SupMessageType
    let senderRole: SupSenderRole
    let sender: SupPerson?
    let text: String?
    var attachment: SupAttachment?
    let createdAt: Date

    var isMine: Bool { senderRole == .therapist }
    var isSystem: Bool { senderRole == .system || type == .system }
}

struct SupLastMessage: Decodable, Equatable {
    let type: SupMessageType
    let senderRole: SupSenderRole
    let preview: String?
    let createdAt: Date
}

struct SupTicket: Decodable, Identifiable, Equatable {
    let id: String
    let number: Int
    let status: SupTicketStatus
    let category: String?
    let subject: String?
    let waitingFor: SupWaitingFor?
    let assignedAdmin: SupPerson?
    let lastMessage: SupLastMessage?
    let unreadCount: Int?
    let createdAt: Date
    let resolvedAt: Date?
    /// Até quando o time já leu a conversa (persiste o "Visto" ao reabrir).
    let adminLastReadAt: Date?

    var unread: Int { unreadCount ?? 0 }

    var title: String {
        if let subject, !subject.isEmpty { return subject }
        return SupCategory.label(for: category) ?? "Atendimento"
    }

    var lastActivity: Date { lastMessage?.createdAt ?? createdAt }
}

struct SupSummary: Decodable, Equatable {
    let openTicketId: String?
    let unreadCount: Int
}

struct SupTicketPage: Decodable {
    let items: [SupTicket]
    let total: Int?
    let page: Int?
    let pageSize: Int?
}

struct SupMessagePage: Decodable {
    let items: [SupMessage]
    let hasMore: Bool
}

struct SupCreatedTicket: Decodable {
    let ticket: SupTicket
    let message: SupMessage
}

struct SupUploadGrant: Decodable {
    let uploadId: String
    let uploadUrl: String
    let method: String?
    let headers: [String: String]?
    let maxBytes: Int?
    let expiresAt: Date?
}

struct SupUploadResult: Decodable {
    let uploadId: String
    let status: String?
    let contentType: String?
    let sizeBytes: Int?
}

struct SupAttachmentURL: Decodable {
    let url: String
    let expiresAt: Date?
}

struct SupRealtimeTicket: Decodable {
    let ticket: String
    let url: String
    let expiresInSeconds: Int?
}

struct SupReadAck: Decodable {
    let ok: Bool?
    let at: Date?
}

/// Rota de navegação pra uma conversa (só o id: `navigationDestination(item:)` exige Hashable).
struct SupChatRoute: Hashable, Identifiable {
    let id: String
}

// MARK: - Regras de anexo (mesma tabela do servidor)

enum SupUploadKind: String, Encodable {
    case image = "IMAGE"
    case video = "VIDEO"
    case audio = "AUDIO"
    case file = "FILE"

    private static let mb = 1024 * 1024

    var maxBytes: Int {
        switch self {
        case .image: 10 * Self.mb
        case .video: 50 * Self.mb
        case .audio: 10 * Self.mb
        case .file: 15 * Self.mb
        }
    }

    var maxLabel: String {
        switch self {
        case .image, .audio: "10 MB"
        case .video: "50 MB"
        case .file: "15 MB"
        }
    }

    var allowedContentTypes: Set<String> {
        switch self {
        case .image: ["image/jpeg", "image/png", "image/webp", "image/gif"]
        case .video: ["video/mp4", "video/quicktime", "video/webm"]
        case .audio: ["audio/mp4", "audio/x-m4a", "audio/aac", "audio/mpeg", "audio/webm", "audio/ogg"]
        case .file: [
            "application/pdf", "text/plain", "text/csv",
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        ]
        }
    }

    /// Mensagem em português do problema, ou nil se o arquivo pode subir.
    func validate(contentType: String, sizeBytes: Int, durationMs: Int?) -> String? {
        guard allowedContentTypes.contains(contentType) else {
            return "Esse tipo de arquivo não é aceito no suporte."
        }
        guard sizeBytes > 0 else { return "O arquivo está vazio." }
        guard sizeBytes <= maxBytes else {
            return "Arquivo muito grande. O máximo é \(maxLabel)."
        }
        if self == .audio, let durationMs, durationMs > 300_000 {
            return "O áudio pode ter no máximo 5 minutos."
        }
        return nil
    }
}

// MARK: - Decodificação fora do APIClient (eventos do WebSocket, PUT de upload)

enum SupJSON {
    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso = ISO8601DateFormatter()

    /// Mesma estratégia de datas do `APIClient` (ISO-8601 com ou sem frações).
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            if let date = isoFractional.date(from: value) ?? iso.date(from: value) {
                return date
            }
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Data inválida: \(value)"
            ))
        }
        return decoder
    }()

    /// Extrai o `message` do corpo de erro padrão do Nest.
    static func errorMessage(from data: Data, status: Int) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let text = object["message"] as? String, !text.isEmpty { return text }
            if let list = object["message"] as? [String], !list.isEmpty { return list.joined(separator: "\n") }
        }
        switch status {
        case 403: return "O prazo desse envio venceu. Tente de novo."
        case 409: return "Esse arquivo já foi enviado."
        case 413: return "Arquivo maior que o permitido."
        case 415: return "Esse tipo de arquivo não é aceito."
        default: return "Não foi possível enviar o arquivo (código \(status))."
        }
    }
}

// MARK: - API

enum SupportAPI {
    static func summary() async throws -> SupSummary {
        try await APIClient.shared.get("support/summary")
    }

    static func tickets(page: Int = 1, pageSize: Int = 50) async throws -> SupTicketPage {
        try await APIClient.shared.get(
            "support/tickets",
            query: ["page": String(page), "pageSize": String(pageSize)]
        )
    }

    static func createTicket(category: SupCategory?, text: String) async throws -> SupCreatedTicket {
        struct Body: Encodable {
            let category: SupCategory?
            let text: String
        }
        return try await APIClient.shared.post("support/tickets", body: Body(category: category, text: text))
    }

    static func ticket(id: String) async throws -> SupTicket {
        try await APIClient.shared.get("support/tickets/\(id)")
    }

    static func messages(
        ticketId: String,
        before: String? = nil,
        after: String? = nil,
        limit: Int = 50
    ) async throws -> SupMessagePage {
        try await APIClient.shared.get(
            "support/tickets/\(ticketId)/messages",
            query: ["before": before, "after": after, "limit": String(limit)]
        )
    }

    static func send(ticketId: String, clientId: String, text: String?, uploadId: String?) async throws -> SupMessage {
        struct Body: Encodable {
            let clientId: String
            let text: String?
            let uploadId: String?
        }
        return try await APIClient.shared.post(
            "support/tickets/\(ticketId)/messages",
            body: Body(clientId: clientId, text: text, uploadId: uploadId)
        )
    }

    static func requestUpload(ticketId: String, file: SupLocalFile) async throws -> SupUploadGrant {
        struct Body: Encodable {
            let kind: SupUploadKind
            let contentType: String
            let sizeBytes: Int
            let fileName: String?
            let durationMs: Int?
            let width: Int?
            let height: Int?
        }
        return try await APIClient.shared.post(
            "support/tickets/\(ticketId)/uploads",
            body: Body(
                kind: file.kind,
                contentType: file.contentType,
                sizeBytes: file.sizeBytes,
                fileName: file.fileName,
                durationMs: file.durationMs,
                width: file.width,
                height: file.height
            )
        )
    }

    static func markRead(ticketId: String) async throws -> SupReadAck {
        try await APIClient.shared.post("support/tickets/\(ticketId)/read")
    }

    static func attachmentURL(messageId: String) async throws -> SupAttachmentURL {
        try await APIClient.shared.get("support/messages/\(messageId)/attachment")
    }

    static func realtimeTicket() async throws -> SupRealtimeTicket {
        try await APIClient.shared.post("support/realtime/ticket")
    }
}

// MARK: - PUT do arquivo cru

/// Sobe o arquivo direto na API (a mídia não passa por proxy nenhum).
///
/// Sem `Authorization`: o token vai assinado na própria URL. Mandar o Bearer
/// junto só espalharia a credencial por uma rota que não precisa dela.
final class SupUploader: NSObject, URLSessionTaskDelegate {
    private let onProgress: @Sendable (Double) -> Void

    private init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        onProgress(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
    }

    static func put(
        fileURL: URL,
        grant: SupUploadGrant,
        contentType: String,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> SupUploadResult {
        guard let url = URL(string: grant.uploadUrl) else {
            throw APIError(statusCode: 0, message: "Endereço de envio inválido.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = grant.method ?? "PUT"
        for (header, value) in grant.headers ?? [:] where header.lowercased() != "authorization" {
            request.setValue(value, forHTTPHeaderField: header)
        }
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")

        let delegate = SupUploader(onProgress: onProgress)
        let (data, response) = try await URLSession.shared.upload(for: request, fromFile: fileURL, delegate: delegate)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200 ..< 300).contains(status) else {
            throw APIError(statusCode: status, message: SupJSON.errorMessage(from: data, status: status))
        }
        return (try? SupJSON.decoder.decode(SupUploadResult.self, from: data))
            ?? SupUploadResult(uploadId: grant.uploadId, status: "READY", contentType: contentType, sizeBytes: nil)
    }
}

// MARK: - Formatação

enum SupFormat {
    private static func formatter(_ pattern: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = pattern
        return formatter
    }

    static let hora = formatter("HH:mm")
    static let diaMes = formatter("d 'de' MMMM")
    static let diaMesAno = formatter("d 'de' MMMM 'de' yyyy")
    static let dataCurta = formatter("dd/MM/yyyy")
    static let dataHora = formatter("dd/MM 'às' HH:mm")

    static func dia(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Hoje" }
        if calendar.isDateInYesterday(date) { return "Ontem" }
        if calendar.component(.year, from: date) == calendar.component(.year, from: Date()) {
            return diaMes.string(from: date)
        }
        return diaMesAno.string(from: date)
    }

    static func duracao(_ segundos: TimeInterval) -> String {
        let total = max(0, Int(segundos.isFinite ? segundos : 0))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func duracao(ms: Int?) -> String? {
        ms.map { duracao(Double($0) / 1000) }
    }

    static func tamanho(_ bytes: Int?) -> String? {
        bytes.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }
    }
}
