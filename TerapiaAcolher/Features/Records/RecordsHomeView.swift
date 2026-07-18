import SwiftUI

// MARK: - Home de Prontuários/Anamneses: escolher paciente → timeline

@Observable
final class RecordsHomeViewModel {
    var patients: [Patient] = []
    var searchText = ""
    var isLoading = true
    var errorMessage: String? = nil

    private var searchTask: Task<Void, Never>?

    @MainActor
    func load(showSpinner: Bool = true) async {
        if showSpinner { isLoading = true }
        errorMessage = nil
        do {
            patients = try await PatientsAPI.list(status: "ACTIVE", search: searchText)
        } catch let error as APIError {
            errorMessage = error.message
        } catch {
            errorMessage = "Não foi possível carregar os pacientes."
        }
        isLoading = false
    }

    @MainActor
    func searchChanged() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await self?.load(showSpinner: false)
        }
    }
}

/// Fluxo dos itens de menu "Prontuários"/"Anamneses":
/// escolher o paciente → timeline de registros do tipo.
struct RecordsHomeView: View {
    let kind: RecordsKind
    @State private var model = RecordsHomeViewModel()

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                Text("Escolha o paciente para ver \(kind == .record ? "os prontuários" : "as anamneses").")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.top, 8)
                searchField
                content
            }
        }
        .task { await model.load() }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.textSecondary)
            TextField("Buscar paciente...", text: $model.searchText)
                .font(Theme.body(15))
                .autocorrectionDisabled()
                .onChange(of: model.searchText) { model.searchChanged() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.surface)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
        .padding(.horizontal, Theme.screenPadding)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading {
            Spacer()
            ProgressView().tint(Theme.primary)
            Spacer()
        } else if let error = model.errorMessage {
            Spacer()
            ErrorRetryView(message: error) { Task { await model.load() } }
            Spacer()
        } else if model.patients.isEmpty {
            Spacer()
            EmptyStateView(
                icon: kind == .record ? "doc.text" : "pencil.line",
                title: "Nenhum paciente",
                message: "Cadastre pacientes para registrar \(kind == .record ? "prontuários" : "anamneses")."
            )
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.patients) { patient in
                        NavigationLink {
                            RecTimelineView(patient: RecPatientRef(from: patient), kind: kind)
                        } label: {
                            PatientRow(patient: patient)
                        }
                        .buttonStyle(.plain)
                        if patient.id != model.patients.last?.id {
                            Divider().overlay(Theme.border)
                                .padding(.leading, Theme.screenPadding + 56)
                        }
                    }
                }
                .padding(.bottom, 40)
            }
            .refreshable { await model.load(showSpinner: false) }
        }
    }
}

// MARK: - Timeline de registros de um paciente

@Observable
final class RecTimelineViewModel {
    let patient: RecPatientRef
    let kind: RecordsKind
    var entries: [RecEntrySummary] = []
    var isLoading = true
    var errorMessage: String? = nil

    init(patient: RecPatientRef, kind: RecordsKind) {
        self.patient = patient
        self.kind = kind
    }

    @MainActor
    func load(showSpinner: Bool = true) async {
        if showSpinner { isLoading = entries.isEmpty }
        errorMessage = nil
        do {
            entries = try await RecordsAPI.entries(patientId: patient.id, kind: kind)
        } catch let error as APIError {
            errorMessage = error.message
        } catch {
            errorMessage = "Não foi possível carregar os registros."
        }
        isLoading = false
    }
}

struct RecTimelineView: View {
    @State private var model: RecTimelineViewModel
    @State private var showTemplatePicker = false
    @State private var openedEntry: RecEntrySummary? = nil
    @State private var creation: RecCreationContext? = nil

    init(patient: RecPatientRef, kind: RecordsKind) {
        _model = State(initialValue: RecTimelineViewModel(patient: patient, kind: kind))
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                content
            }
            FloatingActionButton { showTemplatePicker = true }
                .padding(.trailing, Theme.screenPadding)
                .padding(.bottom, 24)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(model.kind == .record ? "Prontuário" : "Anamnese")
                    .font(Theme.serifTitle(20))
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .sheet(isPresented: $showTemplatePicker) {
            RecTemplatePickerView(kind: model.kind) { template in
                showTemplatePicker = false
                creation = RecCreationContext(template: template)
            }
        }
        .sheet(item: $creation) { context in
            RecEntryFormView(
                mode: .create(template: context.template),
                patient: model.patient,
                kind: model.kind
            ) {
                Task { await model.load(showSpinner: false) }
            }
        }
        .sheet(item: $openedEntry) { entry in
            RecEntryFormView(
                mode: .edit(entryId: entry.id),
                patient: model.patient,
                kind: model.kind
            ) {
                Task { await model.load(showSpinner: false) }
            }
        }
        .task { await model.load() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            InitialAvatar(name: model.patient.name, colorHex: model.patient.groupColor, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.patient.name)
                    .font(Theme.body(16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(recordsCountLabel)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.vertical, 12)
    }

    private var recordsCountLabel: String {
        let count = model.entries.count
        let word = model.kind == .record
            ? (count == 1 ? "registro" : "registros")
            : (count == 1 ? "anamnese" : "anamneses")
        return "\(count) \(word) · criptografados"
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading {
            Spacer()
            ProgressView().tint(Theme.primary)
            Spacer()
        } else if let error = model.errorMessage {
            Spacer()
            ErrorRetryView(message: error) { Task { await model.load() } }
            Spacer()
        } else if model.entries.isEmpty {
            Spacer()
            EmptyStateView(
                icon: model.kind == .record ? "doc.text" : "pencil.line",
                title: model.kind == .record ? "Nenhum registro ainda" : "Nenhuma anamnese ainda",
                message: "Toque em + para criar a partir de um modelo.",
                actionTitle: model.kind.newTitle,
                action: { showTemplatePicker = true }
            )
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(model.entries) { entry in
                        Button {
                            openedEntry = entry
                        } label: {
                            RecEntryCard(entry: entry)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 4)
                .padding(.bottom, 100)
            }
            .refreshable { await model.load(showSpinner: false) }
        }
    }
}

/// Contexto de criação (sheet item): modelo escolhido ou em branco.
struct RecCreationContext: Identifiable {
    let id = UUID()
    let template: RecTemplate?
}

// MARK: - Card da timeline ("Evolução — 13/07")

struct RecEntryCard: View {
    let entry: RecEntrySummary

    var body: some View {
        ThemeCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if let template = entry.template {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 11, weight: .semibold))
                            Text(template.name)
                                .font(Theme.body(12, weight: .semibold))
                        }
                        .foregroundStyle(Color(hex: 0x7C6BA5))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(hex: 0xB9A6D9).opacity(0.18))
                        .clipShape(Capsule())
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Em branco")
                                .font(Theme.body(12, weight: .semibold))
                        }
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Theme.border.opacity(0.5))
                        .clipShape(Capsule())
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary.opacity(0.5))
                }
                Text(entry.title)
                    .font(Theme.serifTitle(20))
                    .foregroundStyle(Theme.textPrimary)
                Text(RecFormat.fullDate.string(from: entry.entryDate))
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
