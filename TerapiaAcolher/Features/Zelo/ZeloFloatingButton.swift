import SwiftUI

/// Botão do Zelo: canto inferior direito por padrão, arrastável, preso à
/// tela, posição lembrada. Tocar abre o chat; terminar de arrastar não abre.
struct ZeloFloatingButton: View {
    @State private var zelo = ZeloStore.shared
    @State private var arrasto: CGSize = .zero
    @State private var arrastando = false

    private let tamanho: CGFloat = 58
    private let margem: CGFloat = 16
    /// Espaço sempre livre acima do rodapé (2026-10-07): as telas têm botão
    /// flutuante no canto ("+ Novo prontuário", "+" de pacientes, "Criar
    /// cobrança"…) e o Zelo ficava por cima deles. Como no web, o Zelo mora
    /// acima dessa faixa.
    private let folgaDosBotoesDaTela: CGFloat = 76

    var body: some View {
        GeometryReader { geo in
            let area = CGRect(
                x: margem,
                y: margem + 60,
                width: max(1, geo.size.width - tamanho - margem * 2),
                height: max(1, geo.size.height - tamanho - margem * 2 - 60 - folgaDosBotoesDaTela - zelo.folgaInferior)
            )
            let base = CGPoint(
                x: area.minX + area.width * zelo.posicao.x,
                y: area.minY + area.height * zelo.posicao.y
            )
            if zelo.ativo {
                botao
                    .position(
                        x: clamp(base.x + arrasto.width, area.minX, area.maxX) + tamanho / 2,
                        y: clamp(base.y + arrasto.height, area.minY, area.maxY) + tamanho / 2
                    )
                    .gesture(
                        DragGesture(minimumDistance: 6)
                            .onChanged { v in
                                arrastando = true
                                arrasto = v.translation
                            }
                            .onEnded { v in
                                let x = clamp(base.x + v.translation.width, area.minX, area.maxX)
                                let y = clamp(base.y + v.translation.height, area.minY, area.maxY)
                                zelo.posicao = CGPoint(
                                    x: (x - area.minX) / area.width,
                                    y: (y - area.minY) / area.height
                                )
                                arrasto = .zero
                                // Solta sem abrir: o toque seguinte é que abre.
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { arrastando = false }
                            }
                    )
            }
        }
        .task { if !zelo.carregou { await zelo.carregarStatus() } }
        .sheet(isPresented: $zelo.aberto) {
            ZeloChatView()
                .presentationDragIndicator(.visible)
        }
    }

    private var botao: some View {
        Button {
            guard !arrastando else { return }
            Haptics.tap()
            zelo.aberto = true
        } label: {
            ZeloAvatar(size: tamanho)
                .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 2))
                .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Abrir o Zelo")
        .accessibilityIdentifier("zeloBotao")
    }

    private func clamp(_ v: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat { min(max(v, a), b) }
}
