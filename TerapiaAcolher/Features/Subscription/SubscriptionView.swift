import StoreKit
import SwiftUI

// MARK: - ViewModel

@Observable
final class SubscriptionViewModel {
    /// `var`: o logout troca por uma instância nova (ver SessionScope).
    static var shared = SubscriptionViewModel()

    var dados: MySubscription? = nil
    var isLoading = false
    var errorMessage: String? = nil

    @MainActor
    func load(showSpinner: Bool = true) async {
        if showSpinner && dados == nil { isLoading = true }
        errorMessage = nil
        do {
            let novo = try await SubscriptionAPI.mine()
            dados = novo
            AccountStatusModel.shared.dados = novo
        } catch is CancellationError {
        } catch let error as APIError {
            errorMessage = error.message
        } catch {
            errorMessage = "Não foi possível carregar sua assinatura."
        }
        isLoading = false
    }
}

// MARK: - Tela: assinatura e plano

/// Estado do plano e assinatura pela App Store (In-App Purchase).
///
/// Preço e período vêm SEMPRE do StoreKit (`Product.displayPrice`), nunca da
/// nossa tabela: o valor cobrado no iPhone é o da Apple. Nada de site, link
/// ou pagamento fora do app (App Store 3.1.1 / 3.1.3).
struct SubscriptionView: View {
    @State private var model = SubscriptionViewModel.shared
    @State private var loja = StoreKitStore.shared
    @State private var gerenciando = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            content
        }
        .task {
            async let a: Void = model.load()
            async let b: Void = loja.carregar()
            _ = await (a, b)
        }
        .manageSubscriptionsSheet(isPresented: $gerenciando)
        .onChange(of: gerenciando) { _, aberto in
            // Voltou da folha da Apple: pode ter trocado ou cancelado.
            if !aberto { Task { await model.load(showSpinner: false) } }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.dados == nil {
            ProgressView().tint(Theme.primary)
        } else if let erro = model.errorMessage, model.dados == nil {
            VStack(spacing: 14) {
                Text(erro)
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                RetryButton { Task { await model.load() } }
            }
            .padding(.horizontal, 32)
        } else if let dados = model.dados {
            ScrollView {
                VStack(spacing: 16) {
                    PlanoAtualCard(dados: dados)
                    mensagens
                    if !dados.preVenda {
                        PlanosSection(dados: dados, loja: loja)
                        acoes(dados)
                        RodapeLegal()
                    }
                    UsoCard(uso: dados.uso)
                    // Inativa: o plano não vale agora — listar "incluído" confunde.
                    if dados.active, !dados.recursos.destaques.isEmpty {
                        RecursosCard(recursos: dados.recursos)
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .refreshable {
                await model.load(showSpinner: false)
                await loja.carregar()
            }
        }
    }

    @ViewBuilder
    private var mensagens: some View {
        if let erro = loja.errorMessage {
            Aviso(texto: erro, cor: Theme.danger, fundo: Theme.dangerSoft, icone: "exclamationmark.circle.fill")
        } else if let info = loja.infoMessage {
            Aviso(texto: info, cor: Theme.success, fundo: Theme.successSoft, icone: "checkmark.circle.fill")
        }
    }

    @ViewBuilder
    private func acoes(_ dados: MySubscription) -> some View {
        VStack(spacing: 10) {
            if dados.appStore {
                SecondaryButton(title: "Gerenciar assinatura", icon: "gearshape") {
                    Haptics.tap()
                    gerenciando = true
                }
            }
            SecondaryButton(
                title: "Restaurar compras",
                icon: "arrow.clockwise",
                isLoading: loja.restaurando
            ) {
                Haptics.tap()
                Task {
                    await loja.restaurar()
                    await model.load(showSpinner: false)
                }
            }
        }
    }
}

// MARK: - Planos à venda

private struct PlanosSection: View {
    let dados: MySubscription
    let loja: StoreKitStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PLANOS")
                .font(Theme.body(11, weight: .semibold))
                .kerning(1.2)
                .foregroundStyle(Theme.textSecondary)
                .padding(.leading, 4)

            if loja.isLoading && loja.catalogo == nil {
                ProgressView().tint(Theme.primary).frame(maxWidth: .infinity).padding(.vertical, 20)
            } else if let catalogo = loja.catalogo {
                if let bloqueio = catalogo.bloqueio {
                    Aviso(texto: bloqueio, cor: Theme.textSecondary, fundo: Theme.surface, icone: "info.circle")
                } else if itens(catalogo).isEmpty {
                    Aviso(texto: "Os planos não estão disponíveis agora. Tente de novo mais tarde.", cor: Theme.textSecondary, fundo: Theme.surface, icone: "info.circle")
                } else {
                    ForEach(itens(catalogo), id: \.produto.id) { item in
                        PlanoCard(
                            plano: item.plano,
                            produto: item.produto,
                            atual: catalogo.produtoAtual == item.produto.id,
                            trocar: dados.appStore && catalogo.produtoAtual != nil,
                            comprando: loja.comprando,
                            comprar: { Task { await loja.comprar(item.produto) } }
                        )
                    }
                }
            } else if loja.errorMessage != nil {
                RetryButton { Task { await loja.carregar() } }
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// Um cartão por produto que o StoreKit devolveu (produto ainda não
    /// aprovado na App Store simplesmente não aparece).
    private func itens(_ c: AppStoreCatalog) -> [(plano: AppStorePlan, produto: Product)] {
        c.planos.flatMap { plano in
            plano.produtos.compactMap { p in loja.produtos[p.productId].map { (plano, $0) } }
        }
    }
}

private struct PlanoCard: View {
    let plano: AppStorePlan
    let produto: Product
    let atual: Bool
    let trocar: Bool
    let comprando: String?
    let comprar: () -> Void

    var body: some View {
        ThemeCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(plano.nome)
                            .font(Theme.serifTitle(22))
                            .foregroundStyle(Theme.textPrimary)
                        if let descricao = plano.descricao, !descricao.isEmpty {
                            Text(descricao)
                                .font(Theme.body(13.5))
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 8)
                    if atual {
                        StatusBadge(label: "ATUAL", color: Theme.success, background: Theme.successSoft)
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(produto.displayPrice)
                        .font(Theme.money(24))
                        .foregroundStyle(Theme.textPrimary)
                    if let periodo = produto.subscription?.subscriptionPeriod {
                        Text(periodo.descricaoPtBr)
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                if !plano.destaques.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(plano.destaques, id: \.self) { item in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.primary)
                                    .padding(.top, 2)
                                Text(item)
                                    .font(Theme.body(13.5))
                                    .foregroundStyle(Theme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                PrimaryButton(
                    title: atual ? "Seu plano atual" : (trocar ? "Mudar para este plano" : "Assinar"),
                    isLoading: comprando == produto.id,
                    isEnabled: !atual && comprando == nil
                ) {
                    Haptics.tap()
                    comprar()
                }
                .accessibilityIdentifier("assinar-\(produto.id)")
            }
        }
    }
}

/// Texto exigido pela Apple para assinatura que renova sozinha (3.1.2) e os
/// links de Termos e Privacidade.
private struct RodapeLegal: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("A assinatura renova automaticamente pelo mesmo valor e período, a menos que seja cancelada pelo menos 24 horas antes do fim do período. A cobrança é feita na sua conta Apple. Gerencie ou cancele em Ajustes › seu nome › Assinaturas.")
                .font(Theme.body(12))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                Link("Termos de Uso", destination: LinksLegais.termos)
                Link("Política de Privacidade", destination: LinksLegais.privacidade)
            }
            .font(Theme.body(12.5, weight: .semibold))
            .tint(Theme.primary)
        }
        .padding(.horizontal, 12)
        .padding(.top, 2)
    }
}

enum LinksLegais {
    static let termos = URL(string: "https://crm.terapiaacolher.com.br/termos")!
    static let privacidade = URL(string: "https://crm.terapiaacolher.com.br/politica-privacidade")!
}

private struct Aviso: View {
    let texto: String
    let cor: Color
    let fundo: Color
    let icone: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icone)
                .font(.system(size: 13, weight: .semibold))
                .padding(.top, 1)
            Text(texto)
                .font(Theme.body(13.5))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(cor)
        .padding(14)
        .background(fundo, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }
}

// MARK: - Estado do plano

private struct PlanoAtualCard: View {
    let dados: MySubscription

    var body: some View {
        ThemeCard(padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SEU PLANO")
                            .font(Theme.body(11, weight: .semibold))
                            .kerning(1.2)
                            .foregroundStyle(Theme.textSecondary)

                        Text(dados.tituloDoPlano)
                            .font(Theme.serifTitle(24))
                            .foregroundStyle(Theme.textPrimary)
                    }

                    Spacer(minLength: 8)

                    if dados.emTeste, let dias = dados.diasRestantes {
                        StatusBadge(
                            label: dias == 0 ? "ÚLTIMO DIA" : "\(dias) DIA\(dias == 1 ? "" : "S")",
                            color: dados.testeUrgente ? Theme.danger : Theme.success,
                            background: dados.testeUrgente ? Theme.dangerSoft : Theme.successSoft
                        )
                    } else if dados.cortesia {
                        StatusBadge(label: "CORTESIA", color: Theme.success, background: Theme.successSoft)
                    } else if dados.preVenda {
                        StatusBadge(
                            label: SubscriptionStatus.presale.label.uppercased(),
                            color: Theme.warning,
                            background: Theme.warningSoft
                        )
                    } else if !dados.active {
                        StatusBadge(label: "INATIVA", color: Theme.danger, background: Theme.dangerSoft)
                    }
                }

                Text(explicacao)
                    .font(Theme.body(14))
                    .foregroundStyle((dados.testeUrgente || !dados.active) && !dados.preVenda ? Theme.danger : Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let mudanca = dados.mudancaAgendada, let plano = mudanca.plano {
                    Divider().overlay(Theme.border).padding(.vertical, 2)
                    Label {
                        Text(textoDaMudanca(plano, em: mudanca.valeEm))
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.warning)
                    }
                }
            }
        }
    }

    private var explicacao: String {
        if dados.emTeste {
            let sufixo = dados.plano.map { " Você está experimentando o \($0.nome)." } ?? ""
            guard let dias = dados.diasRestantes else { return "Seu período de teste está em andamento.\(sufixo)" }
            if dias == 0 { return "Seu teste termina hoje.\(sufixo)" }
            if dias == 1 { return "Resta 1 dia de teste.\(sufixo)" }
            return "Restam \(dias) dias de teste.\(sufixo)"
        }
        if dados.cortesia {
            return "Seu acesso é cortesia da Terapia Acolher — nada é cobrado."
        }
        if dados.preVenda {
            return "Sua assinatura da pré-venda está garantida. Avisaremos por e-mail quando o acesso for liberado."
        }
        if !dados.active {
            return "Sua assinatura não está ativa. Seus dados continuam salvos. Escolha um plano abaixo para voltar a usar tudo."
        }
        if let fim = dados.currentPeriodEnd {
            if dados.appStore {
                return dados.renovacaoAutomatica
                    ? "Assinado pela App Store · renova em \(SubscriptionFormat.data(fim))."
                    : "Assinado pela App Store · renovação desligada, vale até \(SubscriptionFormat.data(fim))."
            }
            let renovacao = dados.plano?.periodicidade?.renovacao ?? "Renova"
            return "\(renovacao) · próxima em \(SubscriptionFormat.data(fim))."
        }
        return "Assinatura ativa."
    }

    private func textoDaMudanca(_ plano: String, em data: Date?) -> String {
        guard let data else { return "Mudança para o \(plano) já agendada." }
        return "A partir de \(SubscriptionFormat.data(data)) seu plano passa a ser o \(plano)."
    }
}

// MARK: - Uso do ciclo

private struct UsoCard: View {
    let uso: SubscriptionUsage

    var body: some View {
        ThemeCard(padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                Text("USO NESTE CICLO")
                    .font(Theme.body(11, weight: .semibold))
                    .kerning(1.2)
                    .foregroundStyle(Theme.textSecondary)

                ForEach(linhas, id: \.rotulo) { linha in
                    UsoLinha(rotulo: linha.rotulo, item: linha.item)
                }
            }
        }
    }

    /// Mesma lista do CRM web: com as cotas separadas do Zelo quando o backend
    /// manda; sem elas, a soma antiga. Recurso fora do plano e sem uso some —
    /// "0 de 0" não diz nada.
    private var linhas: [(rotulo: String, item: SubscriptionUsageItem)] {
        var itens: [(String, SubscriptionUsageItem)] = [
            ("Pacientes ativos", uso.pacientes),
            ("Mensagens de WhatsApp", uso.whatsapp),
        ]
        if let prontuarios = uso.iaProntuarios {
            itens.append(("Prontuários com o Zelo", prontuarios))
            itens.append(("Anamneses com o Zelo", uso.iaAnamneses ?? uso.ia))
            itens.append(("Resumos do Zelo", uso.resumos ?? uso.ia))
        } else {
            itens.append(("Rascunhos do Zelo", uso.ia))
        }
        return itens.filter { !($0.1.foraDoPlano && $0.1.usado == 0) }
    }
}

private struct UsoLinha: View {
    let rotulo: String
    let item: SubscriptionUsageItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(rotulo)
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 8)
                Text(valor)
                    .font(Theme.money(13))
                    .foregroundStyle(item.apertado ? Theme.warning : Theme.textSecondary)
            }

            if !item.ilimitado && !item.foraDoPlano {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Theme.border)
                        Capsule()
                            .fill(item.apertado ? Theme.warning : Theme.primary)
                            // Largura mínima: barra invisível parece dado que
                            // não carregou.
                            .frame(width: max(geo.size.width * item.fracao, 3))
                    }
                }
                .frame(height: 6)
            }
        }
    }

    private var valor: String {
        if item.ilimitado { return "\(item.usado) · sem limite" }
        if item.foraDoPlano { return "\(item.usado) · fora do plano" }
        return "\(item.usado) de \(item.teto)"
    }
}

// MARK: - O que está incluído

private struct RecursosCard: View {
    let recursos: SubscriptionEntitlements

    var body: some View {
        ThemeCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("INCLUÍDO NO SEU PLANO")
                    .font(Theme.body(11, weight: .semibold))
                    .kerning(1.2)
                    .foregroundStyle(Theme.textSecondary)

                ForEach(recursos.destaques, id: \.rotulo) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.primary)
                            .padding(.top, 1)
                        Text(item.rotulo)
                            .font(Theme.body(14))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Text(item.valor)
                            .font(Theme.body(14, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
            }
        }
    }
}

// MARK: - Datas

enum SubscriptionFormat {
    private static let dia: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "dd/MM/yyyy"
        return f
    }()

    static func data(_ date: Date) -> String { dia.string(from: date) }
}
