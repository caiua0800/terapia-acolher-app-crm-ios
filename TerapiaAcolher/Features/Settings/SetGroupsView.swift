import Observation
import SwiftUI

/// Grupos de pacientes — CRUD completo (listar, criar, renomear, cor, excluir).
/// Exclusão com pacientes vinculados retorna 409 do backend (alert PT-BR).
struct SetGroupsView: View {
    var onChanged: () -> Void = {}

    @State private var viewModel = SetGroupsViewModel()
    @State private var editingGroup: SetGroup?
    @State private var showNewSheet = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Theme.background.ignoresSafeArea()
            if viewModel.isLoading {
                ProgressView().tint(Theme.primary)
            } else if viewModel.groups.isEmpty {
                EmptyStateView(
                    icon: "circle.grid.2x2",
                    title: "Organize seus pacientes",
                    message: "Crie grupos como Adultos, Adolescentes ou Casal para organizar sua base.",
                    actionTitle: "Novo grupo",
                    action: { showNewSheet = true }
                )
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        SetSectionHeader(title: "Seus grupos")
                        ThemeCard(padding: 0) {
                            VStack(spacing: 0) {
                                ForEach(Array(viewModel.groups.enumerated()), id: \.element.id) { index, group in
                                    if index > 0 { Divider().padding(.leading, 52) }
                                    Button {
                                        editingGroup = group
                                    } label: {
                                        groupRow(group)
                                    }
                                    .buttonStyle(.pressableSubtle)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.vertical, 16)
                    .padding(.bottom, 80)
                }
            }

            if !viewModel.groups.isEmpty {
                FloatingActionButton { showNewSheet = true }
                    .padding(.trailing, Theme.screenPadding)
                    .padding(.bottom, 24)
            }
        }
        .setToolbarTitle("Grupos de pacientes")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .sheet(isPresented: $showNewSheet) {
            SetGroupFormView(group: nil) {
                Task {
                    await viewModel.load()
                    onChanged()
                }
            }
        }
        .sheet(item: $editingGroup) { group in
            SetGroupFormView(group: group) {
                Task {
                    await viewModel.load()
                    onChanged()
                }
            }
        }
        .alert("Ops", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "Algo deu errado.")
        }
    }

    private func groupRow(_ group: SetGroup) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Theme.groupColor(group.color))
                .frame(width: 14, height: 14)
                .padding(.leading, 4)
            Text(group.name)
                .font(Theme.body(15, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 8)
            Text(group.patientCount == 1 ? "1 paciente" : "\(group.patientCount) pacientes")
                .font(Theme.body(13))
                .foregroundStyle(Theme.textSecondary)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary.opacity(0.6))
        }
        .padding(.horizontal, Theme.cardPadding)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

// MARK: - Formulário (criar / editar / excluir)

struct SetGroupFormView: View {
    let group: SetGroup?
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var color: String
    @State private var isSaving = false
    @State private var isDeleting = false
    @State private var showDeleteConfirm = false
    @State private var errorMessage: String?
    @State private var showError = false

    /// Paleta do MVP (mesmos hex do seed do backend) + extras harmônicas.
    private let palette = [
        "#8FBCA6", "#B9A6D9", "#E8B98A", "#E9A3B4",
        "#7FA8C9", "#C9C97F", "#A3C9C0", "#D9A6A6",
    ]

    init(group: SetGroup?, onSaved: @escaping () -> Void) {
        self.group = group
        self.onSaved = onSaved
        _name = State(initialValue: group?.name ?? "")
        _color = State(initialValue: group?.color ?? "#8FBCA6")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        VStack(spacing: 8) {
                            SetSectionHeader(title: "Nome do grupo")
                            ThemeCard {
                                TextField("Ex.: Adultos", text: $name)
                                    .font(Theme.body(16))
                            }
                        }

                        VStack(spacing: 8) {
                            SetSectionHeader(title: "Cor da tag")
                            ThemeCard {
                                LazyVGrid(
                                    columns: Array(repeating: GridItem(.flexible()), count: 4),
                                    spacing: 14
                                ) {
                                    ForEach(palette, id: \.self) { hex in
                                        Button {
                                            color = hex
                                        } label: {
                                            Circle()
                                                .fill(Theme.groupColor(hex))
                                                .frame(width: 40, height: 40)
                                                .overlay(
                                                    Circle().stroke(
                                                        color == hex ? Theme.ink : Color.clear,
                                                        lineWidth: 2.5
                                                    )
                                                    .padding(-4)
                                                )
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }

                        if !name.trimmingCharacters(in: .whitespaces).isEmpty {
                            HStack {
                                Text("Pré-visualização")
                                    .font(Theme.body(12))
                                    .foregroundStyle(Theme.textSecondary)
                                GroupTag(name: name, colorHex: color)
                                Spacer()
                            }
                            .padding(.horizontal, 4)
                        }

                        if group != nil {
                            Button {
                                showDeleteConfirm = true
                            } label: {
                                HStack {
                                    if isDeleting {
                                        ProgressView().tint(Theme.danger)
                                    } else {
                                        Label("Excluir grupo", systemImage: "trash")
                                    }
                                }
                                .font(Theme.body(15, weight: .semibold))
                                .foregroundStyle(Theme.danger)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Theme.dangerSoft)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                            }
                            .confirmationDialog(
                                "Excluir este grupo?",
                                isPresented: $showDeleteConfirm,
                                titleVisibility: .visible
                            ) {
                                Button("Excluir", role: .destructive) {
                                    Task { await deleteGroup() }
                                }
                                Button("Cancelar", role: .cancel) {}
                            } message: {
                                Text("Só é possível excluir grupos sem pacientes vinculados.")
                            }
                            .disabled(isDeleting)
                        }
                    }
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.vertical, 16)
                }
            }
            .setToolbarTitle(group == nil ? "Novo grupo" : "Editar grupo")
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
                                .foregroundStyle(Theme.primary)
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .alert("Ops", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Algo deu errado.")
            }
        }
    }

    private func save() async {
        struct Body: Encodable {
            let name: String
            let color: String
        }
        isSaving = true
        defer { isSaving = false }
        let body = Body(name: name.trimmingCharacters(in: .whitespaces), color: color)
        do {
            if let group {
                let _: EmptyResponse = try await APIClient.shared.patch("patient-groups/\(group.id)", body: body)
            } else {
                let _: EmptyResponse = try await APIClient.shared.post("patient-groups", body: body)
            }
            onSaved()
            dismiss()
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
        } catch {
            errorMessage = (error as? APIError)?.message ?? "Não foi possível salvar o grupo."
            showError = true
        }
    }

    private func deleteGroup() async {
        guard let group else { return }
        isDeleting = true
        defer { isDeleting = false }
        do {
            let _: EmptyResponse = try await APIClient.shared.delete("patient-groups/\(group.id)")
            onSaved()
            dismiss()
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
        } catch {
            // 409 do backend: grupo com pacientes vinculados.
            errorMessage = (error as? APIError)?.message ?? "Não foi possível excluir o grupo."
            showError = true
        }
    }
}

@Observable
final class SetGroupsViewModel {
    var groups: [SetGroup] = []
    var isLoading = true
    var errorMessage: String?
    var showError = false

    @MainActor
    func load() async {
        do {
            groups = try await APIClient.shared.get("patient-groups")
            isLoading = false
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
        } catch {
            isLoading = false
            errorMessage = (error as? APIError)?.message ?? "Não foi possível carregar os grupos."
            showError = true
        }
    }
}
