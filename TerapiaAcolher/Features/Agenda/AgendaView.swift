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
    var mode: AgendaMode = .list

    // Lista (hoje → +30 dias)
    var listSessions: [AgendaSession] = []

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

    var isLoading = false
    var errorMessage: String?

    private let calendar = AgendaFormat.calendar

    // MARK: Carregamento

    @MainActor
    func reloadCurrent() async {
        switch mode {
        case .list: await loadList()
        case .week: await loadWeek()
        case .month: await loadMonth()
        }
    }

    @MainActor
    func loadList() async {
        let from = calendar.startOfDay(for: .now)
        let to = calendar.date(byAdding: .day, value: 30, to: from) ?? from
        await fetch(from: from, to: to) { self.listSessions = $0 }
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
        defer { isLoadingDay = false }
        let from = calendar.startOfDay(for: day)
        let to = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: from) ?? from
        do {
            let result: [AgendaSession] = try await APIClient.shared.get("sessions", query: [
                "from": AgendaFormat.isoQuery.string(from: from),
                "to": AgendaFormat.isoQuery.string(from: to),
            ])
            daySessions = result.filter { $0.status != "CANCELED" }
        } catch {
            daySessions = []
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

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
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
        }
        .sheet(isPresented: $showNewSession, onDismiss: {
            Task { await model.reloadCurrent() }
        }) {
            AgendaNewSessionView()
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
                Button {
                    Task { await model.reloadCurrent() }
                } label: {
                    Text("Tentar de novo")
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Theme.primary)
                        .clipShape(Capsule())
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

struct AgendaListView: View {
    let model: AgendaViewModel

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
                    ForEach(AgendaFormat.sections(from: model.listSessions), id: \.day) { section in
                        AgendaDayHeader(day: section.day, count: section.sessions.count)
                            .padding(.top, 10)
                        ForEach(section.sessions) { session in
                            NavigationLink {
                                AgendaSessionDetailView(sessionId: session.id, preloaded: session)
                            } label: {
                                AgendaSessionCardRow(session: session)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.bottom, 100)
            }
            .refreshable { await model.loadList() }
        }
    }
}
