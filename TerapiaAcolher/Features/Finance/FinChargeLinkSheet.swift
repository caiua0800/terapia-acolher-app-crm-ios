import SwiftUI

/// Fim do fluxo de cobrança: a cobrança foi criada e o link já existe.
///
/// Antes a tela só fechava, e o terapeuta ficava com uma cobrança criada e nada
/// para mandar ao paciente — tinha que achar a cobrança na lista e só então
/// pedir o link. Aqui ele já sai com a mensagem pronta.
struct FinChargeLinkSheet: View {
    let result: FinCheckoutResult
    let patientName: String
    var onClose: () -> Void

    @State private var copiado: Copiado?
    @Environment(\.openURL) private var openURL

    private enum Copiado { case link, codigo, mensagem }

    /// Mensagem inteira, pronta para colar no WhatsApp. É o que ele realmente
    /// manda — copiar só a URL obriga a escrever o resto na mão toda vez.
    private var mensagem: String {
        let primeiroNome = patientName.split(separator: " ").first.map(String.init) ?? patientName
        var texto = "Oi, \(primeiroNome)! Segue o link para o pagamento de \(Formatters.brl(result.amount)):"
        if let url = result.invoiceUrl { texto += "\n\n\(url)" }
        texto += "\n\nQualquer dúvida é só me chamar."
        return texto
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        cabecalho
                        if let codigo = result.pixQrCode { pixCard(codigo) }
                        acoes
                    }
                    .padding(Theme.screenPadding)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Cobrança criada")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Concluir") { onClose() }
                        .font(Theme.body(16, weight: .semibold))
                }
            }
        }
    }

    private var cabecalho: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Theme.success)
                .frame(width: 58, height: 58)
                .background(Theme.successSoft, in: Circle())

            Text(Formatters.brl(result.amount))
                .font(Theme.moneyDisplay(32))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)

            Text("para \(patientName)")
                .font(Theme.body(14))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.top, 8)
    }

    private func pixCard(_ codigo: String) -> some View {
        ThemeCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("PIX COPIA E COLA")
                    .font(Theme.body(10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.textSecondary)

                Text(codigo)
                    .font(Theme.body(11, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .truncationMode(.middle)

                Button {
                    copiar(codigo, tipo: .codigo)
                } label: {
                    Label(
                        copiado == .codigo ? "Código copiado" : "Copiar código Pix",
                        systemImage: copiado == .codigo ? "checkmark" : "doc.on.doc"
                    )
                    .font(Theme.body(14, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Theme.primarySoft, in: Capsule())
                }
                .buttonStyle(.pressable)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var acoes: some View {
        VStack(spacing: 10) {
            // A mensagem inteira vem primeiro: é o que ele de fato manda.
            PrimaryButton(
                title: copiado == .mensagem ? "Mensagem copiada!" : "Copiar mensagem pro WhatsApp",
                icon: copiado == .mensagem ? "checkmark" : "text.bubble"
            ) {
                copiar(mensagem, tipo: .mensagem)
            }

            if let urlString = result.invoiceUrl {
                Button {
                    copiar(urlString, tipo: .link)
                } label: {
                    Label(
                        copiado == .link ? "Link copiado" : "Copiar só o link",
                        systemImage: copiado == .link ? "checkmark" : "link"
                    )
                    .font(Theme.body(15, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.pressable)

                if let url = URL(string: urlString) {
                    Button {
                        Haptics.tap()
                        openURL(url)
                    } label: {
                        Label("Abrir a fatura", systemImage: "arrow.up.right")
                            .font(Theme.body(14, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                    }
                    .buttonStyle(.pressable)
                }
            }
        }
    }

    private func copiar(_ texto: String, tipo: Copiado) {
        UIPasteboard.general.string = texto
        Haptics.success()
        withAnimation { copiado = tipo }
        // Volta ao rótulo original: um "Copiado!" permanente faz o terapeuta
        // duvidar se o segundo toque funcionou.
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if copiado == tipo { withAnimation { copiado = nil } }
        }
    }
}
