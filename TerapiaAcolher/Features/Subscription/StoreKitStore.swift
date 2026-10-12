import Foundation
import Observation
import StoreKit

// MARK: - Planos vendidos no iPhone (GET subscription/apple/products)

struct AppStorePlanProduct: Decodable, Hashable {
    let productId: String
    let periodicidade: SubscriptionPeriodicity?
}

struct AppStorePlan: Decodable, Identifiable, Hashable {
    let id: String
    let slug: String
    let nome: String
    let descricao: String?
    let destaques: [String]
    let produtos: [AppStorePlanProduct]
}

struct AppStoreCatalog: Decodable {
    /// UUID do terapeuta: vai na compra (`appAccountToken`) e o servidor
    /// confere que a assinatura é desta conta.
    let appAccountToken: String
    /// Motivo de não vender a esta conta (cortesia, paga por outro meio,
    /// pré-venda). Com ele a tela só informa.
    let bloqueio: String?
    let produtoAtual: String?
    let planos: [AppStorePlan]
}

enum AppStoreAPI {
    static func catalogo() async throws -> AppStoreCatalog {
        try await APIClient.shared.get("subscription/apple/products")
    }

    static func registrar(_ jws: String) async throws -> MySubscription {
        struct Body: Encodable { let signedTransaction: String }
        return try await APIClient.shared.post(
            "subscription/apple/transactions",
            body: Body(signedTransaction: jws)
        )
    }
}

// MARK: - Loja

/// Assinatura pelo In-App Purchase (StoreKit 2, App Store 3.1.1).
///
/// Quem cobra, renova e cancela é a Apple. O app só compra e entrega ao
/// servidor a transação assinada (`jwsRepresentation`); o servidor confere
/// a assinatura da Apple e libera o plano. A transação só é finalizada depois
/// que o servidor aceitou — se a rede cair no meio, o StoreKit a entrega de
/// novo em `Transaction.updates` e nada se perde.
///
/// Regra de texto: pode convidar a assinar AQUI, com o preço do StoreKit.
/// Nunca site, link externo ou preço que não seja o da Apple.
@MainActor
@Observable
final class StoreKitStore {
    static let shared = StoreKitStore()

    private(set) var catalogo: AppStoreCatalog?
    /// Produtos do StoreKit por id (preço e período vêm daqui).
    private(set) var produtos: [String: Product] = [:]
    private(set) var isLoading = false
    /// Id do produto sendo comprado (spinner só no botão tocado).
    private(set) var comprando: String?
    private(set) var restaurando = false
    var errorMessage: String?
    var infoMessage: String?

    private var listener: Task<Void, Never>?

    private init() {}

    /// Logout: o catálogo leva o token da conta que saiu.
    func limpar() {
        catalogo = nil
        errorMessage = nil
        infoMessage = nil
    }

    /// No lançamento do app: renovações, compras aprovadas depois (Ask to Buy)
    /// e compras feitas em outro aparelho chegam por aqui.
    func iniciar() {
        guard listener == nil else { return }
        listener = Task { [weak self] in
            for await resultado in Transaction.updates {
                await self?.entregar(resultado, silencioso: true)
            }
        }
    }

    /// Ao abrir o app logado: reenvia o que o aparelho tem, cobrindo um aviso
    /// do servidor que tenha se perdido. Silencioso.
    func sincronizar() async {
        guard SessionStore.shared.isAuthenticated else { return }
        for await resultado in Transaction.currentEntitlements {
            await entregar(resultado, silencioso: true)
        }
    }

    func carregar() async {
        if catalogo == nil { isLoading = true }
        errorMessage = nil
        defer { isLoading = false }
        do {
            let novo = try await AppStoreAPI.catalogo()
            let ids = Set(novo.planos.flatMap { $0.produtos.map(\.productId) })
            let lista = try await Product.products(for: ids)
            produtos = Dictionary(uniqueKeysWithValues: lista.map { ($0.id, $0) })
            catalogo = novo
        } catch is CancellationError {
        } catch let error as APIError {
            errorMessage = error.message
        } catch {
            errorMessage = "Não foi possível carregar os planos. Tente de novo."
        }
    }

    func comprar(_ produto: Product) async {
        guard comprando == nil, let catalogo else { return }
        errorMessage = nil
        infoMessage = nil
        comprando = produto.id
        defer { comprando = nil }
        var opcoes: Set<Product.PurchaseOption> = []
        if let token = UUID(uuidString: catalogo.appAccountToken) {
            opcoes.insert(.appAccountToken(token))
        }
        do {
            switch try await produto.purchase(options: opcoes) {
            case let .success(resultado):
                if await entregar(resultado, silencioso: false) {
                    Haptics.success()
                    infoMessage = "Assinatura confirmada. Obrigado!"
                }
            case .pending:
                infoMessage = "Compra aguardando aprovação. O plano é liberado assim que a Apple confirmar."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = "A compra não foi concluída. Tente de novo."
        }
    }

    func restaurar() async {
        guard !restaurando else { return }
        errorMessage = nil
        infoMessage = nil
        restaurando = true
        defer { restaurando = false }
        do {
            try await AppStore.sync()
        } catch StoreKitError.userCancelled {
            return
        } catch {
            errorMessage = "Não foi possível falar com a App Store. Tente de novo."
            return
        }
        var achou = false
        for await resultado in Transaction.currentEntitlements {
            if await entregar(resultado, silencioso: false) { achou = true }
        }
        if errorMessage == nil {
            infoMessage = achou
                ? "Compras restauradas."
                : "Nenhuma assinatura ativa encontrada nesta conta Apple."
        }
    }

    /// Manda a transação ao servidor e, aceita, finaliza. Devolve se aplicou.
    @discardableResult
    private func entregar(_ resultado: VerificationResult<Transaction>, silencioso: Bool) async -> Bool {
        // Transação que o StoreKit não conseguiu verificar não é entregue nem
        // finalizada; o servidor recusaria de qualquer forma.
        guard case let .verified(transacao) = resultado else { return false }
        guard transacao.productType == .autoRenewable else {
            // Não vendemos outro tipo no app: nada a liberar.
            await transacao.finish()
            return false
        }
        // Sem sessão não há a quem entregar: fica para o próximo login.
        guard SessionStore.shared.isAuthenticated else { return false }
        do {
            let dados = try await AppStoreAPI.registrar(resultado.jwsRepresentation)
            await transacao.finish()
            AccountStatusModel.shared.dados = dados
            SubscriptionViewModel.shared.dados = dados
            if let atual = catalogo {
                catalogo = AppStoreCatalog(
                    appAccountToken: atual.appAccountToken,
                    bloqueio: atual.bloqueio,
                    produtoAtual: transacao.revocationDate == nil ? transacao.productID : atual.produtoAtual,
                    planos: atual.planos
                )
            }
            return true
        } catch let error as APIError {
            // 409: assinatura de outra conta do app. Finalizar não muda nada
            // (a Apple segue cobrando o dono); não repetir a cada abertura.
            if error.statusCode == 409 { await transacao.finish() }
            if !silencioso { errorMessage = error.message }
            return false
        } catch {
            if !silencioso { errorMessage = "Compra feita, mas não conseguimos confirmar agora. Ela será aplicada assim que a conexão voltar." }
            return false
        }
    }
}

extension Product.SubscriptionPeriod {
    /// "por mês", "a cada 3 meses"…
    var descricaoPtBr: String {
        switch unit {
        case .day: value == 1 ? "por dia" : "a cada \(value) dias"
        case .week: value == 1 ? "por semana" : "a cada \(value) semanas"
        case .month: value == 1 ? "por mês" : "a cada \(value) meses"
        case .year: value == 1 ? "por ano" : "a cada \(value) anos"
        @unknown default: ""
        }
    }
}
