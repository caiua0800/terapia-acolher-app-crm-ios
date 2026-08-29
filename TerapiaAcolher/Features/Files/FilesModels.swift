import SafariServices
import SwiftUI

// MARK: - Referência leve de paciente (DTO próprio de Arquivos)

struct PFilePatientRef: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let group: PFilePatientGroup?
}

struct PFilePatientGroup: Codable, Hashable {
    let color: String?
}

extension PFilePatientRef {
    /// Ponte a partir da ficha do paciente — documentos e anexos são acessados
    /// de dentro do paciente, não por uma lista própria.
    init(from detail: PatientDetail) {
        self.init(
            id: detail.id,
            name: detail.name,
            group: PFilePatientGroup(color: detail.group?.color)
        )
    }
}

// MARK: - Categoria de anexo (enum do backend)

enum PFileCategory: String, Codable, CaseIterable {
    case exam = "EXAM"
    case image = "IMAGE"
    case pdf = "PDF"
    case letter = "LETTER"
    case other = "OTHER"

    var label: String {
        switch self {
        case .exam: "Exame"
        case .image: "Imagem"
        case .pdf: "PDF"
        case .letter: "Carta"
        case .other: "Outro"
        }
    }
}

// MARK: - Anexo do paciente

struct PFileItem: Decodable, Identifiable {
    let id: String
    let fileName: String
    let mimeType: String
    let sizeBytes: Int
    let category: PFileCategory
    let createdAt: Date

    /// Extensão em caixa alta pro selo do ícone (PDF, JPG, DOCX...).
    var extensionLabel: String {
        let ext = (fileName as NSString).pathExtension.uppercased()
        if !ext.isEmpty { return String(ext.prefix(4)) }
        switch mimeType {
        case "application/pdf": return "PDF"
        case "image/jpeg": return "JPG"
        case "image/png": return "PNG"
        case "image/webp": return "WEBP"
        case "image/heic", "image/heif": return "HEIC"
        case "application/msword": return "DOC"
        case "application/vnd.openxmlformats-officedocument.wordprocessingml.document": return "DOCX"
        default: return "ARQ"
        }
    }

    /// Cores do ícone por tipo, como no print (PDF vermelho suave, JPG âmbar, DOCX lilás).
    var iconColors: (foreground: Color, background: Color) {
        switch extensionLabel {
        case "PDF": (Color(hex: 0xC96560), Color(hex: 0xFBEAE9))
        case "JPG", "JPEG", "PNG", "WEBP", "HEIC": (Color(hex: 0xB98A3F), Color(hex: 0xF8EFDC))
        case "DOC", "DOCX": (Color(hex: 0x7E5FC0), Color(hex: 0xEFE9F8))
        default: (Theme.textSecondary, Theme.border.opacity(0.5))
        }
    }
}

struct PFileListResponse: Decodable {
    let files: [PFileItem]
    let count: Int
    let totalSizeBytes: Int
}

struct PFileDownloadResponse: Decodable {
    let url: String
}

struct PFileUpdateBody: Encodable {
    var fileName: String?
    var category: String?
}

struct PFileDeleted: Decodable {
    let deleted: Bool
}

// MARK: - Chamadas de API

enum PFilesAPI {
    static func patients(search: String?) async throws -> [PFilePatientRef] {
        try await APIClient.shared.get("patients", query: ["search": search])
    }

    static func list(patientId: String, category: PFileCategory?) async throws -> PFileListResponse {
        try await APIClient.shared.get("patients/\(patientId)/files", query: [
            "category": category?.rawValue,
        ])
    }

    static func upload(
        patientId: String,
        data: Data,
        fileName: String,
        mimeType: String,
        category: PFileCategory?
    ) async throws -> PFileItem {
        try await APIClient.shared.upload(
            "patients/\(patientId)/files",
            fileData: data,
            fileName: fileName,
            mimeType: mimeType,
            extraFields: category.map { ["category": $0.rawValue] } ?? [:]
        )
    }

    static func downloadUrl(patientId: String, id: String) async throws -> PFileDownloadResponse {
        try await APIClient.shared.get("patients/\(patientId)/files/\(id)/download")
    }

    static func update(patientId: String, id: String, body: PFileUpdateBody) async throws -> PFileItem {
        try await APIClient.shared.patch("patients/\(patientId)/files/\(id)", body: body)
    }

    static func remove(patientId: String, id: String) async throws -> PFileDeleted {
        try await APIClient.shared.delete("patients/\(patientId)/files/\(id)")
    }
}

// MARK: - Formatação e navegador in-app

enum PFileFormat {
    static let dayMonth: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM"
        return formatter
    }()

    static func size(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    static func relativeDay(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "adicionado hoje" }
        if Calendar.current.isDateInYesterday(date) { return "ontem" }
        return dayMonth.string(from: date)
    }
}

struct PFileSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

struct PFileWebLink: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
