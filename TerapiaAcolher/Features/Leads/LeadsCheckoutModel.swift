import Foundation
import Observation

/// Estado e regras do checkout de créditos (a tela só desenha).
///
/// Espelha o checkout do CRM web: cotação a cada mudança de oferta/cupom,
/// validação local antes de chamar a API, id de tentativa que só sobrevive a
/// erro de rede (a mesma compra não é cobrada duas vezes), e cartão salvo que
/// pede a senha do CRM — a confirmação vale 15 min lá; guardamos 14.
@MainActor
@Observable
final class LeadsCheckoutModel {
    let productId: Int

    // Carga
    var product: CheckoutProduct?
    var loadError: APIError?
    var isLoading = true

    // Escolhas
    var selectedOffers: [Int] = [] { didSet { resetAttempt(); Task { await refreshQuote() } } }
    var couponInput = ""
    var coupon: String? { didSet { resetAttempt(); Task { await refreshQuote() } } }
    var method: CheckoutMethod = .pix { didSet { resetAttempt() } }
    var installments = 1 { didSet { resetAttempt() } }
    var cpf = "" { didSet { clearError("cpf") } }
    var email = "" { didSet { clearError("email") } }
    var holderName = "" { didSet { clearError("holderName") } }
    var cardNumber = "" { didSet { resetAttempt(); clearError("number") } }
    var expiry = "" { didSet { clearError("expiry") } }
    var ccv = "" { didSet { clearError("ccv") } }
    var postalCode = "" { didSet { clearError("postalCode") } }
    var addressNumber = "" { didSet { clearError("addressNumber") } }
    var saveCard = false
    /// Cartão salvo escolhido; nil = cartão novo.
    var savedChoice: Int? { didSet { resetAttempt() } }
    var cards: [SavedCard] = []

    // Cotação
    var quote: CheckoutQuote?
    var isQuoting = false

    // Envio
    var isSubmitting = false
    var fieldErrors: [String: String] = [:]
    var submitError: String?
    var suggestPix = false
    var suggestOtherCard = false
    var disconnected = false
    /// Pedido criado: a tela troca para o acompanhamento.
    var createdOrder: LeadsOrder?
    var toast: String?

    // Senha do cartão salvo
    var askingPassword = false
    var passwordError: String?
    var isConfirmingPassword = false
    private var passwordContinuation: CheckedContinuation<String?, Never>?
    private var stepUp: (token: String, until: Date)?

    private var attemptId: String?
    private var quoteGeneration = 0

    init(productId: Int) {
        self.productId = productId
    }

    // MARK: Derivados

    var methods: [CheckoutMethod] {
        guard let m = product?.pagamento.metodos else { return [] }
        return CheckoutMethod.allCases.filter {
            switch $0 {
            case .pix: m.pix
            case .creditCard: m.creditCard
            case .boleto: m.boleto
            }
        }
    }

    var activeCards: [SavedCard] {
        guard product?.cartaoSalvo.ligado == true else { return [] }
        return cards.filter(\.isActive)
    }

    var cardInUse: SavedCard? {
        guard method == .creditCard, let id = savedChoice else { return nil }
        return activeCards.first { $0.id == id }
    }

    var cardLimitReached: Bool {
        guard let p = product else { return true }
        return cards.count >= p.cartaoSalvo.maxCartoes
    }

    var installmentTable: [CheckoutInstallment] {
        quote?.methods.creditCard?.filter(\.allowed) ?? []
    }

    /// A parcela escolhida pode sumir da tabela ao trocar oferta/cupom: vale 1x.
    var chosenInstallment: CheckoutInstallment? {
        installmentTable.first { $0.installments == installments } ?? installmentTable.first
    }

    var totalCents: Int? {
        guard let q = quote else { return nil }
        return method == .creditCard ? (chosenInstallment?.totalCents ?? q.baseCents) : q.baseCents
    }

    var leadsInOrder: Int { quote?.leadsQty ?? product?.product.leadsQty ?? 0 }

    var payTitle: String {
        switch method {
        case .pix: "Gerar Pix"
        case .boleto: "Gerar boleto"
        case .creditCard: totalCents.map { "Pagar \(CheckoutFormat.cents($0))" } ?? "Pagar"
        }
    }

    // MARK: Carga

    func load() async {
        isLoading = product == nil
        loadError = nil
        do {
            let p = try await LeadsCheckoutAPI.product(productId)
            product = p
            cards = p.cartaoSalvo.cartoes
            email = p.pagamento.email ?? ""
            method = methods.first ?? .pix
            savedChoice = activeCards.first?.id
            await refreshQuote()
        } catch is CancellationError {
        } catch let e as APIError {
            loadError = e
        } catch {
            loadError = APIError(statusCode: 0, message: "Não foi possível carregar o pacote.")
        }
        isLoading = false
    }

    func refreshQuote() async {
        guard product != nil else { return }
        quoteGeneration += 1
        let geracao = quoteGeneration
        isQuoting = true
        defer { if geracao == quoteGeneration { isQuoting = false } }
        do {
            let q = try await LeadsCheckoutAPI.quote(productId: productId, offerIds: selectedOffers, coupon: coupon)
            // Resposta velha (o usuário já trocou de oferta) não sobrescreve a nova.
            guard geracao == quoteGeneration else { return }
            quote = q
        } catch {
            // Mantém a cotação anterior; o botão só acende com cotação.
        }
    }

    func toggleOffer(_ id: Int) {
        if selectedOffers.contains(id) { selectedOffers.removeAll { $0 == id } } else { selectedOffers.append(id) }
    }

    func applyCoupon() {
        let c = couponInput.trimmingCharacters(in: .whitespaces).uppercased()
        coupon = c.isEmpty ? nil : c
    }

    func removeCoupon() {
        couponInput = ""
        coupon = nil
    }

    // MARK: Validação

    private func resetAttempt() { attemptId = nil }

    private func clearError(_ campo: String) {
        guard fieldErrors[campo] != nil else { return }
        fieldErrors[campo] = nil
        if fieldErrors.isEmpty { submitError = nil }
    }

    func validate() -> [String: String] {
        var e: [String: String] = [:]
        guard let p = product else { return e }
        if p.pagamento.precisaCpf, !CheckoutFormat.validCpf(cpf) { e["cpf"] = "Informe um CPF válido." }
        if p.pagamento.precisaEmail, !CheckoutFormat.validEmail(email) { e["email"] = "Informe um e-mail válido." }
        if method == .creditCard, cardInUse == nil {
            let n = CheckoutFormat.digits(cardNumber)
            if n.count < 13 || n.count > 19 || !CheckoutFormat.luhn(n) { e["number"] = "Número do cartão inválido. Confira os dígitos." }
            if holderName.trimmingCharacters(in: .whitespaces).count < 2 { e["holderName"] = "Informe o nome como está no cartão." }
            let partes = expiry.split(separator: "/")
            if partes.count != 2 || partes[1].count != 2 || !(1 ... 12).contains(Int(partes[0]) ?? 0) {
                e["expiry"] = "Use MM/AA."
            } else {
                let mes = Int(partes[0])!, ano = 2000 + (Int(partes[1]) ?? 0)
                let hoje = Calendar.current.dateComponents([.year, .month], from: .now)
                if ano < hoje.year! || (ano == hoje.year! && mes < hoje.month!) { e["expiry"] = "Cartão vencido." }
            }
            if !(3 ... 4).contains(ccv.count) || CheckoutFormat.digits(ccv) != ccv { e["ccv"] = "CVV inválido." }
            if CheckoutFormat.digits(postalCode).count != 8 { e["postalCode"] = "CEP inválido." }
            if addressNumber.trimmingCharacters(in: .whitespaces).isEmpty { e["addressNumber"] = "Informe o número." }
        }
        return e
    }

    // MARK: Pagar

    private func request(stepUpToken: String?, attempt: String) -> CheckoutOrderRequest {
        let p = product!
        var r = CheckoutOrderRequest(
            productId: productId,
            offerIds: selectedOffers,
            couponCode: quote?.coupon?.code,
            paymentMethod: method.rawValue,
            installments: method == .creditCard ? (chosenInstallment?.installments ?? 1) : 1,
            clientRequestId: attempt
        )
        if p.pagamento.precisaCpf { r.cpf = CheckoutFormat.digits(cpf) }
        let mail = email.trimmingCharacters(in: .whitespaces)
        if !mail.isEmpty { r.email = mail }
        if method == .creditCard {
            if let salvo = cardInUse {
                r.savedCardId = salvo.id
                r.stepUpToken = stepUpToken
            } else {
                let partes = expiry.split(separator: "/")
                r.card = .init(
                    holderName: holderName.trimmingCharacters(in: .whitespaces),
                    number: CheckoutFormat.digits(cardNumber),
                    expiryMonth: String(partes[0]).count == 1 ? "0\(partes[0])" : String(partes[0]),
                    expiryYear: "20\(partes[1])",
                    ccv: ccv,
                    postalCode: CheckoutFormat.digits(postalCode),
                    addressNumber: addressNumber.trimmingCharacters(in: .whitespaces)
                )
                if p.cartaoSalvo.ligado, saveCard, !cardLimitReached { r.saveCard = true }
            }
        }
        return r
    }

    func pay() async {
        let erros = validate()
        fieldErrors = erros
        guard erros.isEmpty else {
            submitError = "Confira os campos destacados."
            Haptics.warning()
            return
        }
        guard quote != nil else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        submitError = nil
        suggestPix = false
        suggestOtherCard = false
        let tentativa = attemptId ?? CheckoutFormat.newAttemptId()
        let emUso = cardInUse

        do {
            var pedido: LeadsOrder
            if emUso != nil {
                guard let token = await passwordToken() else { return }
                do {
                    pedido = try await LeadsCheckoutAPI.createOrder(request(stepUpToken: token, attempt: tentativa))
                } catch let e as APIError where e.code == "step_up_required" {
                    // Venceu entre a senha e a cobrança: pede de novo, uma vez.
                    stepUp = nil
                    guard let outro = await passwordToken() else { return }
                    pedido = try await LeadsCheckoutAPI.createOrder(request(stepUpToken: outro, attempt: tentativa))
                }
            } else {
                pedido = try await LeadsCheckoutAPI.createOrder(request(stepUpToken: nil, attempt: tentativa))
            }
            attemptId = nil
            switch pedido.saveCardStatus {
            case "saved", "pending": toast = "Cartão salvo para as próximas compras."
            case "unavailable", "failed": toast = "A compra deu certo, mas não foi possível salvar o cartão agora."
            default: break
            }
            Haptics.success()
            createdOrder = pedido
        } catch is CancellationError {
        } catch {
            handle(error, attempt: tentativa, cardInUse: emUso)
        }
    }

    private func handle(_ error: Error, attempt: String, cardInUse emUso: SavedCard?) {
        Haptics.warning()
        let e = error as? APIError
        let rede = e == nil || e!.statusCode == 0 || e!.statusCode >= 500 || e?.code == "leads_timeout"
        // Só erro de rede guarda o id: a compra pode ter sido criada.
        attemptId = rede ? attempt : nil
        let pixLigado = product?.pagamento.metodos.pix == true
        let mensagem = e?.message ?? "Não foi possível falar com o servidor."
        switch e?.code {
        case "saved_card_unavailable", "saved_card_invalid", "saved_cards_disabled":
            submitError = mensagem
            if let emUso { cards.removeAll { $0.id == emUso.id } }
            savedChoice = nil
        case "saved_card_daily_limit", "step_up_locked":
            if e?.code == "step_up_locked" { stepUp = nil }
            submitError = mensagem
            suggestPix = pixLigado
            suggestOtherCard = true
        case "card_declined":
            submitError = mensagem
            suggestPix = pixLigado && (e?.bool("suggestPix") ?? false)
            if e?.bool("savedCardDisabled") == true, let emUso {
                cards.removeAll { $0.id == emUso.id }
                savedChoice = nil
            } else if emUso != nil {
                suggestOtherCard = true
            }
        case "leads_desconectado":
            submitError = mensagem
            disconnected = true
        default:
            submitError = rede ? "\(mensagem) Se tocar em pagar de novo, a mesma compra não é cobrada duas vezes." : mensagem
            suggestPix = pixLigado && method == .creditCard && (e?.bool("suggestPix") ?? false)
        }
    }

    func switchToPix() {
        method = .pix
        submitError = nil
        suggestPix = false
        suggestOtherCard = false
    }

    func useOtherCard() {
        savedChoice = nil
        submitError = nil
        suggestPix = false
        suggestOtherCard = false
    }

    // MARK: Senha do CRM (cartão salvo)

    private func passwordToken() async -> String? {
        if let s = stepUp, s.until > .now { return s.token }
        passwordError = nil
        return await withCheckedContinuation { cont in
            passwordContinuation = cont
            askingPassword = true
        }
    }

    func confirmPassword(_ senha: String) async {
        guard !senha.isEmpty else {
            passwordError = "Digite sua senha."
            return
        }
        isConfirmingPassword = true
        defer { isConfirmingPassword = false }
        passwordError = nil
        do {
            let token = try await LeadsCheckoutAPI.confirmPassword(senha)
            stepUp = (token, Date().addingTimeInterval(14 * 60))
            finishPassword(token)
        } catch let e as APIError {
            passwordError = e.message
            Haptics.warning()
        } catch {
            passwordError = "Não foi possível confirmar agora."
        }
    }

    func cancelPassword() {
        finishPassword(nil)
    }

    private func finishPassword(_ token: String?) {
        askingPassword = false
        let cont = passwordContinuation
        passwordContinuation = nil
        cont?.resume(returning: token)
    }
}
