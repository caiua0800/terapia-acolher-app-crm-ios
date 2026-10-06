import SwiftUI
import Observation

// MARK: - Login de local novo: código por e-mail ou WhatsApp
//
// A senha estava certa, mas o login veio de um IP que a terapeuta nunca
// confirmou (backend: LOGIN_VERIFICAR_IP_NOVO). Ela escolhe o canal, recebe o
// código de 6 dígitos e só então a sessão abre — pelo mesmo caminho do login
// normal (SessionStore), então RootView segue sozinho.

@Observable
final class AuthLoginCodeModel {
    let challenge: LoginChallenge
    /// Canal em que o código foi mandado (nil = ainda escolhendo).
    var sent: LoginCodeSent?
    var code = ""
    /// Uma flag por controle (regra do projeto): o spinner acende só no tocado.
    var sendingChannel: String?
    var isResending = false
    var isVerifying = false
    var errorMessage: String?
    var secondsToResend = 0

    init(challenge: LoginChallenge) {
        self.challenge = challenge
    }

    var canVerify: Bool { code.count == 6 && !isVerifying }

    @MainActor
    func send(_ channel: LoginCodeChannel, resend: Bool = false) async {
        errorMessage = nil
        if resend { isResending = true } else { sendingChannel = channel.canal }
        defer {
            isResending = false
            sendingChannel = nil
        }
        do {
            let r = try await SessionStore.shared.sendLoginCode(challenge: challenge.challenge, channel: channel.canal)
            sent = r
            code = ""
            secondsToResend = r.reenviarEm
        } catch is CancellationError {
            // troca de tela — silencioso
        } catch let error as APIError {
            errorMessage = error.message
        } catch {
            errorMessage = "Não foi possível conectar. Verifique sua internet e tente de novo."
        }
    }

    @MainActor
    func verify() async {
        guard canVerify else { return }
        errorMessage = nil
        isVerifying = true
        defer { isVerifying = false }
        do {
            try await SessionStore.shared.verifyLoginCode(challenge: challenge.challenge, code: code)
        } catch is CancellationError {
            // troca de tela — silencioso
        } catch let error as APIError {
            errorMessage = error.message
            code = ""
        } catch {
            errorMessage = "Não foi possível conectar. Verifique sua internet e tente de novo."
        }
    }

    func chooseAnotherChannel() {
        sent = nil
        code = ""
        errorMessage = nil
    }
}

struct AuthLoginCodeView: View {
    @Binding var path: [AuthRoute]
    @State private var model: AuthLoginCodeModel
    @FocusState private var codeFocused: Bool

    init(challenge: LoginChallenge, path: Binding<[AuthRoute]>) {
        _path = path
        _model = State(initialValue: AuthLoginCodeModel(challenge: challenge))
    }

    var body: some View {
        ZStack {
            AuthBackground()
            ScrollView {
                VStack(spacing: 18) {
                    Circle()
                        .fill(Theme.primarySoft)
                        .frame(width: 88, height: 88)
                        .overlay(
                            Image(systemName: "lock.shield")
                                .font(.system(size: 34))
                                .foregroundStyle(Theme.primary)
                        )
                        .padding(.top, 40)

                    Text("Confirme que é você")
                        .font(Theme.serifTitle(28))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)

                    if let sent = model.sent {
                        codeStep(sent)
                    } else {
                        channelStep
                    }

                    if let error = model.errorMessage {
                        AuthErrorBanner(message: error)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 32)
                .frame(maxWidth: 480)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationBarTitleDisplayMode(.inline)
        .task(id: model.sent?.destino) {
            // Contagem do "Reenviar código".
            while model.secondsToResend > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                model.secondsToResend -= 1
            }
        }
    }

    // Etapa 1 — onde receber o código

    private var channelStep: some View {
        VStack(spacing: 12) {
            Text("Você está entrando de um local novo. Escolha onde receber o código de 6 dígitos.")
                .font(Theme.body(15))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
                .padding(.bottom, 6)

            ForEach(model.challenge.canais) { channel in
                Button {
                    Haptics.tap()
                    Task { await model.send(channel) }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: channel.isWhatsapp ? "message.fill" : "envelope.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(channel.isWhatsapp ? Color(hex: 0x1F9E4F) : Theme.primary)
                            .frame(width: 42, height: 42)
                            .background(
                                (channel.isWhatsapp ? Color(hex: 0xE3F5EA) : Theme.primarySoft),
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(channel.isWhatsapp ? "WhatsApp" : "E-mail")
                                .font(Theme.body(15, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text(channel.destino)
                                .font(Theme.body(13))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        if model.sendingChannel == channel.canal {
                            ProgressView().controlSize(.small).tint(Theme.primary)
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary.opacity(0.6))
                        }
                    }
                    .padding(14)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border, lineWidth: 1))
                    .animation(.easeInOut(duration: 0.15), value: model.sendingChannel)
                }
                .buttonStyle(.pressable)
                .disabled(model.sendingChannel != nil)
                .accessibilityIdentifier(channel.isWhatsapp ? "loginCodeWhatsapp" : "loginCodeEmail")
            }
        }
    }

    // Etapa 2 — digitar o código

    private func codeStep(_ sent: LoginCodeSent) -> some View {
        VStack(spacing: 16) {
            Text("Enviamos um código de 6 dígitos para \(sent.canal == "WHATSAPP" ? "o WhatsApp" : "o e-mail") \(sent.destino).")
                .font(Theme.body(15))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            TextField("000000", text: $model.code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($codeFocused)
                .multilineTextAlignment(.center)
                .font(Theme.body(28, weight: .semibold).monospacedDigit())
                .tracking(10)
                .foregroundStyle(Theme.textPrimary)
                .padding(.vertical, 16)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 1))
                .accessibilityIdentifier("loginCodeField")
                .onChange(of: model.code) { _, novo in
                    let digitos = String(novo.filter(\.isNumber).prefix(6))
                    if digitos != novo { model.code = digitos }
                    // Colou ou o iOS preencheu o código: entra direto.
                    if digitos.count == 6, !model.isVerifying {
                        Task { await model.verify() }
                    }
                }
                .onAppear { codeFocused = true }

            PrimaryButton(
                title: "Entrar",
                icon: "arrow.right",
                isLoading: model.isVerifying,
                isEnabled: model.canVerify
            ) {
                Task { await model.verify() }
            }

            Button {
                Haptics.tap()
                if let channel = model.challenge.canais.first(where: { $0.canal == sent.canal }) {
                    Task { await model.send(channel, resend: true) }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(model.secondsToResend > 0 ? "Reenviar código em \(model.secondsToResend) s" : "Reenviar código")
                    if model.isResending {
                        ProgressView().controlSize(.small).tint(Theme.primary)
                    }
                }
                .font(Theme.body(14, weight: .semibold))
                .foregroundStyle(model.secondsToResend > 0 ? Theme.textSecondary : Theme.primary)
                .animation(.easeInOut(duration: 0.15), value: model.isResending)
            }
            .buttonStyle(.pressable)
            .disabled(model.secondsToResend > 0 || model.isResending)

            if model.challenge.canais.count > 1 {
                Button {
                    Haptics.tap()
                    model.chooseAnotherChannel()
                } label: {
                    Text("Receber de outro jeito")
                        .font(Theme.body(14, weight: .medium))
                        .foregroundStyle(Color(hex: 0x46656F))
                }
                .buttonStyle(.pressable)
            }

            Button {
                path.removeAll()
            } label: {
                Text("Voltar ao login")
                    .font(Theme.body(14, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.top, 2)
        }
    }
}
