import Foundation

// MARK: - Origem da agenda (2026-10-22)
//
// De onde vêm os compromissos da agenda: só as sessões do CRM ("Agenda
// Acolher", padrão), só a agenda do Google do terapeuta ("Minha Agenda") ou as
// duas ("Todos"). O seletor só existe com o Google conectado — sem ele, a
// agenda é sempre a Acolher. Mesma regra do web (`agenda/origem.tsx`).
//
// Este arquivo é só lógica (Foundation): filtro, duplicado, ordenação e datas
// ficam aqui para serem testados sem simulador.

enum AgendaOrigin: String, CaseIterable, Identifiable {
    case acolher = "Agenda Acolher"
    case mine = "Minha Agenda"
    case all = "Todos"

    var id: String { rawValue }

    var showsSessions: Bool { self != .mine }
    var showsGoogle: Bool { self != .acolher }
}

// MARK: - DTOs (GET sessions/google-agenda?from&to)

/// Compromisso da agenda do Google do terapeuta. Só leitura: tocar abre no
/// Google Agenda, nunca o detalhe de sessão.
struct GoogleAgendaEvent: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let startsAt: Date
    let endsAt: Date
    let allDay: Bool
    let meetLink: String?
    let htmlLink: String?
    /// É o convite que o CRM criou para uma sessão: em "Todos" não repete,
    /// a sessão já aparece como sessão da Agenda Acolher.
    let sessionId: String?

    private enum CodingKeys: String, CodingKey {
        case id, titulo, inicio, fim, diaTodo, meetLink, htmlLink, sessaoId
    }

    init(
        id: String, title: String, startsAt: Date, endsAt: Date, allDay: Bool,
        meetLink: String? = nil, htmlLink: String? = nil, sessionId: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.allDay = allDay
        self.meetLink = meetLink
        self.htmlLink = htmlLink
        self.sessionId = sessionId
    }

    /// Datas lidas como texto de propósito: o dia inteiro vem SEM fuso
    /// ("2026-10-22T00:00:00", meia-noite local) e o decodificador ISO do
    /// APIClient recusaria — e uma data recusada derrubaria a resposta toda.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawStart = try container.decode(String.self, forKey: .inicio)
        let rawEnd = try container.decode(String.self, forKey: .fim)
        guard let start = GoogleAgendaDates.parse(rawStart) else {
            throw DecodingError.dataCorruptedError(
                forKey: .inicio, in: container, debugDescription: "Data inválida: \(rawStart)"
            )
        }
        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .titulo) ?? "(sem título)"
        startsAt = start
        endsAt = GoogleAgendaDates.parse(rawEnd) ?? start
        allDay = try container.decodeIfPresent(Bool.self, forKey: .diaTodo) ?? false
        meetLink = try container.decodeIfPresent(String.self, forKey: .meetLink)
        htmlLink = try container.decodeIfPresent(String.self, forKey: .htmlLink)
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessaoId)
    }

    /// "14:00 – 15:00" ou "Dia inteiro".
    var timeLabel: String {
        allDay
            ? "Dia inteiro"
            : "\(GoogleAgendaDates.time.string(from: startsAt)) – \(GoogleAgendaDates.time.string(from: endsAt))"
    }

    /// Abre no Google Agenda (app, se instalado, ou navegador).
    var url: URL? {
        guard let htmlLink, !htmlLink.isEmpty else { return nil }
        return URL(string: htmlLink)
    }

    /// Ocupa algum pedaço de [início, fim) — dia inteiro de vários dias
    /// aparece em cada um deles.
    func overlaps(from start: Date, to end: Date) -> Bool {
        let eventEnd = endsAt > startsAt ? endsAt : startsAt.addingTimeInterval(1)
        return startsAt < end && eventEnd > start
    }
}

struct GoogleAgendaPayload: Decodable {
    let conectado: Bool
    let erro: Bool
    let eventos: [GoogleAgendaEvent]
}

enum GoogleAgendaDates {
    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Sem fuso = horário local do aparelho (dia inteiro do Google).
    private static let local: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()

    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static func parse(_ value: String) -> Date? {
        isoFractional.date(from: value) ?? iso.date(from: value) ?? local.date(from: value)
    }
}

// MARK: - Linha do tempo: sessões e compromissos do Google juntos

enum AgendaItem: Identifiable, Hashable {
    case session(AgendaSession)
    case google(GoogleAgendaEvent)

    var id: String {
        switch self {
        case .session(let session): "s-\(session.id)"
        case .google(let event): "g-\(event.id)"
        }
    }

    var startsAt: Date {
        switch self {
        case .session(let session): session.startsAt
        case .google(let event): event.startsAt
        }
    }

    var isSession: Bool {
        if case .session = self { return true }
        return false
    }
}

enum AgendaTimeline {
    /// Pedaços de até 60 dias: o backend aceita no máximo 62 por consulta e a
    /// lista pode cobrir meses.
    static let maxChunkDays = 60

    /// Eventos do Google que a origem mostra, por horário. Em "Todos" some o
    /// convite de sessão (tem `sessionId`): a sessão já está na tela.
    static func visibleEvents(_ events: [GoogleAgendaEvent], origin: AgendaOrigin) -> [GoogleAgendaEvent] {
        let list: [GoogleAgendaEvent]
        switch origin {
        case .acolher: return []
        case .mine: list = events
        case .all: list = events.filter { $0.sessionId == nil }
        }
        return list.sorted { $0.startsAt < $1.startsAt }
    }

    /// Sessões e eventos na mesma ordem de horário. No empate a sessão vem
    /// primeiro — é o que o terapeuta atende.
    static func merge(
        sessions: [AgendaSession],
        events: [GoogleAgendaEvent],
        origin: AgendaOrigin
    ) -> [AgendaItem] {
        let fromSessions = origin.showsSessions ? sessions.map(AgendaItem.session) : []
        let fromGoogle = visibleEvents(events, origin: origin).map(AgendaItem.google)
        return (fromSessions + fromGoogle).enumerated().sorted { lhs, rhs in
            if lhs.element.startsAt != rhs.element.startsAt {
                return lhs.element.startsAt < rhs.element.startsAt
            }
            if lhs.element.isSession != rhs.element.isSession { return lhs.element.isSession }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// Agrupa pelo dia de início (a lista é agrupada por dia).
    static func sections(_ items: [AgendaItem], calendar: Calendar) -> [(day: Date, items: [AgendaItem])] {
        var order: [Date] = []
        var grouped: [Date: [AgendaItem]] = [:]
        for item in items {
            let day = calendar.startOfDay(for: item.startsAt)
            if grouped[day] == nil { order.append(day) }
            grouped[day, default: []].append(item)
        }
        return order.sorted().map { ($0, grouped[$0] ?? []) }
    }

    /// Eventos que ocupam o dia (o dia tocado no mês).
    static func events(on day: Date, in events: [GoogleAgendaEvent], calendar: Calendar) -> [GoogleAgendaEvent] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return events.filter { $0.overlaps(from: start, to: end) }
    }

    /// Contagem por dia do mês, com a mesma regra do dia tocado: o número da
    /// célula bate com o que aparece embaixo ao tocar.
    static func countsByDay(_ events: [GoogleAgendaEvent], monthAnchor: Date, calendar: Calendar) -> [Int: Int] {
        guard let range = calendar.range(of: .day, in: .month, for: monthAnchor) else { return [:] }
        var components = calendar.dateComponents([.year, .month], from: monthAnchor)
        var counts: [Int: Int] = [:]
        for day in range {
            components.day = day
            guard let date = calendar.date(from: components) else { continue }
            let count = Self.events(on: date, in: events, calendar: calendar).count
            if count > 0 { counts[day] = count }
        }
        return counts
    }

    static func chunks(from: Date, to: Date, maxDays: Int = maxChunkDays) -> [(from: Date, to: Date)] {
        var result: [(Date, Date)] = []
        var start = from
        while start < to {
            let end = min(to, start.addingTimeInterval(TimeInterval(maxDays) * 86_400))
            result.append((start, end))
            start = end
        }
        return result
    }
}
