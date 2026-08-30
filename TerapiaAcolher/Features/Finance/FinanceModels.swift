import Foundation

// MARK: - Referência leve de paciente (DTO próprio do Financeiro)

struct FinPatientRef: Codable, Identifiable, Hashable {
    let id: String
    let name: String
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

struct FinCharge: Decodable, Identifiable {
    let id: String
    let patientId: String
    let patient: FinPatientRef?
    let description: String
    let referenceMonth: String?
    let amount: Double
    let dueDate: Date
    let status: FinChargeStatus
    let paidAt: Date?
    let paymentMethod: String? // PIX | BOLETO | CARD | MANUAL
    let gatewayName: String?
    let gatewayInvoiceUrl: String?
    let splitFeeApplied: Double?
    let reminderSentAt: Date?

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

struct FinChargeBody: Encodable {
    var patientId: String
    var description: String
    var amount: Double
    var dueDate: String // yyyy-MM-dd
    var referenceMonth: String?
}

struct FinReminderResult: Decodable {
    let emailSent: Bool
    let messageText: String
    let reminderSentAt: Date?
}

struct FinCheckoutResult: Decodable, Identifiable {
    let id: String
    let status: FinChargeStatus
    let amount: Double
    let splitFeeApplied: Double?
    let invoiceUrl: String?
    let pixQrCode: String?
    let pixQrCodeImage: String?
}

// MARK: - Carteira Asaas

struct FinWalletStatus: Decodable {
    let connected: Bool
    let gateway: String
    let walletId: String?
    let connectedAt: Date?
}

struct FinWalletGuide: Decodable {
    struct Step: Decodable, Identifiable {
        let order: Int
        let title: String
        let description: String
        var id: Int { order }
    }

    let title: String
    let intro: String
    let steps: [Step]
    let notes: [String]
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

    static func charges(patientId: String?, status: FinChargeStatus? = nil) async throws -> [FinCharge] {
        try await APIClient.shared.get("finance/charges", query: [
            "patientId": patientId,
            "status": status?.rawValue,
        ])
    }

    static func chargesSummary(patientId: String?) async throws -> FinChargeSummary {
        try await APIClient.shared.get("finance/charges/summary", query: ["patientId": patientId])
    }

    static func fees() async throws -> FinFees {
        try await APIClient.shared.get("payments/fees")
    }

    static func createCharge(_ body: FinChargeBody) async throws -> FinCharge {
        try await APIClient.shared.post("finance/charges", body: body)
    }

    static func payCharge(id: String) async throws -> FinCharge {
        try await APIClient.shared.patch("finance/charges/\(id)/pay")
    }

    static func cancelCharge(id: String) async throws -> FinCharge {
        try await APIClient.shared.patch("finance/charges/\(id)/cancel")
    }

    static func sendReminder(id: String) async throws -> FinReminderResult {
        try await APIClient.shared.post("finance/charges/\(id)/reminder")
    }

    static func checkout(id: String, billingType: String) async throws -> FinCheckoutResult {
        try await APIClient.shared.post("finance/charges/\(id)/checkout", body: ["billingType": billingType])
    }

    static func walletStatus() async throws -> FinWalletStatus {
        try await APIClient.shared.get("payments/wallet")
    }

    static func upsertWallet(walletId: String) async throws -> FinWalletStatus {
        try await APIClient.shared.post("payments/wallet", body: ["walletId": walletId])
    }

    static func walletGuide() async throws -> FinWalletGuide {
        try await APIClient.shared.get("payments/guide")
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

// MARK: - Taxas e métodos de cobrança online
//
// Vêm do servidor. A taxa NUNCA é cravada no app: ela mora em
// PLATFORM_FEE_FIXED, e um app com 2,99 no código passaria a mentir o líquido
// no dia em que o valor mudasse. Mentir sobre quanto o terapeuta recebe é o
// pior erro possível neste módulo.

struct FinFees: Decodable {
    struct Method: Decodable, Identifiable, Hashable {
        let id: String
        let label: String
        let description: String
        let available: Bool
    }

    let platformFee: Double
    let minOnlineCharge: Double
    let methods: [Method]

    var disponiveis: [Method] { methods.filter(\.available) }
}

