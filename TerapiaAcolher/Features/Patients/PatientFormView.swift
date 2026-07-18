import SwiftUI

// MARK: - ViewModel do wizard

@Observable
final class PatientFormViewModel {
    enum Mode {
        case create
        case edit(PatientDetail)

        var isEdit: Bool { if case .edit = self { true } else { false } }
    }

    struct Step: Identifiable {
        let id: Int
        let title: String
    }

    let mode: Mode
    var stepIndex = 0
    var groups: [PatientGroup] = []
    var isLoadingGroups = true
    var groupsError: String? = nil

    // Campos
    var groupId: String? = nil
    var name = ""
    var whatsapp = ""
    var email = ""
    var cpf = ""
    var hasBirthDate = false
    var birthDate = Calendar.current.date(byAdding: .year, value: -25, to: .now) ?? .now
    var hasGuardian = false
    var guardianName = ""
    var guardianContact = ""
    var guardianIsPayer = false
    var sessionPriceText = ""
    var billingDay = 5
    var monthlyBillingReminder = false
    var sessionReminder24h = true
    var videoReminder1h = true
    var registrationActive = true

    var isSaving = false
    var errorMessage: String? = nil

    let steps: [Step] = [
        Step(id: 0, title: "Grupo"),
        Step(id: 1, title: "Dados do paciente"),
        Step(id: 2, title: "Responsável"),
        Step(id: 3, title: "Financeiro"),
        Step(id: 4, title: "Automações"),
    ]

    init(mode: Mode) {
        self.mode = mode
        if case let .edit(detail) = mode {
            groupId = detail.group?.id
            name = detail.name
            whatsapp = detail.whatsapp.map(PatientMask.whatsapp) ?? ""
            email = detail.email ?? ""
            cpf = "" // nunca pré-preenche CPF; só reenvia se digitado de novo
            if let birth = detail.birthDate {
                hasBirthDate = true
                // Dia-calendário UTC → mesmo dia no fuso local (round-trip
                // sem edição preserva o dia exato).
                birthDate = PatientFormat.localDate(fromUTCCalendarDay: birth)
            }
            if detail.guardianName != nil || detail.guardianContact != nil {
                hasGuardian = true
                guardianName = detail.guardianName ?? ""
                guardianContact = detail.guardianContact ?? ""
            }
            guardianIsPayer = detail.guardianIsPayer
            if let price = detail.sessionPrice {
                sessionPriceText = String(format: "%.2f", price).replacingOccurrences(of: ".", with: ",")
            }
            billingDay = detail.billingDay ?? 5
            monthlyBillingReminder = detail.monthlyBillingReminder
            sessionReminder24h = detail.sessionReminder24h
            videoReminder1h = detail.videoReminder1h
            registrationActive = detail.registrationActive
        }
    }

    /// Grupo selecionado sugere responsável (Crianças/Adolescentes).
    var selectedGroup: PatientGroup? {
        groups.first { $0.id == groupId }
    }

    var suggestsGuardian: Bool {
        let name = selectedGroup?.name.folding(options: .diacriticInsensitive, locale: Locale(identifier: "pt_BR")).lowercased() ?? ""
        return name.contains("crianca") || name.contains("adolescente")
    }

    var sessionPrice: Double? {
        let normalized = sessionPriceText
            .replacingOccurrences(of: "R$", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        return Double(normalized)
    }

    var canGoNext: Bool {
        switch stepIndex {
        case 1: return name.trimmingCharacters(in: .whitespaces).count >= 2
        default: return true
        }
    }

    var canSave: Bool {
        name.trimmingCharacters(in: .whitespaces).count >= 2 && !isSaving
    }

    @MainActor
    func loadGroups() async {
        isLoadingGroups = true
        groupsError = nil
        do {
            groups = try await PatientsAPI.groups()
            if groupId == nil, case .create = mode {
                groupId = groups.first?.id
            }
        } catch let error as APIError {
            groupsError = error.message
        } catch {
            groupsError = "Não foi possível carregar os grupos."
        }
        isLoadingGroups = false
    }

    @MainActor
    func save() async -> PatientDetail? {
        errorMessage = nil

        let cpfDigits = cpf.filter(\.isNumber)
        if !cpfDigits.isEmpty && cpfDigits.count != 11 {
            errorMessage = "CPF incompleto — confira os 11 dígitos."
            return nil
        }
        if !sessionPriceText.isEmpty && sessionPrice == nil {
            errorMessage = "Valor por sessão inválido."
            return nil
        }

        var payload = PatientPayload(name: name.trimmingCharacters(in: .whitespaces))
        // Em edição, campos limpos precisam sair como null explícito no PATCH
        // (chave ausente é ignorada pelo backend e o campo nunca seria limpo).
        payload.emitsExplicitNulls = mode.isEdit
        payload.groupId = groupId
        payload.cpf = cpfDigits.isEmpty ? nil : cpfDigits
        payload.email = email.isEmpty ? nil : email.trimmingCharacters(in: .whitespaces)
        payload.whatsapp = PatientMask.whatsappPayload(whatsapp)
        payload.birthDate = hasBirthDate ? birthDate : nil
        if hasGuardian {
            payload.guardianName = guardianName.isEmpty ? nil : guardianName
            payload.guardianContact = guardianContact.isEmpty ? nil : guardianContact
            payload.guardianIsPayer = guardianIsPayer
        } else {
            payload.guardianIsPayer = false
        }
        payload.sessionPrice = sessionPrice
        payload.billingDay = billingDay
        payload.monthlyBillingReminder = monthlyBillingReminder
        payload.sessionReminder24h = sessionReminder24h
        payload.videoReminder1h = videoReminder1h
        payload.registrationActive = registrationActive

        isSaving = true
        defer { isSaving = false }
        do {
            switch mode {
            case .create:
                return try await PatientsAPI.create(payload)
            case let .edit(detail):
                payload.status = registrationActive ? "ACTIVE" : "INACTIVE"
                return try await PatientsAPI.update(id: detail.id, payload)
            }
        } catch let error as APIError {
            errorMessage = error.message
        } catch {
            errorMessage = "Não foi possível salvar o paciente."
        }
        return nil
    }
}

// MARK: - Tela: wizard de cadastro/edição

struct PatientFormView: View {
    @State private var model: PatientFormViewModel
    @Environment(\.dismiss) private var dismiss

    let onSaved: (PatientDetail) -> Void

    init(mode: PatientFormViewModel.Mode, onSaved: @escaping (PatientDetail) -> Void) {
        _model = State(initialValue: PatientFormViewModel(mode: mode))
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    progressHeader
                    ScrollView {
                        VStack(spacing: 16) {
                            stepContent
                            if let error = model.errorMessage {
                                Text(error)
                                    .font(Theme.body(13, weight: .medium))
                                    .foregroundStyle(Theme.danger)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.horizontal, Theme.screenPadding)
                        .padding(.top, 16)
                        .padding(.bottom, 24)
                    }
                    footerButtons
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if model.stepIndex > 0 {
                            withAnimation { model.stepIndex -= 1 }
                        } else {
                            dismiss()
                        }
                    } label: {
                        Image(systemName: model.stepIndex > 0 ? "arrow.left" : "xmark")
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text(model.mode.isEdit ? "Editar paciente" : "Novo paciente")
                        .font(Theme.serifTitle(19))
                        .foregroundStyle(Theme.textPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Salvar") { save() }
                        .font(Theme.body(16, weight: .semibold))
                        .foregroundStyle(model.canSave ? Theme.primary : Theme.textSecondary)
                        .disabled(!model.canSave)
                }
            }
            .task { await model.loadGroups() }
            .interactiveDismissDisabled(model.isSaving)
        }
    }

    private func save() {
        Task {
            if let saved = await model.save() {
                onSaved(saved)
                dismiss()
            }
        }
    }

    // MARK: Progresso (dots como no print)

    private var progressHeader: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(model.steps) { step in
                    Circle()
                        .fill(step.id <= model.stepIndex ? Theme.primary : Theme.border)
                        .frame(width: 8, height: 8)
                }
            }
            Spacer()
            Text("\(model.stepIndex + 1) de \(model.steps.count) · \(model.steps[model.stepIndex].title)")
                .font(Theme.body(12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.vertical, 12)
    }

    // MARK: Conteúdo por etapa

    @ViewBuilder
    private var stepContent: some View {
        switch model.stepIndex {
        case 0: groupStep
        case 1: dataStep
        case 2: guardianStep
        case 3: financeStep
        default: automationsStep
        }
    }

    private var groupStep: some View {
        PatientFormSection(icon: "person.2", title: "GRUPO") {
            if model.isLoadingGroups {
                ProgressView().tint(Theme.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else if let error = model.groupsError {
                ErrorRetryView(message: error) { Task { await model.loadGroups() } }
                    .padding(.vertical, 8)
            } else if model.groups.isEmpty {
                Text("Nenhum grupo cadastrado. Crie grupos em Configurações.")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(model.groups) { group in
                        Button {
                            model.groupId = model.groupId == group.id ? nil : group.id
                        } label: {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Theme.groupColor(group.color))
                                    .frame(width: 14, height: 14)
                                Text(group.name)
                                    .font(Theme.body(15, weight: .medium))
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Image(systemName: model.groupId == group.id ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(model.groupId == group.id ? Theme.primary : Theme.border)
                            }
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        if group.id != model.groups.last?.id {
                            Divider().overlay(Theme.border)
                        }
                    }
                }
            }
        }
    }

    private var dataStep: some View {
        VStack(spacing: 16) {
            PatientFormSection(icon: "exclamationmark.circle", title: "INFORMAÇÕES") {
                PatientFieldRow(label: "Nome") {
                    TextField("Nome completo", text: $model.name)
                        .multilineTextAlignment(.trailing)
                }
                Divider().overlay(Theme.border)
                PatientFieldRow(label: "WhatsApp") {
                    TextField("+55 (11) 91234-5678", text: $model.whatsapp)
                        .keyboardType(.phonePad)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: model.whatsapp) { _, newValue in
                            let masked = PatientMask.whatsapp(newValue)
                            if masked != newValue { model.whatsapp = masked }
                        }
                }
                Divider().overlay(Theme.border)
                PatientFieldRow(label: "E-mail") {
                    TextField("email@exemplo.com", text: $model.email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                }
                Divider().overlay(Theme.border)
                PatientFieldRow(label: "CPF") {
                    TextField(cpfPlaceholder, text: $model.cpf)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: model.cpf) { _, newValue in
                            let masked = PatientMask.cpf(newValue)
                            if masked != newValue { model.cpf = masked }
                        }
                }
            }

            PatientFormSection(icon: "calendar", title: "NASCIMENTO") {
                Toggle(isOn: $model.hasBirthDate.animation()) {
                    Text("Informar data de nascimento")
                        .font(Theme.body(15))
                        .foregroundStyle(Theme.textPrimary)
                }
                .tint(Theme.primary)
                if model.hasBirthDate {
                    DatePicker(
                        "Data",
                        selection: $model.birthDate,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                    .font(Theme.body(15))
                    .environment(\.locale, Locale(identifier: "pt_BR"))
                    .tint(Theme.primary)
                }
            }
        }
    }

    private var cpfPlaceholder: String {
        if case let .edit(detail) = model.mode, let masked = detail.cpfMasked {
            return masked
        }
        return "000.000.000-00"
    }

    private var guardianStep: some View {
        PatientFormSection(icon: "figure.and.child.holdinghands", title: "RESPONSÁVEL") {
            if model.suggestsGuardian {
                Text("Grupo \(model.selectedGroup?.name ?? "") costuma exigir responsável financeiro.")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textSecondary)
            }
            Toggle(isOn: $model.hasGuardian.animation()) {
                Text("Possui responsável")
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.textPrimary)
            }
            .tint(Theme.primary)

            if model.hasGuardian {
                Divider().overlay(Theme.border)
                PatientFieldRow(label: "Nome") {
                    TextField("Nome do responsável", text: $model.guardianName)
                        .multilineTextAlignment(.trailing)
                }
                Divider().overlay(Theme.border)
                PatientFieldRow(label: "Contato") {
                    TextField("Telefone ou e-mail", text: $model.guardianContact)
                        .multilineTextAlignment(.trailing)
                }
                Divider().overlay(Theme.border)
                Toggle(isOn: $model.guardianIsPayer) {
                    Text("Responsável é o pagador")
                        .font(Theme.body(15))
                        .foregroundStyle(Theme.textPrimary)
                }
                .tint(Theme.primary)
            }
        }
        .onAppear {
            if model.suggestsGuardian && !model.mode.isEdit {
                model.hasGuardian = true
            }
        }
    }

    private var financeStep: some View {
        PatientFormSection(icon: "dollarsign", title: "FINANCEIRO") {
            PatientFieldRow(label: "Valor por sessão") {
                HStack(spacing: 4) {
                    Spacer()
                    Text("R$")
                        .font(Theme.body(15))
                        .foregroundStyle(Theme.textSecondary)
                    TextField("180,00", text: $model.sessionPriceText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .fixedSize()
                }
            }
            Divider().overlay(Theme.border)
            HStack {
                Text("Dia de cobrança")
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Picker("Dia de cobrança", selection: $model.billingDay) {
                    ForEach(1 ... 28, id: \.self) { day in
                        Text("Dia \(day)").tag(day)
                    }
                }
                .pickerStyle(.menu)
                .tint(Theme.textPrimary)
            }
            Divider().overlay(Theme.border)
            Toggle(isOn: $model.monthlyBillingReminder) {
                Text("Lembrete mensal de cobrança")
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.textPrimary)
            }
            .tint(Theme.primary)
        }
    }

    private var automationsStep: some View {
        PatientFormSection(icon: "bell", title: "AUTOMAÇÕES") {
            Toggle(isOn: $model.sessionReminder24h) {
                Text("Lembrete de sessão · 24h antes")
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.textPrimary)
            }
            .tint(Theme.primary)
            Divider().overlay(Theme.border)
            Toggle(isOn: $model.videoReminder1h) {
                Text("Lembrete de videochamada · 1h antes")
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.textPrimary)
            }
            .tint(Theme.primary)
            Divider().overlay(Theme.border)
            Toggle(isOn: $model.registrationActive) {
                Text("Cadastro ativo")
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.textPrimary)
            }
            .tint(Theme.primary)
        }
    }

    // MARK: Rodapé

    private var footerButtons: some View {
        VStack(spacing: 0) {
            Divider().overlay(Theme.border)
            if model.stepIndex < model.steps.count - 1 {
                PrimaryButton(title: "Continuar", isEnabled: model.canGoNext) {
                    withAnimation { model.stepIndex += 1 }
                }
                .padding(Theme.screenPadding)
            } else {
                PrimaryButton(
                    title: model.mode.isEdit ? "Salvar alterações" : "Cadastrar paciente",
                    isLoading: model.isSaving,
                    isEnabled: model.canSave
                ) { save() }
                    .padding(Theme.screenPadding)
            }
        }
        .background(Theme.background)
    }
}

// MARK: - Blocos de formulário (estilo dos cards do print)

struct PatientFormSection<Content: View>: View {
    let icon: String
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(Theme.body(12, weight: .semibold))
                    .tracking(1.2)
            }
            .foregroundStyle(Theme.textSecondary)
            .padding(.bottom, 6)
            content()
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .stroke(Theme.border, lineWidth: 1)
        )
    }
}

struct PatientFieldRow<Field: View>: View {
    let label: String
    @ViewBuilder var field: () -> Field

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(Theme.body(15))
                .foregroundStyle(Theme.textPrimary)
            field()
                .font(Theme.body(15))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.vertical, 8)
    }
}
