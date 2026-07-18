import SwiftUI

/// Sheet de nova transação / edição de transação manual.
struct FinTransactionFormView: View {
    var existing: FinTransaction?
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var type: FinTransactionType = .income
    @State private var descriptionText = ""
    @State private var amountText = ""
    @State private var partialReceived = false
    @State private var receivedText = ""
    @State private var date = Date()
    @State private var category = ""
    @State private var isRecurring = false
    @State private var patient: FinPatientRef?
    @State private var showPatientPicker = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var isValid: Bool {
        guard !descriptionText.trimmingCharacters(in: .whitespaces).isEmpty,
              let amount = FinFormat.parseAmount(amountText), amount > 0
        else { return false }
        if type == .income, partialReceived {
            guard let received = FinFormat.parseAmount(receivedText), received > 0, received <= amount
            else { return false }
        }
        return true
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        typeSelector

                        fieldCard("Descrição") {
                            TextField("Ex.: Sessão avulsa, Aluguel da sala", text: $descriptionText)
                                .font(Theme.body(15))
                        }

                        fieldCard("Valor (R$)") {
                            TextField("0,00", text: $amountText)
                                .font(Theme.money(17))
                                .keyboardType(.decimalPad)
                        }

                        if type == .income {
                            ThemeCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    Toggle(isOn: $partialReceived) {
                                        Text("Recebi um valor parcial")
                                            .font(Theme.body(15, weight: .semibold))
                                            .foregroundStyle(Theme.textPrimary)
                                    }
                                    .tint(Theme.primary)
                                    if partialReceived {
                                        TextField("Valor recebido (R$)", text: $receivedText)
                                            .font(Theme.money(16))
                                            .keyboardType(.decimalPad)
                                    }
                                }
                            }
                        }

                        ThemeCard {
                            DatePicker("Data", selection: $date, displayedComponents: .date)
                                .font(Theme.body(15, weight: .semibold))
                                .tint(Theme.primary)
                                .environment(\.locale, Locale(identifier: "pt_BR"))
                        }

                        fieldCard("Categoria (opcional)") {
                            TextField("Ex.: Aluguel, Supervisão, Material", text: $category)
                                .font(Theme.body(15))
                        }

                        ThemeCard {
                            Toggle(isOn: $isRecurring) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Recorrente")
                                        .font(Theme.body(15, weight: .semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                    Text("Ex.: aluguel, assinatura mensal")
                                        .font(Theme.body(12))
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                            .tint(Theme.primary)
                        }

                        patientField

                        PrimaryButton(
                            title: existing == nil ? "Registrar" : "Salvar alterações",
                            isLoading: isSaving,
                            isEnabled: isValid
                        ) {
                            Task { await save() }
                        }
                        .padding(.top, 4)
                    }
                    .padding(Theme.screenPadding)
                }
            }
            .navigationTitle(existing == nil ? "Nova transação" : "Editar transação")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .sheet(isPresented: $showPatientPicker) {
                NavigationStack {
                    FinPatientPickerView { selected in
                        patient = selected
                        showPatientPicker = false
                    }
                    .navigationTitle("Paciente")
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
            .alert("Ops", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .onAppear(perform: fill)
        }
    }

    // MARK: Campos

    private var typeSelector: some View {
        HStack(spacing: 10) {
            typeOption(.income, label: "Entrada", icon: "arrow.down.circle.fill", color: Theme.success)
            typeOption(.expense, label: "Saída", icon: "arrow.up.circle.fill", color: Theme.danger)
        }
    }

    private func typeOption(_ option: FinTransactionType, label: String, icon: String, color: Color) -> some View {
        Button {
            type = option
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(label).font(Theme.body(15, weight: .semibold))
            }
            .foregroundStyle(type == option ? color : Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                type == option ? color.opacity(0.12) : Theme.surface,
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(type == option ? color.opacity(0.5) : Theme.border, lineWidth: 1)
            )
        }
    }

    private var patientField: some View {
        ThemeCard {
            Button {
                showPatientPicker = true
            } label: {
                HStack(spacing: 12) {
                    if let patient {
                        InitialAvatar(name: patient.name, size: 34)
                        Text(patient.name)
                            .font(Theme.body(15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                    } else {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 20))
                            .foregroundStyle(Theme.textSecondary)
                        Text("Vincular paciente (opcional)")
                            .font(Theme.body(15))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    if patient != nil {
                        Button {
                            patient = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Theme.textSecondary)
                        }
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
    }

    private func fieldCard(_ label: String, @ViewBuilder content: @escaping () -> some View) -> some View {
        ThemeCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(label.uppercased())
                    .font(Theme.body(11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.textSecondary)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Dados

    private func fill() {
        guard let existing else { return }
        type = existing.type
        descriptionText = existing.description
        amountText = String(format: "%.2f", existing.amount).replacingOccurrences(of: ".", with: ",")
        if let received = existing.receivedAmount, received != existing.amount {
            partialReceived = true
            receivedText = String(format: "%.2f", received).replacingOccurrences(of: ".", with: ",")
        }
        date = existing.date
        category = existing.category ?? ""
        isRecurring = existing.isRecurring
        patient = existing.patient
    }

    private func save() async {
        guard let amount = FinFormat.parseAmount(amountText) else { return }
        isSaving = true
        defer { isSaving = false }

        let received: Double? = (type == .income && partialReceived)
            ? FinFormat.parseAmount(receivedText)
            : nil

        let body = FinTransactionBody(
            type: type.rawValue,
            description: descriptionText.trimmingCharacters(in: .whitespaces),
            amount: amount,
            receivedAmount: received,
            date: FinFormat.isoDay.string(from: date),
            category: category.trimmingCharacters(in: .whitespaces).isEmpty ? nil : category.trimmingCharacters(in: .whitespaces),
            isRecurring: isRecurring,
            patientId: patient?.id
        )

        do {
            if let existing {
                _ = try await FinanceAPI.updateTransaction(id: existing.id, body)
            } else {
                _ = try await FinanceAPI.createTransaction(body)
            }
            onSaved()
            dismiss()
        } catch {
            errorMessage = (error as? APIError)?.message ?? "Não foi possível salvar a transação."
        }
    }
}
