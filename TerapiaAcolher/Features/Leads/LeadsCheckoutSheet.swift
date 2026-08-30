import SwiftUI

/// Escolha de meio de pagamento + confirmação. **Simulação** — nenhum centavo
/// é cobrado e nenhuma requisição sai do app (ver LeadsModels.swift).
struct LeadsCheckoutSheet: View {
    let package: LeadPackage
    /// Devolve quantos créditos entraram, pra tela de trás atualizar o saldo.
    var onPurchased: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var method: LeadPaymentMethod = .pix
    @State private var installments = 1
    @State private var stage: Stage = .choosing

    private enum Stage { case choosing, processing, done }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                switch stage {
                case .choosing: chooser
                case .processing: processing
                case .done: success
                }
            }
            .navigationTitle(stage == .done ? "Tudo certo" : "Pagamento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if stage == .choosing {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancelar") { dismiss() }
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .interactiveDismissDisabled(stage == .processing)
        }
    }

    // MARK: Escolha

    private var chooser: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    resumo

                    Text("COMO QUER PAGAR")
                        .font(Theme.body(11, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.leading, 2)

                    VStack(spacing: 10) {
                        ForEach(LeadPaymentMethod.allCases) { opcao in
                            methodRow(opcao)
                        }
                    }

                    if method == .card {
                        installmentPicker
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .animation(.easeInOut(duration: 0.2), value: method)

            payBar
        }
    }

    private var resumo: some View {
        ThemeCard(padding: 18) {
            VStack(spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(package.name)
                            .font(Theme.serifTitle(19))
                            .foregroundStyle(Theme.textPrimary)
                        Text("\(package.leads) leads · \(Formatters.brl(package.pricePerLead)) cada")
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 8)
                    Text(Formatters.brlCompact(package.price))
                        .font(Theme.moneyDisplay(24))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .fixedSize()
                }

                Divider().overlay(Theme.border)

                HStack(spacing: 8) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.primary)
                    Text("Seu saldo sobe para \(package.leads) créditos")
                        .font(Theme.body(13, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                }
            }
        }
    }

    private func methodRow(_ opcao: LeadPaymentMethod) -> some View {
        let isSelected = method == opcao
        return Button {
            Haptics.tap()
            method = opcao
        } label: {
            HStack(spacing: 13) {
                Image(systemName: opcao.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isSelected ? Theme.primary : Theme.textSecondary)
                    .frame(width: 40, height: 40)
                    .background(
                        isSelected ? Theme.primarySoft : Theme.background,
                        in: RoundedRectangle(cornerRadius: 11)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(opcao.title)
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(opcao.subtitle)
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer(minLength: 6)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19))
                    .foregroundStyle(isSelected ? Theme.primary : Theme.border)
            }
            .padding(14)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .stroke(isSelected ? Theme.primary : Theme.border,
                            lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableSubtle)
    }

    private var installmentPicker: some View {
        ThemeCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("PARCELAS")
                    .font(Theme.body(10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.textSecondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach([1, 2, 3, 6, 12], id: \.self) { n in
                            FilterChip(
                                label: n == 1 ? "À vista" : "\(n)x",
                                isSelected: installments == n
                            ) {
                                Haptics.tap()
                                installments = n
                            }
                        }
                    }
                }

                if installments > 1 {
                    Text("\(installments)x de \(Formatters.brl(package.price / Double(installments)))")
                        .font(Theme.body(13, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
        }
    }

    private var payBar: some View {
        VStack(spacing: 0) {
            Divider().overlay(Theme.border)
            VStack(spacing: 10) {
                HStack {
                    Text("Total")
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(Formatters.brlCompact(package.price))
                        .font(Theme.moneyDisplay(21))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                }
                PrimaryButton(
                    title: method == .pix ? "Gerar Pix" : "Pagar com cartão",
                    icon: method == .pix ? "qrcode" : "creditcard"
                ) {
                    Task { await pagar() }
                }
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, 14)
            .padding(.bottom, 8)
            .background(Theme.surface)
        }
    }

    // MARK: Processando / sucesso

    private var processing: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .tint(Theme.primary)
            Text(method == .pix ? "Gerando seu Pix…" : "Autorizando pagamento…")
                .font(Theme.body(15, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var success: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Theme.success)
                .frame(width: 84, height: 84)
                .background(Theme.successSoft, in: Circle())

            VStack(spacing: 6) {
                Text("Pagamento confirmado")
                    .font(Theme.serifTitle(22))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(package.leads) créditos entraram na sua conta.")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            PrimaryButton(title: "Voltar aos créditos") {
                onPurchased(package.leads)
                dismiss()
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, 12)
        }
        .transition(.opacity)
    }

    @MainActor
    private func pagar() async {
        Haptics.tap()
        withAnimation { stage = .processing }
        // Espera artificial só pra a transição parecer real na demonstração.
        try? await Task.sleep(for: .seconds(1.6))
        Haptics.success()
        withAnimation { stage = .done }
    }
}
