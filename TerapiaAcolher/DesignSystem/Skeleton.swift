import SwiftUI

/// Bloco cinza com brilho passando — o desenho da tela antes do dado chegar.
///
/// Por que isto e não mais um `ProgressView`: um spinner no meio do vazio não
/// diz nada sobre o que vem, e a tela dá um solavanco quando o conteúdo entra
/// de uma vez. O esqueleto já ocupa o lugar certo, então a chegada do dado é
/// uma troca de conteúdo, não um salto de layout — a mesma espera parece bem
/// mais curta.
struct SkeletonBlock: View {
    var width: CGFloat? = nil
    var height: CGFloat = 14
    var cornerRadius: CGFloat = 6

    @State private var brilhando = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Theme.border.opacity(0.55))
            .frame(width: width, height: height)
            .overlay {
                GeometryReader { geo in
                    LinearGradient(
                        colors: [
                            .white.opacity(0),
                            .white.opacity(0.55),
                            .white.opacity(0),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: brilhando ? geo.size.width : -geo.size.width * 0.6)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    brilhando = true
                }
            }
            .accessibilityHidden(true)
    }
}

/// Linha de lista em espera: avatar redondo + duas linhas de texto.
/// Espelha o `PatientRow`/`SessionRow` para o layout não pular na troca.
struct SkeletonRow: View {
    var avatarSize: CGFloat = 46

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Theme.border.opacity(0.55))
                .frame(width: avatarSize, height: avatarSize)
            VStack(alignment: .leading, spacing: 7) {
                SkeletonBlock(width: 150, height: 14)
                SkeletonBlock(width: 96, height: 11)
            }
            Spacer(minLength: 8)
        }
        .padding(.vertical, 10)
    }
}

/// Cartão em espera, no formato dos `ThemeCard` do app.
struct SkeletonCard: View {
    var linhas: Int = 3

    var body: some View {
        ThemeCard {
            VStack(alignment: .leading, spacing: 10) {
                SkeletonBlock(width: 120, height: 12)
                ForEach(0..<max(1, linhas), id: \.self) { i in
                    SkeletonBlock(
                        width: i == linhas - 1 ? 180 : nil,
                        height: 14
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Lista de linhas em espera, com o mesmo divisor das listas reais.
struct SkeletonList: View {
    var linhas: Int = 6
    var avatarSize: CGFloat = 46

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<linhas, id: \.self) { i in
                SkeletonRow(avatarSize: avatarSize)
                if i < linhas - 1 {
                    Divider().overlay(Theme.border)
                }
            }
        }
        .accessibilityLabel("Carregando")
    }
}
