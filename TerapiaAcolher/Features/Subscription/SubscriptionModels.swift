import Foundation

// MARK: - Assinatura (GET subscription/me)
//
// O app mostra o ESTADO da assinatura; não vende nada. Preço, lista de planos e
// contratação ficam no CRM web de propósito — é o que mantém a cobrança fora do
// aplicativo e, com isso, fora da regra de compra in-app da Apple (ver
// subscriptions.controller.ts e memoria/publicacao-app-store.md). Por isso esta
// camada nem chega a chamar `subscription/plans`.

enum SubscriptionStatus: String, Decodable {
    case trialing = "TRIALING"
    case active = "ACTIVE"
    case expired = "EXPIRED"
    case canceled = "CANCELED"
    /// Comprou na pré-venda; o acesso começa quando o admin iniciar.
    case presale = "PRESALE"
    case none = "NONE"

    /// Desconhecido vira `none` em vez de estourar o decode: status novo no
    /// backend não pode derrubar a tela num app já publicado.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SubscriptionStatus(rawValue: raw) ?? .none
    }

    var label: String {
        switch self {
        case .trialing: "Em teste"
        case .active: "Ativa"
        case .expired: "Expirada"
        case .canceled: "Cancelada"
        case .presale: "Pré-venda"
        case .none: "Sem assinatura"
        }
    }
}

enum SubscriptionPeriodicity: String, Decodable {
    case monthly = "MONTHLY"
    case quarterly = "QUARTERLY"
    case semiannual = "SEMIANNUAL"
    case annual = "ANNUAL"

    /// "Renova todo mês" lê melhor que "periodicidade: MONTHLY".
    var renovacao: String {
        switch self {
        case .monthly: "Renova todo mês"
        case .quarterly: "Renova a cada três meses"
        case .semiannual: "Renova a cada seis meses"
        case .annual: "Renova todo ano"
        }
    }
}

struct SubscriptionPlanRef: Decodable, Hashable {
    let nome: String
    let slug: String
    let periodicidade: SubscriptionPeriodicity?
}

struct SubscriptionScheduledChange: Decodable, Hashable {
    let plano: String?
    let valeEm: Date?
}

/// Uso no ciclo. `teto == -1` é ilimitado — quantidade, nunca custo.
struct SubscriptionUsageItem: Decodable, Hashable {
    let usado: Int
    let teto: Int

    var ilimitado: Bool { teto == UsageLimits.ilimitado }

    /// 0…1 para a barrinha. Sem teto não há barra.
    var fracao: Double {
        guard !ilimitado, teto > 0 else { return 0 }
        return min(1, Double(usado) / Double(teto))
    }

    var apertado: Bool { !ilimitado && fracao >= 0.8 }

    /// Teto zero: o plano não inclui o recurso.
    var foraDoPlano: Bool { teto == 0 }

    /// Cota com teto e já toda usada no ciclo.
    var esgotado: Bool { teto > 0 && usado >= teto }
}

enum UsageLimits {
    static let ilimitado = -1
}

struct SubscriptionUsage: Decodable, Hashable {
    let whatsapp: SubscriptionUsageItem
    /// Soma de prontuário + anamnese — o que backends anteriores mandam.
    let ia: SubscriptionUsageItem
    let pacientes: SubscriptionUsageItem
    /// Cotas separadas do Zelo (desde 2026-09-27). Opcionais: backend antigo
    /// não manda, e aí vale a soma em `ia`.
    let iaProntuarios: SubscriptionUsageItem?
    let iaAnamneses: SubscriptionUsageItem?
    let resumos: SubscriptionUsageItem?

    /// Cota do Zelo para o tipo de registro, com o legado como reserva.
    func zelo(_ kind: RecordsKind) -> SubscriptionUsageItem {
        switch kind {
        case .record: iaProntuarios ?? ia
        case .anamnesis: iaAnamneses ?? ia
        }
    }
}

/// Capacidades do plano — espelho de `common/entitlements/capabilities.ts`.
/// Tipado em vez de dicionário livre: chave nova no backend não quebra o
/// decode (cai no valor padrão) e o app não precisa adivinhar rótulos.
struct SubscriptionEntitlements: Decodable, Hashable {
    var patients: Int = 0
    var whatsappPerCycle: Int = 0
    var aiDraftsPerCycle: Int = 0
    var aiRecordsPerCycle: Int = 0
    var aiAnamnesesPerCycle: Int = 0
    var aiSummariesPerCycle: Int = 0
    var billingAutomation: Bool = false
    var onlineCharges: Bool = false
    var bulkImport: Bool = false
    var transcription: Bool = false
    var acolherFinanceiro: Bool = false
    var vitrine: Bool = false
    var vitrineMetrics: Bool = false
    var leads: Bool = false
    var platformFeeDiscountPercent: Int = 0

    private enum CodingKeys: String, CodingKey {
        case patients, whatsappPerCycle, aiDraftsPerCycle
        case aiRecordsPerCycle, aiAnamnesesPerCycle, aiSummariesPerCycle
        case billingAutomation, onlineCharges, bulkImport, transcription
        case acolherFinanceiro, vitrine, vitrineMetrics, leads
        case platformFeeDiscountPercent
    }

    init() {}

    /// Chave ausente cai no padrão em vez de derrubar o decode: capacidade
    /// nova no backend não pode quebrar um app já publicado na loja.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        patients = try c.decodeIfPresent(Int.self, forKey: .patients) ?? 0
        whatsappPerCycle = try c.decodeIfPresent(Int.self, forKey: .whatsappPerCycle) ?? 0
        aiDraftsPerCycle = try c.decodeIfPresent(Int.self, forKey: .aiDraftsPerCycle) ?? 0
        // Backend anterior à separação só manda a cota somada.
        aiRecordsPerCycle = try c.decodeIfPresent(Int.self, forKey: .aiRecordsPerCycle) ?? aiDraftsPerCycle
        aiAnamnesesPerCycle = try c.decodeIfPresent(Int.self, forKey: .aiAnamnesesPerCycle) ?? aiDraftsPerCycle
        aiSummariesPerCycle = try c.decodeIfPresent(Int.self, forKey: .aiSummariesPerCycle) ?? 0
        billingAutomation = try c.decodeIfPresent(Bool.self, forKey: .billingAutomation) ?? false
        onlineCharges = try c.decodeIfPresent(Bool.self, forKey: .onlineCharges) ?? false
        bulkImport = try c.decodeIfPresent(Bool.self, forKey: .bulkImport) ?? false
        transcription = try c.decodeIfPresent(Bool.self, forKey: .transcription) ?? false
        acolherFinanceiro = try c.decodeIfPresent(Bool.self, forKey: .acolherFinanceiro) ?? false
        vitrine = try c.decodeIfPresent(Bool.self, forKey: .vitrine) ?? false
        vitrineMetrics = try c.decodeIfPresent(Bool.self, forKey: .vitrineMetrics) ?? false
        leads = try c.decodeIfPresent(Bool.self, forKey: .leads) ?? false
        // O backend limita o percentual com Math.min/max, então ele pode vir
        // fracionário (50.5) — decodificar direto em Int falharia.
        let desconto = try c.decodeIfPresent(Double.self, forKey: .platformFeeDiscountPercent) ?? 0
        platformFeeDiscountPercent = Int(desconto.rounded())
    }

    /// O que vale mostrar como "incluído no seu plano", na ordem em que o
    /// terapeuta pensa: primeiro o que ele usa, depois o comercial.
    var destaques: [(rotulo: String, valor: String)] {
        var itens: [(String, String)] = [
            ("Pacientes ativos", Self.quantidade(patients)),
            ("Mensagens de WhatsApp por ciclo", Self.quantidade(whatsappPerCycle)),
        ]
        // Cota zero é "não incluído": some da lista em vez de mostrar "0".
        if aiRecordsPerCycle != 0 {
            itens.append(("Prontuários com o Zelo por ciclo", Self.quantidade(aiRecordsPerCycle)))
        }
        if aiAnamnesesPerCycle != 0 {
            itens.append(("Anamneses com o Zelo por ciclo", Self.quantidade(aiAnamnesesPerCycle)))
        }
        if aiSummariesPerCycle != 0 {
            itens.append(("Resumos do Zelo por ciclo", Self.quantidade(aiSummariesPerCycle)))
        }
        if transcription { itens.append(("Transcrição das sessões online", "Incluída")) }
        if billingAutomation { itens.append(("Automação de cobrança", "Incluída")) }
        if onlineCharges { itens.append(("Cobrança online", "Incluída")) }
        if acolherFinanceiro { itens.append(("Acolher Financeiro", "Incluído")) }
        if bulkImport { itens.append(("Importar pacientes de planilha", "Incluída")) }
        if vitrine { itens.append(("Vitrine no app", "Incluída")) }
        if vitrineMetrics { itens.append(("Números da Vitrine", "Incluídos")) }
        if leads { itens.append(("Leads e créditos no app", "Incluídos")) }
        if platformFeeDiscountPercent > 0 {
            itens.append(("Desconto na taxa da plataforma", "\(platformFeeDiscountPercent)%"))
        }
        return itens
    }

    private static func quantidade(_ value: Int) -> String {
        value == UsageLimits.ilimitado ? "Ilimitado" : String(value)
    }
}

/// GET subscription/me
struct MySubscription: Decodable {
    let enforcing: Bool
    let active: Bool
    let status: SubscriptionStatus
    let plano: SubscriptionPlanRef?
    let trialEndsAt: Date?
    let currentPeriodEnd: Date?
    let cortesia: Bool
    let mudancaAgendada: SubscriptionScheduledChange?
    let uso: SubscriptionUsage
    let recursos: SubscriptionEntitlements

    var emTeste: Bool { status == .trialing }
    var preVenda: Bool { status == .presale }

    /// A data que importa agora: no teste é o fim do teste, assinando é a
    /// renovação.
    var proximaData: Date? { emTeste ? trialEndsAt : currentPeriodEnd }

    /// Dias inteiros até a data, arredondando para cima — faltando 6h ainda é
    /// "1 dia"; dizer "0 dias" com o acesso funcionando confunde.
    var diasRestantes: Int? {
        guard let data = proximaData else { return nil }
        let segundos = data.timeIntervalSinceNow
        return max(0, Int(ceil(segundos / 86_400)))
    }

    /// Só chama atenção quando falta pouco — aviso constante vira paisagem.
    var testeUrgente: Bool {
        guard emTeste, let dias = diasRestantes else { return false }
        return dias <= 5
    }

    var tituloDoPlano: String {
        if cortesia { return "Cortesia" }
        if emTeste { return "Teste grátis" }
        if preVenda { return plano?.nome ?? SubscriptionStatus.presale.label }
        return plano?.nome ?? "Sem plano"
    }
}

enum SubscriptionAPI {
    static func mine() async throws -> MySubscription {
        try await APIClient.shared.get("subscription/me")
    }
}
