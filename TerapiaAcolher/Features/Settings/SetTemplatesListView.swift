import Observation
import SwiftUI

/// Tela de modelos por tipo — fiel ao MVP: texto explicando o form-builder,
/// SEUS MODELOS (editáveis) vs MODELOS DO SISTEMA (somente leitura,
/// duplicar / restaurar padrão original) e "+ Novo modelo".
struct SetTemplatesListView: View {
    let type: SetTemplateType
    var onChanged: () -> Void = {}

    @State private var viewModel = SetTemplatesViewModel()
    @State private var editingTemplate: SetTemplate?
    @State private var showNewEditor = false
    @State private var systemActionTemplate: SetTemplate?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if viewModel.isLoading {
                ProgressView().tint(Theme.primary)
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        intro
                        seusModelos
                        modelosDoSistema
                        novoModeloButton
                        rodape
                    }
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.vertical, 16)
                }
            }
        }
        .setToolbarTitle(type.screenTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load(type: type) }
        .refreshable { await viewModel.load(type: type) }
        .sheet(isPresented: $showNewEditor) {
            SetTemplateEditorView(type: type, existing: nil) {
                Task {
                    await viewModel.load(type: type)
                    onChanged()
                }
            }
        }
        .sheet(item: $editingTemplate) { template in
            SetTemplateEditorView(type: type, existing: template) {
                Task {
                    await viewModel.load(type: type)
                    onChanged()
                }
            }
        }
        .confirmationDialog(
            systemActionTemplate.map { "\($0.name) · modelo do sistema" } ?? "",
            isPresented: Binding(
                get: { systemActionTemplate != nil },
                set: { if !$0 { systemActionTemplate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Duplicar para meus modelos") {
                if let template = systemActionTemplate {
                    Task {
                        await viewModel.duplicate(template)
                        onChanged()
                    }
                }
            }
            Button("Restaurar padrão original") {
                Task {
                    await viewModel.restoreDefaults(type: type)
                    onChanged()
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Modelos do sistema são somente leitura. Duplique para editar, ou restaure o padrão original para seus modelos.")
        }
        .alert("Ops", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "Algo deu errado.")
        }
        .alert("Padrão restaurado", isPresented: $viewModel.showRestored) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.restoredMessage)
        }
    }

    // MARK: - Blocos

    private var intro: some View {
        Text(introAttributed)
            .font(Theme.body(14))
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
    }

    private var introAttributed: AttributedString {
        (try? AttributedString(markdown: type.isForm
            ? "Cada modelo é um **form-builder**: adicione perguntas em texto livre, escolha única ou múltipla. Ao criar um novo registro, você seleciona um modelo como base — e pode personalizar durante o preenchimento."
            : "Cada modelo é um **texto com variáveis** como {nome\\_paciente} e {valor}, substituídas automaticamente na hora de gerar. Toque em { } no editor para inserir uma variável."))
            ?? AttributedString(type.intro)
    }

    private var seusModelos: some View {
        VStack(spacing: 8) {
            SetSectionHeader(title: "Seus modelos")
            if viewModel.userTemplates.isEmpty {
                ThemeCard {
                    Text("Você ainda não tem modelos seus. Crie um novo ou duplique um modelo do sistema.")
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ThemeCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(viewModel.userTemplates.enumerated()), id: \.element.id) { index, template in
                            if index > 0 { Divider().padding(.leading, 62) }
                            Button {
                                editingTemplate = template
                            } label: {
                                templateRow(template)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var modelosDoSistema: some View {
        VStack(spacing: 8) {
            SetSectionHeader(title: "Modelos do sistema")
            if viewModel.systemTemplates.isEmpty {
                ThemeCard {
                    Text("Nenhum modelo do sistema para este tipo.")
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ThemeCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(viewModel.systemTemplates.enumerated()), id: \.element.id) { index, template in
                            if index > 0 { Divider().padding(.leading, 62) }
                            Button {
                                systemActionTemplate = template
                            } label: {
                                SetRow(
                                    icon: type.icon,
                                    iconColor: Theme.textSecondary,
                                    title: "\(template.name) (original)",
                                    subtitle: "Restaurar para o modelo original"
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var novoModeloButton: some View {
        Button {
            showNewEditor = true
        } label: {
            Text("+ Novo modelo")
                .font(Theme.body(15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Theme.primarySoft.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerRadius)
                        .stroke(Theme.primary.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                )
        }
    }

    private var rodape: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 1)
            Text("Alterações em modelos preservam registros já preenchidos.")
                .font(Theme.body(12))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
    }

    private func templateRow(_ template: SetTemplate) -> some View {
        SetRow(
            icon: type.icon,
            iconColor: type.tint,
            title: template.name,
            subtitle: subtitle(for: template)
        )
    }

    private func subtitle(for template: SetTemplate) -> String {
        if type.isForm {
            let count = template.schema.questions?.count ?? 0
            let perguntas = count == 1 ? "1 pergunta" : "\(count) perguntas"
            let pacientes = template.patientsInUse ?? 0
            if pacientes > 0 {
                return "\(perguntas) · em uso por \(pacientes) \(pacientes == 1 ? "paciente" : "pacientes")"
            }
            return perguntas
        }
        let content = (template.schema.content ?? "").replacingOccurrences(of: "\n", with: " ")
        return content.count > 60 ? String(content.prefix(60)) + "…" : content
    }
}

// MARK: - ViewModel

@Observable
final class SetTemplatesViewModel {
    var userTemplates: [SetTemplate] = []
    var systemTemplates: [SetTemplate] = []
    var isLoading = true
    var errorMessage: String?
    var showError = false
    var showRestored = false
    var restoredMessage = ""

    @MainActor
    func load(type: SetTemplateType) async {
        do {
            let all: [SetTemplate] = try await APIClient.shared.get(
                "templates", query: ["type": type.rawValue]
            )
            userTemplates = all.filter { !$0.isSystem }
            systemTemplates = all.filter(\.isSystem)
            isLoading = false
        } catch {
            isLoading = false
            present(error)
        }
    }

    @MainActor
    func duplicate(_ template: SetTemplate) async {
        do {
            let _: EmptyResponse = try await APIClient.shared.post("templates/\(template.id)/duplicate")
            await load(type: SetTemplateType(rawValue: template.type) ?? .record)
        } catch {
            present(error)
        }
    }

    @MainActor
    func restoreDefaults(type: SetTemplateType) async {
        do {
            let result: SetRestoreResult = try await SetAPI.postQuery(
                "templates/restore-defaults",
                query: ["type": type.rawValue]
            )
            restoredMessage = result.restored == 0
                ? "Você já tem todos os modelos padrão deste tipo."
                : (result.restored == 1
                    ? "1 modelo padrão foi restaurado para seus modelos."
                    : "\(result.restored) modelos padrão foram restaurados para seus modelos.")
            showRestored = true
            await load(type: type)
        } catch {
            present(error)
        }
    }

    @MainActor
    private func present(_ error: Error) {
        errorMessage = (error as? APIError)?.message ?? "Não foi possível concluir. Verifique sua conexão."
        showError = true
    }
}
