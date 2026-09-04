import SwiftUI

/// Loja de créditos de lead. **Tudo simulado** — ver LeadsCreditsDemo em LeadsModels.swift.
struct LeadsCreditsView: View {
    // Saldo fictício: começa baixo de propósito, pra a tela mostrar o estado
    // de alerta, que é o mais importante de validar visualmente.
    @State private var balance = LeadBalance(
        credits: 2,
        receivedThisMonth: 9,
        convertedThisMonth: 4
    )
    @State private var selected: LeadPackage?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    balanceCard
                    monthStrip

                    Text("PACOTES")
                        .font(Theme.body(11, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, 4)
                        .padding(.leading, 2)

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(LeadCatalog.packages) { pacote in
                            packageCard(pacote)
                        }
                    }

                    footerNote
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .setToolbarTitle("Créditos")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected) { pacote in
            LeadsCheckoutSheet(package: pacote) { comprados in
                balance = LeadBalance(
                    credits: balance.credits + comprados,
                    receivedThisMonth: balance.receivedThisMonth,
                    convertedThisMonth: balance.convertedThisMonth
                )
            }
        }
    }

    // MARK: Saldo

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("SEU SALDO")
                    .font(Theme.body(10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: balance.isLow ? "arrow.down.right" : "checkmark")
                        .font(.system(size: 9, weight: .bold))
                    Text(balance.statusLabel.uppercased())
                        .font(Theme.body(10, weight: .bold))
                        .tracking(0.5)
                }
                .foregroundStyle(balance.isLow ? Theme.warning : Theme.success)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    (balance.isLow ? Theme.warningSoft : Theme.successSoft),
                    in: Capsule()
                )
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(balance.credits)")
                    .font(Theme.moneyDisplay(46))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                Text(balance.credits == 1 ? "crédito" : "créditos")
                    .font(Theme.body(16, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
            }

            Text(balance.isLow
                 ? "Seu saldo está baixo. Escolha um pacote abaixo pra continuar recebendo pacientes."
                 : "Cada crédito é um paciente novo chegando pra você.")
                .font(Theme.body(13))
                .foregroundStyle(Theme.textPrimary.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: balance.isLow
                    ? [Color(hex: 0xF7EEDC), Color(hex: 0xF3EDE4)]
                    : [Color(hex: 0xE7F0EA), Color(hex: 0xEDE9F4)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .animation(.easeInOut(duration: 0.25), value: balance.credits)
    }

    /// O que o saldo virou no mês — sem isso a tela é só uma vitrine.
    private var monthStrip: some View {
        HStack(spacing: 10) {
            miniTile(
                value: "\(balance.receivedThisMonth)",
                label: "Recebidos",
                caption: "no mês",
                color: Theme.textPrimary
            )
            miniTile(
                value: "\(balance.convertedThisMonth)",
                label: "Viraram paciente",
                caption: conversionCaption,
                color: Theme.success
            )
        }
    }

    private var conversionCaption: String {
        guard balance.receivedThisMonth > 0 else { return "—" }
        let taxa = Double(balance.convertedThisMonth) / Double(balance.receivedThisMonth) * 100
        return "\(Int(taxa.rounded()))% de conversão"
    }

    private func miniTile(
        value: String,
        label: String,
        caption: String,
        color: Color
    ) -> some View {
        ThemeCard(padding: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(value)
                    .font(Theme.moneyDisplay(24))
                    .monospacedDigit()
                    .foregroundStyle(color)
                Text(label)
                    .font(Theme.body(12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(caption)
                    .font(Theme.body(10, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Pacotes

    private func packageCard(_ pacote: LeadPackage) -> some View {
        Button {
            Haptics.tap()
            selected = pacote
        } label: {
            VStack(spacing: 0) {
                // Faixa reservada mesmo sem selo: sem ela os cards da linha
                // ficam com alturas diferentes e a grade desalinha.
                ZStack {
                    if pacote.highlighted {
                        Text("MAIS POPULAR")
                            .font(Theme.body(9, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Theme.primary, in: Capsule())
                    }
                }
                .frame(height: 22)

                Text(pacote.name)
                    .font(Theme.body(13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 6)

                Text("\(pacote.leads)")
                    .font(Theme.moneyDisplay(38))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.top, 2)

                Text("leads")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)

                Divider()
                    .overlay(Theme.border)
                    .padding(.vertical, 12)

                Text(Formatters.brlCompact(pacote.price))
                    .font(Theme.moneyDisplay(19))
                    .monospacedDigit()
                    .foregroundStyle(Theme.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text("\(Formatters.brl(pacote.pricePerLead)) por lead")
                    .font(Theme.body(10, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(14)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .stroke(
                        pacote.highlighted ? Theme.primary.opacity(0.55) : Theme.border,
                        lineWidth: pacote.highlighted ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.pressable)
    }

    private var footerNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.shield")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            Text("Os créditos entram na sua conta assim que o pagamento é confirmado.")
                .font(Theme.body(12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
        .padding(.horizontal, 2)
    }
}
