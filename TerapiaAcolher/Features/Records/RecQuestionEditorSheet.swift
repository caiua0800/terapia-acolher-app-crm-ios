import SwiftUI

// MARK: - Pergunta criada na hora (2026-10-06)
//
// Dentro do prontuário/anamnese, a terapeuta monta a pergunta que precisar:
// texto livre, escolha única ou múltipla escolha. Vale só para aquele registro
// (ou vira modelo, com "Salvar também como modelo").

struct RecQuestionEditorSheet: View {
    let isNew: Bool
    let onSave: (RecQuestion) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: RecQuestion
    @State private var options: [String]
    @State private var newOption = ""
    @State private var error: String? = nil
    @FocusState private var labelFocused: Bool

    init(question: RecQuestion, isNew: Bool, onSave: @escaping (RecQuestion) -> Void) {
        self.isNew = isNew
        self.onSave = onSave
        _draft = State(initialValue: question)
        _options = State(initialValue: question.options ?? [])
    }

    private static let kinds: [(value: String, title: String, icon: String)] = [
        ("text", "Texto livre", "text.alignleft"),
        ("single", "Escolha única", "largecircle.fill.circle"),
        ("multiple", "Múltipla escolha", "checkmark.square"),
    ]

    private var isChoice: Bool { draft.kind != "text" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section("PERGUNTA") {
                        TextField("Ex.: Humor na sessão", text: $draft.label, axis: .vertical)
                            .font(Theme.body(16))
                            .focused($labelFocused)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Theme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
                            .accessibilityIdentifier("recQuestionLabel")
                    }

                    section("TIPO") {
                        VStack(spacing: 8) {
                            ForEach(Self.kinds, id: \.value) { k in
                                Button {
                                    Haptics.tap()
                                    draft.kind = k.value
                                    error = nil
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: k.icon)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(draft.kind == k.value ? Theme.primary : Theme.textSecondary)
                                            .frame(width: 22)
                                        Text(k.title)
                                            .font(Theme.body(15, weight: draft.kind == k.value ? .semibold : .regular))
                                            .foregroundStyle(Theme.textPrimary)
                                        Spacer()
                                        if draft.kind == k.value {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundStyle(Theme.primary)
                                        }
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .background(draft.kind == k.value ? Theme.primarySoft.opacity(0.6) : Theme.surface)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(draft.kind == k.value ? Theme.primary.opacity(0.5) : Theme.border, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.pressableSubtle)
                                .accessibilityIdentifier("recQuestionKind_\(k.value)")
                            }
                        }
                    }

                    if isChoice {
                        section("OPÇÕES") {
                            VStack(spacing: 8) {
                                ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                                    HStack(spacing: 10) {
                                        Image(systemName: draft.kind == "single" ? "circle" : "square")
                                            .foregroundStyle(Theme.textSecondary.opacity(0.6))
                                        Text(option)
                                            .font(Theme.body(15))
                                            .foregroundStyle(Theme.textPrimary)
                                        Spacer()
                                        Button {
                                            options.remove(at: index)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(Theme.textSecondary.opacity(0.6))
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Remover opção \(option)")
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 11)
                                    .background(Theme.surface)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
                                }
                                HStack(spacing: 8) {
                                    TextField("Nova opção", text: $newOption)
                                        .font(Theme.body(15))
                                        .submitLabel(.done)
                                        .onSubmit(addOption)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 11)
                                        .background(Theme.surface)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
                                        .accessibilityIdentifier("recQuestionNewOption")
                                    Button(action: addOption) {
                                        Image(systemName: "plus")
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundStyle(.white)
                                            .frame(width: 44, height: 44)
                                            .background(Theme.primary, in: RoundedRectangle(cornerRadius: 12))
                                    }
                                    .buttonStyle(.pressable)
                                    .accessibilityIdentifier("recQuestionAddOption")
                                }
                            }
                        }
                    }

                    Toggle(isOn: Binding(
                        get: { draft.required ?? false },
                        set: { draft.required = $0 ? true : nil }
                    )) {
                        Text("Resposta obrigatória")
                            .font(Theme.body(15))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .tint(Theme.primary)

                    if let error {
                        Text(error)
                            .font(Theme.body(13, weight: .medium))
                            .foregroundStyle(Theme.danger)
                    }
                }
                .padding(Theme.screenPadding)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(isNew ? "Nova pergunta" : "Editar pergunta")
                        .font(Theme.serifTitle(18))
                        .foregroundStyle(Theme.textPrimary)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }
                        .foregroundStyle(Theme.textPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isNew ? "Adicionar" : "Salvar", action: save)
                        .font(Theme.body(16, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                        .accessibilityIdentifier("recQuestionSave")
                }
            }
            .onAppear { if isNew { labelFocused = true } }
        }
        .presentationDetents([.large])
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Theme.body(11, weight: .semibold))
                .tracking(1)
                .foregroundStyle(Theme.textSecondary)
            content()
        }
    }

    private func addOption() {
        let value = newOption.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        guard !options.contains(value) else {
            error = "Essa opção já existe."
            return
        }
        options.append(value)
        newOption = ""
        error = nil
    }

    private func save() {
        // Opção digitada e não confirmada também entra.
        if !newOption.trimmingCharacters(in: .whitespaces).isEmpty { addOption() }
        let label = draft.label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else {
            error = "Escreva a pergunta."
            return
        }
        var saved = draft
        saved.label = label
        if isChoice {
            guard options.count >= 2 else {
                error = "Coloque pelo menos 2 opções."
                return
            }
            saved.options = options
        } else {
            saved.options = nil
        }
        Haptics.success()
        onSave(saved)
        dismiss()
    }
}
