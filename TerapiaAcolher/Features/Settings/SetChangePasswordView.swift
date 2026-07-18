import Observation
import SwiftUI

/// Trocar senha — POST auth/change-password (senha atual + nova).
struct SetChangePasswordView: View {
    @State private var viewModel = SetChangePasswordViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        SetSectionHeader(title: "Senha atual")
                        ThemeCard {
                            SecureField("Digite sua senha atual", text: $viewModel.current)
                                .font(Theme.body(16))
                                .textContentType(.password)
                        }
                    }

                    VStack(spacing: 8) {
                        SetSectionHeader(title: "Nova senha")
                        ThemeCard {
                            VStack(spacing: 14) {
                                SecureField("Nova senha (mínimo 8 caracteres)", text: $viewModel.nova)
                                    .font(Theme.body(16))
                                    .textContentType(.newPassword)
                                Divider()
                                SecureField("Confirme a nova senha", text: $viewModel.confirmacao)
                                    .font(Theme.body(16))
                                    .textContentType(.newPassword)
                            }
                        }
                    }

                    if let hint = viewModel.validationHint {
                        Text(hint)
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.warning)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }

                    PrimaryButton(
                        title: "Trocar senha",
                        isLoading: viewModel.isSaving,
                        isEnabled: viewModel.canSubmit
                    ) {
                        Task { await viewModel.submit() }
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.vertical, 16)
            }
        }
        .setToolbarTitle("Trocar senha")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Ops", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "Algo deu errado.")
        }
        .alert("Senha alterada", isPresented: $viewModel.showSuccess) {
            Button("OK") { dismiss() }
        } message: {
            Text("Sua senha foi trocada com sucesso.")
        }
    }
}

@Observable
final class SetChangePasswordViewModel {
    var current = ""
    var nova = ""
    var confirmacao = ""
    var isSaving = false
    var errorMessage: String?
    var showError = false
    var showSuccess = false

    var canSubmit: Bool {
        !current.isEmpty && nova.count >= 8 && nova == confirmacao
    }

    var validationHint: String? {
        if !nova.isEmpty, nova.count < 8 {
            return "A nova senha deve ter pelo menos 8 caracteres."
        }
        if !confirmacao.isEmpty, nova != confirmacao {
            return "A confirmação não confere com a nova senha."
        }
        return nil
    }

    @MainActor
    func submit() async {
        struct Body: Encodable {
            let currentPassword: String
            let newPassword: String
            /// Com o refresh token atual, o backend preserva ESTA sessão ao
            /// revogar as demais — sem ele, o app deslogaria sozinho depois.
            let refreshToken: String?
        }
        isSaving = true
        defer { isSaving = false }
        do {
            let _: EmptyResponse = try await APIClient.shared.post(
                "auth/change-password",
                body: Body(
                    currentPassword: current,
                    newPassword: nova,
                    refreshToken: SessionStore.shared.currentRefreshToken
                )
            )
            showSuccess = true
        } catch {
            errorMessage = (error as? APIError)?.message ?? "Não foi possível trocar a senha."
            showError = true
        }
    }
}
