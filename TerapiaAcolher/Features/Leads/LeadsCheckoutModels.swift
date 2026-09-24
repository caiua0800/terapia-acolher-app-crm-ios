import Foundation

// MARK: - Créditos de leads (reais desde 2026-09-23)
//
// A compra acontece DENTRO do app, sobre o checkout que já fatura no sistema
// de leads da Terapia Acolher: a API do CRM repassa em nome do terapeuta
// (`integrations/leads/checkout/*`, contrato em backend/docs/CHECKOUT-LEADS.md).
// Nada de pagamento fica no app: o número do cartão vai uma vez para a API e
// segue direto; cartão salvo é um token do Asaas que só existe lá.
// Dinheiro chega em centavos (`*Cents`); datas chegam como texto ISO e são
// lidas só para exibir (um formato inesperado não pode derrubar a tela).

/// `GET integrations/leads/creditos` — saldo e pacotes à venda.
struct LeadCredits: Decodable {
    let saldo: Int
    let statusConta: String?
    let podeComprar: Bool
    let motivo: String?
    let formasDePagamento: Formas
    let maxParcelas: Int
    let pacotes: [Pacote]

    /// Opcionais de propósito: um meio ausente na resposta não pode derrubar a
    /// tela inteira de Créditos (o checkout confirma os meios de verdade).
    struct Formas: Decodable {
        let pix: Bool?
        let cartao: Bool?
        let boleto: Bool?
    }

    struct Pacote: Decodable, Identifiable, Hashable {
        let id: Int
        let titulo: String
        let descricao: String?
        let imagemUrl: String?
        let precoCheio: Double
        let preco: Double
        let leads: Int
        let reposicoes: Int
        let destaque: Bool
        let beneficios: [String]
        let selo: String?
        /// Até quando vale o preço promocional (ISO). Opcional no decode.
        let promocaoAte: String?

        var emPromocao: Bool { preco < precoCheio }
        var precoPorLead: Double? { leads > 0 ? preco / Double(leads) : nil }
    }

    /// Abaixo disso a tela chama atenção (mesmo "Baixo" do portal e do web).
    static let saldoBaixo = 3
    var isLow: Bool { saldo < Self.saldoBaixo }
}

// MARK: - Produto e cotação

struct CheckoutItem: Decodable, Hashable {
    let productId: Int
    let kind: String
    let offerId: Int?
    let title: String
    let description: String?
    let imageUrl: String?
    let priceCents: Int
    let unitPriceCents: Int
    let leadsQty: Int
    let replenishmentsQty: Int
    let sectionLabel: String?
    let headline: String?
    let highlight: Bool?
    let bullets: [String]?
    let guaranteeText: String?
    let faq: [FAQ]?
    let promoLabel: String?

    struct FAQ: Decodable, Hashable {
        let q: String
        let a: String
    }

    var onSale: Bool { unitPriceCents < priceCents }
}

struct SavedCard: Decodable, Identifiable, Hashable {
    let id: Int
    let brand: String?
    let lastDigits: String
    let holderName: String?
    let status: String

    var isActive: Bool { status == "active" }
    var title: String { "\(CardBrand.displayName(brand)) final \(lastDigits)" }
}

/// `GET integrations/leads/checkout/produtos/:id` — tudo o que a tela precisa numa ida.
struct CheckoutProduct: Decodable {
    let product: CheckoutItem
    let offers: [CheckoutItem]
    let pagamento: Pagamento
    let cartaoSalvo: CartaoSalvo

    struct Pagamento: Decodable {
        let metodos: Metodos
        let maxParcelas: Int
        let precisaCpf: Bool
        let precisaEmail: Bool
        let email: String?
    }

    struct Metodos: Decodable {
        let pix: Bool
        let creditCard: Bool
        let boleto: Bool
    }

    struct CartaoSalvo: Decodable {
        let ligado: Bool
        let maxCartoes: Int
        let cartoes: [SavedCard]
    }
}

struct CheckoutInstallment: Decodable, Hashable {
    let installments: Int
    let installmentCents: Int
    let totalCents: Int
    let surchargeCents: Int
    let surchargePct: Double
    let allowed: Bool
}

struct CheckoutQuote: Decodable {
    let items: [CheckoutItem]
    let baseCents: Int
    let coupon: Coupon?
    let couponError: String?
    let leadsQty: Int
    let methods: Methods

    struct Coupon: Decodable {
        let code: String
        let discountCents: Int
    }

    struct Methods: Decodable {
        let creditCard: [CheckoutInstallment]?
    }
}

enum CheckoutMethod: String, CaseIterable, Identifiable {
    case pix
    case creditCard = "credit_card"
    case boleto

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pix: "Pix"
        case .creditCard: "Cartão"
        case .boleto: "Boleto"
        }
    }

    var icon: String {
        switch self {
        case .pix: "qrcode"
        case .creditCard: "creditcard"
        case .boleto: "barcode"
        }
    }
}

// MARK: - Pedido

struct LeadsOrder: Decodable, Identifiable, Hashable {
    let id: Int
    let status: String
    let paymentMethod: String
    let installments: Int
    let totalCents: Int
    let discountCents: Int
    let surchargeCents: Int
    let couponCode: String?
    let leadsQty: Int
    /// Reposições incluídas. Opcional: resposta antiga não traz.
    let replenishmentsQty: Int?
    let items: [Item]
    let pixPayload: String?
    let boletoUrl: String?
    let boletoLine: String?
    let boletoDueDate: String?
    let invoiceUrl: String?
    let cardLast4: String?
    let cardBrand: String?
    let paidWithSavedCard: Bool?
    let paidAt: String?
    let createdAt: String
    let currentBalance: Int?
    /// Só na criação: o que aconteceu com "salvar cartão".
    let saveCardStatus: String?

    struct Item: Decodable, Hashable {
        let productId: Int
        let title: String
        let kind: String
        let unitPriceCents: Int
        let leadsQty: Int
    }

    var isPending: Bool { status == "pending" }
    var isPaid: Bool { status == "paid" }
    var mainProductId: Int? { (items.first { $0.kind == "main" } ?? items.first)?.productId }

    var statusLabel: String {
        switch status {
        case "pending": "Aguardando pagamento"
        case "paid": "Pago"
        case "failed": "Não aprovado"
        case "canceled": "Cancelado"
        case "expired": "Vencido"
        case "refunded": "Estornado"
        case "voided": "Anulado"
        default: status
        }
    }
}

struct SavedCardsList: Decodable {
    let enabled: Bool?
    let maxCards: Int?
    let cards: [SavedCard]
}

/// O que vai no `POST pedidos`. Opcionais nulos não são enviados.
struct CheckoutOrderRequest: Encodable {
    let productId: Int
    let offerIds: [Int]
    var couponCode: String?
    let paymentMethod: String
    var installments: Int?
    var cpf: String?
    var email: String?
    var card: Card?
    var saveCard: Bool?
    var savedCardId: Int?
    var stepUpToken: String?
    let clientRequestId: String

    struct Card: Encodable {
        let holderName: String
        let number: String
        let expiryMonth: String
        let expiryYear: String
        let ccv: String
        let postalCode: String
        let addressNumber: String
    }
}

// MARK: - API

enum LeadsCheckoutAPI {
    private static let base = "integrations/leads/checkout"

    static func credits() async throws -> LeadCredits {
        try await APIClient.shared.get("integrations/leads/creditos")
    }

    static func product(_ id: Int) async throws -> CheckoutProduct {
        try await APIClient.shared.get("\(base)/produtos/\(id)")
    }

    static func quote(productId: Int, offerIds: [Int], coupon: String?) async throws -> CheckoutQuote {
        struct Body: Encodable {
            let productId: Int
            let offerIds: [Int]
            let couponCode: String?
        }
        return try await APIClient.shared.post(
            "\(base)/cotacao",
            body: Body(productId: productId, offerIds: offerIds, couponCode: coupon)
        )
    }

    static func createOrder(_ pedido: CheckoutOrderRequest) async throws -> LeadsOrder {
        try await APIClient.shared.post("\(base)/pedidos", body: pedido)
    }

    static func order(_ id: Int) async throws -> LeadsOrder {
        try await APIClient.shared.get("\(base)/pedidos/\(id)")
    }

    static func orders() async throws -> [LeadsOrder] {
        try await APIClient.shared.get("\(base)/pedidos")
    }

    static func cancel(_ id: Int) async throws {
        let _: EmptyResponse = try await APIClient.shared.post("\(base)/pedidos/\(id)/cancelar")
    }

    static func savedCards() async throws -> SavedCardsList {
        try await APIClient.shared.get("\(base)/cartoes")
    }

    static func removeCard(_ id: Int) async throws {
        let _: EmptyResponse = try await APIClient.shared.delete("\(base)/cartoes/\(id)")
    }

    static func confirmPassword(_ senha: String) async throws -> String {
        struct Body: Encodable { let senha: String }
        struct Resposta: Decodable { let stepUpToken: String }
        let r: Resposta = try await APIClient.shared.post("\(base)/confirmar-senha", body: Body(senha: senha))
        return r.stepUpToken
    }
}

// MARK: - Utilidades de pagamento

enum CheckoutFormat {
    static func cents(_ c: Int) -> String { Formatters.brl(Double(c) / 100) }

    static func digits(_ s: String) -> String { s.filter(\.isNumber) }

    /// Id da tentativa: o mesmo volta no "pagar de novo" depois de erro de rede.
    static func newAttemptId() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    static func maskCard(_ v: String) -> String {
        let d = String(digits(v).prefix(19))
        return stride(from: 0, to: d.count, by: 4).map { i -> String in
            let start = d.index(d.startIndex, offsetBy: i)
            let end = d.index(start, offsetBy: min(4, d.count - i))
            return String(d[start ..< end])
        }.joined(separator: " ")
    }

    static func maskExpiry(_ v: String) -> String {
        let d = String(digits(v).prefix(4))
        return d.count > 2 ? "\(d.prefix(2))/\(d.dropFirst(2))" : d
    }

    static func maskCep(_ v: String) -> String {
        let d = String(digits(v).prefix(8))
        return d.count > 5 ? "\(d.prefix(5))-\(d.dropFirst(5))" : d
    }

    static func maskCpf(_ v: String) -> String {
        let d = Array(digits(v).prefix(11))
        var out = ""
        for (i, c) in d.enumerated() {
            if i == 3 || i == 6 { out.append(".") }
            if i == 9 { out.append("-") }
            out.append(c)
        }
        return out
    }

    static func luhn(_ numero: String) -> Bool {
        let d = digits(numero).compactMap { Int(String($0)) }
        guard d.count >= 13 else { return false }
        var soma = 0
        for (i, n) in d.reversed().enumerated() {
            if i % 2 == 1 {
                let dobro = n * 2
                soma += dobro > 9 ? dobro - 9 : dobro
            } else {
                soma += n
            }
        }
        return soma % 10 == 0
    }

    static func validCpf(_ cpf: String) -> Bool {
        let d = digits(cpf).compactMap { Int(String($0)) }
        guard d.count == 11, Set(d).count > 1 else { return false }
        func digito(_ n: Int) -> Int {
            var s = 0
            for i in 0 ..< n { s += d[i] * (n + 1 - i) }
            let r = (s * 10) % 11
            return r == 10 ? 0 : r
        }
        return digito(9) == d[9] && digito(10) == d[10]
    }

    static func validEmail(_ e: String) -> Bool {
        e.trimmingCharacters(in: .whitespaces).range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
    }

    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func date(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        return isoFrac.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    }

    static let dayMonthYear: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "dd/MM/yyyy"
        return f
    }()

    static let dayTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "dd/MM/yyyy 'às' HH:mm"
        return f
    }()
}

enum CardBrand {
    static func detect(_ numero: String) -> String? {
        let d = CheckoutFormat.digits(numero)
        guard !d.isEmpty else { return nil }
        func starts(_ p: String) -> Bool { d.range(of: "^(\(p))", options: .regularExpression) != nil }
        if starts("4011|4312|4389|4514|4573|5041|5066|5067|509|6277|6362|6363|650|6516|6550") { return "elo" }
        if starts("606282|3841") { return "hipercard" }
        if starts("3[47]") { return "amex" }
        if starts("3(0[0-5]|[68])") { return "diners" }
        if starts("4") { return "visa" }
        if starts("5[1-5]|2[2-7]") { return "mastercard" }
        return nil
    }

    static func displayName(_ brand: String?) -> String {
        switch brand?.lowercased() {
        case nil, "": "Cartão"
        case "visa": "Visa"
        case "mastercard", "master": "Mastercard"
        case "elo": "Elo"
        case "amex", "american_express": "Amex"
        case "hipercard": "Hipercard"
        case "diners": "Diners"
        case let outro?: outro.prefix(1).uppercased() + outro.dropFirst().lowercased()
        }
    }
}
