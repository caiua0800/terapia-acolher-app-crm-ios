import SwiftUI
import Observation

// MARK: - ViewModel do detalhe

enum AgendaSessionAction {
    case attend, miss, cancel
}

@Observable
final class AgendaSessionDetailModel {
    let sessionId: String
    var session: AgendaSession?
    var isLoading = false
    var errorMessage: String?
    var actionError: String?
    var toast: AgendaToastData?
    var actingAction: AgendaSessionAction?
    var isActing: Bool { actingAction != nil }
    /// Nova tentativa a partir do estado de erro — spinner no próprio botão.
    var isRetrying = false

    init(sessionId: String, preloaded: AgendaSession?) {
        self.sessionId = sessionId
        session = preloaded
    }

    @MainActor
    func load() async {
        isLoading = session == nil && errorMessage == nil
        if errorMessage != nil { isRetrying = true }
        errorMessage = nil
        defer { isLoading = false; isRetrying = false }
        do {
            session = try await APIClient.shared.get("sessions/\(sessionId)")
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
        } catch let error as APIError {
            if session == nil { errorMessage = error.message }
        } catch {
            if session == nil { errorMessage = "Não foi possível carregar a sessão." }
        }
    }

    @MainActor
    func markAttended() async {
        await performAction(.attend) {
            let updated: AgendaSession = try await APIClient.shared.patch("sessions/\(self.sessionId)/attend")
            self.session = updated
            self.toast = AgendaToastData(message: "Sessão marcada como atendida")
        }
    }

    @MainActor
    func markMissed() async {
        await performAction(.miss) {
            let updated: AgendaSession = try await APIClient.shared.patch("sessions/\(self.sessionId)/miss")
            self.session = updated
            self.toast = AgendaToastData(message: "Falta registrada")
        }
    }

    /// scope: "this" | "future" (recorrentes)
    @MainActor
    func cancel(scope: String) async {
        await performAction(.cancel) {
            let _: AgendaCancelResult = try await AgendaAPI.patch(
                "sessions/\(self.sessionId)/cancel",
                query: ["scope": scope]
            )
            self.toast = AgendaToastData(message: "Sessão cancelada", showUndo: false)
            await self.load()
        }
    }

    @MainActor
    private func performAction(_ kind: AgendaSessionAction, _ action: @escaping () async throws -> Void) async {
        actionError = nil
        actingAction = kind
        defer { actingAction = nil }
        do {
            try await action()
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
        } catch let error as APIError {
            actionError = error.message
        } catch {
            actionError = "Não foi possível concluir. Tente de novo."
        }
    }
}

// MARK: - Tela de detalhe da sessão

struct AgendaSessionDetailView: View {
    @State private var model: AgendaSessionDetailModel
    @State private var showCancelDialog = false
    @State private var showRescheduleSheet = false
    @Environment(\.openURL) private var openURL

    init(sessionId: String, preloaded: AgendaSession? = nil) {
        _model = State(initialValue: AgendaSessionDetailModel(sessionId: sessionId, preloaded: preloaded))
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            if let session = model.session {
                content(session)
            } else if model.isLoading {
                ProgressView().tint(Theme.primary)
            } else if let error = model.errorMessage {
                VStack(spacing: 14) {
                    EmptyStateView(icon: "calendar.badge.exclamationmark", title: "Ops", message: error)
                    RetryButton(isLoading: model.isRetrying) { Task { await model.load() } }
                }
            }
        }
        .setToolbarTitle("Sessão")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .agendaToast(Bindable(model).toast)
        .alert("Não deu certo", isPresented: .init(
            get: { model.actionError != nil },
            set: { if !$0 { model.actionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.actionError ?? "")
        }
        .sheet(isPresented: $showRescheduleSheet, onDismiss: {
            Task { await model.load() }
        }) {
            if let session = model.session {
                AgendaRescheduleSheet(session: session)
            }
        }
    }

    private func content(_ session: AgendaSession) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                patientCard(session)

                if session.isOnline {
                    meetCard(session)
                }

                actionsSection(session)
                detailsSection(session)
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .refreshable { await model.load() }
    }

    // MARK: Card do paciente (gradiente suave, como no print)

    private func patientCard(_ session: AgendaSession) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                InitialAvatar(name: session.patient.name, colorHex: session.patient.group?.color, size: 58)
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.patient.name)
                        .font(Theme.serifTitle(21))
                        .foregroundStyle(Theme.textPrimary)
                    if let group = session.patient.group {
                        Text(group.name)
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer()
            }

            HStack(spacing: 10) {
                Text("\(AgendaFormat.capitalizedFirst(AgendaFormat.weekday.string(from: session.startsAt))) · \(AgendaFormat.dayMonth.string(from: session.startsAt)) · \(AgendaFormat.time.string(from: session.startsAt)) → \(AgendaFormat.time.string(from: session.endsAt))")
                    .font(Theme.money(13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(.white.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 0)
                AgendaTypeBadge(isOnline: session.isOnline)
            }

            if !session.isScheduled {
                StatusBadge(
                    label: session.statusLabel.uppercased(),
                    color: statusColor(session),
                    background: statusColor(session).opacity(0.14)
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color(hex: 0xE7F0EA), Color(hex: 0xEDE9F4)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func statusColor(_ session: AgendaSession) -> Color {
        switch session.status {
        case "ATTENDED": Theme.success
        case "MISSED": Theme.warning
        case "CANCELED": Theme.danger
        default: Theme.textSecondary
        }
    }

    // MARK: Bloco Google Meet

    private func meetCard(_ session: AgendaSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "video.fill")
                    .font(.system(size: 12, weight: .bold))
                Text("GOOGLE MEET")
                    .font(Theme.body(11, weight: .bold))
                    .tracking(1)
                Spacer()
                if session.meetLink != nil {
                    Button {
                        UIPasteboard.general.string = session.meetLink
                        model.toast = AgendaToastData(message: "Link copiado", showUndo: false)
                    } label: {
                        Text("COPIAR")
                            .font(Theme.body(11, weight: .bold))
                            .tracking(0.8)
                    }
                }
            }
            .foregroundStyle(Color(hex: 0x3E637F))

            if let link = session.meetLink {
                Text(link.replacingOccurrences(of: "https://", with: ""))
                    .font(Theme.money(13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Button {
                    if let url = meetURL(link) { openURL(url) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text("ENTRAR NA REUNIÃO")
                            .font(Theme.body(13, weight: .bold))
                            .tracking(0.8)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color(hex: 0x3E5461))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            } else {
                Text("Sessão online sem link de videochamada.")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(14)
        .background(Color(hex: 0xDDEAF3))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func meetURL(_ link: String) -> URL? {
        if link.hasPrefix("http://") || link.hasPrefix("https://") {
            return URL(string: link)
        }
        return URL(string: "https://\(link)")
    }

    // MARK: Ações

    private func actionsSection(_ session: AgendaSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AÇÕES")
                .font(Theme.body(11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Theme.textSecondary)

            HStack(spacing: 10) {
                actionButton(
                    "Marcar atendida",
                    icon: "checkmark",
                    foreground: .white,
                    background: Theme.primary,
                    disabled: session.status == "ATTENDED" || session.status == "CANCELED",
                    isLoading: model.actingAction == .attend
                ) {
                    Task { await model.markAttended() }
                }
                actionButton(
                    "Marcar falta",
                    icon: "xmark.circle",
                    foreground: Theme.danger,
                    background: Theme.dangerSoft,
                    disabled: !session.isScheduled,
                    isLoading: model.actingAction == .miss
                ) {
                    Task { await model.markMissed() }
                }
            }
            HStack(spacing: 10) {
                actionButton(
                    "Remarcar",
                    icon: "arrow.triangle.2.circlepath",
                    foreground: Theme.textPrimary,
                    background: Theme.surface,
                    bordered: true,
                    disabled: !session.isScheduled
                ) {
                    showRescheduleSheet = true
                }
                actionButton(
                    "Cancelar",
                    icon: "slash.circle",
                    foreground: Theme.textPrimary,
                    background: Theme.surface,
                    bordered: true,
                    disabled: !session.isScheduled,
                    isLoading: model.actingAction == .cancel
                ) {
                    showCancelDialog = true
                }
                .confirmationDialog(
                    "Cancelar sessão",
                    isPresented: $showCancelDialog,
                    titleVisibility: .visible
                ) {
                    if model.session?.isRecurring == true {
                        Button("Cancelar somente esta", role: .destructive) {
                            Task { await model.cancel(scope: "this") }
                        }
                        Button("Cancelar esta e as futuras", role: .destructive) {
                            Task { await model.cancel(scope: "future") }
                        }
                    } else {
                        Button("Cancelar sessão", role: .destructive) {
                            Task { await model.cancel(scope: "this") }
                        }
                    }
                    Button("Voltar", role: .cancel) {}
                } message: {
                    if model.session?.isRecurring == true {
                        Text("Esta sessão faz parte de uma recorrência. O que você quer cancelar?")
                    } else {
                        Text("A sessão será cancelada na agenda.")
                    }
                }
            }
        }
    }

    private func actionButton(
        _ title: String,
        icon: String,
        foreground: Color,
        background: Color,
        bordered: Bool = false,
        disabled: Bool = false,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        // Ação indisponível fica neutra em vez de "verde apagado": cor cheia
        // num botão morto faz o bloco inteiro parecer clicável.
        let isMuted = disabled && !isLoading
        let effectiveForeground = isMuted ? Theme.textSecondary.opacity(0.7) : foreground
        let effectiveBackground = isMuted ? Theme.surface.opacity(0.6) : background

        return Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(foreground)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(title)
                    .font(Theme.body(14, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(effectiveForeground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(effectiveBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(bordered || isMuted ? Theme.border : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.pressable)
        .disabled(disabled || model.isActing)
        .animation(.easeInOut(duration: 0.15), value: isLoading)
    }

    // MARK: Detalhes

    private func detailsSection(_ session: AgendaSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DETALHES")
                .font(Theme.body(11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Theme.textSecondary)

            ThemeCard(padding: 0) {
                VStack(spacing: 0) {
                    detailRow(
                        icon: "dollarsign",
                        iconColor: Theme.warning,
                        label: "Valor",
                        value: session.price.map { Formatters.brl($0) } ?? "—",
                        monospaced: true
                    )
                    Divider().overlay(Theme.border)
                    detailRow(
                        icon: "arrow.triangle.2.circlepath",
                        iconColor: Theme.primary,
                        label: "Recorrência",
                        value: session.recurrenceLabel
                    )
                    if let observations = session.observations, !observations.isEmpty {
                        Divider().overlay(Theme.border)
                        detailRow(
                            icon: "doc.text",
                            iconColor: Color(hex: 0x7FA8C9),
                            label: "Observações",
                            value: observations
                        )
                    }
                }
            }
        }
    }

    private func detailRow(
        icon: String,
        iconColor: Color,
        label: String,
        value: String,
        monospaced: Bool = false
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 32, height: 32)
                .background(iconColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 9))
            Text(label)
                .font(Theme.body(15, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 12)
            Text(value)
                .font(monospaced ? Theme.money(15) : Theme.body(14))
                .foregroundStyle(monospaced ? Theme.textPrimary : Theme.textSecondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(14)
    }
}

// MARK: - Sheet de remarcação

struct AgendaRescheduleSheet: View {
    let session: AgendaSession

    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    @State private var startTime: Date
    @State private var scope = "this"
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let calendar = AgendaFormat.calendar
    private var durationMinutes: Int {
        max(Int(session.endsAt.timeIntervalSince(session.startsAt) / 60), 5)
    }

    init(session: AgendaSession) {
        self.session = session
        _date = State(initialValue: session.startsAt)
        _startTime = State(initialValue: session.startsAt)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ThemeCard {
                            VStack(spacing: 0) {
                                DatePicker("Data", selection: $date, displayedComponents: .date)
                                    .font(Theme.body(15, weight: .medium))
                                Divider().overlay(Theme.border).padding(.vertical, 8)
                                DatePicker("Início", selection: $startTime, displayedComponents: .hourAndMinute)
                                    .font(Theme.body(15, weight: .medium))
                                HStack {
                                    Text("Duração")
                                        .font(Theme.body(15, weight: .medium))
                                    Spacer()
                                    Text("\(durationMinutes) min")
                                        .font(Theme.money(14))
                                        .foregroundStyle(Theme.textSecondary)
                                }
                                .padding(.top, 12)
                            }
                        }
                        .environment(\.locale, AgendaFormat.locale)

                        if session.isRecurring {
                            ThemeCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("SESSÃO RECORRENTE")
                                        .font(Theme.body(11, weight: .bold))
                                        .tracking(1)
                                        .foregroundStyle(Theme.textSecondary)
                                    Picker("Aplicar em", selection: $scope) {
                                        Text("Somente esta").tag("this")
                                        Text("Esta e as futuras").tag("future")
                                    }
                                    .pickerStyle(.segmented)
                                }
                            }
                        }

                        if let errorMessage {
                            AuthErrorBanner(message: errorMessage)
                        }

                        PrimaryButton(title: "Remarcar", icon: "checkmark", isLoading: isSaving) {
                            Task { await save() }
                        }
                    }
                    .padding(Theme.screenPadding)
                }
            }
            .navigationTitle("Remarcar sessão")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @MainActor
    private func save() async {
        struct Body: Encodable {
            let startsAt: Date
            let durationMinutes: Int
        }
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }

        var components = calendar.dateComponents([.year, .month, .day], from: date)
        let time = calendar.dateComponents([.hour, .minute], from: startTime)
        components.hour = time.hour
        components.minute = time.minute
        guard let newStart = calendar.date(from: components) else { return }

        do {
            let _: AgendaSession = try await AgendaAPI.patch(
                "sessions/\(session.id)",
                query: ["scope": scope],
                body: Body(startsAt: newStart, durationMinutes: durationMinutes)
            )
            dismiss()
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
        } catch let error as APIError {
            errorMessage = error.message
        } catch {
            errorMessage = "Não foi possível remarcar. Tente de novo."
        }
    }
}
