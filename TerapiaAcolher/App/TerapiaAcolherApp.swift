import SwiftUI

@main
struct TerapiaAcolherApp: App {
    @State private var session = SessionStore.shared

    init() {
        // Suporte a testes de UI: estado limpo de sessão.
        if CommandLine.arguments.contains("--reset-session") {
            Keychain.delete("accessToken")
            Keychain.delete("refreshToken")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .tint(Theme.primary)
        }
    }
}

/// Raiz: splash de boot → login ou shell autenticado.
struct RootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        Group {
            if session.isBooting {
                BootSplashView()
            } else if session.isAuthenticated {
                MainShellView()
            } else {
                LoginFlowView()
            }
        }
        .task { await session.boot() }
    }
}

struct BootSplashView: View {
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 16) {
                Circle()
                    .fill(Theme.primary.opacity(0.18))
                    .frame(width: 96, height: 96)
                    .overlay(
                        Image(systemName: "heart.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Theme.primary)
                    )
                Text("Terapia Acolher")
                    .font(Theme.serifTitle(30))
                    .foregroundStyle(Theme.textPrimary)
                ProgressView()
                    .tint(Theme.primary)
                    .padding(.top, 8)
            }
        }
    }
}

#Preview {
    RootView().environment(SessionStore.shared)
}
