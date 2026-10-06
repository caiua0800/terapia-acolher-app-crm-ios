import SwiftUI

/// Abertura do app com a biometria ligada: pede o rosto/digital sozinha e
/// sempre oferece "Entrar com senha".
struct BiometricUnlockView: View {
    @Environment(SessionStore.self) private var session
    @State private var entrando = false
    @State private var aviso: String?
    @State private var jaPediu = false

    private var nome: String { BiometricVault.biometryName ?? "biometria" }
    private var icone: String { nome == "Touch ID" ? "touchid" : "faceid" }

    var body: some View {
        ZStack {
            AuthBackground()
            VStack(spacing: 22) {
                Spacer()
                AuthLogoView()
                VStack(spacing: 6) {
                    Text("Acolher Gestão")
                        .font(Theme.serifTitle(28))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Sua conta está protegida pelo \(nome) deste aparelho.")
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)

                Button {
                    Task { await entrar() }
                } label: {
                    HStack(spacing: 10) {
                        if entrando {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: icone).font(.system(size: 20, weight: .semibold))
                        }
                        Text("Entrar com \(nome)")
                    }
                    .font(Theme.body(16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Theme.primary, in: Capsule())
                }
                .buttonStyle(.pressable)
                .disabled(entrando)
                .padding(.horizontal, 32)
                .accessibilityIdentifier("biometricUnlockButton")

                if let aviso {
                    Text(aviso)
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.danger)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Button {
                    Haptics.tap()
                    session.usarSenhaEmVezDaBiometria()
                } label: {
                    Text("Entrar com senha")
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x46656F))
                }
                .accessibilityIdentifier("biometricPasswordButton")
                Spacer()
                Spacer()
            }
        }
        .task {
            // Pede sozinha uma vez ao abrir; depois, só pelo botão.
            guard !jaPediu else { return }
            jaPediu = true
            try? await Task.sleep(for: .milliseconds(350))
            await entrar()
        }
    }

    @MainActor
    private func entrar() async {
        guard !entrando else { return }
        Haptics.tap()
        entrando = true
        aviso = await session.desbloquearComBiometria()
        entrando = false
    }
}
