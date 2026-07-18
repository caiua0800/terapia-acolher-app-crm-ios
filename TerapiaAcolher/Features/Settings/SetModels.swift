import Foundation
import SwiftUI

// MARK: - DTOs do módulo Configurações
// Prefixo Set* — reservado a este módulo (convenção do projeto).

/// GET/PUT settings/office
struct SetOffice: Decodable {
    var officeName: String?
    var address: String?
    var defaultSessionMinutes: Int
    var agenda: SetAgendaPrefs?

    enum CodingKeys: CodingKey { case officeName, address, defaultSessionMinutes, agenda }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        officeName = try container.decodeIfPresent(String.self, forKey: .officeName)
        address = try container.decodeIfPresent(String.self, forKey: .address)
        defaultSessionMinutes = try container.decodeIfPresent(Int.self, forKey: .defaultSessionMinutes) ?? 50
        // `agenda` é JSON livre no backend — decodifica de forma tolerante.
        agenda = try? container.decodeIfPresent(SetAgendaPrefs.self, forKey: .agenda)
    }
}

/// Preferências de agenda gravadas no JSON `agenda` de settings/office.
/// workDays em ISO: 1 = segunda … 7 = domingo.
struct SetAgendaPrefs: Codable, Equatable {
    var workDays: [Int]
    var startTime: String
    var endTime: String

    static let padrao = SetAgendaPrefs(workDays: [1, 2, 3, 4, 5], startTime: "08:00", endTime: "18:00")
}

/// GET patient-groups (DTO leve — não conflita com tipos do módulo Pacientes)
struct SetGroup: Decodable, Identifiable {
    let id: String
    var name: String
    var color: String?
    var patientCount: Int

    enum CodingKeys: CodingKey { case id, name, color, patientCount }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        color = try container.decodeIfPresent(String.self, forKey: .color)
        patientCount = try container.decodeIfPresent(Int.self, forKey: .patientCount) ?? 0
    }
}

/// Tipos de modelo (espelho do TemplateType do backend).
enum SetTemplateType: String, CaseIterable, Identifiable {
    case record = "RECORD"
    case anamnesis = "ANAMNESIS"
    case document = "DOCUMENT"
    case quickReply = "QUICK_REPLY"

    var id: String { rawValue }

    /// RECORD/ANAMNESIS usam form-builder; DOCUMENT/QUICK_REPLY usam texto.
    var isForm: Bool { self == .record || self == .anamnesis }

    var rowTitle: String {
        switch self {
        case .record: "Modelos de prontuário"
        case .anamnesis: "Modelos de anamnese"
        case .document: "Modelos de documentos"
        case .quickReply: "Respostas rápidas"
        }
    }

    var screenTitle: String {
        switch self {
        case .record: "Modelos · Prontuário"
        case .anamnesis: "Modelos · Anamnese"
        case .document: "Modelos · Documentos"
        case .quickReply: "Respostas rápidas"
        }
    }

    var icon: String {
        switch self {
        case .record: "doc.text"
        case .anamnesis: "pencil.line"
        case .document: "doc"
        case .quickReply: "bubble.left"
        }
    }

    var tint: Color {
        switch self {
        case .record: Theme.primary
        case .anamnesis: Color(hex: 0xB9A6D9)
        case .document: Color(hex: 0x7FA8C9)
        case .quickReply: Theme.warning
        }
    }

    var intro: String {
        if isForm {
            return "Cada modelo é um form-builder: adicione perguntas em texto livre, escolha única ou múltipla. Ao criar um novo \(self == .record ? "prontuário" : "registro de anamnese"), você seleciona um modelo como base — e pode personalizar durante o preenchimento."
        }
        return "Cada modelo é um texto com variáveis como {nome_paciente} e {valor}, substituídas automaticamente na hora de gerar. Toque em { } no editor para inserir uma variável."
    }
}

/// Pergunta do form-builder (RECORD/ANAMNESIS).
struct SetQuestion: Codable, Identifiable, Equatable {
    var id: String
    var label: String
    var kind: String // "text" | "single" | "multiple"
    var options: [String]?
    var isRequired: Bool?

    enum CodingKeys: String, CodingKey {
        case id, label, kind, options
        case isRequired = "required"
    }

    static func nova() -> SetQuestion {
        SetQuestion(id: UUID().uuidString, label: "", kind: "text", options: nil, isRequired: false)
    }

    var kindLabel: String {
        switch kind {
        case "single": "Escolha única"
        case "multiple": "Múltipla escolha"
        default: "Texto livre"
        }
    }
}

/// Schema do modelo: questions (form) OU content (texto).
struct SetTemplateSchema: Codable {
    var questions: [SetQuestion]?
    var content: String?
}

/// GET templates?type=
struct SetTemplate: Decodable, Identifiable {
    let id: String
    let type: String
    var name: String
    var schema: SetTemplateSchema
    let isSystem: Bool
    let active: Bool
    var usageCount: Int?
    var patientsInUse: Int?

    enum CodingKeys: CodingKey { case id, type, name, schema, isSystem, active, usageCount, patientsInUse }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        name = try container.decode(String.self, forKey: .name)
        schema = (try? container.decode(SetTemplateSchema.self, forKey: .schema)) ?? SetTemplateSchema()
        isSystem = try container.decodeIfPresent(Bool.self, forKey: .isSystem) ?? false
        active = try container.decodeIfPresent(Bool.self, forKey: .active) ?? true
        usageCount = try container.decodeIfPresent(Int.self, forKey: .usageCount)
        patientsInUse = try container.decodeIfPresent(Int.self, forKey: .patientsInUse)
    }
}

/// GET integrations/google/status
struct SetGoogleStatus: Decodable {
    let connected: Bool
    let googleEmail: String?
}

/// GET integrations/google/auth-url
struct SetAuthURL: Decodable {
    let url: String
}

/// GET settings/avatar · GET settings/signature · POST (retornam { url })
struct SetImageURL: Decodable {
    let url: String?
}

/// POST templates/restore-defaults
struct SetRestoreResult: Decodable {
    let restored: Int
}

/// Variáveis suportadas pelos modelos de documento/resposta rápida
/// (espelho do documents.service do backend).
enum SetTemplateVariable: String, CaseIterable, Identifiable {
    case nomePaciente = "nome_paciente"
    case cpfPaciente = "cpf_paciente"
    case nomeTerapeuta = "nome_terapeuta"
    case registroProfissional = "registro_profissional"
    case dataHoje = "data_hoje"
    case mesReferencia = "mes_referencia"
    case valor = "valor"
    case valorExtenso = "valor_extenso"

    var id: String { rawValue }
    var placeholder: String { "{\(rawValue)}" }

    var label: String {
        switch self {
        case .nomePaciente: "Nome do paciente"
        case .cpfPaciente: "CPF do paciente"
        case .nomeTerapeuta: "Nome do terapeuta"
        case .registroProfissional: "Registro profissional"
        case .dataHoje: "Data de hoje"
        case .mesReferencia: "Mês de referência"
        case .valor: "Valor"
        case .valorExtenso: "Valor por extenso"
        }
    }
}

// MARK: - Chamada com query em POST
// O APIClient público não expõe query string em POST (restore-defaults exige
// ?type=). Helper mínimo reaproveitando token e refresh do APIClient.

enum SetAPI {
    private struct ErrorBody: Decodable { let message: String? }

    static func postQuery<Response: Decodable>(
        _ path: String,
        query: [String: String],
        allowRetry: Bool = true
    ) async throws -> Response {
        var components = URLComponents(
            url: AppConfig.apiBaseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        if let token = APIClient.shared.accessTokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        if status == 401, allowRetry, let refresh = APIClient.shared.refreshHandler {
            if await refresh() {
                return try await postQuery(path, query: query, allowRetry: false)
            }
            // Mesmo comportamento do APIClient: refresh falhou → sessão expirou.
            APIClient.shared.onSessionExpired()
        }
        guard (200 ..< 300).contains(status) else {
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.message
                ?? "Algo deu errado (código \(status)). Tente de novo."
            throw APIError(statusCode: status, message: message)
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}

// MARK: - Componentes visuais compartilhados do módulo

/// Cabeçalho de seção (CONSULTÓRIO, TEMPLATES…) — uppercase com tracking.
struct SetSectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(Theme.body(11, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
            .tracking(1.2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}

/// Linha padrão de configurações: ícone em fundo suave + título + valor + chevron.
struct SetRow: View {
    let icon: String
    var iconColor: Color = Theme.primary
    let title: String
    var subtitle: String? = nil
    var trailing: String? = nil
    var showChevron = true

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 34, height: 34)
                .background(iconColor.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.body(15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.textSecondary)
            }
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary.opacity(0.6))
            }
        }
        .padding(.horizontal, Theme.cardPadding)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

extension View {
    /// Título serifado no centro da barra (padrão visual do app).
    func setToolbarTitle(_ title: String) -> some View {
        toolbar {
            ToolbarItem(placement: .principal) {
                Text(title)
                    .font(Theme.serifTitle(19))
                    .foregroundStyle(Theme.textPrimary)
            }
        }
    }
}
