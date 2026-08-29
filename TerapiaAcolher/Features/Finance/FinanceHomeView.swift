import SwiftUI

// MARK: - ViewModel

@MainActor
@Observable
final class FinHomeViewModel {
    enum Tab: Hashable { case registros, balanco }
    enum Filter: CaseIterable, Hashable {
        case all, income, expense, recurring

        var label: String {
            switch self {
            case .all: "Tudo"
            case .income: "Entradas"
            case .expense: "Saídas"
            case .recurring: "Recorrente"
            }
        }
    }

    var monthDate = Date()
    var tab: Tab = .balanco
    var filter: Filter = .all
    var transactions: [FinTransaction] = []
    var balance: FinBalance?
    var isLoading = false
    var errorMessage: String?
    var expandedId: String?
    var deletingId: String? // transação com exclusão em voo (spinner na linha)

    var monthQuery: String { FinFormat.monthQuery.string(from: monthDate) }
    var monthTitle: String { FinFormat.monthTitleText(monthDate) }

    func changeMonth(_ delta: Int) {
        if let next = Calendar.current.date(byAdding: .month, value: delta, to: monthDate) {
            monthDate = next
            Task { await load() }
        }
    }

    func setFilter(_ newFilter: Filter) {
        filter = newFilter
        Task { await load() }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        expandedId = nil
        do {
            let month = monthQuery
            let type: FinTransactionType? = switch filter {
            case .income: .income
            case .expense: .expense
            default: nil
            }
            let recurring: Bool? = filter == .recurring ? true : nil
            async let balanceTask = FinanceAPI.balance(month: month)
            async let listTask = FinanceAPI.transactions(month: month, type: type, recurring: recurring)
            balance = try await balanceTask
            transactions = try await listTask
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
        } catch {
            errorMessage = (error as? APIError)?.message ?? "Não foi possível carregar o financeiro."
        }
    }

    func delete(_ transaction: FinTransaction) async {
        deletingId = transaction.id
        defer { deletingId = nil }
        do {
            _ = try await FinanceAPI.deleteTransaction(id: transaction.id)
            await load()
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
        } catch {
            errorMessage = (error as? APIError)?.message ?? "Não foi possível excluir a transação."
        }
    }
}

// MARK: - Tela principal do Financeiro (substitui a placeholder)

struct FinanceHomeView: View {
    @State private var model = FinHomeViewModel()
    @State private var showTransactionForm = false
    @State private var editingTransaction: FinTransaction?
    @State private var deletingTransaction: FinTransaction?
    @State private var hasAppeared = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    monthNavigator
                    quickLinks
                    FinSegmentedControl(
                        options: [("Balanço", FinHomeViewModel.Tab.balanco), ("Registros", .registros)],
                        selection: $model.tab
                    )

                    switch model.tab {
                    case .registros: registrosTab
                    case .balanco: balancoTab
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.bottom, 90)
            }
            .refreshable { await model.load() }

            FloatingActionButton {
                showTransactionForm = true
            }
            .padding(.trailing, Theme.screenPadding)
            .padding(.bottom, 24)
        }
        .task { await model.load() }
        // .task não roda de novo ao voltar de uma tela empurrada (a view não
        // sai da hierarquia) — o onAppear recarrega nesses retornos. Na
        // primeira aparição só o .task carrega (hasAppeared ainda é false).
        .onAppear {
            if hasAppeared {
                Task { await model.load() }
            }
            hasAppeared = true
        }
        .sheet(isPresented: $showTransactionForm) {
            FinTransactionFormView(existing: nil) {
                Task { await model.load() }
            }
        }
        // sheet(item:) garante que o form é criado já com a transação em mãos —
        // com isPresented: o SwiftUI pode montar a view antes do estado propagar
        // e o @State inicial fica vazio.
        .sheet(item: $editingTransaction) { transaction in
            FinTransactionFormView(existing: transaction) {
                Task { await model.load() }
            }
        }
        .alert("Excluir transação?", isPresented: .init(
            get: { deletingTransaction != nil },
            set: { if !$0 { deletingTransaction = nil } }
        )) {
            Button("Excluir", role: .destructive) {
                if let transaction = deletingTransaction {
                    Task { await model.delete(transaction) }
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Essa ação não pode ser desfeita.")
        }
        .alert("Ops", isPresented: .init(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    // MARK: Navegação de mês  ‹ Julho de 2026 ›

    private var monthNavigator: some View {
        HStack {
            monthArrow("chevron.left") { model.changeMonth(-1) }
            Spacer()
            Text(model.monthTitle)
                .font(Theme.serifTitle(19).italic())
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            monthArrow("chevron.right") { model.changeMonth(1) }
        }
        .padding(.top, 10)
    }

    private func monthArrow(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 34, height: 34)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().stroke(Theme.border, lineWidth: 1))
        }
    }

    // MARK: Atalhos: Cobranças por paciente e Carteira Asaas

    private var quickLinks: some View {
        HStack(spacing: 10) {
            NavigationLink {
                FinChargesEntryView()
            } label: {
                quickLinkLabel(icon: "creditcard", title: "Cobranças")
            }
            NavigationLink {
                FinWalletView()
            } label: {
                quickLinkLabel(icon: "wallet.pass", title: "Carteira Asaas")
            }
        }
    }

    private func quickLinkLabel(icon: String, title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.primary)
            Text(title)
                .font(Theme.body(14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
    }

    // MARK: Aba Registros

    private var registrosTab: some View {
        VStack(spacing: 14) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FinHomeViewModel.Filter.allCases, id: \.self) { filter in
                        FilterChip(label: filter.label, isSelected: model.filter == filter) {
                            model.setFilter(filter)
                        }
                    }
                }
            }

            if model.isLoading, model.transactions.isEmpty {
                ProgressView().padding(.top, 40)
            } else if model.transactions.isEmpty {
                EmptyStateView(
                    icon: "banknote",
                    title: "Nenhum registro",
                    message: "As entradas e saídas de \(model.monthTitle.lowercased()) aparecem aqui."
                )
            } else {
                transactionList(model.transactions)
            }
        }
    }

    // MARK: Aba Balanço

    private var balancoTab: some View {
        VStack(spacing: 18) {
            balanceCard

            HStack {
                Text("Últimas movimentações")
                    .font(Theme.serifTitle(18))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button("Ver todas") {
                    withAnimation { model.tab = .registros }
                }
                .font(Theme.body(13, weight: .semibold))
                .foregroundStyle(Theme.primary)
            }

            if model.isLoading, model.transactions.isEmpty {
                ProgressView().padding(.top, 20)
            } else if model.transactions.isEmpty {
                EmptyStateView(
                    icon: "banknote",
                    title: "Nada por aqui",
                    message: "Nenhuma movimentação em \(model.monthTitle.lowercased())."
                )
            } else {
                transactionList(Array(model.transactions.prefix(8)))
            }
        }
    }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SALDO DO MÊS")
                .font(Theme.body(11, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.55))
            Text(Formatters.brl(model.balance?.balance ?? 0))
                .font(Theme.money(34, weight: .bold))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            HStack(spacing: 10) {
                balanceSubCard(
                    label: "ENTRADAS",
                    value: model.balance?.incomes ?? 0,
                    color: Color(hex: 0x8FD6AC)
                )
                balanceSubCard(
                    label: "SAÍDAS",
                    value: model.balance?.expenses ?? 0,
                    color: Color(hex: 0xF0928D)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Theme.ink, in: RoundedRectangle(cornerRadius: 20))
    }

    private func balanceSubCard(label: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(Theme.body(10, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.5))
            Text(Formatters.brl(value))
                .font(Theme.money(16, weight: .semibold))
                .foregroundStyle(color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Lista de transações

    private func transactionList(_ items: [FinTransaction]) -> some View {
        VStack(spacing: 0) {
            ForEach(items) { transaction in
                FinTransactionCell(
                    transaction: transaction,
                    expandedId: $model.expandedId,
                    isDeleting: model.deletingId == transaction.id,
                    onEdit: { editingTransaction = $0 },
                    onDelete: { deletingTransaction = $0 }
                )
                if transaction.id != items.last?.id {
                    Divider().overlay(Theme.border)
                }
            }
        }
    }
}
