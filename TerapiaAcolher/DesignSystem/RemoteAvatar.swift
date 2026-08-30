import SwiftUI

/// Cache de fotos remotas em memória, chaveado pelo CAMINHO da URL.
///
/// As URLs de foto (paciente, avatar do terapeuta, Vitrine) vêm **assinadas e
/// com validade curta**: a assinatura vive na query e muda a cada pedido. Com
/// isso o cache do `URLSession` nunca acertava, e a MESMA foto era baixada de
/// novo toda vez que a tela abria — era isso que fazia a imagem demorar e
/// "aparecer do nada" no meio da tela já montada.
///
/// Chavear por host+caminho ignora a assinatura e reconhece a foto como a
/// mesma. Só memória: nada de disco, porque estas são fotos de paciente e a
/// LGPD não combina com cópia persistente fora do controle do app.
@MainActor
final class RemoteImageCache {
    static let shared = RemoteImageCache()

    private var imagens: [String: UIImage] = [:]
    private var emVoo: [String: Task<UIImage?, Never>] = [:]

    /// Teto conservador: 60 fotos de avatar cabem folgado na memória de uma
    /// lista de pacientes, e evita crescer sem limite numa sessão longa.
    private let limite = 60
    private var ordem: [String] = []

    private func chave(_ url: URL) -> String {
        (url.host ?? "") + url.path
    }

    /// Já está em memória? Quem chama usa isso para pintar sem transição.
    func emMemoria(_ url: URL) -> UIImage? {
        imagens[chave(url)]
    }

    func carregar(_ url: URL) async -> UIImage? {
        let k = chave(url)
        if let pronta = imagens[k] { return pronta }

        // Duas telas pedindo a mesma foto ao mesmo tempo (lista e detalhe)
        // compartilham o mesmo download em vez de disparar dois.
        if let andando = emVoo[k] { return await andando.value }

        let tarefa = Task<UIImage?, Never> {
            guard let (dados, resposta) = try? await URLSession.shared.data(from: url),
                  (resposta as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
                  let imagem = UIImage(data: dados)
            else { return nil }
            return imagem
        }
        emVoo[k] = tarefa
        let imagem = await tarefa.value
        emVoo[k] = nil

        if let imagem {
            imagens[k] = imagem
            ordem.append(k)
            while ordem.count > limite, let antiga = ordem.first {
                ordem.removeFirst()
                imagens[antiga] = nil
            }
        }
        return imagem
    }

    /// Chamada ao trocar ou remover a foto: sem isto a versão velha continuaria
    /// aparecendo, já que a chave (o caminho) não muda quando o arquivo muda.
    func invalidar(_ url: URL?) {
        guard let url else { return }
        let k = chave(url)
        imagens[k] = nil
        ordem.removeAll { $0 == k }
    }
}

/// Avatar que carrega foto remota sem pipocar.
///
/// Enquanto baixa, mostra as **iniciais** com um brilho passando por cima — o
/// terapeuta vê que algo está vindo, em vez de um buraco cinza que de repente
/// vira foto. Quando a imagem chega, entra em fade. Se já estiver em cache,
/// entra pronta, sem transição nenhuma.
struct RemoteAvatar: View {
    let url: URL?
    let name: String
    var colorHex: String? = nil
    var size: CGFloat = 44
    var showsBorder: Bool = false

    @State private var imagem: UIImage?
    @State private var carregando = false

    init(
        url: URL?,
        name: String,
        colorHex: String? = nil,
        size: CGFloat = 44,
        showsBorder: Bool = false
    ) {
        self.url = url
        self.name = name
        self.colorHex = colorHex
        self.size = size
        self.showsBorder = showsBorder
        // Pinta já no primeiro frame quando a foto está em memória: sem isto,
        // voltar para uma tela mostraria as iniciais por um instante antes de
        // trocar — o mesmo pisca-pisca que estamos consertando.
        if let url, let pronta = RemoteImageCache.shared.emMemoria(url) {
            _imagem = State(initialValue: pronta)
        }
    }

    /// URL sem a assinatura: é o que identifica a FOTO. Comparar a URL inteira
    /// dispararia recarga a cada refresh da tela, porque a query muda sempre.
    private var identidade: String {
        guard let url else { return "" }
        return (url.host ?? "") + url.path
    }

    var body: some View {
        ZStack {
            InitialAvatar(
                name: name.isEmpty ? "?" : name,
                colorHex: colorHex,
                size: size
            )
            .opacity(imagem == nil ? 1 : 0)

            if let imagem {
                Image(uiImage: imagem)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            }
        }
        .frame(width: size, height: size)
        .overlay {
            if carregando { ShimmerCircle(size: size) }
        }
        .overlay {
            if showsBorder {
                Circle().stroke(Theme.border, lineWidth: 1)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: imagem != nil)
        .task(id: identidade) { await carregar() }
    }

    private func carregar() async {
        guard let url else {
            imagem = nil
            carregando = false
            return
        }
        if let pronta = RemoteImageCache.shared.emMemoria(url) {
            imagem = pronta
            carregando = false
            return
        }
        carregando = true
        let baixada = await RemoteImageCache.shared.carregar(url)
        carregando = false
        imagem = baixada
    }
}

/// Brilho que atravessa o círculo enquanto a foto baixa.
private struct ShimmerCircle: View {
    let size: CGFloat
    @State private var deslocamento: CGFloat = -1

    var body: some View {
        LinearGradient(
            colors: [
                .white.opacity(0),
                .white.opacity(0.38),
                .white.opacity(0),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: size, height: size)
        .offset(x: deslocamento * size)
        .clipShape(Circle())
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                deslocamento = 1
            }
        }
    }
}
