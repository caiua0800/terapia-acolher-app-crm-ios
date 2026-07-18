import SwiftUI
import Observation

// MARK: - ViewModel

@Observable
final class DashboardViewModel {
    var payload: DashPayload?
    var isLoading = false
    var errorMessage: String?

    @MainActor
    func load() async {
        if payload == nil { isLoading = true }
        errorMessage = nil
        defer { isLoading = false }
        do {
            payload = try await APIClient.shared.get("dashboard")
        } catch let error as APIError {
            errorMessage = error.message
        } catch {
            errorMessage = "Não foi possível carregar o painel. Verifique sua internet."
        }
    }
}

// MARK: - Tela Início

struct DashboardView: View {
    @State private var model = DashboardViewModel()

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            if let payload = model.payload {
                content(payload)
            } else if model.isLoading {
                ProgressView()
                    .tint(Theme.primary)
            } else if let error = model.errorMessage {
                VStack(spacing: 14) {
                    EmptyStateView(
                        icon: "wifi.exclamationmark",
                        title: "Ops, não carregou",
                        message: error
                    )
                    Button {
                        Task { await model.load() }
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
            }
        }
        .onAppear {
            Task { await model.load() }
        }
    }

    private func content(_ payload: DashPayload) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                greetingCard(payload)
                metricsGrid(payload.month)
                nextSessionsSection(payload.nextSessions)
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .refreshable { await model.load() }
    }

    // MARK: Card de saudação (gradiente suave + mini-stats)

    private func greetingCard(_ payload: DashPayload) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Olá, \(payload.greetingName)")
                    .font(Theme.serifTitle(26))
                    .italic()
                    .foregroundStyle(Theme.textPrimary)
                Text("🌿")
                    .font(.system(size: 22))
            }

            Text("\(AgendaFormat.capitalizedFirst(AgendaFormat.fullDate.string(from: .now))) · você tem \(payload.today.total) \(payload.today.total == 1 ? "sessão" : "sessões") hoje")
                .font(Theme.body(14))
                .foregroundStyle(Theme.textPrimary.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                miniStat(value: "\(payload.today.total)", label: "Sessões")
                miniStat(value: "\(payload.today.online)", label: "Online")
                miniStat(value: "\(payload.today.toCharge)", label: "Cobrar")
                miniStat(value: "\(payload.today.unreadNotifications)", label: "Não lidas")
            }
            .padding(.top, 10)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color(hex: 0xE7F0EA), Color(hex: 0xEDE9F4), Color(hex: 0xE7EDF4)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func miniStat(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(Theme.money(20, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text(label.uppercased())
                .font(Theme.body(9, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.white.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Grid 2x2 de métricas do mês

    private func metricsGrid(_ month: DashMonth) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
            MetricCard(
                icon: "calendar",
                iconColor: Theme.primary,
                label: "Sessões · mês",
                value: "\(month.sessions)",
                caption: variationCaption(month.sessionsVariationPercent, suffix: " vs \(previousMonthName())"),
                captionColor: month.sessionsVariationPercent < 0 ? Theme.danger : Theme.success
            )
            MetricCard(
                icon: "checkmark.circle",
                iconColor: Color(hex: 0xB9A6D9),
                label: "Atendidas",
                value: "\(month.attended)",
                caption: "\(month.attendanceRate)% taxa",
                captionColor: Theme.success
            )
            MetricCard(
                icon: "exclamationmark.circle",
                iconColor: Theme.warning,
                label: "Faltas",
                value: "\(month.missed)"
            )
            MetricCard(
                icon: "clock",
                iconColor: Color(hex: 0x7FA8C9),
                label: "Receita",
                value: Formatters.brl(month.revenue),
                caption: variationCaption(month.revenueVariationPercent),
                captionColor: month.revenueVariationPercent < 0 ? Theme.danger : Theme.success
            )
        }
    }

    private func variationCaption(_ percent: Int, suffix: String = "") -> String {
        let arrow = percent < 0 ? "↓" : "↑"
        return "\(arrow) \(abs(percent))%\(suffix)"
    }

    private func previousMonthName() -> String {
        let previous = AgendaFormat.calendar.date(byAdding: .month, value: -1, to: .now) ?? .now
        return AgendaFormat.monthName.string(from: previous)
    }

    // MARK: Próximas sessões

    private func nextSessionsSection(_ sessions: [DashNextSession]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Próximas sessões")
                    .font(Theme.serifTitle(20))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                NavigationLink {
                    DashUpcomingSessionsView()
                } label: {
                    Text("Ver tudo")
                        .font(Theme.body(14, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                }
            }
            .padding(.top, 6)

            if sessions.isEmpty {
                EmptyStateView(
                    icon: "calendar",
                    title: "Nenhuma sessão futura",
                    message: "Quando você agendar sessões, elas aparecem aqui."
                )
            } else {
                ForEach(sessions) { session in
                    NavigationLink {
                        AgendaSessionDetailView(sessionId: session.id)
                    } label: {
                        AgendaSessionCardRow(
                            name: session.patient.name,
                            groupName: session.patient.group?.name,
                            groupColorHex: session.patient.group?.color,
                            isOnline: session.isOnline,
                            timeText: AgendaFormat.time.string(from: session.startsAt)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - "Ver tudo": próximas sessões agendadas, agrupadas por dia

struct DashUpcomingSessionsView: View {
    @State private var sessions: [AgendaSession] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            if isLoading {
                ProgressView().tint(Theme.primary)
            } else if let errorMessage {
                VStack(spacing: 14) {
                    EmptyStateView(icon: "wifi.exclamationmark", title: "Ops, não carregou", message: errorMessage)
                    Button("Tentar de novo") { Task { await load() } }
                        .font(Theme.body(15, weight: .semibold))
                }
            } else if sessions.isEmpty {
                EmptyStateView(
                    icon: "calendar",
                    title: "Nenhuma sessão futura",
                    message: "Quando você agendar sessões, elas aparecem aqui."
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(AgendaFormat.sections(from: sessions), id: \.day) { section in
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
                    .padding(.bottom, 32)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Próximas sessões")
                    .font(Theme.serifTitle(19))
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .task { await load() }
    }

    @MainActor
    private func load() async {
        isLoading = sessions.isEmpty
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result: [AgendaSession] = try await APIClient.shared.get("sessions", query: [
                "from": AgendaFormat.isoQuery.string(from: .now),
                "status": "SCHEDULED",
            ])
            sessions = result
        } catch let error as APIError {
            errorMessage = error.message
        } catch {
            errorMessage = "Não foi possível carregar as sessões."
        }
    }
}
