import SwiftUI

// MARK: - Selecionar modelo (fiel ao print)

@Observable
final class RecTemplatePickerViewModel {
    let kind: RecordsKind
    var templates: [RecTemplate] = []
    var searchText = ""
    var isLoading = true
    var errorMessage: String? = nil

    init(kind: RecordsKind) {
        self.kind = kind
    }

    var filtered: [RecTemplate] {
        guard !searchText.isEmpty else { return templates }
        return templates.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    /// Modelo mais usado vira o RECOMENDADO (como o "Padrão" do print).
    var recommended: RecTemplate? {
        filtered.max { ($0.usageCount ?? 0) < ($1.usageCount ?? 0) }
    }

    var others: [RecTemplate] {
        filtered.filter { $0.id != recommended?.id }
    }

    @MainActor
    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            templates = try await RecordsAPI.templates(kind: kind)
        } catch let error as APIError {
            errorMessage = error.message
        } catch {
            errorMessage = "Não foi possível carregar os modelos."
        }
        isLoading = false
    }
}

struct RecTemplatePickerView: View {
    @State private var model: RecTemplatePickerViewModel
    @Environment(\.dismiss) private var dismiss

    /// nil = criar em branco.
    let onSelect: (RecTemplate?) -> Void

    private static let templateIcons = ["doc.text", "pencil.line", "bell", "heart.text.square"]
    private static let templateTints: [Color] = [
        Theme.primary, Color(hex: 0xB9A6D9), Color(hex: 0x7FA8C9), Color(hex: 0xE8B98A),
    ]

    init(kind: RecordsKind, onSelect: @escaping (RecTemplate?) -> Void) {
        _model = State(initialValue: RecTemplatePickerViewModel(kind: kind))
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                content
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Selecionar modelo")
                        .font(Theme.serifTitle(19))
                        .foregroundStyle(Theme.textPrimary)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark").foregroundStyle(Theme.textPrimary)
                    }
                }
            }
            .task { await model.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading {
            ProgressView().tint(Theme.primary)
        } else if let error = model.errorMessage {
            ErrorRetryView(message: error) { Task { await model.load() } }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Escolha um modelo para começar. Você pode personalizar, adicionar e remover perguntas depois.")
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.textSecondary)

                    searchField

                    if model.filtered.isEmpty {
                        EmptyStateView(
                            icon: "doc.text.magnifyingglass",
                            title: "Nenhum modelo",
                            message: model.searchText.isEmpty
                                ? "Crie modelos em Configurações ou comece em branco."
                                : "Nenhum modelo para \"\(model.searchText)\"."
                        )
                    } else {
                        VStack(spacing: 0) {
                            if let recommended = model.recommended {
                                templateRow(recommended, index: 0, isRecommended: true)
                                if !model.others.isEmpty { Divider().overlay(Theme.border) }
                            }
                            ForEach(Array(model.others.enumerated()), id: \.element.id) { index, template in
                                templateRow(template, index: index + 1, isRecommended: false)
                                if template.id != model.others.last?.id {
                                    Divider().overlay(Theme.border)
                                }
                            }
                        }
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                                .stroke(Theme.border, lineWidth: 1)
                        )
                    }

                    blankButton
                }
                .padding(Theme.screenPadding)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.textSecondary)
            TextField("Buscar modelo...", text: $model.searchText)
                .font(Theme.body(15))
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.surface)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
    }

    private func templateRow(_ template: RecTemplate, index: Int, isRecommended: Bool) -> some View {
        Button {
            onSelect(template)
        } label: {
            HStack(spacing: 12) {
                let tint = Self.templateTints[index % Self.templateTints.count]
                Image(systemName: Self.templateIcons[index % Self.templateIcons.count])
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .background(tint.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 11))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(template.name)
                            .font(Theme.body(16, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        if isRecommended {
                            StatusBadge(
                                label: "RECOMENDADO",
                                color: Theme.success,
                                background: Theme.successSoft
                            )
                        }
                    }
                    Text(usageLabel(template))
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary.opacity(0.5))
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func usageLabel(_ template: RecTemplate) -> String {
        let count = template.questions.count
        let questions = count == 1 ? "1 pergunta" : "\(count) perguntas"
        let uses = template.usageCount ?? 0
        let used = uses == 1 ? "usado em 1 sessão" : "usado em \(uses) sessões"
        return "\(questions) · \(used)"
    }

    private var blankButton: some View {
        Button {
            onSelect(nil)
        } label: {
            Text("+ Criar em branco")
                .font(Theme.body(15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Theme.primarySoft.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerRadius)
                        .stroke(style: StrokeStyle(lineWidth: 1.2, dash: [6, 5]))
                        .foregroundStyle(Theme.textSecondary.opacity(0.5))
                )
        }
    }
}

// MARK: - Formulário de registro (criar/ver/editar)

@Observable
final class RecEntryFormViewModel {
    enum Mode {
        case create(template: RecTemplate?)
        case edit(entryId: String)

        var isEdit: Bool { if case .edit = self { true } else { false } }
    }

    let mode: Mode
    let patient: RecPatientRef
    let kind: RecordsKind

    var questions: [RecQuestion] = []
    var textAnswers: [String: String] = [:]
    var multiAnswers: [String: Set<String>] = [:]
    var title = ""
    var templateName: String? = nil
    var entry: RecEntryDetail? = nil
    var blankContent = ""

    var isLoading = false
    var isSaving = false
    var isDeleting = false
    var errorMessage: String? = nil
    var validationMessage: String? = nil

    /// Registro em branco (sem modelo): título + texto livre.
    var isBlank: Bool { questions.isEmpty }

    init(mode: Mode, patient: RecPatientRef, kind: RecordsKind) {
        self.mode = mode
        self.patient = patient
        self.kind = kind
        if case let .create(template) = mode, let template {
            questions = template.questions
            templateName = template.name
        }
    }

    @MainActor
    func loadIfNeeded() async {
        guard case let .edit(entryId) = mode, entry == nil else { return }
        isLoading = true
        errorMessage = nil
        do {
            let detail = try await RecordsAPI.entry(patientId: patient.id, id: entryId)
            entry = detail
            title = detail.title
            templateName = detail.template?.name
            questions = detail.template?.schema?.questions ?? []
            if questions.isEmpty {
                // Registro em branco: junta as respostas livres num texto só
                blankContent = detail.answers
                    .sorted { $0.key < $1.key }
                    .compactMap { $0.value.textValue ?? $0.value.listValue?.joined(separator: ", ") }
                    .joined(separator: "\n\n")
            } else {
                for (key, value) in detail.answers {
                    switch value {
                    case let .text(text): textAnswers[key] = text
                    case let .list(items): multiAnswers[key] = Set(items)
                    }
                }
            }
        } catch let error as APIError {
            errorMessage = error.message
        } catch {
            errorMessage = "Não foi possível carregar o registro."
        }
        isLoading = false
    }

    private func buildAnswers() -> [String: RecAnswer] {
        if isBlank {
            let trimmed = blankContent.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [:] : ["texto": .text(trimmed)]
        }
        var answers: [String: RecAnswer] = [:]
        for question in questions {
            if question.kind == "multiple" {
                let selected = multiAnswers[question.id] ?? []
                if !selected.isEmpty {
                    // Mantém a ordem das opções do modelo
                    let ordered = (question.options ?? []).filter(selected.contains)
                    answers[question.id] = .list(ordered)
                }
            } else {
                let value = (textAnswers[question.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { answers[question.id] = .text(value) }
            }
        }
        return answers
    }

    /// Valida perguntas obrigatórias no cliente (o backend revalida).
    private func validate(_ answers: [String: RecAnswer]) -> Bool {
        for question in questions where question.isRequired {
            if answers[question.id] == nil {
                validationMessage = "A pergunta \"\(question.label)\" é obrigatória."
                return false
            }
        }
        if isBlank && answers.isEmpty {
            validationMessage = "Escreva o conteúdo do registro."
            return false
        }
        validationMessage = nil
        return true
    }

    @MainActor
    func save() async -> Bool {
        let answers = buildAnswers()
        guard validate(answers) else { return false }
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }
        do {
            let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
            switch mode {
            case let .create(template):
                _ = try await RecordsAPI.createEntry(patientId: patient.id, RecEntryCreatePayload(
                    templateId: template?.id,
                    kind: kind.apiValue,
                    title: trimmedTitle.isEmpty ? nil : trimmedTitle,
                    answers: answers,
                    entryDate: nil
                ))
            case let .edit(entryId):
                _ = try await RecordsAPI.updateEntry(patientId: patient.id, id: entryId, RecEntryUpdatePayload(
                    title: trimmedTitle.isEmpty ? nil : trimmedTitle,
                    answers: answers
                ))
            }
            return true
        } catch let error as APIError {
            errorMessage = error.message
        } catch {
            errorMessage = "Não foi possível salvar o registro."
        }
        return false
    }

    @MainActor
    func delete() async -> Bool {
        guard case let .edit(entryId) = mode else { return false }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await RecordsAPI.deleteEntry(patientId: patient.id, id: entryId)
            return true
        } catch let error as APIError {
            errorMessage = error.message
        } catch {
            errorMessage = "Não foi possível excluir o registro."
        }
        return false
    }
}

struct RecEntryFormView: View {
    @State private var model: RecEntryFormViewModel
    @State private var showDeleteConfirm = false
    @Environment(\.dismiss) private var dismiss

    let onSaved: () -> Void

    init(
        mode: RecEntryFormViewModel.Mode,
        patient: RecPatientRef,
        kind: RecordsKind,
        onSaved: @escaping () -> Void
    ) {
        _model = State(initialValue: RecEntryFormViewModel(mode: mode, patient: patient, kind: kind))
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                if model.isLoading {
                    ProgressView().tint(Theme.primary)
                } else if let error = model.errorMessage, model.entry == nil, model.mode.isEdit {
                    ErrorRetryView(message: error) { Task { await model.loadIfNeeded() } }
                } else {
                    form
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark").foregroundStyle(Theme.textPrimary)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text(model.kind == .record ? "Prontuário" : "Anamnese")
                        .font(Theme.serifTitle(19))
                        .foregroundStyle(Theme.textPrimary)
                }
                if model.mode.isEdit {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button(role: .destructive) {
                                showDeleteConfirm = true
                            } label: {
                                Label("Excluir registro", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis").foregroundStyle(Theme.textPrimary)
                        }
                    }
                }
            }
            .alert("Excluir registro?", isPresented: $showDeleteConfirm) {
                Button("Cancelar", role: .cancel) {}
                Button("Excluir", role: .destructive) {
                    Task {
                        if await model.delete() {
                            onSaved()
                            dismiss()
                        }
                    }
                }
            } message: {
                Text("O registro será apagado. Esta ação não pode ser desfeita.")
            }
            .task { await model.loadIfNeeded() }
            .interactiveDismissDisabled(model.isSaving || model.isDeleting)
        }
    }

    private var form: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let templateName = model.templateName {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 11, weight: .semibold))
                            Text("\(templateName) · \(model.patient.name)")
                                .font(Theme.body(12, weight: .semibold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(Color(hex: 0x7C6BA5))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(hex: 0xB9A6D9).opacity(0.18))
                        .clipShape(Capsule())
                    }

                    titleField

                    if model.isBlank {
                        RecQuestionCard(label: "Conteúdo", isRequired: true) {
                            RecTextArea(text: $model.blankContent)
                        }
                    } else {
                        ForEach(model.questions) { question in
                            questionCard(question)
                        }
                    }

                    if let validation = model.validationMessage {
                        feedback(validation)
                    }
                    if let error = model.errorMessage, model.entry != nil || !model.mode.isEdit {
                        feedback(error)
                    }
                }
                .padding(Theme.screenPadding)
                .padding(.bottom, 24)
            }
            footer
        }
    }

    private var titleField: some View {
        TextField(defaultTitlePlaceholder, text: $model.title)
            .font(Theme.serifTitle(24))
            .foregroundStyle(Theme.textPrimary)
    }

    private var defaultTitlePlaceholder: String {
        let day = RecFormat.dayMonth.string(from: .now)
        return model.kind == .record ? "Evolução — \(day)" : "Anamnese — \(day)"
    }

    private func feedback(_ message: String) -> some View {
        Text(message)
            .font(Theme.body(13, weight: .medium))
            .foregroundStyle(Theme.danger)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func questionCard(_ question: RecQuestion) -> some View {
        RecQuestionCard(label: question.label, isRequired: question.isRequired) {
            switch question.kind {
            case "single":
                VStack(spacing: 8) {
                    ForEach(question.options ?? [], id: \.self) { option in
                        RecChoiceRow(
                            label: option,
                            isSelected: model.textAnswers[question.id] == option,
                            style: .radio
                        ) {
                            model.textAnswers[question.id] =
                                model.textAnswers[question.id] == option ? nil : option
                        }
                    }
                }
            case "multiple":
                VStack(spacing: 8) {
                    ForEach(question.options ?? [], id: \.self) { option in
                        RecChoiceRow(
                            label: option,
                            isSelected: model.multiAnswers[question.id]?.contains(option) ?? false,
                            style: .checkbox
                        ) {
                            var selected = model.multiAnswers[question.id] ?? []
                            if selected.contains(option) {
                                selected.remove(option)
                            } else {
                                selected.insert(option)
                            }
                            model.multiAnswers[question.id] = selected
                        }
                    }
                }
            default:
                RecTextArea(text: Binding(
                    get: { model.textAnswers[question.id] ?? "" },
                    set: { model.textAnswers[question.id] = $0 }
                ))
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider().overlay(Theme.border)
            PrimaryButton(
                title: model.mode.isEdit ? "Salvar alterações" : "Salvar registro",
                isLoading: model.isSaving
            ) {
                Task {
                    if await model.save() {
                        onSaved()
                        dismiss()
                    }
                }
            }
            .padding(Theme.screenPadding)
        }
        .background(Theme.background)
    }
}

// MARK: - Componentes do formulário (fiéis ao print do prontuário)

struct RecQuestionCard<Content: View>: View {
    let label: String
    var isRequired = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        ThemeCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 2) {
                    Text(label)
                        .font(Theme.body(16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    if isRequired {
                        Text("*")
                            .font(Theme.body(16, weight: .semibold))
                            .foregroundStyle(Theme.danger)
                    }
                }
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Campo multilinha estilo "card bege" do print ("Queixa inicial").
struct RecTextArea: View {
    @Binding var text: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("Resposta...")
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.textSecondary.opacity(0.7))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
            }
            TextEditor(text: $text)
                .font(Theme.body(15))
                .foregroundStyle(Theme.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .frame(minHeight: 110)
        }
        .background(Theme.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.border, lineWidth: 1)
        )
    }
}

/// Linha de escolha (radio "Cooperativo/Resistente" ou checkbox "Humor").
struct RecChoiceRow: View {
    enum Style { case radio, checkbox }

    let label: String
    let isSelected: Bool
    let style: Style
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Theme.primary : Theme.textSecondary.opacity(0.5))
                Text(label)
                    .font(Theme.body(15, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Theme.success : Theme.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(isSelected ? Theme.primarySoft.opacity(0.6) : Theme.background)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Theme.primary.opacity(0.5) : Theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var iconName: String {
        switch style {
        case .radio: isSelected ? "largecircle.fill.circle" : "circle"
        case .checkbox: isSelected ? "checkmark.square.fill" : "square"
        }
    }
}
