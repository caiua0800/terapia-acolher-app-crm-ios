import Foundation
import Network
import Observation
import SwiftUI

/// Estado da conexão do aparelho.
///
/// O terapeuta abre este app entre sessões, andando pelo consultório, com o
/// celular pulando de Wi-Fi para 4G. Sem isto, cada tela dava seu próprio erro
/// genérico ("não foi possível carregar") e ele não tinha como saber se o
/// problema era dele ou nosso — e ficava tentando de novo sem sair do lugar.
@Observable
@MainActor
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    /// Começa em `true` de propósito: assumir "sem internet" antes da primeira
    /// leitura faria a faixa piscar na abertura de todo mundo.
    private(set) var isOnline = true

    private let monitor = NWPathMonitor()
    private let fila = DispatchQueue(label: "br.com.terapiaacolher.rede")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                guard let self, self.isOnline != online else { return }
                self.isOnline = online
            }
        }
        monitor.start(queue: fila)
    }
}

/// Faixa que desce do topo quando a conexão cai.
///
/// Fica presa ao topo da casca do app, não a cada tela: o aviso é do aparelho,
/// não da tela — repeti-lo em cada uma seria ruído e trabalho duplicado.
struct OfflineBanner: View {
    @State private var monitor = NetworkMonitor.shared

    var body: some View {
        VStack(spacing: 0) {
            if !monitor.isOnline {
                HStack(spacing: 8) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Sem conexão — mostrando o que já foi carregado")
                        .font(Theme.body(12, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(Theme.textPrimary.opacity(0.92))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer(minLength: 0)
        }
        .animation(.easeInOut(duration: 0.25), value: monitor.isOnline)
        .allowsHitTesting(false)
    }
}
