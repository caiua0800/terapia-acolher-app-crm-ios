import SwiftUI

/// "Ver planos": abre a tela Assinatura numa folha, de onde a pessoa assina
/// pela App Store sem perder a tela em que estava. Usado onde o recurso não
/// está incluído ou o limite acabou.
struct VerPlanosButton: View {
    enum Style {
        /// Contorno — ao lado de outro conteúdo, sem roubar a cena.
        case secondary
        /// Cápsula pequena para faixas e cartões.
        case compact
    }

    var style: Style = .secondary
    /// Cor da cápsula no estilo compacto.
    var tint: Color = Theme.primary

    @State private var aberto = false

    var body: some View {
        Group {
            switch style {
            case .secondary:
                SecondaryButton(title: "Ver planos", icon: "sparkles", tint: Theme.primary) { abrir() }
            case .compact:
                Button { abrir() } label: {
                    HStack(spacing: 6) {
                        Text("Ver planos")
                            .font(Theme.body(12.5, weight: .semibold))
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(tint, in: Capsule())
                }
                .buttonStyle(.pressable)
            }
        }
        .accessibilityIdentifier("verPlanos")
        .sheet(isPresented: $aberto) { AssinaturaSheet() }
    }

    private func abrir() {
        Haptics.tap()
        aberto = true
    }
}

/// Tela Assinatura dentro de uma folha (com "Fechar").
struct AssinaturaSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SubscriptionView()
                .setToolbarTitle("Assinatura")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Fechar") { dismiss() }
                            .font(Theme.body(15, weight: .semibold))
                    }
                }
        }
        .tint(Theme.primary)
    }
}
