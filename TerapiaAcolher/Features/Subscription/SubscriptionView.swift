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
            dados = try await SubscriptionAPI.mine()
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

/// Mostra o estado do plano; **não vende**. Contratação, troca de plano e
/// preço ficam no CRM web de propósito (ver `SubscriptionModels.swift`), então
/// aqui não há botão de assinar nem valor em reais. O único caminho é
/// "Gerenciar conta": a API manda um link de acesso para o e-mail do terapeuta
/// (App Store 3.1.3 — ver `ManageAccountButton`).
struct SubscriptionView: View {
    @State private var model = SubscriptionViewModel.shared

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            content
        }
        .task { await model.load() }
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
                    if !dados.active && !dados.preVenda {
                        ManageAccountButton(style: .primary)
                    }
                    UsoCard(uso: dados.uso)
                    if !dados.recursos.destaques.isEmpty {
                        RecursosCard(recursos: dados.recursos)
                    }
                    // Ativo também pode querer trocar de plano: mesmo caminho
                    // do e-mail, só que discreto, depois do conteúdo.
                    if dados.active || dados.preVenda {
                        ManageAccountButton(style: .secondary)
                    }
                    rodape
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .refreshable { await model.load(showSpinner: false) }
        }
    }

    private var rodape: some View {
        // Sem botão de compra e sem link de pagamento: o link chega por e-mail
        // e a gestão acontece fora do app.
        Text(ManageAccountCopy.footer)
            .font(Theme.body(12.5))
            .foregroundStyle(Theme.textSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.top, 4)
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
            return "Sua assinatura não está ativa. Seus dados continuam salvos."
        }
        if let fim = dados.currentPeriodEnd {
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
