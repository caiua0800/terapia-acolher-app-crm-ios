import SwiftUI
import Observation

// MARK: - Esqueci minha senha (pede o e-mail)

@Observable
final class AuthForgotModel {
    var email = ""
    var isLoading = false
    var errorMessage: String?
    /// Mensagem genérica do backend após o envio (não vaza existência da conta).
    var sentMessage: String?

    @MainActor
    func submit() async {
        struct Body: Encodable { let email: String }
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let response: MessageResponse = try await APIClient.shared.post(
                "auth/forgot-password",
                body: Body(email: email.trimmingCharacters(in: .whitespaces))
            )
            sentMessage = response.message
        } catch let error as APIError {
            errorMessage = error.message
        } catch {
            errorMessage = "Não foi possível enviar agora. Verifique sua internet e tente de novo."
        }
    }
}

struct AuthForgotPasswordView: View {
    @Binding var path: [AuthRoute]
    @State private var model = AuthForgotModel()

    var body: some View {
        ZStack {
            AuthBackground()
            ScrollView {
                VStack(spacing: 18) {
                    Circle()
                        .fill(Theme.primarySoft)
                        .frame(width: 88, height: 88)
                        .overlay(
                            Image(systemName: "key")
                                .font(.system(size: 34))
                                .foregroundStyle(Theme.primary)
                        )
                        .padding(.top, 40)

                    Text("Esqueci minha senha")
                        .font(Theme.serifTitle(28))
                        .foregroundStyle(Theme.textPrimary)

                    Text("Informe seu e-mail e enviaremos um código pra você criar uma nova senha.")
                        .font(Theme.body(15))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)

                    if let sent = model.sentMessage {
                        AuthInfoBanner(message: sent)

                        PrimaryButton(title: "Já tenho o código", icon: "arrow.right") {
                            path.append(.resetPassword)
                        }
                        .padding(.top, 8)
                    } else {
                        AuthField(
                            label: "E-mail",
                            text: $model.email,
                            placeholder: "seu@email.com.br",
                            keyboard: .emailAddress,
                            contentType: .username
                        )
                        .padding(.top, 8)

                        if let error = model.errorMessage {
                            AuthErrorBanner(message: error)
                        }

                        PrimaryButton(
                            title: "Enviar instruções",
                            icon: "paperplane",
                            isLoading: model.isLoading,
                            isEnabled: model.email.contains("@")
                        ) {
                            Task { await model.submit() }
                        }
                        .padding(.top, 6)

                        Button {
                            path.append(.resetPassword)
                        } label: {
                            Text("Já tenho o código")
                                .font(Theme.body(15, weight: .medium))
                                .foregroundStyle(Color(hex: 0x46656F))
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 28)
                .frame(maxWidth: 480)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Redefinir senha (código + nova senha)

@Observable
final class AuthResetModel {
    var token = ""
    var newPassword = ""
    var confirmPassword = ""
    var isLoading = false
    var errorMessage: String?
    var successMessage: String?

    var canSubmit: Bool {
        token.trimmingCharacters(in: .whitespaces).count >= 10
            && newPassword.count >= 8
            && newPassword == confirmPassword
    }

    @MainActor
    func submit() async {
        struct Body: Encodable { let token: String, newPassword: String }
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let response: MessageResponse = try await APIClient.shared.post(
                "auth/reset-password",
                body: Body(token: token.trimmingCharacters(in: .whitespacesAndNewlines), newPassword: newPassword)
            )
            successMessage = response.message
        } catch let error as APIError {
            errorMessage = error.message
        } catch {
            errorMessage = "Não foi possível redefinir agora. Tente de novo."
        }
    }
}

struct AuthResetPasswordView: View {
    @Binding var path: [AuthRoute]
    @State private var model = AuthResetModel()

    var body: some View {
        ZStack {
            AuthBackground()
            ScrollView {
                VStack(spacing: 18) {
                    Text("Nova senha")
                        .font(Theme.serifTitle(28))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.top, 32)

                    Text("Cole o código que você recebeu por e-mail e escolha sua nova senha.")
                        .font(Theme.body(15))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)

                    if let success = model.successMessage {
                        AuthInfoBanner(message: success)
                        PrimaryButton(title: "Ir para o login", icon: "arrow.right") {
                            path.removeAll()
                        }
                        .padding(.top, 8)
                    } else {
                        AuthField(
                            label: "Código recebido por e-mail",
                            text: $model.token,
                            placeholder: "Cole o código aqui"
                        )
                        AuthField(
                            label: "Nova senha",
                            text: $model.newPassword,
                            placeholder: "Mínimo 8 caracteres",
                            isSecure: true,
                            contentType: .newPassword
                        )
                        AuthField(
                            label: "Confirmar nova senha",
                            text: $model.confirmPassword,
                            isSecure: true,
                            contentType: .newPassword
                        )

                        if !model.confirmPassword.isEmpty, model.newPassword != model.confirmPassword {
                            AuthErrorBanner(message: "As senhas não conferem.")
                        }
                        if let error = model.errorMessage {
                            AuthErrorBanner(message: error)
                        }

                        PrimaryButton(
                            title: "Redefinir senha",
                            icon: "checkmark",
                            isLoading: model.isLoading,
                            isEnabled: model.canSubmit
                        ) {
                            Task { await model.submit() }
                        }
                        .padding(.top, 6)
                    }
                }
                .padding(.horizontal, 28)
                .frame(maxWidth: 480)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}
