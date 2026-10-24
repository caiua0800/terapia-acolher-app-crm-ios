import SwiftUI

// MARK: - "Quero o Zelo na reunião" (2026-10-22)
//
// O Zelo é o robô que entra na sala do Meet gerada pelo CRM e faz a
// transcrição. Sem ele na reunião não há transcrição; por isso a chave é
// explícita, desligada por padrão na sessão nova. Textos iguais aos do web
// (`agenda/nova/nova-sessao.tsx` e `agenda/sessao/[id]/detalhe.tsx`).

/// GET sessions/zelo — dá para ligar? `restantes` nil = sem limite.
struct ZeloAvailability: Decodable, Equatable {
    let disponivel: Bool
    /// "PLANO" | "COTA" | nil
    let motivo: String?
    let restantes: Int?
}

/// GET sessions/:id/zelo — o Zelo nesta sessão agora. nil = não deu para
/// perguntar ao Google.
struct ZeloInSession: Decodable, Equatable {
    let emAndamento: Bool?
    let zeloNaSala: Bool?
    /// Perto do horário (5 min antes até 30 min depois do fim).
    let noHorario: Bool
    let retiradoEm: Date?
}

enum ZeloText {
    static let base = "A transcrição da sessão só é gerada com o Zelo na reunião."

    /// Descrição da chave na sessão nova: sem crédito, diz o porquê.
    static func newSession(_ zelo: ZeloAvailability?, loading: Bool) -> String {
        if loading { return base }
        guard let zelo else { return "\(base) Não foi possível conferir seu plano agora." }
        switch zelo.motivo {
        case "PLANO": return "\(base) Seu plano não inclui transcrição das sessões online."
        case "COTA": return "\(base) Você já usou todas as transcrições deste ciclo."
        default: break
        }
        if let restantes = zelo.restantes {
            return "\(base) \(restantes == 1 ? "Resta 1 transcrição" : "Restam \(restantes) transcrições") neste ciclo."
        }
        return base
    }

    /// Descrição da chave no detalhe da sessão.
    static func detail(_ zelo: ZeloAvailability?) -> String {
        let base = "A transcrição só é gerada com o Zelo na reunião."
        switch zelo?.motivo {
        case "PLANO": return "\(base) Seu plano não inclui transcrição das sessões online."
        case "COTA": return "\(base) Você já usou todas as transcrições deste ciclo."
        default: return base
        }
    }
}

/// Chave com rótulo e descrição, no tom do bloco do Meet.
struct ZeloToggleRow: View {
    let isOn: Bool
    let isEnabled: Bool
    var isLoading = false
    let description: String
    let onChange: (Bool) -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { isOn }, set: { onChange($0) })) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Quero o Zelo na reunião")
                        .font(Theme.body(15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    if isLoading {
                        ProgressView().controlSize(.mini)
                    }
                }
                Text(description)
                    .font(Theme.body(12))
                    .foregroundStyle(Color(hex: 0x3E637F).opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(Theme.primary)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.75)
    }
}
