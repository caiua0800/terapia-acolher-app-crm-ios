import SwiftUI

// MARK: - Visão SEMANA: grade horária 7 colunas com blocos por horário

struct AgendaWeekView: View {
    let model: AgendaViewModel

    private let calendar = AgendaFormat.calendar
    private let hourHeight: CGFloat = 56
    private let gutterWidth: CGFloat = 34

    private var days: [Date] {
        (0 ..< 7).compactMap { calendar.date(byAdding: .day, value: $0, to: model.weekStart) }
    }

    /// Faixa horária exibida: 8h–19h, expandindo se houver sessão fora dela.
    private var hourRange: ClosedRange<Int> {
        var lower = 8
        var upper = 19
        for session in model.weekSessions {
            lower = min(lower, calendar.component(.hour, from: session.startsAt))
            let endHour = calendar.component(.hour, from: session.endsAt)
            let endMinute = calendar.component(.minute, from: session.endsAt)
            upper = max(upper, endMinute > 0 ? endHour + 1 : endHour)
        }
        return lower ... max(upper, lower + 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            weekHeader
                .padding(.horizontal, Theme.screenPadding)
                .padding(.bottom, 10)

            dayHeaderRow
                .padding(.horizontal, Theme.screenPadding)

            ScrollView {
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
                ForEach(model.weekSessions) { session in
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
        return HStack(spacing: 14) {
            ForEach(entries, id: \.name) { entry in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(entry.color)
                        .frame(width: 10, height: 10)
                    Text(entry.name)
                        .font(Theme.body(11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func legendEntries() -> [(name: String, color: Color)] {
        var seen = Set<String>()
        var entries: [(String, Color)] = []
        for session in model.weekSessions {
            if let group = session.patient.group, !seen.contains(group.name) {
                seen.insert(group.name)
                entries.append((group.name, Theme.groupColor(group.color)))
            }
        }
        if model.weekSessions.contains(where: { $0.isOnline && $0.patient.group == nil }) {
            entries.append(("Online", Color(hex: 0x46656F)))
        }
        return entries
    }
}
