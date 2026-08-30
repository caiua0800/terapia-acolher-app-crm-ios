import SwiftUI
import UIKit

/// Design system do Terapia Acolher — extraído do MVP visual.
/// Referência: https://terapia-acolher-mvp-design.vercel.app/
/// Regra do projeto: fidelidade total ao design; não simplificar.
enum Theme {
    // MARK: - Cores

    /// Fundo geral (creme/off-white acolhedor)
    static let background = Color(hex: 0xFAF8F4)
    /// Superfície de cards
    static let surface = Color.white
    /// Verde da marca — botões, destaques, FAB.
    ///
    /// Amostrado da logo da Terapia Acolher (os verdes das pétalas ficam em
    /// torno de #609060, matiz ~110°) e escurecido até passar no contraste.
    /// O sálvia anterior (#6FA88B) tinha só **2,75:1** com branco: o texto do
    /// botão principal estava abaixo do mínimo da WCAG em todo o app. Este
    /// tem 4,78:1.
    static let primary = Color(hex: 0x4F7D53)
    /// Verde da marca, bem claro (chip ativo, fundos de destaque).
    static let primarySoft = Color(hex: 0xE3EFE2)
    /// Grafite escuro (menu lateral, card de saldo)
    static let ink = Color(hex: 0x232B2F)
    /// Texto principal
    static let textPrimary = Color(hex: 0x2D3436)
    /// Texto secundário
    static let textSecondary = Color(hex: 0x8A8F98)
    /// Bordas suaves
    static let border = Color(hex: 0xEDE7DC)
    /// Negativo (saídas, atrasado, excluir)
    static let danger = Color(hex: 0xD9534F)
    static let dangerSoft = Color(hex: 0xFBE9E8)
    /// Positivo (entradas, pago). Puxado para o azulado de propósito: com o
    /// primário agora sendo verde folha, um sucesso verde-igual faria "pago" e
    /// "botão de ação" se confundirem na mesma tela.
    static let success = Color(hex: 0x3E8E6B)
    static let successSoft = Color(hex: 0xE2F1EA)
    /// Alerta (pendente)
    static let warning = Color(hex: 0xC99B3F)
    static let warningSoft = Color(hex: 0xF9F0DC)

    /// Cores de grupos de pacientes (mesmos hex do seed do backend)
    static let groupColors: [String: Color] = [
        "#8FBCA6": Color(hex: 0x8FBCA6), // Adultos
        "#B9A6D9": Color(hex: 0xB9A6D9), // Adolescentes
        "#E8B98A": Color(hex: 0xE8B98A), // Crianças
        "#E9A3B4": Color(hex: 0xE9A3B4), // Casal
        "#7FA8C9": Color(hex: 0x7FA8C9), // Idosos
    ]

    static func groupColor(_ hexString: String?) -> Color {
        guard let hexString, let value = UInt32(hexString.dropFirst(), radix: 16) else {
            return primary
        }
        return Color(hex: value)
    }

    // MARK: - Tipografia
    // Títulos: serifada elegante (New York) · Corpo: SF · Números financeiros: mono

    /// Teto da escala do Dynamic Type.
    ///
    /// As telas do MVP têm cartões densos e tamanhos cravados: deixar a fonte
    /// ir até 3x (AX5) quebraria layout em quase toda tela. 1.35 cobre
    /// "Grande" e "Muito grande" — que é onde está o terapeuta de 50+, o caso
    /// real — sem estourar cartão nenhum. Acessibilidade que funciona é melhor
    /// que acessibilidade que só existe no papel e destrói a tela.
    private static let tetoDeEscala: CGFloat = 1.35

    /// Converte um tamanho fixo do design em tamanho que acompanha o ajuste de
    /// fonte do iPhone. Antes tudo era `.system(size:)` cravado: quem aumentava
    /// a fonte no aparelho não via diferença nenhuma aqui dentro.
    private static func escalado(
        _ size: CGFloat,
        relativeTo style: UIFont.TextStyle = .body
    ) -> CGFloat {
        let escalado = UIFontMetrics(forTextStyle: style).scaledValue(for: size)
        return min(escalado, size * tetoDeEscala)
    }

    static func serifTitle(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: escalado(size, relativeTo: .title2), weight: weight, design: .serif)
    }

    static func body(_ size: CGFloat = 15, weight: Font.Weight = .regular) -> Font {
        .system(size: escalado(size), weight: weight)
    }

    static func money(_ size: CGFloat = 17, weight: Font.Weight = .semibold) -> Font {
        .system(size: escalado(size), weight: weight, design: .monospaced)
    }

    /// Valor em destaque (receita da dashboard). A monoespaçada de `money`
    /// alinha bem em tabela, mas em corpo grande fica datilografada e larga —
    /// esta usa a arredondada com dígitos de largura fixa: mesmo alinhamento,
    /// aparência de produto.
    static func moneyDisplay(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: escalado(size, relativeTo: .title1), weight: weight, design: .rounded)
    }

    // MARK: - Métricas de layout

    static let cornerRadius: CGFloat = 16
    static let cardPadding: CGFloat = 16
    static let screenPadding: CGFloat = 20
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

// MARK: - Formatadores compartilhados

enum Formatters {
    static let currency: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter
    }()

    /// Sem centavos quando o valor é redondo — "R$ 97" lê melhor que
    /// "R$ 97,00" num preço de tabela. Com centavos, mantém.
    static func brlCompact(_ value: Double) -> String {
        value == value.rounded()
            ? "R$ \(Int(value))"
            : brl(value)
    }

    static func brl(_ value: Double) -> String {
        currency.string(from: NSNumber(value: value)) ?? "R$ \(value)"
    }
}
