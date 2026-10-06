import PhotosUI
import SwiftUI
import VisionKit

// MARK: - Cadastro pela foto da ficha (2026-10-06)
//
// A terapeuta escaneia (ou escolhe da galeria) a ficha em papel; a API lê só os
// dados cadastrais com IA e o wizard abre preenchido para ela conferir. Nada é
// salvo sem ela tocar em "Cadastrar paciente". A imagem fica só em memória —
// e vai para os Arquivos do paciente apenas se ela ligar o interruptor.

struct PatientIntakeResult: Decodable {
    struct Campos: Decodable {
        let nome: String?
        let cpf: String?
        let dataNascimento: String?
        let email: String?
        let whatsapp: String?
        let responsavelNome: String?
        let responsavelContato: String?
    }

    let campos: Campos
    /// Campos que a terapeuta deve conferir (dúvida da IA ou formato inválido).
    let conferir: [String]
    let grupoId: String?
    let restantes: Int?
}

enum PatientIntakeAPI {
    /// Liga junto com a IA no servidor (Gemini ou Haiku de reserva).
    static func isEnabled() async -> Bool {
        (try? await RecordsAPI.aiStatus().intakeEnabled) ?? false
    }

    static func read(_ fotos: [Data]) async throws -> PatientIntakeResult {
        try await APIClient.shared.uploadMany(
            "patients/intake",
            files: fotos.enumerated().map { (data: $0.element, fileName: "ficha-\($0.offset + 1).jpg", mimeType: "image/jpeg") },
            fieldName: "fotos"
        )
    }
}

/// Reduz a foto antes de enviar. 1600 px no lado maior é o ponto medido: com
/// ~900 px a IA trocou dígitos de CPF e data; acima disso só aumenta o custo.
enum IntakeImage {
    static let maxSide: CGFloat = 1600

    static func jpeg(from image: UIImage) -> Data? {
        let size = image.size
        let longest = max(size.width, size.height)
        let scale = longest > maxSide ? maxSide / longest : 1
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.75)
    }
}

/// Scanner de documentos do iOS: recorta a folha e endireita a perspectiva.
struct FichaScannerView: UIViewControllerRepresentable {
    let onFinish: ([UIImage]) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_: VNDocumentCameraViewController, context _: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: FichaScannerView
        init(_ parent: FichaScannerView) { self.parent = parent }

        func documentCameraViewController(_: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            // Frente e verso: no máximo 2 páginas.
            let pages = (0 ..< min(scan.pageCount, 2)).map { scan.imageOfPage(at: $0) }
            parent.onFinish(pages)
        }

        func documentCameraViewControllerDidCancel(_: VNDocumentCameraViewController) {
            parent.onCancel()
        }

        func documentCameraViewController(_: VNDocumentCameraViewController, didFailWithError _: Error) {
            parent.onCancel()
        }
    }
}

/// Cartão no começo do wizard: escanear ou escolher a ficha, ler, e o estado.
struct PatientIntakeCard: View {
    @Bindable var model: PatientFormViewModel
    @State private var showScanner = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .frame(width: 36, height: 36)
                    .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Preencher com a foto da ficha")
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(subtitle)
                        .font(Theme.body(12.5))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if model.isReadingIntake {
                HStack(spacing: 10) {
                    ProgressView().tint(Theme.primary)
                    Text("Lendo a ficha…")
                        .font(Theme.body(14, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
                .accessibilityIdentifier("intakeReading")
            } else {
                HStack(spacing: 10) {
                    if VNDocumentCameraViewController.isSupported {
                        intakeButton(title: "Escanear a ficha", icon: "camera.viewfinder", id: "intakeScan") {
                            Haptics.tap()
                            showScanner = true
                        }
                    }
                    intakeButton(title: "Escolher da galeria", icon: "photo.on.rectangle", id: "intakeGallery") {
                        Haptics.tap()
                        showPicker = true
                    }
                }
            }

            if let error = model.intakeError {
                Text(error)
                    .font(Theme.body(13, weight: .medium))
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                if model.intakeLimitReached {
                    ManageAccountButton(style: .compact, tint: Theme.primary)
                }
            }

            if !model.intakeImages.isEmpty {
                Divider().overlay(Theme.border)
                Toggle(isOn: $model.keepIntakePhoto) {
                    Text("Guardar a foto da ficha nos arquivos do paciente")
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.textPrimary)
                }
                .tint(Theme.primary)
                .accessibilityIdentifier("intakeKeepPhoto")
            }
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).stroke(Theme.border, lineWidth: 1))
        .fullScreenCover(isPresented: $showScanner) {
            FichaScannerView(
                onFinish: { pages in
                    showScanner = false
                    read(pages)
                },
                onCancel: { showScanner = false }
            )
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showPicker, selection: $pickerItems, maxSelectionCount: 2, matching: .images)
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                var images: [UIImage] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        images.append(image)
                    }
                }
                pickerItems = []
                read(images)
            }
        }
    }

    private var subtitle: String {
        if model.intakeApplied {
            return "Ficha lida. Confira os dados nos próximos passos antes de salvar."
        }
        return "A IA lê nome, CPF, nascimento, contato e responsável. Você confere antes de salvar."
    }

    private func read(_ images: [UIImage]) {
        let fotos = images.compactMap(IntakeImage.jpeg(from:))
        guard !fotos.isEmpty else { return }
        Task { await model.readIntake(fotos) }
    }

    private func intakeButton(title: String, icon: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 14, weight: .semibold))
                Text(title).font(Theme.body(13.5, weight: .semibold))
            }
            .foregroundStyle(Theme.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

/// Aviso no topo do passo de dados depois da leitura.
struct IntakeReviewNotice: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.warning)
            Text("Confira os dados antes de salvar. Os campos destacados precisam de atenção.")
                .font(Theme.body(13, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.warningSoft, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("intakeReviewNotice")
    }
}

/// "Confira este campo" embaixo do campo que a IA marcou.
struct IntakeCheckHint: View {
    var body: some View {
        Label("Confira este campo", systemImage: "exclamationmark.circle.fill")
            .font(Theme.body(12, weight: .semibold))
            .foregroundStyle(Theme.warning)
            .padding(.bottom, 4)
    }
}
