import SwiftUI

// MARK: - Regra de texto
//
// Desde a 1.3.0 o app vende a assinatura pela App Store (In-App Purchase):
// pode convidar a assinar AQUI ("Ver planos" leva à tela Assinatura). Nunca
// mencionar site, link externo, pagamento fora do app ou preço que não seja
// o do StoreKit. Os textos neutros abaixo servem às mensagens do servidor,
// escritas para o CRM web (ver `MensagemDeConta`).

enum AccountCopy {
    static let naoIncluido = "Não incluído no seu plano."
    static let limiteAtingido = "Você atingiu o limite do seu plano."
    static let contaInativa = "Sua assinatura não está ativa. Seus dados continuam salvos."

    static func limite(de recurso: String) -> String {
        "Você atingiu o limite de \(recurso) do seu plano."
    }
}

// MARK: - Estado da conta

@Observable
final class AccountStatusModel {
    /// `var`: o logout troca por uma instância nova (ver SessionScope).
    static var shared = AccountStatusModel()

    var dados: MySubscription? = nil

    @MainActor
    func load() async {
        // Falha é silenciosa: é um aviso, não pode virar erro na frente de
        // quem só queria abrir a agenda.
        if let novo = try? await SubscriptionAPI.mine() { dados = novo }
    }
}

/// Faixa de estado da assinatura, no topo de todas as telas.
///
/// Vive na casca e não em cada tela porque o fato é da CONTA, não da tela —
/// mesma razão do aviso de conexão. E só aparece quando há o que dizer: teste
/// correndo ou assinatura inativa. Quem está em dia não vê nada. Tocar leva
/// à tela Assinatura.
struct AccountStatusBanner: View {
    @Binding var selection: MenuDestination
    @State private var model = AccountStatusModel.shared

    var body: some View {
        // VStack com âncora de altura zero: sem dados ainda, a view precisa
        // existir para o .task rodar.
        VStack(spacing: 0) {
            Color.clear.frame(height: 0)
            if let dados = model.dados, deveAparecer(dados) {
                Button {
                    Haptics.tap()
                    selection = .assinatura
                } label: {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: urgente(dados) ? "exclamationmark.circle.fill" : "clock")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.top, 2)
                        Text(texto(dados))
                            .font(Theme.body(12.5, weight: .medium))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        Text("Ver planos")
                            .font(Theme.body(12.5, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.top, 3)
                    }
                    .foregroundStyle(urgente(dados) ? Theme.danger : Theme.success)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(urgente(dados) ? Theme.dangerSoft : Theme.successSoft)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("faixaAssinatura")
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.dados?.status)
        .animation(.easeInOut(duration: 0.25), value: model.dados?.active)
        .task { if model.dados == nil { await model.load() } }
    }

    private func deveAparecer(_ dados: MySubscription) -> Bool {
        // Na própria tela de assinatura a faixa seria redundante.
        if selection == .assinatura { return false }
        if dados.cortesia || dados.preVenda { return false }
        if dados.emTeste { return true }
        return dados.enforcing && !dados.active
    }

    private func urgente(_ dados: MySubscription) -> Bool {
        !dados.active || dados.testeUrgente
    }

    private func texto(_ dados: MySubscription) -> String {
        if !dados.active { return AccountCopy.contaInativa }
        guard let dias = dados.diasRestantes else { return "Você está no período de teste." }
        if dias == 0 { return "Teste grátis · termina hoje." }
        if dias == 1 { return "Teste grátis · resta 1 dia." }
        return "Teste grátis · restam \(dias) dias."
    }
}

// MARK: - Recurso não incluído

/// Estado calmo para recurso que o plano não inclui (leads, Vitrine, Acolher
/// Financeiro). Não é erro — é informação, com o caminho para os planos.
struct NotInPlanView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(Theme.primary)
                .frame(width: 64, height: 64)
                .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 18))

            Text("NÃO INCLUÍDO NO SEU PLANO")
                .font(Theme.body(11, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Theme.border.opacity(0.6), in: Capsule())

            Text(title)
                .font(Theme.serifTitle(22))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)

            Text(message)
                .font(Theme.body(14))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VerPlanosButton()
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
    }
}
