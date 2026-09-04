import SwiftUI
import Observation

// MARK: - DTOs da agenda (espelham o SessionsService do backend)

struct AgendaGroupRef: Decodable, Hashable {
    let id: String
    let name: String
    let color: String?
}

struct AgendaSessionPatient: Decodable, Hashable {
    let id: String
    let name: String
    /// Só dígitos com DDI (pronto para `wa.me/`). Nulo se a ficha não tem.
    let whatsapp: String?
    let group: AgendaGroupRef?
}

/// Sessão como serializada por sessions.service.toResponse.
struct AgendaSession: Decodable, Identifiable, Hashable {
    let id: String
    let patient: AgendaSessionPatient
    let startsAt: Date
    let endsAt: Date
    let type: String        // PRESENCIAL | ONLINE
    let status: String      // SCHEDULED | ATTENDED | MISSED | CANCELED
    let price: Double?
    let recurrence: String  // NONE | WEEKLY | BIWEEKLY | MONTHLY
    let recurrenceGroupId: String?
    let meetLink: String?
    let observations: String?

    var isOnline: Bool { type == "ONLINE" }
    var isScheduled: Bool { status == "SCHEDULED" }

    /// Conversa com o paciente, quando não há chamada para entrar.
    ///
    /// Presencial nunca tem link; online pode ficar sem, e nos dois casos o
    /// cartão não oferecia ação nenhuma. Nulo quando há Meet (o botão de
    /// entrar já resolve) ou quando a ficha não tem número — aí o link só
    /// levaria a um erro do WhatsApp.
    var whatsappURL: URL? {
        if meetLink?.isEmpty == false { return nil }
        let digits = (patient.whatsapp ?? "").filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        return URL(string: "https://wa.me/\(digits)")
    }
    var isRecurring: Bool { recurrenceGroupId != nil }

    var recurrenceLabel: String {
        AgendaRecurrence(rawValue: recurrence)?.label ?? "Nenhuma"
    }

    var statusLabel: String {
        switch status {
        case "ATTENDED": "Atendida"
        case "MISSED": "Falta"
        case "CANCELED": "Cancelada"
        default: "Agendada"
        }
    }
}

/// Referência leve de paciente pro picker (GET patients).
struct AgendaPatientRef: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let email: String?
    let status: String?
    let group: AgendaGroupRef?
}

/// Detalhe usado só pra puxar o valor padrão da sessão (GET patients/:id).
struct AgendaPatientDetail: Decodable {
    let id: String
    let email: String?
    /// Usado para saber se dá para avisar o paciente sem e-mail cadastrado.
    let whatsapp: String?
    let sessionPrice: Double?
}

/// GET sessions/agenda/month → contagem por dia.
struct AgendaMonthPayload: Decodable {
    struct DayCount: Decodable {
        let day: Int
        let count: Int
    }

    let year: Int
    let month: Int
    let days: [DayCount]
}

struct AgendaCancelResult: Decodable {
    let ok: Bool
    let canceledSessions: Int
}

enum AgendaRecurrence: String, CaseIterable, Identifiable {
    case none = "NONE"
    case weekly = "WEEKLY"
    case biweekly = "BIWEEKLY"
    case monthly = "MONTHLY"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: "Nenhuma"
        case .weekly: "Semanal"
        case .biweekly: "Quinzenal"
        case .monthly: "Mensal"
        }
    }
}

// MARK: - Datas pt-BR e calendário (semana começa no domingo, como no MVP)

enum AgendaFormat {
    static let locale = Locale(identifier: "pt_BR")

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.firstWeekday = 1 // domingo
        return calendar
    }()

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = format
        return formatter
    }

    static let time = formatter("HH:mm")
    static let dayMonth = formatter("dd/MM")
    static let weekday = formatter("EEEE")
    static let weekdayShort = formatter("EEE")
    static let monthYear = formatter("MMMM yyyy")
    static let monthName = formatter("MMMM")
    static let dayOnly = formatter("d")
    static let dayOfMonthLong = formatter("d 'de' MMMM")
    /// "Domingo, 13 de julho"
    static let fullDate = formatter("EEEE, d 'de' MMMM")

    static let isoQuery: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func capitalizedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    static func startOfWeek(for date: Date) -> Date {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        return calendar.date(byAdding: .day, value: -(weekday - 1), to: day) ?? day
    }

    /// "Hoje" / "Amanhã" / "Terça"
    static func relativeDayTitle(_ day: Date) -> String {
        if calendar.isDateInToday(day) { return "Hoje" }
        if calendar.isDateInTomorrow(day) { return "Amanhã" }
        return capitalizedFirst(weekday.string(from: day))
    }

    /// "13–19 de julho" (ou "28 de jun – 4 de jul" cruzando meses)
    static func weekRangeLabel(start: Date) -> String {
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        if calendar.isDate(start, equalTo: end, toGranularity: .month) {
            return "\(dayOnly.string(from: start))–\(dayOfMonthLong.string(from: end))"
        }
        return "\(dayOfMonthLong.string(from: start)) – \(dayOfMonthLong.string(from: end))"
    }

    /// Agrupa sessões por dia (ordenadas por horário).
    static func sections(from sessions: [AgendaSession]) -> [(day: Date, sessions: [AgendaSession])] {
        let grouped = Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.startsAt) }
        return grouped.keys.sorted().map { day in
            (day, grouped[day]!.sorted { $0.startsAt < $1.startsAt })
        }
    }
}

// MARK: - PATCH com query string (?scope=this|future)
// O APIClient só expõe query no GET; aqui replicamos o mínimo com Bearer + refresh.

enum AgendaAPI {
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            if let date = fractional.date(from: value) ?? plain.date(from: value) {
                return date
            }
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Data inválida: \(value)"
            ))
        }
        return decoder
    }()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static func patch<Response: Decodable>(
        _ path: String,
        query: [String: String]
    ) async throws -> Response {
        try await patch(path, query: query, body: Optional<Int>.none)
    }

    static func patch<Body: Encodable, Response: Decodable>(
        _ path: String,
        query: [String: String],
        body: Body?
    ) async throws -> Response {
        let bodyData = try body.map { try encoder.encode($0) }
        return try await send(path: path, query: query, bodyData: bodyData, allowRetry: true)
    }

    private static func send<Response: Decodable>(
        path: String,
        query: [String: String],
        bodyData: Data?,
        allowRetry: Bool
    ) async throws -> Response {
        var components = URLComponents(
            url: AppConfig.apiBaseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PATCH"
        request.httpBody = bodyData
        if bodyData != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let token = APIClient.shared.accessTokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        if status == 401, allowRetry, let refresh = APIClient.shared.refreshHandler {
            if await refresh() {
                return try await send(path: path, query: query, bodyData: bodyData, allowRetry: false)
            }
            // Mesmo comportamento do APIClient: refresh falhou → sessão expirou.
            APIClient.shared.onSessionExpired()
        }
        guard (200 ..< 300).contains(status) else {
            let message = (try? JSONDecoder().decode(AgendaErrorBody.self, from: data))?.message
                ?? "Algo deu errado (código \(status)). Tente de novo."
            throw APIError(statusCode: status, message: message)
        }
        return try decoder.decode(Response.self, from: data)
    }
}

private struct AgendaErrorBody: Decodable {
    let message: String?
}

// MARK: - Badge de tipo (Online com pílula; Presencial texto simples, como no print)

struct AgendaTypeBadge: View {
    let isOnline: Bool

    var body: some View {
        if isOnline {
            HStack(spacing: 4) {
                Image(systemName: "video.fill")
                    .font(.system(size: 9, weight: .bold))
                Text("Online")
                    .font(Theme.body(11, weight: .bold))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(hex: 0xDDEAF3))
            .foregroundStyle(Color(hex: 0x3E637F))
            .clipShape(Capsule())
            // Sem isto a badge cede espaço quando o nome do paciente é longo e
            // "Online" quebra letra a letra (O/nl/in/e) — como no Presencial abaixo.
            .lineLimit(1)
            .fixedSize()
        } else {
            Text("Presencial")
                .font(Theme.body(12, weight: .semibold))
                .foregroundStyle(Theme.textPrimary.opacity(0.75))
                .lineLimit(1)
                .fixedSize()
        }
    }
}

// MARK: - Card de sessão (usado na agenda-lista, no dashboard e no mês)

struct AgendaSessionCardRow: View {
    let name: String
    let groupName: String?
    let groupColorHex: String?
    let isOnline: Bool
    let timeText: String
    var statusLabel: String? = nil // só quando != agendada
    var recurrenceLabel: String? = nil // só quando recorrente ("Semanal" etc.)
    /// `false` quando quem chama já desenha o card (pra encaixar ações extras
    /// dentro do mesmo ThemeCard, como as do Meet na agenda-lista).
    var withCard: Bool = true

    var body: some View {
        if withCard {
            ThemeCard(padding: 14) { content }
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 12) {
                InitialAvatar(name: name, colorHex: groupColorHex, size: 46)
                VStack(alignment: .leading, spacing: 5) {
                    Text(name)
                        .font(Theme.body(16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        AgendaTypeBadge(isOnline: isOnline)
                        if let groupName {
                            Text("·")
                                .foregroundStyle(Theme.textSecondary)
                            Text(groupName)
                                .font(Theme.body(12, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                        }
                        if let recurrenceLabel {
                            Text("·")
                                .foregroundStyle(Theme.textSecondary)
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 10, weight: .semibold))
                                Text(recurrenceLabel)
                                    .font(Theme.body(12, weight: .medium))
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                            .foregroundStyle(Theme.primary)
                        }
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(timeText)
                        .font(Theme.money(16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    if let statusLabel {
                        Text(statusLabel.uppercased())
                            .font(Theme.body(9, weight: .bold))
                            .foregroundStyle(statusColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(statusColor.opacity(0.14))
                            .clipShape(Capsule())
                    }
                }
            }
        }

    private var statusColor: Color {
        switch statusLabel {
        case "Atendida": Theme.success
        case "Falta": Theme.warning
        case "Cancelada": Theme.danger
        default: Theme.textSecondary
        }
    }
}

extension AgendaSessionCardRow {
    init(session: AgendaSession, withCard: Bool = true) {
        self.init(
            name: session.patient.name,
            groupName: session.patient.group?.name,
            groupColorHex: session.patient.group?.color,
            isOnline: session.isOnline,
            timeText: AgendaFormat.time.string(from: session.startsAt),
            statusLabel: session.isScheduled ? nil : session.statusLabel,
            recurrenceLabel: session.isRecurring ? session.recurrenceLabel : nil,
            withCard: withCard
        )
    }
}

// MARK: - Cabeçalho de dia da lista ("Hoje domingo · 13/07" + "3 SESSÕES")

struct AgendaDayHeader: View {
    let day: Date
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(AgendaFormat.relativeDayTitle(day))
                .font(Theme.serifTitle(19))
                .foregroundStyle(Theme.textPrimary)
            // Hoje/Amanhã ganham o dia da semana no subtítulo; demais só a data
            Text(
                AgendaFormat.calendar.isDateInToday(day) || AgendaFormat.calendar.isDateInTomorrow(day)
                    ? "\(AgendaFormat.weekday.string(from: day)) · \(AgendaFormat.dayMonth.string(from: day))"
                    : AgendaFormat.dayMonth.string(from: day)
            )
            .font(Theme.body(13))
            .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(count == 1 ? "1 SESSÃO" : "\(count) SESSÕES")
                .font(Theme.body(10, weight: .bold))
                .tracking(0.6)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Theme.primarySoft)
                .foregroundStyle(Theme.success)
                .clipShape(Capsule())
        }
    }
}

// MARK: - Toast estilo MVP (pílula escura com "Desfazer" visual)

struct AgendaToastData: Equatable {
    var message: String
    var showUndo = true
}

private struct AgendaToastModifier: ViewModifier {
    @Binding var toast: AgendaToastData?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let toast {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color(hex: 0x8FD9B6))
                        Text(toast.message)
                            .font(Theme.body(14, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if toast.showUndo {
                            Text("DESFAZER")
                                .font(Theme.body(12, weight: .bold))
                                .tracking(0.8)
                                .foregroundStyle(Color(hex: 0x8FD9B6))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Theme.ink)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.35), value: toast)
            .task(id: toast) {
                guard toast != nil else { return }
                try? await Task.sleep(for: .seconds(3.2))
                toast = nil
            }
    }
}

extension View {
    func agendaToast(_ toast: Binding<AgendaToastData?>) -> some View {
        modifier(AgendaToastModifier(toast: toast))
    }
}
