import Observation
import SwiftUI
import UIKit
import UserNotifications

/// Para onde o toque numa notificação deve levar.
///
/// Fica separado do PushManager porque a navegação também é usada por outras
/// origens no futuro (link, widget) — quem navega não precisa saber de push.
@Observable
final class DeepLink {
    static let shared = DeepLink()

    /// Sessão a abrir na Agenda. A AgendaView observa e empurra o detalhe.
    var sessionId: String?
    /// Leva o menu pra uma seção (ex.: cobrança confirmada → Financeiro).
    var pendingSection: String?
    /// Endereço externo pedido por uma notificação do suporte.
    var externalURL: URL?
}

/// Registro de push e tratamento do toque.
///
/// Sem SDK de terceiro: `UNUserNotificationCenter` e `registerForRemoteNotifications`
/// são framework do sistema. O app segue com zero dependências externas.
@Observable
final class PushManager: NSObject {
    static let shared = PushManager()

    /// `nil` enquanto não perguntamos ao sistema.
    var authorization: UNAuthorizationStatus?

    private var deviceToken: String?

    // MARK: Permissão

    @MainActor
    func refreshAuthorization() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorization = settings.authorizationStatus
        // Já autorizado num lançamento anterior: o token pode ter mudado, então
        // registramos de novo em toda abertura.
        if settings.authorizationStatus == .authorized {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// Pede permissão. Só chamar quando o valor estiver claro pro terapeuta —
    /// pedir na primeira abertura é o jeito de tomar "não" e nunca mais poder
    /// perguntar (o iOS só mostra o alerta UMA vez).
    @MainActor
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorization()
            if granted { UIApplication.shared.registerForRemoteNotifications() }
            return granted
        } catch {
            return false
        }
    }

    /// Abre os Ajustes do iOS — único caminho depois de o usuário ter negado.
    @MainActor
    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: Registro no backend

    func handle(deviceToken data: Data) {
        let token = data.map { String(format: "%02x", $0) }.joined()
        deviceToken = token
        Task { await sendToBackend(token) }
    }

    private func sendToBackend(_ token: String) async {
        // Sem sessão não há a quem associar o aparelho; o registro acontece
        // de novo na próxima abertura já logada.
        guard SessionStore.shared.isAuthenticated else { return }
        struct Body: Encodable {
            let token: String
            let platform = "IOS"
            let sandbox: Bool
            let appVersion: String?
        }
        let body = Body(
            token: token,
            sandbox: Self.isSandboxBuild,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        )
        _ = try? await APIClient.shared.post("notifications/device", body: body) as EmptyResponse?
    }

    /// Remove o aparelho no logout. **Não é opcional**: sem isso o próximo
    /// terapeuta que logar neste iPhone recebe notificação sobre pacientes do
    /// anterior — incidente de privacidade, não incômodo.
    func unregisterOnLogout() async {
        guard let deviceToken else { return }
        struct Body: Encodable { let token: String }
        _ = try? await APIClient.shared.delete(
            "notifications/device",
            body: Body(token: deviceToken)
        ) as EmptyResponse?
    }

    /// Qual APNs este build usa. Quem manda é a entitlement `aps-environment`
    /// do perfil que assinou o app, não a origem da instalação.
    ///
    /// **TestFlight usa APNs de PRODUÇÃO**, porque é assinado com o perfil de
    /// distribuição. A checagem anterior olhava `sandboxReceipt`, que indica
    /// recibo de compra de teste (StoreKit) e nada tem a ver com push: todo
    /// build de TestFlight se declararia sandbox, o servidor mandaria para o
    /// host errado e NENHUMA notificação chegaria aos testadores — sem erro
    /// visível, só silêncio.
    ///
    /// Sobra o critério certo: só o build de desenvolvimento (Debug, assinado
    /// com perfil de development) fala com o sandbox.
    static var isSandboxBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}

// MARK: - Delegate do app

extension PushManager: UNUserNotificationCenterDelegate {
    /// Notificação chegando com o app aberto: mostra mesmo assim (banner), senão
    /// o terapeuta usando o app não fica sabendo do lembrete.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    /// Toque na notificação.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        await MainActor.run { Self.route(info) }
    }

    @MainActor
    static func route(_ userInfo: [AnyHashable: Any]) {
        // Avisa o servidor que ESTA notificação foi aberta. É o que alimenta a
        // taxa de abertura dos comunicados no painel — sem isto o suporte
        // manda no escuro, sem saber se alguém viu.
        if let id = userInfo["notificationId"] as? String {
            Task {
                struct Ok: Decodable { let opened: Bool? }
                _ = try? await APIClient.shared.patch(
                    "notifications/\(id)/opened",
                    body: [String: String]()
                ) as Ok
            }
        }

        // `section` e `url` vêm do painel de suporte e valem para QUALQUER
        // tipo. Vinham sendo ignorados: o switch abaixo só olhava `type`, então
        // uma notificação escrita com destino "Minha Vitrine" caía no default e
        // o app só abria na tela inicial.
        if let url = userInfo["url"] as? String, let destino = URL(string: url) {
            DeepLink.shared.externalURL = destino
            return
        }
        if let secao = userInfo["section"] as? String {
            DeepLink.shared.pendingSection = secao
            return
        }

        // Destino derivado do tipo, para as notificações automáticas.
        switch userInfo["type"] as? String {
        case "SESSION_SOON", "SESSION_ATTENDED", "SESSION_MISSED":
            if let sessionId = userInfo["sessionId"] as? String {
                DeepLink.shared.sessionId = sessionId
            }
            DeepLink.shared.pendingSection = "agenda"
        case "CHARGE_DUE":
            DeepLink.shared.pendingSection = "financeiro"
        default:
            break
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = PushManager.shared
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PushManager.shared.handle(deviceToken: deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Simulador sem conta iCloud e device sem rede caem aqui. Não é fatal:
        // o app inteiro funciona sem push.
        print("[Push] registro falhou: \(error.localizedDescription)")
    }
}
