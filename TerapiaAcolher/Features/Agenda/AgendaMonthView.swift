import SwiftUI

// MARK: - Visão MÊS: calendário com "N sess" por dia + sessões do dia tocado

struct AgendaMonthView: View {
    let model: AgendaViewModel

    private let calendar = AgendaFormat.calendar
    private let weekdaySymbols = ["Dom", "Seg", "Ter", "Qua", "Qui", "Sex", "Sáb"]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                monthHeader

                if model.showsGoogleWarning {
                    GoogleAgendaWarning()
                }

                calendarCard

                if let day = model.selectedDay {
                    daySection(day)
                }
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, 100)
        }
        .refreshable { await model.loadMonth() }
    }

    // MARK: ‹ Julho 2026 ›

    private var monthHeader: some View {
        HStack {
            navButton("chevron.left") { Task { await model.shiftMonth(-1) } }
            Spacer()
            Text(AgendaFormat.capitalizedFirst(AgendaFormat.monthYear.string(from: model.monthAnchor)))
                .font(Theme.serifTitle(20))
                .italic()
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            navButton("chevron.right") { Task { await model.shiftMonth(1) } }
        }
    }

    private func navButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 36, height: 36)
                .background(Theme.surface)
                .clipShape(Circle())
                .overlay(Circle().stroke(Theme.border, lineWidth: 1))
        }
    }

    // MARK: Grade do calendário

    private var calendarCard: some View {
        ThemeCard(padding: 10) {
            VStack(spacing: 6) {
                HStack(spacing: 0) {
                    ForEach(weekdaySymbols, id: \.self) { symbol in
                        Text(symbol)
                            .font(Theme.body(11, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 6)
                .background(Color(hex: 0xF3EEE6))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7),
                    spacing: 2
                ) {
                    ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                        if let day = cell {
                            dayCell(day)
                        } else {
                            Color.clear.frame(height: cellHeight)
                        }
                    }
                }
            }
        }
    }

    /// Célula um pouco mais alta com o Google na tela: cabem as duas
    /// contagens empilhadas ("2 sess" + "1 G").
    private var cellHeight: CGFloat { model.effectiveOrigin.showsGoogle ? 64 : 58 }

    /// Dias do mês com espaços vazios antes do dia 1 (semana começa no domingo).
    private var cells: [Int?] {
        guard
            let range = calendar.range(of: .day, in: .month, for: model.monthAnchor)
        else { return [] }
        let firstWeekday = calendar.component(.weekday, from: model.monthAnchor)
        return Array(repeating: nil, count: firstWeekday - 1) + range.map { $0 }
    }

    private func dayCell(_ day: Int) -> some View {
        let date = dateFor(day: day)
        let count = model.visibleMonthCounts[day] ?? 0
        let googleCount = googleCounts[day] ?? 0
        let isToday = calendar.isDateInToday(date)
        let isSelected = model.selectedDay.map { calendar.isDate($0, inSameDayAs: date) } ?? false

        return Button {
            Haptics.tap()
            Task { await model.loadDay(date) }
        } label: {
            VStack(spacing: 4) {
                Text("\(day)")
                    .font(Theme.body(13, weight: isToday || isSelected ? .bold : .medium))
                    .foregroundStyle(isToday ? .white : Theme.textPrimary)
                    .frame(width: 24, height: 24)
                    .background(isToday ? Theme.primary : Color.clear, in: Circle())

                // Enquanto o dia carrega, o spinner fica na própria célula
                // tocada — a lista de sessões aparece bem abaixo do calendário.
                if isSelected, model.isLoadingDay {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Theme.primary)
                        .frame(height: 15)
                } else if count > 0 || googleCount > 0 {
                    VStack(spacing: 2) {
                        if count > 0 {
                            Text("\(count) sess")
                                .font(Theme.body(9, weight: .bold))
                                .foregroundStyle(Theme.success)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Theme.primarySoft)
                                .clipShape(Capsule())
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        if googleCount > 0 {
                            Text("\(googleCount) G")
                                .font(Theme.body(9, weight: .bold))
                                .foregroundStyle(GoogleAgendaStyle.text)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(GoogleAgendaStyle.soft)
                                .clipShape(Capsule())
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .accessibilityLabel("\(googleCount) na agenda do Google")
                        }
                    }
                } else if model.isLoadingGoogle, model.effectiveOrigin == .mine {
                    // Só o Google na tela e ainda chegando: marca de espera.
                    Capsule()
                        .fill(Theme.border.opacity(0.6))
                        .frame(width: 26, height: 10)
                        .frame(height: 15)
                } else {
                    Color.clear.frame(height: 15)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: cellHeight)
            .background(
                isSelected ? Theme.primarySoft.opacity(0.55) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .animation(.easeInOut(duration: 0.15), value: isSelected)
        }
        .buttonStyle(.pressableSubtle)
    }

    /// Calculado uma vez por desenho, não por célula.
    private var googleCounts: [Int: Int] { model.monthGoogleCounts }

    private func dateFor(day: Int) -> Date {
        var components = calendar.dateComponents([.year, .month], from: model.monthAnchor)
        components.day = day
        return calendar.date(from: components) ?? model.monthAnchor
    }

    // MARK: Sessões do dia selecionado

    private func daySection(_ day: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(AgendaFormat.capitalizedFirst(AgendaFormat.weekday.string(from: day)))
                    .font(Theme.serifTitle(18))
                    .foregroundStyle(Theme.textPrimary)
                Text(AgendaFormat.dayMonth.string(from: day))
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }
            .padding(.top, 4)

            if model.isLoadingDay {
                HStack {
                    Spacer()
                    ProgressView().tint(Theme.primary)
                    Spacer()
                }
                .padding(.vertical, 20)
            } else if let dayError = model.dayErrorMessage {
                ErrorRetryView(message: dayError) {
                    Task { await model.loadDay(day) }
                }
                .padding(.vertical, 8)
            } else if model.selectedDayItems.isEmpty {
                Text(model.effectiveOrigin == .mine
                    ? "Nenhum compromisso na sua agenda do Google neste dia."
                    : "Nenhuma sessão neste dia.")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 18)
            } else {
                ForEach(model.selectedDayItems) { item in
                    switch item {
                    case .session(let session):
                        NavigationLink {
                            AgendaSessionDetailView(sessionId: session.id, preloaded: session)
                        } label: {
                            AgendaSessionCardRow(session: session)
                        }
                        .buttonStyle(.pressableSubtle)
                    case .google(let event):
                        GoogleAgendaEventListItem(event: event)
                    }
                }
            }
        }
    }
}
