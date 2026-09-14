import AVKit
import QuickLook
import SwiftUI
import UIKit

/// Renova a URL assinada de um anexo (id da mensagem → anexo com URL nova).
typealias SupRenew = @MainActor (String) async -> SupAttachment?

// MARK: - Download com renovação

enum SupMediaFetch {
    /// Baixa pela URL assinada; se venceu (403), pede outra e tenta uma vez.
    static func data(messageId: String, attachment: SupAttachment, renew: SupRenew) async -> Data? {
        var atual = attachment
        if atual.isExpiringSoon, let nova = await renew(messageId) { atual = nova }
        for tentativa in 0 ..< 2 {
            guard let url = atual.resolvedURL,
                  let (dados, resposta) = try? await URLSession.shared.data(from: url)
            else { return nil }
            let status = (resposta as? HTTPURLResponse)?.statusCode ?? 0
            if (200 ..< 300).contains(status) { return dados }
            if status == 403, tentativa == 0, let nova = await renew(messageId) {
                atual = nova
                continue
            }
            return nil
        }
        return nil
    }
}

/// Fotos do chat só em memória: pode haver print com dado sensível, e a LGPD
/// não combina com cópia persistente fora do controle do app.
@MainActor
final class SupImageCache {
    static let shared = SupImageCache()
    private let cache = NSCache<NSString, UIImage>()

    private init() { cache.countLimit = 80 }

    func image(for id: String) -> UIImage? { cache.object(forKey: id as NSString) }
    func store(_ image: UIImage, for id: String) { cache.setObject(image, forKey: id as NSString) }
}

// MARK: - Foto

struct SupRemoteImage: View {
    let messageId: String
    let attachment: SupAttachment
    let renew: SupRenew
    var maxWidth: CGFloat = 228

    @State private var image: UIImage?
    @State private var failed = false
    @State private var showViewer = false

    private var aspect: CGFloat {
        if let w = attachment.width, let h = attachment.height, w > 0, h > 0 {
            return CGFloat(w) / CGFloat(h)
        }
        if let image, image.size.height > 0 { return image.size.width / image.size.height }
        return 4.0 / 3.0
    }

    var body: some View {
        let altura = min(max(maxWidth / aspect, 110), 320)
        Button {
            if image != nil {
                showViewer = true
            } else if failed {
                Task { await load() }
            }
        } label: {
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else if failed {
                    VStack(spacing: 6) {
                        Image(systemName: "photo")
                            .font(.system(size: 20))
                        Text("Toque para tentar de novo")
                            .font(Theme.body(11, weight: .medium))
                    }
                    .foregroundStyle(Theme.textSecondary)
                } else {
                    Rectangle().fill(Theme.border.opacity(0.6))
                    ProgressView().tint(Theme.primary)
                }
            }
            .frame(width: maxWidth, height: altura)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.pressableSubtle)
        .accessibilityLabel(failed ? "Foto não carregou. Toque para tentar de novo" : "Foto. Toque para ampliar")
        .task(id: messageId) { await load() }
        .fullScreenCover(isPresented: $showViewer) {
            if let image { SupImageViewer(image: image) }
        }
    }

    private func load() async {
        if let pronta = SupImageCache.shared.image(for: messageId) {
            image = pronta
            return
        }
        failed = false
        if let dados = await SupMediaFetch.data(messageId: messageId, attachment: attachment, renew: renew),
           let carregada = UIImage(data: dados) {
            SupImageCache.shared.store(carregada, for: messageId)
            image = carregada
        } else {
            failed = true
        }
    }
}

struct SupImageViewer: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .gesture(
                    MagnifyGesture()
                        .onChanged { valor in
                            scale = min(max(lastScale * valor.magnification, 1), 5)
                        }
                        .onEnded { _ in
                            lastScale = scale
                            if scale <= 1 { resetar() }
                        }
                        .simultaneously(with: DragGesture()
                            .onChanged { valor in
                                guard scale > 1 else { return }
                                offset = CGSize(
                                    width: lastOffset.width + valor.translation.width,
                                    height: lastOffset.height + valor.translation.height
                                )
                            }
                            .onEnded { _ in lastOffset = offset })
                )
                .onTapGesture(count: 2) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        if scale > 1 {
                            resetar()
                        } else {
                            scale = 2.5
                            lastScale = 2.5
                        }
                    }
                }
                .accessibilityLabel("Foto em tela cheia. Toque duas vezes para ampliar")

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(.white.opacity(0.16), in: Circle())
            }
            .buttonStyle(.pressable)
            .padding(16)
            .accessibilityLabel("Fechar")
        }
    }

    private func resetar() {
        withAnimation(.easeOut(duration: 0.2)) {
            scale = 1
            lastScale = 1
            offset = .zero
            lastOffset = .zero
        }
    }
}

// MARK: - Vídeo

private struct SupPlayable: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct SupVideoAttachment: View {
    let messageId: String
    let attachment: SupAttachment
    let renew: SupRenew

    @State private var playable: SupPlayable?
    @State private var isOpening = false

    var body: some View {
        Button {
            Task { await abrir() }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Theme.ink)
                VStack(spacing: 8) {
                    ZStack {
                        if isOpening {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "play.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 50, height: 50)
                    .background(.white.opacity(0.18), in: Circle())
                    Text(rotulo)
                        .font(Theme.body(12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .frame(width: 228, height: 150)
        }
        .buttonStyle(.pressableSubtle)
        .disabled(isOpening)
        .accessibilityLabel("Vídeo \(rotulo). Toque para assistir")
        .fullScreenCover(item: $playable) { item in
            SupVideoPlayerScreen(url: item.url)
        }
    }

    private var rotulo: String {
        [SupFormat.duracao(ms: attachment.durationMs), SupFormat.tamanho(attachment.sizeBytes)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private func abrir() async {
        isOpening = true
        defer { isOpening = false }
        var atual = attachment
        if atual.isExpiringSoon, let nova = await renew(messageId) { atual = nova }
        if let url = atual.resolvedURL { playable = SupPlayable(url: url) }
    }
}

private struct SupVideoPlayerScreen: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(.white.opacity(0.16), in: Circle())
            }
            .buttonStyle(.pressable)
            .padding(16)
            .accessibilityLabel("Fechar vídeo")
        }
        .onAppear {
            SupAudioPlayback.shared.stop()
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            let novo = AVPlayer(url: url)
            player = novo
            novo.play()
        }
        .onDisappear { player?.pause() }
    }
}

// MARK: - Áudio

struct SupAudioAttachment: View {
    let messageId: String
    let attachment: SupAttachment
    let renew: SupRenew
    let isMine: Bool

    @State private var playback = SupAudioPlayback.shared
    @State private var preparing = false

    private var isCurrent: Bool { playback.currentId == messageId }
    private var tocando: Bool { isCurrent && playback.isPlaying }
    private var frente: Color { isMine ? .white : Theme.primary }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                Task { await alternar() }
            } label: {
                ZStack {
                    if preparing {
                        ProgressView().controlSize(.small).tint(isMine ? Theme.primary : .white)
                    } else {
                        Image(systemName: tocando ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(isMine ? Theme.primary : .white)
                    }
                }
                .frame(width: 36, height: 36)
                .background(frente, in: Circle())
            }
            .buttonStyle(.pressable)
            .disabled(preparing)
            .accessibilityLabel(tocando ? "Pausar áudio" : "Tocar áudio de \(SupFormat.duracao(ms: attachment.durationMs) ?? "duração desconhecida")")

            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(frente.opacity(0.25))
                        Capsule()
                            .fill(frente)
                            .frame(width: geo.size.width * (isCurrent ? playback.progress : 0))
                    }
                }
                .frame(height: 4)
                Text(rotuloTempo)
                    .font(Theme.body(11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(isMine ? .white.opacity(0.85) : Theme.textSecondary)
            }
            .frame(width: 148)
        }
        .padding(.vertical, 2)
    }

    private var rotuloTempo: String {
        let total = SupFormat.duracao(ms: attachment.durationMs) ?? "0:00"
        guard isCurrent, playback.position > 0 else { return total }
        return "\(SupFormat.duracao(playback.position)) / \(total)"
    }

    private func alternar() async {
        if isCurrent {
            if let url = attachment.resolvedURL {
                playback.toggle(id: messageId, url: url, durationMs: attachment.durationMs)
            }
            return
        }
        preparing = true
        defer { preparing = false }
        var atual = attachment
        if atual.isExpiringSoon, let nova = await renew(messageId) { atual = nova }
        guard let url = atual.resolvedURL else { return }
        playback.toggle(id: messageId, url: url, durationMs: atual.durationMs)
    }
}

// MARK: - Arquivo (Quick Look)

private struct SupPreviewFile: Identifiable {
    let url: URL
    let name: String
    var id: String { url.path }
}

struct SupFileAttachment: View {
    let messageId: String
    let attachment: SupAttachment
    let renew: SupRenew
    let isMine: Bool

    @State private var isOpening = false
    @State private var preview: SupPreviewFile?
    @State private var failed = false

    private var nome: String { attachment.name ?? "arquivo" }

    var body: some View {
        Button {
            Task { await abrir() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icone)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isMine ? Theme.primary : Theme.textPrimary)
                    .frame(width: 38, height: 38)
                    .background(isMine ? Color.white : Theme.background, in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text(nome)
                        .font(Theme.body(14, weight: .semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(failed ? "Não abriu. Toque para tentar de novo" : detalhe)
                        .font(Theme.body(11))
                        .opacity(0.8)
                }
                .foregroundStyle(isMine ? .white : Theme.textPrimary)
                Spacer(minLength: 4)
                ZStack {
                    if isOpening {
                        ProgressView().controlSize(.small).tint(isMine ? .white : Theme.primary)
                    } else {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 17))
                            .foregroundStyle(isMine ? .white : Theme.primary)
                    }
                }
                .frame(width: 24, height: 24)
            }
            .frame(width: 228, alignment: .leading)
        }
        .buttonStyle(.pressableSubtle)
        .disabled(isOpening)
        .accessibilityLabel("Arquivo \(nome), \(detalhe). Toque para abrir")
        .sheet(item: $preview) { arquivo in
            NavigationStack {
                SupQuickLook(url: arquivo.url)
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle(arquivo.name)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Fechar") { preview = nil }
                        }
                    }
            }
        }
    }

    private var detalhe: String {
        let ext = (nome as NSString).pathExtension.uppercased()
        return [ext.isEmpty ? nil : ext, SupFormat.tamanho(attachment.sizeBytes)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var icone: String {
        switch attachment.contentType {
        case "application/pdf": "doc.richtext"
        case "text/csv", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": "tablecells"
        default: "doc.text"
        }
    }

    private func abrir() async {
        isOpening = true
        failed = false
        defer { isOpening = false }
        guard let dados = await SupMediaFetch.data(messageId: messageId, attachment: attachment, renew: renew) else {
            failed = true
            return
        }
        do {
            let pasta = FileManager.default.temporaryDirectory
                .appendingPathComponent("suporte-\(messageId)", isDirectory: true)
            try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
            let destino = pasta.appendingPathComponent(nome.replacingOccurrences(of: "/", with: "-"))
            try dados.write(to: destino, options: .atomic)
            preview = SupPreviewFile(url: destino, name: nome)
        } catch {
            failed = true
        }
    }
}

private struct SupQuickLook: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    @MainActor
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
