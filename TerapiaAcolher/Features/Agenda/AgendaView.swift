import SwiftUI
import Observation

// MARK: - Modos da agenda

enum AgendaMode: String, CaseIterable, Identifiable {
    case list = "Lista"
    case week = "Semana"
    case month = "Mês"

    var id: String { rawValue }
}

// MARK: - ViewModel

@Observable
final class AgendaViewModel {
    /// Primeira janela curta: a tela abre rápido com os próximos dias.
    static let firstWindowDays = 30
    /// Blocos seguintes maiores: menos idas à rede enquanto rola.
    static let nextWindowDays = 60
    /// Recorrência gera no máximo 12 ocorrências, então nada passa disso.
    static let horizonMonths = 18

    var mode: AgendaMode = .list

    // Lista: começa em hoje → +30 dias e vai esticando a janela conforme rola.
    // Pagina por TEMPO, não por contagem: a lista é agrupada por dia e cortar
    // no N-ésimo item partiria um dia no meio ("3 SESSÕES" mostrando 2).
    var listSessions: [AgendaSession] = []
    /// Fim da janela já carregada. O próximo bloco começa no instante seguinte.
    private var listLoadedThrough: Date = .now
    var isLoadingMore = false
    var reachedEndOfList = false

    // Semana
    var weekStart = AgendaFormat.startOfWeek(for: .now)
    var weekSessions: [AgendaSession] = []

    // Mês
    var monthAnchor: Date = {
        let calendar = AgendaFormat.calendar
        let components = calendar.dateComponents([.year, .month], from: .now)
        return calendar.date(from: components) ?? .now
    }()
    var monthCounts: [Int: Int] = [:]
    var selectedDay: Date?
    var daySessions: [AgendaSession] = []
    var isLoadingDay = false
    var dayErrorMessage: String?

    var isLoading = false
    var errorMessage: String?
    /// Nova tentativa a partir do estado de erro — spinner no próprio botão.
    var isRetrying = false

    /// Integração Google. `nil` enquanto não sabemos — o aviso só aparece
    /// quando temos certeza de que está desconectada (a conexão é opcional).
    var googleConnected: Bool?

    private let calendar = AgendaFormat.calendar

    // MARK: Carregamento

    @MainActor
    func reloadCurrent() async {
        if errorMessage != nil { isRetrying = true }
        defer { isRetrying = false }
        switch mode {
        case .list: await loadList()
        case .week: await loadWeek()
        case .month: await loadMonth()
        }
    }

    /// Status da integração Google. Falha silenciosa de propósito: é um aviso
    /// opcional, nunca um erro que atrapalhe quem só quer ver a agenda.
    @MainActor
    func loadGoogleStatus() async {
        if let status: SetGoogleStatus = try? await APIClient.shared.get("integrations/google/status") {
            googleConnected = status.connected
        }
    }

    /// Primeira janela (e recarga do pull-to-refresh): zera a paginação.
    @MainActor
    func loadList() async {
        let from = calendar.startOfDay(for: .now)
        let to = calendar.date(byAdding: .day, value: Self.firstWindowDays, to: from) ?? from
        reachedEndOfList = false
        await fetch(from: from, to: to) { self.listSessions = $0 }
        if errorMessage == nil { listLoadedThrough = to }
    }

    /// Próximo bloco de dias, anexado ao fim da lista.
    ///
    /// Janelas vazias são puladas na mesma chamada: se paramos numa janela sem
    /// sessão, a lista não cresceria e o gatilho de rolagem nunca dispararia de
    /// novo — a paginação travaria com sessões ainda por vir depois do buraco.
    @MainActor
    func loadMoreList() async {
        guard !isLoadingMore, !reachedEndOfList, errorMessage == nil else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        let horizon = calendar.date(byAdding: .month, value: Self.horizonMonths, to: .now) ?? .now
        var cursor = listLoadedThrough

        while cursor < horizon {
            let from = cursor.addingTimeInterval(1)
            let to = calendar.date(byAdding: .day, value: Self.nextWindowDays, to: from) ?? from
            guard let batch = await fetchWindow(from: from, to: to) else { return } // erro: mantém o já carregado
            cursor = to
            listLoadedThrough = to
            if !batch.isEmpty {
                let known = Set(listSessions.map(\.id))
                listSessions.append(contentsOf: batch.filter { !known.contains($0.id) })
                return
            }
        }
        reachedEndOfList = true
    }

    @MainActor
    func loadWeek() async {
        let to = calendar.date(byAdding: DateComponents(day: 7, second: -1), to: weekStart) ?? weekStart
        await fetch(from: weekStart, to: to) { self.weekSessions = $0 }
    }

    @MainActor
    func loadMonth() async {
        isLoading = monthCounts.isEmpty
        errorMessage = nil
        defer { isLoading = false }
        let year = calendar.component(.year, from: monthAnchor)
        let month = calendar.component(.month, from: monthAnchor)
        do {
            let payload: AgendaMonthPayload = try await APIClient.shared.get(
                "sessions/agenda/month",
                query: ["year": "\(year)", "month": "\(month)"]
            )
            monthCounts = Dictionary(uniqueKeysWithValues: payload.days.map { ($0.day, $0.count) })
            if let selectedDay { await loadDay(selectedDay) }
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
        } catch let error as APIError {
            errorMessage = error.message
        } catch {
            errorMessage = "Não foi possível carregar a agenda."
        }
    }

    @MainActor
    func loadDay(_ day: Date) async {
        selectedDay = day
        isLoadingDay = true
        dayErrorMessage = nil
        defer { isLoadingDay = false }
        let from = calendar.startOfDay(for: day)
        let to = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: from) ?? from
        do {
            let result: [AgendaSession] = try await APIClient.shared.get("sessions", query: [
                "from": AgendaFormat.isoQuery.string(from: from),
                "to": AgendaFormat.isoQuery.string(from: to),
            ])
            daySessions = result.filter { $0.status != "CANCELED" }
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
        } catch {
            // Erro não pode virar "lista vazia" silenciosa — exibe estado de
            // erro com retry na seção do dia.
            daySessions = []
            dayErrorMessage = (error as? APIError)?.message
                ?? "Não foi possível carregar as sessões do dia."
        }
    }

    /// Busca uma janela sem mexer no estado de tela cheia (`isLoading`).
    /// `nil` = falhou; quem chama decide se mostra erro ou apenas para.
    @MainActor
    private func fetchWindow(from: Date, to: Date) async -> [AgendaSession]? {
        do {
            let result: [AgendaSession] = try await APIClient.shared.get("sessions", query: [
                "from": AgendaFormat.isoQuery.string(from: from),
                "to": AgendaFormat.isoQuery.string(from: to),
            ])
            return result.filter { $0.status != "CANCELED" }
        } catch {
            // Falha ao paginar não derruba o que já está na tela: o terapeuta
            // continua vendo os próximos dias e pode tentar de novo rolando.
            return nil
        }
    }

    @MainActor
    private func fetch(from: Date, to: Date, assign: @escaping ([AgendaSession]) -> Void) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result: [AgendaSession] = try await APIClient.shared.get("sessions", query: [
                "from": AgendaFormat.isoQuery.string(from: from),
                "to": AgendaFormat.isoQuery.string(from: to),
            ])
            assign(result.filter { $0.status != "CANCELED" })
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
        } catch let error as APIError {
            errorMessage = error.message
        } catch {
            errorMessage = "Não foi possível carregar a agenda."
        }
    }

    // MARK: Navegação temporal

    @MainActor
    func shiftWeek(_ delta: Int) async {
        weekStart = calendar.date(byAdding: .day, value: delta * 7, to: weekStart) ?? weekStart
        await loadWeek()
    }

    @MainActor
    func shiftMonth(_ delta: Int) async {
        monthAnchor = calendar.date(byAdding: .month, value: delta, to: monthAnchor) ?? monthAnchor
        selectedDay = nil
        daySessions = []
        monthCounts = [:]
        await loadMonth()
    }
}

// MARK: - Tela Agenda

struct AgendaView: View {
    @State private var model = AgendaViewModel()
    @State private var showNewSession = false
    @State private var deepLink = DeepLink.shared
    /// O terapeuta pode dispensar o convite do Google — a integração é opcional
    /// e o caminho definitivo continua em Configurações → Integrações.
    @AppStorage("agenda.googleBannerDismissed") private var googleBannerDismissed = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                googleBanner

                modePicker
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                content
            }

            FloatingActionButton {
                showNewSession = true
            }
            .padding(.trailing, 20)
            .padding(.bottom, 24)
        }
        .onAppear {
            Task { await model.reloadCurrent() }
            Task { await model.loadGoogleStatus() }
        }
        // Toque numa notificação de sessão abre o detalhe direto.
        .navigationDestination(item: $deepLink.sessionId) { id in
            AgendaSessionDetailView(sessionId: id)
        }
        .sheet(isPresented: $showNewSession, onDismiss: {
            Task { await model.reloadCurrent() }
        }) {
            AgendaNewSessionView()
        }
    }

    // MARK: Convite opcional — Google Calendar não conectado
    //
    // Só aparece com certeza de desconexão (googleConnected == false) e enquanto
    // não for dispensado. Some sozinho assim que a conta é conectada.

    @ViewBuilder
    private var googleBanner: some View {
        if model.googleConnected == false && !googleBannerDismissed {
            HStack(spacing: 10) {
                NavigationLink {
                    SetGoogleView(onChanged: {
                        Task { await model.loadGoogleStatus() }
                    })
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "video.badge.plus")
                            .font(.system(size: 16))
                            .foregroundStyle(Color(hex: 0x7FA8C9))
                            .frame(width: 38, height: 38)
                            .background(Color(hex: 0x7FA8C9).opacity(0.14))
                            .clipShape(RoundedRectangle(cornerRadius: 11))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Link do Meet automático")
                                .font(Theme.body(14, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text("Conecte sua conta Google · opcional")
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.textSecondary)
                        }

                        Spacer(minLength: 4)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .contentShape(Rectangle())
                }
                .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })

                Button {
                    Haptics.tap()
                    withAnimation(.easeOut(duration: 0.2)) { googleBannerDismissed = true }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(Theme.background, in: Circle())
                }
                .accessibilityLabel("Dispensar")
            }
            .padding(12)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .stroke(Theme.border, lineWidth: 1)
            )
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, 10)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    // MARK: Seletor Lista | Semana | Mês (chips segmentados como no print)

    private var modePicker: some View {
        HStack(spacing: 4) {
            ForEach(AgendaMode.allCases) { mode in
                Button {
                    guard model.mode != mode else { return }
                    model.mode = mode
                    Task { await model.reloadCurrent() }
                } label: {
                    Text(mode.rawValue)
                        .font(Theme.body(14, weight: model.mode == mode ? .semibold : .regular))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            model.mode == mode ? Theme.surface : Color.clear,
                            in: Capsule()
                        )
                        .shadow(
                            color: model.mode == mode ? .black.opacity(0.07) : .clear,
                            radius: 4, y: 2
                        )
                }
            }
        }
        .padding(4)
        .background(Color(hex: 0xF0EBE2))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading {
            Spacer()
            ProgressView().tint(Theme.primary)
            Spacer()
        } else if let error = model.errorMessage {
            Spacer()
            VStack(spacing: 14) {
                EmptyStateView(icon: "wifi.exclamationmark", title: "Ops, não carregou", message: error)
                RetryButton(isLoading: model.isRetrying) {
                    Task { await model.reloadCurrent() }
                }
            }
            Spacer()
        } else {
            switch model.mode {
            case .list: AgendaListView(model: model)
            case .week: AgendaWeekView(model: model)
            case .month: AgendaMonthView(model: model)
            }
        }
    }
}

// MARK: - Visão LISTA (agrupada por dia)

/// Item da agenda-lista. Em sessão online já agendada com link, mostra as ações
/// rápidas do Meet dentro do mesmo card.
///
/// A `NavigationLink` cobre só a linha da sessão, não o card inteiro: se ela
/// envolvesse tudo, tocar em "Entrar" ou "Copiar" abriria o detalhe junto.
struct AgendaSessionListItem: View {
    let session: AgendaSession

    @Environment(\.openURL) private var openURL
    @State private var didCopy = false

    private var meetURL: URL? {
        guard session.isOnline, session.isScheduled,
              let raw = session.meetLink, !raw.isEmpty,
              let url = URL(string: raw)
        else { return nil }
        return url
    }

    var body: some View {
        ThemeCard(padding: 14) {
            VStack(spacing: 0) {
                NavigationLink {
                    AgendaSessionDetailView(sessionId: session.id, preloaded: session)
                } label: {
                    AgendaSessionCardRow(session: session, withCard: false)
                }
                .buttonStyle(.pressableSubtle)

                if let meetURL {
                    Divider()
                        .overlay(Theme.border)
                        .padding(.top, 12)
                        .padding(.bottom, 11)

                    HStack(spacing: 8) {
                        Button {
                            Haptics.tap()
                            openURL(meetURL)
                        } label: {
                            Label("Entrar", systemImage: "video.fill")
                                .font(Theme.body(13, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(Theme.primary, in: Capsule())
                        }
                        .buttonStyle(.pressable)

                        Button {
                            UIPasteboard.general.string = meetURL.absoluteString
                            Haptics.success()
                            withAnimation(.easeOut(duration: 0.15)) { didCopy = true }
                            Task {
                                try? await Task.sleep(for: .seconds(2))
                                withAnimation(.easeOut(duration: 0.2)) { didCopy = false }
                            }
                        } label: {
                            Label(
                                didCopy ? "Copiado!" : "Copiar link",
                                systemImage: didCopy ? "checkmark" : "doc.on.doc"
                            )
                            .font(Theme.body(13, weight: .semibold))
                            .foregroundStyle(didCopy ? Theme.success : Theme.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(
                                didCopy ? Theme.successSoft : Theme.primarySoft,
                                in: Capsule()
                            )
                        }
                        .buttonStyle(.pressable)
                        .accessibilityLabel("Copiar link do Meet")
                    }
                }
            }
        }
    }
}

struct AgendaListView: View {
    let model: AgendaViewModel

    private var sections: [(day: Date, sessions: [AgendaSession])] {
        AgendaFormat.sections(from: model.listSessions)
    }

    var body: some View {
        if model.listSessions.isEmpty {
            ScrollView {
                EmptyStateView(
                    icon: "calendar.badge.plus",
                    title: "Agenda livre",
                    message: "Nenhuma sessão nos próximos 30 dias. Toque em + pra agendar."
                )
                .padding(.top, 60)
            }
            .refreshable { await model.loadList() }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(sections.enumerated()), id: \.element.day) { index, section in
                        AgendaDayHeader(day: section.day, count: section.sessions.count)
                            .padding(.top, 10)
                            .onAppear {
                                // Gatilho no PENÚLTIMO grupo, não no último: a
                                // rede responde enquanto o terapeuta ainda rola,
                                // então o spinner do rodapé quase nunca aparece.
                                if index >= sections.count - 2 {
                                    Task { await model.loadMoreList() }
                                }
                            }
                        ForEach(section.sessions) { session in
                            AgendaSessionListItem(session: session)
                        }
                    }

                    if model.isLoadingMore {
                        HStack {
                            Spacer()
                            ProgressView().tint(Theme.primary)
                            Spacer()
                        }
                        .padding(.vertical, 18)
                        .transition(.opacity)
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.bottom, 100)
                .animation(.easeInOut(duration: 0.2), value: model.isLoadingMore)
            }
            .refreshable { await model.loadList() }
        }
    }
}
