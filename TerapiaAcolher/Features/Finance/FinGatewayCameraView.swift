import SwiftUI
import UIKit

// MARK: - Captura ao vivo de documento e selfie
//
// O app não tinha câmera: tudo entrava por PhotosPicker. Documento de abertura
// de conta precisa ser capturado na hora — foto de galeria é o caminho óbvio
// pra mandar a foto de outra pessoa. No simulador não existe câmera
// (`isAvailable == false`) e a tela cai no PhotosPicker com `captureMode=upload`.

struct FinGatewayCameraView: UIViewControllerRepresentable {
    enum Modo {
        case documento
        case selfie

        var instrucoes: [String] {
            switch self {
            case .documento:
                ["Encaixe o documento na moldura", "Evite reflexo e sombra"]
            case .selfie:
                ["Centralize o rosto", "Olhe para a câmera", "Sorria de leve"]
            }
        }

        /// Selfie pede duas fotos: a diferença entre elas é o sinal de vida.
        var fotos: Int { self == .selfie ? 2 : 1 }
    }

    let modo: Modo
    let titulo: String
    let onCapture: ([UIImage]) -> Void
    let onCancel: () -> Void

    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(modo: modo, titulo: titulo, onCapture: onCapture, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = false
        picker.showsCameraControls = false
        picker.cameraCaptureMode = .photo
        if modo == .selfie,
           UIImagePickerController.isCameraDeviceAvailable(.front) {
            picker.cameraDevice = .front
        }
        picker.delegate = context.coordinator
        let overlay = context.coordinator.makeOverlay(bounds: picker.view.bounds)
        picker.cameraOverlayView = overlay
        context.coordinator.picker = picker
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    static func dismantleUIViewController(_ controller: UIImagePickerController, coordinator: Coordinator) {
        MainActor.assumeIsolated { coordinator.pararCiclo() }
    }

    // MARK: Coordinator (moldura, instruções e disparo)

    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let modo: Modo
        private let titulo: String
        private let onCapture: ([UIImage]) -> Void
        private let onCancel: () -> Void

        weak var picker: UIImagePickerController?
        private var fotos: [UIImage] = []
        private var instrucaoIndex = 0
        private var ciclo: Timer?

        private let instrucaoLabel = UILabel()
        private let contadorLabel = UILabel()
        private let disparo = UIButton(type: .custom)
        private let spinner = UIActivityIndicatorView(style: .medium)

        init(
            modo: Modo,
            titulo: String,
            onCapture: @escaping ([UIImage]) -> Void,
            onCancel: @escaping () -> Void
        ) {
            self.modo = modo
            self.titulo = titulo
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func pararCiclo() {
            ciclo?.invalidate()
            ciclo = nil
        }

        // MARK: Overlay

        func makeOverlay(bounds: CGRect) -> UIView {
            let overlay = UIView(frame: bounds)
            overlay.backgroundColor = .clear
            overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]

            // Escurece tudo menos a moldura — a janela clara diz sozinha onde
            // encaixar, sem precisar de texto explicando.
            let escuro = UIView(frame: bounds)
            escuro.backgroundColor = UIColor.black.withAlphaComponent(0.55)
            escuro.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            escuro.isUserInteractionEnabled = false

            let janela = molduraRect(in: bounds)
            let caminho = UIBezierPath(rect: bounds)
            let recorte = modo == .selfie
                ? UIBezierPath(ovalIn: janela)
                : UIBezierPath(roundedRect: janela, cornerRadius: 16)
            caminho.append(recorte.reversing())
            let mascara = CAShapeLayer()
            mascara.path = caminho.cgPath
            escuro.layer.mask = mascara
            overlay.addSubview(escuro)

            let borda = CAShapeLayer()
            borda.path = recorte.cgPath
            borda.strokeColor = UIColor.white.withAlphaComponent(0.9).cgColor
            borda.fillColor = UIColor.clear.cgColor
            borda.lineWidth = 2
            borda.lineDashPattern = modo == .selfie ? nil : [10, 6]
            overlay.layer.addSublayer(borda)

            // Título
            let tituloLabel = UILabel()
            tituloLabel.text = titulo
            tituloLabel.textColor = .white
            tituloLabel.font = .systemFont(ofSize: 17, weight: .semibold)
            tituloLabel.textAlignment = .center
            tituloLabel.frame = CGRect(x: 16, y: 64, width: bounds.width - 32, height: 24)
            tituloLabel.autoresizingMask = [.flexibleWidth, .flexibleBottomMargin]
            overlay.addSubview(tituloLabel)

            // Instrução (muda sozinha e a cada captura)
            instrucaoLabel.text = modo.instrucoes.first
            instrucaoLabel.textColor = .white
            instrucaoLabel.font = .systemFont(ofSize: 15, weight: .medium)
            instrucaoLabel.textAlignment = .center
            instrucaoLabel.numberOfLines = 2
            instrucaoLabel.frame = CGRect(
                x: 24,
                y: janela.maxY + 20,
                width: bounds.width - 48,
                height: 44
            )
            instrucaoLabel.autoresizingMask = [.flexibleWidth, .flexibleTopMargin, .flexibleBottomMargin]
            overlay.addSubview(instrucaoLabel)

            contadorLabel.text = contadorTexto
            contadorLabel.textColor = UIColor.white.withAlphaComponent(0.75)
            contadorLabel.font = .systemFont(ofSize: 13, weight: .semibold)
            contadorLabel.textAlignment = .center
            contadorLabel.frame = CGRect(
                x: 24,
                y: instrucaoLabel.frame.maxY + 2,
                width: bounds.width - 48,
                height: 18
            )
            contadorLabel.autoresizingMask = [.flexibleWidth, .flexibleTopMargin, .flexibleBottomMargin]
            contadorLabel.isHidden = modo.fotos == 1
            overlay.addSubview(contadorLabel)

            // Disparo
            let tamanho: CGFloat = 72
            disparo.frame = CGRect(
                x: (bounds.width - tamanho) / 2,
                y: bounds.height - tamanho - 54,
                width: tamanho,
                height: tamanho
            )
            disparo.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin, .flexibleTopMargin]
            disparo.backgroundColor = .white
            disparo.layer.cornerRadius = tamanho / 2
            disparo.layer.borderWidth = 4
            disparo.layer.borderColor = UIColor.white.withAlphaComponent(0.45).cgColor
            disparo.accessibilityLabel = "Tirar foto"
            disparo.addTarget(self, action: #selector(tocouDisparo), for: .touchUpInside)
            overlay.addSubview(disparo)

            spinner.color = .darkGray
            spinner.center = CGPoint(x: disparo.bounds.midX, y: disparo.bounds.midY)
            spinner.hidesWhenStopped = true
            disparo.addSubview(spinner)

            // Cancelar
            let cancelar = UIButton(type: .system)
            cancelar.setTitle("Cancelar", for: .normal)
            cancelar.setTitleColor(.white, for: .normal)
            cancelar.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
            cancelar.frame = CGRect(x: 16, y: disparo.frame.midY - 22, width: 100, height: 44)
            cancelar.autoresizingMask = [.flexibleRightMargin, .flexibleTopMargin]
            cancelar.addTarget(self, action: #selector(tocouCancelar), for: .touchUpInside)
            overlay.addSubview(cancelar)

            iniciarCiclo()
            return overlay
        }

        private func molduraRect(in bounds: CGRect) -> CGRect {
            switch modo {
            case .documento:
                // Cartão na horizontal (proporção ~85,6 × 54 mm).
                let largura = bounds.width - 48
                let altura = largura * 0.63
                return CGRect(
                    x: 24,
                    y: bounds.midY - altura / 2 - 30,
                    width: largura,
                    height: altura
                )
            case .selfie:
                let largura = bounds.width * 0.66
                let altura = largura * 1.3
                return CGRect(
                    x: (bounds.width - largura) / 2,
                    y: bounds.midY - altura / 2 - 40,
                    width: largura,
                    height: altura
                )
            }
        }

        private var contadorTexto: String {
            "Foto \(min(fotos.count + 1, modo.fotos)) de \(modo.fotos)"
        }

        /// As instruções passam sozinhas enquanto ele se posiciona.
        private func iniciarCiclo() {
            guard modo.instrucoes.count > 1 else { return }
            ciclo?.invalidate()
            // Alvo/seletor em vez de closure: o Timer roda no run loop
            // principal e nada precisa atravessar fronteira de concorrência.
            ciclo = Timer.scheduledTimer(
                timeInterval: 2.6,
                target: self,
                selector: #selector(cicloDisparou),
                userInfo: nil,
                repeats: true
            )
        }

        @objc private func cicloDisparou() {
            avancarInstrucao()
        }

        private func avancarInstrucao() {
            instrucaoIndex = (instrucaoIndex + 1) % modo.instrucoes.count
            UIView.transition(with: instrucaoLabel, duration: 0.2, options: .transitionCrossDissolve) {
                self.instrucaoLabel.text = self.modo.instrucoes[self.instrucaoIndex]
            }
        }

        // MARK: Ações

        @objc private func tocouDisparo() {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            disparo.isEnabled = false
            spinner.startAnimating()
            picker?.takePicture()
        }

        @objc private func tocouCancelar() {
            pararCiclo()
            onCancel()
        }

        // MARK: Delegate

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            spinner.stopAnimating()
            disparo.isEnabled = true
            guard let image = info[.originalImage] as? UIImage else { return }
            fotos.append(image)
            if fotos.count >= modo.fotos {
                pararCiclo()
                onCapture(fotos)
                return
            }
            contadorLabel.text = contadorTexto
            avancarInstrucao()
            Haptics.success()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            pararCiclo()
            onCancel()
        }
    }
}

// MARK: - Sinal de vida calculado no aparelho
//
// Sem serviço de liveness contratado, o que dá pra afirmar com honestidade é
// "as duas fotos são de uma cena que se mexeu entre um clique e outro". Duas
// fotos idênticas (a mesma imagem reenviada) pontuam perto de zero.

enum GwLiveness {
    static func score(first: UIImage, second: UIImage) -> Double {
        guard let a = miniatura(first), let b = miniatura(second) else { return 0.5 }
        let soma = zip(a, b).reduce(0.0) { total, par in
            total + abs(Double(par.0) - Double(par.1))
        }
        let diferenca = soma / Double(a.count) / 255.0
        // Praticamente sem diferença = provavelmente a mesma foto duas vezes.
        guard diferenca > 0.005 else { return 0.2 }
        return min(1.0, max(0.85, diferenca / 0.15))
    }

    private static let lado = 32

    private static func miniatura(_ image: UIImage) -> [UInt8]? {
        guard let cg = image.cgImage else { return nil }
        var bytes = [UInt8](repeating: 0, count: lado * lado)
        let espaco = CGColorSpaceCreateDeviceGray()
        let ok = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress,
                  let contexto = CGContext(
                      data: base,
                      width: lado,
                      height: lado,
                      bitsPerComponent: 8,
                      bytesPerRow: lado,
                      space: espaco,
                      bitmapInfo: CGImageAlphaInfo.none.rawValue
                  )
            else { return false }
            contexto.draw(cg, in: CGRect(x: 0, y: 0, width: lado, height: lado))
            return true
        }
        return ok ? bytes : nil
    }
}

// MARK: - Compressão comum a documentos e selfie

enum GwImage {
    /// Mesmo tratamento da foto de paciente: lado máximo 1024 e JPEG 0.8.
    /// O servidor aceita 10 MB, mas mandar 4 MB de câmera por documento só
    /// gasta a franquia de dados do terapeuta.
    static let ladoMaximo: CGFloat = 1024

    static func downscaledJPEG(_ image: UIImage) -> Data? {
        let maior = max(image.size.width, image.size.height)
        let escala = maior > ladoMaximo ? ladoMaximo / maior : 1
        let alvo = CGSize(
            width: (image.size.width * escala).rounded(),
            height: (image.size.height * escala).rounded()
        )
        let renderer = UIGraphicsImageRenderer(size: alvo)
        let redimensionada = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: alvo))
        }
        return redimensionada.jpegData(compressionQuality: 0.8)
    }
}
