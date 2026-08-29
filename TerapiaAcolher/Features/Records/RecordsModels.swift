import Foundation

// MARK: - Tipo de registro (prontuário × anamnese)
// Recriado aqui após remoção do placeholder — o MainShellView usa RecordsHomeView(kind:).

enum RecordsKind {
    case record, anamnesis

    /// Valor da API (RecordEntryKind / TemplateType do backend).
    var apiValue: String {
        switch self {
        case .record: "RECORD"
        case .anamnesis: "ANAMNESIS"
        }
    }

    var title: String {
        switch self {
        case .record: "Prontuários"
        case .anamnesis: "Anamneses"
        }
    }

    var singular: String {
        switch self {
        case .record: "prontuário"
        case .anamnesis: "anamnese"
        }
    }

    var newTitle: String {
        switch self {
        case .record: "Novo registro"
        case .anamnesis: "Nova anamnese"
        }
    }
}

// MARK: - Referência leve de paciente usada nas telas de registros

struct RecPatientRef: Identifiable, Hashable {
    let id: String
    let name: String
    let groupName: String?
    let groupColor: String?

    init(from patient: Patient) {
        id = patient.id
        name = patient.name
        groupName = patient.group?.name
        groupColor = patient.group?.color
    }

    init(from detail: PatientDetail) {
        id = detail.id
        name = detail.name
        groupName = detail.group?.name
        groupColor = detail.group?.color
    }
}

// MARK: - Form-builder (schema dos modelos)

struct RecQuestion: Codable, Identifiable, Hashable {
    let id: String
    let label: String
    let kind: String // text | single | multiple
    let options: [String]?
    let required: Bool?
    /// Pergunta vedada à IA (natureza diagnóstica) — o terapeuta preenche à mão.
    let aiExcluded: Bool?

    var isRequired: Bool { required ?? false }
    var isAiExcluded: Bool { aiExcluded ?? false }
}

struct RecSchema: Codable, Hashable {
    let questions: [RecQuestion]?
}

/// Resposta de uma pergunta: texto (text/single) ou lista (multiple).
enum RecAnswer: Codable, Hashable {
    case text(String)
    case list([String])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .text(text)
        } else {
            self = .list(try container.decode([String].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .text(value): try container.encode(value)
        case let .list(values): try container.encode(values)
        }
    }

    var textValue: String? { if case let .text(v) = self { v } else { nil } }
    var listValue: [String]? { if case let .list(v) = self { v } else { nil } }
}

// MARK: - Modelos (GET /templates?type=)

struct RecTemplate: Codable, Identifiable, Hashable {
    let id: String
    let type: String
    let name: String
    let schema: RecSchema?
    let isSystem: Bool
    let active: Bool
    let usageCount: Int?
    let patientsInUse: Int?

    var questions: [RecQuestion] { schema?.questions ?? [] }
}

// MARK: - Registros (GET /patients/:id/records)

struct RecEntryTemplateRef: Codable, Hashable {
    let id: String
    let name: String
    let schema: RecSchema?
}

/// Item da timeline (lista leve, sem respostas).
struct RecEntrySummary: Codable, Identifiable, Hashable {
    let id: String
    let kind: String
    let title: String
    let entryDate: Date
    let createdAt: Date
    let updatedAt: Date
    let template: RecEntryTemplateRef?
}

/// Registro completo com respostas decifradas + schema do modelo.
struct RecEntryDetail: Codable, Identifiable, Hashable {
    let id: String
    let patientId: String
    let kind: String
    let title: String
    let answers: [String: RecAnswer]
    let entryDate: Date
    let template: RecEntryTemplateRef?
    let createdAt: Date
    let updatedAt: Date
}

struct RecEntryCreatePayload: Encodable {
    let templateId: String?
    let kind: String
    let title: String?
    let answers: [String: RecAnswer]
    let entryDate: Date?
    /// Rascunho de IA que originou as respostas — alimenta a taxa de aceitação.
    var aiDraftId: String? = nil
}

// MARK: - IA (organizar rascunho nos campos)

struct RecAiStatus: Decodable {
    let enabled: Bool
    let model: String
}

struct RecDraftPayload: Encodable {
    let kind: String
    let templateId: String
    let text: String
}

struct RecDraftExcluded: Decodable, Hashable {
    let id: String
    let label: String
}

struct RecDraftResponse: Decodable {
    let draftId: String
    let answers: [String: RecAnswer]
    /// Ids que a IA conseguiu preencher.
    let filled: [String]
    /// Ids elegíveis que ficaram em branco (o texto não trazia a informação).
    let blank: [String]
    /// Campos que nunca vão à IA (diagnóstico).
    let excluded: [RecDraftExcluded]
    let model: String
}

struct RecEntryUpdatePayload: Encodable {
    let title: String?
    let answers: [String: RecAnswer]?
}

struct RecDeletedResponse: Decodable {
    let deleted: Bool
}

// MARK: - Anotações de sessão (GET /patients/:id/notes)

struct RecNote: Codable, Identifiable, Hashable {
    let id: String
    let patientId: String
    let sessionId: String?
    let content: String
    let tag: String?
    let noteDate: Date
    let createdAt: Date
    let updatedAt: Date
}

struct RecNotePayload: Encodable {
    let content: String
    let tag: String?
    let noteDate: Date?
}

// MARK: - API

enum RecordsAPI {
    static func templates(kind: RecordsKind) async throws -> [RecTemplate] {
        try await APIClient.shared.get("templates", query: ["type": kind.apiValue])
    }

    static func entries(patientId: String, kind: RecordsKind) async throws -> [RecEntrySummary] {
        try await APIClient.shared.get("patients/\(patientId)/records", query: ["kind": kind.apiValue])
    }

    static func entry(patientId: String, id: String) async throws -> RecEntryDetail {
        try await APIClient.shared.get("patients/\(patientId)/records/\(id)")
    }

    static func createEntry(patientId: String, _ payload: RecEntryCreatePayload) async throws -> RecEntryDetail {
        try await APIClient.shared.post("patients/\(patientId)/records", body: payload)
    }

    static func updateEntry(patientId: String, id: String, _ payload: RecEntryUpdatePayload) async throws -> RecEntryDetail {
        try await APIClient.shared.patch("patients/\(patientId)/records/\(id)", body: payload)
    }

    static func deleteEntry(patientId: String, id: String) async throws {
        let _: RecDeletedResponse = try await APIClient.shared.delete("patients/\(patientId)/records/\(id)")
    }

    /// Cacheado no processo: o status não muda durante a sessão do app.
    private static var cachedAiStatus: RecAiStatus?

    static func aiStatus() async throws -> RecAiStatus {
        if let cachedAiStatus { return cachedAiStatus }
        let status: RecAiStatus = try await APIClient.shared.get("ai/status")
        cachedAiStatus = status
        return status
    }

    /// Organiza o rascunho digitado nos campos do modelo. Não salva nada.
    static func draftRecord(patientId: String, _ payload: RecDraftPayload) async throws -> RecDraftResponse {
        try await APIClient.shared.post("patients/\(patientId)/records/draft", body: payload)
    }

    static func notes(patientId: String) async throws -> [RecNote] {
        try await APIClient.shared.get("patients/\(patientId)/notes")
    }

    static func createNote(patientId: String, _ payload: RecNotePayload) async throws -> RecNote {
        try await APIClient.shared.post("patients/\(patientId)/notes", body: payload)
    }

    static func updateNote(patientId: String, id: String, _ payload: RecNotePayload) async throws -> RecNote {
        try await APIClient.shared.patch("patients/\(patientId)/notes/\(id)", body: payload)
    }

    static func deleteNote(patientId: String, id: String) async throws {
        let _: RecDeletedResponse = try await APIClient.shared.delete("patients/\(patientId)/notes/\(id)")
    }
}

// MARK: - Formatação PT-BR

enum RecFormat {
    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = format
        return f
    }

    static let dayMonth = formatter("dd/MM")
    static let time = formatter("HH:mm")
    static let fullDate = formatter("dd 'de' MMMM 'de' yyyy")

    /// "HOJE · 14:52" / "ONTEM · 15:30" / "08/07 · 15:30" (timeline de anotações).
    static func timelineLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        let day: String
        if calendar.isDateInToday(date) {
            day = "HOJE"
        } else if calendar.isDateInYesterday(date) {
            day = "ONTEM"
        } else {
            day = dayMonth.string(from: date)
        }
        return "\(day) · \(time.string(from: date))"
    }
}
