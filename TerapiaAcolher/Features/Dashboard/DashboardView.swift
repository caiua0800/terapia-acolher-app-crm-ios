import SwiftUI
import Observation

// MARK: - ViewModel

@Observable
final class DashboardViewModel {
    var payload: DashPayload?
    var isLoading = false
    var errorMessage: String?
    /// Nova tentativa a partir do estado de erro — alimenta o spinner do
    /// próprio botão "Tentar de novo" (o spinner central já saiu de cena).
    var isRetrying = false

    @MainActor
    func load() async {
        if payload == nil { isLoading = true }
        if errorMessage != nil { isRetrying = true }
        errorMessage = nil
        defer { isLoading = false; isRetrying = false }
        do {
            payload = try await APIClient.shared.get("dashboard")
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
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
                    RetryButton(isLoading: model.isRetrying) {
                        Task { await model.load() }
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
                leadsSection
                monthSection(payload.month)
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

            Text(AgendaFormat.capitalizedFirst(AgendaFormat.fullDate.string(from: .now)))
                .font(Theme.body(14))
                .foregroundStyle(Theme.textPrimary.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)

            Text("HOJE")
                .font(Theme.body(10, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.textPrimary.opacity(0.45))
                .padding(.top, 12)

            HStack(spacing: 8) {
                miniStat(value: "\(payload.today.total)", label: "Sessões")
                miniStat(value: "\(payload.today.online)", label: "Online")
                miniStat(value: "\(payload.today.toCharge)", label: "A cobrar")
            }

            if payload.today.unreadNotifications > 0 {
                NavigationLink {
                    NotificationsView()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text(payload.today.unreadNotifications == 1
                             ? "1 notificação não lida"
                             : "\(payload.today.unreadNotifications) notificações não lidas")
                            .font(Theme.body(13, weight: .medium))
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Theme.textPrimary.opacity(0.72))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.pressableSubtle)
                .padding(.top, 8)
            }
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

    // MARK: Leads (módulo em demonstração — some com LeadsDemo.enabled)

    @ViewBuilder
    private var leadsSection: some View {
        if LeadsDemo.enabled {
            let store = LeadsStore.shared
            VStack(alignment: .leading, spacing: 12) {
                Text("LEADS")
                    .font(Theme.body(11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.leading, 2)

                NavigationLink {
                    LeadsListView()
                } label: {
                    ThemeCard(padding: 16) {
                        HStack(spacing: 14) {
                            Image(systemName: "tray.full.fill")
                                .font(.system(size: 17))
                                .foregroundStyle(Theme.primary)
                                .frame(width: 42, height: 42)
                                .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 12))

                            VStack(alignment: .leading, spacing: 3) {
                                Text(store.uncontactedCount == 1
                                     ? "1 lead esperando contato"
                                     : "\(store.uncontactedCount) leads esperando contato")
                                    .font(Theme.body(15, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                Text(store.lateCount > 0
                                     ? "\(store.lateCount) há mais de um dia"
                                     : "Nenhum atrasado")
                                    .font(Theme.body(12))
                                    .foregroundStyle(store.lateCount > 0 ? Theme.danger : Theme.textSecondary)
                            }

                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary.opacity(0.5))
                        }
                    }
                }
                .buttonStyle(.pressableSubtle)

                NavigationLink {
                    LeadsCreditsView()
                } label: {
                    ThemeCard(padding: 16) {
                        HStack(spacing: 14) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 17))
                                .foregroundStyle(Theme.warning)
                                .frame(width: 42, height: 42)
                                .background(Theme.warningSoft, in: RoundedRectangle(cornerRadius: 12))

                            VStack(alignment: .leading, spacing: 3) {
                                Text("2 créditos restantes")
                                    .font(Theme.body(15, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Text("Saldo baixo — toque pra recarregar")
                                    .font(Theme.body(12))
                                    .foregroundStyle(Theme.warning)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            }

                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary.opacity(0.5))
                        }
                    }
                }
                .buttonStyle(.pressableSubtle)
            }
        }
    }

    // MARK: Este mês — receita em destaque + faixa compacta
    //
    // A receita saiu do grid 2x2: num card de meia largura o valor encolhia com
    // minimumScaleFactor e ficava ilegível em receitas altas. É a métrica que o
    // terapeuta mais olha, então ganha largura inteira e a tipografia arredondada.

    private func monthSection(_ month: DashMonth) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 5) {
                Text("ESTE MÊS")
                    .font(Theme.body(11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.textSecondary)
                Text("·")
                    .foregroundStyle(Theme.textSecondary.opacity(0.5))
                Text(AgendaFormat.capitalizedFirst(AgendaFormat.monthName.string(from: .now)))
                    .font(Theme.body(11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary.opacity(0.8))
            }
            .padding(.leading, 2)

            revenueCard(month)
            countsStrip(month)
        }
    }

    private func revenueCard(_ month: DashMonth) -> some View {
        ThemeCard(padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("RECEITA")
                        .font(Theme.body(11, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    variationChip(month.revenueVariationPercent)
                }

                Text(Formatters.brl(month.revenue))
                    .font(Theme.moneyDisplay(34))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(month.attended == 1
                     ? "de 1 sessão atendida"
                     : "de \(month.attended) sessões atendidas")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Chip de variação. Sem mês anterior (0%) não mostra nada: uma seta em 0%
    /// sugere estabilidade onde na verdade não há com o que comparar.
    @ViewBuilder
    private func variationChip(_ percent: Int) -> some View {
        if percent != 0 {
            let positivo = percent > 0
            HStack(spacing: 3) {
                Image(systemName: positivo ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 10, weight: .bold))
                Text("\(abs(percent))%")
                    .font(Theme.body(12, weight: .semibold))
                Text("vs \(previousMonthName())")
                    .font(Theme.body(12))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(positivo ? Theme.success : Theme.danger)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                (positivo ? Theme.successSoft : Theme.dangerSoft),
                in: Capsule()
            )
        }
    }

    private func countsStrip(_ month: DashMonth) -> some View {
        HStack(spacing: 10) {
            countTile(
                value: "\(month.sessions)",
                label: "Sessões",
                caption: month.sessionsVariationPercent == 0
                    ? "no mês"
                    : variationCaption(month.sessionsVariationPercent),
                captionColor: month.sessionsVariationPercent == 0
                    ? Theme.textSecondary
                    : (month.sessionsVariationPercent < 0 ? Theme.danger : Theme.success)
            )
            countTile(
                value: "\(month.attended)",
                label: "Atendidas",
                caption: "\(month.attendanceRate)% de presença",
                captionColor: Theme.success
            )
            countTile(
                value: "\(month.missed)",
                label: "Faltas",
                caption: missedCaption(month),
                captionColor: month.missed == 0 ? Theme.success : Theme.warning
            )
        }
    }

    /// "nenhuma" quando zerado; senão a taxa, que é o dado acionável — 4 faltas
    /// em 26 sessões e 4 em 6 são situações completamente diferentes.
    private func missedCaption(_ month: DashMonth) -> String {
        guard month.missed > 0 else { return "nenhuma" }
        guard month.sessions > 0 else { return "no mês" }
        return "\(Int((Double(month.missed) / Double(month.sessions) * 100).rounded()))% do mês"
    }

    private func countTile(
        value: String,
        label: String,
        caption: String,
        captionColor: Color
    ) -> some View {
        ThemeCard(padding: 13) {
            VStack(alignment: .leading, spacing: 3) {
                Text(value)
                    .font(Theme.moneyDisplay(25))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(label)
                    .font(Theme.body(12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.8))
                    .lineLimit(1)
                Text(caption)
                    .font(Theme.body(10, weight: .medium))
                    .foregroundStyle(captionColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
                    .buttonStyle(.pressableSubtle)
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
    @State private var isRetrying = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            if isLoading {
                ProgressView().tint(Theme.primary)
            } else if let errorMessage {
                VStack(spacing: 14) {
                    EmptyStateView(icon: "wifi.exclamationmark", title: "Ops, não carregou", message: errorMessage)
                    RetryButton(isLoading: isRetrying) { Task { await load() } }
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
                                .buttonStyle(.pressableSubtle)
                            }
                        }
                    }
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.bottom, 32)
                }
            }
        }
        .setToolbarTitle("Próximas sessões")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    @MainActor
    private func load() async {
        isLoading = sessions.isEmpty && errorMessage == nil
        if errorMessage != nil { isRetrying = true }
        errorMessage = nil
        defer { isLoading = false; isRetrying = false }
        do {
            let result: [AgendaSession] = try await APIClient.shared.get("sessions", query: [
                "from": AgendaFormat.isoQuery.string(from: .now),
                "status": "SCHEDULED",
            ])
            sessions = result
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
        } catch let error as APIError {
            errorMessage = error.message
        } catch {
            errorMessage = "Não foi possível carregar as sessões."
        }
    }
}
