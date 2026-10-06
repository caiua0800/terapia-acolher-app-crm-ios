import AVFoundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Chat com o Zelo: texto, áudio (até 1 min), fotos e PDF; botões de escolha
/// e cartões das ações (feitas ou esperando confirmação).
struct ZeloChatView: View {
    @State private var zelo = ZeloStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var texto = ""
    @State private var arquivos: [ZeloArquivoLocal] = []
    @State private var fotos: [PhotosPickerItem] = []
    @State private var mostrandoFotos = false
    @State private var mostrandoScanner = false
    @State private var mostrandoPDF = false
    @State private var confirmandoReinicio = false
    @State private var avisoLocal: String?
    @State private var gravador = ZeloGravador()
    @State private var caminho = NavigationPath()
    @FocusState private var focado: Bool

    private let maxAnexos = 3

    var body: some View {
        NavigationStack(path: $caminho) {
            VStack(spacing: 0) {
                lista
                rodape
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        ZeloAvatar(size: 26)
                        VStack(alignment: .leading, spacing: 0) {
                            Zelo.nomeEstilizado(17)
                            Text("Seu assistente no Acolher Gestão")
                                .font(Theme.body(10))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button(role: .destructive) {
                            confirmandoReinicio = true
                        } label: {
                            Label("Reiniciar conversa", systemImage: "arrow.counterclockwise")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Mais opções")
                    .accessibilityIdentifier("zeloMais")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Fechar o Zelo")
                }
            }
            .navigationDestination(for: String.self) { pacienteId in
                PatientDetailView(patientId: pacienteId)
            }
            .confirmationDialog("Reiniciar conversa?", isPresented: $confirmandoReinicio, titleVisibility: .visible) {
                Button("Reiniciar conversa", role: .destructive) {
                    Task {
                        if await zelo.reiniciar() { Haptics.success() }
                    }
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("A conversa e os arquivos mandados aqui são apagados de vez.")
            }
        }
        .task { await zelo.carregar() }
        .photosPicker(isPresented: $mostrandoFotos, selection: $fotos, maxSelectionCount: maxAnexos, matching: .images)
        .onChange(of: fotos) { _, itens in
            guard !itens.isEmpty else { return }
            Task { await carregarFotos(itens) }
        }
        .fullScreenCover(isPresented: $mostrandoScanner) {
            FichaScannerView(maxPages: maxAnexos) { paginas in
                mostrandoScanner = false
                for (i, p) in paginas.enumerated() {
                    adicionarImagem(p, nome: "foto-\(Int(Date().timeIntervalSince1970))-\(i + 1).jpg")
                }
            } onCancel: {
                mostrandoScanner = false
            }
            .ignoresSafeArea()
        }
        .fileImporter(isPresented: $mostrandoPDF, allowedContentTypes: [.pdf]) { resultado in
            guard case .success(let url) = resultado else { return }
            let acesso = url.startAccessingSecurityScopedResource()
            defer { if acesso { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                avisoLocal = "Não consegui abrir esse arquivo."
                return
            }
            adicionar(ZeloArquivoLocal(data: data, nome: url.lastPathComponent, mime: "application/pdf"))
        }
    }

    // MARK: Lista

    private var lista: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if zelo.mensagens.isEmpty && !zelo.enviando {
                        boasVindas
                    }
                    ForEach(zelo.mensagens) { m in
                        BalaoDoZelo(
                            m: m,
                            ultima: m.id == zelo.mensagens.last?.id,
                            ocupado: zelo.enviando,
                            aoEscolher: { rotulo in Task { await mandar(rotulo) } },
                            aoAbrir: abrir
                        )
                        .id(m.id)
                    }
                    if zelo.enviando {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Zelo está pensando…")
                                .font(Theme.body(13))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.leading, 4)
                        .id("pensando")
                    }
                }
                .padding(Theme.screenPadding)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: zelo.mensagens.count) { _, _ in
                withAnimation { proxy.scrollTo(zelo.mensagens.last?.id, anchor: .bottom) }
            }
            .onChange(of: zelo.enviando) { _, enviando in
                if enviando { withAnimation { proxy.scrollTo("pensando", anchor: .bottom) } }
            }
            .onAppear { proxy.scrollTo(zelo.mensagens.last?.id, anchor: .bottom) }
        }
    }

    private var boasVindas: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZeloAvatar(size: 40)
                (Text("Oi! Sou o ") + Zelo.nomeEstilizado(18) + Text(". Como posso ajudar?"))
                    .font(Theme.body(16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            Text("Agendo, remarco e cancelo sessões, vejo cobranças e mensagens dos pacientes, anoto e anexo arquivos na ficha.")
                .font(Theme.body(14))
                .foregroundStyle(Theme.textSecondary)
            ForEach(["Como está minha agenda hoje?", "Quem está com cobrança em aberto?", "Quanto já usei do plano?"], id: \.self) { s in
                Button {
                    Task { await mandar(s) }
                } label: {
                    Text(s)
                        .font(Theme.body(14))
                        .foregroundStyle(Zelo.cor)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Zelo.cor.opacity(0.08), in: Capsule())
                        .overlay(Capsule().stroke(Zelo.cor.opacity(0.25)))
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: Rodapé (entrada)

    private var rodape: some View {
        VStack(spacing: 8) {
            if let erro = avisoLocal ?? zelo.erro {
                VStack(spacing: 6) {
                    Text(erro)
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if zelo.noLimite {
                        ManageAccountButton(style: .compact, tint: Zelo.cor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            if !arquivos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(arquivos) { a in
                            HStack(spacing: 6) {
                                Image(systemName: a.mime == "application/pdf" ? "doc.richtext" : "photo")
                                Text(a.nome).lineLimit(1)
                                Button {
                                    arquivos.removeAll { $0.id == a.id }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                            }
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Theme.surface, in: Capsule())
                            .overlay(Capsule().stroke(Theme.border))
                        }
                    }
                }
            }
            if gravador.gravando {
                gravacao
            } else {
                entrada
            }
            HStack(spacing: 4) {
                Image(systemName: "lock.fill").font(.system(size: 9))
                Text("Conversa privada e cifrada. Só você vê.")
                if let r = zelo.restantes { Text("· restam \(r) mensagens") }
            }
            .font(Theme.body(10))
            .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Theme.surface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Divider().overlay(Theme.border) }
    }

    private var entrada: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Menu {
                Button { mostrandoFotos = true } label: { Label("Fotos", systemImage: "photo.on.rectangle") }
                Button { mostrandoScanner = true } label: { Label("Câmera (escanear)", systemImage: "doc.viewfinder") }
                Button { mostrandoPDF = true } label: { Label("Documento PDF", systemImage: "doc.richtext") }
            } label: {
                Image(systemName: "paperclip")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 38, height: 38)
            }
            .disabled(arquivos.count >= maxAnexos || zelo.enviando)
            .accessibilityLabel("Anexar")

            TextField("Peça ao Zelo…", text: $texto, axis: .vertical)
                .lineLimit(1...5)
                .font(Theme.body(15))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.border))
                .focused($focado)
                .accessibilityIdentifier("zeloEntrada")

            if texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && arquivos.isEmpty && zelo.audioDisponivel {
                Button {
                    Task { await gravar() }
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Zelo.cor, in: Circle())
                }
                .buttonStyle(.pressable)
                .disabled(zelo.enviando)
                .accessibilityLabel("Gravar áudio (até 1 minuto)")
                .accessibilityIdentifier("zeloMicrofone")
            } else {
                Button {
                    Task { await mandar(texto) }
                } label: {
                    Group {
                        if zelo.enviando {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "arrow.up").font(.system(size: 17, weight: .bold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Theme.primary, in: Circle())
                }
                .buttonStyle(.pressable)
                .disabled(zelo.enviando)
                .accessibilityLabel("Enviar")
                .accessibilityIdentifier("zeloEnviar")
            }
        }
    }

    private var gravacao: some View {
        HStack(spacing: 12) {
            Button {
                gravador.cancelar()
            } label: {
                Image(systemName: "trash")
                    .frame(width: 40, height: 40)
                    .foregroundStyle(Theme.danger)
            }
            .accessibilityLabel("Cancelar áudio")
            Circle().fill(Theme.danger).frame(width: 9, height: 9)
            Text(String(format: "Gravando 0:%02d / 1:00", min(60, Int(gravador.segundos))))
                .font(Theme.body(14, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button {
                Task { await mandarAudio() }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Theme.primary, in: Circle())
            }
            .accessibilityLabel("Enviar áudio")
        }
        .onChange(of: gravador.terminouSozinho) { _, terminou in
            if terminou { Task { await mandarAudio() } }
        }
    }

    // MARK: Ações

    private func mandar(_ t: String) async {
        avisoLocal = nil
        let enviados = arquivos
        let txt = t
        texto = ""
        arquivos = []
        focado = false
        Haptics.tap()
        let feito = await zelo.enviar(texto: txt, arquivos: enviados)
        if feito { Haptics.success() }
        if zelo.erro != nil && !enviados.isEmpty && zelo.mensagens.isEmpty { arquivos = enviados }
    }

    private func gravar() async {
        avisoLocal = nil
        if let falha = await gravador.iniciar() { avisoLocal = falha }
    }

    private func mandarAudio() async {
        guard let audio = gravador.parar() else { return }
        Haptics.tap()
        let feito = await zelo.enviar(texto: "", audio: (audio, "audio/mp4"))
        if feito { Haptics.success() }
    }

    private func abrir(_ link: String) {
        let partes = link.split(separator: "/").map(String.init)
        if partes.first == "pacientes", partes.count >= 2 {
            caminho.append(partes[1])
            return
        }
        let secao: String? = switch partes.first {
        case "agenda": "agenda"
        case "financeiro": "financeiro"
        case "gateway": "gateway"
        case "pacientes": "pacientes"
        default: nil
        }
        if let secao {
            DeepLink.shared.pendingSection = secao
            dismiss()
        }
    }

    private func adicionar(_ a: ZeloArquivoLocal) {
        guard arquivos.count < maxAnexos else {
            avisoLocal = "Até \(maxAnexos) arquivos por mensagem."
            return
        }
        guard a.data.count <= 10 * 1024 * 1024 else {
            avisoLocal = "Arquivo grande demais (máximo 10 MB)."
            return
        }
        arquivos.append(a)
    }

    private func adicionarImagem(_ img: UIImage, nome: String) {
        guard let data = ZeloImagem.jpeg(img) else {
            avisoLocal = "Não consegui abrir esse arquivo."
            return
        }
        adicionar(ZeloArquivoLocal(data: data, nome: nome, mime: "image/jpeg"))
    }

    private func carregarFotos(_ itens: [PhotosPickerItem]) async {
        for (i, item) in itens.enumerated() {
            if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                adicionarImagem(img, nome: "foto-\(Int(Date().timeIntervalSince1970))-\(i + 1).jpg")
            }
        }
        fotos = []
    }
}

// MARK: - Balão

private struct BalaoDoZelo: View {
    let m: ZeloMensagem
    let ultima: Bool
    let ocupado: Bool
    let aoEscolher: (String) -> Void
    let aoAbrir: (String) -> Void

    var body: some View {
        VStack(alignment: m.daTerapeuta ? .trailing : .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                if m.daTerapeuta { Spacer(minLength: 40) } else { ZeloAvatar(size: 26) }
                VStack(alignment: .leading, spacing: 6) {
                    if m.audio == true {
                        Label("Áudio transcrito", systemImage: "mic.fill")
                            .font(Theme.body(11, weight: .semibold))
                            .foregroundStyle(m.daTerapeuta ? .white.opacity(0.85) : Zelo.cor)
                    }
                    if !m.texto.isEmpty {
                        Text(Markdown.renderizar(m.texto))
                            .font(Theme.body(15))
                            .foregroundStyle(m.daTerapeuta ? .white : Theme.textPrimary)
                            .textSelection(.enabled)
                    }
                    ForEach(m.anexos ?? []) { a in
                        Label(a.nome, systemImage: a.mime == "application/pdf" ? "doc.richtext" : "photo")
                            .font(Theme.body(12))
                            .foregroundStyle(m.daTerapeuta ? .white.opacity(0.9) : Theme.textSecondary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    m.daTerapeuta ? AnyShapeStyle(Theme.primary) : AnyShapeStyle(Theme.surface),
                    in: RoundedRectangle(cornerRadius: 18)
                )
                .overlay {
                    if !m.daTerapeuta { RoundedRectangle(cornerRadius: 18).stroke(Theme.border) }
                }
                if !m.daTerapeuta { Spacer(minLength: 24) }
            }

            ForEach(m.acoes ?? [], id: \.self) { a in
                CartaoDeAcao(a: a, aoAbrir: aoAbrir)
                    .padding(.leading, 34)
            }

            if ultima, let opcoes = m.opcoes, !opcoes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(opcoes, id: \.self) { o in
                        Button {
                            aoEscolher(o.rotulo)
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(o.rotulo).font(Theme.body(14, weight: .semibold))
                                if let d = o.detalhe {
                                    Text(d).font(Theme.body(12)).foregroundStyle(Theme.textSecondary)
                                }
                            }
                            .foregroundStyle(Zelo.cor)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Zelo.cor.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Zelo.cor.opacity(0.25)))
                        }
                        .buttonStyle(.pressable)
                        .disabled(ocupado)
                        .accessibilityIdentifier("zeloOpcao:\(o.rotulo)")
                    }
                }
                .padding(.leading, 34)
            }
        }
        .frame(maxWidth: .infinity, alignment: m.daTerapeuta ? .trailing : .leading)
    }
}

private struct CartaoDeAcao: View {
    let a: ZeloAcao
    let aoAbrir: (String) -> Void

    var body: some View {
        Button {
            if let link = a.link { aoAbrir(link) }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: a.aguardandoConfirmacao ? "hourglass" : "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(a.aguardandoConfirmacao ? Theme.warning : Theme.success)
                VStack(alignment: .leading, spacing: 2) {
                    Text(a.aguardandoConfirmacao ? "AGUARDANDO SUA CONFIRMAÇÃO" : "FEITO")
                        .font(Theme.body(10, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(a.aguardandoConfirmacao ? Theme.warning : Theme.success)
                    Text(a.titulo)
                        .font(Theme.body(14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.leading)
                    if let d = a.detalhe {
                        Text(d).font(Theme.body(12)).foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                if a.link != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(12)
            .background(
                a.aguardandoConfirmacao ? Theme.warningSoft : Theme.successSoft,
                in: RoundedRectangle(cornerRadius: 14)
            )
        }
        .buttonStyle(.pressable)
        .disabled(a.link == nil)
    }
}

// MARK: - Markdown simples (negrito, itálico, listas) sem HTML

enum Markdown {
    static func renderizar(_ texto: String) -> AttributedString {
        // Listas "- item" viram "• item"; o resto é markdown em linha.
        let linhas = texto.split(separator: "\n", omittingEmptySubsequences: false).map { linha -> String in
            let t = linha.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("- ") || t.hasPrefix("* ") { return "• " + t.dropFirst(2) }
            return String(linha)
        }
        let junto = linhas.joined(separator: "\n")
        let opcoes = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: junto, options: opcoes)) ?? AttributedString(junto)
    }
}

// MARK: - Imagem e gravação

enum ZeloImagem {
    /// Foto mandada ao Zelo (pode virar anexo do paciente): 2000 px, JPEG 0,85.
    static func jpeg(_ image: UIImage) -> Data? {
        let maxSide: CGFloat = 2000
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxSide ? maxSide / longest : 1
        let alvo = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let formato = UIGraphicsImageRendererFormat.default()
        formato.scale = 1
        return UIGraphicsImageRenderer(size: alvo, format: formato).image { _ in
            image.draw(in: CGRect(origin: .zero, size: alvo))
        }.jpegData(compressionQuality: 0.85)
    }
}

/// Grava áudio AAC/M4A, para sozinho em 60 s.
@MainActor
@Observable
final class ZeloGravador {
    var gravando = false
    var segundos: TimeInterval = 0
    var terminouSozinho = false
    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var arquivo: URL?

    func iniciar() async -> String? {
        let permitido = await AVAudioApplication.requestRecordPermission()
        guard permitido else { return "Sem acesso ao microfone. Libere nos Ajustes do iPhone." }
        do {
            let sessao = AVAudioSession.sharedInstance()
            try sessao.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
            try sessao.setActive(true)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("zelo-audio-\(UUID().uuidString).m4a")
            let r = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 22_050,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 32_000,
            ])
            r.record(forDuration: 60)
            recorder = r
            arquivo = url
            segundos = 0
            terminouSozinho = false
            gravando = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let r = self.recorder else { return }
                    if r.isRecording {
                        self.segundos = r.currentTime
                    } else if self.gravando {
                        self.terminouSozinho = true
                    }
                }
            }
            Haptics.tap()
            return nil
        } catch {
            return "Não foi possível gravar agora."
        }
    }

    /// Para e devolve o áudio (nil se não houver).
    func parar() -> Data? {
        timer?.invalidate()
        recorder?.stop()
        gravando = false
        defer { limpar() }
        guard let arquivo, let data = try? Data(contentsOf: arquivo), !data.isEmpty else { return nil }
        return data
    }

    func cancelar() {
        timer?.invalidate()
        recorder?.stop()
        gravando = false
        limpar()
    }

    private func limpar() {
        if let arquivo { try? FileManager.default.removeItem(at: arquivo) }
        arquivo = nil
        recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
