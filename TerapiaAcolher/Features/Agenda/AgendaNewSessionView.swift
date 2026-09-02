import SwiftUI
import Observation

// MARK: - ViewModel da nova sessão

@Observable
final class AgendaNewSessionModel {
    var patient: AgendaPatientRef?
    /// E-mail conhecido do paciente (lista/detalhe) — define se o campo obrigatório aparece.
    var patientEmail: String?
    var patientWhatsapp: String?

    var date = Date.now
    var startTime: Date
    var endTime: Date
    var recurrence: AgendaRecurrence = .none
    var priceText = ""
    var isOnline = false
    var generateMeet = false
    var manualLink = ""
    var sendEmail = false
    var patientEmailInput = ""
    var observations = ""

    var isSaving = false
    var alertTitle: String?
    var alertMessage: String?

    private let calendar = AgendaFormat.calendar

    init() {
        // Próxima hora cheia, duração padrão de 50 min
        let now = Date.now
        var components = AgendaFormat.calendar.dateComponents([.year, .month, .day, .hour], from: now)
        components.hour = (components.hour ?? 8) + 1
        components.minute = 0
        let start = AgendaFormat.calendar.date(from: components) ?? now
        startTime = start
        endTime = start.addingTimeInterval(50 * 60)
    }

    /// Só cobra o e-mail quando não há NENHUM canal. Antes disto, paciente
    /// com WhatsApp e sem e-mail travava o agendamento por um campo que a
    /// mensagem nem ia usar.
    var needsEmailField: Bool {
        sendEmail
            && patient != nil
            && (patientEmail ?? "").isEmpty
            && (patientWhatsapp ?? "").isEmpty
    }

    var canSave: Bool {
        guard patient != nil, endTime > startTime else { return false }
        if needsEmailField, !patientEmailInput.contains("@") { return false }
        return true
    }

    /// Ao mudar o início, preserva a duração atual.
    func startChanged(oldValue: Date) {
        let duration = endTime.timeIntervalSince(oldValue)
        endTime = startTime.addingTimeInterval(max(duration, 5 * 60))
    }

    @MainActor
    func select(_ ref: AgendaPatientRef) {
        patient = ref
        patientEmail = ref.email
        // Zera antes de buscar: sobra do paciente anterior faria o formulário
        // achar que este tem WhatsApp e liberar o agendamento sem canal.
        patientWhatsapp = nil
        // Valor padrão da sessão vem do detalhe do paciente
        Task {
            if let detail: AgendaPatientDetail = try? await APIClient.shared.get("patients/\(ref.id)") {
                if let email = detail.email, !email.isEmpty { patientEmail = email }
                patientWhatsapp = detail.whatsapp
                if priceText.isEmpty, let price = detail.sessionPrice {
                    priceText = String(format: "%.2f", price).replacingOccurrences(of: ".", with: ",")
                }
            }
        }
    }

    private var priceValue: Double? {
        let normalized = priceText
            .replacingOccurrences(of: "R$", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        return Double(normalized)
    }

    private var startsAt: Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        let time = calendar.dateComponents([.hour, .minute], from: startTime)
        components.hour = time.hour
        components.minute = time.minute
        return calendar.date(from: components)
    }

    @MainActor
    func save() async -> Bool {
        struct Body: Encodable {
            let patientId: String
            let startsAt: Date
            let endsAt: Date
            let type: String
            let price: Double?
            let recurrence: String
            let observations: String?
            let generateMeetLink: Bool?
            let meetLink: String?
            let sendEmailToPatient: Bool?
            let patientEmail: String?
        }

        guard let patient, let startsAt else { return false }
        let duration = endTime.timeIntervalSince(startTime)
        let endsAt = startsAt.addingTimeInterval(duration)

        isSaving = true
        defer { isSaving = false }
        do {
            let trimmedLink = manualLink.trimmingCharacters(in: .whitespaces)
            let _: [AgendaSession] = try await APIClient.shared.post("sessions", body: Body(
                patientId: patient.id,
                startsAt: startsAt,
                endsAt: endsAt,
                type: isOnline ? "ONLINE" : "PRESENCIAL",
                price: priceValue,
                recurrence: recurrence.rawValue,
                observations: observations.isEmpty ? nil : observations,
                generateMeetLink: (isOnline && generateMeet) ? true : nil,
                meetLink: (isOnline && !generateMeet && !trimmedLink.isEmpty) ? trimmedLink : nil,
                sendEmailToPatient: sendEmail ? true : nil,
                patientEmail: needsEmailField ? patientEmailInput.trimmingCharacters(in: .whitespaces) : nil
            ))
            return true
        } catch let error as APIError where error.statusCode == 409 {
            alertTitle = "Conflito de horário"
            alertMessage = error.message
        } catch let error as APIError where error.statusCode == 400 && isOnline && generateMeet {
            alertTitle = "Google não conectado"
            alertMessage = "\(error.message)\n\nConecte sua conta Google em Configurações pra gerar links do Meet automaticamente — ou desligue a geração e informe o link manualmente."
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
        } catch let error as APIError {
            alertTitle = "Não deu certo"
            alertMessage = error.message
        } catch {
            alertTitle = "Não deu certo"
            alertMessage = "Não foi possível agendar. Verifique sua internet e tente de novo."
        }
        return false
    }
}

// MARK: - Sheet Nova sessão (fiel ao print)

struct AgendaNewSessionView: View {
    /// Paciente já escolhido por quem abriu a tela (ficha do paciente).
    /// Nil quando vem da Agenda, onde a escolha é o primeiro passo.
    var pacienteInicial: AgendaPatientRef? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var model = AgendaNewSessionModel()
    @State private var showPatientPicker = false

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 14) {
                    mainCard
                    typeCard
                    emailCard
                    observationsCard
                }
                .padding(Theme.screenPadding)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Theme.background)
        .sheet(isPresented: $showPatientPicker) {
            AgendaPatientPickerView { ref in
                model.select(ref)
            }
        }
        .alert(model.alertTitle ?? "", isPresented: .init(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil; model.alertTitle = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.alertMessage ?? "")
        }
        .onChange(of: model.startTime) { oldValue, _ in
            model.startChanged(oldValue: oldValue)
        }
        .task {
            // Só na primeira montagem: `select` busca o detalhe do paciente
            // (valor da sessão, e-mail, WhatsApp) e não pode repetir a cada
            // reavaliação da view.
            guard let pacienteInicial, model.patient == nil else { return }
            model.select(pacienteInicial)
        }
    }

    // MARK: Cabeçalho Cancelar · Nova sessão · Salvar

    private var header: some View {
        ZStack {
            Text("Nova sessão")
                .font(Theme.serifTitle(19))
                .foregroundStyle(Theme.textPrimary)
            HStack {
                Button("Cancelar") { dismiss() }
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Button {
                    Task {
                        if await model.save() { dismiss() }
                    }
                } label: {
                    if model.isSaving {
                        ProgressView().tint(Theme.primary)
                    } else {
                        Text("Salvar")
                            .font(Theme.body(16, weight: .bold))
                            .foregroundStyle(model.canSave ? Theme.primary : Theme.primary.opacity(0.4))
                    }
                }
                .disabled(!model.canSave || model.isSaving)
            }
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    // MARK: Paciente · Data · Hora · Recorrência · Valor

    private var mainCard: some View {
        ThemeCard(padding: 0) {
            VStack(spacing: 0) {
                // Paciente
                Button {
                    showPatientPicker = true
                } label: {
                    HStack(spacing: 10) {
                        Text("Paciente")
                            .font(Theme.body(15, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        if let patient = model.patient {
                            InitialAvatar(name: patient.name, colorHex: patient.group?.color, size: 24)
                            Text(patient.name)
                                .font(Theme.body(15, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                        } else {
                            Text("Escolher")
                                .font(Theme.body(15))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(14)
                }

                Divider().overlay(Theme.border)

                DatePicker("Data", selection: $model.date, displayedComponents: .date)
                    .font(Theme.body(15, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .environment(\.locale, AgendaFormat.locale)

                Divider().overlay(Theme.border)

                HStack {
                    Text("Hora")
                        .font(Theme.body(15, weight: .medium))
                    Spacer()
                    DatePicker("", selection: $model.startTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    DatePicker("", selection: $model.endTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

                Divider().overlay(Theme.border)

                HStack {
                    Text("Recorrência")
                        .font(Theme.body(15, weight: .medium))
                    Spacer()
                    Picker("Recorrência", selection: $model.recurrence) {
                        ForEach(AgendaRecurrence.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.textSecondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)

                Divider().overlay(Theme.border)

                HStack {
                    Text("Valor")
                        .font(Theme.body(15, weight: .medium))
                    Spacer()
                    Text("R$")
                        .font(Theme.money(15))
                        .foregroundStyle(Theme.textSecondary)
                    TextField("0,00", text: $model.priceText)
                        .keyboardType(.decimalPad)
                        .font(Theme.money(15, weight: .semibold))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }
                .padding(14)
            }
        }
    }

    // MARK: Tipo de atendimento + Meet

    private var typeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TIPO DE ATENDIMENTO")
                .font(Theme.body(11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Theme.textSecondary)

            HStack(spacing: 4) {
                typeOption("Presencial", icon: "building.2", selected: !model.isOnline) {
                    model.isOnline = false
                }
                typeOption("Online", icon: "video", selected: model.isOnline) {
                    model.isOnline = true
                }
            }
            .padding(4)
            .background(Color(hex: 0xF0EBE2))
            .clipShape(Capsule())

            if model.isOnline {
                meetSection
            }
        }
    }

    private func typeOption(_ title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                Text(title)
                    .font(Theme.body(14, weight: selected ? .semibold : .regular))
            }
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(selected ? Theme.surface : Color.clear, in: Capsule())
            .shadow(color: selected ? .black.opacity(0.07) : .clear, radius: 4, y: 2)
        }
    }

    private var meetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "video.fill")
                    .font(.system(size: 12, weight: .bold))
                Text("GOOGLE MEET")
                    .font(Theme.body(11, weight: .bold))
                    .tracking(1)
                Spacer()
            }
            .foregroundStyle(Color(hex: 0x3E637F))

            Toggle(isOn: $model.generateMeet) {
                Text("Gerar link do Meet")
                    .font(Theme.body(15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
            }
            .tint(Theme.primary)

            if !model.generateMeet {
                HStack(spacing: 8) {
                    TextField("meet.google.com/xyz-abcd-efg", text: $model.manualLink)
                        .font(Theme.money(13))
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    Button {
                        UIPasteboard.general.string = model.manualLink
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x3E637F))
                            .frame(width: 40, height: 40)
                            .background(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(model.manualLink.isEmpty)
                }
            } else {
                Text("O link será criado no seu Google Calendar e enviado junto do convite.")
                    .font(Theme.body(12))
                    .foregroundStyle(Color(hex: 0x3E637F).opacity(0.8))
            }
        }
        .padding(14)
        .background(Color(hex: 0xDDEAF3))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Confirmação para o paciente

    private var emailCard: some View {
        ThemeCard {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $model.sendEmail) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Avisar o paciente")
                            .font(Theme.body(15, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                        // O texto diz os dois canais porque é o que acontece:
                        // o backend manda por e-mail e por WhatsApp, conforme
                        // o que o paciente tiver cadastrado.
                        Text("Confirmação por e-mail e WhatsApp, com data, hora e o link da videochamada.")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .tint(Theme.primary)

                if model.needsEmailField {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("E-MAIL DO PACIENTE · OBRIGATÓRIO")
                            .font(Theme.body(10, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(Theme.warning)
                        TextField("paciente@email.com.br", text: $model.patientEmailInput)
                            .font(Theme.body(15))
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 11)
                            .background(Theme.background)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Theme.border, lineWidth: 1)
                            )
                        Text("Será salvo no cadastro do paciente.")
                            .font(Theme.body(11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
    }

    // MARK: Observações

    private var observationsCard: some View {
        ThemeCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("OBSERVAÇÕES · OPCIONAL")
                    .font(Theme.body(11, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.textSecondary)
                TextField("Ex.: trazer diário do sono", text: $model.observations, axis: .vertical)
                    .font(Theme.body(15))
                    .lineLimit(2 ... 5)
            }
        }
    }
}

// MARK: - Picker de paciente (busca no GET patients)

struct AgendaPatientPickerView: View {
    let onSelect: (AgendaPatientRef) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var patients: [AgendaPatientRef] = []
    @State private var search = ""
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var filtered: [AgendaPatientRef] {
        let active = patients.filter { $0.status != "INACTIVE" }
        guard !search.isEmpty else { return active }
        return active.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                if isLoading {
                    ProgressView().tint(Theme.primary)
                } else if let errorMessage {
                    VStack(spacing: 14) {
                        EmptyStateView(icon: "wifi.exclamationmark", title: "Ops", message: errorMessage)
                        Button("Tentar de novo") { Task { await load() } }
                            .font(Theme.body(15, weight: .semibold))
                    }
                } else if filtered.isEmpty {
                    EmptyStateView(
                        icon: "person.2",
                        title: search.isEmpty ? "Nenhum paciente" : "Nada encontrado",
                        message: search.isEmpty
                            ? "Cadastre um paciente primeiro pra agendar sessões."
                            : "Nenhum paciente com \"\(search)\"."
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(filtered) { patient in
                                Button {
                                    onSelect(patient)
                                    dismiss()
                                } label: {
                                    ThemeCard(padding: 12) {
                                        HStack(spacing: 12) {
                                            InitialAvatar(name: patient.name, colorHex: patient.group?.color, size: 40)
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(patient.name)
                                                    .font(Theme.body(15, weight: .semibold))
                                                    .foregroundStyle(Theme.textPrimary)
                                                if let group = patient.group {
                                                    GroupTag(name: group.name, colorHex: group.color)
                                                }
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(Theme.textSecondary)
                                        }
                                    }
                                }
                                .buttonStyle(.pressableSubtle)
                            }
                        }
                        .padding(Theme.screenPadding)
                    }
                }
            }
            .navigationTitle("Escolher paciente")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Buscar por nome...")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
        }
        .task { await load() }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            patients = try await APIClient.shared.get("patients")
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
        } catch let error as APIError {
            errorMessage = error.message
        } catch {
            errorMessage = "Não foi possível carregar os pacientes."
        }
    }
}
