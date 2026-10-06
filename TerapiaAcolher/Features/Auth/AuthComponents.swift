import SwiftUI

// Peças visuais compartilhadas do fluxo de autenticação (fiel ao print do MVP).

/// Fundo em degradê suave: lavanda → creme → verde-sálvia.
struct AuthBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(hex: 0xEDE8F1),
                Color(hex: 0xF6F1E9),
                Color(hex: 0xFAF8F4),
                Color(hex: 0xDFEDE4),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

/// Logo do Acolher Gestão (a flor colorida). Até 2026-10-06 era um anel
/// segmentado desenhado em código, que não era a marca de verdade.
struct AuthLogoView: View {
    var size: CGFloat = 118

    var body: some View {
        Image("LogoAcolherGestao")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel("Acolher Gestão")
    }
}

/// Campo com label pequeno em caixa alta (E-MAIL, SENHA...), como no print.
struct AuthField: View {
    let label: String
    @Binding var text: String
    var placeholder = ""
    var isSecure = false
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType? = nil
    var autocapitalize = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(Theme.body(11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .tracking(1.4)
            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboard)
                        .textInputAutocapitalization(autocapitalize ? .words : .never)
                        .autocorrectionDisabled()
                }
            }
            .textContentType(contentType)
            .font(Theme.body(16))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Theme.border, lineWidth: 1)
            )
        }
    }
}

/// Banner de erro inline (mensagens PT-BR do backend).
struct AuthErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Theme.danger)
            Text(message)
                .font(Theme.body(13, weight: .medium))
                .foregroundStyle(Theme.danger)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Theme.dangerSoft)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// Banner de sucesso/informação suave.
struct AuthInfoBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.success)
            Text(message)
                .font(Theme.body(13, weight: .medium))
                .foregroundStyle(Theme.success)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Theme.successSoft)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
