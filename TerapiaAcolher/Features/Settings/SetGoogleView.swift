import Observation
import SwiftUI

/// Integração Google Calendar / Meet.
/// Conecta abrindo a URL OAuth no navegador; o usuário autoriza lá e
/// volta ao app ("Já autorizei — atualizar" recarrega o status).
struct SetGoogleView: View {
    var onChanged: () -> Void = {}

    @State private var viewModel = SetGoogleViewModel()
    @State private var showDisconnectConfirm = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if viewModel.isLoading {
                ProgressView().tint(Theme.primary)
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        header
                        if viewModel.status?.connected == true {
                            connectedCard
                        } else {
                            disconnectedCard
                        }
                    }
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.vertical, 16)
                }
            }
        }
        .setToolbarTitle("Google Calendar · Meet")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .alert("Ops", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "Algo deu errado.")
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "video.fill")
                .font(.system(size: 30))
                .foregroundStyle(Color(hex: 0x7FA8C9))
                .frame(width: 68, height: 68)
                .background(Color(hex: 0x7FA8C9).opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 18))
            Text("Sessões online com Google Meet")
                .font(Theme.serifTitle(20))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Text("Conecte sua conta Google para criar eventos na agenda e gerar links do Meet automaticamente nas sessões online.")
                .font(Theme.body(14))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private var connectedCard: some View {
        VStack(spacing: 16) {
            ThemeCard {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.success)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Conta conectada")
                            .font(Theme.body(15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(viewModel.status?.googleEmail ?? "—")
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    StatusBadge(label: "ATIVA", color: Theme.success, background: Theme.successSoft)
                }
            }

            Button {
                showDisconnectConfirm = true
            } label: {
                HStack {
                    if viewModel.isWorking {
                        ProgressView().tint(Theme.danger)
                    } else {
                        Label("Desconectar", systemImage: "xmark.circle")
                    }
                }
                .font(Theme.body(15, weight: .semibold))
                .foregroundStyle(Theme.danger)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.dangerSoft)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
            }
            .disabled(viewModel.isWorking)
            .confirmationDialog(
                "Desconectar a conta Google?",
                isPresented: $showDisconnectConfirm,
                titleVisibility: .visible
            ) {
                Button("Desconectar", role: .destructive) {
                    Task {
                        await viewModel.disconnect()
                        onChanged()
                    }
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Novas sessões online não vão mais gerar link do Google Meet.")
            }
        }
    }

    private var disconnectedCard: some View {
        VStack(spacing: 14) {
            PrimaryButton(title: "Conectar com Google", icon: "arrow.up.right", isLoading: viewModel.isWorking) {
                Task {
                    if let url = await viewModel.fetchAuthURL() {
                        openURL(url)
                    }
                }
            }

            if viewModel.didOpenAuth {
                ThemeCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Label {
                            Text("Autorize no navegador e volte ao app")
                                .font(Theme.body(14, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                        } icon: {
                            Image(systemName: "safari")
                                .foregroundStyle(Theme.primary)
                        }
                        Text("Depois de autorizar sua conta Google no Safari, toque no botão abaixo para atualizar o status da conexão.")
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.textSecondary)
                        Button {
                            Haptics.tap()
                            Task {
                                await viewModel.refreshStatus()
                                onChanged()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if viewModel.isRefreshingStatus {
                                    ProgressView().controlSize(.small).tint(Theme.primary)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                                Text("Já autorizei — atualizar")
                            }
                            .font(Theme.body(14, weight: .semibold))
                            .foregroundStyle(Theme.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Theme.primarySoft)
                            .clipShape(Capsule())
                            .animation(.easeInOut(duration: 0.15), value: viewModel.isRefreshingStatus)
                        }
                        .buttonStyle(.pressable)
                        .disabled(viewModel.isRefreshingStatus)
                    }
                }
            }
        }
    }
}

@Observable
final class SetGoogleViewModel {
    var status: SetGoogleStatus?
    var isLoading = true
    var isWorking = false
    /// Recheque manual do status ("Já autorizei") — spinner no próprio botão.
    var isRefreshingStatus = false
    var didOpenAuth = false
    var errorMessage: String?
    var showError = false

    @MainActor
    func load() async {
        do {
            status = try await APIClient.shared.get("integrations/google/status")
            isLoading = false
            if status?.connected == true { didOpenAuth = false }
        } catch {
            isLoading = false
            present(error)
        }
    }

    @MainActor
    func refreshStatus() async {
        isRefreshingStatus = true
        defer { isRefreshingStatus = false }
        await load()
    }

    @MainActor
    func fetchAuthURL() async -> URL? {
        isWorking = true
        defer { isWorking = false }
        do {
            let response: SetAuthURL = try await APIClient.shared.get("integrations/google/auth-url")
            didOpenAuth = true
            return URL(string: response.url)
        } catch {
            present(error)
            return nil
        }
    }

    @MainActor
    func disconnect() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let _: EmptyResponse = try await APIClient.shared.delete("integrations/google")
            await load()
        } catch {
            present(error)
        }
    }

    @MainActor
    private func present(_ error: Error) {
        errorMessage = (error as? APIError)?.message ?? "Não foi possível concluir. Verifique sua conexão."
        showError = true
    }
}
