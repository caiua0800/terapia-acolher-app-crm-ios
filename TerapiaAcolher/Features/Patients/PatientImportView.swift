import SwiftUI
import UniformTypeIdentifiers

// MARK: - Modelos da API de importação (POST imports/preview → execute)

struct ImportField: Decodable, Identifiable, Hashable {
    let key: String
    let label: String
    let required: Bool

    var id: String { key }
}

/// Palpite do servidor para uma coluna do arquivo.
struct ImportSuggestion: Decodable {
    let column: String
    let field: String?
    /// `header` = reconheceu pelo nome da coluna. `content` = pelo formato dos valores.
    let reason: String?
    let confidence: String?
}

/// Linha que já existe na base do terapeuta.
struct ImportDuplicate: Decodable, Identifiable {
    let row: Int
    let name: String
    let matchedBy: String
    /// `certa` (CPF ou e-mail bateram) ou `provavel` (só o nome).
    let confidence: String
    let patientId: String

    var id: Int { row }
    var motivo: String {
        switch matchedBy {
        case "cpf": "mesmo CPF"
        case "email": "mesmo e-mail"
        default: "mesmo nome"
        }
    }
}

struct ImportRepeated: Decodable, Identifiable {
    let row: Int
    let name: String
    let motivo: String

    var id: Int { row }
}

struct ImportDuplicates: Decodable {
    let existing: [ImportDuplicate]
    let repeatedInFile: [ImportRepeated]
}

struct ImportPreview: Decodable {
    let jobId: String
    let columns: [String]
    let preview: [[String]]
    let availableFields: [ImportField]
    let totalRows: Int?
    /// Mapeamento sugerido pelo servidor — a tela abre já preenchida com ele.
    let suggestedMapping: [String: String]?
    let suggestions: [ImportSuggestion]?
    let duplicates: ImportDuplicates?
}

struct ImportRowError: Decodable, Identifiable {
    let row: Int
    let error: String

    var id: String { "\(row)-\(error)" }
}

struct ImportJobResult: Decodable {
    let id: String
    let fileName: String
    let status: String
    let totalRows: Int
    let importedRows: Int
    let errors: [ImportRowError]
    /// Linhas puladas por já existirem na base.
    let skippedDuplicates: Int?
}

// MARK: - ViewModel

@MainActor
@Observable
final class PatientImportViewModel {
    enum Step { case file, mapping, result }

    /// Limite do backend (15MB) validado antes do upload.
    static let maxFileBytes = 15 * 1024 * 1024

    var step: Step = .file
    /// Ligado por padrão: importar duplicado é o erro caro, porque desfazer
    /// significa apagar paciente por paciente, na mão.
    var pularDuplicados = true
    var isLoading = false
    var errorMessage: String?

    var fileName: String?
    var preview: ImportPreview?
    /// Coluna do arquivo → key do campo destino (ausente = ignorar).
    var mapping: [String: String] = [:]
    var result: ImportJobResult?

    var stepNumber: Int {
        switch step {
        case .file: 1
        case .mapping: 2
        case .result: 3
        }
    }

    var nameIsMapped: Bool { mapping.values.contains("name") }

    /// Campos já usados por outra coluna não podem repetir (o backend
    /// sobrescreveria silenciosamente — melhor travar aqui).
    func isFieldTaken(_ key: String, exceptColumn column: String) -> Bool {
        mapping.contains { $0.key != column && $0.value == key }
    }

    func sampleValues(forColumnAt index: Int) -> String {
        guard let preview else { return "" }
        let values = preview.preview
            .compactMap { $0.indices.contains(index) ? $0[index] : nil }
            .filter { !$0.isEmpty }
            .prefix(3)
        return values.isEmpty ? "— sem exemplos —" : values.joined(separator: " · ")
    }

    // MARK: Passo 1 — upload + prévia

    func upload(url: URL) async {
        errorMessage = nil
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            errorMessage = "Não foi possível ler o arquivo selecionado."
            return
        }
        guard data.count <= Self.maxFileBytes else {
            errorMessage = "Arquivo muito grande (limite: 15MB)."
            return
        }

        let name = url.lastPathComponent
        let isXlsx = name.lowercased().hasSuffix(".xlsx")
        isLoading = true
        defer { isLoading = false }
        do {
            let response: ImportPreview = try await APIClient.shared.upload(
                "imports/preview",
                fileData: data,
                fileName: name,
                mimeType: isXlsx
                    ? "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
                    : "text/csv"
            )
            fileName = name
            preview = response
            // O servidor reconhece sinônimos ("TELEFONE" → whatsapp) e o
            // formato dos valores (um CPF se identifica sozinho). O autoMap
            // local só casa o rótulo exato, então fica como reserva para
            // quando a API for antiga.
            mapping = response.suggestedMapping
                ?? Self.autoMap(columns: response.columns, fields: response.availableFields)
            withAnimation { step = .mapping }
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
        } catch {
            errorMessage = (error as? APIError)?.message ?? "Não foi possível enviar o arquivo."
        }
    }

    /// Pré-mapeia colunas cujo nome bate com o rótulo/key do campo
    /// (sem acentos e caixa), pra o terapeuta só revisar.
    static func autoMap(columns: [String], fields: [ImportField]) -> [String: String] {
        func normalize(_ text: String) -> String {
            text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
                .lowercased()
                .filter { $0.isLetter || $0.isNumber }
        }
        // Sinônimos comuns em planilhas de leads/clientes.
        let synonyms: [String: String] = [
            "nomecompleto": "name", "paciente": "name", "cliente": "name",
            "telefone": "whatsapp", "celular": "whatsapp", "fone": "whatsapp", "zap": "whatsapp",
            "nascimento": "birthDate", "datanascimento": "birthDate", "datadenascimento": "birthDate",
            "valor": "sessionPrice", "valorsessao": "sessionPrice", "valordasessao": "sessionPrice", "preco": "sessionPrice",
            "diacobranca": "billingDay", "diadecobranca": "billingDay", "vencimento": "billingDay",
            "responsavel": "guardianName", "nomeresponsavel": "guardianName", "nomedoresponsavel": "guardianName",
            "contatoresponsavel": "guardianContact", "contatodoresponsavel": "guardianContact",
            "observacao": "notes", "observacoes": "notes", "obs": "notes", "anotacoes": "notes",
            "categoria": "groupName", "tipo": "groupName",
        ]

        var byNormalized: [String: String] = synonyms
        for field in fields {
            byNormalized[normalize(field.label)] = field.key
            byNormalized[normalize(field.key)] = field.key
        }

        var result: [String: String] = [:]
        var used: Set<String> = []
        for column in columns {
            if let key = byNormalized[normalize(column)], !used.contains(key) {
                result[column] = key
                used.insert(key)
            }
        }
        return result
    }

    // MARK: Passo 2 → 3 — executar

    func execute() async {
        guard let preview else { return }
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        struct Body: Encodable {
            let columnMapping: [String: String]
            let skipDuplicates: Bool
        }
        do {
            let job: ImportJobResult = try await APIClient.shared.post(
                "imports/\(preview.jobId)/execute",
                body: Body(columnMapping: mapping, skipDuplicates: pularDuplicados)
            )
            result = job
            withAnimation { step = .result }
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
        } catch {
            errorMessage = (error as? APIError)?.message ?? "Não foi possível concluir a importação."
        }
    }
}

// MARK: - Tela (sheet com 3 passos: arquivo → mapeamento → resultado)

struct PatientImportView: View {
    @State private var model = PatientImportViewModel()
    @State private var showFilePicker = false
    @Environment(\.dismiss) private var dismiss

    /// Chamado ao concluir com ao menos 1 paciente importado.
    let onImported: () -> Void

    private static let xlsxType = UTType(filenameExtension: "xlsx") ?? .data

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    progressHeader
                    ScrollView {
                        VStack(spacing: 16) {
                            switch model.step {
                            case .file: fileStep
                            case .mapping: mappingStep
                            case .result: resultStep
                            }
                            if let error = model.errorMessage {
                                Text(error)
                                    .font(Theme.body(13, weight: .medium))
                                    .foregroundStyle(Theme.danger)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.horizontal, Theme.screenPadding)
                        .padding(.top, 16)
                        .padding(.bottom, 24)
                    }
                    footerButtons
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if model.step == .mapping {
                            withAnimation { model.step = .file }
                        } else {
                            finish()
                        }
                    } label: {
                        Image(systemName: model.step == .mapping ? "arrow.left" : "xmark")
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("Importar pacientes")
                        .font(Theme.serifTitle(19))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.commaSeparatedText, Self.xlsxType]
            ) { pick in
                if case let .success(url) = pick {
                    Task { await model.upload(url: url) }
                }
            }
            .interactiveDismissDisabled(model.isLoading)
        }
    }

    private func finish() {
        if let result = model.result, result.importedRows > 0 {
            onImported()
        }
        dismiss()
    }

    // MARK: Progresso (dots como no wizard de paciente)

    private var stepTitle: String {
        switch model.step {
        case .file: "Arquivo"
        case .mapping: "Mapeamento"
        case .result: "Resultado"
        }
    }

    private var progressHeader: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(1...3, id: \.self) { index in
                    Circle()
                        .fill(index <= model.stepNumber ? Theme.primary : Theme.border)
                        .frame(width: 8, height: 8)
                }
            }
            Spacer()
            Text("\(model.stepNumber) de 3 · \(stepTitle)")
                .font(Theme.body(12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.vertical, 12)
    }

    // MARK: Passo 1 — escolher arquivo

    private var fileStep: some View {
        VStack(spacing: 16) {
            ThemeCard {
                VStack(alignment: .leading, spacing: 12) {
                    Label {
                        Text("Como funciona")
                            .font(Theme.body(15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                    } icon: {
                        Image(systemName: "square.and.arrow.down")
                            .foregroundStyle(Theme.primary)
                    }
                    bullet("Envie uma planilha .csv ou .xlsx com seus clientes ou leads (até 15MB).")
                    bullet("A primeira linha deve ser o cabeçalho, com o nome de cada coluna.")
                    bullet("Depois você diz qual coluna vira qual campo — só o nome é obrigatório.")
                    bullet("Grupos que não existirem serão criados automaticamente.")
                }
            }

            if let fileName = model.fileName {
                ThemeCard {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.text")
                            .foregroundStyle(Theme.primary)
                        Text(fileName)
                            .font(Theme.body(14, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Spacer()
                    }
                }
            }

            PrimaryButton(
                title: model.fileName == nil ? "Escolher arquivo" : "Escolher outro arquivo",
                isLoading: model.isLoading
            ) {
                showFilePicker = true
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Theme.primary)
                .frame(width: 5, height: 5)
                .padding(.top, 6)
            Text(text)
                .font(Theme.body(14))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }



    /// Frase do resultado. Os pulados aparecem porque "3 de 10 importados"
    /// sem explicação parece falha — e não é: os outros 7 já existiam.
    static func resumoDoResultado(_ r: ImportJobResult) -> String {
        let pulados = r.skippedDuplicates ?? 0
        let base = "\(r.importedRows) de \(r.totalRows) pacientes importados"
        guard pulados > 0 else { return base }
        return pulados == 1
            ? "\(base) · 1 já existia e foi pulado"
            : "\(base) · \(pulados) já existiam e foram pulados"
    }

    // MARK: Duplicidade

    /// Avisa ANTES de importar. Descobrir depois significa apagar paciente na
    /// mão, um a um — e é o que faz o terapeuta desistir de usar o recurso.
    @ViewBuilder
    private func duplicadosCard(_ dup: ImportDuplicates, total: Int) -> some View {
        ThemeCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.exclamationmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.warning)
                    Text(resumoDuplicados(dup, total: total))
                        .font(Theme.body(14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !dup.existing.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(dup.existing.prefix(4)) { d in
                            HStack(spacing: 6) {
                                Text("Linha \(d.row)")
                                    .font(Theme.body(11, weight: .semibold))
                                    .foregroundStyle(Theme.textSecondary)
                                Text(d.name)
                                    .font(Theme.body(13))
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(1)
                                Text("· \(d.motivo)")
                                    .font(Theme.body(12))
                                    .foregroundStyle(
                                        d.confidence == "certa" ? Theme.danger : Theme.textSecondary
                                    )
                            }
                        }
                        if dup.existing.count > 4 {
                            Text("e mais \(dup.existing.count - 4)…")
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }

                Toggle(isOn: Binding(
                    get: { model.pularDuplicados },
                    set: { model.pularDuplicados = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pular quem já existe")
                            .font(Theme.body(14, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                        Text(
                            model.pularDuplicados
                                ? "Só os novos serão importados."
                                : "Vai criar cópias dos pacientes que já existem."
                        )
                        .font(Theme.body(12))
                        .foregroundStyle(
                            model.pularDuplicados ? Theme.textSecondary : Theme.danger
                        )
                    }
                }
                .tint(Theme.primary)
            }
        }
    }

    private func resumoDuplicados(_ dup: ImportDuplicates, total: Int) -> String {
        var partes: [String] = []
        if !dup.existing.isEmpty {
            partes.append(
                dup.existing.count == 1
                    ? "1 pessoa do arquivo já está na sua lista"
                    : "\(dup.existing.count) pessoas do arquivo já estão na sua lista"
            )
        }
        if !dup.repeatedInFile.isEmpty {
            partes.append(
                dup.repeatedInFile.count == 1
                    ? "1 linha repetida no próprio arquivo"
                    : "\(dup.repeatedInFile.count) linhas repetidas no próprio arquivo"
            )
        }
        return partes.joined(separator: " · ")
    }

    // MARK: Passo 2 — mapear colunas

    @ViewBuilder
    private var mappingStep: some View {
        if let preview = model.preview {
            VStack(alignment: .leading, spacing: 12) {
                // Com a sugestão do servidor, o trabalho vira CONFERIR e não
                // montar. O texto muda para refletir isso.
                Text(
                    preview.suggestedMapping?.isEmpty == false
                        ? "Já identificamos as colunas do seu arquivo. Confira e ajuste o que estiver errado."
                        : "Diga o que é cada coluna do arquivo. Colunas em \"Ignorar\" ficam de fora."
                )
                .font(Theme.body(14))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

                if let dup = preview.duplicates,
                   !dup.existing.isEmpty || !dup.repeatedInFile.isEmpty {
                    duplicadosCard(dup, total: preview.totalRows ?? 0)
                }

                if !model.nameIsMapped {
                    ThemeCard {
                        Label {
                            Text("Mapeie uma coluna para o campo Nome — ele é obrigatório.")
                                .font(Theme.body(13, weight: .medium))
                                .foregroundStyle(Theme.warning)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(Theme.warning)
                        }
                    }
                }

                ForEach(Array(preview.columns.enumerated()), id: \.offset) { index, column in
                    columnCard(column: column, index: index, fields: preview.availableFields)
                }
            }
        }
    }

    private func columnCard(column: String, index: Int, fields: [ImportField]) -> some View {
        ThemeCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(column.isEmpty ? "(coluna sem nome)" : column)
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    fieldMenu(column: column, fields: fields)
                }
                Text(model.sampleValues(forColumnAt: index))
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }
        }
    }

    private func fieldMenu(column: String, fields: [ImportField]) -> some View {
        Menu {
            Button("Ignorar") { model.mapping[column] = nil }
            ForEach(fields) { field in
                Button {
                    model.mapping[column] = field.key
                } label: {
                    if model.isFieldTaken(field.key, exceptColumn: column) {
                        Label("\(field.label) · em uso", systemImage: "checkmark.circle")
                    } else {
                        Text(field.required ? "\(field.label) *" : field.label)
                    }
                }
                .disabled(model.isFieldTaken(field.key, exceptColumn: column))
            }
        } label: {
            HStack(spacing: 4) {
                Text(mappedLabel(column: column, fields: fields))
                    .font(Theme.body(13, weight: .semibold))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(model.mapping[column] == nil ? Theme.textSecondary : Theme.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(model.mapping[column] == nil ? Theme.background : Theme.primarySoft)
            .clipShape(Capsule())
        }
    }

    private func mappedLabel(column: String, fields: [ImportField]) -> String {
        guard let key = model.mapping[column] else { return "Ignorar" }
        return fields.first { $0.key == key }?.label ?? key
    }

    // MARK: Passo 3 — resultado

    @ViewBuilder
    private var resultStep: some View {
        if let result = model.result {
            VStack(spacing: 16) {
                ThemeCard {
                    VStack(spacing: 10) {
                        Image(systemName: (result.importedRows > 0 || (result.skippedDuplicates ?? 0) > 0) ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle((result.importedRows > 0 || (result.skippedDuplicates ?? 0) > 0) ? Theme.success : Theme.danger)
                        Text(
                            result.importedRows > 0
                                ? "Importação concluída"
                                : (result.skippedDuplicates ?? 0) > 0
                                    ? "Sua lista já estava em dia"
                                    : "Nada foi importado"
                        )
                            .font(Theme.serifTitle(20))
                            .foregroundStyle(Theme.textPrimary)
                        Text(Self.resumoDoResultado(result))
                            .font(Theme.body(14, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }

                if !result.errors.isEmpty {
                    ThemeCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Linhas com problema (\(result.errors.count))")
                                .font(Theme.body(14, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text("Corrija na planilha e importe de novo só essas linhas — as demais já entraram.")
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            ForEach(result.errors) { rowError in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("Linha \(rowError.row)")
                                        .font(Theme.money(12, weight: .bold))
                                        .foregroundStyle(Theme.danger)
                                        .frame(width: 64, alignment: .leading)
                                    Text(rowError.error)
                                        .font(Theme.body(13))
                                        .foregroundStyle(Theme.textPrimary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Rodapé

    private var footerButtons: some View {
        VStack(spacing: 0) {
            Divider().overlay(Theme.border)
            switch model.step {
            case .file:
                EmptyView()
            case .mapping:
                PrimaryButton(
                    title: "Importar pacientes",
                    isLoading: model.isLoading,
                    isEnabled: model.nameIsMapped
                ) {
                    Task { await model.execute() }
                }
                .padding(Theme.screenPadding)
            case .result:
                PrimaryButton(title: "Concluir") { finish() }
                    .padding(Theme.screenPadding)
            }
        }
        .background(Theme.background)
    }
}
