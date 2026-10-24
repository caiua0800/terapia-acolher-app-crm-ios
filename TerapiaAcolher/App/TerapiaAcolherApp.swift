import SwiftUI

@main
struct TerapiaAcolherApp: App {
    // Push precisa de AppDelegate: o token do APNs chega por callback do UIKit,
    // que o ciclo de vida SwiftUI puro não expõe.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session = SessionStore.shared

    init() {
        // Suporte a testes de UI: estado limpo de sessão.
        if CommandLine.arguments.contains("--reset-session") {
            Keychain.delete("accessToken")
            Keychain.delete("refreshToken")
            BiometricVault.apagar()
            BiometricVault.isEnabled = false
        }
        // Renovações e compras aprovadas depois chegam a qualquer momento:
        // o ouvinte do StoreKit nasce com o app (ver StoreKitStore).
        StoreKitStore.shared.iniciar()
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
    @Environment(\.scenePhase) private var fase
    @State private var atualizacao = AtualizacaoDoApp.shared

    var body: some View {
        ZStack {
            conteudo
            // Versão nova na loja: aparece a cada abertura até atualizar.
            if let aviso = atualizacao.aviso {
                AvisoDeAtualizacaoView(aviso: aviso)
            }
            // Tela de privacidade (auditoria de segurança, 2026-10-07): fora de
            // `.active`, o iOS tira o "retrato" do app para o seletor de apps e
            // o guarda em disco. Com isto ele mostra só a marca, nunca um
            // prontuário ou o saldo.
            if fase != .active {
                TelaDePrivacidade()
                    .transition(.opacity)
            }
        }
        .onChange(of: fase) { _, nova in
            switch nova {
            case .background:
                session.appFoiParaSegundoPlano()
                atualizacao.appFoiParaSegundoPlano()
            case .active:
                session.appVoltouAoPrimeiroPlano()
                Task { await atualizacao.verificar() }
            default: break
            }
        }
        .animation(.easeOut(duration: 0.2), value: atualizacao.aviso)
        // Abertura a frio: a fase já nasce `.active` e o onChange não dispara.
        .task { await atualizacao.verificar() }
    }

    private var conteudo: some View {
        Group {
            if session.isBooting {
                BootSplashView()
            } else if session.isAuthenticated {
                MainShellView()
            } else if session.travadoPorBiometria {
                BiometricUnlockView()
            } else {
                LoginFlowView()
            }
        }
        .task { await session.boot() }
    }
}

/// Cobre o app quando ele sai de foco (ver RootView).
struct TelaDePrivacidade: View {
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 14) {
                AuthLogoView(size: 88)
                Text("Acolher Gestão")
                    .font(Theme.serifTitle(26))
                    .foregroundStyle(Theme.textPrimary)
            }
        }
    }
}

struct BootSplashView: View {
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 16) {
                AuthLogoView(size: 96)
                Text("Acolher Gestão")
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
