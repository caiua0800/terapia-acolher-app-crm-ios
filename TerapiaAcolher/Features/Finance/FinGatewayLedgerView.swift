import SwiftUI

// MARK: - Extrato da conta (filtros, resumo, paginação e exportação)
//
// Os filtros viajam na query (`from`, `to`, `type`, `kind`, `search`,
// `minAmount`, `maxAmount`) e o resumo devolvido já respeita todos eles —
// somar na mão aqui daria número errado em lista paginada. Exportar usa a
// mesma query: o que está na tela é o que sai no CSV/PDF.

@MainActor
@Observable
final class FinGatewayLedgerModel {
    var items: [GwLedgerEntry] = []
    var total = 0
    var page = 1
    var summary: GwLedgerPage.Summary?
    var filter = GwLedgerFilter()
    var isLoading = false
    var isLoadingMore = false
    var exportando: GwExportFormat?
    var errorMessage: String?

    var temMais: Bool { items.count < total }

    func carregar() async {
        if items.isEmpty { isLoading = true }
        defer { isLoading = false }
        do {
            let pagina = try await FinGatewayAPI.ledger(page: 1, filter: filter)
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

    /// Filtro mudou: recarrega do zero mostrando a lista antiga esmaecida
    /// (skeleton só quando não há nada pra mostrar).
    func aplicarFiltro() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let pagina = try await FinGatewayAPI.ledger(page: 1, filter: filter)
            items = pagina.items
            total = pagina.total
            summary = pagina.summary
            page = 1
        } catch is CancellationError {
        } catch {
            errorMessage = (error as? APIError)?.message ?? "Não foi possível filtrar o extrato."
        }
    }

    func carregarMais() async {
        guard temMais, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let pagina = try await FinGatewayAPI.ledger(page: page + 1, filter: filter)
            items.append(contentsOf: pagina.items)
            total = pagina.total
            page += 1
        } catch is CancellationError {
        } catch {
            errorMessage = (error as? APIError)?.message ?? "Não foi possível carregar mais lançamentos."
        }
    }

    func exportar(_ formato: GwExportFormat) async -> GwArquivoBaixado? {
        exportando = formato
        defer { exportando = nil }
        do {
            let arquivo = try await FinGatewayAPI.exportLedger(format: formato, filter: filter)
            Haptics.success()
            return try GwArquivoBaixado(arquivo)
        } catch is CancellationError {
            return nil
        } catch {
            errorMessage = (error as? APIError)?.message ?? "Não foi possível exportar o extrato."
            Haptics.warning()
            return nil
        }
    }
}

struct FinGatewayLedgerView: View {
    @State private var model = FinGatewayLedgerModel()
    @State private var store = FinGatewayStore.shared
    @State private var filtrosAbertos = false
    @State private var arquivo: GwArquivoBaixado?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    barraDeFiltros
                    resumo
                    if let descricao = model.filter.descricao {
                        filtroAtivo(descricao)
                    }
                    if model.isLoading, model.items.isEmpty {
                        SkeletonList(linhas: 6, avatarSize: 38).padding(.top, 6)
                    } else if model.items.isEmpty {
                        EmptyStateView(
                            icon: "list.bullet.rectangle",
                            title: model.filter.isEmpty ? "Sem movimentações" : "Nada com esses filtros",
                            message: model.filter.isEmpty
                                ? "Cada cobrança recebida, taxa e saque aparece aqui."
                                : "Tente outro período ou limpe os filtros.",
                            actionTitle: model.filter.isEmpty ? nil : "Limpar filtros",
                            action: model.filter.isEmpty ? nil : { limpar() }
                        )
                    } else {
                        lista
                            .opacity(model.isLoading ? 0.55 : 1)
                            .animation(.easeInOut(duration: 0.18), value: model.isLoading)
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                menuExportar
            }
        }
        .task { await model.carregar() }
        .sheet(isPresented: $filtrosAbertos) {
            FinGatewayLedgerFilterSheet(filtro: model.filter) { novo in
                model.filter = novo
                Task { await model.aplicarFiltro() }
            }
        }
        .sheet(item: $arquivo) { baixado in
            GwShareSheet(url: baixado.url)
                .presentationDetents([.medium, .large])
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

    private func limpar() {
        model.filter = GwLedgerFilter()
        Task { await model.aplicarFiltro() }
    }

    // MARK: Exportar

    private var menuExportar: some View {
        Menu {
            ForEach(GwExportFormat.allCases) { formato in
                Button {
                    Haptics.tap()
                    Task { arquivo = await model.exportar(formato) }
                } label: {
                    Label(formato.label, systemImage: formato.icon)
                }
            }
        } label: {
            ZStack {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .opacity(model.exportando == nil ? 1 : 0)
                if model.exportando != nil {
                    ProgressView().controlSize(.small).tint(Theme.primary)
                }
            }
            .foregroundStyle(Theme.primary)
            .frame(minWidth: 28, minHeight: 28)
        }
        .disabled(model.exportando != nil || model.items.isEmpty)
        .accessibilityLabel("Exportar extrato")
        .accessibilityIdentifier("gwExportar")
    }

    // MARK: Filtros rápidos

    private var barraDeFiltros: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(GwLedgerFilter.Periodo.allCases.filter { $0 != .personalizado }) { periodo in
                        FilterChip(label: periodo.label, isSelected: model.filter.periodo == periodo) {
                            model.filter.periodo = periodo
                            Task { await model.aplicarFiltro() }
                        }
                    }
                    if model.filter.periodo == .personalizado, let descricao = model.filter.descricao {
                        FilterChip(label: descricao.components(separatedBy: " · ").first ?? "Período", isSelected: true) {
                            filtrosAbertos = true
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            HStack(spacing: 8) {
                ForEach([nil, GwLedgerType.credit, GwLedgerType.debit], id: \.self) { tipo in
                    FilterChip(
                        label: tipo == nil ? "Tudo" : (tipo == .credit ? "Entradas" : "Saídas"),
                        isSelected: model.filter.type == tipo
                    ) {
                        model.filter.type = tipo
                        Task { await model.aplicarFiltro() }
                    }
                }
                Spacer(minLength: 0)
                Button {
                    Haptics.tap()
                    filtrosAbertos = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Filtros")
                            .font(Theme.body(14, weight: .semibold))
                        if model.filter.count > 0 {
                            Text("\(model.filter.count)")
                                .font(Theme.body(11, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.primary, in: Capsule())
                        }
                    }
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.surface, in: Capsule())
                    .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
                }
                .buttonStyle(.pressable)
                .accessibilityIdentifier("gwFiltros")
            }
        }
    }

    private func filtroAtivo(_ descricao: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 11, weight: .semibold))
            Text(descricao)
                .font(Theme.body(12, weight: .medium))
                .lineLimit(2)
            Spacer(minLength: 4)
            Button {
                Haptics.tap()
                limpar()
            } label: {
                Text("Limpar")
                    .font(Theme.body(12, weight: .semibold))
                    .foregroundStyle(Theme.primary)
            }
            .buttonStyle(.pressable)
        }
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
    }

    // MARK: Resumo

    private var resumo: some View {
        ThemeCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SALDO ATUAL")
                            .font(Theme.body(10, weight: .semibold))
                            .tracking(1.2)
                            .foregroundStyle(Theme.textSecondary)
                        Text(Formatters.brl(store.balance))
                            .font(Theme.moneyDisplay(28))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                    }
                    Spacer(minLength: 8)
                    if let summary = model.summary, let count = summary.count {
                        Text("\(count) lançamento\(count == 1 ? "" : "s")")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                if let summary = model.summary {
                    Divider().overlay(Theme.border)
                    GwValueRow(label: "Entradas", value: Formatters.brl(summary.credits), valueColor: Theme.success)
                    GwValueRow(label: "Saídas", value: "− \(Formatters.brl(summary.debits))", valueColor: Theme.danger)
                    GwValueRow(
                        label: model.filter.isEmpty ? "Resultado" : "Resultado do período",
                        value: (summary.liquido < 0 ? "− " : "") + Formatters.brl(abs(summary.liquido)),
                        destaque: true,
                        valueColor: summary.liquido >= 0 ? Theme.success : Theme.danger
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Lista

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

// MARK: - Sheet de filtros (período livre, categorias, busca, faixa de valor)

struct FinGatewayLedgerFilterSheet: View {
    @State private var filtro: GwLedgerFilter
    let aoAplicar: (GwLedgerFilter) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var minTexto: String
    @State private var maxTexto: String

    init(filtro: GwLedgerFilter, aoAplicar: @escaping (GwLedgerFilter) -> Void) {
        _filtro = State(initialValue: filtro)
        self.aoAplicar = aoAplicar
        _minTexto = State(initialValue: filtro.minAmount.map { GwFormat.amountText($0) } ?? "")
        _maxTexto = State(initialValue: filtro.maxAmount.map { GwFormat.amountText($0) } ?? "")
    }

    private var de: Binding<Date> {
        Binding(
            get: { filtro.de ?? Calendar.current.date(byAdding: .month, value: -1, to: Date())! },
            set: { filtro.de = Calendar.current.startOfDay(for: $0); filtro.periodo = .personalizado }
        )
    }

    private var ate: Binding<Date> {
        Binding(
            get: { filtro.ate ?? Date() },
            set: { filtro.ate = Calendar.current.startOfDay(for: $0); filtro.periodo = .personalizado }
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        secaoPeriodo
                        secaoTipo
                        secaoCategorias
                        secaoBusca
                        secaoValor
                    }
                    .padding(Theme.screenPadding)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Filtrar extrato")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Limpar") {
                        Haptics.tap()
                        filtro = GwLedgerFilter()
                        minTexto = ""
                        maxTexto = ""
                    }
                    .foregroundStyle(Theme.textSecondary)
                    .disabled(filtro.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Aplicar") {
                        Haptics.tap()
                        var final = filtro
                        final.minAmount = GwMask.amount(minTexto)
                        final.maxAmount = GwMask.amount(maxTexto)
                        if final.periodo == .personalizado, final.de == nil, final.ate == nil {
                            final.periodo = .tudo
                        }
                        aoAplicar(final)
                        dismiss()
                    }
                    .font(Theme.body(16, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .accessibilityIdentifier("gwAplicarFiltros")
                }
            }
        }
        .presentationDetents([.large])
    }

    private var secaoPeriodo: some View {
        PatientFormSection(icon: "calendar", title: "PERÍODO") {
            VStack(alignment: .leading, spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(GwLedgerFilter.Periodo.allCases) { periodo in
                            FilterChip(label: periodo.label, isSelected: filtro.periodo == periodo) {
                                filtro.periodo = periodo
                                if periodo == .personalizado, filtro.de == nil {
                                    filtro.de = Calendar.current.date(byAdding: .month, value: -1, to: Calendar.current.startOfDay(for: Date()))
                                    filtro.ate = Calendar.current.startOfDay(for: Date())
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                if filtro.periodo == .personalizado {
                    DatePicker("De", selection: de, in: ...Date(), displayedComponents: .date)
                        .font(Theme.body(14))
                        .tint(Theme.primary)
                    DatePicker("Até", selection: ate, in: (filtro.de ?? .distantPast)...Date(), displayedComponents: .date)
                        .font(Theme.body(14))
                        .tint(Theme.primary)
                }
            }
        }
    }

    private var secaoTipo: some View {
        PatientFormSection(icon: "arrow.up.arrow.down", title: "TIPO") {
            HStack(spacing: 8) {
                ForEach([nil, GwLedgerType.credit, GwLedgerType.debit], id: \.self) { tipo in
                    FilterChip(
                        label: tipo == nil ? "Tudo" : (tipo == .credit ? "Entradas" : "Saídas"),
                        isSelected: filtro.type == tipo
                    ) {
                        filtro.type = tipo
                    }
                }
            }
        }
    }

    private var secaoCategorias: some View {
        PatientFormSection(icon: "tag", title: "CATEGORIAS") {
            VStack(alignment: .leading, spacing: 8) {
                Text(filtro.kinds.isEmpty ? "Todas as categorias." : "\(filtro.kinds.count) selecionada\(filtro.kinds.count == 1 ? "" : "s").")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(GwLedgerKind.filterable, id: \.self) { kind in
                        Button {
                            Haptics.tap()
                            if filtro.kinds.contains(kind) { filtro.kinds.remove(kind) } else { filtro.kinds.insert(kind) }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: filtro.kinds.contains(kind) ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 16))
                                    .foregroundStyle(filtro.kinds.contains(kind) ? Theme.primary : Theme.border)
                                Text(kind.label)
                                    .font(Theme.body(13, weight: .medium))
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                Spacer(minLength: 0)
                            }
                            .padding(10)
                            .background(Theme.background, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
                        }
                        .buttonStyle(.pressableSubtle)
                    }
                }
            }
        }
    }

    private var secaoBusca: some View {
        PatientFormSection(icon: "magnifyingglass", title: "BUSCA") {
            GwField(label: "Descrição", hint: "Nome do paciente ou texto do lançamento.") {
                TextField("Ex.: Ana Lima", text: $filtro.search)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("gwBuscaExtrato")
            }
        }
    }

    private var secaoValor: some View {
        PatientFormSection(icon: "dollarsign.circle", title: "VALOR") {
            HStack(spacing: 12) {
                GwField(label: "De") {
                    TextField("0,00", text: $minTexto)
                        .keyboardType(.decimalPad)
                        .font(Theme.money(15, weight: .semibold))
                }
                GwField(label: "Até") {
                    TextField("0,00", text: $maxTexto)
                        .keyboardType(.decimalPad)
                        .font(Theme.money(15, weight: .semibold))
                }
            }
        }
    }
}
