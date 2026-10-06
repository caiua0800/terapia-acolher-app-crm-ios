import SwiftUI

// MARK: - Cobrar no cartão uma cobrança que já existe (2026-10-06)
//
// A prévia vem do servidor (`card/quote`): com a cobrança criada, o número que
// aparece aqui é o mesmo que vai para o Asaas. Gerado o link, a folha do
// pagamento (a mesma do Pix) assume — com a atualização automática.

struct FinCardChargeSheet: View {
    let charge: FinCharge
    /// Devolve a cobrança no cartão já gerada, para quem abriu mostrar o link.
    var onCreated: (GwCharge) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var store = FinGatewayStore.shared
    @State private var repassar: Bool
    @State private var quote: GwCardQuote?
    @State private var carregandoQuote = false
    @State private var gerando = false
    @State private var errorMessage: String?

    init(charge: FinCharge, repassarPadrao: Bool, onCreated: @escaping (GwCharge) -> Void) {
        self.charge = charge
        self.onCreated = onCreated
        _repassar = State(initialValue: repassarPadrao)
    }

    private var provedor: String { store.overview?.provider.name ?? GwProvider.asaasPadrao.name }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        VStack(spacing: 6) {
                            Text(Formatters.brl(charge.amount))
                                .font(Theme.moneyDisplay(30))
                                .monospacedDigit()
                                .foregroundStyle(Theme.textPrimary)
                            Text(charge.description)
                                .font(Theme.body(14))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.top, 4)

                        ThemeCard {
                            VStack(alignment: .leading, spacing: 6) {
                                Toggle(isOn: $repassar) {
                                    Text("Repassar as taxas ao paciente")
                                        .font(Theme.body(15, weight: .semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                }
                                .tint(Theme.primary)
                                Text(repassar
                                     ? "O paciente paga um pouco mais e você recebe o valor cheio."
                                     : "O paciente paga o valor da cobrança e as taxas saem do que você recebe.")
                                    .font(Theme.body(12))
                                    .foregroundStyle(Theme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        resumo

                        PrimaryButton(
                            title: "Gerar link do cartão",
                            icon: "creditcard",
                            isLoading: gerando,
                            isEnabled: !carregandoQuote
                        ) {
                            Task { await gerar() }
                        }

                        GwProviderFooter(provider: store.overview?.provider ?? .asaasPadrao)
                    }
                    .padding(Theme.screenPadding)
                }
            }
            .navigationTitle("Cobrar no cartão")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
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
            // Refaz a prévia a cada troca do repasse.
            .task(id: repassar) { await carregarQuote() }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private var resumo: some View {
        if let q = quote {
            ThemeCard {
                VStack(alignment: .leading, spacing: 10) {
                    GwValueRow(label: "O paciente paga", value: Formatters.brl(q.chargedAmount))
                    if q.fees.platform > 0 {
                        GwValueRow(label: "Taxa Terapia Acolher", value: "− \(Formatters.brl(q.fees.platform))")
                    }
                    // Antecipação embutida na tarifa do Asaas (2026-10-06).
                    GwValueRow(label: "Tarifa do cartão \(provedor)", value: "− \(Formatters.brl(q.fees.provider + (q.fees.anticipation ?? 0)))")
                    Divider().overlay(Theme.border)
                    GwValueRow(
                        label: "Você recebe",
                        value: Formatters.brl(q.netAmount),
                        destaque: true,
                        valueColor: Theme.success
                    )
                    Text("No cartão, contestações do pagamento podem ser debitadas da sua conta.")
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .opacity(carregandoQuote ? 0.5 : 1)
            .animation(.easeOut(duration: 0.2), value: q)
        } else if carregandoQuote {
            ThemeCard {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            }
        }
    }

    private func carregarQuote() async {
        carregandoQuote = true
        defer { carregandoQuote = false }
        do {
            quote = try await FinGatewayAPI.cardQuote(chargeId: charge.id, passFees: repassar)
        } catch is CancellationError {
        } catch {
            // Sem prévia do servidor, cai na estimativa local (melhor que nada
            // para decidir; o valor exato aparece ao gerar).
            if let card = store.overview?.fees.card {
                quote = card.estimativa(valor: charge.amount, repassar: repassar)
            }
        }
    }

    private func gerar() async {
        gerando = true
        defer { gerando = false }
        do {
            let criada = try await FinGatewayAPI.createCard(chargeId: charge.id, passFees: repassar)
            Haptics.success()
            // Entrega antes de fechar: quem abriu mostra o link no onDismiss.
            onCreated(criada)
            dismiss()
        } catch is CancellationError {
        } catch {
            errorMessage = (error as? APIError)?.message ?? "Não foi possível gerar o link do cartão."
        }
    }
}

extension FinCharge {
    /// Cobrança online do Acolher Financeiro feita no cartão (e não no Pix).
    var ehNoCartao: Bool {
        intendedBillingType == "CARD" || intendedBillingType == "CREDIT_CARD"
    }
}
