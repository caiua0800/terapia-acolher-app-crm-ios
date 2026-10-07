import Foundation

/// Arquivos baixados para abrir/compartilhar (comprovantes, extratos,
/// documentos, mídia do suporte) — auditoria de segurança, 2026-10-07.
///
/// Ficam todos numa pasta só dentro do temporário do app, gravados com
/// `.completeFileProtection` (cifrados enquanto o aparelho está bloqueado), e
/// a pasta inteira é apagada na abertura do app e ao sair da conta: comprovante
/// ou anexo de paciente não sobra no aparelho.
enum ArquivosTemporarios {
    private static var raiz: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("acolher-arquivos", isDirectory: true)
    }

    /// Pasta nova (e exclusiva) para um arquivo, preservando o nome sugerido.
    static func novaPasta(_ prefixo: String) throws -> URL {
        let pasta = raiz.appendingPathComponent("\(prefixo)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: pasta,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        return pasta
    }

    /// Grava protegido e devolve a URL.
    @discardableResult
    static func gravar(_ dados: Data, nome: String, prefixo: String) throws -> URL {
        let seguro = nome.replacingOccurrences(of: "/", with: "-")
        let url = try novaPasta(prefixo).appendingPathComponent(seguro.isEmpty ? "arquivo" : seguro)
        try dados.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    /// Apaga tudo (abertura do app e saída da conta).
    static func limparTudo() {
        try? FileManager.default.removeItem(at: raiz)
    }
}
