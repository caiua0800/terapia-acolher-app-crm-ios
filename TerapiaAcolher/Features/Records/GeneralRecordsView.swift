import SwiftUI

// MARK: - Listas gerais do menu (Prontuários, Anamneses, Transcrições)
//
// Antes o menu pedia o paciente primeiro. Agora mostra tudo de todos os
// pacientes, com busca pelo nome, período e ordem — igual ao CRM web.
// GET records?kind=… e GET transcricoes (backend `listagem-geral.dto.ts`).

/// Página devolvida pelas listas gerais.
struct GeneralPage<Item: Decodable>: Decodable {
    let itens: [Item]
    let total: Int
    let pagina: Int
    let porPagina: Int
}

struct GeneralPatientRef: Decodable, Hashable {
    let id: String
    let name: String
}

struct GeneralRecordItem: Decodable, Identifiable, Hashable {
    let id: String
    let kind: String
    let title: String
    let entryDate: Date
    let createdAt: Date
    let updatedAt: Date
    let template: GeneralTemplateRef?
    let patient: GeneralPatientRef

    /// Mudou depois de criado (mais de 1 min de diferença).
    var editado: Bool { updatedAt.timeIntervalSince(createdAt) > 60 }
}

struct GeneralTemplateRef: Decodable, Hashable {
    let id: String
    let name: String
}

// MARK: Filtros

enum GeneralPeriod: String, CaseIterable, Identifiable {
    case qualquer, sete, trinta, mes, personalizado
    var id: String { rawValue }

    var rotulo: String {
        switch self {
        case .qualquer: "Qualquer data"
        case .sete: "Últimos 7 dias"
        case .trinta: "Últimos 30 dias"
        case .mes: "Este mês"
        case .personalizado: "Escolher datas"
        }
    }
}

/// Estado dos filtros de uma lista geral. `query` é o que vai para a API.
@Observable
final class GeneralListFilters {
    var busca = ""
    var periodo: GeneralPeriod = .qualquer
    var de = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
    var ate = Date.now
    var usarDe = true
    var usarAte = true
    var maisRecentes = true

    var temFiltro: Bool {
        !busca.trimmingCharacters(in: .whitespaces).isEmpty || periodo != .qualquer || !maisRecentes
    }

    private static let dia: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "America/Sao_Paulo")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Datas no fuso de Brasília, como o backend espera.
    private var datas: (de: String?, ate: String?) {
        let hoje = Date.now
        switch periodo {
        case .qualquer:
            return (nil, nil)
        case .sete:
            return (Self.dia.string(from: hoje.addingTimeInterval(-6 * 86_400)), nil)
        case .trinta:
            return (Self.dia.string(from: hoje.addingTimeInterval(-29 * 86_400)), nil)
        case .mes:
            return (String(Self.dia.string(from: hoje).prefix(7)) + "-01", nil)
        case .personalizado:
            return (usarDe ? Self.dia.string(from: de) : nil, usarAte ? Self.dia.string(from: ate) : nil)
        }
    }

    func query(pagina: Int, porPagina: Int = 20) -> [String: String?] {
        let termo = busca.trimmingCharacters(in: .whitespaces)
        let (de, ate) = datas
        return [
            "busca": termo.isEmpty ? nil : termo,
            "de": de,
            "ate": ate,
            "ordem": maisRecentes ? "recentes" : "antigos",
            "pagina": String(pagina),
            "porPagina": String(porPagina),
        ]
    }

    func limpar() {
        busca = ""
        periodo = .qualquer
        maisRecentes = true
        usarDe = true
        usarAte = true
    }
}

/// Barra de filtros: busca, período (atalhos) e ordem. Simples de propósito.
struct GeneralFilterBar: View {
    @Bindable var filtros: GeneralListFilters
    let placeholder: String

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.textSecondary)
                TextField(placeholder, text: $filtros.busca)
                    .font(Theme.body(15))
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                if !filtros.busca.isEmpty {
                    Button {
                        filtros.busca = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textSecondary)
                    }
                    .accessibilityLabel("Limpar busca")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Theme.surface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Theme.border, lineWidth: 1))

            HStack(spacing: 8) {
                Menu {
                    Picker("Período", selection: $filtros.periodo) {
                        ForEach(GeneralPeriod.allCases) { p in Text(p.rotulo).tag(p) }
                    }
                } label: {
                    chip(icon: "calendar", texto: filtros.periodo.rotulo, ativo: filtros.periodo != .qualquer)
                }
                Menu {
                    Picker("Ordem", selection: $filtros.maisRecentes) {
                        Text("Mais recentes primeiro").tag(true)
                        Text("Mais antigos primeiro").tag(false)
                    }
                } label: {
                    chip(
                        icon: "arrow.up.arrow.down",
                        texto: filtros.maisRecentes ? "Mais recentes" : "Mais antigos",
                        ativo: !filtros.maisRecentes
                    )
                }
                Spacer(minLength: 0)
                if filtros.temFiltro {
                    Button("Limpar") {
                        Haptics.tap()
                        filtros.limpar()
                    }
                    .font(Theme.body(13, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                }
            }

            if filtros.periodo == .personalizado {
                VStack(spacing: 8) {
                    datePickerRow(titulo: "De", usar: $filtros.usarDe, data: $filtros.de)
                    datePickerRow(titulo: "Até", usar: $filtros.usarAte, data: $filtros.ate)
                }
                .padding(12)
                .background(Theme.primarySoft.opacity(0.45))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func chip(icon: String, texto: String, ativo: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold))
            Text(texto).font(Theme.body(13, weight: .semibold))
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
        }
        .foregroundStyle(ativo ? .white : Theme.textPrimary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(ativo ? Theme.ink : Theme.surface)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(ativo ? Color.clear : Theme.border, lineWidth: 1))
    }

    private func datePickerRow(titulo: String, usar: Binding<Bool>, data: Binding<Date>) -> some View {
        HStack {
            Toggle(isOn: usar) {
                Text(titulo).font(Theme.body(14, weight: .medium)).foregroundStyle(Theme.textPrimary)
            }
            .toggleStyle(.switch)
            .tint(Theme.primary)
            .fixedSize()
            Spacer()
            if usar.wrappedValue {
                DatePicker("", selection: data, displayedComponents: .date)
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "pt_BR"))
            } else {
                Text("sem limite").font(Theme.body(13)).foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

// MARK: Prontuários / Anamneses

@Observable
final class GeneralRecordsViewModel {
    let kind: RecordsKind
    let filtros = GeneralListFilters()
    var itens: [GeneralRecordItem] = []
    var total = 0
    var pagina = 1
    var isLoading = true
    var carregandoMais = false
    var errorMessage: String? = nil
    private var buscaTask: Task<Void, Never>?

    init(kind: RecordsKind) { self.kind = kind }

    var temMais: Bool { itens.count < total }

    @MainActor
    func recarregar(mostrarEsqueleto: Bool = false) async {
        if mostrarEsqueleto || itens.isEmpty { isLoading = true }
        errorMessage = nil
        do {
            var q = filtros.query(pagina: 1)
            q["kind"] = kind.apiValue
            let pagina: GeneralPage<GeneralRecordItem> = try await APIClient.shared.get("records", query: q)
            itens = pagina.itens
            total = pagina.total
            self.pagina = 1
        } catch is CancellationError {
        } catch let error as APIError {
            errorMessage = error.message
        } catch {
            errorMessage = "Não foi possível carregar os registros."
        }
        isLoading = false
    }

    @MainActor
    func carregarMais() async {
        guard temMais, !carregandoMais else { return }
        carregandoMais = true
        do {
            var q = filtros.query(pagina: pagina + 1)
            q["kind"] = kind.apiValue
            let proxima: GeneralPage<GeneralRecordItem> = try await APIClient.shared.get("records", query: q)
            itens += proxima.itens
            total = proxima.total
            pagina += 1
        } catch {
            // Falha no "carregar mais" não apaga o que já está na tela.
        }
        carregandoMais = false
    }

    /// Busca espera 350 ms depois da última letra.
    @MainActor
    func buscaMudou() {
        buscaTask?.cancel()
        buscaTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await self?.recarregar()
        }
    }
}

struct GeneralRecordsView: View {
    let kind: RecordsKind
    @State private var model: GeneralRecordsViewModel
    @State private var aberto: GeneralRecordItem? = nil

    init(kind: RecordsKind) {
        self.kind = kind
        _model = State(initialValue: GeneralRecordsViewModel(kind: kind))
    }

    private var ehProntuario: Bool { kind == .record }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Theme.background.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    GeneralFilterBar(filtros: model.filtros, placeholder: "Buscar pelo nome do paciente")
                    contagem
                    conteudo
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, 110)
            }
            .refreshable { await model.recarregar() }

            NavigationLink {
                RecordsHomeView(kind: kind)
                    .navigationTitle(ehProntuario ? "Novo prontuário" : "Nova anamnese")
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus").font(.system(size: 15, weight: .bold))
                    Text(ehProntuario ? "Novo prontuário" : "Nova anamnese")
                        .font(Theme.body(15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 15)
                .background(Theme.primary)
                .clipShape(Capsule())
                .shadow(color: Theme.primary.opacity(0.3), radius: 10, y: 4)
            }
            .buttonStyle(.pressable)
            .padding(.trailing, Theme.screenPadding)
            .padding(.bottom, 24)
        }
        .task { if model.itens.isEmpty { await model.recarregar() } }
        .onChange(of: model.filtros.busca) { model.buscaMudou() }
        .onChange(of: model.filtros.periodo) { Task { await model.recarregar() } }
        .onChange(of: model.filtros.maisRecentes) { Task { await model.recarregar() } }
        .onChange(of: model.filtros.de) { Task { await model.recarregar() } }
        .onChange(of: model.filtros.ate) { Task { await model.recarregar() } }
        .onChange(of: model.filtros.usarDe) { Task { await model.recarregar() } }
        .onChange(of: model.filtros.usarAte) { Task { await model.recarregar() } }
        .sheet(item: $aberto) { item in
            RecEntryFormView(
                mode: .edit(entryId: item.id),
                patient: RecPatientRef(id: item.patient.id, name: item.patient.name),
                kind: kind
            ) {
                Task { await model.recarregar() }
            }
        }
    }

    private var contagem: some View {
        Text(model.total == 1
             ? (ehProntuario ? "1 REGISTRO" : "1 ANAMNESE")
             : "\(model.total) \(ehProntuario ? "REGISTROS" : "ANAMNESES")")
            .font(Theme.body(11, weight: .semibold))
            .kerning(1.2)
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 4)
            .opacity(model.isLoading ? 0 : 1)
    }

    @ViewBuilder
    private var conteudo: some View {
        if model.isLoading && model.itens.isEmpty {
            SkeletonList(linhas: 6, avatarSize: 40)
        } else if let erro = model.errorMessage, model.itens.isEmpty {
            ErrorRetryView(message: erro) { Task { await model.recarregar(mostrarEsqueleto: true) } }
                .padding(.top, 30)
        } else if model.itens.isEmpty {
            EmptyStateView(
                icon: ehProntuario ? "doc.text" : "pencil.line",
                title: model.filtros.temFiltro ? "Nada com esses filtros" : (ehProntuario ? "Nenhum prontuário ainda" : "Nenhuma anamnese ainda"),
                message: model.filtros.temFiltro
                    ? "Tente outro nome ou outro período."
                    : "Quando você registrar, aparece aqui com o nome do paciente e a data."
            )
            .padding(.top, 30)
        } else {
            ForEach(model.itens) { item in
                Button {
                    Haptics.tap()
                    aberto = item
                } label: {
                    GeneralRecordRow(item: item)
                }
                .buttonStyle(.pressableSubtle)
                .onAppear {
                    if item.id == model.itens.last?.id { Task { await model.carregarMais() } }
                }
            }
            if model.carregandoMais {
                ProgressView().tint(Theme.primary).frame(maxWidth: .infinity).padding(.vertical, 8)
            }
        }
    }
}

private struct GeneralRecordRow: View {
    let item: GeneralRecordItem

    var body: some View {
        ThemeCard {
            HStack(alignment: .top, spacing: 12) {
                InitialAvatar(name: item.patient.name, size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.patient.name)
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(item.title)
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        if let modelo = item.template {
                            Text(modelo.name)
                                .font(Theme.body(11.5, weight: .semibold))
                                .foregroundStyle(Theme.primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Theme.primarySoft)
                                .clipShape(Capsule())
                                .lineLimit(1)
                        }
                        Text(rodape)
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary.opacity(0.5))
                    .padding(.top, 4)
            }
        }
    }

    private var rodape: String {
        let base = "\(RecFormat.dayMonthYear(item.entryDate)) · criado às \(RecFormat.time.string(from: item.createdAt))"
        return item.editado ? base + " · editado" : base
    }
}

extension RecFormat {
    private static let dmy: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "dd/MM/yyyy"
        return f
    }()

    static func dayMonthYear(_ date: Date) -> String { dmy.string(from: date) }
}
