import SafariServices
import SwiftUI

// MARK: - Navegador in-app (links de pagamento, PDFs)

struct FinSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

/// URL identificável pra usar com .sheet(item:).
struct FinWebLink: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

// MARK: - Segmented "Registros | Balanço" fiel ao design

struct FinSegmentedControl<Option: Hashable>: View {
    let options: [(label: String, value: Option)]
    @Binding var selection: Option

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { selection = option.value }
                } label: {
                    Text(option.label)
                        .font(Theme.body(15, weight: selection == option.value ? .semibold : .regular))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            selection == option.value ? Theme.surface : Color.clear,
                            in: Capsule()
                        )
                        .shadow(
                            color: selection == option.value ? Color.black.opacity(0.06) : .clear,
                            radius: 4, y: 1
                        )
                }
            }
        }
        .padding(4)
        .background(Color(hex: 0xF1ECE1), in: Capsule())
    }
}

// MARK: - Seletor leve de paciente (usado por Cobranças e formulários)

@MainActor
@Observable
final class FinPatientPickerModel {
    var patients: [FinPatientRef] = []
    var search = ""
    var isLoading = false
    var errorMessage: String?

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            patients = try await FinanceAPI.patients(search: search.isEmpty ? nil : search)
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
        } catch {
            errorMessage = (error as? APIError)?.message ?? "Não foi possível carregar os pacientes."
        }
    }
}

/// Lista de pacientes com busca; chama `onSelect` ao tocar.
struct FinPatientPickerView: View {
    var subtitle = "Escolha o paciente"
    let onSelect: (FinPatientRef) -> Void

    @State private var model = FinPatientPickerModel()

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(Theme.textSecondary)
                        TextField("Buscar paciente...", text: $model.search)
                            .font(Theme.body(15))
                            .autocorrectionDisabled()
                            .onSubmit { Task { await model.load() } }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Theme.surface, in: Capsule())
                    .overlay(Capsule().stroke(Theme.border, lineWidth: 1))

                    if model.isLoading, model.patients.isEmpty {
                        ProgressView().padding(.top, 40)
                    } else if model.patients.isEmpty {
                        EmptyStateView(
                            icon: "person.2",
                            title: "Nenhum paciente",
                            message: "Cadastre pacientes para usar esta área."
                        )
                    } else {
                        VStack(spacing: 0) {
                            ForEach(model.patients) { patient in
                                Button {
                                    onSelect(patient)
                                } label: {
                                    PatientPickerRow(name: patient.name)
                                }
                                .buttonStyle(.pressableSubtle)
                                if patient.id != model.patients.last?.id {
                                    InsetDivider()
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
                }
                .padding(Theme.screenPadding)
            }
        }
        .task { await model.load() }
        .alert("Ops", isPresented: .init(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

// MARK: - Célula de transação (Registros e Últimas movimentações)

struct FinTransactionCell: View {
    let transaction: FinTransaction
    @Binding var expandedId: String?
    var isDeleting: Bool = false
    var onEdit: (FinTransaction) -> Void
    var onDelete: (FinTransaction) -> Void

    private var isIncome: Bool { transaction.type == .income }
    private var isExpanded: Bool { expandedId == transaction.id }

    /// Valor recebido quando menor que o valor cheio (recebimento parcial).
    private var partialReceived: Double? {
        guard let received = transaction.receivedAmount, received < transaction.amount else {
            return nil
        }
        return received
    }

    /// Entrada do gateway: a diferença é taxa retida (split), não pendência.
    private var isGateway: Bool { transaction.source == "GATEWAY" }

    private var subtitle: String {
        var parts: [String] = [FinFormat.relativeDay(transaction.date)]
        if let category = transaction.category, !category.isEmpty {
            parts.append(category)
        } else if let patient = transaction.patient,
                  !transaction.description.localizedCaseInsensitiveContains(patient.name) {
            // não repete o nome quando a descrição já o contém ("Sessão · Maria...")
            parts.append(patient.name)
        }
        if let source = transaction.sourceLabel { parts.append(source) }
        if transaction.isRecurring, transaction.category?.isEmpty != false { parts.append("Recorrente") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    expandedId = isExpanded ? nil : transaction.id
                }
            } label: {
                HStack(spacing: 12) {
                    Circle()
                        .fill(isIncome ? Theme.successSoft : Theme.dangerSoft)
                        .frame(width: 38, height: 38)
                        .overlay(
                            Image(systemName: isIncome ? "chevron.down" : "chevron.up")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(isIncome ? Theme.success : Theme.danger)
                        )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(transaction.description)
                            .font(Theme.body(15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Text(subtitle)
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(isIncome ? "+" : "−") \(Formatters.brl(transaction.amount))")
                            .font(Theme.money(15, weight: .semibold))
                            .foregroundStyle(isIncome ? Theme.success : Theme.danger)
                        if let received = partialReceived {
                            HStack(spacing: 3) {
                                Image(systemName: isGateway ? "percent" : "circle.lefthalf.filled")
                                    .font(.system(size: 8, weight: .bold))
                                Text("\(isGateway ? "Líquido" : "Recebido") \(Formatters.brl(received))")
                                    .font(Theme.money(10, weight: .semibold))
                            }
                            .foregroundStyle(isGateway ? Theme.textSecondary : Theme.warning)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background((isGateway ? Theme.textSecondary : Theme.warning).opacity(0.12))
                            .clipShape(Capsule())
                        }
                    }
                }
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressableSubtle)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    if let received = partialReceived {
                        if isGateway {
                            detailRow("Valor líquido", Formatters.brl(received))
                            detailRow("Taxa da transação", Formatters.brl(transaction.amount - received))
                        } else {
                            detailRow("Valor recebido", Formatters.brl(received))
                            detailRow("Falta receber", Formatters.brl(transaction.amount - received))
                        }
                    }
                    if let patient = transaction.patient {
                        detailRow("Paciente", patient.name)
                    }
                    if let category = transaction.category, !category.isEmpty {
                        detailRow("Categoria", category)
                    }
                    detailRow("Recorrente", transaction.isRecurring ? "Sim" : "Não")
                    if transaction.isEditable {
                        HStack(spacing: 10) {
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                onEdit(transaction)
                            } label: {
                                Label("Editar", systemImage: "pencil")
                                    .font(Theme.body(13, weight: .semibold))
                                    .foregroundStyle(Theme.primary)
                            }
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                onDelete(transaction)
                            } label: {
                                HStack(spacing: 4) {
                                    if isDeleting {
                                        ProgressView()
                                            .controlSize(.mini)
                                            .tint(Theme.danger)
                                        Text("Excluindo…")
                                    } else {
                                        Label("Excluir", systemImage: "trash")
                                    }
                                }
                                .font(Theme.body(13, weight: .semibold))
                                .foregroundStyle(Theme.danger)
                            }
                            .disabled(isDeleting)
                        }
                        .padding(.top, 2)
                        .animation(.easeInOut(duration: 0.15), value: isDeleting)
                    } else {
                        Text("Gerada pelo pagamento online — não pode ser editada.")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
                .padding(.bottom, 12)
            }
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(Theme.body(13))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(Theme.body(13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
    }
}
