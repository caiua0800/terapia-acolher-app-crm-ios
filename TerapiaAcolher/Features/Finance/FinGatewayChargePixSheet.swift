import SwiftUI
import UIKit

// MARK: - Pix da cobrança gerado pelo Acolher Financeiro
//
// O servidor manda `pixQrCodeImage` nulo de propósito: o QR é desenhado aqui
// a partir do copia-e-cola, então nada de imagem trafega pela rede.

struct FinGatewayChargePixSheet: View {
    let charge: GwCharge
    var simulation: Bool
    var provider: GwProvider?
    /// Chamado quando o pagamento é simulado, pra a tela de trás recarregar.
    var onPaid: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var atual: GwCharge
    @State private var isSimulating = false
    @State private var errorMessage: String?

    init(
        charge: GwCharge,
        simulation: Bool,
        provider: GwProvider?,
        onPaid: @escaping () -> Void
    ) {
        self.charge = charge
        self.simulation = simulation
        self.provider = provider
        self.onPaid = onPaid
        _atual = State(initialValue: charge)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        cabecalho
                        if atual.status == .paid {
                            pago
                        } else {
                            GwQRCodeView(payload: atual.pixCopyPaste)
                            validade
                            copiaECola
                        }
                        valores
                        if simulation, atual.status != .paid {
                            botaoSimular
                        }
                        // Tela com QR e valor: o selo não some se o provedor
                        // não tiver chegado.
                        GwProviderFooter(provider: provider ?? .asaasPadrao)
                    }
                    .padding(Theme.screenPadding)
                }
            }
            .navigationTitle("Cobrança por Pix")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fechar") { dismiss() }
                        .foregroundStyle(Theme.primary)
                }
            }
            .alert("Ops", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .presentationDetents([.large])
    }

    // MARK: Blocos

    private var cabecalho: some View {
        VStack(spacing: 6) {
            Text(Formatters.brl(atual.amount))
                .font(Theme.moneyDisplay(32))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
            if let nome = atual.patientName {
                Text(nome)
                    .font(Theme.body(15, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            if let descricao = atual.description {
                Text(descricao)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.top, 4)
    }

    private var pago: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.success)
            Text("Pagamento confirmado")
                .font(Theme.serifTitle(20))
                .foregroundStyle(Theme.textPrimary)
            if let pago = atual.paidAt {
                Text(GwFormat.dayTime.string(from: pago))
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textSecondary)
            }
            Text("O valor líquido já entrou no seu saldo.")
                .font(Theme.body(13))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(Theme.successSoft, in: RoundedRectangle(cornerRadius: 16))
    }

    private var validade: some View {
        VStack(spacing: 4) {
            Text(atual.status == .expired ? "Pix expirado" : GwFormat.expiry(atual.expiresAt))
                .font(Theme.body(12, weight: .semibold))
                .foregroundStyle(atual.status == .expired ? Theme.danger : Theme.textSecondary)
            // Ninguém precisa ficar conferindo: quando o pagamento cai, a
            // cobrança se marca sozinha e o líquido entra no saldo.
            if atual.status != .expired {
                Text("Quando o pagamento cair, a cobrança é marcada como paga e o valor líquido entra no seu saldo automaticamente.")
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var copiaECola: some View {
        ThemeCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("PIX COPIA E COLA")
                    .font(Theme.body(10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.textSecondary)
                Text(atual.pixCopyPaste)
                    .font(Theme.money(11))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(3)
                    .truncationMode(.middle)
                HStack(spacing: 10) {
                    GwCopyButton(title: "Copiar código", value: atual.pixCopyPaste, icon: "qrcode")
                    // Manda a MENSAGEM pronta, não o código cru: colado no
                    // WhatsApp sozinho, o código parece spam e o paciente não
                    // sabe o que fazer com ele.
                    ShareLink(item: mensagemParaOPaciente) {
                        Label("Enviar", systemImage: "square.and.arrow.up")
                            .font(Theme.body(15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22))
                            .overlay(
                                RoundedRectangle(cornerRadius: 22)
                                    .stroke(Theme.border, lineWidth: 1)
                            )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Texto pronto para mandar ao paciente — o mesmo do CRM web.
    private var mensagemParaOPaciente: String {
        let primeiroNome = atual.patientName?
            .split(separator: " ").first
            .map { ", \($0)" } ?? ""
        let descricao = atual.description.map { " (\($0))" } ?? ""
        return """
        Oi\(primeiroNome)! Segue o Pix de \(Formatters.brl(atual.amount))\(descricao):

        \(atual.pixCopyPaste)

        É só copiar esse código e pagar pelo Pix. Qualquer dúvida é só me chamar.
        """
    }

    private var valores: some View {
        ThemeCard {
            VStack(alignment: .leading, spacing: 10) {
                GwValueRow(label: "Valor da cobrança", value: Formatters.brl(atual.amount))
                GwValueRow(
                    label: "Taxa de plataforma Terapia Acolher",
                    value: "− \(Formatters.brl(atual.platformFee))"
                )
                GwValueRow(
                    label: "Tarifa Pix \(provider?.name ?? GwProvider.asaasPadrao.name)",
                    value: "− \(Formatters.brl(atual.providerFee))"
                )
                Divider().overlay(Theme.border)
                GwValueRow(
                    label: "Você recebe",
                    value: Formatters.brl(atual.netAmount),
                    destaque: true,
                    valueColor: Theme.success
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var botaoSimular: some View {
        VStack(spacing: 8) {
            GwSimulationBanner()
            SecondaryButton(
                title: "Simular pagamento (teste)",
                icon: "checkmark.circle",
                isLoading: isSimulating,
                tint: Theme.warning
            ) {
                Task { await simular() }
            }
            .accessibilityIdentifier("gwSimularPagamento")
        }
    }

    private func simular() async {
        isSimulating = true
        defer { isSimulating = false }
        do {
            atual = try await FinGatewayAPI.simulatePayment(chargeId: atual.chargeId)
            Haptics.success()
            await FinGatewayStore.shared.load(showSpinner: false)
            onPaid()
        } catch is CancellationError {
        } catch {
            errorMessage = (error as? APIError)?.message
                ?? "Não foi possível simular o pagamento."
        }
    }
}
