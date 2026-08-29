import Observation
import SwiftUI

/// Editor de modelo.
/// RECORD/ANAMNESIS → form-builder: perguntas reordenáveis (texto livre,
/// escolha única, múltipla) com opções e obrigatoriedade.
/// DOCUMENT/QUICK_REPLY → editor de texto com inserção de variáveis { }.
struct SetTemplateEditorView: View {
    let type: SetTemplateType
    let existing: SetTemplate?
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var questions: [SetQuestion]
    @State private var content: String
    @State private var editMode: EditMode = .inactive
    @State private var editingQuestionIndex: Int?
    @State private var showNewQuestion = false
    @State private var showDeleteConfirm = false
    @State private var isSaving = false
    @State private var isDeleting = false
    @State private var errorMessage: String?
    @State private var showError = false

    init(type: SetTemplateType, existing: SetTemplate?, onSaved: @escaping () -> Void) {
        self.type = type
        self.existing = existing
        self.onSaved = onSaved
        _name = State(initialValue: existing?.name ?? "")
        _questions = State(initialValue: existing?.schema.questions ?? [])
        _content = State(initialValue: existing?.schema.content ?? "")
    }

    private var canSave: Bool {
        let hasName = !name.trimmingCharacters(in: .whitespaces).isEmpty
        if type.isForm {
            return hasName && !questions.isEmpty
        }
        return hasName && !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if type.isForm {
                    formBuilder
                } else {
                    contentEditor
                }
            }
            .setToolbarTitle(existing == nil ? "Novo modelo" : "Editar modelo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView().tint(Theme.primary)
                        } else {
                            Text("Salvar")
                                .font(Theme.body(16, weight: .semibold))
                                .foregroundStyle(canSave ? Theme.primary : Theme.textSecondary)
                        }
                    }
                    .disabled(!canSave || isSaving)
                }
            }
            .sheet(isPresented: $showNewQuestion) {
                SetQuestionEditorView(question: .nova(), isNew: true) { saved in
                    questions.append(saved)
                }
            }
            .sheet(
                isPresented: Binding(
                    get: { editingQuestionIndex != nil },
                    set: { if !$0 { editingQuestionIndex = nil } }
                )
            ) {
                if let index = editingQuestionIndex, questions.indices.contains(index) {
                    SetQuestionEditorView(question: questions[index], isNew: false) { saved in
                        questions[index] = saved
                    }
                }
            }
            .alert("Ops", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Algo deu errado.")
            }
        }
    }

    // MARK: - Form-builder (RECORD / ANAMNESIS)

    private var formBuilder: some View {
        List {
            Section {
                TextField("Ex.: Evolução padrão", text: $name)
                    .font(Theme.body(16))
            } header: {
                Text("Nome do modelo")
            }

            Section {
                ForEach(Array(questions.enumerated()), id: \.element.id) { index, question in
                    Button {
                        editingQuestionIndex = index
                    } label: {
                        questionRow(question, position: index + 1)
                    }
                    .buttonStyle(.pressableSubtle)
                }
                .onDelete { offsets in
                    questions.remove(atOffsets: offsets)
                }
                .onMove { source, destination in
                    questions.move(fromOffsets: source, toOffset: destination)
                }

                Button {
                    showNewQuestion = true
                } label: {
                    Label("Adicionar pergunta", systemImage: "plus.circle.fill")
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                }
            } header: {
                HStack {
                    Text("Perguntas")
                    Spacer()
                    Button(editMode == .active ? "Concluir" : "Reordenar") {
                        withAnimation {
                            editMode = editMode == .active ? .inactive : .active
                        }
                    }
                    .font(Theme.body(12, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .textCase(nil)
                }
            } footer: {
                Text("Arraste para reordenar · deslize para excluir. Toque numa pergunta para editar.")
            }

            if existing != nil {
                Section {
                    deleteButton
                }
            }
        }
        .environment(\.editMode, $editMode)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
    }

    private func questionRow(_ question: SetQuestion, position: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(position)")
                .font(Theme.money(13))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 24, height: 24)
                .background(Theme.background)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(question.label.isEmpty ? "Sem enunciado" : question.label)
                    .font(Theme.body(15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(question.kindLabel)
                        .font(Theme.body(11, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Theme.primarySoft)
                        .foregroundStyle(Theme.primary)
                        .clipShape(Capsule())
                    if let options = question.options, !options.isEmpty {
                        Text("\(options.count) opções")
                            .font(Theme.body(11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    if question.isRequired == true {
                        Text("Obrigatória")
                            .font(Theme.body(11))
                            .foregroundStyle(Theme.warning)
                    }
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary.opacity(0.6))
        }
        .contentShape(Rectangle())
    }

    // MARK: - Editor de texto (DOCUMENT / QUICK_REPLY)

    private var contentEditor: some View {
        List {
            Section {
                TextField(
                    type == .document ? "Ex.: Recibo de sessão" : "Ex.: Confirmação de horário",
                    text: $name
                )
                .font(Theme.body(16))
            } header: {
                Text("Nome do modelo")
            }

            Section {
                TextEditor(text: $content)
                    .font(Theme.body(15))
                    .frame(minHeight: 220)
            } header: {
                HStack {
                    Text("Conteúdo")
                    Spacer()
                    Menu {
                        ForEach(SetTemplateVariable.allCases) { variable in
                            Button {
                                insertVariable(variable)
                            } label: {
                                Text("\(variable.label) — \(variable.placeholder)")
                            }
                        }
                    } label: {
                        Label("{ } Inserir variável", systemImage: "curlybraces")
                            .font(Theme.body(12, weight: .semibold))
                            .foregroundStyle(Theme.primary)
                            .textCase(nil)
                    }
                }
            } footer: {
                Text("As variáveis entre chaves são substituídas automaticamente na hora de gerar — ex.: {nome_paciente}, {valor}, {data_hoje}.")
            }

            if existing != nil {
                Section {
                    deleteButton
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
    }

    private func insertVariable(_ variable: SetTemplateVariable) {
        if !content.isEmpty, !content.hasSuffix(" "), !content.hasSuffix("\n") {
            content += " "
        }
        content += variable.placeholder
    }

    private var deleteButton: some View {
        Button {
            showDeleteConfirm = true
        } label: {
            HStack {
                Spacer()
                if isDeleting {
                    ProgressView().tint(Theme.danger)
                } else {
                    Label("Excluir modelo", systemImage: "trash")
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(Theme.danger)
                }
                Spacer()
            }
        }
        .disabled(isDeleting)
        .confirmationDialog(
            "Excluir este modelo?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Excluir", role: .destructive) {
                Task { await deleteTemplate() }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se o modelo já foi usado, ele é arquivado e os registros preenchidos são preservados.")
        }
    }

    // MARK: - Persistência

    private func save() async {
        struct CreateBody: Encodable {
            let type: String
            let name: String
            let schema: SetTemplateSchema
        }
        struct UpdateBody: Encodable {
            let name: String
            let schema: SetTemplateSchema
        }

        let schema: SetTemplateSchema
        if type.isForm {
            // Sanitiza: perguntas de escolha sem opções válidas travam no backend.
            for (index, question) in questions.enumerated() {
                if question.label.trimmingCharacters(in: .whitespaces).isEmpty {
                    errorMessage = "A pergunta \(index + 1) está sem enunciado."
                    showError = true
                    return
                }
                if question.kind != "text", (question.options ?? []).filter({ !$0.trimmingCharacters(in: .whitespaces).isEmpty }).isEmpty {
                    errorMessage = "A pergunta \"\(question.label)\" é de escolha e precisa de pelo menos uma opção."
                    showError = true
                    return
                }
            }
            let cleaned = questions.map { question -> SetQuestion in
                var copy = question
                copy.label = question.label.trimmingCharacters(in: .whitespaces)
                if question.kind == "text" {
                    copy.options = nil
                } else {
                    // Sem vazias nem duplicadas (o backend rejeita ambas).
                    var seen = Set<String>()
                    copy.options = (question.options ?? [])
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty && seen.insert($0).inserted }
                }
                return copy
            }
            schema = SetTemplateSchema(questions: cleaned, content: nil)
        } else {
            schema = SetTemplateSchema(questions: nil, content: content)
        }

        isSaving = true
        defer { isSaving = false }
        do {
            let trimmedName = name.trimmingCharacters(in: .whitespaces)
            if let existing {
                let _: EmptyResponse = try await APIClient.shared.patch(
                    "templates/\(existing.id)",
                    body: UpdateBody(name: trimmedName, schema: schema)
                )
            } else {
                let _: EmptyResponse = try await APIClient.shared.post(
                    "templates",
                    body: CreateBody(type: type.rawValue, name: trimmedName, schema: schema)
                )
            }
            onSaved()
            dismiss()
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
        } catch {
            errorMessage = (error as? APIError)?.message ?? "Não foi possível salvar o modelo."
            showError = true
        }
    }

    private func deleteTemplate() async {
        guard let existing else { return }
        isDeleting = true
        defer { isDeleting = false }
        do {
            let _: EmptyResponse = try await APIClient.shared.delete("templates/\(existing.id)")
            onSaved()
            dismiss()
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
        } catch {
            errorMessage = (error as? APIError)?.message ?? "Não foi possível excluir o modelo."
            showError = true
        }
    }
}

// MARK: - Editor de pergunta

struct SetQuestionEditorView: View {
    /// Rascunho de opção com identidade estável — ForEach por índice +
    /// remove(at:) crasha quando o SwiftUI reusa linhas durante a remoção.
    private struct OptionDraft: Identifiable {
        let id = UUID()
        var text: String
    }

    @State var question: SetQuestion
    let isNew: Bool
    var onSave: (SetQuestion) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var optionDrafts: [OptionDraft]
    @State private var isRequired: Bool

    init(question: SetQuestion, isNew: Bool, onSave: @escaping (SetQuestion) -> Void) {
        _question = State(initialValue: question)
        self.isNew = isNew
        self.onSave = onSave
        _optionDrafts = State(initialValue: (question.options ?? []).map { OptionDraft(text: $0) })
        _isRequired = State(initialValue: question.isRequired ?? false)
    }

    private var canSave: Bool {
        let hasLabel = !question.label.trimmingCharacters(in: .whitespaces).isEmpty
        if question.kind == "text" { return hasLabel }
        return hasLabel && optionDrafts.contains { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Enunciado") {
                    TextField("Ex.: Como o paciente chegou hoje?", text: $question.label, axis: .vertical)
                        .font(Theme.body(15))
                        .lineLimit(1 ... 3)
                }

                Section("Tipo de resposta") {
                    Picker("Tipo", selection: $question.kind) {
                        Text("Texto livre").tag("text")
                        Text("Escolha única").tag("single")
                        Text("Múltipla escolha").tag("multiple")
                    }
                    .pickerStyle(.segmented)
                }

                if question.kind != "text" {
                    Section {
                        ForEach($optionDrafts) { $draft in
                            let number = (optionDrafts.firstIndex { $0.id == draft.id } ?? 0) + 1
                            HStack {
                                TextField("Opção \(number)", text: $draft.text)
                                    .font(Theme.body(15))
                                Button {
                                    optionDrafts.removeAll { $0.id == draft.id }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(Theme.danger.opacity(0.7))
                                }
                                .buttonStyle(.pressableSubtle)
                            }
                        }
                        Button {
                            optionDrafts.append(OptionDraft(text: ""))
                        } label: {
                            Label("Adicionar opção", systemImage: "plus.circle.fill")
                                .font(Theme.body(14, weight: .semibold))
                                .foregroundStyle(Theme.primary)
                        }
                    } header: {
                        Text("Opções")
                    } footer: {
                        Text(question.kind == "single"
                            ? "O paciente ou você escolhe uma única opção."
                            : "Permite marcar várias opções.")
                    }
                }

                Section {
                    Toggle(isOn: $isRequired) {
                        Text("Resposta obrigatória")
                            .font(Theme.body(15))
                    }
                    .tint(Theme.primary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .setToolbarTitle(isNew ? "Nova pergunta" : "Editar pergunta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Salvar") {
                        var saved = question
                        saved.label = question.label.trimmingCharacters(in: .whitespaces)
                        saved.isRequired = isRequired
                        saved.options = question.kind == "text"
                            ? nil
                            : optionDrafts
                                .map { $0.text.trimmingCharacters(in: .whitespaces) }
                                .filter { !$0.isEmpty }
                        onSave(saved)
                        dismiss()
                    }
                    .font(Theme.body(16, weight: .semibold))
                    .foregroundStyle(canSave ? Theme.primary : Theme.textSecondary)
                    .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.large])
    }
}
