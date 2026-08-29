import SwiftUI

/// Carteira Asaas: status da conexão, cadastro do Wallet ID e guia passo a passo.
/// Acessível pelo Financeiro e pelas Configurações.
struct FinWalletView: View {
    @State private var status: FinWalletStatus?
    @State private var guide: FinWalletGuide?
    @State private var walletIdText = ""
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var savedFeedback = false
    @State private var errorMessage: String?

    private var isWalletIdValid: Bool {
        let pattern = "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
        return walletIdText.trimmingCharacters(in: .whitespaces)
            .range(of: pattern, options: .regularExpression) != nil
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    statusCard
                    walletForm
                    if let guide { guideSection(guide) }
                }
                .padding(Theme.screenPadding)
            }
        }
        .navigationTitle("Carteira Asaas")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .alert("Ops", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Status

    private var statusCard: some View {
        ThemeCard {
            HStack(spacing: 12) {
                Circle()
                    .fill(status?.connected == true ? Theme.successSoft : Theme.warningSoft)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: status?.connected == true ? "checkmark.seal.fill" : "wallet.pass")
                            .font(.system(size: 18))
                            .foregroundStyle(status?.connected == true ? Theme.success : Theme.warning)
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text(status?.connected == true ? "Carteira conectada" : "Carteira não conectada")
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    if let status, status.connected, let masked = status.walletId {
                        Text("Wallet ID: \(masked)")
                            .font(Theme.money(12))
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        Text("Cadastre seu Wallet ID pra receber pagamentos online.")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer()
                if isLoading { ProgressView() }
            }
        }
    }

    // MARK: Formulário do Wallet ID

    private var walletForm: some View {
        ThemeCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("WALLET ID DA SUA CONTA ASAAS")
                    .font(Theme.body(10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.textSecondary)
                TextField("a1b2c3d4-e5f6-7890-abcd-ef1234567890", text: $walletIdText)
                    .font(Theme.money(13))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: 10))
                PrimaryButton(
                    title: savedFeedback
                        ? "Salvo!"
                        : (status?.connected == true ? "Atualizar Wallet ID" : "Salvar Wallet ID"),
                    icon: savedFeedback ? "checkmark" : nil,
                    isLoading: isSaving,
                    isEnabled: isWalletIdValid
                ) {
                    Task { await save() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Guia passo a passo

    private func guideSection(_ guide: FinWalletGuide) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(guide.title)
                .font(Theme.serifTitle(20))
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 8)
            Text(guide.intro)
                .font(Theme.body(14))
                .foregroundStyle(Theme.textSecondary)

            ForEach(guide.steps) { step in
                ThemeCard {
                    HStack(alignment: .top, spacing: 12) {
                        Circle()
                            .fill(Theme.primarySoft)
                            .frame(width: 32, height: 32)
                            .overlay(
                                Text("\(step.order)")
                                    .font(Theme.body(14, weight: .bold))
                                    .foregroundStyle(Theme.primary)
                            )
                        VStack(alignment: .leading, spacing: 4) {
                            Text(step.title)
                                .font(Theme.body(15, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text(step.description)
                                .font(Theme.body(13))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }

            if !guide.notes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(guide.notes, id: \.self) { note in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.success)
                                .padding(.top, 2)
                            Text(note)
                                .font(Theme.body(13))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.successSoft.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
            }
        }
    }

    // MARK: Dados

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let statusTask = FinanceAPI.walletStatus()
            async let guideTask = FinanceAPI.walletGuide()
            status = try await statusTask
            guide = try await guideTask
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
        } catch {
            errorMessage = (error as? APIError)?.message ?? "Não foi possível carregar a carteira."
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            status = try await FinanceAPI.upsertWallet(
                walletId: walletIdText.trimmingCharacters(in: .whitespaces)
            )
            walletIdText = ""
            withAnimation { savedFeedback = true }
            Task {
                try? await Task.sleep(for: .seconds(2))
                withAnimation { savedFeedback = false }
            }
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
        } catch {
            errorMessage = (error as? APIError)?.message ?? "Não foi possível salvar o Wallet ID."
        }
    }
}
