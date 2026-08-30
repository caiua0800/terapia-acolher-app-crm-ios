import Foundation

// MARK: - Status da conexão

struct VitrineStatus: Decodable {
    struct Plano: Decodable {
        let tipo: String
        let status: String
        let expiraEm: Date?
    }

    struct Mes: Decodable {
        let visualizacoes: Int
        let cliquesWhatsapp: Int
    }

    let configured: Bool
    let connected: Bool
    /// A Vitrine pode estar fora do ar sem que o vínculo tenha caído — nesse
    /// caso vem conectado, mas sem os números.
    let indisponivel: Bool?
    let therapistId: Int?
    let slug: String?
    let perfilAtivo: Bool?
    let plano: Plano?
    let mes: Mes?
    let impressoesTotais: Int?

    var planoLegivel: String {
        switch plano?.tipo {
        case "FREE": "Gratuito"
        case let t?: t.capitalized
        case nil: "—"
        }
    }
}

// MARK: - Perfil (espelha o TherapistProfileDto da Vitrine)

struct VitrineProfile: Codable {
    let id: Int
    var name: String?
    var crp: String?
    var gender: String?
    var photoUrl: String?
    var bio: String?
    var state: String?
    var city: String?
    var whatsapp: String?
    var modalities: [String]?
    var specialties: [String]?
    var targetAudience: [String]?
    var shifts: [String]?
    var approaches: [String]?
    var approachOther: String?
    var languages: String?
    var consultationPrice: Double?
    var isActive: Bool?
    let slug: String?
}

/// Só o que o formulário envia. Campos ausentes não são tocados na Vitrine —
/// mandar o objeto inteiro faria o app sobrescrever com dados velhos aquilo
/// que ele nem exibe.
struct VitrineProfilePatch: Encodable {
    var name: String?
    var bio: String?
    var state: String?
    var city: String?
    var whatsapp: String?
    var modalities: [String]?
    var specialties: [String]?
    var targetAudience: [String]?
    var shifts: [String]?
    var approaches: [String]?
    var languages: String?
    var consultationPrice: Double?
}

// MARK: - Listas de domínio
//
// Vêm da Vitrine e NUNCA são redeclaradas aqui. Foi assim que a opção "Outra"
// sumiu do cadastro no sistema antigo deles — o front tinha a própria cópia.

struct VitrineOptions: Decodable {
    let specialties: [String]?
    let approaches: [String]?
    let targetAudience: [String]?
    let shifts: [String]?
    let modalities: [String]?
    let languages: [String]?
    let states: [String]?
}

// MARK: - API

enum VitrineAPI {
    static func status() async throws -> VitrineStatus {
        try await APIClient.shared.get("integrations/vitrine/status")
    }

    static func connectUrl() async throws -> URL? {
        struct Resposta: Decodable { let url: String }
        let r: Resposta = try await APIClient.shared.get("integrations/vitrine/connect-url")
        return URL(string: r.url)
    }

    static func profile() async throws -> VitrineProfile {
        try await APIClient.shared.get("integrations/vitrine/profile")
    }

    static func options() async throws -> VitrineOptions {
        try await APIClient.shared.get("integrations/vitrine/options")
    }

    static func save(_ patch: VitrineProfilePatch) async throws {
        struct Ok: Decodable { let success: Bool? }
        let _: Ok = try await APIClient.shared.patch(
            "integrations/vitrine/profile",
            body: patch
        )
    }

    static func disconnect() async throws {
        struct Ok: Decodable { let disconnected: Bool? }
        let _: Ok = try await APIClient.shared.delete("integrations/vitrine")
    }
}
