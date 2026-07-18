import Foundation

// MARK: - Payload do GET /dashboard (espelho do DashboardService)

struct DashPayload: Decodable {
    let greetingName: String
    let today: DashToday
    let month: DashMonth
    let nextSessions: [DashNextSession]
}

struct DashToday: Decodable {
    let total: Int
    let online: Int
    let toCharge: Int
    let unreadNotifications: Int
}

struct DashMonth: Decodable {
    let sessions: Int
    let attended: Int
    let attendanceRate: Int
    let missed: Int
    let revenue: Double
    let revenueVariationPercent: Int
    let sessionsVariationPercent: Int
}

/// Próxima sessão (subset — sem status/price).
struct DashNextSession: Decodable, Identifiable, Hashable {
    let id: String
    let startsAt: Date
    let endsAt: Date
    let type: String
    let meetLink: String?
    let patient: AgendaSessionPatient

    var isOnline: Bool { type == "ONLINE" }
}
