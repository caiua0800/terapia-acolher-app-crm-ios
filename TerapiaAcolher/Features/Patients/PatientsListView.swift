import SwiftUI

// MARK: - ViewModel

@Observable
final class PatientsListViewModel {
    enum StatusFilter { case active, inactive }

    var patients: [Patient] = []
    var groups: [PatientGroup] = []
    var searchText = ""
    var statusFilter: StatusFilter = .active
    var selectedGroupId: String? = nil
    var sortAscending = true
    var isLoading = false
    var errorMessage: String? = nil
    var toast: String? = nil

    /// Liga NO INSTANTE da digitação, antes do debounce e da requisição.
    /// Sem isso a busca fica 350ms + rede sem sinal nenhum na tela e passa
    /// sensação de travamento (ver memoria/feedback-loading-imediato.md).
    var isSearching = false

    private var searchTask: Task<Void, Never>?
    /// Só a busca MAIS RECENTE pode apagar o spinner: uma resposta antiga
    /// chegando depois desligaria o feedback com outra digitação em voo.
    private var searchGeneration = 0

    var sortedPatients: [Patient] {
        sortAscending ? patients : patients.reversed()
    }

    var headerLabel: String {
        let count = patients.count
        let word = count == 1 ? "PACIENTE" : "PACIENTES"
        let status = statusFilter == .active ? (count == 1 ? "ATIVO" : "ATIVOS") : (count == 1 ? "INATIVO" : "INATIVOS")
        return "\(count) \(word) \(status)"
    }

    @MainActor
    func load(showSpinner: Bool = true) async {
        if showSpinner { isLoading = true }
        errorMessage = nil
        do {
            async let patientsCall = PatientsAPI.list(
                status: statusFilter == .active ? "ACTIVE" : "INACTIVE",
                groupId: selectedGroupId,
                search: searchText
            )
            async let groupsCall = PatientsAPI.groups()
            let (patients, groups) = try await (patientsCall, groupsCall)
            self.patients = patients
            self.groups = groups
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
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
        searchGeneration += 1
        let generation = searchGeneration
        isSearching = true

        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await self?.load(showSpinner: false)
            guard let self, generation == self.searchGeneration else { return }
            self.isSearching = false
        }
    }

    @MainActor
    func showToast(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            if toast == message { toast = nil }
        }
    }
}

// MARK: - Tela: lista de pacientes

struct PatientsListView: View {
    @State private var model = PatientsListViewModel()
    @State private var showNewPatient = false
    @State private var showAddOptions = false
    @State private var showImport = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                searchField
                filterChips
                content
            }

            FloatingActionButton { showAddOptions = true }
                .confirmationDialog("Adicionar pacientes", isPresented: $showAddOptions, titleVisibility: .visible) {
                    Button("Novo paciente") { showNewPatient = true }
                    Button("Importar planilha (CSV/Excel)") { showImport = true }
                }
                .padding(.trailing, Theme.screenPadding)
                .padding(.bottom, 24)

            if let toast = model.toast {
                ToastBanner(message: toast)
                    .frame(maxWidth: .infinity)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.toast)
        .sheet(isPresented: $showNewPatient) {
            PatientFormView(mode: .create) { _ in
                Task { await model.load(showSpinner: false) }
                model.showToast("Paciente cadastrado")
            }
        }
        .sheet(isPresented: $showImport) {
            PatientImportView {
                Task { await model.load(showSpinner: false) }
                model.showToast("Pacientes importados")
            }
        }
        .task { await model.load() }
    }

    // MARK: Busca

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.textSecondary)
            TextField("Buscar por nome, WhatsApp...", text: $model.searchText)
                .font(Theme.body(15))
                .autocorrectionDisabled()
                .onChange(of: model.searchText) { model.searchChanged() }

            // Spinner e "limpar" dividem o mesmo espaço: sem largura fixa o
            // campo daria um salto a cada troca entre os dois.
            ZStack {
                if model.isSearching {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Theme.primary)
                        .transition(.opacity)
                } else if !model.searchText.isEmpty {
                    Button {
                        Haptics.tap()
                        model.searchText = ""
                        model.searchChanged()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.textSecondary.opacity(0.6))
                    }
                    .transition(.opacity)
                }
            }
            .frame(width: 20, height: 20)
            .animation(.easeInOut(duration: 0.15), value: model.isSearching)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.surface)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
        .padding(.horizontal, Theme.screenPadding)
        .padding(.top, 8)
    }

    // MARK: Chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(label: "Ativos", isSelected: model.statusFilter == .active) {
                    model.statusFilter = .active
                    Task { await model.load(showSpinner: false) }
                }
                FilterChip(label: "Inativos", isSelected: model.statusFilter == .inactive) {
                    model.statusFilter = .inactive
                    Task { await model.load(showSpinner: false) }
                }
                ForEach(model.groups) { group in
                    FilterChip(label: group.name, isSelected: model.selectedGroupId == group.id) {
                        model.selectedGroupId = model.selectedGroupId == group.id ? nil : group.id
                        Task { await model.load(showSpinner: false) }
                    }
                }
            }
            .padding(.horizontal, Theme.screenPadding)
        }
        .padding(.vertical, 12)
    }

    // MARK: Conteúdo

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
                icon: "person.2",
                title: "Nenhum paciente aqui",
                message: model.searchText.isEmpty
                    ? "Cadastre seu primeiro paciente para começar."
                    : "Nenhum resultado para \"\(model.searchText)\".",
                actionTitle: model.searchText.isEmpty ? "Novo paciente" : nil,
                action: model.searchText.isEmpty ? { showNewPatient = true } : nil
            )
            Spacer()
        } else {
            // Durante a busca a lista ANTERIOR continua visível, só esmaecida:
            // trocar por spinner de tela cheia perde o contexto e pisca a cada
            // tecla. O sinal de "atualizando" fica no campo, onde ele digitou.
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: []) {
                    listHeader
                    ForEach(model.sortedPatients) { patient in
                        NavigationLink {
                            PatientDetailView(patientId: patient.id) { deletedName in
                                Task { await model.load(showSpinner: false) }
                                model.showToast("\(deletedName) foi excluído(a)")
                            }
                        } label: {
                            PatientRow(patient: patient)
                        }
                        .buttonStyle(.pressableSubtle)
                        if patient.id != model.sortedPatients.last?.id {
                            // Divisor alinhado ao texto e recuado da margem
                            // direita — antes ele encostava na borda da tela.
                            InsetDivider(
                                leading: Theme.screenPadding + 58,
                                trailing: Theme.screenPadding
                            )
                        }
                    }
                }
                .padding(.bottom, 100)
            }
            .refreshable { await model.load(showSpinner: false) }
            .opacity(model.isSearching ? 0.55 : 1)
            .animation(.easeInOut(duration: 0.18), value: model.isSearching)
        }
    }

    private var listHeader: some View {
        HStack {
            Text(model.headerLabel)
                .font(Theme.body(12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .tracking(1.2)
            Spacer()
            Button {
                model.sortAscending.toggle()
            } label: {
                Text(model.sortAscending ? "A–Z" : "Z–A")
                    .font(Theme.body(12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.bottom, 10)
    }
}

// MARK: - Célula de paciente

struct PatientRow: View {
    let patient: Patient

    var body: some View {
        HStack(spacing: 12) {
            InitialAvatar(name: patient.name, colorHex: patient.group?.color, size: 46)
            VStack(alignment: .leading, spacing: 5) {
                Text(patient.name)
                    .font(Theme.body(16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if let group = patient.group {
                        GroupTag(name: group.name, colorHex: group.color)
                    }
                    Text(PatientFormat.nextSessionLabel(patient.nextSession))
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// MARK: - Componentes locais reutilizados na feature

/// Toast escuro estilo MVP ("Sessão marcada como atendida").
struct ToastBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.primary)
            Text(message)
                .font(Theme.body(14, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Theme.ink)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
        .padding(.bottom, 96)
        .padding(.horizontal, Theme.screenPadding)
    }
}

/// Estado de erro com botão de tentar de novo.
struct ErrorRetryView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 36))
                .foregroundStyle(Theme.danger.opacity(0.7))
            Text(message)
                .font(Theme.body(14))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Tentar de novo", action: retry)
                .font(Theme.body(15, weight: .semibold))
                .foregroundStyle(Theme.primary)
        }
        .padding(.horizontal, 40)
    }
}
