import SwiftUI

/// Máscara de valor em reais por centavos (2026-10-06, igual ao web —
/// `mascaraDinheiro` em web-app/lib/formato.ts): só dígitos, até 11, e o
/// número é lido como centavos. Digitar 1-0-0 mostra "1,00"; apagar tira o
/// último dígito. O texto sai no formato "1.234,56", que os parsers das telas
/// (FinFormat.parseAmount e os locais) já entendem.
enum MascaraDinheiro {
    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    static func aplicar(_ bruto: String) -> String {
        let digitos = String(bruto.filter(\.isNumber).prefix(11))
        guard !digitos.isEmpty, let centavos = Double(digitos) else { return "" }
        return formatter.string(from: NSNumber(value: centavos / 100)) ?? ""
    }
}

private struct MascaraDinheiroModifier: ViewModifier {
    @Binding var texto: String

    func body(content: Content) -> some View {
        content
            .keyboardType(.numberPad)
            .onChange(of: texto) { _, novo in
                let mascarado = MascaraDinheiro.aplicar(novo)
                if mascarado != novo { texto = mascarado }
            }
    }
}

extension View {
    /// Aplica a máscara de centavos ao `TextField` que edita `texto`.
    func mascaraDinheiro(_ texto: Binding<String>) -> some View {
        modifier(MascaraDinheiroModifier(texto: texto))
    }
}

/// Campo de valor em reais: "R$" fixo na frente e a máscara de centavos.
struct CampoDinheiro: View {
    var placeholder = "0,00"
    @Binding var texto: String
    var fonte: Font = Theme.money(17)
    var alinhamento: TextAlignment = .leading

    var body: some View {
        HStack(spacing: 6) {
            if alinhamento == .trailing { Spacer(minLength: 0) }
            Text("R$")
                .font(fonte)
                .foregroundStyle(Theme.textSecondary)
            TextField(placeholder, text: $texto)
                .font(fonte)
                .multilineTextAlignment(alinhamento)
                .mascaraDinheiro($texto)
        }
    }
}
