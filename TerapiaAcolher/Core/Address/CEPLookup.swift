import Foundation

/// Busca de endereço pelo CEP (ViaCEP, com a BrasilAPI de reserva).
///
/// Só o CEP sai do aparelho — nada que identifique o terapeuta. Falha de
/// rede ou CEP inexistente devolve nil: o formulário continua manual.
enum CEPLookup {
    struct Endereco: Equatable {
        let rua: String
        let bairro: String
        let cidade: String
        let uf: String
    }

    static func buscar(_ cep: String) async -> Endereco? {
        let digitos = cep.filter(\.isNumber)
        guard digitos.count == 8 else { return nil }
        if let e = await viaCep(digitos) { return e }
        return await brasilApi(digitos)
    }

    private static func json(_ url: String) async -> [String: Any]? {
        guard let u = URL(string: url) else { return nil }
        var req = URLRequest(url: u, timeoutInterval: 6)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func viaCep(_ cep: String) async -> Endereco? {
        guard let d = await json("https://viacep.com.br/ws/\(cep)/json/"), d["erro"] == nil,
              let cidade = d["localidade"] as? String, let uf = d["uf"] as? String else { return nil }
        return Endereco(
            rua: d["logradouro"] as? String ?? "",
            bairro: d["bairro"] as? String ?? "",
            cidade: cidade,
            uf: uf
        )
    }

    private static func brasilApi(_ cep: String) async -> Endereco? {
        guard let d = await json("https://brasilapi.com.br/api/cep/v1/\(cep)"),
              let cidade = d["city"] as? String, let uf = d["state"] as? String else { return nil }
        return Endereco(
            rua: d["street"] as? String ?? "",
            bairro: d["neighborhood"] as? String ?? "",
            cidade: cidade,
            uf: uf
        )
    }
}
