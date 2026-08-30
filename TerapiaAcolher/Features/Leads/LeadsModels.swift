import Foundation

// MARK: - ⚠️ MÓDULO EM DEMONSTRAÇÃO
//
// Nada aqui fala com backend. Saldo, pacotes e pagamento são SIMULADOS, para
// validar a experiência antes de existir integração com o sistema de leads.
//
// O item do menu só aparece com `LeadsDemo.enabled == true`. Publicar uma loja
// que finge cobrar seria problema de revisão na App Store e de confiança com o
// terapeuta — então desligar é uma linha, e é deliberado.

enum LeadsDemo {
    static let enabled = true
}

// MARK: - Pacote de créditos

struct LeadPackage: Identifiable, Hashable {
    let id: String
    let name: String
    let leads: Int
    let price: Double
    /// Destaque comercial (o "MAIS POPULAR" do portal web).
    let highlighted: Bool

    /// Preço por lead — o número que permite comparar pacotes de verdade.
    var pricePerLead: Double { price / Double(leads) }
}

// MARK: - Catálogo (espelha o portal do terapeuta)

enum LeadCatalog {
    static let packages: [LeadPackage] = [
        .init(id: "light",    name: "Acolher Light",    leads: 3,  price: 97,   highlighted: false),
        .init(id: "start",    name: "Acolher Start",    leads: 8,  price: 197,  highlighted: false),
        .init(id: "impulso",  name: "Acolher Impulso",  leads: 13, price: 294,  highlighted: true),
        .init(id: "infinity", name: "Acolher Infinity", leads: 25, price: 397,  highlighted: false),
        .init(id: "escala",   name: "Acolher Escala",   leads: 40, price: 597,  highlighted: false),
        .init(id: "giga",     name: "Acolher Giga",     leads: 60, price: 1170, highlighted: false),
    ]

    /// Melhor preço por lead do catálogo — usado para marcar o pacote que mais
    /// compensa, que nem sempre é o maior.
    static var bestPricePerLead: Double {
        packages.map(\.pricePerLead).min() ?? 0
    }
}

// MARK: - Saldo

struct LeadBalance {
    let credits: Int
    let receivedThisMonth: Int
    let convertedThisMonth: Int

    /// Abaixo disso o app passa a cobrar atenção — espelha o "Baixo" do portal.
    static let lowThreshold = 3

    var isLow: Bool { credits < Self.lowThreshold }

    var statusLabel: String { isLow ? "Baixo" : "Ok" }
}

// MARK: - Meio de pagamento (simulado)

enum LeadPaymentMethod: String, CaseIterable, Identifiable {
    case pix, card

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pix: "Pix"
        case .card: "Cartão de crédito"
        }
    }

    var subtitle: String {
        switch self {
        case .pix: "Aprovação na hora"
        case .card: "Em até 12x"
        }
    }

    var icon: String {
        switch self {
        case .pix: "qrcode"
        case .card: "creditcard"
        }
    }
}

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

struct Lead: Identifiable, Hashable {
    let id: String
    var status: LeadStatus
    let receivedAt: Date

    // Vindos do quiz
    let name: String
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
