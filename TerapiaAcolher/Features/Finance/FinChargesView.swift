import SwiftUI

// MARK: - Entrada: escolher o paciente das cobranças

struct FinChargesEntryView: View {
    @State private var selectedPatient: FinPatientRef?

    var body: some View {
        FinPatientPickerView { patient in
            selectedPatient = patient
        }
        .navigationTitle("Cobranças")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedPatient) { patient in
            FinChargesView(patient: patient)
        }
    }
}

// MARK: - ViewModel

@MainActor
@Observable
final class FinChargesViewModel {
    enum Filter: CaseIterable, Hashable {
        case all, paid, pending, overdue

        var label: String {
            switch self {
            case .all: "Tudo"
            case .paid: "Pago"
            case .pending: "Pendente"
            case .overdue: "Atrasado"
            }
        }

        var status: FinChargeStatus? {
            switch self {
            case .all: nil
            case .paid: .paid
            case .pending: .pending
            case .overdue: .overdue
            }
        }
    }

    let patient: FinPatientRef
    var filter: Filter = .all
    var charges: [FinCharge] = []
    var summary: FinChargeSummary?
    var isLoading = false
    var errorMessage: String?

    // Resultados de ações
    var reminderResult: FinReminderResult?
    var checkoutResult: FinCheckoutResult?
    var walletMissingMessage: String?
    var isWorking = false
    var workingChargeId: String? // cobrança com ação em voo (spinner na linha)

    init(patient: FinPatientRef) {
        self.patient = patient
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let summaryTask = FinanceAPI.chargesSummary(patientId: patient.id)
            async let listTask = FinanceAPI.charges(patientId: patient.id, status: filter.status)
            summary = try await summaryTask
            charges = try await listTask
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
        } catch {
            errorMessage = (error as? APIError)?.message ?? "Não foi possível carregar as cobranças."
        }
    }

    func setFilter(_ newFilter: Filter) {
        filter = newFilter
        Task { await load() }
    }

    func pay(_ charge: FinCharge) async {
        await run(chargeId: charge.id) {
            _ = try await FinanceAPI.payCharge(id: charge.id)
        }
    }

    func cancel(_ charge: FinCharge) async {
        await run(chargeId: charge.id) {
            _ = try await FinanceAPI.cancelCharge(id: charge.id)
        }
    }

    func sendReminder(_ charge: FinCharge) async {
        isWorking = true
        workingChargeId = charge.id
        defer {
            isWorking = false
            workingChargeId = nil
        }
        do {
            reminderResult = try await FinanceAPI.sendReminder(id: charge.id)
            await load()
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
        } catch {
            errorMessage = (error as? APIError)?.message ?? "Não foi possível gerar o lembrete."
        }
    }

    func checkout(_ charge: FinCharge, billingType: String) async {
        isWorking = true
        workingChargeId = charge.id
        defer {
            isWorking = false
            workingChargeId = nil
        }
        do {
            checkoutResult = try await FinanceAPI.checkout(id: charge.id, billingType: billingType)
            await load()
        } catch let apiError as APIError {
            // 400 sem Wallet ID cadastrado → oferecer o cadastro da carteira.
            if apiError.statusCode == 400, apiError.message.localizedCaseInsensitiveContains("wallet") {
                walletMissingMessage = apiError.message
            } else {
                errorMessage = apiError.message
            }
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
        } catch {
            errorMessage = "Não foi possível gerar a cobrança online."
        }
    }

    /// Cobrança mais urgente pro botão largo "Enviar lembrete de cobrança".
    var reminderTarget: FinCharge? {
        let open = charges.filter { $0.status == .overdue || $0.status == .pending }
        return open.min { $0.dueDate < $1.dueDate }
    }

    private func run(chargeId: String? = nil, _ operation: () async throws -> Void) async {
        isWorking = true
        workingChargeId = chargeId
        defer {
            isWorking = false
            workingChargeId = nil
        }
        do {
            try await operation()
            await load()
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
        } catch {
            errorMessage = (error as? APIError)?.message ?? "Não foi possível concluir a ação."
        }
    }
}

// MARK: - Tela de cobranças do paciente (fiel ao print)

struct FinChargesView: View {
    @State private var model: FinChargesViewModel
    @State private var showChargeForm = false
    @State private var showWalletSheet = false
    @State private var cancelingCharge: FinCharge?
    @State private var webLink: FinWebLink?

    init(patient: FinPatientRef) {
        _model = State(initialValue: FinChargesViewModel(patient: patient))
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    header
                    summaryCard
                    chips

                    if model.isLoading, model.charges.isEmpty {
                        ProgressView().padding(.top, 30)
                    } else if model.charges.isEmpty {
                        EmptyStateView(
                            icon: "creditcard",
                            title: "Nenhuma cobrança",
                            message: "Crie uma cobrança para \(model.patient.name) tocando em +."
                        )
                    } else {
                        chargeList
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.bottom, 110)
            }
            .refreshable { await model.load() }

            reminderBottomButton
        }
        .navigationTitle("Cobranças")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showChargeForm = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(Theme.primary)
                }
            }
        }
        .task { await model.load() }
        .sheet(isPresented: $showChargeForm) {
            FinChargeFormView(patient: model.patient) {
                Task { await model.load() }
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
        .sheet(isPresented: .init(
            get: { model.checkoutResult != nil },
            set: { if !$0 { model.checkoutResult = nil } }
        )) {
            if let result = model.checkoutResult {
                FinCheckoutSheet(result: result)
            }
        }
        .sheet(isPresented: $showWalletSheet) {
            NavigationStack { FinWalletView() }
        }
        .sheet(item: $webLink) { link in
            FinSafariView(url: link.url).ignoresSafeArea()
        }
        .alert("Carteira não conectada", isPresented: .init(
            get: { model.walletMissingMessage != nil },
            set: { if !$0 { model.walletMissingMessage = nil } }
        )) {
            Button("Cadastrar Wallet ID") { showWalletSheet = true }
            Button("Agora não", role: .cancel) {}
        } message: {
            Text(model.walletMissingMessage ?? "")
        }
        .alert("Cancelar cobrança?", isPresented: .init(
            get: { cancelingCharge != nil },
            set: { if !$0 { cancelingCharge = nil } }
        )) {
            Button("Cancelar cobrança", role: .destructive) {
                if let charge = cancelingCharge {
                    Task { await model.cancel(charge) }
                }
            }
            Button("Voltar", role: .cancel) {}
        } message: {
            Text("Se houver link de pagamento, ele também será cancelado.")
        }
        .alert("Ops", isPresented: .init(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    // MARK: Header do paciente

    private var header: some View {
        HStack(spacing: 12) {
            InitialAvatar(name: model.patient.name, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.patient.name)
                    .font(Theme.body(16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                if let summary = model.summary {
                    Text("\(summary.total) cobrança\(summary.total == 1 ? "" : "s") no total")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
        }
        .padding(.top, 6)
    }

    // MARK: Card A RECEBER / EM ATRASO

    private var summaryCard: some View {
        ThemeCard {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("A RECEBER")
                            .font(Theme.body(10, weight: .semibold))
                            .tracking(1.2)
                            .foregroundStyle(Theme.textSecondary)
                        Text(Formatters.brl(model.summary?.toReceive ?? 0))
                            .font(Theme.money(26, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("EM ATRASO")
                            .font(Theme.body(10, weight: .semibold))
                            .tracking(1.2)
                            .foregroundStyle(Theme.textSecondary)
                        Text(Formatters.brl(model.summary?.overdue ?? 0))
                            .font(Theme.money(17, weight: .bold))
                            .foregroundStyle(Theme.danger)
                    }
                }
                if let summary = model.summary {
                    let open = summary.counts.pending + summary.counts.overdue
                    Text("\(open) cobrança\(open == 1 ? "" : "s") em aberto")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, 4)
                }
            }
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FinChargesViewModel.Filter.allCases, id: \.self) { filter in
                    FilterChip(label: filter.label, isSelected: model.filter == filter) {
                        model.setFilter(filter)
                    }
                }
            }
        }
    }

    // MARK: Lista

    private var chargeList: some View {
        VStack(spacing: 0) {
            ForEach(model.charges) { charge in
                chargeCell(charge)
                if charge.id != model.charges.last?.id {
                    Divider().overlay(Theme.border)
                }
            }
        }
    }

    private func chargeCell(_ charge: FinCharge) -> some View {
        HStack(spacing: 12) {
            statusIcon(charge.status)
            VStack(alignment: .leading, spacing: 5) {
                Text(charge.description)
                    .font(Theme.body(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    statusBadge(charge.status)
                    Text(dueLabel(charge))
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(Formatters.brl(charge.amount))
                .font(Theme.money(15, weight: .semibold))
                .foregroundStyle(amountColor(charge.status))
            chargeMenu(charge)
        }
        .padding(.vertical, 13)
    }

    private func statusIcon(_ status: FinChargeStatus) -> some View {
        let (icon, color, background): (String, Color, Color) = switch status {
        case .paid: ("checkmark", Theme.success, Theme.successSoft)
        case .pending: ("clock", Theme.warning, Theme.warningSoft)
        case .overdue: ("exclamationmark", Theme.danger, Theme.dangerSoft)
        case .canceled: ("xmark", Theme.textSecondary, Theme.border.opacity(0.5))
        }
        return Circle()
            .fill(background)
            .frame(width: 38, height: 38)
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(color)
            )
    }

    @ViewBuilder
    private func statusBadge(_ status: FinChargeStatus) -> some View {
        switch status {
        case .paid: StatusBadge.pago()
        case .pending: StatusBadge.pendente()
        case .overdue: StatusBadge.atrasado()
        case .canceled: StatusBadge(
            label: "CANCELADA",
            color: Theme.textSecondary,
            background: Theme.border.opacity(0.5)
        )
        }
    }

    private func amountColor(_ status: FinChargeStatus) -> Color {
        switch status {
        case .paid: Theme.success
        case .pending: Theme.warning
        case .overdue: Theme.danger
        case .canceled: Theme.textSecondary
        }
    }

    private func dueLabel(_ charge: FinCharge) -> String {
        let dueDay = FinFormat.dayMonthUTC.string(from: charge.dueDate)
        switch charge.status {
        case .overdue:
            let days = abs(FinFormat.daysUntilDue(charge.dueDate))
            return "Vencia \(dueDay) · \(days) dia\(days == 1 ? "" : "s")"
        case .pending:
            let days = FinFormat.daysUntilDue(charge.dueDate)
            if days == 0 { return "Vence hoje" }
            if days < 0 { return "Vencia \(dueDay)" }
            return "Vence \(dueDay) · em \(days) dia\(days == 1 ? "" : "s")"
        case .paid:
            var parts: [String] = []
            if let paidAt = charge.paidAt { parts.append(FinFormat.dayMonth.string(from: paidAt)) }
            if let method = charge.paymentMethodLabel { parts.append(method) }
            return parts.isEmpty ? "Paga" : parts.joined(separator: " · ")
        case .canceled:
            return "Vencia \(dueDay)"
        }
    }

    // MARK: Menu de ações por cobrança

    private func chargeMenu(_ charge: FinCharge) -> some View {
        Menu {
            if charge.status == .pending || charge.status == .overdue {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    Task { await model.pay(charge) }
                } label: {
                    Label("Marcar como paga", systemImage: "checkmark.circle")
                }
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    Task { await model.sendReminder(charge) }
                } label: {
                    Label("Enviar lembrete de cobrança", systemImage: "bell")
                }
                if let urlString = charge.gatewayInvoiceUrl, let url = URL(string: urlString) {
                    Button {
                        webLink = FinWebLink(url: url)
                    } label: {
                        Label("Abrir link de pagamento", systemImage: "safari")
                    }
                    Button {
                        UIPasteboard.general.string = urlString
                    } label: {
                        Label("Copiar link de pagamento", systemImage: "doc.on.doc")
                    }
                } else {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        Task { await model.checkout(charge, billingType: "PIX") }
                    } label: {
                        Label("Cobrar via Pix", systemImage: "qrcode")
                    }
                }
                Button(role: .destructive) {
                    cancelingCharge = charge
                } label: {
                    Label("Cancelar cobrança", systemImage: "xmark.circle")
                }
            } else if charge.status == .paid, let urlString = charge.gatewayInvoiceUrl,
                      let url = URL(string: urlString) {
                Button {
                    webLink = FinWebLink(url: url)
                } label: {
                    Label("Ver fatura", systemImage: "safari")
                }
            }
        } label: {
            Group {
                if model.workingChargeId == charge.id {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Theme.textSecondary)
                } else {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
        }
        .disabled(charge.status == .canceled || model.isWorking)
        .animation(.easeInOut(duration: 0.15), value: model.workingChargeId)
    }

    // MARK: Botão largo do rodapé (como no print)

    @ViewBuilder
    private var reminderBottomButton: some View {
        if let target = model.reminderTarget {
            VStack {
                Spacer()
                Button {
                    Haptics.tap()
                    Task { await model.sendReminder(target) }
                } label: {
                    HStack(spacing: 8) {
                        // Rótulo permanece: o spinner ocupa o lugar do ícone.
                        if model.isWorking {
                            ProgressView().controlSize(.small).tint(.white)
                        } else {
                            Image(systemName: "text.bubble")
                        }
                        Text("Enviar lembrete de cobrança")
                    }
                    .font(Theme.body(16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Theme.primary, in: Capsule())
                    .shadow(color: Theme.primary.opacity(0.35), radius: 10, y: 4)
                    .animation(.easeInOut(duration: 0.15), value: model.isWorking)
                }
                .buttonStyle(.pressable)
                .disabled(model.isWorking)
                .padding(.horizontal, Theme.screenPadding)
                .padding(.bottom, 16)
            }
        }
    }
}

// MARK: - Sheet do lembrete (texto pro WhatsApp + status do e-mail)

struct FinReminderSheet: View {
    let result: FinReminderResult

    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Mensagem pronta para enviar")
                            .font(Theme.serifTitle(20))
                            .foregroundStyle(Theme.textPrimary)

                        ThemeCard {
                            Text(result.messageText)
                                .font(Theme.body(14))
                                .foregroundStyle(Theme.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        PrimaryButton(
                            title: copied ? "Copiado!" : "Copiar mensagem",
                            icon: copied ? "checkmark" : "doc.on.doc"
                        ) {
                            UIPasteboard.general.string = result.messageText
                            withAnimation { copied = true }
                        }

                        HStack(spacing: 8) {
                            Image(systemName: result.emailSent ? "checkmark.circle.fill" : "info.circle")
                                .foregroundStyle(result.emailSent ? Theme.success : Theme.warning)
                            Text(result.emailSent
                                ? "E-mail de lembrete enviado ao paciente."
                                : "Paciente sem e-mail cadastrado — copie a mensagem e envie pelo WhatsApp.")
                                .font(Theme.body(13))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            result.emailSent ? Theme.successSoft : Theme.warningSoft,
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                    }
                    .padding(Theme.screenPadding)
                }
            }
            .navigationTitle("Lembrete de cobrança")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fechar") { dismiss() }
                        .foregroundStyle(Theme.primary)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Sheet do checkout (link de pagamento + Pix copia-e-cola)

struct FinCheckoutSheet: View {
    let result: FinCheckoutResult

    @Environment(\.dismiss) private var dismiss
    @State private var copiedLink = false
    @State private var copiedPix = false
    @State private var webLink: FinWebLink?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(Theme.success)
                            Text("Cobrança online gerada")
                                .font(Theme.serifTitle(20))
                                .foregroundStyle(Theme.textPrimary)
                        }

                        if let fee = result.splitFeeApplied {
                            ThemeCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    feeRow("Valor da cobrança", Formatters.brl(result.amount))
                                    feeRow("Taxa do sistema", "− \(Formatters.brl(fee))")
                                    Divider()
                                    HStack {
                                        Text("Você recebe")
                                            .font(Theme.body(14, weight: .semibold))
                                            .foregroundStyle(Theme.textPrimary)
                                        Spacer()
                                        Text(Formatters.brl(result.amount - fee))
                                            .font(Theme.money(15, weight: .bold))
                                            .foregroundStyle(Theme.success)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        if let urlString = result.invoiceUrl, let url = URL(string: urlString) {
                            ThemeCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("LINK DE PAGAMENTO")
                                        .font(Theme.body(10, weight: .semibold))
                                        .tracking(1.2)
                                        .foregroundStyle(Theme.textSecondary)
                                    Text(urlString)
                                        .font(Theme.body(13))
                                        .foregroundStyle(Theme.primary)
                                        .lineLimit(2)
                                    HStack(spacing: 10) {
                                        Button {
                                            webLink = FinWebLink(url: url)
                                        } label: {
                                            Label("Abrir", systemImage: "safari")
                                                .font(Theme.body(14, weight: .semibold))
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(Theme.primary)
                                        Button {
                                            UIPasteboard.general.string = urlString
                                            withAnimation { copiedLink = true }
                                        } label: {
                                            Label(copiedLink ? "Copiado!" : "Copiar", systemImage: copiedLink ? "checkmark" : "doc.on.doc")
                                                .font(Theme.body(14, weight: .semibold))
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(Theme.textPrimary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        if let pix = result.pixQrCode {
                            ThemeCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("PIX COPIA E COLA")
                                        .font(Theme.body(10, weight: .semibold))
                                        .tracking(1.2)
                                        .foregroundStyle(Theme.textSecondary)
                                    Text(pix)
                                        .font(Theme.money(12))
                                        .foregroundStyle(Theme.textPrimary)
                                        .lineLimit(3)
                                        .truncationMode(.middle)
                                    Button {
                                        UIPasteboard.general.string = pix
                                        withAnimation { copiedPix = true }
                                    } label: {
                                        Label(copiedPix ? "Copiado!" : "Copiar código Pix", systemImage: copiedPix ? "checkmark" : "qrcode")
                                            .font(Theme.body(14, weight: .semibold))
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(Theme.primary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        Text("Envie o link ou o código Pix pro paciente por onde preferir. Quando o pagamento cair, a cobrança é marcada como paga automaticamente.")
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(Theme.screenPadding)
                }
            }
            .navigationTitle("Cobrança online")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fechar") { dismiss() }
                        .foregroundStyle(Theme.primary)
                }
            }
            .sheet(item: $webLink) { link in
                FinSafariView(url: link.url).ignoresSafeArea()
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func feeRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(Theme.body(13))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(Theme.money(13))
                .foregroundStyle(Theme.textPrimary)
        }
    }
}
