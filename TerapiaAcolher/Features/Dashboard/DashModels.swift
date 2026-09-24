import Foundation

// MARK: - Payload do GET /dashboard (espelho do DashboardService)

struct DashPayload: Decodable {
    let greetingName: String
    let today: DashToday
    let month: DashMonth
    let nextSessions: [DashNextSession]
    // Opcionais: o app pode chegar ao terapeuta antes do backend que os manda.
    let patients: DashPatients?
    let receivables: DashReceivables?
    let week: DashWeek?
    /// Receita dos últimos 6 meses, do mais antigo ao atual ("AAAA-MM").
    let revenueHistory: [DashRevenueMonth]?
    let usage: DashUsage?
}

struct DashPatients: Decodable {
    let active: Int
    let newThisMonth: Int
}

struct DashReceivables: Decodable {
    let count: Int
    let amount: Double
    let overdueCount: Int
    let overdueAmount: Double
}

struct DashWeek: Decodable {
    let sessions: Int
}

struct DashRevenueMonth: Decodable, Identifiable {
    let month: String
    let revenue: Double
    var id: String { month }
}

struct DashUsage: Decodable {
    let whatsapp: Int
    let transcriptSummaries: Int
    let recordAi: Int
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
