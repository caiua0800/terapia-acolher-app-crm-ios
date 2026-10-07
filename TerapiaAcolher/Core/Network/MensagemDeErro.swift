import Foundation

/// Tradução central de erro para o terapeuta (2026-10-06).
///
/// Nada técnico ou em inglês chega à tela ("Cannot GET /zelo/config",
/// "Internal server error", "The Internet connection appears to be offline",
/// erro de leitura do JSON). As mensagens em português que o backend escreve de
/// propósito ("Esse paciente já tem cobrança em aberto.") passam intactas —
/// elas explicam o que fazer, e trocá-las por uma genérica pioraria a tela.
enum MensagemDeErro {
    static let semConexao = "Sem conexão com a internet. Confira sua rede e tente de novo."
    static let indisponivel = "Esta parte ainda não está disponível na sua versão. Atualize o app ou tente de novo mais tarde."
    static let generica = "Ops! Tivemos um problema ao carregar esta tela. Tente de novo em instantes — se continuar, fale com o nosso suporte."
    static let muitasTentativas = "Muitas tentativas seguidas. Espere um pouco e tente de novo."
    static let sessao = "Sua sessão expirou. Entre de novo para continuar."
    static let semAcesso = "Você não tem acesso a esta parte."
    static let dadosInvalidos = "Não foi possível concluir. Confira os dados e tente de novo."

    /// Mensagem final a partir do status HTTP e do texto que veio do servidor.
    static func amigavel(status: Int, mensagem: String?) -> String {
        let texto = (mensagem ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if status == 0 { return semConexao }
        if ehRotaInexistente(texto) { return indisponivel }
        if !texto.isEmpty, ehNossa(texto) { return texto }
        switch status {
        case 401: return sessao
        case 403: return semAcesso
        case 404: return indisponivel
        case 429: return muitasTentativas
        case 400, 409, 413, 415, 422: return dadosInvalidos
        default: return generica
        }
    }

    /// Para qualquer erro (rede, leitura, API) — quem mostra erro na tela usa isto.
    static func para(_ erro: Error) -> String {
        if let api = erro as? APIError { return api.message }
        if erro is URLError { return semConexao }
        if erro is DecodingError { return generica }
        let ns = erro as NSError
        if ns.domain == NSURLErrorDomain { return semConexao }
        let texto = erro.localizedDescription
        return ehNossa(texto) ? texto : generica
    }

    /// "Cannot GET /x" — a rota não existe no servidor (app novo × backend antigo).
    static func ehRotaInexistente(_ texto: String) -> Bool {
        texto.range(of: #"^Cannot (GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS) "#, options: .regularExpression) != nil
    }

    /// Mensagem escrita por nós, em português (acento ou palavras comuns do PT).
    static func ehNossa(_ texto: String) -> Bool {
        let t = texto.lowercased()
        if t.range(of: "[ãõáéíóúâêôçà]", options: .regularExpression) != nil { return true }
        let palavras = [" de ", " para ", " não ", "não ", " você", " seu ", " sua ", " com ", " uma ",
                        " do ", " da ", " no ", " na ", " em ", "tente", " ou ", " já ", " ao "]
        let comEspacos = " \(t) "
        return palavras.contains { comEspacos.contains($0) }
    }
}
