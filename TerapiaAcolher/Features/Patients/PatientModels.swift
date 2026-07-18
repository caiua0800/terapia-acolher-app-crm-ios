import Foundation

// MARK: - Modelos (shapes fiéis ao backend NestJS)

/// Grupo de pacientes (GET /patient-groups).
struct PatientGroup: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let color: String?
    var sortOrder: Int? = nil
    var patientCount: Int? = nil
}

/// Grupo embutido nas respostas de paciente ({ id, name, color }).
struct PatientGroupRef: Codable, Hashable {
    let id: String
    let name: String
    let color: String?
}

/// Próxima sessão embutida na listagem (patients.service.findAll).
struct PatientNextSession: Codable, Hashable {
    let id: String
    let startsAt: Date
    let endsAt: Date
    let type: String // PRESENCIAL | ONLINE
}

/// Item da listagem (GET /patients).
struct Patient: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let status: String // ACTIVE | INACTIVE
    let group: PatientGroupRef?
    let cpfMasked: String?
    let email: String?
    let whatsapp: String?
    let registrationActive: Bool
    let nextSession: PatientNextSession?

    var isActive: Bool { status == "ACTIVE" }
}

/// Estatísticas da ficha (GET /patients/:id).
struct PatientStats: Codable, Hashable {
    let totalSessions: Int
    let attended: Int
    let missed: Int
}

/// Ficha completa (GET /patients/:id). `cpf` só vem com ?revealCpf=true.
struct PatientDetail: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let status: String
    let group: PatientGroupRef?
    let cpfMasked: String?
    let cpf: String?
    let email: String?
    let whatsapp: String?
    let birthDate: Date?
    let guardianName: String?
    let guardianContact: String?
    let guardianIsPayer: Bool
    let sessionPrice: Double?
    let billingDay: Int?
    let monthlyBillingReminder: Bool
    let sessionReminder24h: Bool
    let videoReminder1h: Bool
    let registrationActive: Bool
    let notes: String?
    let createdAt: Date
    let updatedAt: Date
    let stats: PatientStats?
    let pendingBalance: Double?
}

/// Payload de cadastro/edição (POST/PATCH /patients).
///
/// O PATCH do backend ignora chaves AUSENTES; limpar um campo exige `null`
/// explícito no JSON. Como o JSONEncoder omite nil por padrão, o encode é
/// customizado: em modo edição (`emitsExplicitNulls`), campos opcionais que o
/// usuário limpou saem como `null`; no CREATE, nil continua omitido.
struct PatientPayload: Encodable {
    var name: String
    var groupId: String?
    var cpf: String?
    var email: String?
    var whatsapp: String?
    var birthDate: Date?
    var guardianName: String?
    var guardianContact: String?
    var guardianIsPayer: Bool?
    var sessionPrice: Double?
    var billingDay: Int?
    var monthlyBillingReminder: Bool?
    var sessionReminder24h: Bool?
    var videoReminder1h: Bool?
    var registrationActive: Bool?
    var status: String?

    /// true no PATCH de edição: campos limpos viram `null` explícito.
    var emitsExplicitNulls = false

    private enum CodingKeys: String, CodingKey {
        case name, groupId, cpf, email, whatsapp, birthDate
        case guardianName, guardianContact, guardianIsPayer
        case sessionPrice, billingDay
        case monthlyBillingReminder, sessionReminder24h, videoReminder1h
        case registrationActive, status
    }

    /// birthDate é dia-calendário: serializa o dia LOCAL escolhido no picker
    /// como "yyyy-MM-dd" (o backend interpreta como meia-noite UTC).
    private static let isoDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try encodeClearable(groupId, forKey: .groupId, into: &container)
        // CPF nunca é pré-preenchido no form: ausente = "manter" (nunca null).
        if let cpf { try container.encode(cpf, forKey: .cpf) }
        try encodeClearable(email, forKey: .email, into: &container)
        try encodeClearable(whatsapp, forKey: .whatsapp, into: &container)
        try encodeClearable(
            birthDate.map { Self.isoDay.string(from: $0) },
            forKey: .birthDate,
            into: &container
        )
        try encodeClearable(guardianName, forKey: .guardianName, into: &container)
        try encodeClearable(guardianContact, forKey: .guardianContact, into: &container)
        if let guardianIsPayer { try container.encode(guardianIsPayer, forKey: .guardianIsPayer) }
        try encodeClearable(sessionPrice, forKey: .sessionPrice, into: &container)
        if let billingDay { try container.encode(billingDay, forKey: .billingDay) }
        if let monthlyBillingReminder {
            try container.encode(monthlyBillingReminder, forKey: .monthlyBillingReminder)
        }
        if let sessionReminder24h { try container.encode(sessionReminder24h, forKey: .sessionReminder24h) }
        if let videoReminder1h { try container.encode(videoReminder1h, forKey: .videoReminder1h) }
        if let registrationActive { try container.encode(registrationActive, forKey: .registrationActive) }
        if let status { try container.encode(status, forKey: .status) }
    }

    /// Campos que o update do backend aceita limpar com null.
    private func encodeClearable<Value: Encodable>(
        _ value: Value?,
        forKey key: CodingKeys,
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        if let value {
            try container.encode(value, forKey: key)
        } else if emitsExplicitNulls {
            try container.encodeNil(forKey: key)
        }
    }
}

struct PatientDeleteResponse: Decodable {
    let ok: Bool
    let purgeAfter: Date?
}

// MARK: - API

/// Chamadas de pacientes e grupos — camada fina sobre o APIClient.
enum PatientsAPI {
    static func groups() async throws -> [PatientGroup] {
        try await APIClient.shared.get("patient-groups")
    }

    static func list(
        status: String? = nil,
        groupId: String? = nil,
        search: String? = nil
    ) async throws -> [Patient] {
        try await APIClient.shared.get("patients", query: [
            "status": status,
            "groupId": groupId,
            "search": (search?.isEmpty ?? true) ? nil : search,
        ])
    }

    static func detail(id: String, revealCpf: Bool = false) async throws -> PatientDetail {
        try await APIClient.shared.get(
            "patients/\(id)",
            query: revealCpf ? ["revealCpf": "true"] : [:]
        )
    }

    static func create(_ payload: PatientPayload) async throws -> PatientDetail {
        try await APIClient.shared.post("patients", body: payload)
    }

    static func update(id: String, _ payload: PatientPayload) async throws -> PatientDetail {
        try await APIClient.shared.patch("patients/\(id)", body: payload)
    }

    static func delete(id: String) async throws -> PatientDeleteResponse {
        try await APIClient.shared.delete("patients/\(id)")
    }
}

// MARK: - Formatação PT-BR

enum PatientFormat {
    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = format
        return f
    }

    static let weekdayShort = formatter("EEE")
    static let monthYear = formatter("MMMM 'de' yyyy")
    static let dayMonth = formatter("dd/MM")
    static let time = formatter("HH:mm")
    static let fullDate = formatter("dd/MM/yyyy")

    /// birthDate é dia-calendário gravado à meia-noite UTC — exibir em UTC
    /// (formatar no fuso local mostraria o dia anterior no Brasil).
    static let fullDateUTC: DateFormatter = {
        let f = formatter("dd/MM/yyyy")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    /// Converte um dia-calendário UTC (meia-noite UTC) pra data com o MESMO
    /// dia no fuso local — pro DatePicker exibir/editar sem regredir 1 dia.
    static func localDate(fromUTCCalendarDay date: Date) -> Date {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        let comps = utcCalendar.dateComponents([.year, .month, .day], from: date)
        return Calendar.current.date(from: comps) ?? date
    }

    /// "Qui · 14h" / "Sex · 15h30" — próxima sessão na lista.
    static func nextSessionLabel(_ session: PatientNextSession?) -> String {
        guard let session else { return "Sem próxima sessão" }
        var day = weekdayShort.string(from: session.startsAt).replacingOccurrences(of: ".", with: "")
        day = day.prefix(1).uppercased() + day.dropFirst()
        let calendar = Calendar(identifier: .gregorian)
        let comps = calendar.dateComponents([.hour, .minute], from: session.startsAt)
        let hour = comps.minute == 0
            ? "\(comps.hour ?? 0)h"
            : "\(comps.hour ?? 0)h\(String(format: "%02d", comps.minute ?? 0))"
        return "\(day) · \(hour)"
    }

    /// "Paciente desde março de 2024".
    static func sinceLabel(_ date: Date) -> String {
        "Paciente desde \(monthYear.string(from: date))"
    }
}

// MARK: - Máscaras de digitação

enum PatientMask {
    /// CPF: 000.000.000-00
    static func cpf(_ raw: String) -> String {
        let digits = String(raw.filter(\.isNumber).prefix(11))
        var out = ""
        for (i, ch) in digits.enumerated() {
            if i == 3 || i == 6 { out += "." }
            if i == 9 { out += "-" }
            out.append(ch)
        }
        return out
    }

    /// WhatsApp: +55 (DD) 99999-9999
    static func whatsapp(_ raw: String) -> String {
        var digits = String(raw.filter(\.isNumber))
        if digits.hasPrefix("55") { digits = String(digits.dropFirst(2)) }
        digits = String(digits.prefix(11))
        guard !digits.isEmpty else { return "" }
        var out = "+55 ("
        for (i, ch) in digits.enumerated() {
            if i == 2 { out += ") " }
            if (digits.count > 10 && i == 7) || (digits.count <= 10 && digits.count > 6 && i == 6) {
                out += "-"
            }
            out.append(ch)
        }
        return out
    }

    /// Valor enviado à API: só dígitos com +55 (ex.: +5541991234567).
    /// A máscara com parênteses/hífen é apenas exibição.
    static func whatsappPayload(_ masked: String) -> String? {
        var digits = String(masked.filter(\.isNumber))
        if digits.hasPrefix("55") { digits = String(digits.dropFirst(2)) }
        guard !digits.isEmpty else { return nil }
        return "+55\(digits)"
    }
}
