import Observation
import SwiftUI

// MARK: - Todas as cobranças (2026-10-06)
//
// A tela de cobranças do Acolher Financeiro mostra TODAS as cobranças —
// pacientes e avulsas juntas — com filtros, totais e rolagem infinita. Antes
// ela pedia primeiro para escolher um paciente, e não havia onde ver tudo o
// que foi cobrado. "Nova cobrança" abre o formulário com a escolha Paciente |
// Outra pessoa.

@MainActor
@Observable
final class FinAllChargesModel {
    var filtro = FinChargesPageFilter()
    var itens: [FinCharge] = []
    var total = 0
    var totais: FinChargesPage.Totais?
    var carregando = false
    var carregandoMais = false
    var erro: String?
    private var pagina = 0
    private var geracao = 0
    private let porPagina = 20

    var temMais: Bool { itens.count < total }

    /// Recomeça do zero (filtro mudou, puxou para atualizar, voltou do detalhe).
    func recarregar() async {
        geracao += 1
        let minha = geracao
        carregando = itens.isEmpty
        erro = nil
        defer { if minha == geracao { carregando = false } }
        do {
            let r = try await FinanceAPI.chargesPage(filtro, page: 1, perPage: porPagina)
            guard minha == geracao else { return }
            itens = r.itens
            total = r.total
            totais = r.totais
            pagina = 1
        } catch is CancellationError {
        } catch {
            guard minha == geracao else { return }
            erro = (error as? APIError)?.message ?? "Não foi possível carregar as cobranças."
        }
    }

    /// Próxima página quando a lista chega ao fim.
    func carregarMais() async {
        guard temMais, !carregandoMais, !carregando else { return }
        let minha = geracao
        carregandoMais = true
        defer { carregandoMais = false }
        do {
            let r = try await FinanceAPI.chargesPage(filtro, page: pagina + 1, perPage: porPagina)
            guard minha == geracao else { return }
            let vistos = Set(itens.map(\.id))
            itens += r.itens.filter { !vistos.contains($0.id) }
            total = r.total
            pagina += 1
        } catch {
            // Falha ao paginar não apaga o que já está na tela; a próxima
            // rolagem tenta de novo.
        }
    }

    func quantidade(_ status: FinChargeStatus?) -> Int? {
        guard let q = totais?.quantidade else { return nil }
        if let status { return q[status.rawValue] ?? 0 }
        return q.values.reduce(0, +)
    }
}

struct FinChargesEntryView: View {
    @State private var model = FinAllChargesModel()
    @State private var store = FinGatewayStore.shared
    @State private var novaCobranca = false
    @State private var buscaDigitada = ""
    @State private var mostrandoFiltros = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                LazyVStack(spacing: 14) {
                    totaisCard
                    chipsDeStatus
                    barraDeFiltros
                    conteudo
                    GwProviderFooter(provider: store.overview?.provider ?? .asaasPadrao)
                        .padding(.top, 8)
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .refreshable { await model.recarregar() }
        }
        .navigationTitle("Cobranças")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $buscaDigitada, prompt: "Buscar paciente, pagador ou descrição")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.tap()
                    novaCobranca = true
                } label: {
                    Label("Nova cobrança", systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                        .font(Theme.body(14, weight: .semibold))
                        .foregroundStyle(store.isApproved ? Theme.primary : Theme.textSecondary.opacity(0.4))
                }
                .disabled(!store.isApproved)
                .accessibilityIdentifier("cobrancasNova")
            }
        }
        .task {
            await model.recarregar()
            await store.load(showSpinner: false)
        }
        // Busca com espera: só consulta quando a pessoa para de digitar.
        .task(id: buscaDigitada) {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, buscaDigitada != model.filtro.busca else { return }
            model.filtro.busca = buscaDigitada
        }
        .onChange(of: model.filtro) { _, _ in
            Task { await model.recarregar() }
        }
        .sheet(isPresented: $novaCobranca) {
            FinChargeFormView(patient: nil) {
                Task { await model.recarregar() }
            }
        }
        .sheet(isPresented: $mostrandoFiltros) {
            FinChargesFiltrosSheet(filtro: $model.filtro)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: Totais dos filtros atuais

    private var totaisCard: some View {
        ThemeCard {
            HStack(alignment: .top, spacing: 10) {
                numero("A RECEBER", model.totais?.aReceber, Theme.warning)
                numero("RECEBIDO", model.totais?.recebido, Theme.success)
                numero("EM ATRASO", model.totais?.atrasado, Theme.danger)
            }
        }
    }

    private func numero(_ rotulo: String, _ valor: Double?, _ cor: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(rotulo)
                .font(Theme.body(10, weight: .semibold))
                .tracking(1)
                .foregroundStyle(Theme.textSecondary)
            Text(valor.map(Formatters.brl) ?? "—")
                .font(Theme.moneyDisplay(16, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(cor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Filtros

    private var chipsDeStatus: some View {
        let opcoes: [(String, FinChargeStatus?)] = [
            ("Todas", nil), ("Em aberto", .pending), ("Atrasadas", .overdue),
            ("Pagas", .paid), ("Canceladas", .canceled),
        ]
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(opcoes, id: \.0) { rotulo, status in
                    let n = model.quantidade(status)
                    FilterChip(
                        label: n.map { "\(rotulo) · \($0)" } ?? rotulo,
                        isSelected: model.filtro.status == status
                    ) {
                        Haptics.tap()
                        model.filtro.status = status
                    }
                }
            }
        }
    }

    private var barraDeFiltros: some View {
        HStack(spacing: 8) {
            Picker("Quem", selection: $model.filtro.kind) {
                Text("Todas").tag(String?.none)
                Text("Pacientes").tag(String?.some("PATIENT"))
                Text("Avulsas").tag(String?.some("STANDALONE"))
            }
            .pickerStyle(.segmented)

            Button {
                Haptics.tap()
                mostrandoFiltros = true
            } label: {
                Image(systemName: maisFiltrosAtivos ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(maisFiltrosAtivos ? Theme.primary : Theme.textSecondary)
            }
            .accessibilityLabel("Mais filtros")
        }
    }

    private var maisFiltrosAtivos: Bool {
        model.filtro.metodo != nil || model.filtro.periodo != .todos || model.filtro.ordem != .vencimentoDesc
    }

    // MARK: Lista

    @ViewBuilder
    private var conteudo: some View {
        if model.carregando {
            VStack(spacing: 10) {
                ForEach(0..<5, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Theme.border.opacity(0.45))
                        .frame(height: 64)
                }
            }
            .redacted(reason: .placeholder)
        } else if let erro = model.erro {
            EmptyStateView(
                icon: "exclamationmark.triangle",
                title: "Não carregou",
                message: erro,
                actionTitle: "Tentar de novo"
            ) { Task { await model.recarregar() } }
        } else if model.itens.isEmpty {
            EmptyStateView(
                icon: "creditcard",
                title: model.filtro.temFiltro ? "Nenhuma cobrança com esses filtros" : "Nenhuma cobrança ainda",
                message: model.filtro.temFiltro
                    ? "Mude ou limpe os filtros para ver mais."
                    : "Crie a primeira em Nova cobrança.",
                actionTitle: model.filtro.temFiltro ? "Limpar filtros" : nil
            ) {
                buscaDigitada = ""
                model.filtro = FinChargesPageFilter()
            }
        } else {
            ThemeCard(padding: 0) {
                LazyVStack(spacing: 0) {
                    ForEach(model.itens) { charge in
                        NavigationLink {
                            FinChargeDetailView(charge: charge) {
                                Task { await model.recarregar() }
                            }
                        } label: {
                            FinAllChargesRow(charge: charge)
                                .padding(.horizontal, Theme.cardPadding)
                        }
                        .buttonStyle(.pressableSubtle)
                        .onAppear {
                            if charge.id == model.itens.last?.id {
                                Task { await model.carregarMais() }
                            }
                        }
                        if charge.id != model.itens.last?.id {
                            Divider().overlay(Theme.border).padding(.leading, 64)
                        }
                    }
                }
            }
            if model.carregandoMais {
                ProgressView().padding(.vertical, 8)
            } else if !model.temMais, model.total > 0 {
                Text("\(model.total) cobrança\(model.total == 1 ? "" : "s")")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

// MARK: - Linha

struct FinAllChargesRow: View {
    let charge: FinCharge

    var body: some View {
        HStack(spacing: 12) {
            metodo
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(charge.nomeDoPagador ?? "Sem nome")
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if charge.ehAvulsa {
                        StatusBadge(label: "AVULSA", color: Theme.textSecondary, background: Theme.border.opacity(0.5))
                    }
                }
                Text(charge.description)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    status
                    Text("Vence \(FinFormat.dayMonthUTC.string(from: charge.dueDate))")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                    if let quando = charge.reminderScheduledAt, quando > Date(),
                       charge.status == .pending || charge.status == .overdue {
                        Image(systemName: "clock.badge")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.primary)
                            .accessibilityLabel("Lembrete agendado para \(FinFormat.diaEHora.string(from: quando))")
                    }
                }
            }
            Spacer(minLength: 8)
            Text(Formatters.brl(charge.amount))
                .font(Theme.moneyDisplay(16, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(cor)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    /// Ícone do método: Pix, cartão ou sem link ainda.
    private var metodo: some View {
        let semLink = charge.gatewayName == nil && charge.paymentMethod == nil
        let icone = charge.ehNoCartao ? "creditcard" : (semLink ? "doc.text" : "qrcode")
        return Image(systemName: icone)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(cor)
            .frame(width: 38, height: 38)
            .background(cor.opacity(0.12), in: Circle())
            .accessibilityLabel(charge.ehNoCartao ? "Cartão" : (semLink ? "Sem link" : "Pix"))
    }

    @ViewBuilder
    private var status: some View {
        switch charge.status {
        case .paid: StatusBadge.pago()
        case .pending: StatusBadge.pendente()
        case .overdue: StatusBadge.atrasado()
        case .canceled: StatusBadge(label: "CANCELADA", color: Theme.textSecondary, background: Theme.border.opacity(0.5))
        }
    }

    private var cor: Color {
        switch charge.status {
        case .paid: Theme.success
        case .pending: Theme.warning
        case .overdue: Theme.danger
        case .canceled: Theme.textSecondary
        }
    }
}

// MARK: - Mais filtros

struct FinChargesFiltrosSheet: View {
    @Binding var filtro: FinChargesPageFilter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Forma") {
                    Picker("Forma", selection: $filtro.metodo) {
                        Text("Qualquer").tag(String?.none)
                        Text("Pix").tag(String?.some("PIX"))
                        Text("Cartão").tag(String?.some("CARD"))
                        Text("Sem link").tag(String?.some("NENHUM"))
                    }
                    .pickerStyle(.segmented)
                }
                Section("Vencimento") {
                    Picker("Período", selection: $filtro.periodo) {
                        ForEach(FinChargesPeriodo.allCases) { Text($0.rotulo).tag($0) }
                    }
                    if filtro.periodo == .personalizado {
                        DatePicker("De", selection: $filtro.de, displayedComponents: .date)
                        DatePicker("Até", selection: $filtro.ate, displayedComponents: .date)
                    }
                }
                .environment(\.locale, Locale(identifier: "pt_BR"))
                Section("Ordenar por") {
                    Picker("Ordem", selection: $filtro.ordem) {
                        ForEach(FinChargesOrdem.allCases) { Text($0.rotulo).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            .tint(Theme.primary)
            .navigationTitle("Filtros")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Limpar") {
                        let busca = filtro.busca
                        filtro = FinChargesPageFilter()
                        filtro.busca = busca
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Pronto") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }
}
