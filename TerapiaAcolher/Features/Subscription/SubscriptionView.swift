import SwiftUI

// MARK: - ViewModel

@Observable
final class SubscriptionViewModel {
    static let shared = SubscriptionViewModel()

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
/// aqui não há botão de assinar nem valor em reais — quem quiser mudar fala com
/// a equipe.
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
                    UsoCard(uso: dados.uso)
                    if !dados.recursos.destaques.isEmpty {
                        RecursosCard(recursos: dados.recursos)
                    }
                    rodape(dados)
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .refreshable { await model.load(showSpinner: false) }
        }
    }

    private func rodape(_ dados: MySubscription) -> some View {
        // Sem botão de compra e sem link de pagamento: a contratação acontece
        // fora do app. Dizer com quem falar é o que resta — e é o suficiente.
        Text(dados.active
             ? "Para mudar de plano ou tirar dúvidas, fale com a equipe da Terapia Acolher."
             : "Para ativar seu acesso, fale com a equipe da Terapia Acolher.")
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
                    } else if !dados.active {
                        StatusBadge(label: "INATIVA", color: Theme.danger, background: Theme.dangerSoft)
                    }
                }

                Text(explicacao)
                    .font(Theme.body(14))
                    .foregroundStyle(dados.testeUrgente || !dados.active ? Theme.danger : Theme.textSecondary)
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

                UsoLinha(rotulo: "Pacientes ativos", item: uso.pacientes)
                UsoLinha(rotulo: "Mensagens de WhatsApp", item: uso.whatsapp)
                UsoLinha(rotulo: "Rascunhos de IA", item: uso.ia)
            }
        }
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

            if !item.ilimitado {
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
        item.ilimitado ? "\(item.usado) · sem limite" : "\(item.usado) de \(item.teto)"
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
