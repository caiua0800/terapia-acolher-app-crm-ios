import SwiftUI

/// Aviso de versão nova (2026-10-23). A cada vez que o app abre ou volta ao
/// primeiro plano, compara a versão instalada com:
/// - a publicada na App Store (consulta pública da Apple, sem configurar nada:
///   aprovou na loja, o aviso começa sozinho — a Apple pode levar algumas
///   horas para refletir a versão nova nessa consulta);
/// - a mínima do backend (`GET app/versao`): abaixo dela não há "Lembrar
///   depois", o app obriga a atualizar.
@MainActor
@Observable
final class AtualizacaoDoApp {
    static let shared = AtualizacaoDoApp()

    enum Aviso: Equatable {
        case opcional(versao: String)
        case obrigatoria
    }

    /// O que a tela mostra agora (nil = nada).
    private(set) var aviso: Aviso?

    /// "Lembrar depois" vale até o app ir para o segundo plano.
    private var adiado = false
    private var verificando = false

    static let urlDaLoja = URL(string: "https://apps.apple.com/br/app/acolher-gest%C3%A3o/id6798024931")!
    private static let bundleId = "com.ccypher.terapiaacolher"

    private var versaoInstalada: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    func appFoiParaSegundoPlano() {
        adiado = false
    }

    func verificar() async {
        if CommandLine.arguments.contains("--simular-atualizacao") {
            if !adiado { aviso = .opcional(versao: "9.9.9") }
            return
        }
        guard !verificando else { return }
        verificando = true
        defer { verificando = false }

        async let loja = Self.versaoNaLoja()
        async let minima = Self.versaoMinima()
        let (versaoLoja, versaoMinima) = await (loja, minima)
        let instalada = versaoInstalada

        if let versaoMinima, Self.compara(instalada, versaoMinima) == .orderedAscending {
            aviso = .obrigatoria
        } else if let versaoLoja, Self.compara(instalada, versaoLoja) == .orderedAscending {
            aviso = adiado ? nil : .opcional(versao: versaoLoja)
        } else {
            aviso = nil
        }
    }

    func lembrarDepois() {
        guard aviso != .obrigatoria else { return }
        adiado = true
        aviso = nil
    }

    // MARK: - Consultas

    private struct RespostaDaLoja: Decodable {
        struct Item: Decodable { let version: String }
        let results: [Item]
    }

    private struct VersaoDoBackend: Decodable {
        struct Plataforma: Decodable { let minima: String? }
        let ios: Plataforma
    }

    private static func versaoNaLoja() async -> String? {
        // `t` fura o cache da CDN da Apple, que segura a resposta por horas.
        let t = Int(Date().timeIntervalSince1970)
        guard let url = URL(string: "https://itunes.apple.com/lookup?bundleId=\(bundleId)&country=br&t=\(t)") else { return nil }
        var pedido = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        pedido.httpMethod = "GET"
        guard let (dados, _) = try? await URLSession.shared.data(for: pedido),
              let resposta = try? JSONDecoder().decode(RespostaDaLoja.self, from: dados)
        else { return nil }
        return resposta.results.first?.version
    }

    private static func versaoMinima() async -> String? {
        let resposta: VersaoDoBackend? = try? await APIClient.shared.get("app/versao")
        return resposta?.ios.minima
    }

    /// Compara "1.3.0" com "1.10" número a número (string pura erraria).
    static func compara(_ a: String, _ b: String) -> ComparisonResult {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x < y ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}

/// Cartão do aviso, por cima de qualquer tela (logado ou não).
struct AvisoDeAtualizacaoView: View {
    let aviso: AtualizacaoDoApp.Aviso
    @Environment(\.openURL) private var openURL

    private var obrigatoria: Bool { aviso == .obrigatoria }

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "arrow.down.app.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .frame(width: 64, height: 64)
                    .background(Theme.primarySoft, in: Circle())

                VStack(spacing: 8) {
                    Text(obrigatoria ? "Atualização necessária" : "Nova versão disponível")
                        .font(Theme.serifTitle(22))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                    Text(obrigatoria
                         ? "Esta versão do Acolher Gestão não é mais compatível. Atualize para continuar usando."
                         : "Atualize o Acolher Gestão para ter as novidades e melhorias mais recentes.")
                        .font(Theme.body(15))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 10) {
                    PrimaryButton(title: "Atualizar agora") {
                        openURL(AtualizacaoDoApp.urlDaLoja)
                    }
                    .accessibilityIdentifier("atualizarAgora")
                    if !obrigatoria {
                        SecondaryButton(title: "Lembrar depois") {
                            withAnimation(.easeOut(duration: 0.2)) {
                                AtualizacaoDoApp.shared.lembrarDepois()
                            }
                        }
                        .accessibilityIdentifier("lembrarDepois")
                    }
                }
                .padding(.top, 4)
            }
            .padding(24)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: 24))
            .padding(.horizontal, 28)
        }
        .transition(.opacity)
    }
}
