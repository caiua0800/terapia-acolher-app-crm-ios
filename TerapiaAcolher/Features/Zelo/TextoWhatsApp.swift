import SwiftUI

/// Formatação do WhatsApp (*negrito*, _itálico_, ~tachado~) virando texto
/// estilizado. Não usa o Markdown do SwiftUI: lá `*` é itálico, e a prévia do
/// bom dia vem no padrão do WhatsApp, que é por onde a mensagem vai chegar.
enum TextoWhatsApp {
    private static let padrao = try! NSRegularExpression(
        pattern: #"([*_~])(\S(?:[^\n]*?\S)?)\1"#
    )

    static func formatar(_ texto: String) -> AttributedString {
        var saida = AttributedString()
        let ns = texto as NSString
        var cursor = 0
        for m in padrao.matches(in: texto, range: NSRange(location: 0, length: ns.length)) {
            if m.range.location > cursor {
                saida += AttributedString(ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor)))
            }
            var trecho = AttributedString(ns.substring(with: m.range(at: 2)))
            switch ns.substring(with: m.range(at: 1)) {
            case "*": trecho.inlinePresentationIntent = .stronglyEmphasized
            case "_": trecho.inlinePresentationIntent = .emphasized
            default: trecho.strikethroughStyle = .single
            }
            saida += trecho
            cursor = m.range.location + m.range.length
        }
        if cursor < ns.length {
            saida += AttributedString(ns.substring(from: cursor))
        }
        return saida
    }
}
