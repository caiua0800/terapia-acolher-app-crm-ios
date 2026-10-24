import SwiftUI
import Observation

// MARK: - Cadastro do terapeuta

@Observable
final class AuthRegisterModel {
    var name = ""
    var email = ""
    var password = ""
    var specialty = ""
    var professionalRegistration = ""
    /// Número mascarado, sem o DDI; o país fica ao lado (Brasil por padrão).
    var whatsapp = ""
    var whatsappPais = TelefoneInternacional.brasil
    var isLoading = false
    var errorMessage: String?

    /// Validação do número reaproveitada pelo botão e pela mensagem do campo.
    /// O `payload` já sai no formato da API: "55…" no Brasil, "+DDI…" fora.
    var phoneCheck: PhoneRules.Result { TelefoneInternacional.validarWhatsapp(whatsappPais, whatsapp) }

    /// Só aparece depois que a pessoa digitou algo: erro em campo vazio antes
    /// de qualquer digitação é regra sendo esfregada na cara de quem chegou.
    var phoneError: String? {
        whatsapp.isEmpty ? nil : phoneCheck.error
    }

    var canSubmit: Bool {
        name.trimmingCharacters(in: .whitespaces).count >= 2
            && email.contains("@")
            && password.count >= 10
            && phoneCheck.isValid
    }

    /// POST auth/register → resposta genérica; sucesso leva à tela "confira seu e-mail".
    @MainActor
    func submit() async -> Bool {
        struct Body: Encodable {
            let name: String
            let email: String
            let password: String
            let specialty: String?
            let professionalRegistration: String?
            let whatsapp: String
        }
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let _: MessageResponse = try await APIClient.shared.post(
                "auth/register",
                body: Body(
                    name: name.trimmingCharacters(in: .whitespaces),
                    email: email.trimmingCharacters(in: .whitespaces),
                    password: password,
                    specialty: specialty.isEmpty ? nil : specialty,
                    professionalRegistration: professionalRegistration.isEmpty ? nil : professionalRegistration,
                    // Manda os dígitos com DDI, nunca a máscara ("+" na
                    // frente se for de fora do Brasil).
                    whatsapp: phoneCheck.payload ?? whatsapp
                )
            )
            return true
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
        } catch let error as APIError {
            errorMessage = error.message
        } catch {
            errorMessage = "Não foi possível criar a conta agora. Tente de novo."
        }
        return false
    }
}

struct AuthRegisterView: View {
    @Binding var path: [AuthRoute]
    @State private var model = AuthRegisterModel()

    var body: some View {
        ZStack {
            AuthBackground()
            ScrollView {
                VStack(spacing: 18) {
                    Text("Criar conta")
                        .font(Theme.serifTitle(30))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.top, 24)
                    Text("Seu consultório completo no bolso 🌿")
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.bottom, 8)

                    AuthField(label: "Nome completo", text: $model.name, placeholder: "Maria Silva", contentType: .name, autocapitalize: true)
                    AuthField(label: "E-mail", text: $model.email, placeholder: "seu@email.com.br", keyboard: .emailAddress, contentType: .username)
                    AuthField(label: "Senha", text: $model.password, placeholder: "Mínimo 10 caracteres", isSecure: true, contentType: .newPassword)
                    AuthField(label: "Especialidade · opcional", text: $model.specialty, placeholder: "Psicologia", autocapitalize: true)
                    AuthField(label: "Registro profissional · opcional", text: $model.professionalRegistration, placeholder: "CRP 06/54321")
                    VStack(alignment: .leading, spacing: 6) {
                        // Mesma moldura do `AuthField`, com o país ao lado do número.
                        VStack(alignment: .leading, spacing: 8) {
                            Text("WHATSAPP")
                                .font(Theme.body(11, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                                .tracking(1.4)
                            CampoTelefoneInternacional(pais: $model.whatsappPais, numero: $model.whatsapp)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 13)
                                .background(Theme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(model.phoneError == nil ? Theme.border : Theme.danger, lineWidth: 1)
                                )
                        }
                        // Obrigatório desde 2026-09: é por ele que sai o código
                        // de verificação e todo aviso de cobrança e sessão.
                        Text(model.phoneError ?? "Você vai confirmar este número no app depois de entrar.")
                            .font(Theme.body(12))
                            .foregroundStyle(model.phoneError == nil ? Theme.textSecondary : Theme.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let error = model.errorMessage {
                        AuthErrorBanner(message: error)
                    }

                    PrimaryButton(
                        title: "Criar conta",
                        icon: "arrow.right",
                        isLoading: model.isLoading,
                        isEnabled: model.canSubmit
                    ) {
                        Task {
                            if await model.submit() {
                                path.append(.checkEmail(email: model.email.trimmingCharacters(in: .whitespaces)))
                            }
                        }
                    }
                    .padding(.top, 6)
                    .padding(.bottom, 32)
                }
                .padding(.horizontal, 28)
                .frame(maxWidth: 480)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - "Confira seu e-mail" (pós-cadastro)

struct AuthCheckEmailView: View {
    let email: String
    @Binding var path: [AuthRoute]

    @State private var isResending = false
    @State private var feedback: String?
    @State private var resendError: String?

    var body: some View {
        ZStack {
            AuthBackground()
            ScrollView {
                VStack(spacing: 16) {
                    Circle()
                        .fill(Theme.primarySoft)
                        .frame(width: 96, height: 96)
                        .overlay(
                            Image(systemName: "envelope.open")
                                .font(.system(size: 38))
                                .foregroundStyle(Theme.primary)
                        )
                        .padding(.top, 56)

                    Text("Confira seu e-mail")
                        .font(Theme.serifTitle(28))
                        .foregroundStyle(Theme.textPrimary)

                    Text("Enviamos um link de confirmação para\n**\(email)**.\nToque no link do e-mail e depois volte aqui pra entrar.")
                        .font(Theme.body(15))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)

                    if let feedback {
                        AuthInfoBanner(message: feedback)
                    }
                    if let resendError {
                        AuthErrorBanner(message: resendError)
                    }

                    PrimaryButton(
                        title: "Reenviar e-mail",
                        icon: "paperplane",
                        isLoading: isResending
                    ) {
                        Task { await resend() }
                    }
                    .padding(.top, 16)

                    Button {
                        path.removeAll()
                    } label: {
                        Text("Voltar para o login")
                            .font(Theme.body(15, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x46656F))
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 28)
                .frame(maxWidth: 480)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
    }

    @MainActor
    private func resend() async {
        struct Body: Encodable { let email: String }
        feedback = nil
        resendError = nil
        isResending = true
        defer { isResending = false }
        do {
            let response: MessageResponse = try await APIClient.shared.post(
                "auth/resend-verification",
                body: Body(email: email)
            )
            feedback = response.message
        } catch is CancellationError {
            // requisição cancelada (refresh/troca de tela) — silencioso
        } catch let error as APIError {
            resendError = error.message
        } catch {
            resendError = "Não foi possível reenviar agora. Tente de novo em instantes."
        }
    }
}
