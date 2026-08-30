import Observation
import SwiftUI

@Observable
@MainActor
final class SetDeleteAccountViewModel {
    var password = ""
    var confirmacaoDigitada = ""
    var isDeleting = false
    var errorMessage: String?
    var showError = false

    /// Palavra que o terapeuta digita para confirmar.
    ///
    /// A Apple permite passos de confirmação para evitar exclusão acidental, e
    /// aqui isso não é burocracia: uma conta apagada leva junto o prontuário de
    /// todos os pacientes, e não há de onde voltar.
    static let palavraDeConfirmacao = "EXCLUIR"

    var podeExcluir: Bool {
        !password.isEmpty
            && confirmacaoDigitada.trimmingCharacters(in: .whitespaces).uppercased()
                == Self.palavraDeConfirmacao
            && !isDeleting
    }

    func excluir() async -> Bool {
        isDeleting = true
        defer { isDeleting = false }
        do {
            struct Corpo: Encodable { let password: String }
            struct Resposta: Decodable { let deleted: Bool? }
            let _: Resposta = try await APIClient.shared.delete(
                "auth/me",
                body: Corpo(password: password)
            )
            Haptics.success()
            return true
        } catch let error as APIError {
            present(error.message)
        } catch {
            present("Não foi possível excluir a conta. Verifique sua conexão.")
        }
        return false
    }

    private func present(_ mensagem: String) {
        errorMessage = mensagem
        showError = true
    }
}

/// Config · Conta · Excluir conta.
///
/// Exigência da App Store (5.1.1(v)): app que cria conta precisa oferecer a
/// exclusão DENTRO do app — desativar não vale, e mandar o usuário ligar ou
/// mandar e-mail também não. É também o direito de eliminação da LGPD
/// (art. 18, VI), que aqui pesa mais que o normal: o que some são prontuários
/// e anamneses, dado sensível de saúde.
struct SetDeleteAccountView: View {
    @State private var model = SetDeleteAccountViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    aviso
                    oQueSome
                    formulario
                    botao
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
        }
        .setToolbarTitle("Excluir minha conta")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Ops", isPresented: $model.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "Algo deu errado.")
        }
    }

    private var aviso: some View {
        ThemeCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.danger)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Isto não tem volta")
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Sua conta e todos os dados dos seus pacientes são apagados em definitivo. Não guardamos cópia e não conseguimos restaurar depois.")
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var oQueSome: some View {
        ThemeCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("O QUE É APAGADO")
                    .font(Theme.body(10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.textSecondary)
                ForEach(Self.itens, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 4))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.top, 7)
                        Text(item)
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text("Se você emite recibos ou notas, guarde o que precisar antes de continuar.")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.warning)
                    .padding(.top, 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private static let itens = [
        "Seus pacientes, com prontuários, anamneses e anotações de sessão",
        "Sua agenda e o histórico de sessões",
        "Seu financeiro: cobranças, entradas e saídas",
        "Documentos gerados, anexos e fotos",
        "Seu perfil profissional e sua assinatura",
    ]

    private var formulario: some View {
        ThemeCard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("SUA SENHA")
                        .font(Theme.body(10, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(Theme.textSecondary)
                    SecureField("Digite sua senha", text: $model.password)
                        .font(Theme.body(15))
                        .textContentType(.password)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(Theme.background, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Theme.border, lineWidth: 1)
                        )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("DIGITE \(SetDeleteAccountViewModel.palavraDeConfirmacao)")
                        .font(Theme.body(10, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(Theme.textSecondary)
                    TextField(
                        SetDeleteAccountViewModel.palavraDeConfirmacao,
                        text: $model.confirmacaoDigitada
                    )
                    .font(Theme.body(15, weight: .semibold))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Theme.border, lineWidth: 1)
                    )
                }
            }
        }
    }

    private var botao: some View {
        Button {
            Task {
                if await model.excluir() {
                    // Sai da sessão: o token ainda existe no aparelho, mas a
                    // conta do outro lado já não.
                    await SessionStore.shared.logout()
                    dismiss()
                }
            }
        } label: {
            HStack(spacing: 8) {
                if model.isDeleting {
                    ProgressView().controlSize(.small).tint(.white)
                }
                Text(model.isDeleting ? "Excluindo…" : "Excluir minha conta")
                    .font(Theme.body(16, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(model.podeExcluir ? Theme.danger : Theme.danger.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.pressable)
        .disabled(!model.podeExcluir)
    }
}
