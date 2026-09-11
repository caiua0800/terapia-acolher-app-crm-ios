import SwiftUI

// MARK: - Extrato da conta (paginado)

@MainActor
@Observable
final class FinGatewayLedgerModel {
    var items: [GwLedgerEntry] = []
    var total = 0
    var page = 1
    var summary: GwLedgerPage.Summary?
    var isLoading = false
    var isLoadingMore = false
    var errorMessage: String?

    var temMais: Bool { items.count < total }

    func carregar() async {
        if items.isEmpty { isLoading = true }
        defer { isLoading = false }
        do {
            let pagina = try await FinGatewayAPI.ledger(page: 1)
            items = pagina.items
            total = pagina.total
            summary = pagina.summary
            page = 1
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
        } catch {
            errorMessage = (error as? APIError)?.message ?? "Não foi possível carregar o extrato."
        }
    }

    func carregarMais() async {
        guard temMais, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let pagina = try await FinGatewayAPI.ledger(page: page + 1)
            items.append(contentsOf: pagina.items)
            total = pagina.total
            page += 1
        } catch is CancellationError {
        } catch {
            errorMessage = (error as? APIError)?.message ?? "Não foi possível carregar mais lançamentos."
        }
    }
}

struct FinGatewayLedgerView: View {
    @State private var model = FinGatewayLedgerModel()
    @State private var store = FinGatewayStore.shared

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    resumo
                    if model.isLoading, model.items.isEmpty {
                        SkeletonList(linhas: 6, avatarSize: 38).padding(.top, 6)
                    } else if model.items.isEmpty {
                        EmptyStateView(
                            icon: "list.bullet.rectangle",
                            title: "Sem movimentações",
                            message: "Cada cobrança recebida, taxa e saque aparece aqui."
                        )
                    } else {
                        lista
                        if model.temMais {
                            SecondaryButton(
                                title: "Carregar mais",
                                icon: "arrow.down",
                                isLoading: model.isLoadingMore
                            ) {
                                Task { await model.carregarMais() }
                            }
                        }
                    }
                    if let provider = store.overview?.provider {
                        GwProviderFooter(provider: provider)
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
            .refreshable { await model.carregar() }
        }
        .setToolbarTitle("Extrato")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.carregar() }
        .alert("Ops", isPresented: .init(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var resumo: some View {
        ThemeCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("SALDO ATUAL")
                    .font(Theme.body(10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.textSecondary)
                Text(Formatters.brl(store.balance))
                    .font(Theme.moneyDisplay(28))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                if let summary = model.summary {
                    Divider().overlay(Theme.border)
                    GwValueRow(
                        label: "Entradas",
                        value: Formatters.brl(summary.credits),
                        valueColor: Theme.success
                    )
                    GwValueRow(
                        label: "Saídas",
                        value: "− \(Formatters.brl(summary.debits))",
                        valueColor: Theme.danger
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var lista: some View {
        LazyVStack(spacing: 0) {
            ForEach(model.items) { entrada in
                linha(entrada)
                if entrada.id != model.items.last?.id {
                    Divider().overlay(Theme.border)
                }
            }
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    private func linha(_ entrada: GwLedgerEntry) -> some View {
        let credito = entrada.type == .credit
        return HStack(spacing: 12) {
            Circle()
                .fill(credito ? Theme.successSoft : Theme.dangerSoft)
                .frame(width: 38, height: 38)
                .overlay(
                    Image(systemName: entrada.kind.icon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(credito ? Theme.success : Theme.danger)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(entrada.description)
                    .font(Theme.body(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                Text("\(entrada.kind.label) · \(GwFormat.shortDayTime.string(from: entrada.createdAt))")
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(credito ? "+" : "−") \(Formatters.brl(entrada.amount))")
                    .font(Theme.money(14, weight: .semibold))
                    .foregroundStyle(credito ? Theme.success : Theme.danger)
                    .lineLimit(1)
                Text("Saldo \(Formatters.brl(entrada.balanceAfter))")
                    .font(Theme.body(10))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
