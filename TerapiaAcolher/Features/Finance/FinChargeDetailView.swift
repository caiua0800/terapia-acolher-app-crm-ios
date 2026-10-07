import Observation
import SwiftUI

@Observable
@MainActor
final class FinChargeDetailModel {
    var charge: FinCharge
    /// Flag separada: com uma só, o spinner acenderia no botão errado.
    var isWorkingPix = false
    var alerta: String?
    var showAlerta = false
    var gatewayPix: GwCharge?
    /// Folha de cobrar no cartão (prévia + gerar link) e o link gerado, que
    /// só abre depois que a prévia fecha — duas folhas juntas se derrubam.
    var cobrandoNoCartao = false
    var cartaoGerado: GwCharge?
    // Lembrete (2026-10-06): agendar, alterar, cancelar e enviar agora.
    var isWorkingLembrete = false
    var isSendingNow = false
    var editandoLembrete = false
    var reminderResult: FinReminderResult?
    /// Por onde vai o "Enviar lembrete agora" (2026-10-06). Sem escolher, o
    /// servidor mandava WhatsApp e e-mail juntos — duas mensagens ao paciente.
    var canaisAgora: Set<String>

    init(charge: FinCharge) {
        self.charge = charge
        let whats = charge.patient?.whatsappEnabled != false
        canaisAgora = whats ? ["WHATSAPP"] : ["EMAIL"]
    }

    /// WhatsApp liberado para este paciente (sem a informação, quem decide é o servidor).
    var whatsappDisponivel: Bool { charge.patient?.whatsappEnabled != false }

    /// Lembrete agendado sai por um canal só: WhatsApp quando dá, senão e-mail.
    var canalDoAgendamento: String { whatsappDisponivel ? "WHATSAPP" : "EMAIL" }

    func alternarCanal(_ canal: String) {
        if canaisAgora.contains(canal) {
            guard canaisAgora.count > 1 else { return }
            canaisAgora.remove(canal)
        } else {
            canaisAgora.insert(canal)
        }
    }

    /// Link do caminho antigo (conta Asaas própria). Só cobrança criada antes
    /// do Acolher Financeiro tem isso; hoje só o gateway cobra.
    var linkAntigo: String? {
        guard charge.gatewayName != "ACOLHER",
              let url = charge.gatewayInvoiceUrl, !url.isEmpty else { return nil }
        return url
    }

    var emAberto: Bool { charge.status == .pending || charge.status == .overdue }

    func carregar() async {
        // Avulsa não tem paciente: busca na lista das avulsas.
        let lista = charge.patientId == nil
            ? try? await FinanceAPI.charges(patientId: nil, kind: "STANDALONE")
            : try? await FinanceAPI.charges(patientId: charge.patientId)
        if let atual = lista?.first(where: { $0.id == charge.id }) {
            charge = atual
        }
    }

    /// Lembrete agendado e ainda por vir.
    var lembreteAgendado: Date? {
        guard let quando = charge.reminderScheduledAt, quando > Date() else { return nil }
        return quando
    }

    func agendar(_ quando: Date?) async {
        isWorkingLembrete = true
        defer { isWorkingLembrete = false }
        do {
            _ = try await FinanceAPI.scheduleReminder(id: charge.id, at: quando, canais: [canalDoAgendamento])
            Haptics.success()
            await carregar()
        } catch is CancellationError {
        } catch let error as APIError {
            present(error.message)
        } catch {
            present("Não foi possível agendar o lembrete.")
        }
    }

    func enviarAgora() async {
        isSendingNow = true
        defer { isSendingNow = false }
        do {
            reminderResult = try await FinanceAPI.sendReminder(
                id: charge.id,
                canais: ["WHATSAPP", "EMAIL"].filter { canaisAgora.contains($0) }
            )
            Haptics.success()
            await carregar()
        } catch is CancellationError {
        } catch let error as APIError {
            present(error.message)
        } catch {
            present("Não foi possível enviar o lembrete.")
        }
    }

    /// Pix pelo Acolher Financeiro — caminho principal de quem tem conta aprovada.
    func pixDoGateway() async {
        isWorkingPix = true
        defer { isWorkingPix = false }
        do {
            gatewayPix = charge.gatewayName == "ACOLHER"
                ? try await FinGatewayAPI.charge(chargeId: charge.id)
                : try await FinGatewayAPI.createPix(chargeId: charge.id)
            Haptics.success()
            await carregar()
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
        } catch let error as APIError {
            present(error.message)
        } catch {
            present("Não foi possível gerar o Pix. Verifique sua conexão.")
        }
    }

    private func present(_ m: String) {
        alerta = m
        showAlerta = true
    }
}

/// Página da cobrança.
///
/// Esta tela não existia: tocar na linha da lista não fazia nada, e todas as
/// ações viviam escondidas atrás dos três pontinhos — inclusive o link de
/// pagamento, que é justamente o que o terapeuta abre a cobrança para pegar.
struct FinChargeDetailView: View {
    @State private var model: FinChargeDetailModel
    @State private var store = FinGatewayStore.shared
    var onChange: () -> Void

    init(charge: FinCharge, onChange: @escaping () -> Void) {
        _model = State(initialValue: FinChargeDetailModel(charge: charge))
        self.onChange = onChange
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    cabecalho
                    dados
                    if model.emAberto { acoes }
                    // Lembrete só para paciente: o número oficial não fala com
                    // quem não está cadastrado.
                    if model.emAberto, !model.charge.ehAvulsa { lembrete }

                    // O selo não pode depender de conta aprovada: a tela mostra
                    // valor e status de cobrança de qualquer jeito.
                    GwProviderFooter(provider: store.overview?.provider ?? .asaasPadrao)
                }
                .padding(Theme.screenPadding)
                .padding(.bottom, 32)
            }
        }
        .setToolbarTitle("Cobrança")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.carregar()
            await store.load(showSpinner: false)
        }
        .refreshable { await model.carregar() }
        .alert("Ops", isPresented: $model.showAlerta) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.alerta ?? "Algo deu errado.")
        }
        .sheet(isPresented: $model.cobrandoNoCartao, onDismiss: {
            if let criada = model.cartaoGerado {
                model.cartaoGerado = nil
                model.gatewayPix = criada
            }
        }) {
            FinCardChargeSheet(
                charge: model.charge,
                repassarPadrao: store.account?.cardFeesPassThrough ?? false
            ) { criada in
                model.cartaoGerado = criada
                Task { await model.carregar() }
                onChange()
            }
        }
        .sheet(isPresented: $model.editandoLembrete) {
            FinAgendarLembreteSheet(
                inicial: model.lembreteAgendado
                    ?? Calendar.current.date(
                        bySettingHour: 9, minute: 0, second: 0,
                        of: max(FinFormat.localDate(fromCalendarDay: model.charge.dueDate), Date())
                    ) ?? Date()
            ) { quando in
                Task { await model.agendar(quando) }
            }
        }
        .sheet(isPresented: .init(
            get: { model.reminderResult != nil },
            set: { if !$0 { model.reminderResult = nil } }
        )) {
            if let result = model.reminderResult {
                FinReminderSheet(result: result)
            }
        }
        .sheet(item: $model.gatewayPix) { pix in
            FinGatewayChargePixSheet(
                charge: pix,
                simulation: store.simulation,
                provider: store.overview?.provider
            ) {
                Task { await model.carregar() }
                onChange()
            }
        }
    }

    private var cabecalho: some View {
        VStack(spacing: 10) {
            Text(Formatters.brl(model.charge.amount))
                .font(Theme.moneyDisplay(34))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)

            HStack(spacing: 6) {
                StatusBadge(
                    label: rotuloStatus,
                    color: corStatus,
                    background: corStatus.opacity(0.14)
                )
                if model.charge.gatewayName == "ACOLHER",
                   model.charge.status != .paid, model.charge.status != .canceled {
                    StatusBadge(
                        label: model.charge.ehNoCartao ? "LINK DO CARTÃO GERADO" : "PIX GERADO",
                        color: Theme.primary,
                        background: Theme.primarySoft
                    )
                }
            }

            if let nome = model.charge.nomeDoPagador {
                Text(nome)
                    .font(Theme.body(15, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            if model.charge.ehAvulsa {
                StatusBadge(label: "AVULSA", color: Theme.textSecondary, background: Theme.border.opacity(0.5))
            }
        }
        .padding(.top, 6)
    }

    private var rotuloStatus: String {
        switch model.charge.status {
        case .paid: "PAGA"
        case .overdue: "ATRASADA"
        case .canceled: "CANCELADA"
        default: "PENDENTE"
        }
    }

    private var corStatus: Color {
        switch model.charge.status {
        case .paid: Theme.success
        case .overdue: Theme.danger
        case .canceled: Theme.textSecondary
        default: Theme.warning
        }
    }

    private var dados: some View {
        ThemeCard(padding: 0) {
            VStack(spacing: 0) {
                linha("Descrição", model.charge.description)
                if let payer = model.charge.payer {
                    if let doc = payer.documentMasked {
                        Divider().overlay(Theme.border)
                        linha("CPF/CNPJ", doc)
                    }
                    if let email = payer.email, !email.isEmpty {
                        Divider().overlay(Theme.border)
                        linha("E-mail", email)
                    }
                }
                Divider().overlay(Theme.border)
                linha("Vencimento", PatientFormat.fullDate.string(from: model.charge.dueDate))
                if let m = model.charge.paymentMethodLabel {
                    Divider().overlay(Theme.border)
                    linha("Forma", m)
                }
                if let taxa = model.charge.splitFeeApplied, taxa > 0 {
                    Divider().overlay(Theme.border)
                    linha("Taxas (plataforma + Pix)", "− \(Formatters.brl(taxa))")
                    Divider().overlay(Theme.border)
                    linha(
                        "Você recebe",
                        Formatters.brl(model.charge.amount - taxa),
                        destaque: true
                    )
                }
                if let pago = model.charge.paidAt {
                    Divider().overlay(Theme.border)
                    linha("Pago em", PatientFormat.fullDate.string(from: pago))
                }
            }
        }
    }

    private func linha(_ rotulo: String, _ valor: String, destaque: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(rotulo)
                .font(Theme.body(14))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 12)
            Text(valor)
                .font(Theme.body(15, weight: destaque ? .semibold : .medium))
                .foregroundStyle(destaque ? Theme.success : Theme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }

    @ViewBuilder
    private var acoes: some View {
        if store.isApproved {
            VStack(spacing: 8) {
                PrimaryButton(
                    title: model.charge.gatewayName == "ACOLHER"
                        ? (model.charge.ehNoCartao ? "Ver link do cartão" : "Ver Pix")
                        : "Cobrar por Pix (Acolher Financeiro)",
                    icon: model.charge.ehNoCartao && model.charge.gatewayName == "ACOLHER" ? "creditcard" : "qrcode",
                    isLoading: model.isWorkingPix
                ) {
                    Task { await model.pixDoGateway() }
                }
                .accessibilityIdentifier("gwCobrarPix")
                // Cartão só antes de existir cobrança online (Pix ou link):
                // dois meios abertos para a mesma cobrança confundiriam o paciente.
                if model.charge.gatewayName != "ACOLHER", store.overview?.fees.cartaoDisponivel == true {
                    SecondaryButton(title: "Cobrar no cartão de crédito", icon: "creditcard") {
                        model.cobrandoNoCartao = true
                    }
                    .accessibilityIdentifier("gwCobrarCartao")
                }
            }
        } else if store.overview != nil {
            // Só o Acolher Financeiro cobra. Sem conta aprovada, o caminho é
            // abrir a conta (não existe mais "recebida por fora").
            NavigationLink {
                FinGatewayHomeView()
            } label: {
                ThemeCard {
                    HStack(spacing: 12) {
                        Image(systemName: "building.columns")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.primary)
                            .frame(width: 34, height: 34)
                            .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Para cobrar por Pix, abra sua conta no Acolher Financeiro")
                                .font(Theme.body(14, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Leva poucas etapas, tudo dentro do app.")
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary.opacity(0.6))
                    }
                }
            }
            .buttonStyle(.pressableSubtle)
        }

        if let link = model.linkAntigo {
            // Cobrança criada antes do gateway: o link do Asaas próprio ainda
            // vale pro paciente, então dá pra copiar. Discreto de propósito.
            Button {
                UIPasteboard.general.string = link
                Haptics.tap()
            } label: {
                Label("Copiar link antigo", systemImage: "doc.on.doc")
                    .font(Theme.body(14, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
            }
            .buttonStyle(.pressable)
        }
    }

    // MARK: - Lembrete da cobrança

    private var lembrete: some View {
        ThemeCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: model.lembreteAgendado == nil ? "bell" : "clock.badge")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                        .frame(width: 32, height: 32)
                        .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lembrete da cobrança")
                            .font(Theme.body(15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(model.lembreteAgendado.map { quando in
                            let pelo = (model.charge.reminderChannels ?? [model.canalDoAgendamento]).contains("WHATSAPP")
                                ? "pelo WhatsApp" : "por e-mail"
                            return "Agendado para \(FinFormat.diaEHora.string(from: quando)) \(pelo)"
                        } ?? "Nenhum lembrete agendado")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 0)
                    if model.isWorkingLembrete {
                        ProgressView().controlSize(.small)
                    }
                }
                HStack(spacing: 8) {
                    SecondaryButton(
                        title: model.lembreteAgendado == nil ? "Agendar" : "Alterar",
                        icon: "calendar.badge.clock"
                    ) {
                        Haptics.tap()
                        model.editandoLembrete = true
                    }
                    if model.lembreteAgendado != nil {
                        Button {
                            Haptics.tap()
                            Task { await model.agendar(nil) }
                        } label: {
                            Text("Cancelar")
                                .font(Theme.body(14, weight: .semibold))
                                .foregroundStyle(Theme.danger)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.pressable)
                        .disabled(model.isWorkingLembrete)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("ENVIAR AGORA POR")
                        .font(Theme.body(10, weight: .semibold))
                        .tracking(1.1)
                        .foregroundStyle(Theme.textSecondary)
                    HStack(spacing: 8) {
                        if model.whatsappDisponivel {
                            FilterChip(label: "WhatsApp", isSelected: model.canaisAgora.contains("WHATSAPP")) {
                                Haptics.tap()
                                model.alternarCanal("WHATSAPP")
                            }
                        }
                        FilterChip(label: "E-mail", isSelected: model.canaisAgora.contains("EMAIL")) {
                            Haptics.tap()
                            model.alternarCanal("EMAIL")
                        }
                    }
                }
                PrimaryButton(
                    title: "Enviar lembrete agora",
                    icon: "paperplane",
                    isLoading: model.isSendingNow
                ) {
                    Haptics.tap()
                    Task { await model.enviarAgora() }
                }
            }
        }
    }
}

/// Escolher data e hora do lembrete (não aceita passado).
struct FinAgendarLembreteSheet: View {
    var inicial: Date
    var onSalvar: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var quando: Date

    init(inicial: Date, onSalvar: @escaping (Date) -> Void) {
        self.inicial = inicial
        self.onSalvar = onSalvar
        _quando = State(initialValue: max(inicial, Date().addingTimeInterval(60)))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 16) {
                    Text("O paciente recebe o lembrete com o link de pagamento no horário escolhido.")
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ThemeCard {
                        DatePicker(
                            "Quando",
                            selection: $quando,
                            in: Date()...Date().addingTimeInterval(90 * 86_400),
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .font(Theme.body(15, weight: .semibold))
                        .tint(Theme.primary)
                        .environment(\.locale, Locale(identifier: "pt_BR"))
                    }
                    PrimaryButton(title: "Agendar lembrete", icon: "checkmark", isEnabled: quando > Date()) {
                        Haptics.tap()
                        onSalvar(quando)
                        dismiss()
                    }
                    Spacer()
                }
                .padding(Theme.screenPadding)
            }
            .navigationTitle("Agendar lembrete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .presentationDetents([.medium])
    }

}
