import SwiftUI

// MARK: - Regra de texto (App Store 3.1.3(f))
//
// O app iOS é acompanhante gratuito da ferramenta web. Ele INFORMA (limite
// atingido, recurso não incluído, conta inativa) e nunca CONVIDA a comprar:
// nada de nome de plano, preço, teste grátis, "assine", "upgrade", botão
// "Ver planos" ou link/e-mail para o site. Todo texto de conta passa por aqui
// para nenhuma tela inventar o seu.

enum AccountCopy {
    static let naoIncluido = "Não incluído na sua conta."
    static let limiteAtingido = "Você atingiu o limite da sua conta."
    static let contaInativa = "Sua conta não está ativa. Seus dados continuam salvos."

    static func limite(de recurso: String) -> String {
        "Você atingiu o limite de \(recurso) da sua conta."
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

/// Faixa no topo de todas as telas, só quando a conta está inativa. Informa e
/// para aí: sem botão e sem caminho de compra.
struct AccountStatusBanner: View {
    @State private var model = AccountStatusModel.shared

    var body: some View {
        // VStack com âncora de altura zero: sem dados ainda, a view precisa
        // existir para o .task rodar.
        VStack(spacing: 0) {
            Color.clear.frame(height: 0)
            if let dados = model.dados, dados.enforcing, !dados.active, !dados.preVenda {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.top, 2)
                    Text(AccountCopy.contaInativa)
                        .font(Theme.body(12.5, weight: .medium))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Theme.danger)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Theme.dangerSoft)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.dados?.active)
        .task { if model.dados == nil { await model.load() } }
    }
}

// MARK: - Recurso não incluído

/// Estado calmo para recurso que a conta não inclui (leads, Vitrine, Acolher
/// Financeiro). Não é erro — é informação, e termina aí.
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

            Text("NÃO INCLUÍDO NA SUA CONTA")
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
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
    }
}
