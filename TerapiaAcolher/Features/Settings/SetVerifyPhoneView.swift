import Observation
import SwiftUI

// MARK: - Verificação do WhatsApp por código

@Observable
final class VerifyPhoneViewModel {
    /// Número em máscara, editável antes do envio.
    var whatsapp = ""
    var code = ""
    var etapa: Etapa = .numero
    var isSending = false
    var isVerifying = false
    var errorMessage: String?
    var destinoMascarado = ""
    /// Segundos que faltam para poder reenviar.
    var reenvioEm = 0

    enum Etapa { case numero, codigo, pronto }

    var phoneCheck: PhoneRules.Result { PhoneRules.validate(whatsapp) }
    var podeEnviar: Bool { phoneCheck.isValid && !isSending }
    var podeVerificar: Bool { code.count == 6 && !isVerifying }

    private struct SendResponse: Decodable {
        let message: String
        let whatsappMasked: String
        let resendInSeconds: Int
    }

    @MainActor
    func enviarCodigo() async {
        struct Body: Encodable { let whatsapp: String? }
        errorMessage = nil
        isSending = true
        defer { isSending = false }
        do {
            let resposta: SendResponse = try await APIClient.shared.post(
                "auth/phone/send-code",
                body: Body(whatsapp: phoneCheck.payload)
            )
            destinoMascarado = resposta.whatsappMasked
            reenvioEm = resposta.resendInSeconds
            etapa = .codigo
            iniciarContagem()
        } catch let error as APIError {
            errorMessage = error.message
        } catch {
            errorMessage = "Não foi possível enviar o código agora."
        }
    }

    @MainActor
    func verificar() async {
        struct Body: Encodable { let code: String }
        errorMessage = nil
        isVerifying = true
        defer { isVerifying = false }
        do {
            let _: MessageResponse = try await APIClient.shared.post(
                "auth/phone/verify",
                body: Body(code: code)
            )
            etapa = .pronto
            // Recarrega as duas fontes: o perfil no menu e a lista de
            // pendências que alimenta o aviso do Início.
            await SessionStore.shared.reloadProfile()
            await ProfileStatusStore.shared.refresh()
        } catch let error as APIError {
            errorMessage = error.message
            // Código errado limpa o campo: reaproveitar os dígitos antigos só
            // gera uma segunda tentativa idêntica e queima o limite.
            code = ""
        } catch {
            errorMessage = "Não foi possível verificar o código agora."
        }
    }

    /// Contagem regressiva do reenvio. Roda enquanto a tela estiver aberta.
    @MainActor
    private func iniciarContagem() {
        Task {
            while reenvioEm > 0 {
                try? await Task.sleep(for: .seconds(1))
                reenvioEm -= 1
            }
        }
    }
}

struct SetVerifyPhoneView: View {
    /// Número já cadastrado, se houver — a tela abre preenchida.
    let numeroAtual: String?
    var onVerified: () -> Void = {}

    @State private var model = VerifyPhoneViewModel()
    @Environment(\.dismiss) private var dismiss
    @FocusState private var codeFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        cabecalho
                        switch model.etapa {
                        case .numero: passoNumero
                        case .codigo: passoCodigo
                        case .pronto: passoPronto
                        }
                        if let erro = model.errorMessage {
                            Text(erro)
                                .font(Theme.body(13))
                                .foregroundStyle(Theme.danger)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                        }
                    }
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.vertical, 20)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .setToolbarTitle("Verificar WhatsApp")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fechar") { dismiss() }
                        .font(Theme.body(16))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .onAppear {
                if model.whatsapp.isEmpty, let numeroAtual, !numeroAtual.isEmpty {
                    model.whatsapp = PatientMask.whatsapp(numeroAtual)
                }
            }
        }
    }

    private var cabecalho: some View {
        VStack(spacing: 10) {
            Image(systemName: model.etapa == .pronto ? "checkmark.seal.fill" : "shield.lefthalf.filled")
                .font(.system(size: 40))
                .foregroundStyle(model.etapa == .pronto ? Theme.success : Theme.primary)
            Text(model.etapa == .pronto ? "Número confirmado" : "Confirme seu WhatsApp")
                .font(Theme.serifTitle(22))
                .foregroundStyle(Theme.textPrimary)
            Text(subtitulo)
                .font(Theme.body(14))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 4)
    }

    private var subtitulo: String {
        switch model.etapa {
        case .numero:
            "É por ele que você recebe aviso de cobrança paga e lembrete de sessão."
        case .codigo:
            "Enviamos um código de 6 dígitos para \(model.destinoMascarado)."
        case .pronto:
            "Tudo certo. Seus avisos vão chegar por aqui."
        }
    }

    private var passoNumero: some View {
        VStack(spacing: 14) {
            ThemeCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SEU WHATSAPP")
                        .font(Theme.body(11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .tracking(0.8)
                    TextField("+55 (11) 91234-5678", text: $model.whatsapp)
                        .font(Theme.body(17))
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .onChange(of: model.whatsapp) { _, novo in
                            let m = PatientMask.whatsapp(novo)
                            if m != novo { model.whatsapp = m }
                        }
                    if let erro = model.whatsapp.isEmpty ? nil : model.phoneCheck.error {
                        Text(erro)
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.danger)
                    }
                }
            }
            PrimaryButton(
                title: "Enviar código",
                icon: "paperplane",
                isLoading: model.isSending,
                isEnabled: model.podeEnviar
            ) {
                Task { await model.enviarCodigo() }
            }
        }
    }

    private var passoCodigo: some View {
        VStack(spacing: 14) {
            ThemeCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("CÓDIGO DE 6 DÍGITOS")
                        .font(Theme.body(11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .tracking(0.8)
                    TextField("000000", text: $model.code)
                        .font(Theme.body(28, weight: .semibold))
                        .kerning(8)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .focused($codeFocused)
                        .onChange(of: model.code) { _, novo in
                            let limpo = String(novo.filter(\.isNumber).prefix(6))
                            if limpo != novo { model.code = limpo }
                        }
                }
            }
            PrimaryButton(
                title: "Confirmar",
                icon: "checkmark",
                isLoading: model.isVerifying,
                isEnabled: model.podeVerificar
            ) {
                Task { await model.verificar() }
            }

            HStack(spacing: 16) {
                Button("Trocar número") {
                    model.etapa = .numero
                    model.code = ""
                    model.errorMessage = nil
                }
                .font(Theme.body(14))
                .foregroundStyle(Theme.textSecondary)

                Spacer()

                // A espera vira contagem visível: sem ela o terapeuta toca em
                // "reenviar" e leva um erro que parece defeito.
                Button(model.reenvioEm > 0 ? "Reenviar em \(model.reenvioEm)s" : "Reenviar código") {
                    Task { await model.enviarCodigo() }
                }
                .font(Theme.body(14, weight: .semibold))
                .foregroundStyle(model.reenvioEm > 0 ? Theme.textSecondary : Theme.primary)
                .disabled(model.reenvioEm > 0 || model.isSending)
            }
            .padding(.horizontal, 4)
        }
        .onAppear { codeFocused = true }
    }

    private var passoPronto: some View {
        PrimaryButton(title: "Concluir", icon: "checkmark") {
            onVerified()
            dismiss()
        }
    }
}
