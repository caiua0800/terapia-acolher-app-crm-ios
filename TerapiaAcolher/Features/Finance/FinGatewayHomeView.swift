import SwiftUI

// MARK: - Gateway Acolher — porta de entrada da conta do terapeuta
//
// Uma tela só, dirigida pelo status da conta: apresentação → assistente →
// análise → conta ativa. O caminho antigo (conta Asaas própria + Wallet ID)
// continua existindo, num link discreto no rodapé.

struct FinGatewayHomeView: View {
    @State private var store = FinGatewayStore.shared
    @State private var showOnboarding = false
    @State private var isReopening = false
    @State private var isRetrying = false
    @State private var ultimosSaques: [GwWithdrawal] = []

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    conteudo
                    if let overview = store.overview {
                        linkCarteiraPropria
                        GwProviderFooter(provider: overview.provider)
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
            .refreshable { await recarregar() }
        }
        .setToolbarTitle("Gateway Acolher")
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
            return
        }
        if let pagina = try? await FinGatewayAPI.withdrawals(page: 1, pageSize: 3) {
            ultimosSaques = pagina.items
        }
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
            Text(store.errorMessage ?? "Não foi possível carregar o Gateway Acolher.")
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
                            Text("Gateway Acolher")
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
                GwFeesCard(fees: fees)
            }

            if let badge = store.overview?.provider.badgeUrl {
                SeloAsaas(badgeUrl: badge)
            } else {
                SeloAsaas(badgeUrl: nil)
            }

            PrimaryButton(title: "Ativar recebimentos", icon: "arrow.right") {
                showOnboarding = true
            }
            .accessibilityIdentifier("gwAtivar")
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
        }
    }

    // MARK: UNDER_REVIEW

    private func emAnalise(_ conta: GwAccount) -> some View {
        VStack(spacing: 16) {
            GwStateCard(
                icon: "clock.badge.checkmark",
                iconColor: Theme.primary,
                title: "Conta em análise",
                message: conta.submittedAt.map {
                    "Enviada em \(GwFormat.dayTime.string(from: $0)). Assim que a análise terminar você recebe um aviso aqui no app."
                } ?? "Assim que a análise terminar você recebe um aviso aqui no app."
            )
            documentosEnviados(conta)
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

    private func canaisDoProvedor(_ provider: GwProvider) -> some View {
        ThemeCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("CANAIS DE ATENDIMENTO DO \(provider.name.uppercased())")
                    .font(Theme.body(10, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(Theme.textSecondary)
                Text("Dúvidas sobre a análise ou sobre os serviços financeiros falam direto com o \(provider.name).")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textSecondary)
                if let tel = URL(string: "tel://\(provider.supportPhone.filter(\.isNumber))") {
                    Link(destination: tel) {
                        Label(provider.supportPhone, systemImage: "phone")
                            .font(Theme.body(14, weight: .semibold))
                            .foregroundStyle(Theme.primary)
                    }
                }
                if let mail = URL(string: "mailto:\(provider.supportEmail)") {
                    Link(destination: mail) {
                        Label(provider.supportEmail, systemImage: "envelope")
                            .font(Theme.body(14, weight: .semibold))
                            .foregroundStyle(Theme.primary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
            documentosEnviados(conta)
            PrimaryButton(
                title: "Corrigir e reenviar",
                icon: "arrow.clockwise",
                isLoading: isReopening
            ) {
                Task { await reabrir() }
            }
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
                message: "Enquanto estiver suspensa não é possível gerar Pix nem sacar.",
                detail: conta.suspendedReason
            )
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
            metricas(conta)
            saquesRecentes
            atalhoChavesPix
            if let fees = store.overview?.fees {
                GwFeesCard(fees: fees)
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
                Text("\(conta.pendingWithdrawals) saque\(conta.pendingWithdrawals == 1 ? "" : "s") aguardando aprovação.")
                    .font(Theme.body(12))
                    .foregroundStyle(.white.opacity(0.7))
            }

            HStack(spacing: 10) {
                NavigationLink {
                    FinGatewayWithdrawView()
                } label: {
                    acaoDoCartao(icon: "arrow.up.circle", title: "Sacar", destaque: true)
                }
                .buttonStyle(.pressable)
                .accessibilityIdentifier("gwSacar")

                NavigationLink {
                    FinGatewayLedgerView()
                } label: {
                    acaoDoCartao(icon: "list.bullet.rectangle", title: "Extrato", destaque: false)
                }
                .buttonStyle(.pressable)
                .accessibilityIdentifier("gwExtrato")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Theme.ink, in: RoundedRectangle(cornerRadius: 20))
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
                label: "Tarifa Pix Asaas",
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
                        Text("Onde o dinheiro do saque cai.")
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

    // MARK: Caminho antigo

    private var linkCarteiraPropria: some View {
        NavigationLink {
            FinWalletView()
        } label: {
            Text("Já tenho conta Asaas própria (Wallet ID)")
                .font(Theme.body(13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .underline()
        }
        .buttonStyle(.pressable)
        .padding(.top, 6)
    }
}

// MARK: - Linha de saque (reaproveitada na home e na tela de saques)

struct GwWithdrawalRow: View {
    let saque: GwWithdrawal

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Formatters.brl(saque.amount))
                    .font(Theme.money(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(saque.pixKeyType.label) · \(saque.pixKeyMasked ?? "")")
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
