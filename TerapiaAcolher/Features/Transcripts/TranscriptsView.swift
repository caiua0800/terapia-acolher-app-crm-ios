import SwiftUI

// MARK: - Transcrições: escolher o paciente

/// Entrada pelo paciente, como no CRM web: quem procura uma conversa antiga
/// lembra de quem atendeu, não da data. A leitura reaproveita a folha da
/// Agenda (`AgendaTranscriptSheet`) — é o mesmo conteúdo, da mesma rota.
@Observable
final class TranscriptsPatientsViewModel {
    /// Instância única pelo mesmo motivo da lista de pacientes: voltar para cá
    /// não pode dar spinner de novo.
    static let shared = TranscriptsPatientsViewModel()

    var patients: [Patient] = []
    var searchText = ""
    var isLoading = false
    var isSearching = false
    var errorMessage: String? = nil

    private var searchTask: Task<Void, Never>?
    private var searchGeneration = 0

    @MainActor
    func load(showSpinner: Bool = true) async {
        if showSpinner && patients.isEmpty { isLoading = true }
        errorMessage = nil
        do {
            patients = try await PatientsAPI.list(status: "ACTIVE", search: searchText)
        } catch is CancellationError {
            // troca de tela / refresh — silencioso
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
}

struct TranscriptsView: View {
    @State private var model = TranscriptsPatientsViewModel.shared

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                searchField
                content
            }
        }
        .task { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.patients.isEmpty {
            Spacer()
            ProgressView().tint(Theme.primary)
            Spacer()
        } else if let erro = model.errorMessage, model.patients.isEmpty {
            Spacer()
            VStack(spacing: 14) {
                Text(erro)
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                RetryButton { Task { await model.load() } }
            }
            .padding(.horizontal, 32)
            Spacer()
        } else if model.patients.isEmpty {
            Spacer()
            EmptyStateView(
                icon: "text.bubble",
                title: model.searchText.isEmpty ? "Nenhum paciente" : "Nada encontrado",
                message: model.searchText.isEmpty
                    ? "As transcrições ficam guardadas por paciente — elas aparecem aqui depois das sessões online."
                    : "Nenhum paciente com esse nome."
            )
            .padding(.horizontal, Theme.screenPadding)
            Spacer()
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Escolha o paciente para ver as sessões online que foram transcritas.")
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 4)

                    ThemeCard(padding: 14) {
                        VStack(spacing: 0) {
                            ForEach(Array(model.patients.enumerated()), id: \.element.id) { indice, paciente in
                                NavigationLink {
                                    PatientTranscriptsView(patient: paciente)
                                } label: {
                                    PatientPickerRow(
                                        name: paciente.name,
                                        colorHex: paciente.group?.color,
                                        subtitle: paciente.group?.name
                                    )
                                    .padding(.vertical, 10)
                                }
                                .buttonStyle(.plain)

                                if indice < model.patients.count - 1 {
                                    InsetDivider(leading: 40 + 12, trailing: 0)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .refreshable { await model.load(showSpinner: false) }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.textSecondary)
            TextField("Buscar paciente", text: $model.searchText)
                .font(Theme.body(15))
                .autocorrectionDisabled()
                .onChange(of: model.searchText) { model.searchChanged() }

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
}

// MARK: - Sessões transcritas de um paciente

@Observable
final class PatientTranscriptsViewModel {
    let patient: Patient

    var dados: PatientTranscripts? = nil
    var isLoading = false
    var errorMessage: String? = nil

    /// Transcrição aberta na folha de leitura.
    var transcricao: AgendaTranscriptResponse? = nil
    var isLoadingTranscricao = false
    var erroTranscricao: String? = nil
    var showTranscricao = false
    /// Qual cartão está esperando resposta — o spinner fica no botão tocado.
    var abrindoSessionId: String? = nil

    init(patient: Patient) { self.patient = patient }

    @MainActor
    func load(showSpinner: Bool = true) async {
        if showSpinner && dados == nil { isLoading = true }
        errorMessage = nil
        do {
            dados = try await TranscriptsAPI.doPaciente(patient.id)
        } catch is CancellationError {
        } catch let error as APIError {
            errorMessage = error.message
        } catch {
            errorMessage = "Não foi possível carregar as transcrições."
        }
        isLoading = false
    }

    @MainActor
    func abrir(_ sessionId: String) async {
        abrindoSessionId = sessionId
        isLoadingTranscricao = true
        erroTranscricao = nil
        transcricao = nil
        showTranscricao = true
        do {
            transcricao = try await TranscriptsAPI.daSessao(sessionId)
        } catch let error as APIError {
            erroTranscricao = error.message
        } catch {
            erroTranscricao = "Não foi possível abrir a transcrição."
        }
        isLoadingTranscricao = false
        abrindoSessionId = nil
    }
}

struct PatientTranscriptsView: View {
    @State private var model: PatientTranscriptsViewModel

    init(patient: Patient) {
        _model = State(initialValue: PatientTranscriptsViewModel(patient: patient))
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            content
        }
        .navigationTitle(model.patient.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .sheet(isPresented: .init(
            get: { model.showTranscricao },
            set: { model.showTranscricao = $0 }
        )) {
            AgendaTranscriptSheet(
                response: model.transcricao,
                isLoading: model.isLoadingTranscricao,
                errorMessage: model.erroTranscricao
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.dados == nil {
            ProgressView().tint(Theme.primary)
        } else if let erro = model.errorMessage, model.dados == nil {
            VStack(spacing: 14) {
                Text(erro)
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                RetryButton { Task { await model.load() } }
            }
            .padding(.horizontal, 32)
        } else if model.dados?.sessoes.isEmpty ?? true {
            EmptyStateView(
                icon: "text.bubble",
                title: "Nenhuma transcrição",
                message: "As sessões online de \(primeiroNome) ainda não geraram transcrição. Ela aparece aqui depois que a chamada termina."
            )
            .padding(.horizontal, Theme.screenPadding)
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    Text(cabecalho)
                        .font(Theme.body(11, weight: .semibold))
                        .kerning(1.2)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)

                    ForEach(model.dados?.sessoes ?? []) { sessao in
                        SessionTranscriptCard(
                            sessao: sessao,
                            isLoading: model.abrindoSessionId == sessao.sessionId
                        ) {
                            Task { await model.abrir(sessao.sessionId) }
                        }
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .refreshable { await model.load(showSpinner: false) }
        }
    }

    private var primeiroNome: String {
        model.patient.name.split(separator: " ").first.map(String.init) ?? model.patient.name
    }

    private var cabecalho: String {
        let total = model.dados?.total ?? 0
        return total == 1 ? "1 TRANSCRIÇÃO" : "\(total) TRANSCRIÇÕES"
    }
}

// MARK: - Cartão de uma sessão transcrita

private struct SessionTranscriptCard: View {
    let sessao: SessionWithTranscripts
    let isLoading: Bool
    let aoAbrir: () -> Void

    var body: some View {
        ThemeCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "video.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                        .frame(width: 38, height: 38)
                        .background(Theme.primarySoft)
                        .clipShape(RoundedRectangle(cornerRadius: 11))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(TranscriptsFormat.diaLongo(sessao.iniciaEm))
                            .font(Theme.body(15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)

                        Text(intervalo)
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.textSecondary)
                    }

                    Spacer(minLength: 8)

                    if sessao.status == "ATTENDED" {
                        StatusBadge(label: "ATENDIDA", color: Theme.success, background: Theme.successSoft)
                    }
                }

                if let participantes = sessao.principal?.participantes, !participantes.isEmpty {
                    Label(participantes.joined(separator: ", "), systemImage: "person.2")
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }

                Text(rodape)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)

                Button {
                    Haptics.tap()
                    aoAbrir()
                } label: {
                    HStack(spacing: 8) {
                        if isLoading {
                            ProgressView().controlSize(.small).tint(Theme.primary)
                        } else {
                            Image(systemName: "text.alignleft")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        Text("Ver transcrição")
                            .font(Theme.body(14, weight: .semibold))
                    }
                    .foregroundStyle(Theme.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Theme.primarySoft)
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.pressable)
                .disabled(isLoading)
            }
        }
    }

    private var intervalo: String {
        "\(TranscriptsFormat.hora(sessao.iniciaEm)) às \(TranscriptsFormat.hora(sessao.terminaEm))"
    }

    /// O terapeuta precisa saber se a transcrição tem conteúdo antes de abrir —
    /// chamada curta com 3 falas não vale o toque.
    private var rodape: String {
        let trechos = sessao.principal?.trechos ?? 0
        let base = trechos == 1 ? "1 fala registrada" : "\(trechos) falas registradas"
        guard sessao.transcricoes.count > 1 else { return base }
        return "\(base) · \(sessao.transcricoes.count) gravações nesta sessão"
    }
}

// MARK: - Datas

enum TranscriptsFormat {
    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = format
        return f
    }

    private static let dia = formatter("d 'de' MMMM 'de' yyyy")
    private static let time = formatter("HH:mm")

    /// "13 de julho de 2026" — com ano, porque aqui se procura sessão antiga.
    static func diaLongo(_ date: Date) -> String {
        AgendaFormat.capitalizedFirst(dia.string(from: date))
    }

    static func hora(_ date: Date) -> String { time.string(from: date) }
}
