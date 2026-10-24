import SwiftUI

// MARK: - Visão SEMANA: grade horária 7 colunas com blocos por horário

struct AgendaWeekView: View {
    let model: AgendaViewModel

    private let calendar = AgendaFormat.calendar
    private let hourHeight: CGFloat = 56
    private let gutterWidth: CGFloat = 34

    /// Sessões que a origem mostra ("Minha Agenda" esconde as do CRM).
    private var sessions: [AgendaSession] { model.visibleWeekSessions }
    /// Compromissos do Google com horário: entram na grade.
    private var timedEvents: [GoogleAgendaEvent] { model.visibleWeekEvents.filter { !$0.allDay } }
    /// Dia inteiro: faixa própria acima da grade.
    private var allDayEvents: [GoogleAgendaEvent] { model.visibleWeekEvents.filter(\.allDay) }

    private var days: [Date] {
        (0 ..< 7).compactMap { calendar.date(byAdding: .day, value: $0, to: model.weekStart) }
    }

    /// Faixa horária exibida: 8h–19h, expandindo se houver sessão fora dela.
    private var hourRange: ClosedRange<Int> {
        var lower = 8
        var upper = 19
        let spans = sessions.map { ($0.startsAt, $0.endsAt) } + timedEvents.map { ($0.startsAt, $0.endsAt) }
        for (start, end) in spans {
            // Compromisso que vira o dia não estica a grade até a meia-noite.
            guard calendar.isDate(start, inSameDayAs: end) else { continue }
            lower = min(lower, calendar.component(.hour, from: start))
            let endHour = calendar.component(.hour, from: end)
            let endMinute = calendar.component(.minute, from: end)
            upper = max(upper, endMinute > 0 ? endHour + 1 : endHour)
        }
        return lower ... max(upper, lower + 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            weekHeader
                .padding(.horizontal, Theme.screenPadding)
                .padding(.bottom, 10)

            if model.showsGoogleWarning {
                GoogleAgendaWarning()
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.bottom, 10)
            }

            dayHeaderRow
                .padding(.horizontal, Theme.screenPadding)

            ScrollView {
                if !allDayEvents.isEmpty {
                    allDayRow
                        .padding(.horizontal, Theme.screenPadding)
                        .padding(.top, 6)
                }

                grid
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.bottom, 16)

                legend
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.bottom, 100)
            }
            .refreshable { await model.loadWeek() }
        }
    }

    // MARK: Cabeçalho ‹ 13–19 de julho ›

    private var weekHeader: some View {
        HStack {
            navButton("chevron.left") { Task { await model.shiftWeek(-1) } }
            Spacer()
            Text(AgendaFormat.weekRangeLabel(start: model.weekStart))
                .font(Theme.serifTitle(19))
                .italic()
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            navButton("chevron.right") { Task { await model.shiftWeek(1) } }
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

    // MARK: Linha Dom 13 · Seg 14 · ...

    private var dayHeaderRow: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: gutterWidth, height: 1)
            ForEach(days, id: \.self) { day in
                VStack(spacing: 3) {
                    Text(AgendaFormat.capitalizedFirst(
                        AgendaFormat.weekdayShort.string(from: day).replacingOccurrences(of: ".", with: "")
                    ))
                    .font(Theme.body(11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)

                    Text(AgendaFormat.dayOnly.string(from: day))
                        .font(Theme.body(13, weight: .semibold))
                        .foregroundStyle(calendar.isDateInToday(day) ? .white : Theme.textPrimary)
                        .frame(width: 26, height: 26)
                        .background(
                            calendar.isDateInToday(day) ? Theme.primary : Color.clear,
                            in: Circle()
                        )
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 8)
        .background(Color(hex: 0xF3EEE6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Grade horária + blocos

    private var grid: some View {
        let hours = Array(hourRange.lowerBound ... hourRange.upperBound)
        let totalHeight = CGFloat(hours.count - 1) * hourHeight

        return GeometryReader { proxy in
            let columnWidth = (proxy.size.width - gutterWidth) / 7

            ZStack(alignment: .topLeading) {
                // Linhas de hora + rótulos (8h, 10h, ...)
                ForEach(Array(hours.enumerated()), id: \.element) { index, hour in
                    let y = CGFloat(index) * hourHeight
                    Rectangle()
                        .fill(Theme.border.opacity(0.7))
                        .frame(width: proxy.size.width - gutterWidth, height: 1)
                        .offset(x: gutterWidth, y: y)
                    if hour % 2 == 0 {
                        Text("\(hour)h")
                            .font(Theme.body(10, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: gutterWidth - 6, alignment: .leading)
                            .offset(y: y - 6)
                    }
                }

                // Separadores verticais das colunas
                ForEach(0 ..< 8) { index in
                    Rectangle()
                        .fill(Theme.border.opacity(0.45))
                        .frame(width: 1, height: totalHeight)
                        .offset(x: gutterWidth + CGFloat(index) * columnWidth)
                }

                // Blocos de sessão
                ForEach(sessions) { session in
                    if let frame = blockFrame(for: session, columnWidth: columnWidth) {
                        NavigationLink {
                            AgendaSessionDetailView(sessionId: session.id, preloaded: session)
                        } label: {
                            sessionBlock(session, height: frame.height)
                        }
                        .buttonStyle(.pressableSubtle)
                        .frame(width: columnWidth - 5, height: frame.height)
                        .offset(x: frame.x, y: frame.y)
                    }
                }

                // Compromissos do Google (só leitura: abrem no Google Agenda)
                ForEach(timedEvents) { event in
                    if let frame = eventFrame(for: event, columnWidth: columnWidth) {
                        googleBlock(event, height: frame.height)
                            .frame(width: columnWidth - 5, height: frame.height)
                            .offset(x: frame.x, y: frame.y)
                    }
                }
            }
        }
        .frame(height: totalHeight)
        .padding(.top, 8)
    }

    private func blockFrame(
        for session: AgendaSession,
        columnWidth: CGFloat
    ) -> (x: CGFloat, y: CGFloat, height: CGFloat)? {
        let dayStart = calendar.startOfDay(for: session.startsAt)
        guard let dayIndex = days.firstIndex(where: { calendar.isDate($0, inSameDayAs: dayStart) }) else {
            return nil
        }
        let startHour = CGFloat(calendar.component(.hour, from: session.startsAt))
            + CGFloat(calendar.component(.minute, from: session.startsAt)) / 60
        let durationHours = max(session.endsAt.timeIntervalSince(session.startsAt) / 3600, 0.5)

        let y = (startHour - CGFloat(hourRange.lowerBound)) * hourHeight
        let height = max(CGFloat(durationHours) * hourHeight - 3, 30)
        let x = gutterWidth + CGFloat(dayIndex) * columnWidth + 2.5
        return (x, y, height)
    }

    private func eventFrame(
        for event: GoogleAgendaEvent,
        columnWidth: CGFloat
    ) -> (x: CGFloat, y: CGFloat, height: CGFloat)? {
        guard let dayIndex = days.firstIndex(where: { calendar.isDate($0, inSameDayAs: event.startsAt) }) else {
            return nil
        }
        let startHour = CGFloat(calendar.component(.hour, from: event.startsAt))
            + CGFloat(calendar.component(.minute, from: event.startsAt)) / 60
        // Virou o dia: o bloco vai até o fim da grade.
        let endHour = calendar.isDate(event.startsAt, inSameDayAs: event.endsAt)
            ? CGFloat(calendar.component(.hour, from: event.endsAt))
                + CGFloat(calendar.component(.minute, from: event.endsAt)) / 60
            : CGFloat(hourRange.upperBound)
        let duration = max(endHour - startHour, 0.5)

        let y = (startHour - CGFloat(hourRange.lowerBound)) * hourHeight
        let height = max(duration * hourHeight - 3, 30)
        let x = gutterWidth + CGFloat(dayIndex) * columnWidth + 2.5
        return (x, y, height)
    }

    private func googleBlock(_ event: GoogleAgendaEvent, height: CGFloat) -> some View {
        GoogleWeekBlockLink(event: event) {
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(Theme.body(9, weight: .bold))
                    .lineLimit(1)
                if height > 40 {
                    Text(shortTime(event.startsAt))
                        .font(Theme.body(8, weight: .medium))
                        .lineLimit(1)
                        .opacity(0.9)
                }
            }
            .foregroundStyle(GoogleAgendaStyle.blockText)
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(GoogleAgendaStyle.blockFill)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(GoogleAgendaStyle.color, lineWidth: 1))
        }
    }

    // MARK: Dia inteiro (Google), alinhado às colunas

    private var allDayRow: some View {
        HStack(alignment: .top, spacing: 0) {
            Color.clear.frame(width: gutterWidth, height: 1)
            ForEach(days, id: \.self) { day in
                let events = AgendaTimeline.events(on: day, in: allDayEvents, calendar: calendar)
                VStack(spacing: 2) {
                    ForEach(events) { event in
                        GoogleWeekBlockLink(event: event) {
                            Text(event.title)
                                .font(Theme.body(9, weight: .semibold))
                                .lineLimit(1)
                                .foregroundStyle(GoogleAgendaStyle.text)
                                .padding(.horizontal, 3)
                                .padding(.vertical, 2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(GoogleAgendaStyle.color.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(GoogleAgendaStyle.color, lineWidth: 1))
                        }
                    }
                }
                .padding(.horizontal, 2)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func sessionBlock(_ session: AgendaSession, height: CGFloat) -> some View {
        let color = blockColor(session)
        return VStack(alignment: .leading, spacing: 1) {
            Text(shortName(session.patient.name))
                .font(Theme.body(9, weight: .bold))
                .lineLimit(1)
            if height > 40 {
                Text(shortTime(session.startsAt))
                    .font(Theme.body(8, weight: .medium))
                    .lineLimit(1)
                if session.isOnline, height > 56 {
                    Text("Online")
                        .font(Theme.body(8, weight: .medium))
                        .lineLimit(1)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(color)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    /// Cor do bloco: grupo do paciente; online sem grupo → azul-ardósia (como no print).
    private func blockColor(_ session: AgendaSession) -> Color {
        if let hex = session.patient.group?.color {
            return Theme.groupColor(hex)
        }
        return session.isOnline ? Color(hex: 0x46656F) : Theme.primary
    }

    /// "Maria V." — primeiro nome + inicial do segundo.
    private func shortName(_ name: String) -> String {
        let parts = name.split(separator: " ")
        guard let first = parts.first else { return name }
        if parts.count > 1, let secondInitial = parts[1].first {
            return "\(first) \(secondInitial)."
        }
        return String(first)
    }

    /// "8h30" / "14h"
    private func shortTime(_ date: Date) -> String {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return minute == 0 ? "\(hour)h" : "\(hour)h\(String(format: "%02d", minute))"
    }

    // MARK: Legenda (grupos presentes na semana)

    private var legend: some View {
        let entries = legendEntries()
        // Centralizada quando cabe numa linha; com muitos grupos (ou o Google
        // junto) quebra em vez de vazar da tela.
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { legendItems(entries) }
                .frame(maxWidth: .infinity)
            FlowLayout(spacing: 10) { legendItems(entries) }
        }
    }

    @ViewBuilder
    private func legendItems(_ entries: [(name: String, color: Color)]) -> some View {
        ForEach(entries, id: \.name) { entry in
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(entry.color)
                    .frame(width: 10, height: 10)
                Text(entry.name)
                    .font(Theme.body(11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize()
            }
        }
    }

    private func legendEntries() -> [(name: String, color: Color)] {
        var seen = Set<String>()
        var entries: [(String, Color)] = []
        for session in sessions {
            if let group = session.patient.group, !seen.contains(group.name) {
                seen.insert(group.name)
                entries.append((group.name, Theme.groupColor(group.color)))
            }
        }
        if sessions.contains(where: { $0.isOnline && $0.patient.group == nil }) {
            entries.append(("Online", Color(hex: 0x46656F)))
        }
        if !model.visibleWeekEvents.isEmpty {
            entries.append(("Minha Agenda (Google)", GoogleAgendaStyle.color))
        }
        return entries
    }
}

/// Bloco do Google na semana: toque abre no Google Agenda (sem detalhe de sessão).
private struct GoogleWeekBlockLink<Label: View>: View {
    let event: GoogleAgendaEvent
    @ViewBuilder let label: () -> Label

    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            guard let url = event.url else { return }
            Haptics.tap()
            openURL(url)
        } label: {
            label()
        }
        .buttonStyle(.pressableSubtle)
        .accessibilityLabel("\(event.title), \(event.timeLabel), Minha Agenda do Google")
    }
}
