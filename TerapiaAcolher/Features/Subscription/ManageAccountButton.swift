import SwiftUI

// MARK: - "Gerenciar conta" (link por e-mail)
//
// Regra da App Store (3.1.3): o app NÃO vende. Nada de preço, comparação de
// planos, "assine" ou link que abra o navegador para pagar. O único caminho
// para o terapeuta mexer na assinatura é pedir que a API mande para o e-mail
// dele um link que entra no CRM web já logado — quem abre o navegador é ele,
// pelo e-mail, fora do aplicativo.
//
// Um componente só, usado em todos os lugares (login, Assinatura, faixa do
// topo, recursos fora do plano): se cada tela montasse o seu, alguma acabaria
// com um texto que a Apple recusa.

enum ManageAccountAPI {
    /// Logado: `POST auth/web-link` — o e-mail sai para o dono da sessão.
    static func sendLink() async throws -> MessageResponse {
        try await APIClient.shared.post("auth/web-link")
    }

    /// Tela de login (assinatura inativa, sem sessão): `POST auth/web-link/email`.
    /// A resposta é genérica de propósito — não diz se o e-mail tem conta.
    static func sendLink(email: String) async throws -> MessageResponse {
        struct Body: Encodable { let email: String }
        return try await APIClient.shared.post("auth/web-link/email", body: Body(email: email))
    }
}

struct ManageAccountButton: View {
    enum Destination: Equatable {
        /// Usuário logado: o backend sabe para quem mandar.
        case session
        /// Sem sessão (login recusado): manda para o e-mail digitado.
        case email(String)
    }

    enum Style {
        /// Botão cheio verde — quando é a ação principal da tela.
        case primary
        /// Contorno — ao lado de outro conteúdo, sem roubar a cena.
        case secondary
        /// Cápsula pequena para faixas e cartões.
        case compact
    }

    var destination: Destination = .session
    var style: Style = .secondary
    /// Cor da cápsula no estilo compacto (a faixa do topo usa a cor do aviso).
    var tint: Color = Theme.primary

    @State private var isSending = false
    @State private var confirmation: String?
    @State private var errorMessage: String?
    @State private var showErrorAlert = false

    private var canSend: Bool {
        switch destination {
        case .session: true
        case let .email(email): email.trimmingCharacters(in: .whitespaces).contains("@")
        }
    }

    var body: some View {
        Group {
            switch style {
            case .primary, .secondary: fullBody
            case .compact: compactBody
            }
        }
        .animation(.easeOut(duration: 0.2), value: confirmation)
    }

    // MARK: Botão inteiro (login, Assinatura, telas fora do plano)

    @ViewBuilder
    private var fullBody: some View {
        VStack(spacing: 10) {
            if let confirmation {
                AuthInfoBanner(message: confirmation)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                if style == .primary {
                    PrimaryButton(
                        title: "Gerenciar conta",
                        icon: "envelope",
                        isLoading: isSending,
                        isEnabled: canSend
                    ) { send() }
                } else {
                    SecondaryButton(
                        title: "Gerenciar conta",
                        icon: "envelope",
                        isLoading: isSending,
                        isEnabled: canSend,
                        tint: Theme.primary
                    ) { send() }
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(Theme.body(12.5, weight: .medium))
                        .foregroundStyle(Theme.danger)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityIdentifier("gerenciarConta")
    }

    // MARK: Cápsula (faixa do topo, cartão do Zelo)

    @ViewBuilder
    private var compactBody: some View {
        if confirmation != nil {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("Link enviado ao seu e-mail")
                    .font(Theme.body(12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(Theme.success)
            .transition(.opacity)
            .accessibilityElement(children: .combine)
        } else {
            Button {
                send()
            } label: {
                HStack(spacing: 6) {
                    Text("Gerenciar conta")
                        .font(Theme.body(12.5, weight: .semibold))
                        .lineLimit(1)
                    if isSending {
                        ProgressView().controlSize(.mini).tint(.white)
                    } else {
                        Image(systemName: "envelope")
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(tint, in: Capsule())
                .animation(.easeInOut(duration: 0.15), value: isSending)
            }
            .buttonStyle(.pressable)
            .disabled(isSending || !canSend)
            .fixedSize()
            .accessibilityIdentifier("gerenciarConta")
            .alert("Não deu certo", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: Envio

    private func send() {
        guard !isSending, canSend else { return }
        Haptics.tap()
        errorMessage = nil
        isSending = true
        Task { @MainActor in
            defer { isSending = false }
            do {
                let response: MessageResponse
                switch destination {
                case .session:
                    response = try await ManageAccountAPI.sendLink()
                case let .email(email):
                    response = try await ManageAccountAPI.sendLink(
                        email: email.trimmingCharacters(in: .whitespaces)
                    )
                }
                Haptics.success()
                confirmation = response.message
            } catch is CancellationError {
                // tela fechada no meio do envio — silencioso
            } catch let error as APIError {
                fail(error.message)
            } catch {
                fail("Não foi possível enviar o link agora. Verifique sua internet e tente de novo.")
            }
        }
    }

    @MainActor
    private func fail(_ message: String) {
        Haptics.warning()
        errorMessage = message
        if style == .compact { showErrorAlert = true }
    }
}

// MARK: - Recurso fora do plano

/// Estado calmo para recurso que o plano não inclui (leads, Vitrine, Acolher
/// Financeiro). Não é erro — é informação, com o caminho do e-mail ao lado.
/// Nunca nomeia plano nem preço.
struct NotInPlanView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundStyle(Theme.primary)
                    .frame(width: 64, height: 64)
                    .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 18))

                Text("NÃO INCLUÍDO NO SEU PLANO")
                    .font(Theme.body(11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Theme.border.opacity(0.6), in: Capsule())

                Text(title)
                    .font(Theme.serifTitle(22))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ManageAccountButton(style: .secondary)

            Text(ManageAccountCopy.footer)
                .font(Theme.body(12))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
    }
}

enum ManageAccountCopy {
    /// Texto neutro que explica o botão — sem preço e sem "assine".
    static let footer = "Para gerenciar a sua assinatura, toque em Gerenciar conta: enviamos um link para o seu e-mail."
}
