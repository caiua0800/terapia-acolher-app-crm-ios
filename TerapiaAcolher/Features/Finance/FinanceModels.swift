import Foundation

// MARK: - Referência leve de paciente (DTO próprio do Financeiro)

struct FinPatientRef: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    /// Para a opção "Enviar agora pelo WhatsApp" ao cobrar (2026-10-06).
    /// Opcionais: nem toda tela de origem tem esses dados.
    var whatsapp: String? = nil
    /// WhatsApp ligado para este paciente (ausente = ligado, o padrão).
    var whatsappEnabled: Bool? = nil
}

// MARK: - Transações

enum FinTransactionType: String, Codable {
    case income = "INCOME"
    case expense = "EXPENSE"
}

struct FinTransaction: Decodable, Identifiable {
    let id: String
    let type: FinTransactionType
    let source: String // MANUAL | SESSION_AUTO | GATEWAY
    let description: String
    let amount: Double
    let receivedAmount: Double?
    let date: Date
    let category: String?
    let isRecurring: Bool
    let patient: FinPatientRef?
    let sessionId: String?
    let chargeId: String?

    /// Transações do gateway são imutáveis (regra do backend).
    var isEditable: Bool { source != "GATEWAY" }

    var sourceLabel: String? {
        switch source {
        case "SESSION_AUTO": "Automático"
        case "GATEWAY": "Pagamento online"
        default: nil
        }
    }
}

struct FinBalance: Decodable {
    let month: String
    let incomes: Double
    let expenses: Double
    let balance: Double
    let variationPercent: Double?
}

/// Corpo de criação/edição de transação manual.
struct FinTransactionBody: Encodable {
    var type: String
    var description: String
    var amount: Double
    var receivedAmount: Double?
    var date: String // yyyy-MM-dd
    var category: String?
    var isRecurring: Bool
    var patientId: String?
}

// MARK: - Cobranças

enum FinChargeStatus: String, Decodable {
    case pending = "PENDING"
    case paid = "PAID"
    case overdue = "OVERDUE"
    case canceled = "CANCELED"
}

/// Quem paga uma cobrança avulsa (2026-10-06): não é paciente, não ocupa
/// vaga no plano e não tem ficha. O documento vem mascarado do servidor.
struct FinPayer: Decodable, Hashable {
    let name: String
    let documentMasked: String?
    let email: String?
}

struct FinCharge: Decodable, Identifiable {
    let id: String
    /// Nil na cobrança avulsa (`kind == "STANDALONE"`).
    let patientId: String?
    let patient: FinPatientRef?
    /// PATIENT | STANDALONE. Opcional: backend antigo não manda (= paciente).
    let kind: String?
    let payer: FinPayer?
    /// Lembrete agendado (só cobrança de paciente). Opcional: campo novo.
    let reminderScheduledAt: Date?
    /// Por onde o lembrete agendado sai: "WHATSAPP" e/ou "EMAIL" (2026-10-06).
    let reminderChannels: [String]?
    let description: String
    let referenceMonth: String?
    let amount: Double
    let dueDate: Date
    let status: FinChargeStatus
    let paidAt: Date?
    let paymentMethod: String? // PIX | BOLETO | CARD | MANUAL
    /// Como o terapeuta escolheu receber AO CRIAR. Diferente de
    /// `paymentMethod`, que só existe depois de paga.
    let intendedBillingType: String?
    let gatewayName: String?
    let gatewayInvoiceUrl: String?
    let splitFeeApplied: Double?
    let reminderSentAt: Date?

    var ehAvulsa: Bool { kind == "STANDALONE" || (patientId == nil && payer != nil) }

    /// Nome de quem paga: o paciente ou o pagador avulso.
    var nomeDoPagador: String? { patient?.name ?? payer?.name }

    var paymentMethodLabel: String? {
        switch paymentMethod {
        case "PIX": "Pix"
        case "BOLETO": "Boleto"
        case "CARD": "Cartão"
        case "MANUAL": "Recebido por fora"
        default: nil
        }
    }
}

// MARK: - Todas as cobranças (paginado, 2026-10-06)

struct FinChargesPage: Decodable {
    struct Totais: Decodable {
        let aReceber: Double
        let recebido: Double
        let atrasado: Double
        let quantidade: [String: Int]?
    }

    let itens: [FinCharge]
    let total: Int
    let page: Int
    let perPage: Int
    let totais: Totais?
}

enum FinChargesPeriodo: String, CaseIterable, Identifiable {
    case todos, esteMes, mesPassado, ultimos30, personalizado
    var id: String { rawValue }
    var rotulo: String {
        switch self {
        case .todos: "Qualquer data"
        case .esteMes: "Este mês"
        case .mesPassado: "Mês passado"
        case .ultimos30: "Últimos 30 dias"
        case .personalizado: "Escolher datas"
        }
    }
}

enum FinChargesOrdem: String, CaseIterable, Identifiable {
    case vencimentoDesc = "vencimento_desc"
    case vencimentoAsc = "vencimento_asc"
    case criacaoDesc = "criacao_desc"
    case valorDesc = "valor_desc"
    var id: String { rawValue }
    var rotulo: String {
        switch self {
        case .vencimentoDesc: "Vencimento (mais recentes)"
        case .vencimentoAsc: "Vencimento (mais antigas)"
        case .criacaoDesc: "Criadas por último"
        case .valorDesc: "Maior valor"
        }
    }
}

/// Filtros da tela "Todas as cobranças" — viram a query de `finance/charges/pagina`.
struct FinChargesPageFilter: Equatable {
    var status: FinChargeStatus? = nil
    /// nil = todas · "PATIENT" · "STANDALONE"
    var kind: String? = nil
    /// nil = qualquer · "PIX" · "CARD" · "NENHUM"
    var metodo: String? = nil
    var periodo: FinChargesPeriodo = .todos
    var de: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    var ate: Date = Date()
    var busca: String = ""
    var ordem: FinChargesOrdem = .vencimentoDesc

    var temFiltro: Bool {
        status != nil || kind != nil || metodo != nil || periodo != .todos
            || !busca.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static let dia: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Intervalo do período escolhido (pelo vencimento).
    var intervalo: (de: Date, ate: Date)? {
        let cal = Calendar.current
        let hoje = Date()
        switch periodo {
        case .todos: return nil
        case .esteMes:
            let inicio = cal.date(from: cal.dateComponents([.year, .month], from: hoje)) ?? hoje
            let fim = cal.date(byAdding: DateComponents(month: 1, day: -1), to: inicio) ?? hoje
            return (inicio, fim)
        case .mesPassado:
            let inicioEste = cal.date(from: cal.dateComponents([.year, .month], from: hoje)) ?? hoje
            let inicio = cal.date(byAdding: .month, value: -1, to: inicioEste) ?? hoje
            let fim = cal.date(byAdding: .day, value: -1, to: inicioEste) ?? hoje
            return (inicio, fim)
        case .ultimos30:
            return (cal.date(byAdding: .day, value: -30, to: hoje) ?? hoje, hoje)
        case .personalizado:
            return (min(de, ate), max(de, ate))
        }
    }

    var query: [String: String?] {
        let busca = busca.trimmingCharacters(in: .whitespaces)
        return [
            "status": status?.rawValue,
            "kind": kind,
            "metodo": metodo,
            "de": intervalo.map { Self.dia.string(from: $0.de) },
            "ate": intervalo.map { Self.dia.string(from: $0.ate) },
            "busca": busca.isEmpty ? nil : busca,
            "ordenar": ordem.rawValue,
        ]
    }
}

struct FinChargeSummary: Decodable {
    struct Counts: Decodable {
        let pending: Int
        let overdue: Int
        let paid: Int
        let canceled: Int
    }

    /// Soma das cobranças que existiram de fato (pagas + em aberto).
    /// Canceladas ficam de fora: nunca foram devidas, e somá-las faria
    /// `cobrado − pago − a receber` não fechar.
    ///
    /// Opcionais de propósito: são campos novos. Um app atualizado falando com
    /// uma API mais antiga decodificaria com erro e derrubaria a tela inteira
    /// de cobranças — assim ele apenas esconde o bloco de totais.
    let charged: Double?
    let paid: Double?
    let toReceive: Double
    let overdue: Double
    let counts: Counts

    var total: Int { counts.pending + counts.overdue + counts.paid + counts.canceled }
}

/// Pagador da cobrança avulsa: só o mínimo que o Asaas exige.
struct FinPayerBody: Encodable {
    var name: String
    /// CPF ou CNPJ, só dígitos.
    var document: String
    var email: String?
}

/// Exatamente um de `patientId` ou `payer` (o servidor recusa os dois ou nenhum).
struct FinChargeBody: Encodable {
    var patientId: String?
    var payer: FinPayerBody?
    var description: String
    var amount: Double
    var dueDate: String // yyyy-MM-dd
    var referenceMonth: String?
    /// PIX | CARD. Cobranças antigas "por fora" vêm sem.
    var intendedBillingType: String?
}

struct FinReminderResult: Decodable {
    let emailSent: Bool
    let messageText: String
    let reminderSentAt: Date?
    /// Se o WhatsApp saiu (preferências, cota e número permitindo). Opcional:
    /// backend antigo não manda.
    let whatsappSent: Bool?
    /// Por que o WhatsApp não saiu (preferências, cota, sem número…).
    let whatsappReason: String?
}

/// O que aconteceu com o envio/agendamento do lembrete ao criar a cobrança.
struct FinAvisoDeEnvio: Hashable {
    let texto: String
    let ok: Bool
}

struct FinReminderSchedule: Decodable {
    let reminderScheduledAt: Date?
}

/// `{"at": null}` cancela — por isso o `encode` explícito: o sintetizado
/// omitiria a chave e o servidor não saberia que é para cancelar.
private struct FinReminderScheduleBody: Encodable {
    let at: String?
    /// Canais do lembrete agendado; ausente = o servidor escolhe.
    let canais: [String]?
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(at, forKey: .at)
        try c.encodeIfPresent(canais, forKey: .canais)
    }
    enum CodingKeys: String, CodingKey { case at, canais }
}

/// Canais do envio na hora: sem corpo, o servidor manda pelos dois (apps antigos).
private struct FinReminderBody: Encodable {
    let canais: [String]
}

struct FinDeleted: Decodable {
    let deleted: Bool
}

// MARK: - Chamadas de API do módulo

enum FinanceAPI {
    static func balance(month: String) async throws -> FinBalance {
        try await APIClient.shared.get("finance/balance", query: ["month": month])
    }

    static func transactions(
        month: String?,
        type: FinTransactionType? = nil,
        recurring: Bool? = nil,
        patientId: String? = nil
    ) async throws -> [FinTransaction] {
        try await APIClient.shared.get("finance/transactions", query: [
            "month": month,
            "type": type?.rawValue,
            "recurring": recurring.map { $0 ? "true" : "false" },
            "patientId": patientId,
        ])
    }

    static func createTransaction(_ body: FinTransactionBody) async throws -> FinTransaction {
        try await APIClient.shared.post("finance/transactions", body: body)
    }

    static func updateTransaction(id: String, _ body: FinTransactionBody) async throws -> FinTransaction {
        try await APIClient.shared.patch("finance/transactions/\(id)", body: body)
    }

    static func deleteTransaction(id: String) async throws -> FinDeleted {
        try await APIClient.shared.delete("finance/transactions/\(id)")
    }

    /// `kind`: "STANDALONE" lista só as avulsas; nil traz todas (backend antigo ignora).
    static func charges(
        patientId: String?,
        status: FinChargeStatus? = nil,
        kind: String? = nil
    ) async throws -> [FinCharge] {
        try await APIClient.shared.get("finance/charges", query: [
            "patientId": patientId,
            "status": status?.rawValue,
            "kind": kind,
        ])
    }

    static func chargesSummary(patientId: String?) async throws -> FinChargeSummary {
        try await APIClient.shared.get("finance/charges/summary", query: ["patientId": patientId])
    }

    static func createCharge(_ body: FinChargeBody) async throws -> FinCharge {
        try await APIClient.shared.post("finance/charges", body: body)
    }

    static func cancelCharge(id: String) async throws -> FinCharge {
        try await APIClient.shared.patch("finance/charges/\(id)/cancel")
    }

    /// `canais`: ["WHATSAPP"], ["EMAIL"] ou os dois (2026-10-06). Sem canais,
    /// o servidor manda pelos dois — era o que fazia "Enviar agora pelo
    /// WhatsApp" mandar também um e-mail.
    static func sendReminder(id: String, canais: [String]? = nil) async throws -> FinReminderResult {
        if let canais {
            return try await APIClient.shared.post(
                "finance/charges/\(id)/reminder",
                body: FinReminderBody(canais: canais)
            )
        }
        return try await APIClient.shared.post("finance/charges/\(id)/reminder")
    }

    /// Agenda (ou, com `nil`, cancela) o lembrete da cobrança.
    static func scheduleReminder(id: String, at: Date?, canais: [String]? = nil) async throws -> FinReminderSchedule {
        try await APIClient.shared.put(
            "finance/charges/\(id)/reminder-schedule",
            body: FinReminderScheduleBody(at: at.map(FinFormat.isoComFuso), canais: at == nil ? nil : canais)
        )
    }

    /// Todas as cobranças, paginado e filtrado (`GET finance/charges/pagina`).
    static func chargesPage(_ filtro: FinChargesPageFilter, page: Int, perPage: Int = 20) async throws -> FinChargesPage {
        try await APIClient.shared.get("finance/charges/pagina", query: filtro.query.merging([
            "page": String(page),
            "perPage": String(perPage),
        ]) { _, novo in novo })
    }

    static func patients(search: String?) async throws -> [FinPatientRef] {
        try await APIClient.shared.get("patients", query: ["search": search])
    }
}

// MARK: - Formatação de datas e valores do Financeiro

enum FinFormat {
    static let monthQuery: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }()

    static let monthTitle: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "MMMM 'de' yyyy"
        return formatter
    }()

    static let dayMonth: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM"
        return formatter
    }()

    /// Datas-calendário (vencimento) são gravadas à meia-noite UTC — formatar em UTC.
    static let dayMonthUTC: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    /// "2026-10-10T09:00:00-03:00": momento com o fuso do aparelho, para o
    /// servidor agendar no horário que o terapeuta escolheu.
    static func isoComFuso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = .current
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    /// "10/10 às 09:00".
    static let diaEHora: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "dd/MM 'às' HH:mm"
        return formatter
    }()

    static let isoDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// "Julho de 2026" (primeira letra maiúscula, como no design).
    static func monthTitleText(_ date: Date) -> String {
        let raw = monthTitle.string(from: date)
        return raw.prefix(1).uppercased() + raw.dropFirst()
    }

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Timestamps exatamente à meia-noite UTC são datas-calendário do backend
    /// (transações manuais, vencimentos). Timestamps com hora (SESSION_AUTO)
    /// são momentos reais e devem ser tratados no fuso local.
    static func isUTCCalendarDay(_ date: Date) -> Bool {
        let comps = utcCalendar.dateComponents([.hour, .minute, .second], from: date)
        return comps.hour == 0 && comps.minute == 0 && comps.second == 0
    }

    /// Converte um dia-calendário UTC (meia-noite UTC) pra data no MESMO dia
    /// do fuso local. Timestamps reais passam inalterados.
    static func localDate(fromCalendarDay date: Date) -> Date {
        guard isUTCCalendarDay(date) else { return date }
        let comps = utcCalendar.dateComponents([.year, .month, .day], from: date)
        return Calendar.current.date(from: comps) ?? date
    }

    /// "Hoje", "Ontem" ou dd/MM.
    /// Dias-calendário UTC são comparados/formatados pelo dia UTC gravado;
    /// timestamps reais (SESSION_AUTO), pelo fuso local.
    static func relativeDay(_ date: Date) -> String {
        if isUTCCalendarDay(date) {
            let local = localDate(fromCalendarDay: date)
            if Calendar.current.isDateInToday(local) { return "Hoje" }
            if Calendar.current.isDateInYesterday(local) { return "Ontem" }
            return dayMonthUTC.string(from: date)
        }
        if Calendar.current.isDateInToday(date) { return "Hoje" }
        if Calendar.current.isDateInYesterday(date) { return "Ontem" }
        return dayMonth.string(from: date)
    }

    /// Dias entre hoje (dia local) e o vencimento (dia-calendário UTC).
    static func daysUntilDue(_ dueDate: Date) -> Int {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        let components = utcCalendar.dateComponents([.year, .month, .day], from: dueDate)
        let calendar = Calendar.current
        guard let dueLocal = calendar.date(from: components) else { return 0 }
        let start = calendar.startOfDay(for: Date())
        return calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: dueLocal)).day ?? 0
    }

    /// Converte texto PT-BR ("1.234,56") em Double.
    static func parseAmount(_ text: String) -> Double? {
        let normalized = text
            .replacingOccurrences(of: "R$", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }
}

