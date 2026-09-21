import Foundation

// MARK: - Transcrições por paciente
//
// A transcrição da sessão já existia no detalhe da sessão (Agenda). O que
// faltava no app era o caminho do web: escolher o paciente e ver todas as
// sessões transcritas dele num lugar só — quem procura uma conversa antiga não
// lembra a data exata, lembra de quem era.

/// Cabeçalho da transcrição na listagem: sem as falas, que só vêm ao abrir.
/// (session-transcripts.service.ts → `ResumoDeTranscricao`)
struct TranscriptSummary: Decodable, Identifiable, Hashable {
    let id: String
    let iniciadaEm: Date?
    let terminadaEm: Date?
    let participantes: [String]
    let trechos: Int
    let criadaEm: Date
    let documentoApagadoDoDrive: Bool
}

/// Uma sessão do paciente e as transcrições que ela produziu.
struct SessionWithTranscripts: Decodable, Identifiable, Hashable {
    let sessionId: String
    let iniciaEm: Date
    let terminaEm: Date
    let tipo: String    // PRESENCIAL | ONLINE
    let status: String  // SCHEDULED | ATTENDED | MISSED | CANCELED
    let transcricoes: [TranscriptSummary]

    var id: String { sessionId }

    /// Uma sessão só tem mais de uma quando a sala do Meet foi redefinida no
    /// meio; as descartadas o backend já tira fora.
    var principal: TranscriptSummary? { transcricoes.first }
}

/// GET patients/<id>/transcricoes
struct PatientTranscripts: Decodable {
    let patientId: String
    let total: Int
    let sessoes: [SessionWithTranscripts]
}

enum TranscriptsAPI {
    static func doPaciente(_ patientId: String) async throws -> PatientTranscripts {
        try await APIClient.shared.get("patients/\(patientId)/transcricoes")
    }

    /// Mesma rota usada pelo detalhe da sessão — o conteúdo é o mesmo, então a
    /// folha de leitura também é a mesma (`AgendaTranscriptSheet`).
    static func daSessao(_ sessionId: String) async throws -> AgendaTranscriptResponse {
        try await APIClient.shared.get("sessions/\(sessionId)/transcricao")
    }
}
