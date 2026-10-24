import Foundation

// MARK: - Para onde vai quem toca numa notificação (2026-10-23)
//
// Mesma regra do web (`web-app/lib/destino-da-notificacao.ts`) e do Android:
// o `data` que o backend grava diz o destino. Vale para o toque na lista do
// sininho e para o toque no push (o push leva o mesmo `data`).
//
// Ordem: suporte → lead → automação → cobrança → saque → sessão → cobranças
// do paciente → modelo → seção → link. Sem nada disso, só marca como lida.
//
// Só lógica (Foundation): testada sem simulador.

enum NotifDestination: Hashable, Identifiable {
    /// Conversa do suporte.
    case supportChat(ticketId: String)
    /// Seção do menu ("leads", "configuracoes", "agenda"…).
    case section(String)
    /// Acolher Financeiro → Automações.
    case automations
    /// Cobrança com link online (Acolher Financeiro). Sem paciente = avulsa.
    case gatewayCharge(patientId: String?, chargeId: String)
    /// Cobrança no financeiro do paciente.
    case patientCharge(patientId: String, chargeId: String)
    /// Todas as cobranças (cobrança sem paciente e sem link online).
    case allCharges
    /// Extrato do Acolher Financeiro (saque).
    case statement
    /// Detalhe da sessão na Agenda.
    case session(id: String)
    /// Cobranças do paciente (lembrete do mês, sem cobrança específica).
    case patientCharges(patientId: String)
    /// Aviso do time com link https.
    case external(URL)

    var id: String {
        switch self {
        case .supportChat(let ticketId): "suporte-\(ticketId)"
        case .section(let secao): "secao-\(secao)"
        case .automations: "automacoes"
        case .gatewayCharge(let patientId, let chargeId): "gw-\(patientId ?? "avulsa")-\(chargeId)"
        case .patientCharge(let patientId, let chargeId): "fin-\(patientId)-\(chargeId)"
        case .allCharges: "cobrancas"
        case .statement: "extrato"
        case .session(let id): "sessao-\(id)"
        case .patientCharges(let patientId): "cobrancas-\(patientId)"
        case .external(let url): "url-\(url.absoluteString)"
        }
    }

    /// Seções que o backend e os avisos do time (painel admin) usam.
    static let sections: Set<String> = [
        "inicio", "agenda", "pacientes", "prontuarios", "financeiro",
        "gateway", "vitrine", "configuracoes", "assinatura", "leads",
    ]

    /// Decide o destino a partir do tipo e do `data` (só os valores texto).
    static func resolve(type: String?, data: [String: String]) -> NotifDestination? {
        func value(_ key: String) -> String? {
            guard let raw = data[key], !raw.isEmpty else { return nil }
            return raw
        }

        if data["kind"] == "SUPPORT", let ticketId = value("ticketId") {
            return .supportChat(ticketId: ticketId)
        }
        if type == "LEAD_RECEIVED" || data["section"] == "leads" { return .section("leads") }

        if value("automationId") != nil { return .automations }

        let patientId = value("patientId")
        if let chargeId = value("chargeId") {
            if data["section"] == "gateway" {
                return .gatewayCharge(patientId: patientId, chargeId: chargeId)
            }
            if let patientId { return .patientCharge(patientId: patientId, chargeId: chargeId) }
            return .allCharges
        }
        if value("withdrawalId") != nil { return .statement }

        if let sessionId = value("sessionId") { return .session(id: sessionId) }

        // Lembrete do mês de um paciente (sem cobrança específica).
        if let patientId { return .patientCharges(patientId: patientId) }
        if value("templateId") != nil { return .section("configuracoes") }

        if let secao = value("section"), sections.contains(secao) { return .section(secao) }

        // Aviso do time (painel admin) com link.
        if let raw = value("url"), raw.lowercased().hasPrefix("https://"), let url = URL(string: raw) {
            return .external(url)
        }
        return nil
    }

    /// Payload do push: o `data` da notificação chega solto no `userInfo` (e,
    /// em versões antigas do servidor, dentro de `data`). Junta os dois.
    static func resolve(pushUserInfo info: [AnyHashable: Any]) -> NotifDestination? {
        var data: [String: String] = [:]
        if let nested = info["data"] as? [String: Any] {
            for (key, value) in nested { if let text = value as? String { data[key] = text } }
        }
        for (key, value) in info {
            if let key = key as? String, let text = value as? String { data[key] = text }
        }
        return resolve(type: data["type"], data: data)
    }

    /// Seção do menu que "mora" o destino: o push leva o menu até lá antes de
    /// abrir a tela, para o Voltar cair no lugar que faz sentido.
    var homeSection: String? {
        switch self {
        case .supportChat: "suporte"
        case .section(let secao): secao
        case .automations, .gatewayCharge, .statement, .allCharges, .patientCharge, .patientCharges: "gateway"
        case .session: "agenda"
        case .external: nil
        }
    }

    /// Precisa abrir uma tela própria (empilhada), não só trocar de seção.
    var isScreen: Bool {
        switch self {
        case .section, .external: false
        default: true
        }
    }
}
