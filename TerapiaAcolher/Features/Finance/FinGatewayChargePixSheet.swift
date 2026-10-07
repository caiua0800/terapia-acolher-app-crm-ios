import SwiftUI
import UIKit

// MARK: - Pix (ou link do cartão) da cobrança gerado pelo Acolher Financeiro
//
// O servidor manda `pixQrCodeImage` nulo de propósito: o QR é desenhado aqui
// a partir do copia-e-cola, então nada de imagem trafega pela rede.
//
// Cartão (2026-10-06): a mesma folha mostra o link da página segura do Asaas
// no lugar do QR — o paciente digita o cartão lá, nunca no app.

struct FinGatewayChargePixSheet: View {
    let charge: GwCharge
    var simulation: Bool
    var provider: GwProvider?
    /// Resultado do "Enviar agora pelo WhatsApp" / agendamento feitos ao criar.
    var aviso: FinAvisoDeEnvio?
    /// Chamado quando o pagamento cai (real ou simulado), pra a tela de trás recarregar.
    var onPaid: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var atual: GwCharge
    @State private var isSimulating = false
    @State private var errorMessage: String?

    init(
        charge: GwCharge,
        simulation: Bool,
        provider: GwProvider?,
        aviso: FinAvisoDeEnvio? = nil,
        onPaid: @escaping () -> Void
    ) {
        self.charge = charge
        self.simulation = simulation
        self.provider = provider
        self.aviso = aviso
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
                        if let aviso { avisoDoEnvio(aviso) }
                        if atual.status == .paid {
                            pago
                        } else if atual.isCartao {
                            linkDoCartao
                            validade
                        } else {
                            GwQRCodeView(payload: codigoPix)
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
            .navigationTitle(atual.isCartao ? "Cobrança no cartão" : "Cobrança por Pix")
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
        // Pix (ou cartão) em aberto: a confirmação chega por webhook do Asaas, de alguns
        // segundos a ~30 s depois do pagamento. Pergunta a cada 4 s enquanto
        // a folha estiver aberta, pra virar "pago" sozinha — sem isto a
        // terapeuta fechava e reabria achando que o pagamento não tinha caído.
        // A task morre ao fechar a folha ou quando o status muda.
        .task(id: atual.status) {
            guard atual.status == .pending else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled,
                      let novo = try? await FinGatewayAPI.charge(chargeId: atual.chargeId),
                      novo.status != atual.status
                else { continue }
                atual = novo
                if novo.status == .paid {
                    Haptics.success()
                    await FinGatewayStore.shared.load(showSpinner: false)
                    onPaid()
                }
                return
            }
        }
    }

    /// BR Code sem espaço/quebra nas pontas: colado com "\n" no fim, o app
    /// do banco do paciente recusa o código.
    private var codigoPix: String {
        atual.pixCopyPaste.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Blocos

    private func avisoDoEnvio(_ aviso: FinAvisoDeEnvio) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: aviso.ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(aviso.ok ? Theme.success : Theme.warning)
            Text(aviso.texto)
                .font(Theme.body(13))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(aviso.ok ? Theme.successSoft : Theme.warningSoft, in: RoundedRectangle(cornerRadius: 12))
    }

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
            if atual.status == .expired {
                Text(atual.isCartao ? "Link expirado" : "Pix expirado")
                    .font(Theme.body(12, weight: .semibold))
                    .foregroundStyle(Theme.danger)
            } else if let expira = atual.expiresAt {
                Text(GwFormat.expiry(expira))
                    .font(Theme.body(12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            // Ninguém precisa ficar conferindo: quando o pagamento cai, a
            // cobrança se marca sozinha e o líquido entra no saldo.
            if atual.status != .expired {
                Text("Depois do pagamento, a confirmação chega em alguns segundos. Esta tela atualiza sozinha.")
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
                Text(codigoPix)
                    .font(Theme.money(11))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(3)
                    .truncationMode(.middle)
                HStack(spacing: 10) {
                    GwCopyButton(title: "Copiar código", value: codigoPix, icon: "qrcode")
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

    private var linkDePagamento: URL? {
        atual.invoiceUrl.flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil }
    }

    /// Cartão: o paciente paga na página segura do Asaas. Copiar, abrir e
    /// compartilhar — o mesmo que o Pix oferece, com o link no lugar do código.
    private var linkDoCartao: some View {
        ThemeCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "creditcard")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                        .frame(width: 34, height: 34)
                        .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("LINK DE PAGAMENTO")
                            .font(Theme.body(10, weight: .semibold))
                            .tracking(1.2)
                            .foregroundStyle(Theme.textSecondary)
                        Text("O paciente paga no cartão na página segura do \(provider?.name ?? GwProvider.asaasPadrao.name).")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let link = linkDePagamento {
                    Text(link.absoluteString)
                        .font(Theme.money(11))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    HStack(spacing: 10) {
                        GwCopyButton(title: "Copiar link", value: link.absoluteString, icon: "link")
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
                    Link(destination: link) {
                        Label("Abrir página de pagamento", systemImage: "safari")
                            .font(Theme.body(14, weight: .semibold))
                            .foregroundStyle(Theme.primary)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.top, 2)
                } else {
                    Text("O link ainda não chegou. Feche e abra a cobrança de novo em instantes.")
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textSecondary)
                }
                Text("No cartão, contestações do pagamento podem ser debitadas da sua conta.")
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
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
        if atual.isCartao {
            return """
            Oi\(primeiroNome)! Segue o link para pagar \(Formatters.brl(atual.amount))\(descricao) no cartão de crédito:

            \(linkDePagamento?.absoluteString ?? "")

            É só abrir e pagar com o cartão. Qualquer dúvida é só me chamar.
            """
        }
        return """
        Oi\(primeiroNome)! Segue o Pix de \(Formatters.brl(atual.amount))\(descricao):

        \(codigoPix)

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
                    label: atual.isCartao
                        ? "Tarifas do cartão \(provider?.name ?? GwProvider.asaasPadrao.name) (com antecipação)"
                        : "Tarifa Pix \(provider?.name ?? GwProvider.asaasPadrao.name)",
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
