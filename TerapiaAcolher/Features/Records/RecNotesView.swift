import SwiftUI

// MARK: - ViewModel

@Observable
final class RecNotesViewModel {
    let patient: RecPatientRef
    var notes: [RecNote] = []
    var isLoading = true
    var errorMessage: String? = nil

    init(patient: RecPatientRef) {
        self.patient = patient
    }

    var headerLabel: String {
        let count = notes.count
        let word = count == 1 ? "anotação" : "anotações"
        return "\(count) \(word) · privadas"
    }

    @MainActor
    func load(showSpinner: Bool = true) async {
        if showSpinner { isLoading = notes.isEmpty }
        errorMessage = nil
        do {
            notes = try await RecordsAPI.notes(patientId: patient.id)
        } catch let error as APIError {
            errorMessage = error.message
        } catch {
            errorMessage = "Não foi possível carregar as anotações."
        }
        isLoading = false
    }

    @MainActor
    func delete(_ note: RecNote) async {
        do {
            try await RecordsAPI.deleteNote(patientId: patient.id, id: note.id)
            notes.removeAll { $0.id == note.id }
        } catch let error as APIError {
            errorMessage = error.message
        } catch {
            errorMessage = "Não foi possível excluir a anotação."
        }
    }
}

// MARK: - Tela: Anotações de sessão (timeline fiel ao print)

struct RecNotesView: View {
    @State private var model: RecNotesViewModel
    @State private var composerNote: RecNoteEditorContext? = nil
    @State private var noteToDelete: RecNote? = nil

    init(patient: RecPatientRef) {
        _model = State(initialValue: RecNotesViewModel(patient: patient))
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                content
            }
            FloatingActionButton { composerNote = RecNoteEditorContext(note: nil) }
                .padding(.trailing, Theme.screenPadding)
                .padding(.bottom, 24)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Anotações")
                    .font(Theme.serifTitle(20))
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .sheet(item: $composerNote) { context in
            RecNoteEditorView(patient: model.patient, note: context.note) {
                Task { await model.load(showSpinner: false) }
            }
        }
        .alert(
            "Excluir anotação?",
            isPresented: Binding(
                get: { noteToDelete != nil },
                set: { if !$0 { noteToDelete = nil } }
            )
        ) {
            Button("Cancelar", role: .cancel) { noteToDelete = nil }
            Button("Excluir", role: .destructive) {
                if let note = noteToDelete {
                    Task { await model.delete(note) }
                }
                noteToDelete = nil
            }
        } message: {
            Text("A anotação será apagada. Esta ação não pode ser desfeita.")
        }
        .task { await model.load() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            InitialAvatar(name: model.patient.name, colorHex: model.patient.groupColor, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.patient.name)
                    .font(Theme.body(16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(model.headerLabel)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading {
            Spacer()
            ProgressView().tint(Theme.primary)
            Spacer()
        } else if let error = model.errorMessage, model.notes.isEmpty {
            Spacer()
            ErrorRetryView(message: error) { Task { await model.load() } }
            Spacer()
        } else if model.notes.isEmpty {
            Spacer()
            EmptyStateView(
                icon: "list.clipboard",
                title: "Nenhuma anotação ainda",
                message: "Anotações são privadas e criptografadas — só você as vê.",
                actionTitle: "Nova anotação",
                action: { composerNote = RecNoteEditorContext(note: nil) }
            )
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    if let error = model.errorMessage {
                        Text(error)
                            .font(Theme.body(13, weight: .medium))
                            .foregroundStyle(Theme.danger)
                    }
                    ForEach(model.notes) { note in
                        RecNoteCard(note: note)
                            .contextMenu {
                                Button {
                                    composerNote = RecNoteEditorContext(note: note)
                                } label: {
                                    Label("Editar", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    noteToDelete = note
                                } label: {
                                    Label("Excluir", systemImage: "trash")
                                }
                            }
                            .onTapGesture {
                                composerNote = RecNoteEditorContext(note: note)
                            }
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 4)
                .padding(.bottom, 100)
            }
            .refreshable { await model.load(showSpinner: false) }
        }
    }
}

struct RecNoteEditorContext: Identifiable {
    let id = UUID()
    let note: RecNote?
}

// MARK: - Card da anotação ("HOJE · 14:52" + tag verde)

struct RecNoteCard: View {
    let note: RecNote

    var body: some View {
        ThemeCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(RecFormat.timelineLabel(note.noteDate))
                        .font(Theme.money(12, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .tracking(0.5)
                    Spacer()
                    if let tag = note.tag, !tag.isEmpty {
                        StatusBadge(label: tag, color: Theme.success, background: Theme.successSoft)
                    }
                }
                Text(note.content)
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.textPrimary)
                    .lineSpacing(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Composer (nova/editar anotação)

@Observable
final class RecNoteEditorViewModel {
    let patient: RecPatientRef
    let existing: RecNote?
    var content: String
    var tag: String
    var isSaving = false
    var errorMessage: String? = nil

    static let suggestedTags = ["Pós-sessão", "Pré-sessão", "Observação"]

    init(patient: RecPatientRef, note: RecNote?) {
        self.patient = patient
        existing = note
        content = note?.content ?? ""
        tag = note?.tag ?? ""
    }

    var canSave: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    @MainActor
    func save() async -> Bool {
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }
        let payload = RecNotePayload(
            content: content.trimmingCharacters(in: .whitespacesAndNewlines),
            tag: tag.trimmingCharacters(in: .whitespaces).isEmpty ? nil : tag.trimmingCharacters(in: .whitespaces),
            noteDate: existing == nil ? Date() : nil
        )
        do {
            if let existing {
                _ = try await RecordsAPI.updateNote(patientId: patient.id, id: existing.id, payload)
            } else {
                _ = try await RecordsAPI.createNote(patientId: patient.id, payload)
            }
            return true
        } catch let error as APIError {
            errorMessage = error.message
        } catch {
            errorMessage = "Não foi possível salvar a anotação."
        }
        return false
    }
}

struct RecNoteEditorView: View {
    @State private var model: RecNoteEditorViewModel
    @Environment(\.dismiss) private var dismiss

    let onSaved: () -> Void

    init(patient: RecPatientRef, note: RecNote?, onSaved: @escaping () -> Void) {
        _model = State(initialValue: RecNoteEditorViewModel(patient: patient, note: note))
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 16) {
                    tagPicker
                    RecTextArea(text: $model.content)
                        .frame(maxHeight: .infinity, alignment: .top)
                    if let error = model.errorMessage {
                        Text(error)
                            .font(Theme.body(13, weight: .medium))
                            .foregroundStyle(Theme.danger)
                    }
                    PrimaryButton(
                        title: model.existing == nil ? "Salvar anotação" : "Salvar alterações",
                        isLoading: model.isSaving,
                        isEnabled: model.canSave
                    ) {
                        Task {
                            if await model.save() {
                                onSaved()
                                dismiss()
                            }
                        }
                    }
                }
                .padding(Theme.screenPadding)
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
                    Text(model.existing == nil ? "Nova anotação" : "Editar anotação")
                        .font(Theme.serifTitle(19))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            .interactiveDismissDisabled(model.isSaving)
        }
        .presentationDetents([.medium, .large])
    }

    private var tagPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TAG (OPCIONAL)")
                .font(Theme.body(11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .tracking(1.2)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(RecNoteEditorViewModel.suggestedTags, id: \.self) { suggestion in
                        FilterChip(label: suggestion, isSelected: model.tag == suggestion) {
                            model.tag = model.tag == suggestion ? "" : suggestion
                        }
                    }
                }
            }
        }
    }
}
