import SwiftUI

// MARK: - ViewModel

@Observable
final class PatientMainDataViewModel {
    let patientId: String
    var detail: PatientDetail?
    var revealedCpf: String? = nil
    var isLoading = true
    var isRevealing = false
    var errorMessage: String? = nil
    var revealError: String? = nil

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
            errorMessage = "Não foi possível carregar os dados."
        }
        isLoading = false
    }

    /// GET /patients/:id?revealCpf=true — decifra com trilha de auditoria no backend.
    @MainActor
    func revealCpf() async {
        isRevealing = true
        revealError = nil
        do {
            let full = try await PatientsAPI.detail(id: patientId, revealCpf: true)
            if let cpf = full.cpf {
                revealedCpf = Self.formatCpf(cpf)
            } else {
                revealError = "CPF não cadastrado."
            }
        } catch let error as APIError {
            revealError = error.message
        } catch {
            revealError = "Não foi possível revelar o CPF."
        }
        isRevealing = false
    }

    private static func formatCpf(_ digits: String) -> String {
        guard digits.count == 11 else { return digits }
        let d = Array(digits)
        return "\(String(d[0...2])).\(String(d[3...5])).\(String(d[6...8]))-\(String(d[9...10]))"
    }
}

// MARK: - Tela: Dados principais (leitura + atalho de edição)

struct PatientMainDataView: View {
    @State private var model: PatientMainDataViewModel
    @State private var showEdit = false

    init(patientId: String) {
        _model = State(initialValue: PatientMainDataViewModel(patientId: patientId))
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            content
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Dados principais")
                    .font(Theme.serifTitle(19))
                    .foregroundStyle(Theme.textPrimary)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Editar") { showEdit = true }
                    .font(Theme.body(15, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .disabled(model.detail == nil)
            }
        }
        .sheet(isPresented: $showEdit) {
            if let detail = model.detail {
                PatientFormView(mode: .edit(detail)) { _ in
                    model.revealedCpf = nil
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
                VStack(spacing: 16) {
                    identitySection(detail)
                    if detail.guardianName != nil || detail.guardianContact != nil {
                        guardianSection(detail)
                    }
                    financeSection(detail)
                    automationsSection(detail)
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.vertical, 16)
            }
            .refreshable { await model.load() }
        }
    }

    // MARK: Seções de leitura

    private func identitySection(_ detail: PatientDetail) -> some View {
        PatientFormSection(icon: "person", title: "IDENTIFICAÇÃO") {
            readRow("Nome", detail.name)
            Divider().overlay(Theme.border)
            readRow("Grupo", detail.group?.name ?? "—")
            Divider().overlay(Theme.border)
            readRow("WhatsApp", detail.whatsapp ?? "—")
            Divider().overlay(Theme.border)
            readRow("E-mail", detail.email ?? "—")
            Divider().overlay(Theme.border)
            cpfRow(detail)
            Divider().overlay(Theme.border)
            readRow(
                "Nascimento",
                // Dia-calendário gravado à meia-noite UTC → formatar em UTC
                // (no fuso local mostraria o dia anterior).
                detail.birthDate.map { PatientFormat.fullDateUTC.string(from: $0) } ?? "—"
            )
            Divider().overlay(Theme.border)
            readRow("Status", detail.status == "ACTIVE" ? "Ativo" : "Inativo")
        }
    }

    private func cpfRow(_ detail: PatientDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text("CPF")
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(model.revealedCpf ?? detail.cpfMasked ?? "—")
                    .font(Theme.money(15))
                    .foregroundStyle(Theme.textPrimary)
                if detail.cpfMasked != nil && model.revealedCpf == nil {
                    Button {
                        Task { await model.revealCpf() }
                    } label: {
                        if model.isRevealing {
                            ProgressView().tint(Theme.primary)
                        } else {
                            Label("Revelar", systemImage: "eye")
                                .font(Theme.body(13, weight: .semibold))
                                .foregroundStyle(Theme.primary)
                        }
                    }
                } else if model.revealedCpf != nil {
                    Button {
                        model.revealedCpf = nil
                    } label: {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            if let revealError = model.revealError {
                Text(revealError)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.danger)
            }
        }
        .padding(.vertical, 8)
    }

    private func guardianSection(_ detail: PatientDetail) -> some View {
        PatientFormSection(icon: "figure.and.child.holdinghands", title: "RESPONSÁVEL") {
            readRow("Nome", detail.guardianName ?? "—")
            Divider().overlay(Theme.border)
            readRow("Contato", detail.guardianContact ?? "—")
            Divider().overlay(Theme.border)
            readRow("É o pagador", detail.guardianIsPayer ? "Sim" : "Não")
        }
    }

    private func financeSection(_ detail: PatientDetail) -> some View {
        PatientFormSection(icon: "dollarsign", title: "FINANCEIRO") {
            readRow(
                "Valor por sessão",
                detail.sessionPrice.map { Formatters.brl($0) } ?? "—"
            )
            Divider().overlay(Theme.border)
            readRow("Dia de cobrança", detail.billingDay.map { "Dia \($0)" } ?? "—")
            Divider().overlay(Theme.border)
            readRow("Lembrete mensal de cobrança", detail.monthlyBillingReminder ? "Ativo" : "Desativado")
        }
    }

    private func automationsSection(_ detail: PatientDetail) -> some View {
        PatientFormSection(icon: "bell", title: "AUTOMAÇÕES") {
            readRow("Lembrete de sessão · 24h", detail.sessionReminder24h ? "Ativo" : "Desativado")
            Divider().overlay(Theme.border)
            readRow("Lembrete de videochamada · 1h", detail.videoReminder1h ? "Ativo" : "Desativado")
            Divider().overlay(Theme.border)
            readRow("Cadastro ativo", detail.registrationActive ? "Sim" : "Não")
        }
    }

    private func readRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(Theme.body(15))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(Theme.body(15, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 8)
    }
}
