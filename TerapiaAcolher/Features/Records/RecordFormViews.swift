import PhotosUI
import SwiftUI
import VisionKit

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
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
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
        .buttonStyle(.pressableSubtle)
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

    /// Perguntas do modelo (fixas) + criadas na hora neste registro.
    var templateQuestions: [RecQuestion] = []
    var extraQuestions: [RecQuestion] = []
    var questions: [RecQuestion] { templateQuestions + extraQuestions }
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

    // MARK: "Salvar também como modelo"

    var saveAsTemplate = false
    var newTemplateName = ""
    /// Registro já gravado, mas o modelo falhou: salvar de novo só refaz o modelo.
    private var recordAlreadySaved = false
    var canSaveAsTemplate: Bool { !extraQuestions.isEmpty }

    // MARK: Foto das anotações → rascunho

    var noteOcrEnabled = false
    var isReadingNotes = false
    var notesError: String? = nil
    var notesLimitReached = false

    // MARK: IA — organizar rascunho nos campos

    var templateId: String? = nil
    var aiEnabled = false
    var isComposerOpen = false
    var draftText = ""
    var isDrafting = false
    var aiError: String? = nil
    /// Campos preenchidos pela IA nesta sessão de edição (marcados na tela).
    var aiFilledIds: Set<String> = []
    /// Elegíveis que a IA deixou em branco — o texto não trazia a informação.
    var aiBlankCount = 0
    /// Id do rascunho aceito; vai junto no salvamento pra métrica de aceitação.
    var aiDraftId: String? = nil
    /// Cota do Zelo para este tipo de registro (`subscription/me`). O plano diz
    /// ANTES se o Zelo está liberado: ninguém escreve um rascunho inteiro para
    /// só no fim ouvir "seu plano não inclui".
    var zeloUsage: SubscriptionUsageItem? = nil
    /// Cota só vale com o bloqueio por assinatura ligado no backend.
    var zeloEnforcing = false
    var zeloNotInPlan: Bool { zeloEnforcing && zeloUsage?.foraDoPlano == true }
    var zeloExhausted: Bool { zeloEnforcing && zeloUsage?.esgotado == true }
    /// Estado anterior ao "organizar", pra desfazer sem perder o que era manual.
    private var undoSnapshot: (text: [String: String], multi: [String: Set<String>])? = nil

    var canUndoAi: Bool { undoSnapshot != nil }
    var aiExcludedQuestions: [RecQuestion] { questions.filter(\.isAiExcluded) }
    /// Só mostra o recurso quando há campos pra preencher e IA ligada no backend.
    var showsAiComposer: Bool {
        aiEnabled && !isBlank && questions.contains { !$0.isAiExcluded }
    }

    var draftCharacterCount: Int { draftText.count }
    var canRunDraft: Bool {
        draftText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 20
    }

    /// Registro antigo sem modelo nem perguntas: caixa única de texto.
    var isBlank = false

    init(mode: Mode, patient: RecPatientRef, kind: RecordsKind) {
        self.mode = mode
        self.patient = patient
        self.kind = kind
        if case let .create(template) = mode {
            if let template {
                templateQuestions = template.questions
                templateName = template.name
                templateId = template.id
            } else {
                // Em branco: começa com uma anotação livre; ela acrescenta o resto.
                extraQuestions = [RecQuestion.nova(label: "Anotação")]
            }
        }
    }

    // MARK: Perguntas criadas na hora

    @MainActor
    func upsertExtra(_ question: RecQuestion) {
        if let i = extraQuestions.firstIndex(where: { $0.id == question.id }) {
            let antiga = extraQuestions[i]
            extraQuestions[i] = question
            // Mudou o tipo ou as opções: resposta antiga pode não valer mais.
            if antiga.kind != question.kind {
                textAnswers[question.id] = nil
                multiAnswers[question.id] = nil
            } else if let opcoes = question.options {
                if let t = textAnswers[question.id], question.kind == "single", !opcoes.contains(t) {
                    textAnswers[question.id] = nil
                }
                if let m = multiAnswers[question.id] { multiAnswers[question.id] = m.filter(opcoes.contains) }
            }
        } else {
            extraQuestions.append(question)
        }
        validationMessage = nil
    }

    @MainActor
    func removeExtra(_ id: String) {
        extraQuestions.removeAll { $0.id == id }
        textAnswers[id] = nil
        multiAnswers[id] = nil
        aiFilledIds.remove(id)
    }

    @MainActor
    func moveExtra(_ id: String, by offset: Int) {
        guard let i = extraQuestions.firstIndex(where: { $0.id == id }) else { return }
        let j = i + offset
        guard extraQuestions.indices.contains(j) else { return }
        extraQuestions.swapAt(i, j)
        Haptics.tap()
    }

    func isExtra(_ id: String) -> Bool { extraQuestions.contains { $0.id == id } }

    // MARK: Foto das anotações

    @MainActor
    func readNotes(_ fotos: [Data]) async {
        guard !fotos.isEmpty, !isReadingNotes else { return }
        notesError = nil
        notesLimitReached = false
        isReadingNotes = true
        defer { isReadingNotes = false }
        do {
            let r = try await RecordsAPI.transcribeNotes(fotos)
            let atual = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
            draftText = atual.isEmpty ? r.texto : "\(atual)\n\n\(r.texto)"
            isComposerOpen = true
            Haptics.success()
        } catch is CancellationError {
            // tela fechada — silencioso
        } catch let error as APIError {
            notesError = error.message
            notesLimitReached = error.code == "LIMITE_DO_PLANO"
        } catch {
            notesError = "Não foi possível ler a foto. Tente de novo."
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
            templateId = detail.template?.id
            templateQuestions = detail.template?.schema?.questions ?? []
            extraQuestions = detail.extraQuestions ?? []
            isBlank = questions.isEmpty
            if isBlank {
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
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
        } catch let error as APIError {
            errorMessage = error.message
        } catch {
            errorMessage = "Não foi possível carregar o registro."
        }
        isLoading = false
    }

    // MARK: IA

    /// Pergunta ao backend se a IA está configurada. Silencioso: se falhar, o
    /// recurso simplesmente não aparece — não é erro que interesse ao terapeuta.
    @MainActor
    func loadAiStatus() async {
        guard !isBlank else { return }
        async let cota: Void = loadZeloQuota()
        if !aiEnabled, let status = try? await RecordsAPI.aiStatus() {
            aiEnabled = status.enabled
            noteOcrEnabled = status.noteOcrEnabled ?? false
        }
        await cota
    }

    /// Lê a cota do Zelo no plano. Silencioso como o status: sem resposta, o
    /// recurso aparece e o backend decide na hora de organizar.
    @MainActor
    func loadZeloQuota() async {
        guard let dados = try? await SubscriptionAPI.mine() else { return }
        zeloEnforcing = dados.enforcing
        zeloUsage = dados.uso.zelo(kind)
    }

    /// Manda o rascunho pro backend e distribui a resposta nos campos.
    @MainActor
    func structureWithAI() async {
        guard canRunDraft, !isDrafting else { return }
        aiError = nil
        isDrafting = true
        defer { isDrafting = false }

        do {
            let response = try await RecordsAPI.draftRecord(
                patientId: patient.id,
                RecDraftPayload(
                    kind: kind.apiValue,
                    templateId: templateId,
                    text: draftText.trimmingCharacters(in: .whitespacesAndNewlines),
                    questions: extraQuestions.isEmpty ? nil : extraQuestions
                )
            )
            applyDraft(response)
        } catch is CancellationError {
            // requisição cancelada (fechou a tela) — silencioso
        } catch let error as APIError {
            aiError = error.message
            // Cota mudou no meio do caminho: o bloco passa a mostrar o motivo.
            await loadZeloQuota()
        } catch {
            aiError = "Não foi possível organizar o rascunho. Tente de novo."
        }
    }

    /// Escreve as respostas da IA por cima, guardando o estado anterior.
    /// Campos que a IA não preencheu ficam como estavam — nada é apagado.
    @MainActor
    private func applyDraft(_ response: RecDraftResponse) {
        // Nada preenchido: o rascunho fica aberto e a terapeuta sabe por quê,
        // em vez de o bloco fechar como se nada tivesse acontecido.
        guard !response.answers.isEmpty else {
            aiError = "O Zelo não encontrou no texto respostas para estas perguntas. Ajuste o rascunho ou preencha à mão."
            isComposerOpen = true
            Haptics.warning()
            return
        }
        if undoSnapshot == nil {
            undoSnapshot = (text: textAnswers, multi: multiAnswers)
        }

        var filled: Set<String> = []
        for (questionId, answer) in response.answers {
            switch answer {
            case let .text(value):
                textAnswers[questionId] = value
            case let .list(values):
                multiAnswers[questionId] = Set(values)
            }
            filled.insert(questionId)
        }

        aiFilledIds = filled
        aiBlankCount = response.blank.count
        aiDraftId = response.draftId
        isComposerOpen = false
        Haptics.success()
    }

    /// Volta ao que estava antes de organizar — o rascunho continua disponível.
    @MainActor
    func undoAi() {
        guard let snapshot = undoSnapshot else { return }
        textAnswers = snapshot.text
        multiAnswers = snapshot.multi
        undoSnapshot = nil
        aiFilledIds = []
        aiBlankCount = 0
        aiDraftId = nil
        isComposerOpen = true
        Haptics.tap()
    }

    /// Edição manual num campo tira a marca de "veio da IA" — o texto agora é
    /// do terapeuta, e a tela precisa refletir isso.
    @MainActor
    func markEditedByHand(_ questionId: String) {
        guard aiFilledIds.contains(questionId) else { return }
        aiFilledIds.remove(questionId)
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
        if !isBlank && questions.isEmpty {
            validationMessage = "Adicione pelo menos uma pergunta."
            return false
        }
        if saveAsTemplate && canSaveAsTemplate
            && newTemplateName.trimmingCharacters(in: .whitespaces).isEmpty {
            validationMessage = "Dê um nome ao modelo."
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
            if !recordAlreadySaved {
                switch mode {
                case let .create(template):
                    _ = try await RecordsAPI.createEntry(patientId: patient.id, RecEntryCreatePayload(
                        templateId: template?.id,
                        kind: kind.apiValue,
                        title: trimmedTitle.isEmpty ? nil : trimmedTitle,
                        answers: answers,
                        entryDate: nil,
                        aiDraftId: aiDraftId,
                        questions: extraQuestions.isEmpty ? nil : extraQuestions
                    ))
                case let .edit(entryId):
                    _ = try await RecordsAPI.updateEntry(patientId: patient.id, id: entryId, RecEntryUpdatePayload(
                        title: trimmedTitle.isEmpty ? nil : trimmedTitle,
                        answers: answers,
                        // Registro antigo (caixa única) não tem perguntas a mandar.
                        questions: isBlank ? nil : extraQuestions
                    ))
                }
                recordAlreadySaved = true
            }
            if saveAsTemplate && canSaveAsTemplate {
                do {
                    try await RecordsAPI.createTemplate(
                        kind: kind,
                        name: newTemplateName.trimmingCharacters(in: .whitespaces),
                        questions: questions.map { q in
                            var c = q
                            c.label = q.label.trimmingCharacters(in: .whitespaces)
                            return c
                        }
                    )
                } catch let error as APIError {
                    errorMessage = "O registro foi salvo, mas o modelo não: \(error.message)"
                    return false
                }
            }
            return true
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
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
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
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
    /// Pergunta em edição na folha (nova ou existente).
    @State private var editingQuestion: RecQuestion? = nil
    @State private var showNotesScanner = false
    @State private var showNotesPicker = false
    @State private var notesPickerItems: [PhotosPickerItem] = []
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
            .task {
                await model.loadIfNeeded()
                await model.loadAiStatus()
            }
            .interactiveDismissDisabled(model.isSaving || model.isDeleting || model.isDrafting || model.isReadingNotes)
            .sheet(item: $editingQuestion) { question in
                RecQuestionEditorSheet(
                    question: question,
                    isNew: !model.isExtra(question.id)
                ) { saved in
                    model.upsertExtra(saved)
                }
            }
            .fullScreenCover(isPresented: $showNotesScanner) {
                FichaScannerView(
                    maxPages: 4,
                    onFinish: { pages in
                        showNotesScanner = false
                        readNotes(pages)
                    },
                    onCancel: { showNotesScanner = false }
                )
                .ignoresSafeArea()
            }
            .photosPicker(isPresented: $showNotesPicker, selection: $notesPickerItems, maxSelectionCount: 4, matching: .images)
            .onChange(of: notesPickerItems) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    var images: [UIImage] = []
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                            images.append(image)
                        }
                    }
                    notesPickerItems = []
                    readNotes(images)
                }
            }
        }
    }

    private func readNotes(_ images: [UIImage]) {
        let fotos = images.compactMap(IntakeImage.jpeg(from:))
        guard !fotos.isEmpty else { return }
        Haptics.tap()
        Task { await model.readNotes(fotos) }
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

                    if model.showsAiComposer {
                        aiSection
                    }

                    if model.isBlank {
                        RecQuestionCard(label: "Conteúdo", isRequired: true) {
                            RecTextArea(text: $model.blankContent)
                        }
                    } else {
                        ForEach(model.questions) { question in
                            questionCard(question)
                        }
                        addQuestionButton
                        if model.canSaveAsTemplate {
                            saveAsTemplateCard
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

    // MARK: IA — escrever solto e deixar a IA distribuir nos campos

    @ViewBuilder
    private var aiSection: some View {
        VStack(spacing: 10) {
            if model.aiFilledIds.isEmpty && (model.zeloNotInPlan || model.zeloExhausted) {
                aiUnavailableCard
            } else if model.aiFilledIds.isEmpty {
                if model.isComposerOpen {
                    aiComposer
                } else {
                    aiEntryButton
                }
            } else {
                aiReviewBanner
            }

            if let aiError = model.aiError {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 13))
                    Text(aiError)
                        .font(Theme.body(13))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Theme.danger)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .animation(.easeOut(duration: 0.25), value: model.isComposerOpen)
        .animation(.easeOut(duration: 0.25), value: model.zeloNotInPlan || model.zeloExhausted)
        .animation(.easeOut(duration: 0.25), value: model.aiFilledIds.isEmpty)
    }

    /// Zelo fora do plano ou cota do ciclo usada: avisa ANTES de o terapeuta
    /// escrever o rascunho. Sem nomear plano nem preço — só o link por e-mail.
    private var aiUnavailableCard: some View {
        let oQue = model.kind == .record ? "prontuários" : "anamneses"
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZeloAvatar(size: 40)
                    .opacity(0.6)
                    .saturation(0.65)
                VStack(alignment: .leading, spacing: 3) {
                    Group {
                        if model.zeloNotInPlan {
                            Text("Escreva solto. O ") + Zelo.nomeEstilizado(15.5) + Text(" organiza.")
                        } else {
                            Text("Você usou os \(model.zeloUsage?.teto ?? 0) \(oQue) com o ")
                                + Zelo.nomeEstilizado(15.5) + Text(" deste ciclo.")
                        }
                    }
                    .font(Theme.body(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                    Text(model.zeloNotInPlan
                         ? "Não incluído na sua conta. Você pode continuar preenchendo os campos à mão."
                         : "A cota renova no próximo ciclo. Enquanto isso, preencha os campos à mão.")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [RecAi.soft.opacity(0.22), Theme.surface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .stroke(RecAi.soft.opacity(0.45), lineWidth: 1)
        )
    }

    /// Estado fechado: convite discreto, não rouba a cena do formulário.
    private var aiEntryButton: some View {
        Button {
            Haptics.tap()
            model.isComposerOpen = true
        } label: {
            HStack(spacing: 12) {
                ZeloAvatar(size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    (Text("Escreva solto. O ") + Zelo.nomeEstilizado(15.5) + Text(" organiza."))
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Anote do seu jeito. O Zelo distribui cada coisa no campo certo e você revisa antes de salvar.")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(RecAi.accent)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [RecAi.soft.opacity(0.22), Theme.surface],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .stroke(RecAi.soft.opacity(0.45), lineWidth: 1)
            )
        }
        .buttonStyle(.pressableSubtle)
    }

    private var aiComposer: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ZeloAvatar(size: 24)
                (Text("Seu rascunho para o ") + Zelo.nomeEstilizado(13.5))
                    .font(Theme.body(13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button {
                    Haptics.tap()
                    model.isComposerOpen = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .disabled(model.isDrafting)
            }
            .foregroundStyle(RecAi.accent)

            if model.noteOcrEnabled {
                notesPhotoRow
            }

            RecTextArea(
                text: $model.draftText,
                placeholder: "Ex.: paciente chegou mais falante hoje, relatou que dormiu melhor na semana, trouxe o conflito com a irmã de novo…",
                minHeight: 132
            )
            .disabled(model.isDrafting || model.isReadingNotes)

            HStack(spacing: 10) {
                Text(
                    model.canRunDraft
                        ? "O Zelo só preenche. Nada é salvo sem você revisar."
                        : "Escreva um pouco mais para começar."
                )
                .font(Theme.body(11))
                .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 8)
                Button {
                    Haptics.tap()
                    Task { await model.structureWithAI() }
                } label: {
                    HStack(spacing: 7) {
                        if model.isDrafting {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        } else {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        Text(model.isDrafting ? "Zelo organizando…" : "Organizar com o Zelo")
                            .font(Theme.body(14, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(model.canRunDraft ? RecAi.accent : RecAi.accent.opacity(0.4))
                    .clipShape(Capsule())
                    .animation(.easeInOut(duration: 0.15), value: model.isDrafting)
                }
                .buttonStyle(.pressable)
                .disabled(!model.canRunDraft || model.isDrafting)
            }
        }
        .padding(14)
        .background(RecAi.soft.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .stroke(RecAi.soft.opacity(0.45), lineWidth: 1)
        )
    }

    /// Foto das anotações à mão: a IA transcreve e o texto cai na caixa abaixo.
    @ViewBuilder
    private var notesPhotoRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.isReadingNotes {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(RecAi.accent)
                    Text("Lendo as anotações…")
                        .font(Theme.body(13, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                }
                .padding(.vertical, 4)
                .accessibilityIdentifier("notesReading")
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "camera")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(RecAi.accent)
                    Text("Foto das anotações")
                        .font(Theme.body(12.5, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 4)
                    if VNDocumentCameraViewController.isSupported {
                        notesButton("Escanear", icon: "camera.viewfinder", id: "notesScan") {
                            showNotesScanner = true
                        }
                    }
                    notesButton("Galeria", icon: "photo.on.rectangle", id: "notesGallery") {
                        showNotesPicker = true
                    }
                }
            }
            if let erro = model.notesError {
                Text(erro)
                    .font(Theme.body(12.5, weight: .medium))
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func notesButton(_ title: String, icon: String, id: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                Text(title).font(Theme.body(12.5, weight: .semibold))
            }
            .foregroundStyle(RecAi.accent)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(RecAi.accent.opacity(0.12))
            .clipShape(Capsule())
        }
        .buttonStyle(.pressable)
        .disabled(model.isDrafting)
        .accessibilityIdentifier(id)
    }

    // MARK: Perguntas criadas na hora

    private var addQuestionButton: some View {
        Button {
            Haptics.tap()
            editingQuestion = RecQuestion.nova()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 13, weight: .bold))
                Text("Adicionar pergunta").font(Theme.body(15, weight: .semibold))
            }
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Theme.primarySoft.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .stroke(style: StrokeStyle(lineWidth: 1.2, dash: [6, 5]))
                    .foregroundStyle(Theme.textSecondary.opacity(0.5))
            )
        }
        .buttonStyle(.pressableSubtle)
        .accessibilityIdentifier("recAddQuestion")
    }

    private var saveAsTemplateCard: some View {
        ThemeCard {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $model.saveAsTemplate) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Salvar também como modelo")
                            .font(Theme.body(15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Use estas perguntas de novo com outros pacientes.")
                            .font(Theme.body(12.5))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .tint(Theme.primary)
                .accessibilityIdentifier("recSaveAsTemplate")
                if model.saveAsTemplate {
                    TextField("Nome do modelo", text: $model.newTemplateName)
                        .font(Theme.body(15))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Theme.background)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
                        .accessibilityIdentifier("recTemplateName")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .animation(.easeOut(duration: 0.2), value: model.saveAsTemplate)
    }

    /// Menu de uma pergunta criada na hora: editar, mover e remover.
    private func extraMenu(_ question: RecQuestion) -> some View {
        let lista = model.extraQuestions
        let i = lista.firstIndex { $0.id == question.id } ?? 0
        return Menu {
            Button { editingQuestion = question } label: { Label("Editar pergunta", systemImage: "pencil") }
            if i > 0 {
                Button { model.moveExtra(question.id, by: -1) } label: { Label("Mover para cima", systemImage: "arrow.up") }
            }
            if i < lista.count - 1 {
                Button { model.moveExtra(question.id, by: 1) } label: { Label("Mover para baixo", systemImage: "arrow.down") }
            }
            Button(role: .destructive) { model.removeExtra(question.id) } label: {
                Label("Remover pergunta", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 30, height: 26)
                .contentShape(Rectangle())
        }
        .accessibilityIdentifier("recQuestionMenu")
    }

    /// Depois de organizar: o que fazer agora fica explícito, e dá pra voltar.
    private var aiReviewBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                ZeloAvatar(size: 30)
                VStack(alignment: .leading, spacing: 3) {
                    (Text("O ") + Zelo.nomeEstilizado(14) + Text(" \(filledSummary)"))
                        .font(Theme.body(14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Confira cada campo marcado antes de salvar — o registro é seu.")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Button {
                    model.undoAi()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Desfazer")
                            .font(Theme.body(13, weight: .semibold))
                    }
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Theme.surface)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
                }
                .buttonStyle(.pressable)

                Button {
                    Haptics.tap()
                    model.isComposerOpen = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Editar rascunho")
                            .font(Theme.body(13, weight: .semibold))
                    }
                    .foregroundStyle(RecAi.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(RecAi.accent.opacity(0.12))
                    .clipShape(Capsule())
                }
                .buttonStyle(.pressable)
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RecAi.soft.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .stroke(RecAi.soft.opacity(0.45), lineWidth: 1)
        )
    }

    private var filledSummary: String {
        let count = model.aiFilledIds.count
        let fields = count == 1 ? "preencheu 1 campo" : "preencheu \(count) campos"
        if model.aiBlankCount > 0 {
            let blank = model.aiBlankCount == 1
                ? "1 ficou em branco"
                : "\(model.aiBlankCount) ficaram em branco"
            return "\(fields) · \(blank)"
        }
        return fields
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
        RecQuestionCard(
            label: question.label,
            isRequired: question.isRequired,
            isAiFilled: model.aiFilledIds.contains(question.id),
            isAiExcluded: question.isAiExcluded && model.showsAiComposer,
            accessory: model.isExtra(question.id) ? AnyView(extraMenu(question)) : nil
        ) {
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
                            model.markEditedByHand(question.id)
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
                            model.markEditedByHand(question.id)
                        }
                    }
                }
            default:
                RecTextArea(text: Binding(
                    get: { model.textAnswers[question.id] ?? "" },
                    set: {
                        model.textAnswers[question.id] = $0
                        model.markEditedByHand(question.id)
                    }
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
    /// Campo escrito pela IA nesta edição — some assim que o terapeuta digita.
    var isAiFilled = false
    /// Campo que a IA nunca preenche (diagnóstico).
    var isAiExcluded = false
    /// Ações da pergunta criada na hora (menu "…").
    var accessory: AnyView? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        ThemeCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(label)
                        .font(Theme.body(16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    if isRequired {
                        Text("*")
                            .font(Theme.body(16, weight: .semibold))
                            .foregroundStyle(Theme.danger)
                    }
                    Spacer(minLength: 8)
                    if isAiFilled {
                        RecAiTag(text: "Zelo · revise", icon: "sparkles", tint: RecAi.accent)
                    } else if isAiExcluded {
                        RecAiTag(
                            text: "Só você preenche",
                            icon: "hand.raised",
                            tint: Theme.textSecondary
                        )
                    }
                    if let accessory { accessory }
                }
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Borda lilás enquanto o texto for da IA: o campo pede revisão.
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .stroke(isAiFilled ? RecAi.accent.opacity(0.45) : .clear, lineWidth: 1.5)
        )
        .animation(.easeOut(duration: 0.25), value: isAiFilled)
    }
}

/// Identidade visual da IA no app — lilás, o mesmo tom já usado nos modelos.
enum RecAi {
    static let accent = Color(hex: 0x7C6BA5)
    static let soft = Color(hex: 0xB9A6D9)
}

/// Etiqueta pequena de status do campo.
struct RecAiTag: View {
    let text: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            Text(text)
                .font(Theme.body(10, weight: .bold))
                .tracking(0.3)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(tint.opacity(0.12))
        .clipShape(Capsule())
    }
}

/// Campo multilinha estilo "card bege" do print ("Queixa inicial").
struct RecTextArea: View {
    @Binding var text: String
    var placeholder: String = "Resposta..."
    var minHeight: CGFloat = 110

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.textSecondary.opacity(0.7))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .fixedSize(horizontal: false, vertical: true)
            }
            TextEditor(text: $text)
                .font(Theme.body(15))
                .foregroundStyle(Theme.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .frame(minHeight: minHeight)
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
        .buttonStyle(.pressableSubtle)
    }

    private var iconName: String {
        switch style {
        case .radio: isSelected ? "largecircle.fill.circle" : "circle"
        case .checkbox: isSelected ? "checkmark.square.fill" : "square"
        }
    }
}
