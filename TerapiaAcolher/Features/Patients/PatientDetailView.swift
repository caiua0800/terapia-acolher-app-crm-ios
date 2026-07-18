import SwiftUI

// MARK: - ViewModel

@Observable
final class PatientDetailViewModel {
    let patientId: String
    var detail: PatientDetail?
    var isLoading = true
    var errorMessage: String? = nil
    var isDeleting = false
    var deleteError: String? = nil

    init(patientId: String) {
        self.patientId = patientId
    }

    @MainActor
    func load() async {
        isLoading = detail == nil
        errorMessage = nil
        do {
            detail = try await PatientsAPI.detail(id: patientId)
        } catch let error as APIError {
            errorMessage = error.message
        } catch {
            errorMessage = "Não foi possível carregar a ficha."
        }
        isLoading = false
    }

    @MainActor
    func delete() async -> Bool {
        isDeleting = true
        deleteError = nil
        do {
            _ = try await PatientsAPI.delete(id: patientId)
            isDeleting = false
            return true
        } catch let error as APIError {
            deleteError = error.message
        } catch {
            deleteError = "Não foi possível excluir o paciente."
        }
        isDeleting = false
        return false
    }
}

// MARK: - Tela: Ficha do paciente

struct PatientDetailView: View {
    @State private var model: PatientDetailViewModel
    @State private var showDeleteModal = false
    @State private var showEdit = false
    @State private var showScheduleInfo = false
    @Environment(\.dismiss) private var dismiss

    /// Chamado após exclusão bem-sucedida (nome do paciente) — a lista mostra o toast.
    var onDeleted: (String) -> Void = { _ in }

    init(patientId: String, onDeleted: @escaping (String) -> Void = { _ in }) {
        _model = State(initialValue: PatientDetailViewModel(patientId: patientId))
        self.onDeleted = onDeleted
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            content
            if showDeleteModal, let detail = model.detail {
                PatientDeleteModal(
                    patientName: detail.name,
                    isDeleting: model.isDeleting,
                    errorMessage: model.deleteError,
                    onCancel: { showDeleteModal = false },
                    onConfirm: {
                        Task {
                            if await model.delete() {
                                showDeleteModal = false
                                onDeleted(detail.name)
                                dismiss()
                            }
                        }
                    }
                )
            }
        }
        .navigationTitle("Ficha")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Ficha")
                    .font(Theme.serifTitle(20))
                    .foregroundStyle(Theme.textPrimary)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showEdit = true
                    } label: {
                        Label("Editar paciente", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        model.deleteError = nil
                        showDeleteModal = true
                    } label: {
                        Label("Excluir paciente", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(Theme.textPrimary)
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            if let detail = model.detail {
                PatientFormView(mode: .edit(detail)) { _ in
                    Task { await model.load() }
                }
            }
        }
        .task { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading {
            ProgressView().tint(Theme.primary)
        } else if let error = model.errorMessage {
            ErrorRetryView(message: error) { Task { await model.load() } }
        } else if let detail = model.detail {
            ScrollView {
                VStack(spacing: 20) {
                    header(detail)
                    statsCard(detail)
                    scheduleButton(detail)
                    sectionsCard(detail)
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 16)
                .padding(.bottom, 48)
            }
            .refreshable { await model.load() }
        }
    }

    // MARK: Cabeçalho

    private func header(_ detail: PatientDetail) -> some View {
        VStack(spacing: 14) {
            InitialAvatar(name: detail.name, colorHex: detail.group?.color, size: 96)
            Text(detail.name)
                .font(Theme.serifTitle(26))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Text(subtitle(detail))
                .font(Theme.body(13))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func subtitle(_ detail: PatientDetail) -> String {
        var parts: [String] = []
        if let group = detail.group { parts.append(group.name) }
        parts.append(PatientFormat.sinceLabel(detail.createdAt))
        if let cpf = detail.cpfMasked { parts.append("CPF \(cpf)") }
        return parts.joined(separator: " · ")
    }

    // MARK: Stats

    private func statsCard(_ detail: PatientDetail) -> some View {
        ThemeCard {
            HStack(spacing: 0) {
                statColumn(value: detail.stats?.totalSessions ?? 0, label: "SESSÕES")
                divider
                statColumn(value: detail.stats?.attended ?? 0, label: "ATENDIDAS")
                divider
                statColumn(value: detail.stats?.missed ?? 0, label: "FALTAS")
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(Theme.border).frame(width: 1, height: 44)
    }

    private func statColumn(value: Int, label: String) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(Theme.money(26, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(Theme.body(10, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .tracking(1)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Agendar
    // O módulo de chat foi CORTADO do produto — sem botão "Conversar".
    // Integração com a Agenda: por ora navega-se pelo menu lateral; o botão
    // publica uma notificação que a feature Agenda pode ouvir no futuro.

    private func scheduleButton(_ detail: PatientDetail) -> some View {
        Button {
            NotificationCenter.default.post(
                name: Notification.Name("TA.agenda.newSession"),
                object: nil,
                userInfo: ["patientId": detail.id, "patientName": detail.name]
            )
            showScheduleInfo = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.square")
                Text("Agendar")
                    .font(Theme.body(16, weight: .semibold))
            }
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).stroke(Theme.ink.opacity(0.5), lineWidth: 1.2))
        }
        .alert("Agendar sessão", isPresented: $showScheduleInfo) {
            Button("Entendi", role: .cancel) {}
        } message: {
            Text("Abra a Agenda pelo menu lateral para criar a sessão de \(detail.name).")
        }
    }

    // MARK: Seções

    private func sectionsCard(_ detail: PatientDetail) -> some View {
        ThemeCard(padding: 0) {
            VStack(spacing: 0) {
                NavigationLink {
                    PatientMainDataView(patientId: detail.id)
                } label: {
                    sectionRow(icon: "person", tint: Theme.primary, title: "Dados principais")
                }
                rowDivider
                NavigationLink {
                    RecTimelineView(patient: RecPatientRef(from: detail), kind: .record)
                } label: {
                    sectionRow(icon: "doc.text", tint: Color(hex: 0xB9A6D9), title: "Prontuário")
                }
                rowDivider
                NavigationLink {
                    RecTimelineView(patient: RecPatientRef(from: detail), kind: .anamnesis)
                } label: {
                    sectionRow(icon: "pencil.line", tint: Color(hex: 0x7FA8C9), title: "Anamnese")
                }
                rowDivider
                NavigationLink {
                    RecNotesView(patient: RecPatientRef(from: detail))
                } label: {
                    sectionRow(icon: "list.clipboard", tint: Theme.primary, title: "Anotações de sessão")
                }
                rowDivider
                sectionRow(
                    icon: "dollarsign",
                    tint: Theme.warning,
                    title: "Financeiro",
                    trailing: Formatters.brl(detail.pendingBalance ?? 0)
                )
            }
        }
    }

    private var rowDivider: some View {
        Divider().overlay(Theme.border).padding(.leading, 60)
    }

    private func sectionRow(icon: String, tint: Color, title: String, trailing: String? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 9))
            Text(title)
                .font(Theme.body(15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(Theme.money(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary.opacity(0.5))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

// MARK: - Modal destrutivo (fiel ao print)

struct PatientDeleteModal: View {
    let patientName: String
    let isDeleting: Bool
    let errorMessage: String?
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { if !isDeleting { onCancel() } }

            VStack(spacing: 18) {
                Circle()
                    .fill(Theme.dangerSoft)
                    .frame(width: 64, height: 64)
                    .overlay(
                        Image(systemName: "trash")
                            .font(.system(size: 24))
                            .foregroundStyle(Theme.danger)
                    )

                Text("Excluir paciente?")
                    .font(Theme.serifTitle(22))
                    .foregroundStyle(Theme.textPrimary)

                Group {
                    Text("Todos os dados de ").font(Theme.body(14))
                        + Text(patientName).font(Theme.body(14, weight: .bold))
                        + Text(" serão apagados — prontuário, anamnese, sessões, documentos e arquivos. Esta ação não pode ser desfeita.")
                        .font(Theme.body(14))
                }
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)

                if let errorMessage {
                    Text(errorMessage)
                        .font(Theme.body(13, weight: .medium))
                        .foregroundStyle(Theme.danger)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 12) {
                    Button(action: onCancel) {
                        Text("Cancelar")
                            .font(Theme.body(15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Theme.background)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
                    }
                    .disabled(isDeleting)

                    Button(action: onConfirm) {
                        Group {
                            if isDeleting {
                                ProgressView().tint(.white)
                            } else {
                                Text("Excluir")
                                    .font(Theme.body(15, weight: .semibold))
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Theme.danger)
                        .clipShape(Capsule())
                    }
                    .disabled(isDeleting)
                }
                .padding(.top, 4)
            }
            .padding(24)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .padding(.horizontal, 32)
        }
        .transition(.opacity)
    }
}
