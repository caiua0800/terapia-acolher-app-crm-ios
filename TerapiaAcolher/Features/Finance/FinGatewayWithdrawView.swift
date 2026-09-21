import SwiftUI

// MARK: - Saque por Pix
//
// v2 (2026-09-12): o destino é sempre uma chave salva e verificada — sem
// campo de chave livre. Com chave verificada não há fila de aprovação: na
// simulação o saque sai na hora (`DONE`) e o comprovante abre em seguida;
// com o Asaas real fica `PROCESSING` até o webhook.

@MainActor
@Observable
final class FinGatewayWithdrawModel {
    var saques: [GwWithdrawal] = []
    var chaves: [GwPixKey] = []
    var isLoading = false
    var isRequesting = false
    var cancelandoId: String?
    var carregandoComprovanteId: String?
    var baixandoPdfId: String?
    var errorMessage: String?
    var sucesso: String?

    var valorTexto = ""
    var chaveId: String?

    /// Filtro do histórico. `nil` = todos.
    var filtroStatus: GwWithdrawalStatus?
    var carregandoMais = false
    private var pagina = 1
    private var totalDeSaques = 0

    var temMaisSaques: Bool { saques.count < totalDeSaques }

    var valor: Double { GwMask.amount(valorTexto) ?? 0 }

    var chaveEscolhida: GwPixKey? {
        chaves.first { $0.id == chaveId } ?? chaves.first { $0.isDefault } ?? chaves.first
    }

    func podePedir(saldo: Double, minimo: Double) -> Bool {
        valor >= minimo && valor <= saldo && chaveEscolhida != nil
    }

    func carregar() async {
        if saques.isEmpty { isLoading = true }
        defer { isLoading = false }
        do {
            async let saquesTask = FinGatewayAPI.withdrawals(page: 1, status: filtroStatus)
            async let chavesTask = FinGatewayAPI.pixKeys()
            let primeira = try await saquesTask
            saques = primeira.items
            pagina = 1
            totalDeSaques = primeira.total
            chaves = try await chavesTask
            if chaveId == nil { chaveId = chaves.first { $0.isDefault }?.id ?? chaves.first?.id }
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
        } catch {
            errorMessage = (error as? APIError)?.message ?? "Não foi possível carregar os saques."
        }
    }

    /// Troca o filtro e recarrega só a lista — as chaves não mudam com isso.
    func filtrar(_ status: GwWithdrawalStatus?) async {
        guard filtroStatus != status else { return }
        filtroStatus = status
        isLoading = true
        defer { isLoading = false }
        do {
            let primeira = try await FinGatewayAPI.withdrawals(page: 1, status: status)
            saques = primeira.items
            pagina = 1
            totalDeSaques = primeira.total
        } catch is CancellationError {
        } catch {
            errorMessage = (error as? APIError)?.message ?? "Não foi possível filtrar os saques."
        }
    }

    /// Próxima página, anexada ao fim. Sem isto o histórico parava nos 30
    /// primeiros e não havia como chegar num saque antigo pelo app.
    func carregarMais() async {
        guard !carregandoMais, temMaisSaques else { return }
        carregandoMais = true
        defer { carregandoMais = false }
        do {
            let proxima = try await FinGatewayAPI.withdrawals(page: pagina + 1, status: filtroStatus)
            let conhecidos = Set(saques.map(\.id))
            saques.append(contentsOf: proxima.items.filter { !conhecidos.contains($0.id) })
            pagina += 1
            totalDeSaques = proxima.total
        } catch {
            // Falhar ao paginar não derruba o que já está na tela.
        }
    }

    /// Devolve o saque criado pra a tela abrir o comprovante na hora.
    func pedir() async -> GwWithdrawal? {
        guard let chave = chaveEscolhida else { return nil }
        isRequesting = true
        defer { isRequesting = false }
        do {
            let saque = try await FinGatewayAPI.requestWithdrawal(
                GwWithdrawalBody(amount: valor, pixKeyId: chave.id)
            )
            valorTexto = ""
            Haptics.success()
            await FinGatewayStore.shared.load(showSpinner: false)
            await carregar()
            if saque.status != .done {
                sucesso = saque.status == .failed
                    ? (saque.failReason ?? "O saque não foi enviado.")
                    : "Saque de \(Formatters.brl(saque.amount)) em processamento. Você recebe um aviso quando cair."
            }
            return saque
        } catch is CancellationError {
            return nil
        } catch {
            errorMessage = (error as? APIError)?.message ?? "Não foi possível pedir o saque."
            Haptics.warning()
            return nil
        }
    }

    func cancelar(_ saque: GwWithdrawal) async {
        cancelandoId = saque.id
        defer { cancelandoId = nil }
        do {
            _ = try await FinGatewayAPI.cancelWithdrawal(id: saque.id)
            await FinGatewayStore.shared.load(showSpinner: false)
            await carregar()
        } catch is CancellationError {
        } catch {
            errorMessage = (error as? APIError)?.message ?? "Não foi possível cancelar o saque."
        }
    }

    func comprovante(_ saque: GwWithdrawal) async -> GwReceipt? {
        carregandoComprovanteId = saque.id
        defer { carregandoComprovanteId = nil }
        do {
            return try await FinGatewayAPI.receipt(id: saque.id)
        } catch is CancellationError {
            return nil
        } catch {
            errorMessage = (error as? APIError)?.message ?? "Não foi possível abrir o comprovante."
            return nil
        }
    }
}

struct FinGatewayWithdrawView: View {
    @State private var model = FinGatewayWithdrawModel()
    @State private var store = FinGatewayStore.shared
    @State private var confirmando = false
    @State private var cancelando: GwWithdrawal?
    @State private var comprovante: GwReceipt?

    private var fees: GwFees? { store.overview?.fees }
    private var tarifa: Double { fees?.withdrawalFee ?? 0 }
    private var minimo: Double { fees?.minWithdrawal ?? 1 }

    /// Atalhos de valor: frações do saldo, arredondadas pra baixo em reais.
    private var atalhos: [(String, Double)] {
        let saldo = store.balance
        guard saldo >= minimo else { return [] }
        var lista: [(String, Double)] = []
        for (rotulo, fracao) in [("25%", 0.25), ("50%", 0.5), ("75%", 0.75), ("Tudo", 1.0)] {
            let valor = fracao == 1 ? saldo : (saldo * fracao).rounded(.down)
            if valor >= minimo { lista.append((rotulo, valor)) }
        }
        return lista
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    saldoCard
                    formulario
                    filtrosDoHistorico
                    historico
                    GwProviderFooter(provider: store.overview?.provider ?? .asaasPadrao)
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
            .refreshable { await model.carregar() }
        }
        .setToolbarTitle("Sacar")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.carregar() }
        .sheet(item: $comprovante) { recibo in
            FinGatewayReceiptSheet(receipt: recibo)
        }
        .alert("Confirmar saque?", isPresented: $confirmando) {
            Button("Sacar agora") {
                Task {
                    if let saque = await model.pedir(), saque.status == .done {
                        comprovante = await model.comprovante(saque)
                    }
                }
            }
            Button("Voltar", role: .cancel) {}
        } message: {
            if let chave = model.chaveEscolhida {
                Text(tarifa > 0
                     ? "\(Formatters.brl(model.valor)) para \(chave.title) (\(chave.keyType.label) \(chave.display)). Tarifa de \(Formatters.brl(tarifa)) — você recebe \(Formatters.brl(max(0, model.valor - tarifa)))."
                     : "\(Formatters.brl(model.valor)) para \(chave.title) (\(chave.keyType.label) \(chave.display)). Sem tarifa.")
            }
        }
        .alert("Cancelar saque?", isPresented: .init(
            get: { cancelando != nil },
            set: { if !$0 { cancelando = nil } }
        )) {
            Button("Cancelar saque", role: .destructive) {
                if let saque = cancelando {
                    Task { await model.cancelar(saque) }
                }
            }
            Button("Voltar", role: .cancel) {}
        } message: {
            Text("O valor volta para o seu saldo na hora.")
        }
        .alert("Saque", isPresented: .init(
            get: { model.sucesso != nil },
            set: { if !$0 { model.sucesso = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.sucesso ?? "")
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

    // MARK: Saldo

    private var saldoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DISPONÍVEL PARA SAQUE")
                .font(Theme.body(10, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.55))
            Text(Formatters.brl(store.balance))
                .font(Theme.moneyDisplay(30))
                .monospacedDigit()
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if let fees {
                Text("Mínimo \(Formatters.brl(fees.minWithdrawal)) · até \(Formatters.brl(fees.dailyWithdrawalLimit)) por dia · \(fees.withdrawalFee > 0 ? "tarifa de \(Formatters.brl(fees.withdrawalFee))" : "sem tarifa") · cai na hora.")
                    .font(Theme.body(11))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Theme.ink, in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: Formulário

    private var formulario: some View {
        PatientFormSection(icon: "arrow.up.circle", title: "SACAR") {
            VStack(alignment: .leading, spacing: 14) {
                GwField(label: "Valor") {
                    TextField("0,00", text: $model.valorTexto)
                        .keyboardType(.decimalPad)
                        .font(Theme.money(20, weight: .bold))
                        .accessibilityIdentifier("gwValorSaque")
                }

                if !atalhos.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(atalhos, id: \.0) { rotulo, valor in
                            FilterChip(label: rotulo, isSelected: model.valor == valor && model.valor > 0) {
                                model.valorTexto = GwFormat.amountText(valor)
                            }
                        }
                    }
                }

                destino

                Divider().overlay(Theme.border)

                GwValueRow(label: "Valor", value: Formatters.brl(model.valor))
                GwValueRow(label: "Tarifa de saque", value: Formatters.brl(fees?.withdrawalFee ?? 0))
                GwValueRow(
                    label: "Você recebe",
                    value: Formatters.brl(max(0, model.valor - (fees?.withdrawalFee ?? 0))),
                    destaque: true,
                    valueColor: Theme.success
                )

                PrimaryButton(
                    title: "Sacar",
                    icon: "arrow.up.circle",
                    isLoading: model.isRequesting,
                    isEnabled: model.podePedir(saldo: store.balance, minimo: minimo)
                ) {
                    confirmando = true
                }
                .accessibilityIdentifier("gwPedirSaque")
            }
        }
    }

    @ViewBuilder
    private var destino: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("PARA QUAL CHAVE")
                    .font(Theme.body(10, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                NavigationLink {
                    FinGatewayPixKeysView()
                } label: {
                    Text(model.chaves.isEmpty ? "Cadastrar" : "Gerenciar")
                        .font(Theme.body(12, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                }
                .buttonStyle(.pressable)
            }

            if model.isLoading, model.chaves.isEmpty {
                SkeletonList(linhas: 2, avatarSize: 30)
            } else if model.chaves.isEmpty {
                NavigationLink {
                    FinGatewayPixKeysView()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "key")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.primary)
                            .frame(width: 32, height: 32)
                            .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 9))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Cadastre uma chave Pix sua")
                                .font(Theme.body(14, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text("O saque só vai pra uma conta no seu CPF/CNPJ.")
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary.opacity(0.6))
                    }
                    .padding(12)
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
                }
                .buttonStyle(.pressableSubtle)
                .accessibilityIdentifier("gwCadastrarChave")
            } else {
                ForEach(model.chaves) { chave in
                    GwPixKeyOption(chave: chave, isSelected: model.chaveEscolhida?.id == chave.id) {
                        model.chaveId = chave.id
                    }
                }
            }
        }
    }

    // MARK: Histórico

    /// Chips de status. Ficam fora do `if` da lista vazia de propósito: com o
    /// filtro escondido quando não há resultado, não haveria como voltar.
    @ViewBuilder
    private var filtrosDoHistorico: some View {
        if !model.saques.isEmpty || model.filtroStatus != nil {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(label: "Todos", isSelected: model.filtroStatus == nil) {
                        Task { await model.filtrar(nil) }
                    }
                    ForEach(FinGatewayWithdrawView.statusFiltraveis, id: \.self) { status in
                        FilterChip(
                            label: status.chipLabel,
                            isSelected: model.filtroStatus == status
                        ) {
                            Task { await model.filtrar(status) }
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    static let statusFiltraveis: [GwWithdrawalStatus] = [.done, .processing, .pendingApproval, .failed, .canceled]

    @ViewBuilder
    private var historico: some View {
        if model.isLoading, model.saques.isEmpty {
            SkeletonList(linhas: 3, avatarSize: 0)
        } else if model.saques.isEmpty {
            EmptyStateView(
                icon: "arrow.up.circle",
                title: model.filtroStatus == nil ? "Nenhum saque ainda" : "Nenhum saque com esse status",
                message: model.filtroStatus == nil
                    ? "Os saques aparecem aqui com o comprovante de cada um."
                    : "Toque em \"Todos\" para ver o histórico completo."
            )
        } else {
            ThemeCard(padding: 0) {
                VStack(spacing: 0) {
                    Text("MEUS SAQUES")
                        .font(Theme.body(10, weight: .semibold))
                        .tracking(1.1)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Theme.cardPadding)
                        .padding(.top, 14)
                        .padding(.bottom, 8)
                    ForEach(model.saques) { saque in
                        VStack(alignment: .leading, spacing: 10) {
                            GwWithdrawalRow(saque: saque)
                            if let motivo = saque.failReason, !motivo.isEmpty {
                                Text(motivo)
                                    .font(Theme.body(12))
                                    .foregroundStyle(Theme.danger)
                            }
                            if saque.status.canCancel || saque.status == .done {
                                HStack(spacing: 10) {
                                    if saque.status.canCancel {
                                        SecondaryButton(
                                            title: "Cancelar",
                                            icon: "xmark",
                                            isLoading: model.cancelandoId == saque.id,
                                            isEnabled: model.cancelandoId == nil,
                                            tint: Theme.danger
                                        ) {
                                            cancelando = saque
                                        }
                                    }
                                    if saque.status == .done {
                                        SecondaryButton(
                                            title: "Comprovante",
                                            icon: "doc.text",
                                            isLoading: model.carregandoComprovanteId == saque.id,
                                            isEnabled: model.carregandoComprovanteId == nil,
                                            tint: Theme.primary
                                        ) {
                                            Task { comprovante = await model.comprovante(saque) }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, Theme.cardPadding)
                        .padding(.vertical, 12)
                        if saque.id != model.saques.last?.id {
                            Divider().overlay(Theme.border).padding(.leading, Theme.cardPadding)
                        }
                    }

                    if model.temMaisSaques {
                        Divider().overlay(Theme.border)
                        Button {
                            Haptics.tap()
                            Task { await model.carregarMais() }
                        } label: {
                            HStack(spacing: 8) {
                                if model.carregandoMais {
                                    ProgressView().controlSize(.small).tint(Theme.primary)
                                }
                                Text("Carregar mais")
                                    .font(Theme.body(14, weight: .semibold))
                                    .foregroundStyle(Theme.primary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.pressableSubtle)
                        .disabled(model.carregandoMais)
                    }
                }
                .padding(.bottom, 6)
            }
        }
    }
}

// MARK: - Comprovante do saque

struct FinGatewayReceiptSheet: View {
    let receipt: GwReceipt

    @Environment(\.dismiss) private var dismiss
    @State private var baixandoPdf = false
    @State private var arquivo: GwArquivoBaixado?
    @State private var erro: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 34))
                                .foregroundStyle(Theme.success)
                            Text(Formatters.brl(receipt.withdrawal.netAmount))
                                .font(Theme.moneyDisplay(30))
                                .monospacedDigit()
                                .foregroundStyle(Theme.textPrimary)
                            Text(receipt.withdrawal.origin == .auto ? "Saque automático enviado por Pix" : "Saque enviado por Pix")
                                .font(Theme.body(14))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.top, 8)

                        ThemeCard {
                            VStack(spacing: 10) {
                                if receipt.withdrawal.fee > 0 {
                                    GwValueRow(
                                        label: "Valor bruto",
                                        value: Formatters.brl(receipt.withdrawal.amount)
                                    )
                                    GwValueRow(
                                        label: "Tarifa de saque",
                                        value: "− \(Formatters.brl(receipt.withdrawal.fee))"
                                    )
                                    Divider().overlay(Theme.border)
                                }
                                GwValueRow(label: "Titular", value: receipt.account.legalName ?? "—")
                                GwValueRow(label: "Documento", value: receipt.account.cpfCnpjMasked ?? "—")
                                GwValueRow(
                                    label: "Chave de destino",
                                    value: "\(receipt.withdrawal.pixKeyType.label) \(receipt.withdrawal.pixKeyMasked ?? "")"
                                )
                                GwValueRow(
                                    label: "Pedido em",
                                    value: GwFormat.dayTime.string(from: receipt.withdrawal.requestedAt)
                                )
                                if let processado = receipt.withdrawal.processedAt {
                                    GwValueRow(
                                        label: "Enviado em",
                                        value: GwFormat.dayTime.string(from: processado)
                                    )
                                }
                                if let codigo = receipt.withdrawal.receiptCode {
                                    GwValueRow(label: "Comprovante", value: codigo)
                                }
                                if let e2e = receipt.withdrawal.endToEndId {
                                    GwValueRow(label: "ID da transação", value: e2e)
                                }
                            }
                        }

                        PrimaryButton(
                            title: "Compartilhar PDF",
                            icon: "square.and.arrow.up",
                            isLoading: baixandoPdf
                        ) {
                            Task { await baixarPdf() }
                        }
                        .accessibilityIdentifier("gwCompartilharComprovante")

                        GwProviderLegalFooter(provider: receipt.provider)
                    }
                    .padding(Theme.screenPadding)
                }
            }
            .navigationTitle("Comprovante")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fechar") { dismiss() }
                        .foregroundStyle(Theme.primary)
                }
            }
            .sheet(item: $arquivo) { baixado in
                GwShareSheet(url: baixado.url)
                    .presentationDetents([.medium, .large])
            }
            .alert("Ops", isPresented: .init(
                get: { erro != nil },
                set: { if !$0 { erro = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(erro ?? "")
            }
        }
        .presentationDetents([.large])
    }

    private func baixarPdf() async {
        baixandoPdf = true
        defer { baixandoPdf = false }
        do {
            let pdf = try await FinGatewayAPI.receiptPDF(
                id: receipt.withdrawal.id,
                receiptCode: receipt.withdrawal.receiptCode
            )
            arquivo = try GwArquivoBaixado(pdf)
            Haptics.success()
        } catch is CancellationError {
        } catch {
            erro = (error as? APIError)?.message ?? "Não foi possível gerar o PDF do comprovante."
        }
    }
}
