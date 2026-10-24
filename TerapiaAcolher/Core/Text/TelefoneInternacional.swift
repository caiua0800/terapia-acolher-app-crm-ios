import Foundation

/// Telefone com país (2026-10-23), espelho de `telefone-internacional.tsx`
/// do CRM web. O número fica no campo sem o "+55" fixo; o país (Brasil por
/// padrão) escolhe-se ao lado. Para a API vai "55DDDNÚMERO" no Brasil e
/// "+DDI…" fora — o "+" é o que diz ao backend (`normalizePhone`) que o
/// número é de outro país; sem ele, valida como brasileiro e recusa.
///
/// A lista e as regras têm que continuar iguais às do web. Se uma mudar,
/// muda a outra.
enum TelefoneInternacional {
    struct Pais: Identifiable, Hashable {
        let iso: String
        let ddi: String
        let nome: String
        let bandeira: String
        var id: String { iso }
    }

    static let brasil = "BR"

    /// ISO → DDI, na MESMA ordem do web. Para DDI dividido (1, 7, 44…), o
    /// primeiro país da lista é o padrão: +1 = Estados Unidos, +7 = Rússia.
    private static let ddis: [(String, String)] = [
        ("BR", "55"), ("US", "1"), ("CA", "1"), ("PT", "351"), ("AR", "54"), ("UY", "598"), ("PY", "595"),
        ("CL", "56"), ("BO", "591"), ("PE", "51"), ("CO", "57"), ("VE", "58"), ("EC", "593"), ("MX", "52"),
        ("ES", "34"), ("IT", "39"), ("FR", "33"), ("DE", "49"), ("GB", "44"), ("IE", "353"), ("NL", "31"),
        ("BE", "32"), ("CH", "41"), ("AT", "43"), ("LU", "352"), ("JP", "81"), ("AO", "244"), ("MZ", "258"),
        ("CV", "238"), ("GW", "245"), ("ST", "239"), ("TL", "670"), ("RU", "7"), ("KZ", "7"),
        ("AF", "93"), ("ZA", "27"), ("AL", "355"), ("AD", "376"), ("AI", "1264"), ("AG", "1268"), ("SA", "966"),
        ("DZ", "213"), ("AM", "374"), ("AW", "297"), ("AU", "61"), ("AZ", "994"), ("BS", "1242"), ("BH", "973"),
        ("BD", "880"), ("BB", "1246"), ("BZ", "501"), ("BJ", "229"), ("BM", "1441"), ("BY", "375"), ("BA", "387"),
        ("BW", "267"), ("BN", "673"), ("BG", "359"), ("BF", "226"), ("BI", "257"), ("BT", "975"), ("CM", "237"),
        ("KH", "855"), ("QA", "974"), ("TD", "235"), ("CN", "86"), ("CY", "357"), ("KM", "269"), ("CG", "242"),
        ("CD", "243"), ("KP", "850"), ("KR", "82"), ("CI", "225"), ("CR", "506"), ("HR", "385"), ("CU", "53"),
        ("CW", "599"), ("DK", "45"), ("DJ", "253"), ("DM", "1767"), ("DO", "1809"), ("EG", "20"), ("SV", "503"),
        ("AE", "971"), ("ER", "291"), ("SK", "421"), ("SI", "386"), ("EE", "372"), ("SZ", "268"), ("ET", "251"),
        ("FJ", "679"), ("PH", "63"), ("FI", "358"), ("GA", "241"), ("GM", "220"), ("GH", "233"), ("GE", "995"),
        ("GI", "350"), ("GD", "1473"), ("GR", "30"), ("GL", "299"), ("GP", "590"), ("GU", "1671"), ("GT", "502"),
        ("GY", "592"), ("GF", "594"), ("GN", "224"), ("GQ", "240"), ("HT", "509"), ("HN", "504"), ("HK", "852"),
        ("HU", "36"), ("YE", "967"), ("IN", "91"), ("ID", "62"), ("IQ", "964"), ("IR", "98"), ("IS", "354"),
        ("IL", "972"), ("JM", "1876"), ("JO", "962"), ("KW", "965"), ("KG", "996"), ("LA", "856"), ("LS", "266"),
        ("LV", "371"), ("LB", "961"), ("LR", "231"), ("LY", "218"), ("LI", "423"), ("LT", "370"), ("MO", "853"),
        ("MK", "389"), ("MG", "261"), ("MY", "60"), ("MW", "265"), ("MV", "960"), ("ML", "223"), ("MT", "356"),
        ("MA", "212"), ("MQ", "596"), ("MU", "230"), ("MR", "222"), ("MM", "95"), ("FM", "691"), ("MD", "373"),
        ("MC", "377"), ("MN", "976"), ("ME", "382"), ("NA", "264"), ("NP", "977"), ("NI", "505"), ("NE", "227"),
        ("NG", "234"), ("NO", "47"), ("NC", "687"), ("NZ", "64"), ("OM", "968"), ("PW", "680"), ("PS", "970"),
        ("PA", "507"), ("PG", "675"), ("PK", "92"), ("PF", "689"), ("PL", "48"), ("PR", "1787"), ("KE", "254"),
        ("CF", "236"), ("CZ", "420"), ("RE", "262"), ("RO", "40"), ("RW", "250"), ("WS", "685"), ("SM", "378"),
        ("LC", "1758"), ("KN", "1869"), ("VC", "1784"), ("SN", "221"), ("SL", "232"), ("RS", "381"), ("SC", "248"),
        ("SG", "65"), ("SY", "963"), ("SO", "252"), ("LK", "94"), ("SD", "249"), ("SS", "211"), ("SE", "46"),
        ("SR", "597"), ("TJ", "992"), ("TH", "66"), ("TW", "886"), ("TZ", "255"), ("TG", "228"), ("TO", "676"),
        ("TT", "1868"), ("TN", "216"), ("TM", "993"), ("TR", "90"), ("UA", "380"), ("UG", "256"), ("UZ", "998"),
        ("VU", "678"), ("VA", "379"), ("VN", "84"), ("ZM", "260"), ("ZW", "263"), ("KY", "1345"), ("TC", "1649"),
        ("VG", "1284"), ("VI", "1340"), ("XK", "383"),
    ]

    private static let ptBR = Locale(identifier: "pt_BR")

    /// Brasil primeiro; o resto em ordem alfabética pelo nome em português.
    static let paises: [Pais] = {
        let lista = ddis.map { iso, ddi in
            Pais(
                iso: iso,
                ddi: ddi,
                nome: ptBR.localizedString(forRegionCode: iso) ?? iso,
                bandeira: bandeira(iso)
            )
        }
        let resto = lista.dropFirst().sorted {
            $0.nome.compare($1.nome, options: [.caseInsensitive, .diacriticInsensitive], locale: ptBR) == .orderedAscending
        }
        return [lista[0]] + resto
    }()

    private static let porISO: [String: Pais] = Dictionary(uniqueKeysWithValues: paises.map { ($0.iso, $0) })

    static func pais(_ iso: String) -> Pais { porISO[iso] ?? paises[0] }

    /// "BR" → 🇧🇷 (dois regional indicators).
    private static func bandeira(_ iso: String) -> String {
        var saida = ""
        for escalar in iso.uppercased().unicodeScalars {
            if let ri = Unicode.Scalar(0x1F1E6 + escalar.value - 65) { saida.unicodeScalars.append(ri) }
        }
        return saida
    }

    static func semAcento(_ texto: String) -> String {
        texto.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: ptBR)
    }

    // MARK: Máscara

    /// "(11) 91234-5678" — o celular brasileiro sem o +55.
    static func mascaraBrasil(_ digitos: String) -> String {
        let d = Array(digitos.prefix(11))
        guard !d.isEmpty else { return "" }
        var saida = "("
        for (i, ch) in d.enumerated() {
            if i == 2 { saida += ") " }
            if (d.count > 10 && i == 7) || (d.count <= 10 && d.count > 6 && i == 6) { saida += "-" }
            saida.append(ch)
        }
        return saida
    }

    /// Fora do Brasil: blocos de 3 (o último pode ter 4), até o limite de 15 do E.164.
    private static func mascaraOutro(_ digitos: String, ddi: String) -> String {
        let d = Array(digitos.prefix(max(4, 15 - ddi.count)))
        var blocos: [String] = stride(from: 0, to: d.count, by: 3).map {
            String(d[$0..<min($0 + 3, d.count)])
        }
        // "415 555 267 1" fica "415 555 2671": dígito sozinho no fim vai para o bloco anterior.
        if blocos.count > 1, blocos[blocos.count - 1].count == 1 {
            let ultimo = blocos.removeLast()
            blocos[blocos.count - 1] += ultimo
        }
        return blocos.joined(separator: " ")
    }

    static func mascara(_ iso: String, _ bruto: String) -> String {
        let digitos = bruto.filter(\.isASCIIDigit)
        return iso == brasil ? mascaraBrasil(digitos) : mascaraOutro(digitos, ddi: pais(iso).ddi)
    }

    // MARK: País

    /// DDI mais longo que casa com o começo dos dígitos. No empate (+1, +7)
    /// vale a ordem de `ddis`: Estados Unidos antes do Canadá, Rússia antes
    /// do Cazaquistão.
    static func detectar(_ digitos: String) -> Pais? {
        var melhor: (String, String)?
        for par in ddis where digitos.hasPrefix(par.1) {
            if melhor == nil || par.1.count > melhor!.1.count { melhor = par }
        }
        return melhor.map { pais($0.0) }
    }

    /// O que está gravado ("5511912345678", "14155552671") → país + número mascarado.
    ///
    /// O backend grava o Brasil sempre com 55 e o estrangeiro só em dígitos,
    /// sem "+". Por isso 11 dígitos só é Brasil se for celular válido:
    /// "14155552671" é dos Estados Unidos, não DDD 14.
    static func ler(_ armazenado: String?) -> (pais: String, numero: String) {
        let texto = (armazenado ?? "").trimmingCharacters(in: .whitespaces)
        let digitos = texto.filter(\.isASCIIDigit)
        guard !digitos.isEmpty else { return (brasil, "") }
        if !texto.hasPrefix("+") {
            if digitos.hasPrefix("55"), digitos.count == 12 || digitos.count == 13 {
                return (brasil, mascaraBrasil(String(digitos.dropFirst(2))))
            }
            // Nacional sem DDI: fixo/curto, ou celular brasileiro válido.
            if digitos.count <= 10 || (digitos.count == 11 && PhoneRules.validate(digitos).isValid) {
                return (brasil, mascaraBrasil(digitos))
            }
        }
        guard let achado = detectar(digitos) else { return (brasil, mascaraBrasil(digitos)) }
        return (achado.iso, mascara(achado.iso, String(digitos.dropFirst(achado.ddi.count))))
    }

    // MARK: API

    /// Para a API: Brasil "55DDDNÚMERO"; outro país "+DDINÚMERO". Vazio = nil.
    static func paraSalvar(_ iso: String, _ numero: String) -> String? {
        let digitos = numero.filter(\.isASCIIDigit)
        guard !digitos.isEmpty else { return nil }
        return iso == brasil ? "55\(digitos)" : "+\(pais(iso).ddi)\(digitos)"
    }

    /// WhatsApp obrigatório do terapeuta: a mesma regra do backend.
    /// Brasil é checado a fundo (DDD, celular com 9); fora, 8 a 15 dígitos.
    /// O `payload` do resultado já é o que vai para a API ("55…" ou "+DDI…").
    static func validarWhatsapp(_ iso: String, _ numero: String) -> PhoneRules.Result {
        let digitos = numero.filter(\.isASCIIDigit)
        let entrada = iso == brasil ? digitos : (digitos.isEmpty ? "" : "+\(pais(iso).ddi)\(digitos)")
        let r = PhoneRules.validate(entrada)
        guard r.isValid, let payload = r.payload else { return r }
        return PhoneRules.Result(isValid: true, payload: iso == brasil ? payload : "+\(payload)", error: nil)
    }

    /// Para mostrar o que está gravado: "+55 (11) 91234-5678" / "+351 912 345 678".
    static func formatar(_ armazenado: String?) -> String {
        let (iso, numero) = ler(armazenado)
        guard !numero.isEmpty else { return "" }
        return "+\(pais(iso).ddi) \(numero)"
    }
}

private extension Character {
    /// Só 0–9: `isNumber` aceita também algarismos de outras escritas.
    var isASCIIDigit: Bool { isASCII && isNumber }
}
