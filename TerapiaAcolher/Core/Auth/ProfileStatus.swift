import Foundation
import Observation

/// Espelho de `GET /auth/profile-status`.
///
/// O backend é quem decide o que está pendente; o app só desenha. Assim o
/// modal do Início e a tela de perfil nunca discordam sobre o que falta.
struct ProfilePendency: Codable, Identifiable, Equatable {
    let code: String
    let title: String
    let description: String
    let field: String

    var id: String { code }

    var icon: String {
        switch code {
        case "EMAIL_NAO_VERIFICADO": "envelope.badge"
        case "WHATSAPP_AUSENTE": "phone.badge.plus"
        default: "checkmark.shield"
        }
    }
}

struct ProfileStatus: Codable, Equatable {
    let complete: Bool
    let whatsappEnabled: Bool
    let whatsapp: String?
    let whatsappMasked: String?
    let phoneVerifiedAt: String?
    let emailVerifiedAt: String?
    let pendencias: [ProfilePendency]

    /// O que realmente cabe mostrar: sem o canal de WhatsApp configurado no
    /// servidor, cobrar verificação seria pedir algo impossível de concluir.
    var pendenciasVisiveis: [ProfilePendency] {
        pendencias.filter { p in
            p.code == "WHATSAPP_NAO_VERIFICADO" ? whatsappEnabled : true
        }
    }

    var temPendencia: Bool { !pendenciasVisiveis.isEmpty }
}

/// Estado compartilhado — o Início consulta, o perfil atualiza, os dois veem
/// o mesmo. Sem isso o modal reapareceria depois de o número ser verificado.
@Observable
final class ProfileStatusStore {
    static let shared = ProfileStatusStore()
    private init() {}

    private(set) var status: ProfileStatus?
    /// Marcado quando o terapeuta dispensa o modal — some até reabrir o app.
    var dispensadoNestaSessao = false

    @MainActor
    func refresh() async {
        status = try? await APIClient.shared.get("auth/profile-status")
    }

    @MainActor
    func limpar() {
        status = nil
        dispensadoNestaSessao = false
    }
}
