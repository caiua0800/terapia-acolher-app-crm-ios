import SwiftUI

// MARK: - Saque por Pix

@MainActor
@Observable
final class FinGatewayWithdrawModel {
    var saques: [GwWithdrawal] = []
    var chaves: [GwPixKey] = []
    var isLoading = false
    var isRequesting = false
    var cancelandoId: String?
    var carregandoComprovanteId: String?
    var errorMessage: String?
    var sucesso: String?

    var valorTexto = ""
    var tipoChave: GwPixKeyType = .cpf
    var chave = ""
    var salvarChave = true
    var rotulo = ""

    var valor: Double { GwMask.amount(valorTexto) ?? 0 }

    func podePedir(saldo: Double, minimo: Double) -> Bool {
        valor >= minimo && valor <= saldo && !chave.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func carregar() async {
        if saques.isEmpty { isLoading = true }
        defer { isLoading = false }
        do {
            async let saquesTask = FinGatewayAPI.withdrawals(page: 1)
            async let chavesTask = FinGatewayAPI.pixKeys()
            let pagina = try await saquesTask
            saques = pagina.items
            chaves = try await chavesTask
            if chave.isEmpty, let primeira = chaves.first {
                usar(primeira)
            }
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
        } catch {
            errorMessage = (error as? APIError)?.message ?? "Não foi possível carregar os saques."
        }
    }

    func usar(_ chaveSalva: GwPixKey) {
        tipoChave = chaveSalva.keyType
        chave = chaveSalva.key
        salvarChave = false
        rotulo = chaveSalva.label ?? ""
    }

    func pedir() async {
        isRequesting = true
        defer { isRequesting = false }
        do {
            let body = GwWithdrawalBody(
                amount: valor,
                pixKeyType: tipoChave.rawValue,
                pixKey: chave.trimmingCharacters(in: .whitespaces),
                saveKey: salvarChave,
                label: rotulo.isEmpty ? nil : rotulo
            )
            let saque = try await FinGatewayAPI.requestWithdrawal(body)
            valorTexto = ""
            sucesso = "Saque de \(Formatters.brl(saque.amount)) pedido. Fica aguardando aprovação."
            Haptics.success()
            await FinGatewayStore.shared.load(showSpinner: false)
            await carregar()
        } catch is CancellationError {
        } catch {
            errorMessage = (error as? APIError)?.message ?? "Não foi possível pedir o saque."
            Haptics.warning()
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

    /// Máscara conforme o tipo escolhido.
    func aplicarMascara() {
        let mascarada: String = switch tipoChave {
        case .cpf: GwMask.cpf(chave)
        case .cnpj: GwMask.cnpj(chave)
        case .phone: GwMask.phone(chave)
        case .email, .evp: chave
        }
        if mascarada != chave { chave = mascarada }
    }
}

struct FinGatewayWithdrawView: View {
    @State private var model = FinGatewayWithdrawModel()
    @State private var store = FinGatewayStore.shared
    @State private var confirmando = false
    @State private var cancelando: GwWithdrawal?
    @State private var comprovante: GwReceipt?

    private var fees: GwFees? { store.overview?.fees }
    private var minimo: Double { fees?.minWithdrawal ?? 1 }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    saldoCard
                    formulario
                    historico
                    if let provider = store.overview?.provider {
                        GwProviderFooter(provider: provider)
                    }
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
            Button("Pedir saque") { Task { await model.pedir() } }
            Button("Voltar", role: .cancel) {}
        } message: {
            Text("\(Formatters.brl(model.valor)) para a chave \(model.tipoChave.label) \(model.chave).")
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
        .alert("Pronto", isPresented: .init(
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
                Text("Mínimo \(Formatters.brl(fees.minWithdrawal)) · limite de \(Formatters.brl(fees.dailyWithdrawalLimit)) por dia · sem tarifa de saque.")
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
        PatientFormSection(icon: "arrow.up.circle", title: "PEDIR SAQUE") {
            VStack(alignment: .leading, spacing: 14) {
                GwField(label: "Valor") {
                    TextField("0,00", text: $model.valorTexto)
                        .keyboardType(.decimalPad)
                        .font(Theme.money(20, weight: .bold))
                        .accessibilityIdentifier("gwValorSaque")
                }

                if !model.chaves.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("CHAVES SALVAS")
                            .font(Theme.body(10, weight: .semibold))
                            .tracking(1.1)
                            .foregroundStyle(Theme.textSecondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(model.chaves) { chaveSalva in
                                    FilterChip(
                                        label: chaveSalva.label ?? chaveSalva.display,
                                        isSelected: model.chave == chaveSalva.key
                                    ) {
                                        model.usar(chaveSalva)
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(GwPixKeyType.allCases, id: \.self) { tipo in
                            FilterChip(label: tipo.label, isSelected: model.tipoChave == tipo) {
                                model.tipoChave = tipo
                                model.chave = ""
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }

                GwField(label: "Chave Pix de destino") {
                    TextField(model.tipoChave.placeholder, text: $model.chave)
                        .keyboardType(teclado)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("gwChaveSaque")
                        .onChange(of: model.chave) { _, _ in model.aplicarMascara() }
                }

                Toggle(isOn: $model.salvarChave) {
                    Text("Salvar esta chave para os próximos saques")
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.textPrimary)
                }
                .tint(Theme.primary)

                Divider().overlay(Theme.border)

                GwValueRow(
                    label: "Valor pedido",
                    value: Formatters.brl(model.valor)
                )
                GwValueRow(
                    label: "Tarifa de saque",
                    value: Formatters.brl(fees?.withdrawalFee ?? 0)
                )
                GwValueRow(
                    label: "Você recebe",
                    value: Formatters.brl(max(0, model.valor - (fees?.withdrawalFee ?? 0))),
                    destaque: true,
                    valueColor: Theme.success
                )

                PrimaryButton(
                    title: "Pedir saque",
                    icon: "arrow.up.circle",
                    isLoading: model.isRequesting,
                    isEnabled: model.podePedir(saldo: store.balance, minimo: minimo)
                ) {
                    confirmando = true
                }
                .accessibilityIdentifier("gwPedirSaque")

                SeloAsaas(badgeUrl: store.overview?.provider.badgeUrl)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var teclado: UIKeyboardType {
        switch model.tipoChave {
        case .cpf, .cnpj, .phone: .numberPad
        case .email: .emailAddress
        case .evp: .asciiCapable
        }
    }

    // MARK: Histórico

    @ViewBuilder
    private var historico: some View {
        if model.isLoading, model.saques.isEmpty {
            SkeletonList(linhas: 3, avatarSize: 0)
        } else if model.saques.isEmpty {
            EmptyStateView(
                icon: "arrow.up.circle",
                title: "Nenhum saque ainda",
                message: "Os saques pedidos aparecem aqui com o status de cada um."
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
                        .padding(.horizontal, Theme.cardPadding)
                        .padding(.vertical, 12)
                        if saque.id != model.saques.last?.id {
                            Divider().overlay(Theme.border).padding(.leading, Theme.cardPadding)
                        }
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
                            Text("Saque enviado por Pix")
                                .font(Theme.body(14))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.top, 8)

                        ThemeCard {
                            VStack(spacing: 10) {
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

                        ShareLink(item: texto) {
                            Label("Compartilhar comprovante", systemImage: "square.and.arrow.up")
                                .font(Theme.body(15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Theme.primary, in: Capsule())
                        }

                        GwProviderFooter(provider: receipt.provider)
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
        }
        .presentationDetents([.large])
    }

    private var texto: String {
        var linhas = [
            "Comprovante de saque · Gateway Acolher",
            "Valor: \(Formatters.brl(receipt.withdrawal.netAmount))",
            "Titular: \(receipt.account.legalName ?? "—") (\(receipt.account.cpfCnpjMasked ?? "—"))",
            "Destino: \(receipt.withdrawal.pixKeyType.label) \(receipt.withdrawal.pixKeyMasked ?? "")",
            "Pedido em: \(GwFormat.dayTime.string(from: receipt.withdrawal.requestedAt))",
        ]
        if let processado = receipt.withdrawal.processedAt {
            linhas.append("Enviado em: \(GwFormat.dayTime.string(from: processado))")
        }
        if let codigo = receipt.withdrawal.receiptCode {
            linhas.append("Comprovante: \(codigo)")
        }
        if let e2e = receipt.withdrawal.endToEndId {
            linhas.append("ID da transação: \(e2e)")
        }
        linhas.append("Serviços financeiros prestados por \(receipt.provider.legalName).")
        return linhas.joined(separator: "\n")
    }
}
