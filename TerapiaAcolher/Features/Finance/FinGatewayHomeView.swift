import SwiftUI

// MARK: - Acolher Financeiro — porta de entrada da conta do terapeuta
//
// Uma tela só, dirigida pelo status da conta: apresentação → assistente →
// análise → conta ativa. O caminho antigo (conta Asaas própria + Wallet ID)
// mora em Configurações → Integrações, fora daqui.

struct FinGatewayHomeView: View {
    @State private var store = FinGatewayStore.shared
    @State private var showOnboarding = false
    @State private var isReopening = false
    @State private var isRetrying = false
    @State private var ultimosSaques: [GwWithdrawal] = []
    @State private var resumoCobrancas: FinChargeSummary?
    @State private var ultimasMovimentacoes: [GwLedgerEntry] = []
    @State private var chaves: [GwPixKey] = []

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    conteudo
                    // Mesmo com a carga falhando, a tela é financeira: o selo
                    // usa o provedor conhecido e não some.
                    GwProviderFooter(provider: store.overview?.provider ?? .asaasPadrao)
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
            .refreshable { await recarregar() }
        }
        .setToolbarTitle("Acolher Financeiro")
        .navigationBarTitleDisplayMode(.inline)
        .task { await recarregar() }
        .sheet(isPresented: $showOnboarding, onDismiss: {
            Task { await recarregar() }
        }) {
            if let overview = store.overview {
                FinGatewayOnboardingView(overview: overview)
            }
        }
        .alert("Ops", isPresented: .init(
            get: { store.errorMessage != nil && store.overview != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private func recarregar() async {
        await store.load()
        guard store.isApproved else {
            ultimosSaques = []
            resumoCobrancas = nil
            ultimasMovimentacoes = []
            chaves = []
            return
        }
        // Em paralelo: são quatro quadros independentes do mesmo painel, e em
        // série o painel montaria de cima para baixo com quatro esperas.
        async let saques = try? await FinGatewayAPI.withdrawals(page: 1, pageSize: 3)
        async let resumo = try? await FinanceAPI.chargesSummary(patientId: nil)
        async let extrato = try? await FinGatewayAPI.ledger(page: 1, pageSize: 6)
        async let pix = try? await FinGatewayAPI.pixKeys()
        ultimosSaques = (await saques)?.items ?? []
        resumoCobrancas = await resumo
        ultimasMovimentacoes = (await extrato)?.items ?? []
        chaves = (await pix) ?? []
    }

    // MARK: Conteúdo por estado

    @ViewBuilder
    private var conteudo: some View {
        if store.overview == nil {
            if store.isLoading {
                VStack(spacing: 14) {
                    SkeletonCard(linhas: 4)
                    SkeletonCard(linhas: 3)
                }
                .padding(.top, 20)
            } else {
                falhaAoCarregar
            }
        } else if let conta = store.account {
            switch conta.status {
            case .draft: rascunho(conta)
            case .underReview: emAnalise(conta)
            case .approved: contaAtiva(conta)
            case .rejected: recusada(conta)
            case .suspended: suspensa(conta)
            }
        } else {
            apresentacao
        }
    }

    private var falhaAoCarregar: some View {
        VStack(spacing: 14) {
            Text(store.errorMessage ?? "Não foi possível carregar o Acolher Financeiro.")
                .font(Theme.body(14))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            RetryButton(isLoading: isRetrying) {
                Task {
                    isRetrying = true
                    await recarregar()
                    isRetrying = false
                }
            }
        }
        .padding(.top, 60)
    }

    // MARK: Sem conta — apresentação

    private var apresentacao: some View {
        VStack(spacing: 16) {
            ThemeCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Theme.primarySoft)
                            .frame(width: 48, height: 48)
                            .overlay(
                                Image(systemName: "building.columns")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(Theme.primary)
                            )
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Acolher Financeiro")
                                .font(Theme.serifTitle(21))
                                .foregroundStyle(Theme.textPrimary)
                            Text("Receba de seus pacientes sem sair do aplicativo.")
                                .font(Theme.body(13))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    Divider().overlay(Theme.border)
                    vantagem("qrcode", "Pix na hora", "Gere o código da cobrança e mande pro paciente por onde quiser.")
                    vantagem("arrow.down.circle", "Saldo no app", "O que o paciente paga entra aqui, com extrato de cada movimento.")
                    vantagem("arrow.up.circle", "Saque pra sua chave Pix", "Peça o saque pelo app; o valor vai para a chave que você cadastrar.")
                    vantagem("checkmark.seal", "Sem sair daqui", "A abertura é feita nesta tela, em cinco etapas.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let fees = store.overview?.fees {
                GwFeesCard(fees: fees, provider: store.overview?.provider ?? .asaasPadrao)
            }

            SeloAsaas(badgeUrl: store.overview?.provider.badgeUrl)

            PrimaryButton(title: "Ativar recebimentos", icon: "arrow.right") {
                showOnboarding = true
            }
            .accessibilityIdentifier("gwAtivar")

            atalhoCobrancas(ativo: false)
        }
    }

    private func vantagem(_ icon: String, _ titulo: String, _ texto: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.primary)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo)
                    .font(Theme.body(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(texto)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: DRAFT

    private func rascunho(_ conta: GwAccount) -> some View {
        VStack(spacing: 16) {
            GwStateCard(
                icon: "doc.badge.ellipsis",
                iconColor: Theme.warning,
                title: "Cadastro em andamento",
                message: "Você parou na etapa \(min(conta.step, 5)) de 5 (\(FinGatewayOnboardingModel.steps[conta.wizardStartIndex])). Continue de onde parou."
            )
            if !conta.missingDocuments.isEmpty {
                ThemeCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("AINDA FALTA ENVIAR")
                            .font(Theme.body(10, weight: .semibold))
                            .tracking(1.1)
                            .foregroundStyle(Theme.textSecondary)
                        ForEach(conta.missingDocuments, id: \.self) { tipo in
                            Label(tipo.label, systemImage: tipo.icon)
                                .font(Theme.body(13))
                                .foregroundStyle(Theme.textPrimary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            PrimaryButton(title: "Continuar cadastro", icon: "arrow.right") {
                showOnboarding = true
            }
            .accessibilityIdentifier("gwContinuarCadastro")
            atalhoCobrancas(ativo: false)
            // Os outros estados já traziam os canais do provedor; o cadastro em
            // andamento é justamente onde mais aparece dúvida.
            if let provider = store.overview?.provider {
                canaisDoProvedor(provider)
            }
        }
    }

    // MARK: UNDER_REVIEW

    private func emAnalise(_ conta: GwAccount) -> some View {
        VStack(spacing: 16) {
            GwStateCard(
                icon: "clock.badge.checkmark",
                iconColor: Theme.primary,
                title: "Conta em análise",
                message: {
                    let quem = store.overview?.provider.name ?? "A instituição de pagamento"
                    let prazo = "O \(quem), instituição de pagamento que opera a conta, confere tudo em até 2 dias úteis e você recebe um aviso aqui no app."
                    guard let enviada = conta.submittedAt else { return prazo }
                    return "Enviada em \(GwFormat.dayTime.string(from: enviada)). \(prazo)"
                }()
            )
            dadosEnviados(conta)
            documentosEnviados(conta)
            atalhoCobrancas(ativo: false)
            if let provider = store.overview?.provider {
                canaisDoProvedor(provider)
            }
        }
    }

    private func documentosEnviados(_ conta: GwAccount) -> some View {
        ThemeCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("DOCUMENTOS ENVIADOS")
                    .font(Theme.body(10, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(Theme.textSecondary)
                ForEach(conta.documents) { documento in
                    HStack(spacing: 12) {
                        Image(systemName: documento.type.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.primary)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(documento.title)
                                .font(Theme.body(14, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                            if let motivo = documento.rejectionReason, !motivo.isEmpty {
                                Text(motivo)
                                    .font(Theme.body(12))
                                    .foregroundStyle(Theme.danger)
                            }
                        }
                        Spacer(minLength: 8)
                        StatusBadge.gwDocument(documento.status)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// O que foi enviado, para conferir sem precisar reabrir o cadastro.
    private func dadosEnviados(_ conta: GwAccount) -> some View {
        ThemeCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("O QUE FOI ENVIADO")
                    .font(Theme.body(10, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(Theme.textSecondary)
                if let nome = conta.legalName, !nome.isEmpty {
                    GwValueRow(label: "Nome", value: nome)
                }
                if let documento = conta.cpfCnpjMasked, !documento.isEmpty {
                    GwValueRow(label: conta.personType == .pj ? "CNPJ" : "CPF", value: documento)
                }
                if let endereco = conta.address {
                    GwValueRow(
                        label: "Endereço",
                        value: "\(endereco.street), \(endereco.number) — \(endereco.city)/\(endereco.state)"
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Só os recusados: com a lista inteira, encontrar o que precisa refazer
    /// vira caça ao erro.
    @ViewBuilder
    private func documentosARenviar(_ conta: GwAccount) -> some View {
        let recusados = conta.documents.filter { $0.status == .rejected }
        if !recusados.isEmpty {
            ThemeCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("DOCUMENTOS A REENVIAR")
                        .font(Theme.body(10, weight: .semibold))
                        .tracking(1.1)
                        .foregroundStyle(Theme.danger)
                    ForEach(recusados) { documento in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: documento.type.icon)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.danger)
                                .frame(width: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(documento.title)
                                    .font(Theme.body(14, weight: .medium))
                                    .foregroundStyle(Theme.textPrimary)
                                Text(documento.rejectionReason?.isEmpty == false
                                     ? documento.rejectionReason!
                                     : "Precisa ser enviado de novo.")
                                    .font(Theme.body(12))
                                    .foregroundStyle(Theme.danger)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Saldo continua existindo com a conta suspensa — esconder isso é o que
    /// mais assusta quem tem dinheiro parado lá.
    @ViewBuilder
    private func saldoRetido(_ conta: GwAccount) -> some View {
        if conta.balance > 0 {
            ThemeCard {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SALDO RETIDO")
                        .font(Theme.body(10, weight: .semibold))
                        .tracking(1.1)
                        .foregroundStyle(Theme.textSecondary)
                    Text(Formatters.brl(conta.balance))
                        .font(Theme.moneyDisplay(24))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                    Text("O valor continua seu e fica retido até a conta ser liberada.")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Dúvidas sobre análise ou operação financeira falam com o Asaas — mas
    /// num item da lista, não num bloco de telefone estampado na tela.
    private func canaisDoProvedor(_ provider: GwProvider) -> some View {
        GwSupportRow(provider: provider)
    }

    // MARK: REJECTED / SUSPENDED

    private func recusada(_ conta: GwAccount) -> some View {
        VStack(spacing: 16) {
            GwStateCard(
                icon: "xmark.octagon",
                iconColor: Theme.danger,
                title: "Cadastro recusado",
                message: "Dá pra corrigir e enviar de novo — seus dados continuam salvos.",
                detail: conta.rejectionReason
            )
            documentosARenviar(conta)
            documentosEnviados(conta)
            PrimaryButton(
                title: "Corrigir e reenviar",
                icon: "arrow.clockwise",
                isLoading: isReopening
            ) {
                Task { await reabrir() }
            }
            atalhoCobrancas(ativo: false)
            if let provider = store.overview?.provider {
                canaisDoProvedor(provider)
            }
        }
    }

    private func suspensa(_ conta: GwAccount) -> some View {
        VStack(spacing: 16) {
            GwStateCard(
                icon: "pause.circle",
                iconColor: Theme.warning,
                title: "Conta suspensa",
                message: {
                    let quem = store.overview?.provider.name ?? "a instituição de pagamento"
                    return "Enquanto estiver suspensa não é possível gerar Pix nem sacar. A liberação depende da análise do \(quem), a instituição de pagamento que opera a conta — fale com o suporte dele abaixo."
                }(),
                detail: conta.suspendedReason
            )
            saldoRetido(conta)
            atalhoCobrancas(ativo: false)
            if let provider = store.overview?.provider {
                canaisDoProvedor(provider)
            }
        }
    }

    private func reabrir() async {
        isReopening = true
        defer { isReopening = false }
        do {
            let conta = try await FinGatewayAPI.reopen()
            store.apply(conta)
            showOnboarding = true
        } catch is CancellationError {
        } catch {
            store.errorMessage = (error as? APIError)?.message
                ?? "Não foi possível reabrir o cadastro."
        }
    }

    // MARK: APPROVED

    private func contaAtiva(_ conta: GwAccount) -> some View {
        VStack(spacing: 16) {
            if store.simulation { GwSimulationBanner() }
            cartaoSaldo(conta)
            cartaoCobrancas
            metricas(conta)
            ultimasMovimentacoesCard
            saquesRecentes
            chavesCard
            atalhoSaqueAutomatico(conta)
            if let fees = store.overview?.fees {
                GwFeesCard(fees: fees, provider: store.overview?.provider ?? .asaasPadrao)
            }
            if let provider = store.overview?.provider {
                GwSupportRow(provider: provider)
            }
        }
    }

    private func cartaoSaldo(_ conta: GwAccount) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("SALDO DISPONÍVEL")
                        .font(Theme.body(10, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(.white.opacity(0.55))
                    Text(Formatters.brl(conta.balance))
                        .font(Theme.moneyDisplay(34))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .accessibilityIdentifier("gwSaldo")
                }
                Spacer(minLength: 8)
                Image(systemName: "building.columns")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
            }

            if conta.pendingWithdrawals > 0 {
                Text("\(conta.pendingWithdrawals) saque\(conta.pendingWithdrawals == 1 ? "" : "s") em processamento.")
                    .font(Theme.body(12))
                    .foregroundStyle(.white.opacity(0.7))
            }

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    NavigationLink {
                        FinChargesEntryView()
                    } label: {
                        acaoDoCartao(icon: "creditcard", title: "Cobrar", destaque: true)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityIdentifier("gwCobrar")

                    NavigationLink {
                        FinGatewayWithdrawView()
                    } label: {
                        acaoDoCartao(icon: "arrow.up.circle", title: "Sacar", destaque: true)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityIdentifier("gwSacar")
                }
                HStack(spacing: 10) {
                    NavigationLink {
                        FinGatewayLedgerView()
                    } label: {
                        acaoDoCartao(icon: "list.bullet.rectangle", title: "Extrato", destaque: false)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityIdentifier("gwExtrato")

                    NavigationLink {
                        FinGatewayPixKeysView()
                    } label: {
                        acaoDoCartao(icon: "key", title: "Chaves Pix", destaque: false)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityIdentifier("gwChaves")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Theme.ink, in: RoundedRectangle(cornerRadius: 20))
    }


    // MARK: Blocos do painel

    /// Cobranças com os números: quanto ainda entra e quanto já atrasou.
    /// Sem eles o painel mandava para outra tela para responder "quanto tenho
    /// a receber?", que é justamente a pergunta do painel.
    private var cartaoCobrancas: some View {
        NavigationLink {
            FinChargesEntryView()
        } label: {
            ThemeCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "creditcard")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.primary)
                            .frame(width: 34, height: 34)
                            .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Cobranças")
                                .font(Theme.body(15, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text("Cobre seus pacientes por Pix e acompanhe quem pagou.")
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary.opacity(0.6))
                    }

                    if let resumo = resumoCobrancas {
                        Divider().overlay(Theme.border)
                        HStack(spacing: 12) {
                            resumoDeCobranca(
                                rotulo: "A receber",
                                valor: resumo.toReceive,
                                cor: Theme.textPrimary
                            )
                            Divider().overlay(Theme.border).frame(height: 32)
                            resumoDeCobranca(
                                rotulo: "Em atraso",
                                valor: resumo.overdue,
                                cor: resumo.overdue > 0 ? Theme.danger : Theme.textPrimary
                            )
                        }
                    }
                }
            }
        }
        .buttonStyle(.pressableSubtle)
        .accessibilityIdentifier("gwCobrancas")
    }

    private func resumoDeCobranca(rotulo: String, valor: Double, cor: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(rotulo.uppercased())
                .font(Theme.body(10, weight: .semibold))
                .tracking(1.1)
                .foregroundStyle(Theme.textSecondary)
            Text(Formatters.brl(valor))
                .font(Theme.money(15, weight: .semibold))
                .foregroundStyle(cor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Prévia do extrato: o painel responde "o que entrou hoje?" sem exigir
    /// abrir a tela cheia.
    @ViewBuilder
    private var ultimasMovimentacoesCard: some View {
        if !ultimasMovimentacoes.isEmpty {
            ThemeCard(padding: 0) {
                VStack(spacing: 0) {
                    HStack {
                        Text("ÚLTIMAS MOVIMENTAÇÕES")
                            .font(Theme.body(10, weight: .semibold))
                            .tracking(1.1)
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        NavigationLink {
                            FinGatewayLedgerView()
                        } label: {
                            Text("Ver extrato")
                                .font(Theme.body(12, weight: .semibold))
                                .foregroundStyle(Theme.primary)
                        }
                        .buttonStyle(.pressable)
                    }
                    .padding(.horizontal, Theme.cardPadding)
                    .padding(.top, 14)
                    .padding(.bottom, 4)

                    ForEach(ultimasMovimentacoes) { entrada in
                        GwLedgerEntryRow(entrada: entrada, mostraSaldo: false)
                        if entrada.id != ultimasMovimentacoes.last?.id {
                            Divider().overlay(Theme.border).padding(.leading, 64)
                        }
                    }
                }
                .padding(.bottom, 6)
            }
        }
    }

    /// As chaves no painel: é onde o terapeuta confere para onde o dinheiro
    /// vai antes de sacar.
    @ViewBuilder
    private var chavesCard: some View {
        if chaves.isEmpty {
            atalhoChavesPix
        } else {
            NavigationLink {
                FinGatewayPixKeysView()
            } label: {
                ThemeCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("MINHAS CHAVES PIX")
                                .font(Theme.body(10, weight: .semibold))
                                .tracking(1.1)
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary.opacity(0.6))
                        }
                        ForEach(chaves) { chave in
                            HStack(spacing: 10) {
                                Image(systemName: "key")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.primary)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(chave.title)
                                        .font(Theme.body(14, weight: .medium))
                                        .foregroundStyle(Theme.textPrimary)
                                        .lineLimit(1)
                                    Text("\(chave.keyType.label) · \(chave.display)")
                                        .font(Theme.body(11))
                                        .foregroundStyle(Theme.textSecondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                if chave.isDefault {
                                    StatusBadge(
                                        label: "PADRÃO",
                                        color: Theme.success,
                                        background: Theme.successSoft
                                    )
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.pressableSubtle)
            .accessibilityIdentifier("gwChavesCard")
        }
    }

    private func acaoDoCartao(icon: String, title: String, destaque: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
            Text(title)
                .font(Theme.body(15, weight: .semibold))
        }
        .foregroundStyle(destaque ? Theme.ink : .white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(destaque ? Color.white : Color.white.opacity(0.12), in: Capsule())
    }

    private func metricas(_ conta: GwAccount) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            MetricCard(
                icon: "arrow.down",
                iconColor: Theme.success,
                label: "Recebido",
                value: Formatters.brl(conta.stats.receivedTotal)
            )
            MetricCard(
                icon: "arrow.up",
                iconColor: Theme.primary,
                label: "Sacado",
                value: Formatters.brl(conta.stats.withdrawnTotal)
            )
            MetricCard(
                icon: "percent",
                iconColor: Theme.warning,
                label: "Taxa de plataforma",
                value: Formatters.brl(conta.stats.platformFeesTotal)
            )
            MetricCard(
                icon: "percent",
                iconColor: Theme.textSecondary,
                label: "Tarifa Pix \(store.overview?.provider.name ?? GwProvider.asaasPadrao.name)",
                value: Formatters.brl(conta.stats.providerFeesTotal)
            )
        }
    }

    @ViewBuilder
    private var saquesRecentes: some View {
        if !ultimosSaques.isEmpty {
            ThemeCard(padding: 0) {
                VStack(spacing: 0) {
                    HStack {
                        Text("ÚLTIMOS SAQUES")
                            .font(Theme.body(10, weight: .semibold))
                            .tracking(1.1)
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        NavigationLink {
                            FinGatewayWithdrawView()
                        } label: {
                            Text("Ver todos")
                                .font(Theme.body(12, weight: .semibold))
                                .foregroundStyle(Theme.primary)
                        }
                        .buttonStyle(.pressable)
                    }
                    .padding(.horizontal, Theme.cardPadding)
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                    ForEach(ultimosSaques) { saque in
                        GwWithdrawalRow(saque: saque)
                            .padding(.horizontal, Theme.cardPadding)
                            .padding(.vertical, 10)
                        if saque.id != ultimosSaques.last?.id {
                            Divider().overlay(Theme.border).padding(.leading, Theme.cardPadding)
                        }
                    }
                }
                .padding(.bottom, 6)
            }
        }
    }

    /// Cobranças moram aqui: só o Acolher Financeiro cobra. Sem conta aprovada a
    /// linha continua, pra consultar as cobranças antigas.
    private func atalhoCobrancas(ativo: Bool) -> some View {
        NavigationLink {
            FinChargesEntryView()
        } label: {
            ThemeCard {
                HStack(spacing: 12) {
                    Image(systemName: "creditcard")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                        .frame(width: 34, height: 34)
                        .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cobranças")
                            .font(Theme.body(15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(ativo
                             ? "Cobre seus pacientes por Pix e acompanhe quem pagou."
                             : "As cobranças são feitas por Pix e chegam com a conta aprovada.")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary.opacity(0.6))
                }
            }
        }
        .buttonStyle(.pressableSubtle)
        .accessibilityIdentifier("gwCobrancas")
    }

    private var atalhoChavesPix: some View {
        NavigationLink {
            FinGatewayPixKeysView()
        } label: {
            ThemeCard {
                HStack(spacing: 12) {
                    Image(systemName: "key")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                        .frame(width: 34, height: 34)
                        .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Minhas chaves Pix")
                            .font(Theme.body(15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Só chaves no seu CPF/CNPJ. É onde o saque cai.")
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
        .accessibilityIdentifier("gwChaves")
    }

    // MARK: Saque automático

    private func atalhoSaqueAutomatico(_ conta: GwAccount) -> some View {
        let auto = conta.autoWithdraw
        return NavigationLink {
            FinGatewayAutoWithdrawView()
        } label: {
            ThemeCard {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(auto.enabled ? Theme.success : Theme.textSecondary)
                        .frame(width: 34, height: 34)
                        .background(
                            auto.enabled ? Theme.successSoft : Theme.background,
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Saque automático")
                            .font(Theme.body(15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(subtituloDoSaqueAutomatico(auto))
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    StatusBadge(
                        label: auto.enabled ? "LIGADO" : "DESLIGADO",
                        color: auto.enabled ? Theme.success : Theme.textSecondary,
                        background: auto.enabled ? Theme.successSoft : Theme.border.opacity(0.5)
                    )
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary.opacity(0.6))
                }
            }
        }
        .buttonStyle(.pressableSubtle)
        .accessibilityIdentifier("gwSaqueAutomatico")
    }

    private func subtituloDoSaqueAutomatico(_ auto: GwAutoWithdraw) -> String {
        guard auto.enabled else { return "O saldo vai sozinho pra sua chave, todo dia às 18h." }
        if let minimo = auto.minAmount, minimo > 0 {
            return "\(auto.scheduleLabel), quando o saldo passar de \(Formatters.brl(minimo))."
        }
        return "\(auto.scheduleLabel), com qualquer saldo disponível."
    }
}

// MARK: - Linha de saque (reaproveitada na home e na tela de saques)

struct GwWithdrawalRow: View {
    let saque: GwWithdrawal

    private var destino: String {
        let chave = "\(saque.pixKeyType.label) · \(saque.pixKeyMasked ?? "")"
        return saque.origin == .auto ? "Automático · \(chave)" : chave
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Formatters.brl(saque.amount))
                    .font(Theme.money(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(destino)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                StatusBadge.gwWithdrawal(saque.status)
                Text(GwFormat.shortDayTime.string(from: saque.requestedAt))
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}
