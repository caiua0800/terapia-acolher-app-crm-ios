import SwiftUI

// MARK: - ViewModel do wizard

@Observable
final class PatientFormViewModel {
    enum Mode {
        case create
        case edit(PatientDetail)
        /// Vem de um lead: nome e WhatsApp já preenchidos, o resto o terapeuta
        /// completa. É a ponte entre o topo do funil e a ficha de verdade.
        case fromLead(name: String, whatsapp: String)

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

    // Ficha pela foto (só em cadastro novo)
    var intakeEnabled = false
    var isReadingIntake = false
    var intakeError: String? = nil
    var intakeLimitReached = false
    var intakeApplied = false
    /// Fotos já reduzidas, só em memória; vão para os Arquivos se ela quiser.
    var intakeImages: [Data] = []
    var keepIntakePhoto = false
    /// Campos que a IA pediu para conferir (chaves da API).
    var fieldsToCheck: Set<String> = []
    /// Grupo escolhido à mão: a leitura não troca.
    var groupPickedByUser = false

    let steps: [Step] = [
        Step(id: 0, title: "Grupo"),
        Step(id: 1, title: "Dados do paciente"),
        Step(id: 2, title: "Responsável"),
        Step(id: 3, title: "Financeiro"),
        Step(id: 4, title: "Automações"),
    ]

    init(mode: Mode) {
        self.mode = mode
        if case let .fromLead(leadName, leadWhatsapp) = mode {
            name = leadName
            whatsapp = leadWhatsapp.isEmpty ? "" : PatientMask.whatsapp(leadWhatsapp)
        }
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
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
        } catch let error as APIError {
            groupsError = error.message
        } catch {
            groupsError = "Não foi possível carregar os grupos."
        }
        isLoadingGroups = false
    }

    @MainActor
    func loadIntakeAvailability() async {
        guard !mode.isEdit else { return }
        intakeEnabled = await PatientIntakeAPI.isEnabled()
    }

    @MainActor
    func readIntake(_ fotos: [Data]) async {
        guard !isReadingIntake else { return }
        Haptics.tap()
        isReadingIntake = true
        intakeError = nil
        intakeLimitReached = false
        defer { isReadingIntake = false }
        do {
            let result = try await PatientIntakeAPI.read(fotos)
            intakeImages = fotos
            apply(result)
            Haptics.success()
            withAnimation { stepIndex = 1 }
        } catch is CancellationError {
        } catch let error as APIError {
            Haptics.warning()
            intakeError = error.message
            intakeLimitReached = error.code == "LIMITE_DO_PLANO"
        } catch {
            Haptics.warning()
            intakeError = "Não conseguimos ler a ficha agora. Tente de novo ou preencha à mão."
        }
    }

    /// Preenche só o que está vazio: o que a terapeuta já digitou fica.
    @MainActor
    func apply(_ result: PatientIntakeResult) {
        let c = result.campos
        func filled(_ v: String?) -> String? {
            guard let v = v?.trimmingCharacters(in: .whitespaces), !v.isEmpty else { return nil }
            return v
        }
        if name.trimmingCharacters(in: .whitespaces).isEmpty, let v = filled(c.nome) { name = v }
        if cpf.isEmpty, let v = filled(c.cpf) { cpf = PatientMask.cpf(v) }
        if email.isEmpty, let v = filled(c.email) { email = v.lowercased() }
        if whatsapp.isEmpty, let v = filled(c.whatsapp) { whatsapp = PatientMask.whatsapp(v) }
        if !hasBirthDate, let v = filled(c.dataNascimento), let date = Self.intakeDate(v) {
            hasBirthDate = true
            birthDate = date
        }
        let guardianName = filled(c.responsavelNome)
        let guardianContact = filled(c.responsavelContato)
        if guardianName != nil || guardianContact != nil {
            hasGuardian = true
            if self.guardianName.isEmpty, let guardianName { self.guardianName = guardianName }
            if self.guardianContact.isEmpty, let guardianContact {
                self.guardianContact = Self.intakeContact(guardianContact)
            }
        }
        if !groupPickedByUser, let id = result.grupoId, groups.contains(where: { $0.id == id }) {
            groupId = id
        }
        fieldsToCheck = Set(result.conferir)
        intakeApplied = true
    }

    /// "AAAA-MM-DD" (dia-calendário) → data local ao meio-dia (sem pular de dia por fuso).
    static func intakeDate(_ text: String) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    /// Contato do responsável: telefone só com dígitos vira "(11) 99812-3344"; e-mail fica como veio.
    static func intakeContact(_ raw: String) -> String {
        var d = raw.filter(\.isNumber)
        guard !raw.contains("@"), d.count >= 10, d.count <= 13 else { return raw }
        if d.count > 11, d.hasPrefix("55") { d = String(d.dropFirst(2)) }
        guard d.count == 10 || d.count == 11 else { return raw }
        let ddd = d.prefix(2), resto = d.dropFirst(2)
        let corte = resto.count - 4
        return "(\(ddd)) \(resto.prefix(corte))-\(resto.suffix(4))"
    }

    func needsCheck(_ key: String) -> Bool { fieldsToCheck.contains(key) }

    /// Fotos da ficha nos Arquivos do paciente, se ela pediu. Falha não
    /// desfaz o cadastro — o paciente já está salvo.
    @MainActor
    func uploadIntakePhotos(patientId: String) async {
        guard keepIntakePhoto, !intakeImages.isEmpty else { return }
        for (i, data) in intakeImages.enumerated() {
            _ = try? await PFilesAPI.upload(
                patientId: patientId,
                data: data,
                fileName: intakeImages.count > 1 ? "Ficha de cadastro (\(i + 1)).jpg" : "Ficha de cadastro.jpg",
                mimeType: "image/jpeg",
                category: .image
            )
        }
        intakeImages = []
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
            case .create, .fromLead:
                return try await PatientsAPI.create(payload)
            case let .edit(detail):
                payload.status = registrationActive ? "ACTIVE" : "INACTIVE"
                return try await PatientsAPI.update(id: detail.id, payload)
            }
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
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
            .task {
                await model.loadGroups()
                await model.loadIntakeAvailability()
            }
            .interactiveDismissDisabled(model.isSaving)
        }
    }

    private func save() {
        Task {
            if let saved = await model.save() {
                if !model.mode.isEdit {
                    await model.uploadIntakePhotos(patientId: saved.id)
                }
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
        VStack(spacing: 16) {
            if model.intakeEnabled && !model.mode.isEdit {
                PatientIntakeCard(model: model)
            }
            groupSection
        }
    }

    private var groupSection: some View {
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
                            model.groupPickedByUser = true
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
            if model.intakeApplied {
                IntakeReviewNotice()
            }
            PatientFormSection(icon: "exclamationmark.circle", title: "INFORMAÇÕES") {
                PatientFieldRow(label: "Nome", check: model.needsCheck("nome")) {
                    TextField("Nome completo", text: $model.name)
                        .multilineTextAlignment(.trailing)
                }
                Divider().overlay(Theme.border)
                PatientFieldRow(label: "WhatsApp", check: model.needsCheck("whatsapp")) {
                    TextField("+55 (11) 91234-5678", text: $model.whatsapp)
                        .keyboardType(.phonePad)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: model.whatsapp) { _, newValue in
                            let masked = PatientMask.whatsapp(newValue)
                            if masked != newValue { model.whatsapp = masked }
                        }
                }
                Divider().overlay(Theme.border)
                PatientFieldRow(label: "E-mail", check: model.needsCheck("email")) {
                    // Sanitiza no binding, não só no teclado: `.textInputAutocapitalization`
                    // não alcança texto colado nem teclado físico (iPad/Mac).
                    TextField("email@exemplo.com", text: Binding(
                        get: { model.email },
                        set: { model.email = $0.lowercased().filter { !$0.isWhitespace } }
                    ))
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
                }
                Divider().overlay(Theme.border)
                PatientFieldRow(label: "CPF", check: model.needsCheck("cpf")) {
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
                    if model.needsCheck("dataNascimento") {
                        IntakeCheckHint()
                    }
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
                PatientFieldRow(label: "Nome", check: model.needsCheck("responsavelNome")) {
                    TextField("Nome do responsável", text: $model.guardianName)
                        .multilineTextAlignment(.trailing)
                }
                Divider().overlay(Theme.border)
                PatientFieldRow(label: "Contato", check: model.needsCheck("responsavelContato")) {
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
                        .mascaraDinheiro($model.sessionPriceText)
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
    /// A IA marcou este campo para conferir (ficha pela foto).
    var check: Bool = false
    @ViewBuilder var field: () -> Field

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 12) {
                Text(label)
                    .font(Theme.body(15))
                    .foregroundStyle(check ? Theme.warning : Theme.textPrimary)
                field()
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.vertical, 8)
            if check {
                IntakeCheckHint()
            }
        }
        .padding(.horizontal, check ? 8 : 0)
        .background(check ? Theme.warningSoft.opacity(0.6) : .clear, in: RoundedRectangle(cornerRadius: 8))
    }
}
