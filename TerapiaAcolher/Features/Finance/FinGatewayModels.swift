import Foundation

// MARK: - Gateway Acolher — DTOs do terapeuta
//
// Contrato: backend/docs/GATEWAY-ACOLHER.md. Dinheiro chega em reais (número
// com 2 casas), datas em ISO-8601 — exceto `birthDate`, que é dia-calendário
// "AAAA-MM-DD" e por isso é String aqui (o decoder de datas do APIClient
// rejeitaria esse formato e derrubaria a tela inteira).

enum GwAccountStatus: String, Decodable {
    case draft = "DRAFT"
    case underReview = "UNDER_REVIEW"
    case approved = "APPROVED"
    case rejected = "REJECTED"
    case suspended = "SUSPENDED"
}

enum GwPersonType: String, Codable {
    case pf = "PF"
    case pj = "PJ"

    var label: String { self == .pf ? "Pessoa física" : "Pessoa jurídica" }
    var documentLabel: String { self == .pf ? "CPF" : "CNPJ" }
}

enum GwDocumentType: String, Codable, Hashable {
    case identityFront = "IDENTITY_FRONT"
    case identityBack = "IDENTITY_BACK"
    case selfie = "SELFIE"
    case socialContract = "SOCIAL_CONTRACT"
    case proofOfAddress = "PROOF_OF_ADDRESS"

    var label: String {
        switch self {
        case .identityFront: "Documento (frente)"
        case .identityBack: "Documento (verso)"
        case .selfie: "Selfie"
        case .socialContract: "Contrato social"
        case .proofOfAddress: "Comprovante de endereço"
        }
    }

    var hint: String {
        switch self {
        case .identityFront: "RG ou CNH aberta, lado da foto."
        case .identityBack: "O verso do mesmo documento."
        case .selfie: "Uma foto sua, de frente, com boa luz."
        case .socialContract: "Contrato social ou certificado MEI (PDF ou foto)."
        case .proofOfAddress: "Conta de luz, água ou internet recente."
        }
    }

    var icon: String {
        switch self {
        case .identityFront, .identityBack: "person.text.rectangle"
        case .selfie: "person.crop.circle"
        case .socialContract: "doc.text"
        case .proofOfAddress: "house"
        }
    }

    /// Contrato social aceita PDF; o resto é foto.
    var acceptsPDF: Bool { self == .socialContract || self == .proofOfAddress }
}

enum GwDocumentStatus: String, Decodable {
    case pending = "PENDING"
    case approved = "APPROVED"
    case rejected = "REJECTED"

    var label: String {
        switch self {
        case .pending: "EM ANÁLISE"
        case .approved: "APROVADO"
        case .rejected: "RECUSADO"
        }
    }
}

enum GwLedgerType: String, Decodable {
    case credit = "CREDIT"
    case debit = "DEBIT"
}

enum GwLedgerKind: String, Decodable {
    case openingBonus = "OPENING_BONUS"
    case chargeReceived = "CHARGE_RECEIVED"
    case platformFee = "PLATFORM_FEE"
    case providerFee = "PROVIDER_FEE"
    case withdrawal = "WITHDRAWAL"
    case withdrawalReversal = "WITHDRAWAL_REVERSAL"
    case adjustment = "ADJUSTMENT"
    case platformPurchase = "PLATFORM_PURCHASE"

    var icon: String {
        switch self {
        case .openingBonus: "gift"
        case .chargeReceived: "arrow.down.circle"
        case .platformFee, .providerFee: "percent"
        case .withdrawal: "arrow.up.circle"
        case .withdrawalReversal: "arrow.uturn.left.circle"
        case .adjustment: "slider.horizontal.3"
        case .platformPurchase: "cart"
        }
    }

    var label: String {
        switch self {
        case .openingBonus: "Crédito inicial"
        case .chargeReceived: "Cobrança recebida"
        case .platformFee: "Taxa de plataforma"
        case .providerFee: "Tarifa Pix"
        case .withdrawal: "Saque"
        case .withdrawalReversal: "Estorno de saque"
        case .adjustment: "Ajuste"
        case .platformPurchase: "Compra na plataforma"
        }
    }

    /// Categorias que fazem sentido como filtro do extrato (na ordem do menu).
    static let filterable: [GwLedgerKind] = [
        .chargeReceived, .withdrawal, .withdrawalReversal, .platformFee,
        .providerFee, .platformPurchase, .adjustment, .openingBonus,
    ]
}

enum GwWithdrawalOrigin: String, Decodable {
    case manual = "MANUAL"
    case auto = "AUTO"
}

enum GwWithdrawalStatus: String, Decodable {
    case pendingApproval = "PENDING_APPROVAL"
    case processing = "PROCESSING"
    case done = "DONE"
    case failed = "FAILED"
    case canceled = "CANCELED"

    var label: String {
        switch self {
        case .pendingApproval: "EM ANÁLISE"
        case .processing: "EM PROCESSAMENTO"
        case .done: "ENVIADO"
        case .failed: "NÃO ENVIADO"
        case .canceled: "CANCELADO"
        }
    }

    /// Só o que ainda não saiu da conta pode ser cancelado; `DONE` já foi.
    var canCancel: Bool { self == .pendingApproval || self == .processing }
}

enum GwPixKeyType: String, Codable, CaseIterable, Hashable {
    case cpf = "CPF"
    case cnpj = "CNPJ"
    case email = "EMAIL"
    case phone = "PHONE"
    case evp = "EVP"

    var label: String {
        switch self {
        case .cpf: "CPF"
        case .cnpj: "CNPJ"
        case .email: "E-mail"
        case .phone: "Celular"
        case .evp: "Aleatória"
        }
    }

    var placeholder: String {
        switch self {
        case .cpf: "000.000.000-00"
        case .cnpj: "00.000.000/0000-00"
        case .email: "voce@email.com"
        case .phone: "+55 (11) 99999-9999"
        case .evp: "chave aleatória (formato UUID)"
        }
    }
}

enum GwChargeStatus: String, Decodable {
    case pending = "PENDING"
    case paid = "PAID"
    case expired = "EXPIRED"
    case canceled = "CANCELED"
}

// MARK: - Objetos

struct GwFees: Decodable {
    let platformFixed: Double
    let providerPixFixed: Double
    let withdrawalFee: Double
    let minCharge: Double
    let minWithdrawal: Double
    let dailyWithdrawalLimit: Double

    var totalPerCharge: Double { platformFixed + providerPixFixed }
}

struct GwProvider: Decodable {
    let name: String
    let legalName: String
    let supportPhone: String
    let supportEmail: String
    let site: String?
    let badgeUrl: String?
}

struct GwTerms: Decodable {
    let version: String
    let clause: String
}

struct GwAddress: Codable {
    let postalCode: String
    let street: String
    let number: String
    let complement: String?
    let district: String
    let city: String
    let state: String
}

struct GwDocument: Decodable, Identifiable, Hashable {
    let id: String
    let type: GwDocumentType
    let label: String?
    let status: GwDocumentStatus
    let rejectionReason: String?
    let capturedAt: Date?
    let captureMode: String?
    let livenessScore: Double?
    let reviewedAt: Date?
    let previewUrl: String?

    static func == (lhs: GwDocument, rhs: GwDocument) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var title: String { label ?? type.label }
    var previewURL: URL? { previewUrl.flatMap(URL.init(string:)) }
}

struct GwStats: Decodable {
    let receivedTotal: Double
    let withdrawnTotal: Double
    let platformFeesTotal: Double
    let providerFeesTotal: Double
}

struct GwAccount: Decodable {
    let id: String
    let status: GwAccountStatus
    let step: Int
    let personType: GwPersonType
    let legalName: String?
    let cpfCnpjMasked: String?
    /// Dia-calendário "AAAA-MM-DD" (não é timestamp).
    let birthDate: String?
    let phone: String?
    let email: String?
    let incomeValue: Double?
    let companyType: String?
    let address: GwAddress?
    let termsAcceptedAt: Date?
    let termsVersion: String?
    let submittedAt: Date?
    let approvedAt: Date?
    let rejectedAt: Date?
    let rejectionReason: String?
    let suspendedReason: String?
    let balance: Double
    let documents: [GwDocument]
    let requiredDocuments: [GwDocumentType]
    let missingDocuments: [GwDocumentType]
    let canSubmit: Bool
    let pendingWithdrawals: Int
    let stats: GwStats
    /// Preferências da conta (saque automático). Opcional pra tolerar API antiga.
    let settings: GwSettings?

    var autoWithdraw: GwAutoWithdraw { settings?.autoWithdraw ?? .desligado }

    func document(_ type: GwDocumentType) -> GwDocument? {
        documents.first { $0.type == type }
    }

    /// Etapa (0-based) em que o assistente deve reabrir.
    var wizardStartIndex: Int { max(0, min(4, step - 1)) }
}

/// Saque automático: todo dia às 18h, se o saldo bater o mínimo escolhido.
struct GwAutoWithdraw: Decodable {
    let enabled: Bool
    let minAmount: Double?
    let pixKeyId: String?
    let schedule: String?

    static let desligado = GwAutoWithdraw(enabled: false, minAmount: nil, pixKeyId: nil, schedule: nil)

    var scheduleLabel: String { schedule ?? "Todo dia às 18h" }
}

struct GwSettings: Decodable {
    let autoWithdraw: GwAutoWithdraw
}

struct GwOverview: Decodable {
    let simulation: Bool
    let fees: GwFees
    let provider: GwProvider
    let terms: GwTerms
    let account: GwAccount?
}

struct GwLedgerEntry: Decodable, Identifiable {
    let id: String
    let type: GwLedgerType
    let kind: GwLedgerKind
    let amount: Double
    let balanceAfter: Double
    let description: String
    let referenceType: String?
    let referenceId: String?
    let createdAt: Date
}

struct GwLedgerPage: Decodable {
    struct Summary: Decodable {
        let credits: Double
        let debits: Double
        let net: Double?
        let count: Int?

        var liquido: Double { net ?? (credits - debits) }
    }

    let items: [GwLedgerEntry]
    let total: Int
    let page: Int
    let pageSize: Int
    let summary: Summary
}

struct GwWithdrawal: Decodable, Identifiable {
    let id: String
    let amount: Double
    let fee: Double
    let netAmount: Double
    let origin: GwWithdrawalOrigin?
    let pixKeyId: String?
    let pixKeyType: GwPixKeyType
    let pixKeyMasked: String?
    let ownerName: String?
    let status: GwWithdrawalStatus
    let failReason: String?
    let receiptCode: String?
    let endToEndId: String?
    let requestedAt: Date
    let processedAt: Date?
}

struct GwWithdrawalPage: Decodable {
    let items: [GwWithdrawal]
    let total: Int
    let page: Int
    let pageSize: Int
}

struct GwReceipt: Decodable, Identifiable {
    struct Holder: Decodable {
        let legalName: String?
        let cpfCnpjMasked: String?
    }

    let withdrawal: GwWithdrawal
    let account: Holder
    let provider: GwProvider
    let generatedAt: Date

    var id: String { withdrawal.id }
}

struct GwPixKey: Decodable, Identifiable, Hashable {
    let id: String
    let keyType: GwPixKeyType
    let key: String
    let keyMasked: String?
    let label: String?
    let ownerName: String?
    let ownerDocumentMasked: String?
    let isDefault: Bool
    let verifiedAt: Date?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, keyType, key, keyMasked, label, ownerName, ownerDocumentMasked, isDefault, verifiedAt, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        keyType = try c.decode(GwPixKeyType.self, forKey: .keyType)
        key = try c.decode(String.self, forKey: .key)
        keyMasked = try c.decodeIfPresent(String.self, forKey: .keyMasked)
        label = try c.decodeIfPresent(String.self, forKey: .label)
        ownerName = try c.decodeIfPresent(String.self, forKey: .ownerName)
        ownerDocumentMasked = try c.decodeIfPresent(String.self, forKey: .ownerDocumentMasked)
        isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        verifiedAt = try c.decodeIfPresent(Date.self, forKey: .verifiedAt)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
    }

    static func == (lhs: GwPixKey, rhs: GwPixKey) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var display: String { keyMasked ?? key }
    /// "Nubank" ou, sem apelido, o tipo da chave.
    var title: String { label?.isEmpty == false ? label! : keyType.label }
}

// MARK: - Filtro do extrato

struct GwLedgerFilter: Equatable {
    enum Periodo: String, CaseIterable, Identifiable {
        case tudo, hoje, seteDias, esteMes, mesPassado, personalizado

        var id: String { rawValue }

        var label: String {
            switch self {
            case .tudo: "Tudo"
            case .hoje: "Hoje"
            case .seteDias: "7 dias"
            case .esteMes: "Este mês"
            case .mesPassado: "Mês passado"
            case .personalizado: "Período"
            }
        }
    }

    var periodo: Periodo = .tudo
    var de: Date?
    var ate: Date?
    var type: GwLedgerType?
    var kinds: Set<GwLedgerKind> = []
    var search = ""
    var minAmount: Double?
    var maxAmount: Double?

    var isEmpty: Bool {
        periodo == .tudo && type == nil && kinds.isEmpty
            && search.trimmingCharacters(in: .whitespaces).isEmpty
            && minAmount == nil && maxAmount == nil
    }

    /// Quantos filtros estão ativos (pra badge no botão).
    var count: Int {
        var n = 0
        if periodo != .tudo { n += 1 }
        if type != nil { n += 1 }
        if !kinds.isEmpty { n += 1 }
        if !search.trimmingCharacters(in: .whitespaces).isEmpty { n += 1 }
        if minAmount != nil || maxAmount != nil { n += 1 }
        return n
    }

    /// Datas efetivas (dia-calendário) conforme o atalho escolhido.
    var intervalo: (de: Date?, ate: Date?) {
        let cal = Calendar.current
        let hoje = cal.startOfDay(for: Date())
        switch periodo {
        case .tudo: return (nil, nil)
        case .hoje: return (hoje, hoje)
        case .seteDias: return (cal.date(byAdding: .day, value: -6, to: hoje), hoje)
        case .esteMes:
            let inicio = cal.date(from: cal.dateComponents([.year, .month], from: hoje))
            return (inicio, hoje)
        case .mesPassado:
            let inicioEste = cal.date(from: cal.dateComponents([.year, .month], from: hoje))!
            let inicio = cal.date(byAdding: .month, value: -1, to: inicioEste)
            let fim = cal.date(byAdding: .day, value: -1, to: inicioEste)
            return (inicio, fim)
        case .personalizado: return (de, ate)
        }
    }

    var query: [String: String?] {
        let (de, ate) = intervalo
        var q: [String: String?] = [:]
        if let de { q["from"] = GwFormat.calendarDay(from: de) }
        if let ate { q["to"] = GwFormat.calendarDay(from: ate) }
        if let type { q["type"] = type.rawValue }
        if !kinds.isEmpty {
            q["kind"] = kinds.map(\.rawValue).sorted().joined(separator: ",")
        }
        let texto = search.trimmingCharacters(in: .whitespaces)
        if !texto.isEmpty { q["search"] = texto }
        if let minAmount { q["minAmount"] = String(format: "%.2f", minAmount) }
        if let maxAmount { q["maxAmount"] = String(format: "%.2f", maxAmount) }
        return q
    }

    /// Resumo curto do que está filtrado, pra mostrar acima da lista.
    var descricao: String? {
        var partes: [String] = []
        if periodo != .tudo {
            let (de, ate) = intervalo
            if let de, let ate {
                partes.append("\(GwFormat.day.string(from: de)) a \(GwFormat.day.string(from: ate))")
            } else {
                partes.append(periodo.label)
            }
        }
        if let type { partes.append(type == .credit ? "só entradas" : "só saídas") }
        if !kinds.isEmpty {
            partes.append(kinds.count == 1 ? kinds.first!.label : "\(kinds.count) categorias")
        }
        if minAmount != nil || maxAmount != nil {
            let de = minAmount.map(Formatters.brl) ?? "—"
            let ate = maxAmount.map(Formatters.brl) ?? "—"
            partes.append("de \(de) a \(ate)")
        }
        return partes.isEmpty ? nil : partes.joined(separator: " · ")
    }
}

enum GwExportFormat: String, CaseIterable, Identifiable {
    case csv, pdf

    var id: String { rawValue }
    var label: String { self == .csv ? "Planilha (CSV)" : "PDF" }
    var icon: String { self == .csv ? "tablecells" : "doc.richtext" }
}

struct GwCharge: Decodable, Identifiable {
    let chargeId: String
    let gatewayChargeId: String?
    let status: GwChargeStatus
    let amount: Double
    let platformFee: Double
    let providerFee: Double
    let netAmount: Double
    let pixCopyPaste: String
    let pixQrCodeImage: String?
    let expiresAt: Date
    let paidAt: Date?
    let createdAt: Date?
    let patientName: String?
    let description: String?

    var id: String { chargeId }
}

struct GwOk: Decodable {
    let ok: Bool
}

// MARK: - Corpos de requisição

struct GwPersonalBody: Encodable {
    var legalName: String
    var cpfCnpj: String
    var birthDate: String?
    var phone: String
    var email: String
    var incomeValue: Double?
    var companyType: String?
}

struct GwAddressBody: Encodable {
    var postalCode: String
    var street: String
    var number: String
    var complement: String?
    var district: String
    var city: String
    var state: String
}

struct GwWithdrawalBody: Encodable {
    var amount: Double
    var pixKeyId: String
}

/// Chaves sempre presentes: `null` explícito desliga o mínimo / troca a chave.
struct GwAutoWithdrawBody: Encodable {
    var enabled: Bool
    var minAmount: Double?
    var pixKeyId: String?

    enum CodingKeys: String, CodingKey { case enabled, minAmount, pixKeyId }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(minAmount, forKey: .minAmount)
        try c.encode(pixKeyId, forKey: .pixKeyId)
    }
}

struct GwPixKeyBody: Encodable {
    var keyType: String
    var key: String
    var label: String?
}

// MARK: - Chamadas de API

enum FinGatewayAPI {
    static func overview() async throws -> GwOverview {
        try await APIClient.shared.get("gateway/account")
    }

    static func start(personType: GwPersonType) async throws -> GwAccount {
        try await APIClient.shared.post(
            "gateway/account/start",
            body: ["personType": personType.rawValue]
        )
    }

    static func savePersonal(_ body: GwPersonalBody) async throws -> GwAccount {
        try await APIClient.shared.put("gateway/account/personal", body: body)
    }

    static func saveAddress(_ body: GwAddressBody) async throws -> GwAccount {
        try await APIClient.shared.put("gateway/account/address", body: body)
    }

    static func uploadDocument(
        data: Data,
        fileName: String,
        mimeType: String,
        type: GwDocumentType,
        captureMode: String,
        livenessScore: Double?
    ) async throws -> GwDocument {
        var fields = ["type": type.rawValue, "captureMode": captureMode]
        if let livenessScore {
            fields["livenessScore"] = String(format: "%.3f", livenessScore)
        }
        return try await APIClient.shared.upload(
            "gateway/account/documents",
            fileData: data,
            fileName: fileName,
            mimeType: mimeType,
            fieldName: "file",
            extraFields: fields
        )
    }

    static func deleteDocument(id: String) async throws -> GwOk {
        try await APIClient.shared.delete("gateway/account/documents/\(id)")
    }

    static func acceptTerms(version: String) async throws -> GwAccount {
        try await APIClient.shared.post("gateway/account/terms", body: ["version": version])
    }

    static func submit() async throws -> GwAccount {
        try await APIClient.shared.post("gateway/account/submit")
    }

    static func reopen() async throws -> GwAccount {
        try await APIClient.shared.post("gateway/account/reopen")
    }

    static func ledger(
        page: Int,
        pageSize: Int = 30,
        filter: GwLedgerFilter = GwLedgerFilter()
    ) async throws -> GwLedgerPage {
        var query = filter.query
        query["page"] = String(page)
        query["pageSize"] = String(pageSize)
        return try await APIClient.shared.get("gateway/ledger", query: query)
    }

    static func exportLedger(
        format: GwExportFormat,
        filter: GwLedgerFilter
    ) async throws -> APIClient.DownloadedFile {
        var query = filter.query
        query["format"] = format.rawValue
        return try await APIClient.shared.download(
            "gateway/ledger/export",
            query: query,
            fallbackName: "extrato-gateway-acolher.\(format.rawValue)"
        )
    }

    static func withdrawals(page: Int = 1, pageSize: Int = 30) async throws -> GwWithdrawalPage {
        try await APIClient.shared.get("gateway/withdrawals", query: [
            "page": String(page),
            "pageSize": String(pageSize),
        ])
    }

    static func receiptPDF(id: String, receiptCode: String?) async throws -> APIClient.DownloadedFile {
        try await APIClient.shared.download(
            "gateway/withdrawals/\(id)/receipt",
            query: ["format": "pdf"],
            fallbackName: "comprovante-\(receiptCode ?? id).pdf"
        )
    }

    static func updateAutoWithdraw(_ body: GwAutoWithdrawBody) async throws -> GwAutoWithdraw {
        try await APIClient.shared.put("gateway/settings/auto-withdraw", body: body)
    }

    static func requestWithdrawal(_ body: GwWithdrawalBody) async throws -> GwWithdrawal {
        try await APIClient.shared.post("gateway/withdrawals", body: body)
    }

    static func cancelWithdrawal(id: String) async throws -> GwWithdrawal {
        try await APIClient.shared.post("gateway/withdrawals/\(id)/cancel")
    }

    static func receipt(id: String) async throws -> GwReceipt {
        try await APIClient.shared.get("gateway/withdrawals/\(id)/receipt")
    }

    static func pixKeys() async throws -> [GwPixKey] {
        try await APIClient.shared.get("gateway/pix-keys")
    }

    static func addPixKey(_ body: GwPixKeyBody) async throws -> GwPixKey {
        try await APIClient.shared.post("gateway/pix-keys", body: body)
    }

    static func setDefaultPixKey(id: String) async throws -> [GwPixKey] {
        try await APIClient.shared.put("gateway/pix-keys/\(id)/default", body: Optional<Int>.none)
    }

    static func removePixKey(id: String) async throws -> GwOk {
        try await APIClient.shared.delete("gateway/pix-keys/\(id)")
    }

    static func createPix(chargeId: String) async throws -> GwCharge {
        try await APIClient.shared.post("gateway/charges/\(chargeId)/pix")
    }

    static func charge(chargeId: String) async throws -> GwCharge {
        try await APIClient.shared.get("gateway/charges/\(chargeId)")
    }

    static func simulatePayment(chargeId: String) async throws -> GwCharge {
        try await APIClient.shared.post("gateway/charges/\(chargeId)/simulate-payment")
    }
}

// MARK: - Estado compartilhado da conta
//
// Vive fora das telas porque Cobranças precisa saber se a conta está aprovada
// sem abrir a seção — e reabrir o Gateway não pode dar spinner do zero.

@MainActor
@Observable
final class FinGatewayStore {
    static let shared = FinGatewayStore()

    var overview: GwOverview?
    var isLoading = false
    var errorMessage: String?

    var account: GwAccount? { overview?.account }
    var simulation: Bool { overview?.simulation ?? false }
    var isApproved: Bool { account?.status == .approved }
    var balance: Double { account?.balance ?? 0 }

    func load(showSpinner: Bool = true) async {
        if showSpinner, overview == nil { isLoading = true }
        defer { isLoading = false }
        do {
            overview = try await FinGatewayAPI.overview()
            errorMessage = nil
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
        } catch {
            errorMessage = (error as? APIError)?.message
                ?? "Não foi possível carregar o Gateway Acolher."
        }
    }

    /// Atualiza só a conta, mantendo taxas/provedor/termos já carregados.
    func apply(_ account: GwAccount) {
        guard let current = overview else { return }
        overview = GwOverview(
            simulation: current.simulation,
            fees: current.fees,
            provider: current.provider,
            terms: current.terms,
            account: account
        )
    }
}

// MARK: - Máscaras e formatação do Gateway

enum GwMask {
    static func cpf(_ raw: String) -> String { PatientMask.cpf(raw) }

    /// CNPJ: 00.000.000/0000-00
    static func cnpj(_ raw: String) -> String {
        let digits = String(raw.filter(\.isNumber).prefix(14))
        var out = ""
        for (i, ch) in digits.enumerated() {
            if i == 2 || i == 5 { out += "." }
            if i == 8 { out += "/" }
            if i == 12 { out += "-" }
            out.append(ch)
        }
        return out
    }

    static func document(_ raw: String, personType: GwPersonType) -> String {
        personType == .pf ? cpf(raw) : cnpj(raw)
    }

    /// CEP: 00000-000
    static func cep(_ raw: String) -> String {
        let digits = String(raw.filter(\.isNumber).prefix(8))
        guard digits.count > 5 else { return digits }
        let index = digits.index(digits.startIndex, offsetBy: 5)
        return "\(digits[..<index])-\(digits[index...])"
    }

    static func phone(_ raw: String) -> String { PatientMask.whatsapp(raw) }

    static func digits(_ raw: String) -> String { raw.filter(\.isNumber) }

    /// Data por extenso: 00/00/0000 (digitação, não DatePicker — nascimento é
    /// número conhecido de cor, e rolar 36 anos de calendário é pior).
    static func date(_ raw: String) -> String {
        let digits = String(raw.filter(\.isNumber).prefix(8))
        var out = ""
        for (i, ch) in digits.enumerated() {
            if i == 2 || i == 4 { out += "/" }
            out.append(ch)
        }
        return out
    }

    /// Valor digitado em reais → Double (aceita "1.234,56" e "1234.56").
    static func amount(_ text: String) -> Double? { FinFormat.parseAmount(text) }
}

enum GwFormat {
    /// Double → texto pra campo de valor ("1.234,56"), sem o "R$".
    static func amountText(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    static let dayTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "dd/MM/yyyy 'às' HH:mm"
        return formatter
    }()

    static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter
    }()

    static let shortDayTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "dd/MM · HH:mm"
        return formatter
    }()

    /// "AAAA-MM-DD" → Date (dia-calendário, sem fuso).
    static func date(fromCalendarDay text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)
    }

    /// "10/05/1990" → "1990-05-10" (nil se incompleta ou inválida).
    static func calendarDay(fromTyped text: String) -> String? {
        let digits = text.filter(\.isNumber)
        guard digits.count == 8 else { return nil }
        let dia = String(digits.prefix(2))
        let mes = String(digits.dropFirst(2).prefix(2))
        let ano = String(digits.suffix(4))
        guard let d = Int(dia), let m = Int(mes), let a = Int(ano),
              (1 ... 31).contains(d), (1 ... 12).contains(m), a > 1900
        else { return nil }
        return String(format: "%04d-%02d-%02d", a, m, d)
    }

    /// "1990-05-10" → "10/05/1990" (para pré-preencher o campo).
    static func typed(fromCalendarDay text: String?) -> String {
        guard let text, text.count == 10 else { return "" }
        let partes = text.split(separator: "-")
        guard partes.count == 3 else { return "" }
        return "\(partes[2])/\(partes[1])/\(partes[0])"
    }

    static func calendarDay(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// "em 2 dias", "em 3 horas", "expirado".
    static func expiry(_ date: Date) -> String {
        let seconds = date.timeIntervalSinceNow
        if seconds <= 0 { return "Expirado" }
        let hours = Int(seconds / 3600)
        if hours >= 24 {
            let days = hours / 24
            return "Vale por \(days) dia\(days == 1 ? "" : "s")"
        }
        if hours >= 1 { return "Vale por \(hours) hora\(hours == 1 ? "" : "s")" }
        let minutes = max(1, Int(seconds / 60))
        return "Vale por \(minutes) min"
    }
}
