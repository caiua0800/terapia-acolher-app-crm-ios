import SafariServices
import SwiftUI

// MARK: - Referência leve de paciente (DTO próprio de Documentos)

struct DocPatientRef: Codable, Identifiable, Hashable {
    let id: String
    let name: String
}

// MARK: - Documento gerado

struct DocItem: Decodable, Identifiable {
    let id: String
    let name: String
    let status: String // GENERATED | SIGNED
    let signedAt: Date?
    let createdAt: Date
    let templateId: String?
    let templateName: String?

    var isSigned: Bool { status == "SIGNED" }
}

// MARK: - Modelo de documento (Template DOCUMENT)

struct DocTemplate: Decodable, Identifiable {
    struct Schema: Decodable {
        let content: String?
    }

    let id: String
    let name: String
    let isSystem: Bool
    let schema: Schema?

    var content: String { schema?.content ?? "" }
}

struct DocGenerateBody: Encodable {
    var templateId: String
    var name: String?
    var variables: [String: String]?
}

struct DocDownloadResponse: Decodable {
    let url: String
}

struct DocDeleted: Decodable {
    let deleted: Bool
}

// MARK: - Chamadas de API

enum DocumentsAPI {
    static func patients(search: String?) async throws -> [DocPatientRef] {
        try await APIClient.shared.get("patients", query: ["search": search])
    }

    static func list(patientId: String) async throws -> [DocItem] {
        try await APIClient.shared.get("patients/\(patientId)/documents")
    }

    static func templates() async throws -> [DocTemplate] {
        try await APIClient.shared.get("templates", query: ["type": "DOCUMENT"])
    }

    static func generate(patientId: String, body: DocGenerateBody) async throws -> DocItem {
        try await APIClient.shared.post("patients/\(patientId)/documents", body: body)
    }

    static func downloadUrl(patientId: String, id: String) async throws -> DocDownloadResponse {
        try await APIClient.shared.get("patients/\(patientId)/documents/\(id)/download")
    }

    static func sign(patientId: String, id: String) async throws -> DocItem {
        try await APIClient.shared.post("patients/\(patientId)/documents/\(id)/sign")
    }

    static func remove(patientId: String, id: String) async throws -> DocDeleted {
        try await APIClient.shared.delete("patients/\(patientId)/documents/\(id)")
    }
}

// MARK: - Variáveis do modelo ({nome_paciente}, {valor}...)

enum DocVariables {
    /// Roxo das variáveis, como no editor do MVP.
    static let purple = Color(hex: 0x7E5FC0)
    static let purpleSoft = Color(hex: 0xEFE9F8)

    /// Variáveis preenchidas automaticamente pelo backend.
    static let automaticKeys: Set<String> = [
        "nome_paciente", "cpf_paciente", "data_hoje",
        "nome_terapeuta", "registro_profissional",
        "mes_referencia", "valor_extenso",
    ]

    /// Placeholders `{chave}` na ordem em que aparecem no conteúdo (sem repetição).
    static func placeholders(in content: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "\\{([a-zA-Z0-9_]+)\\}") else { return [] }
        let range = NSRange(content.startIndex..., in: content)
        var seen = Set<String>()
        var keys: [String] = []
        regex.enumerateMatches(in: content, range: range) { match, _, _ in
            guard let match, match.numberOfRanges > 1,
                  let keyRange = Range(match.range(at: 1), in: content) else { return }
            let key = String(content[keyRange])
            if seen.insert(key).inserted { keys.append(key) }
        }
        return keys
    }

    /// Variáveis que precisam de valor digitado pela terapeuta.
    static func extraKeys(in content: String) -> [String] {
        placeholders(in: content).filter { !automaticKeys.contains($0) }
    }

    /// "numero_de_sessoes" → "Número de sessões" (aproximação legível).
    static func label(for key: String) -> String {
        let known: [String: String] = [
            "valor": "Valor (R$)",
            "numero_de_sessoes": "Número de sessões",
            "mes_referencia": "Mês de referência",
        ]
        if let label = known[key] { return label }
        let words = key.replacingOccurrences(of: "_", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    /// Conteúdo do modelo com as variáveis destacadas em roxo (como no print do editor).
    static func highlighted(_ content: String) -> AttributedString {
        var result = AttributedString()
        var plain = AttributeContainer()
        plain.foregroundColor = Theme.textPrimary

        var variable = AttributeContainer()
        variable.foregroundColor = purple
        variable.backgroundColor = purpleSoft
        variable.font = .system(size: 13, weight: .semibold, design: .monospaced)

        guard let regex = try? NSRegularExpression(pattern: "\\{[a-zA-Z0-9_]+\\}") else {
            return AttributedString(content, attributes: plain)
        }

        let nsContent = content as NSString
        var cursor = 0
        let matches = regex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))
        for match in matches {
            if match.range.location > cursor {
                let text = nsContent.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                result += AttributedString(text, attributes: plain)
            }
            result += AttributedString(nsContent.substring(with: match.range), attributes: variable)
            cursor = match.range.location + match.range.length
        }
        if cursor < nsContent.length {
            result += AttributedString(
                nsContent.substring(from: cursor),
                attributes: plain
            )
        }
        return result
    }
}

// MARK: - Formatação e navegador in-app

enum DocFormat {
    static let dayMonthYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter
    }()

    static func relativeDay(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "hoje" }
        if Calendar.current.isDateInYesterday(date) { return "ontem" }
        return dayMonthYear.string(from: date)
    }
}

struct DocSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

struct DocWebLink: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
