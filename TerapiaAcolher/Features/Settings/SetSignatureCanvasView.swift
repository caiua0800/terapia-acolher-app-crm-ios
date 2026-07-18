import SwiftUI

/// Canvas de assinatura — desenho com o dedo, renderizado para PNG
/// e enviado via POST settings/signature pelo chamador.
struct SetSignatureCanvasView: View {
    var onDone: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var strokes: [[CGPoint]] = []
    @State private var currentStroke: [CGPoint] = []
    @State private var canvasSize: CGSize = .init(width: 350, height: 220)

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 20) {
                    Text("Assine com o dedo no quadro abaixo, como você assina no papel.")
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)

                    GeometryReader { geo in
                        drawing
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                                    .stroke(Theme.border, lineWidth: 1)
                            )
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        currentStroke.append(value.location)
                                    }
                                    .onEnded { _ in
                                        if !currentStroke.isEmpty {
                                            strokes.append(currentStroke)
                                            currentStroke = []
                                        }
                                    }
                            )
                            .onAppear { canvasSize = geo.size }
                    }
                    .frame(height: 220)

                    Button {
                        strokes = []
                        currentStroke = []
                    } label: {
                        Label("Limpar", systemImage: "eraser")
                            .font(Theme.body(14, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .disabled(strokes.isEmpty && currentStroke.isEmpty)

                    Spacer()

                    PrimaryButton(title: "Usar esta assinatura", isEnabled: !strokes.isEmpty) {
                        if let png = renderPNG() {
                            onDone(png)
                            dismiss()
                        }
                    }
                }
                .padding(Theme.screenPadding)
            }
            .setToolbarTitle("Desenhar assinatura")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private var drawing: some View {
        Canvas { context, _ in
            for stroke in strokes + (currentStroke.isEmpty ? [] : [currentStroke]) {
                guard let first = stroke.first else { continue }
                var path = Path()
                path.move(to: first)
                for point in stroke.dropFirst() {
                    path.addLine(to: point)
                }
                context.stroke(
                    path,
                    with: .color(Color(hex: 0x2D3436)),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                )
            }
        }
    }

    @MainActor
    private func renderPNG() -> Data? {
        let content = drawing
            .frame(width: canvasSize.width, height: canvasSize.height)
            .background(Color.white)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        return renderer.uiImage?.pngData()
    }
}
