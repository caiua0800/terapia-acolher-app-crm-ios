import Foundation

/// Validação de telefone espelhando `validateWhatsappPhone` do backend.
///
/// Existe duplicada de propósito: sem ela o terapeuta só descobre que o número
/// está errado depois de enviar o cadastro e receber um 400 — e o erro chega
/// como banner genérico no fim do formulário, longe do campo. Aqui ele vê
/// enquanto digita.
///
/// A regra tem que continuar igual à do servidor. Se uma mudar, muda a outra.
enum PhoneRules {
    /// DDDs que existem no Brasil — lista fechada, igual à do backend.
    private static let dddsValidos: Set<Int> = [
        11, 12, 13, 14, 15, 16, 17, 18, 19,
        21, 22, 24, 27, 28,
        31, 32, 33, 34, 35, 37, 38,
        41, 42, 43, 44, 45, 46, 47, 48, 49,
        51, 53, 54, 55,
        61, 62, 63, 64, 65, 66, 67, 68, 69,
        71, 73, 74, 75, 77, 79,
        81, 82, 83, 84, 85, 86, 87, 88, 89,
        91, 92, 93, 94, 95, 96, 97, 98, 99,
    ]

    struct Result {
        let isValid: Bool
        /// Pronto para a API: dígitos com DDI, sem "+".
        let payload: String?
        /// Mensagem para mostrar embaixo do campo. Nil quando válido.
        let error: String?
    }

    static func validate(_ raw: String) -> Result {
        let texto = raw.trimmingCharacters(in: .whitespaces)
        guard !texto.isEmpty else {
            return Result(isValid: false, payload: nil, error: "Informe seu número de WhatsApp.")
        }

        let digitos = texto.filter(\.isNumber)
        guard !digitos.isEmpty else {
            return Result(isValid: false, payload: nil, error: "Informe um número de telefone válido.")
        }

        // Só é estrangeiro quem declara o DDI com "+". Sem isso, nove dígitos
        // sem DDD passariam como número de fora.
        let declarouDDI = texto.hasPrefix("+")
        if declarouDDI && !digitos.hasPrefix("55") {
            let ok = digitos.count >= 8 && digitos.count <= 15
            return Result(
                isValid: ok,
                payload: ok ? digitos : nil,
                error: ok ? nil : "Número internacional inválido. Informe com o código do país."
            )
        }

        var nacional = digitos
        if digitos.hasPrefix("55") && digitos.count > 11 {
            nacional = String(digitos.dropFirst(2))
        }

        guard nacional.count == 11 else {
            let msg = nacional.count == 10
                ? "Parece um telefone fixo. Informe um celular com WhatsApp."
                : "Número incompleto. Informe DDD + 9 dígitos."
            return Result(isValid: false, payload: nil, error: msg)
        }

        let ddd = Int(nacional.prefix(2)) ?? 0
        guard dddsValidos.contains(ddd) else {
            return Result(isValid: false, payload: nil, error: "DDD \(nacional.prefix(2)) não existe.")
        }

        let semDDD = String(nacional.dropFirst(2))
        guard semDDD.first == "9" else {
            return Result(isValid: false, payload: nil, error: "Celular começa com 9 depois do DDD.")
        }
        guard Set(semDDD).count > 1 else {
            return Result(isValid: false, payload: nil, error: "Número inválido. Confira os dígitos.")
        }

        return Result(isValid: true, payload: "55\(nacional)", error: nil)
    }

    /// `5511987654321` → `+55 (11) 98765-4321`, para exibir.
    static func display(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "—" }
        return PatientMask.whatsapp(raw)
    }
}
