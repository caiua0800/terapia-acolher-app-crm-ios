import SwiftUI

/// Configurações → Conta → "Entrar com Face ID" (ou Touch ID).
struct SetBiometricRow: View {
    @State private var ligada = BiometricVault.isEnabled
    @State private var trabalhando = false
    @State private var aviso: String?

    private var nome: String? { BiometricVault.biometryName }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: nome == "Touch ID" ? "touchid" : "faceid")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .frame(width: 34, height: 34)
                    .background(Theme.primary.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Entrar com \(nome ?? "biometria")")
                        .font(Theme.body(15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text(nome == nil
                         ? BiometricVault.motivoIndisponivel
                         : ligada ? "Ligado: o app abre com o seu \(nome!)." : "Abra o app sem digitar a senha.")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(3)
                }
                Spacer()
                if trabalhando {
                    ProgressView().controlSize(.small)
                } else {
                    Toggle("", isOn: Binding(get: { ligada }, set: { mudar($0) }))
                        .labelsHidden()
                        .tint(Theme.primary)
                        .disabled(nome == nil)
                        .accessibilityIdentifier("biometricToggle")
                }
            }
            if let aviso {
                Text(aviso)
                    .font(Theme.body(12))
                    .foregroundStyle(aviso.hasPrefix("Pronto") ? Theme.success : Theme.danger)
                    .padding(.leading, 46)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func mudar(_ novo: Bool) {
        Haptics.tap()
        aviso = nil
        if !novo {
            SessionStore.shared.desligarBiometria()
            ligada = false
            return
        }
        trabalhando = true
        Task { @MainActor in
            defer { trabalhando = false }
            do {
                try await SessionStore.shared.ligarBiometria()
                ligada = true
                aviso = "Pronto. Na próxima vez, o app abre com o seu \(nome ?? "biometria")."
            } catch BiometricVault.Falha.cancelada {
                ligada = false
            } catch BiometricVault.Falha.indisponivel(let msg) {
                ligada = false
                aviso = msg
            } catch let e as APIError {
                ligada = false
                aviso = e.message
            } catch {
                ligada = false
                aviso = "Não foi possível ligar a biometria."
            }
        }
    }
}
