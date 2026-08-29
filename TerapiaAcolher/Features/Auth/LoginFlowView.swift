import SwiftUI
import Observation

// MARK: - Rotas do fluxo de autenticação

enum AuthRoute: Hashable {
    case register
    case checkEmail(email: String)
    case forgotPassword
    case resetPassword
}

// MARK: - ViewModel do login

@Observable
final class AuthLoginModel {
    var email = ""
    var password = ""
    var isLoading = false
    var isResending = false
    var errorMessage: String?
    /// 403 de e-mail pendente → oferece reenvio da confirmação.
    var canResendVerification = false
    var infoMessage: String?

    var canSubmit: Bool {
        email.contains("@") && !password.isEmpty
    }

    @MainActor
    func submit() async {
        errorMessage = nil
        infoMessage = nil
        canResendVerification = false
        isLoading = true
        defer { isLoading = false }
        do {
            try await SessionStore.shared.login(
                email: email.trimmingCharacters(in: .whitespaces),
                password: password
            )
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
        } catch let error as APIError {
            errorMessage = error.message
            if error.statusCode == 403, error.message.localizedCaseInsensitiveContains("confirme seu e-mail") {
                canResendVerification = true
            }
        } catch {
            errorMessage = "Não foi possível conectar. Verifique sua internet e tente de novo."
        }
    }

    @MainActor
    func resendVerification() async {
        struct Body: Encodable { let email: String }
        // Flag própria: usar `isLoading` acendia o spinner no botão "Entrar",
        // que não foi o controle tocado.
        isResending = true
        defer { isResending = false }
        do {
            let response: MessageResponse = try await APIClient.shared.post(
                "auth/resend-verification",
                body: Body(email: email.trimmingCharacters(in: .whitespaces))
            )
            errorMessage = nil
            canResendVerification = false
            infoMessage = response.message
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
        } catch let error as APIError {
            errorMessage = error.message
        } catch {
            errorMessage = "Não foi possível reenviar agora. Tente de novo em instantes."
        }
    }
}

// MARK: - Tela de login (raiz do fluxo de auth)

struct LoginFlowView: View {
    @State private var path: [AuthRoute] = []
    @State private var model = AuthLoginModel()

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                AuthBackground()
                ScrollView {
                    VStack(spacing: 0) {
                        AuthLogoView()
                            .padding(.top, 48)

                        Text("Terapia Acolher")
                            .font(Theme.serifTitle(34))
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.top, 28)

                        Text("Painel da terapeuta")
                            .font(Theme.body(15))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.top, 6)

                        VStack(spacing: 18) {
                            AuthField(
                                label: "E-mail",
                                text: $model.email,
                                placeholder: "seu@email.com.br",
                                keyboard: .emailAddress,
                                contentType: .username
                            )
                            AuthField(
                                label: "Senha",
                                text: $model.password,
                                isSecure: true,
                                contentType: .password
                            )

                            if let error = model.errorMessage {
                                AuthErrorBanner(message: error)
                            }
                            if let info = model.infoMessage {
                                AuthInfoBanner(message: info)
                            }
                            if model.canResendVerification {
                                Button {
                                    Haptics.tap()
                                    Task { await model.resendVerification() }
                                } label: {
                                    HStack(spacing: 8) {
                                        Text("Reenviar e-mail de confirmação")
                                        if model.isResending {
                                            ProgressView().controlSize(.small).tint(Theme.primary)
                                        }
                                    }
                                    .font(Theme.body(14, weight: .semibold))
                                    .foregroundStyle(Theme.primary)
                                    .animation(.easeInOut(duration: 0.15), value: model.isResending)
                                }
                                .buttonStyle(.pressable)
                                .disabled(model.isResending)
                            }

                            PrimaryButton(
                                title: "Entrar",
                                icon: "arrow.right",
                                isLoading: model.isLoading,
                                isEnabled: model.canSubmit
                            ) {
                                Task { await model.submit() }
                            }
                            .padding(.top, 4)

                            Button {
                                path.append(.forgotPassword)
                            } label: {
                                Text("Esqueci minha senha")
                                    .font(Theme.body(15, weight: .medium))
                                    .foregroundStyle(Color(hex: 0x46656F))
                            }
                            .padding(.top, 4)
                        }
                        .padding(.top, 40)

                        HStack(spacing: 4) {
                            Text("Ainda não tem conta?")
                                .font(Theme.body(14))
                                .foregroundStyle(Theme.textSecondary)
                            Button {
                                path.append(.register)
                            } label: {
                                Text("Criar conta")
                                    .font(Theme.body(14, weight: .bold))
                                    .foregroundStyle(Theme.primary)
                            }
                        }
                        .padding(.top, 36)
                        .padding(.bottom, 32)
                    }
                    .padding(.horizontal, 28)
                    .frame(maxWidth: 480)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationDestination(for: AuthRoute.self) { route in
                switch route {
                case .register:
                    AuthRegisterView(path: $path)
                case let .checkEmail(email):
                    AuthCheckEmailView(email: email, path: $path)
                case .forgotPassword:
                    AuthForgotPasswordView(path: $path)
                case .resetPassword:
                    AuthResetPasswordView(path: $path)
                }
            }
        }
        .tint(Theme.primary)
    }
}

#Preview {
    LoginFlowView()
}
