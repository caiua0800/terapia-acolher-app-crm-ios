import Foundation

// Os LEADS são reais: vêm da API do CRM (`integrations/leads`), que os lê do
// sistema de leads da Terapia Acolher em nome do terapeuta — ver LeadsStore.
// Créditos e compra: LeadsCheckoutModels.swift (reais desde 2026-09-23).

// MARK: - Lead
//
// Campos espelham o quiz da landing (isaackAmaral/terapia-acolher-landing,
// `lib/types.ts` → WebhookPayload). Manter os mesmos nomes de domínio evita
// tradução perdida quando a integração real existir.

enum LeadStatus: String, CaseIterable, Identifiable, Codable {
    case novo             // recebido, ninguém falou com ele ainda
    case tentandoContato
    case negociando
    case agendado
    case naoConverteu

    var id: String { rawValue }

    var label: String {
        switch self {
        case .novo: "Não contactado"
        case .tentandoContato: "Tentando contato"
        case .negociando: "Negociando"
        case .agendado: "Agendado"
        case .naoConverteu: "Não converteu"
        }
    }

    /// Rótulo curto para a badge do card (o longo quebra a linha).
    var shortLabel: String {
        switch self {
        case .novo: "NOVO"
        case .tentandoContato: "EM CONTATO"
        case .negociando: "NEGOCIANDO"
        case .agendado: "AGENDADO"
        case .naoConverteu: "NÃO CONVERTEU"
        }
    }

    var icon: String {
        switch self {
        case .novo: "sparkles"
        case .tentandoContato: "phone"
        case .negociando: "bubble.left.and.bubble.right"
        case .agendado: "calendar.badge.checkmark"
        case .naoConverteu: "xmark"
        }
    }

    /// Só quem ainda não foi contactado tem relógio correndo contra.
    var countsForSLA: Bool { self == .novo }

    /// Estados que ainda podem virar paciente.
    var isOpen: Bool { self != .agendado && self != .naoConverteu }
}

enum LeadTherapyFor: String, Codable {
    case normal, casal, infantil, outraPessoa = "outra_pessoa"

    var label: String {
        switch self {
        case .normal: "Para si"
        case .casal: "Casal"
        case .infantil: "Criança"
        case .outraPessoa: "Outra pessoa"
        }
    }
}

enum LeadGender: String, Codable {
    case feminino, masculino, outro

    var label: String {
        switch self {
        case .feminino: "Feminino"
        case .masculino: "Masculino"
        case .outro: "Prefere não dizer"
        }
    }
}

enum LeadShift: String, Codable {
    case manha, tarde, noite, qualquer

    var label: String {
        switch self {
        case .manha: "Manhã"
        case .tarde: "Tarde"
        case .noite: "Noite"
        case .qualquer: "Qualquer horário"
        }
    }
}

struct Lead: Identifiable, Hashable, Decodable {
    let id: String
    var status: LeadStatus
    let receivedAt: Date

    // Vindos do quiz
    let name: String
    /// Só dígitos com DDI (pronto para `wa.me/`). Vazio se veio sem telefone.
    let whatsapp: String
    let gender: LeadGender
    let preferredTherapistGender: String   // feminino | masculino | indiferente
    let shift: LeadShift
    let reason: String                     // "O que você está buscando?"
    let therapyFor: LeadTherapyFor
    let contactWhen: String                // "Ex.: hoje depois das 19h"

    // Condicionais do quiz
    let childName: String?
    let childAge: String?
    let relativeName: String?
    let relativeContact: String?

    /// Preenchido quando o lead vira paciente — é o que permite medir conversão.
    var convertedPatientId: String?

    /// A API fala o vocabulário do quiz (nome, motivo, paraQuem…); o app fala
    /// inglês como o resto do código. A tradução mora só aqui.
    enum CodingKeys: String, CodingKey {
        case id, status, whatsapp
        case receivedAt = "recebidoEm"
        case name = "nome"
        case gender = "genero"
        case preferredTherapistGender = "terapeutaPreferido"
        case shift = "turno"
        case reason = "motivo"
        case therapyFor = "paraQuem"
        case contactWhen = "quandoContactar"
        case childName = "nomeCrianca"
        case childAge = "idadeCrianca"
        case relativeName = "nomeParente"
        case relativeContact = "contatoParente"
        case convertedPatientId = "pacienteConvertidoId"
    }

    /// Telefone legível na ficha ("+55 (11) 99999-0000").
    var whatsappLegivel: String {
        whatsapp.isEmpty ? "—" : PatientMask.whatsapp(whatsapp)
    }

    var preferredTherapistLabel: String {
        switch preferredTherapistGender {
        case "feminino": "Terapeuta mulher"
        case "masculino": "Terapeuta homem"
        default: "Tanto faz"
        }
    }

    /// Horas desde que o lead chegou.
    var hoursSinceReceived: Int {
        max(0, Int(Date().timeIntervalSince(receivedAt) / 3600))
    }

    var elapsedLabel: String {
        let h = hoursSinceReceived
        if h < 1 { return "agora há pouco" }
        if h < 24 { return "há \(h)h" }
        let d = h / 24
        return d == 1 ? "há 1 dia" : "há \(d) dias"
    }

    /// Urgência do SLA. Só corre enquanto ninguém falou com o lead — depois do
    /// primeiro contato o relógio perde o sentido de alarme.
    enum SLA { case fresh, warning, late, none }

    var sla: SLA {
        guard status.countsForSLA else { return .none }
        switch hoursSinceReceived {
        case ..<6: return .fresh
        case ..<24: return .warning
        default: return .late
        }
    }
}

// MARK: - Conexão com o sistema de leads

/// Resposta de `integrations/leads/status`.
struct LeadsConnectionStatus: Decodable {
    let configured: Bool
    let connected: Bool
    /// Sistema de leads fora do ar: o vínculo continua, só os dados somem.
    let indisponivel: Bool?
    /// O token foi revogado lá; o vínculo aqui já foi desfeito.
    let revogada: Bool?
    let therapistId: Int?
    let nome: String?
    let statusConta: String?
    let saldo: Int?
    let totalRecebidos: Int?
    let ultimoRecebidoEm: Date?
}

// MARK: - API

enum LeadsAPI {
    static func status() async throws -> LeadsConnectionStatus {
        try await APIClient.shared.get("integrations/leads/status")
    }

    static func connectUrl() async throws -> URL? {
        struct Resposta: Decodable { let url: String }
        let r: Resposta = try await APIClient.shared.get("integrations/leads/connect-url")
        return URL(string: r.url)
    }

    static func list() async throws -> [Lead] {
        try await APIClient.shared.get("integrations/leads")
    }

    static func updateStatus(_ id: String, to status: LeadStatus) async throws {
        struct Body: Encodable { let status: String }
        struct Ok: Decodable { let id: String? }
        let _: Ok = try await APIClient.shared.patch(
            "integrations/leads/\(id)/status",
            body: Body(status: status.rawValue)
        )
    }

    static func linkPatient(_ id: String, patientId: String) async throws {
        struct Body: Encodable { let patientId: String }
        struct Ok: Decodable { let id: String? }
        let _: Ok = try await APIClient.shared.patch(
            "integrations/leads/\(id)/patient",
            body: Body(patientId: patientId)
        )
    }

    static func disconnect() async throws {
        struct Ok: Decodable { let disconnected: Bool? }
        let _: Ok = try await APIClient.shared.delete("integrations/leads")
    }
}
