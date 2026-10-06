import SwiftUI

/// Detalhes de uma movimentação do extrato (2026-10-06).
///
/// Tocar numa linha do extrato abre isto. Recebimento (Pix ou cartão) e saque
/// têm comprovante em PDF com código de autenticação: qualquer pessoa confere
/// na página pública do Acolher Gestão se o comprovante é verdadeiro, então o
/// terapeuta pode mandar o PDF a um paciente ou contador sem precisar provar
/// nada por fora. Taxas e ajustes abrem o detalhe, mas não têm comprovante.
struct FinGatewayLedgerDetailSheet: View {
    let entrada: GwLedgerEntry
    var provider: GwProvider = .asaasPadrao

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var detalhe: GwLedgerDetail?
    @State private var carregando = true
    @State private var erroCarga: String?
    @State private var baixandoPdf = false
    @State private var arquivo: GwArquivoBaixado?
    @State private var erro: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        cabecalho
                        if carregando {
                            ProgressView()
                                .tint(Theme.primary)
                                .padding(.vertical, 24)
                        } else if let detalhe {
                            informacoes(detalhe)
                            if detalhe.temComprovante {
                                comprovante(detalhe)
                            }
                        } else {
                            // Servidor antigo (sem a rota) ou falha: o básico da
                            // linha continua visível, com o motivo embaixo.
                            ThemeCard {
                                VStack(spacing: 10) {
                                    GwValueRow(label: "Descrição", value: entrada.description)
                                    GwValueRow(
                                        label: "Data",
                                        value: GwFormat.dayTime.string(from: entrada.createdAt)
                                    )
                                }
                            }
                            if let erroCarga {
                                Text(erroCarga)
                                    .font(Theme.body(12.5))
                                    .foregroundStyle(Theme.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        GwProviderLegalFooter(provider: provider)
                    }
                    .padding(Theme.screenPadding)
                }
            }
            .navigationTitle("Detalhes da movimentação")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fechar") { dismiss() }
                        .foregroundStyle(Theme.primary)
                }
            }
            .sheet(item: $arquivo) { baixado in
                GwShareSheet(url: baixado.url)
                    .presentationDetents([.medium, .large])
            }
            .alert("Ops", isPresented: .init(
                get: { erro != nil },
                set: { if !$0 { erro = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(erro ?? "")
            }
            .task { await carregar() }
        }
        .presentationDetents([.large])
    }

    // MARK: Cabeçalho

    private var cabecalho: some View {
        let credito = entrada.type == .credit
        return VStack(spacing: 8) {
            Circle()
                .fill(credito ? Theme.successSoft : Theme.dangerSoft)
                .frame(width: 52, height: 52)
                .overlay(
                    Image(systemName: entrada.kind.icon)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(credito ? Theme.success : Theme.danger)
                )
            Text("\(credito ? "+" : "−") \(Formatters.brl(entrada.amount))")
                .font(Theme.moneyDisplay(30))
                .monospacedDigit()
                .foregroundStyle(credito ? Theme.success : Theme.textPrimary)
            Text(titulo)
                .font(Theme.body(14))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.top, 8)
    }

    private var titulo: String {
        switch entrada.kind {
        case .chargeReceived:
            detalhe?.noCartao == true ? "Recebimento no cartão" : "Recebimento por Pix"
        case .withdrawal: "Saque enviado por Pix"
        default: entrada.kind.label
        }
    }

    // MARK: Informações

    private func informacoes(_ d: GwLedgerDetail) -> some View {
        ThemeCard {
            VStack(spacing: 10) {
                if let descricao = d.description, !descricao.isEmpty {
                    GwValueRow(label: "Descrição", value: descricao)
                }
                GwValueRow(label: "Data", value: GwFormat.dayTime.string(from: d.createdAt))

                if let c = d.charge {
                    Divider().overlay(Theme.border)
                    if let paciente = c.patientName {
                        GwValueRow(label: "Paciente", value: paciente)
                    }
                    if let cobranca = c.description, !cobranca.isEmpty {
                        GwValueRow(label: "Cobrança", value: cobranca)
                    }
                    if d.method != nil {
                        GwValueRow(label: "Forma", value: d.noCartao ? "Cartão de crédito" : "Pix")
                    }
                    if let valor = c.amount {
                        GwValueRow(label: "Valor pago", value: Formatters.brl(valor))
                    }
                    if let taxa = c.platformFee, taxa > 0 {
                        GwValueRow(label: "Taxa de plataforma", value: "− \(Formatters.brl(taxa))")
                    }
                    if let tarifa = c.providerFee, tarifa > 0 {
                        GwValueRow(
                            label: d.noCartao ? "Tarifa do cartão \(provider.name)" : "Tarifa Pix \(provider.name)",
                            value: "− \(Formatters.brl(tarifa))"
                        )
                    }
                    if let liquido = c.netAmount {
                        GwValueRow(
                            label: "Você recebeu",
                            value: Formatters.brl(liquido),
                            destaque: true,
                            valueColor: Theme.success
                        )
                    }
                }

                if let w = d.withdrawal {
                    Divider().overlay(Theme.border)
                    if let titular = w.ownerName {
                        GwValueRow(label: "Para", value: titular)
                    }
                    if let chave = w.pixKeyMasked {
                        GwValueRow(label: "Chave Pix", value: chave)
                    }
                    if let banco = w.bankName {
                        GwValueRow(label: "Banco", value: banco)
                    }
                    if let enviado = w.processedAt {
                        GwValueRow(label: "Enviado em", value: GwFormat.dayTime.string(from: enviado))
                    }
                }

                if let e2e = d.endToEndId ?? d.withdrawal?.endToEndId {
                    Divider().overlay(Theme.border)
                    identificador("ID da transação Pix (E2E)", e2e)
                }
                if let idProvedor = d.providerTransactionId {
                    identificador("ID no \(provider.name)", idProvedor)
                }
            }
        }
    }

    /// Identificadores longos quebram linha em vez de cortar — é o que a pessoa
    /// confere contra o extrato do banco.
    private func identificador(_ rotulo: String, _ valor: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(rotulo)
                .font(Theme.body(13))
                .foregroundStyle(Theme.textSecondary)
            Text(valor)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Comprovante

    private func comprovante(_ d: GwLedgerDetail) -> some View {
        VStack(spacing: 12) {
            if let codigo = d.authCode {
                ThemeCard {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(Theme.success)
                            Text("CÓDIGO DE AUTENTICAÇÃO")
                                .font(Theme.body(10, weight: .semibold))
                                .tracking(1.1)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Text(codigo)
                            .font(.system(size: 17, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.textPrimary)
                            .textSelection(.enabled)
                        Text("Qualquer pessoa confere se este comprovante é verdadeiro pelo código, na página do Acolher Gestão.")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            PrimaryButton(
                title: "Baixar comprovante",
                icon: "arrow.down.doc",
                isLoading: baixandoPdf
            ) {
                Task { await baixarPdf(d) }
            }
            .accessibilityIdentifier("gwBaixarComprovanteMovimentacao")

            if let link = d.verifyUrl, let url = URL(string: link), url.scheme == "https" {
                SecondaryButton(title: "Verificar autenticidade", icon: "safari") {
                    openURL(url)
                }
            }
        }
    }

    // MARK: Rede

    private func carregar() async {
        carregando = true
        defer { carregando = false }
        do {
            detalhe = try await FinGatewayAPI.ledgerEntry(id: entrada.id)
        } catch is CancellationError {
        } catch let erro as APIError where erro.statusCode == 404 {
            erroCarga = "Os detalhes e o comprovante desta movimentação ainda não estão disponíveis. Atualize o app ou tente mais tarde."
        } catch {
            erroCarga = (error as? APIError)?.message ?? "Não foi possível carregar os detalhes agora."
        }
    }

    private func baixarPdf(_ d: GwLedgerDetail) async {
        baixandoPdf = true
        defer { baixandoPdf = false }
        do {
            let pdf = try await FinGatewayAPI.ledgerReceiptPDF(id: d.id, authCode: d.authCode)
            arquivo = try GwArquivoBaixado(pdf)
            Haptics.success()
        } catch is CancellationError {
        } catch {
            erro = (error as? APIError)?.message ?? "Não foi possível gerar o PDF do comprovante."
        }
    }
}
