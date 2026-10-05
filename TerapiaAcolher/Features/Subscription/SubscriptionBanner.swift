import SwiftUI

/// Faixa de estado da assinatura, no topo de todas as telas.
///
/// Vive na casca e não em cada tela porque o fato é da CONTA, não da tela —
/// mesma razão do aviso de conexão. E só aparece quando há o que dizer: teste
/// correndo, teste acabando ou assinatura inativa. Quem está em dia não vê
/// nada; faixa permanente vira paisagem e deixa de ser lida justamente quando
/// importa.
struct SubscriptionBanner: View {
    @Binding var selection: MenuDestination

    @State private var model = SubscriptionViewModel.shared

    var body: some View {
        Group {
            if let dados = model.dados, deveAparecer(dados) {
                if inativa(dados) {
                    inativaFaixa
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else {
                    Button {
                        Haptics.tap()
                        selection = .assinatura
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: urgente(dados) ? "exclamationmark.circle.fill" : "clock")
                                .font(.system(size: 12, weight: .semibold))
                            Text(texto(dados))
                                .font(Theme.body(12.5, weight: .medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .opacity(0.7)
                        }
                        .foregroundStyle(urgente(dados) ? Theme.danger : Theme.success)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(urgente(dados) ? Theme.dangerSoft : Theme.successSoft)
                    }
                    .buttonStyle(.plain)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.dados?.status)
        // Falha aqui é silenciosa: a faixa é um aviso, não pode virar erro na
        // frente de quem só queria abrir a agenda.
        .task { if model.dados == nil { await model.load(showSpinner: false) } }
    }

    /// Assinatura inativa: a faixa diz o fato e já oferece o link por e-mail —
    /// é o único caminho, e escondê-lo atrás de mais uma tela só atrasa.
    private var inativaFaixa: some View {
        HStack(spacing: 10) {
            Button {
                Haptics.tap()
                selection = .assinatura
            } label: {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.top, 2)
                    Text("Sua assinatura não está ativa. Seus dados continuam salvos.")
                        .font(Theme.body(12.5, weight: .medium))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Theme.danger)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            ManageAccountButton(style: .compact, tint: Theme.danger)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Theme.dangerSoft)
    }

    private func inativa(_ dados: MySubscription) -> Bool {
        !dados.active && !dados.preVenda
    }

    private func deveAparecer(_ dados: MySubscription) -> Bool {
        // Na própria tela de assinatura a faixa seria redundante.
        if selection == .assinatura { return false }
        if dados.cortesia || dados.preVenda { return false }
        if dados.emTeste { return true }
        return !dados.active
    }

    private func urgente(_ dados: MySubscription) -> Bool {
        !dados.active || dados.testeUrgente
    }

    private func texto(_ dados: MySubscription) -> String {
        if !dados.active && !dados.emTeste { return "Sua assinatura não está ativa." }
        guard let dias = dados.diasRestantes else { return "Você está no período de teste." }
        if dias == 0 { return "Teste grátis · termina hoje." }
        if dias == 1 { return "Teste grátis · resta 1 dia." }
        return "Teste grátis · restam \(dias) dias."
    }
}
