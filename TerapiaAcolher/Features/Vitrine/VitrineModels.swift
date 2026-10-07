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
    /// `false` = o plano não inclui a integração com a Vitrine. O perfil
    /// continua no ar lá; só não aparece no app.
    let planIncludes: Bool?
    /// `false` = números do perfil fora do plano (o backend já tira `mes`).
    let metricsIncluded: Bool?
    /// A Vitrine pode estar fora do ar sem que o vínculo tenha caído — nesse
    /// caso vem conectado, mas sem os números.
    let indisponivel: Bool?
    let therapistId: Int?
    let slug: String?
    let perfilAtivo: Bool?
    let plano: Plano?
    let mes: Mes?
    let impressoesTotais: Int?
    /// Disse "Agora não" no convite do Início: não mostrar mais lá.
    /// `var`: o Início esconde na hora, antes de a API confirmar.
    var inviteDismissed: Bool?

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
    var languages: ListaOuTexto?
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
    /// Lista (até 20) — a API da Vitrine aceita array.
    var languages: [String]?
    var consultationPrice: Double?
}

/// Idiomas chegam como lista na API nova e como texto separado por vírgula nos
/// perfis antigos: aceita os dois, sempre expõe lista.
struct ListaOuTexto: Codable, Equatable {
    var itens: [String]

    init(_ itens: [String]) { self.itens = itens }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let lista = try? c.decode([String].self) {
            itens = lista
        } else if let texto = try? c.decode(String.self) {
            itens = texto.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        } else {
            itens = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(itens)
    }
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

    /// "Agora não" no convite do Início — gravado na conta.
    static func dismissInvite() async throws {
        struct Ok: Decodable { let inviteDismissed: Bool? }
        let _: Ok = try await APIClient.shared.post("integrations/vitrine/invite/dismiss")
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
