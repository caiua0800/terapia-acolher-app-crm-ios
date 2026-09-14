import AVFoundation
import CoreTransferable
import Foundation
import Observation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Arquivo local pronto pra subir

/// Já convertido/comprimido, num diretório temporário do app.
struct SupLocalFile: Equatable {
    let url: URL
    let kind: SupUploadKind
    let contentType: String
    let fileName: String
    let sizeBytes: Int
    var durationMs: Int?
    var width: Int?
    var height: Int?
    var preview: UIImage?
}

/// Mensagem ainda não confirmada pelo servidor (envio otimista).
struct SupOutgoing: Identifiable, Equatable {
    enum State: Equatable {
        case sending(progress: Double?)
        case failed(String)
    }

    let clientId: String
    var text: String?
    var file: SupLocalFile?
    var uploadId: String?
    var state: State
    let createdAt: Date

    var id: String { clientId }
}

struct SupPrepError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

// MARK: - Conversa

@MainActor
@Observable
final class SupportChatModel {
    let ticketId: String
    private(set) var ticket: SupTicket?
    private(set) var messages: [SupMessage] = []
    private(set) var outgoing: [SupOutgoing] = []
    private(set) var isLoading = false
    private(set) var loadError: String?
    private(set) var hasMoreOlder = false
    private(set) var isLoadingOlder = false
    private(set) var typingName: String?
    private(set) var adminReadAt: Date?
    var errorMessage: String?
    var draft = ""

    @ObservationIgnored private var observerId: UUID?
    @ObservationIgnored private var typingClearTask: Task<Void, Never>?
    @ObservationIgnored private var lastTypingSentAt: Date = .distantPast
    @ObservationIgnored private var sendTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var readInFlight = false

    init(ticketId: String, ticket: SupTicket? = nil) {
        self.ticketId = ticketId
        self.ticket = ticket
    }

    var isResolved: Bool { ticket?.status.isResolved ?? false }

    /// Até quando o time leu: o maior entre o `adminLastReadAt` do atendimento
    /// (vem na carga e em `support.ticket`, então sobrevive a reabrir a conversa)
    /// e o `support.read` recebido em tempo real.
    var effectiveAdminReadAt: Date? {
        switch (ticket?.adminLastReadAt, adminReadAt) {
        case let (a?, b?): max(a, b)
        case let (a?, nil): a
        case let (nil, b?): b
        case (nil, nil): nil
        }
    }

    /// Última mensagem minha que o time já viu (é nela que aparece o "Visto").
    /// Vista = criada até a leitura do time; reforço: houve resposta depois dela.
    var lastSeenMineId: String? {
        let lida = effectiveAdminReadAt
        let respostas = messages.filter { $0.senderRole == .admin }.map(\.createdAt)
        let ultimaResposta = respostas.max()
        return messages.last { mensagem in
            guard mensagem.isMine else { return false }
            if let lida, mensagem.createdAt <= lida { return true }
            if let ultimaResposta, ultimaResposta >= mensagem.createdAt { return true }
            return false
        }?.id
    }

    // MARK: Ciclo de vida da tela

    func appear() {
        if observerId == nil {
            observerId = SupportStore.shared.observe { [weak self] event in
                self?.handle(event)
            }
        }
        if messages.isEmpty {
            Task { await load() }
        } else {
            Task { await fillGap() }
        }
    }

    func disappear() {
        if let observerId { SupportStore.shared.removeObserver(observerId) }
        observerId = nil
        typingName = nil
    }

    func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            async let ticketRequest = SupportAPI.ticket(id: ticketId)
            async let pageRequest = SupportAPI.messages(ticketId: ticketId, limit: 50)
            let (ticketValue, page) = try await (ticketRequest, pageRequest)
            ticket = ticketValue
            SupportStore.shared.upsert(ticketValue)
            merge(page.items)
            hasMoreOlder = page.hasMore
            await markRead()
        } catch is CancellationError {
            return
        } catch {
            loadError = texto(de: error, padrao: "Não foi possível abrir a conversa. Confira a conexão e tente de novo.")
        }
    }

    func loadOlder() async {
        guard hasMoreOlder, !isLoadingOlder, let first = messages.first else { return }
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        do {
            let page = try await SupportAPI.messages(ticketId: ticketId, before: first.id, limit: 50)
            merge(page.items)
            hasMoreOlder = page.hasMore
        } catch is CancellationError {
            return
        } catch {
            hasMoreOlder = false
            errorMessage = texto(de: error, padrao: "Não foi possível carregar as mensagens antigas.")
        }
    }

    /// Reconexão ou volta pra tela: busca só o que chegou depois da última.
    func fillGap() async {
        guard let last = messages.last else {
            await load()
            return
        }
        var cursor = last.id
        for _ in 0 ..< 5 {
            guard let page = try? await SupportAPI.messages(ticketId: ticketId, after: cursor, limit: 100) else { break }
            merge(page.items)
            guard page.hasMore, let newest = page.items.last else { break }
            cursor = newest.id
        }
        if let fresh = try? await SupportAPI.ticket(id: ticketId) {
            ticket = fresh
        }
        await markRead()
    }

    private func merge(_ incoming: [SupMessage]) {
        guard !incoming.isEmpty else { return }
        var byId = Dictionary(messages.map { ($0.id, $0) }, uniquingKeysWith: { _, novo in novo })
        for message in incoming { byId[message.id] = message }
        messages = byId.values.sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
        let confirmados = Set(incoming.compactMap(\.clientId))
        outgoing.removeAll { confirmados.contains($0.clientId) }
    }

    private func handle(_ event: SupRealtimeEvent) {
        switch event {
        case let .message(id, message) where id == ticketId:
            merge([message])
            if !message.isMine {
                typingName = nil
                Task { await markRead() }
            }
        case let .ticket(value) where value.id == ticketId:
            ticket = value
        case let .typing(id, role, name) where id == ticketId && role != .therapist:
            showTyping(name)
        case let .read(id, role, at) where id == ticketId && role == .admin:
            adminReadAt = at ?? Date()
        case .connected:
            Task { await fillGap() }
        default:
            break
        }
    }

    private func showTyping(_ name: String?) {
        typingName = (name?.isEmpty == false) ? name : "Suporte"
        typingClearTask?.cancel()
        typingClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            self?.typingName = nil
        }
    }

    func markRead() async {
        guard !readInFlight, let last = messages.last else { return }
        guard !last.isMine || (ticket?.unread ?? 0) > 0 else { return }
        readInFlight = true
        defer { readInFlight = false }
        _ = try? await SupportAPI.markRead(ticketId: ticketId)
    }

    func draftChanged() {
        guard !isResolved, !draft.isEmpty, Date().timeIntervalSince(lastTypingSentAt) > 2 else { return }
        lastTypingSentAt = Date()
        SupportStore.shared.sendTyping(ticketId: ticketId)
    }

    // MARK: Envio

    func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isResolved else { return }
        guard text.count <= 4000 else {
            errorMessage = "A mensagem pode ter no máximo 4.000 caracteres."
            return
        }
        draft = ""
        let item = SupOutgoing(
            clientId: Self.newClientId(),
            text: text,
            file: nil,
            uploadId: nil,
            state: .sending(progress: nil),
            createdAt: Date()
        )
        outgoing.append(item)
        run(item)
    }

    func send(file: SupLocalFile) {
        guard !isResolved else { return }
        if let problema = file.kind.validate(
            contentType: file.contentType,
            sizeBytes: file.sizeBytes,
            durationMs: file.durationMs
        ) {
            try? FileManager.default.removeItem(at: file.url)
            errorMessage = problema
            return
        }
        let item = SupOutgoing(
            clientId: Self.newClientId(),
            text: nil,
            file: file,
            uploadId: nil,
            state: .sending(progress: 0),
            createdAt: Date()
        )
        outgoing.append(item)
        run(item)
    }

    func retry(_ clientId: String) {
        guard let index = index(of: clientId) else { return }
        outgoing[index].state = .sending(progress: outgoing[index].file == nil ? nil : 0)
        run(outgoing[index])
    }

    func discard(_ clientId: String) {
        sendTasks[clientId]?.cancel()
        sendTasks[clientId] = nil
        if let index = index(of: clientId), let file = outgoing[index].file {
            try? FileManager.default.removeItem(at: file.url)
        }
        outgoing.removeAll { $0.clientId == clientId }
    }

    private func run(_ item: SupOutgoing) {
        sendTasks[item.clientId]?.cancel()
        sendTasks[item.clientId] = Task { [weak self] in
            guard let self else { return }
            let clientId = item.clientId
            do {
                var uploadId = item.uploadId
                if let file = item.file, uploadId == nil {
                    let grant = try await SupportAPI.requestUpload(ticketId: self.ticketId, file: file)
                    _ = try await SupUploader.put(
                        fileURL: file.url,
                        grant: grant,
                        contentType: file.contentType
                    ) { progress in
                        Task { @MainActor [weak self] in self?.setProgress(clientId, progress) }
                    }
                    uploadId = grant.uploadId
                    if let index = self.index(of: clientId) {
                        self.outgoing[index].uploadId = grant.uploadId
                    }
                }
                let message = try await SupportAPI.send(
                    ticketId: self.ticketId,
                    clientId: clientId,
                    text: item.text,
                    uploadId: uploadId
                )
                if let file = item.file { try? FileManager.default.removeItem(at: file.url) }
                self.merge([message])
                self.outgoing.removeAll { $0.clientId == clientId }
            } catch is CancellationError {
                // Descartado pelo terapeuta.
            } catch let error as APIError where error.statusCode == 409 {
                // Atendimento finalizado enquanto escrevia.
                self.fail(clientId, error.message)
                if let fresh = try? await SupportAPI.ticket(id: self.ticketId) { self.ticket = fresh }
            } catch {
                self.fail(clientId, self.texto(de: error, padrao: "Não enviada. Confira a conexão."))
            }
            self.sendTasks[clientId] = nil
        }
    }

    private func setProgress(_ clientId: String, _ progress: Double) {
        guard let index = index(of: clientId), case let .sending(atual) = outgoing[index].state else { return }
        // Sem este passo mínimo, cada pedaço enviado redesenharia a conversa.
        if let atual, progress < 1, progress - atual < 0.02 { return }
        outgoing[index].state = .sending(progress: progress)
    }

    private func fail(_ clientId: String, _ message: String) {
        guard let index = index(of: clientId) else { return }
        outgoing[index].state = .failed(message)
        Haptics.warning()
    }

    private func index(of clientId: String) -> Int? {
        outgoing.firstIndex { $0.clientId == clientId }
    }

    /// URL assinada venceu: pede outra e atualiza a mensagem.
    func renewAttachment(messageId: String) async -> SupAttachment? {
        guard let fresh = try? await SupportAPI.attachmentURL(messageId: messageId),
              let index = messages.firstIndex(where: { $0.id == messageId }),
              var attachment = messages[index].attachment
        else { return nil }
        attachment.url = fresh.url
        attachment.expiresAt = fresh.expiresAt
        messages[index].attachment = attachment
        return attachment
    }

    private func texto(de error: Error, padrao: String) -> String {
        (error as? APIError)?.message ?? (error as? SupPrepError)?.message ?? padrao
    }

    private static func newClientId() -> String {
        "ios-\(UUID().uuidString.lowercased())"
    }
}

// MARK: - Preparação de mídia

/// Vídeo da galeria copiado pra um arquivo nosso (o do PhotosPicker some logo).
struct SupMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let destino = try SupMediaPrep.tempURL(ext: ext)
            try FileManager.default.copyItem(at: received.file, to: destino)
            return SupMovie(url: destino)
        }
    }
}

enum SupMediaPrep {
    static func tempURL(ext: String) throws -> URL {
        let pasta = FileManager.default.temporaryDirectory.appendingPathComponent("suporte", isDirectory: true)
        try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        return pasta.appendingPathComponent("\(UUID().uuidString).\(ext)")
    }

    static let documentTypes: [UTType] = {
        let tipos: [UTType?] = [
            .pdf, .plainText, .commaSeparatedText,
            UTType(filenameExtension: "xlsx"), UTType(filenameExtension: "docx"),
        ]
        return tipos.compactMap { $0 }
    }()

    static func mimeForDocument(_ ext: String) -> String? {
        [
            "pdf": "application/pdf",
            "txt": "text/plain",
            "csv": "text/csv",
            "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        ][ext.lowercased()]
    }

    static func fromPhotosItem(_ item: PhotosPickerItem) async throws -> SupLocalFile {
        if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
            return try await video(from: item)
        }
        return try await image(from: item)
    }

    // MARK: Foto

    static func image(from item: PhotosPickerItem) async throws -> SupLocalFile {
        guard let data = try await item.loadTransferable(type: Data.self) else {
            throw SupPrepError("Não foi possível ler a imagem escolhida.")
        }
        // GIF passa direto (redesenhar perderia a animação).
        if item.supportedContentTypes.contains(where: { $0.conforms(to: .gif) }) {
            let url = try tempURL(ext: "gif")
            try data.write(to: url, options: .atomic)
            let imagem = UIImage(data: data)
            return SupLocalFile(
                url: url, kind: .image, contentType: "image/gif", fileName: "imagem.gif",
                sizeBytes: data.count,
                width: imagem.map { Int($0.size.width * $0.scale) },
                height: imagem.map { Int($0.size.height * $0.scale) },
                preview: imagem.map { resize($0, maxSide: 600) }
            )
        }
        guard let imagem = UIImage(data: data) else {
            throw SupPrepError("Esse formato de imagem não é suportado.")
        }
        return try jpeg(from: imagem)
    }

    /// HEIC e PNG viram JPEG 0,85 com o lado maior em até 2560 px.
    static func jpeg(from image: UIImage) throws -> SupLocalFile {
        let ajustada = resize(image, maxSide: 2560)
        guard let data = ajustada.jpegData(compressionQuality: 0.85) else {
            throw SupPrepError("Não foi possível preparar a imagem.")
        }
        let url = try tempURL(ext: "jpg")
        try data.write(to: url, options: .atomic)
        return SupLocalFile(
            url: url, kind: .image, contentType: "image/jpeg", fileName: "foto.jpg",
            sizeBytes: data.count,
            width: Int(ajustada.size.width * ajustada.scale),
            height: Int(ajustada.size.height * ajustada.scale),
            preview: resize(ajustada, maxSide: 600)
        )
    }

    /// Redesenha já com a orientação aplicada.
    static func resize(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let largura = image.size.width * image.scale
        let altura = image.size.height * image.scale
        let maior = max(largura, altura)
        let fator = maior > maxSide ? maxSide / maior : 1
        let alvo = CGSize(width: (largura * fator).rounded(), height: (altura * fator).rounded())
        let formato = UIGraphicsImageRendererFormat.default()
        formato.scale = 1
        return UIGraphicsImageRenderer(size: alvo, format: formato).image { _ in
            image.draw(in: CGRect(origin: .zero, size: alvo))
        }
    }

    // MARK: Vídeo

    /// Exporta pra MP4 H.264 — o formato que o navegador do painel toca.
    static func video(from item: PhotosPickerItem) async throws -> SupLocalFile {
        guard let movie = try await item.loadTransferable(type: SupMovie.self) else {
            throw SupPrepError("Não foi possível ler o vídeo escolhido.")
        }
        defer { try? FileManager.default.removeItem(at: movie.url) }

        let asset = AVURLAsset(url: movie.url)
        var saida = try await export(asset, preset: AVAssetExportPreset1280x720)
        var tamanho = fileSize(saida)
        if tamanho > SupUploadKind.video.maxBytes {
            try? FileManager.default.removeItem(at: saida)
            saida = try await export(asset, preset: AVAssetExportPresetMediumQuality)
            tamanho = fileSize(saida)
        }
        guard tamanho <= SupUploadKind.video.maxBytes else {
            try? FileManager.default.removeItem(at: saida)
            throw SupPrepError("Vídeo muito grande (máximo 50 MB). Tente um trecho mais curto.")
        }

        let exportado = AVURLAsset(url: saida)
        let duracao = (try? await exportado.load(.duration)).map { CMTimeGetSeconds($0) } ?? 0
        var largura: Int?
        var altura: Int?
        if let trilha = try? await exportado.loadTracks(withMediaType: .video).first,
           let (tamanhoNatural, transformacao) = try? await trilha.load(.naturalSize, .preferredTransform) {
            let caixa = CGRect(origin: .zero, size: tamanhoNatural).applying(transformacao)
            largura = Int(abs(caixa.width))
            altura = Int(abs(caixa.height))
        }
        let gerador = AVAssetImageGenerator(asset: exportado)
        gerador.appliesPreferredTrackTransform = true
        gerador.maximumSize = CGSize(width: 600, height: 600)
        let capa = try? await gerador.image(at: .zero).image

        return SupLocalFile(
            url: saida, kind: .video, contentType: "video/mp4", fileName: "video.mp4",
            sizeBytes: tamanho,
            durationMs: duracao.isFinite ? Int(duracao * 1000) : nil,
            width: largura, height: altura,
            preview: capa.map { UIImage(cgImage: $0) }
        )
    }

    private static func export(_ asset: AVURLAsset, preset: String) async throws -> URL {
        guard let sessao = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw SupPrepError("Não foi possível preparar o vídeo.")
        }
        let saida = try tempURL(ext: "mp4")
        sessao.shouldOptimizeForNetworkUse = true
        if #available(iOS 18.0, *) {
            do {
                try await sessao.export(to: saida, as: .mp4)
            } catch {
                throw SupPrepError("Não foi possível preparar o vídeo.")
            }
        } else {
            sessao.outputURL = saida
            sessao.outputFileType = .mp4
            await withCheckedContinuation { continuation in
                sessao.exportAsynchronously { continuation.resume() }
            }
            guard sessao.status == .completed else {
                throw SupPrepError("Não foi possível preparar o vídeo.")
            }
        }
        return saida
    }

    private static func fileSize(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    // MARK: Documento

    static func fromImportedFile(_ origem: URL) throws -> SupLocalFile {
        let acesso = origem.startAccessingSecurityScopedResource()
        defer { if acesso { origem.stopAccessingSecurityScopedResource() } }
        let ext = origem.pathExtension.lowercased()
        guard let mime = mimeForDocument(ext) else {
            throw SupPrepError("Esse tipo de arquivo não é aceito. Envie PDF, TXT, CSV, XLSX ou DOCX.")
        }
        let destino = try tempURL(ext: ext)
        try FileManager.default.copyItem(at: origem, to: destino)
        return SupLocalFile(
            url: destino, kind: .file, contentType: mime,
            fileName: origem.lastPathComponent,
            sizeBytes: fileSize(destino)
        )
    }
}

// MARK: - Gravação de áudio (AAC .m4a)

@MainActor
@Observable
final class SupAudioRecorder {
    enum Phase: Equatable { case idle, recording }

    static let limit: TimeInterval = 300

    private(set) var phase: Phase = .idle
    private(set) var elapsed: TimeInterval = 0

    /// Chegou aos 5 min: quem mostra a tela decide o que fazer (envia).
    @ObservationIgnored var onLimitReached: (() -> Void)?

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var fileURL: URL?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private lazy var delegateProxy = SupRecorderDelegate { [weak self] recorder in
        guard let self, self.phase == .recording, self.recorder === recorder else { return }
        self.onLimitReached?()
    }

    func requestPermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        case .undetermined: return await AVAudioApplication.requestRecordPermission()
        @unknown default: return false
        }
    }

    func start() throws {
        let sessao = AVAudioSession.sharedInstance()
        try sessao.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try sessao.setActive(true)
        let url = try SupMediaPrep.tempURL(ext: "m4a")
        let ajustes: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        let novo = try AVAudioRecorder(url: url, settings: ajustes)
        novo.delegate = delegateProxy
        guard novo.record(forDuration: Self.limit) else {
            throw SupPrepError("Não foi possível começar a gravação.")
        }
        recorder = novo
        fileURL = url
        elapsed = 0
        phase = .recording
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard let self, let atual = self.recorder else { return }
                if atual.isRecording { self.elapsed = atual.currentTime }
            }
        }
    }

    /// Para e devolve o arquivo; nil se ficou curto demais (toque sem querer).
    func finish() -> SupLocalFile? {
        guard let recorder, let fileURL else { return nil }
        let duracao = max(recorder.isRecording ? recorder.currentTime : 0, elapsed)
        recorder.stop()
        limpar()
        guard duracao >= 1 else {
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
        let tamanho = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return SupLocalFile(
            url: fileURL, kind: .audio, contentType: "audio/x-m4a", fileName: "audio.m4a",
            sizeBytes: tamanho,
            durationMs: Int(min(duracao, Self.limit) * 1000)
        )
    }

    func cancel() {
        recorder?.stop()
        recorder?.deleteRecording()
        limpar()
    }

    private func limpar() {
        ticker?.cancel()
        ticker = nil
        recorder = nil
        fileURL = nil
        phase = .idle
        elapsed = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// `AVAudioRecorderDelegate` exige NSObject; o gravador observável não é.
private final class SupRecorderDelegate: NSObject, AVAudioRecorderDelegate {
    private let onFinish: @MainActor (AVAudioRecorder) -> Void

    init(onFinish: @escaping @MainActor (AVAudioRecorder) -> Void) {
        self.onFinish = onFinish
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in self.onFinish(recorder) }
    }
}

// MARK: - Reprodução de áudio (um de cada vez)

@MainActor
@Observable
final class SupAudioPlayback {
    static let shared = SupAudioPlayback()

    private(set) var currentId: String?
    private(set) var isPlaying = false
    private(set) var progress: Double = 0
    private(set) var position: TimeInterval = 0

    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?

    func toggle(id: String, url: URL, durationMs: Int?) {
        if currentId == id, let player {
            if isPlaying {
                player.pause()
                isPlaying = false
            } else {
                if progress >= 0.999 { player.seek(to: .zero) }
                player.play()
                isPlaying = true
            }
            return
        }
        stop()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)

        let item = AVPlayerItem(url: url)
        let novo = AVPlayer(playerItem: item)
        let totalInformado = durationMs.map { Double($0) / 1000 } ?? 0
        player = novo
        currentId = id
        timeObserver = novo.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] tempo in
            MainActor.assumeIsolated {
                guard let self else { return }
                let segundos = tempo.seconds.isFinite ? tempo.seconds : 0
                let duracaoItem = item.duration.seconds
                let total = duracaoItem.isFinite && duracaoItem > 0 ? duracaoItem : totalInformado
                self.position = segundos
                self.progress = total > 0 ? min(segundos / total, 1) : 0
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isPlaying = false
                self?.progress = 1
            }
        }
        novo.play()
        isPlaying = true
    }

    func stop() {
        player?.pause()
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeObserver = nil
        endObserver = nil
        player = nil
        currentId = nil
        isPlaying = false
        progress = 0
        position = 0
    }
}
