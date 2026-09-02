import Foundation
import Observation

/// Usuário autenticado (espelho do /auth/me do backend).
struct AuthUser: Codable, Identifiable, Equatable {
    let id: String
    var email: String
    var name: String
    var specialty: String?
    var professionalRegistration: String?
    var whatsapp: String?
    var role: String
    var status: String
    var timezone: String
    /// Nulo enquanto o número não passou pelo código do WhatsApp.
    var phoneVerifiedAt: String?
    var emailVerifiedAt: String?
}

struct LoginResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let user: AuthUser
}

struct MessageResponse: Codable {
    let message: String
}

/// Estado global de sessão: tokens no Keychain, refresh automático,
/// fonte da verdade de "logado ou não" pro RootView.
@Observable
final class SessionStore {
    static let shared = SessionStore()

    private(set) var user: AuthUser?
    private(set) var isBooting = true
    var isAuthenticated: Bool { user != nil }

    private let accessKey = "accessToken"
    private let refreshKey = "refreshToken"

    private init() {
        APIClient.shared.accessTokenProvider = { [weak self] in self?.accessToken }
        APIClient.shared.refreshHandler = { [weak self] in await self?.refreshSession() ?? false }
        APIClient.shared.onSessionExpired = { [weak self] in
            Task { @MainActor in self?.clearSession() }
        }
    }

    private var accessToken: String? {
        get { Keychain.get(accessKey) }
        set {
            if let newValue { Keychain.set(newValue, forKey: accessKey) } else { Keychain.delete(accessKey) }
        }
    }

    private var refreshToken: String? {
        get { Keychain.get(refreshKey) }
        set {
            if let newValue { Keychain.set(newValue, forKey: refreshKey) } else { Keychain.delete(refreshKey) }
        }
    }

    // MARK: - Boot

    /// Chamado na abertura do app: se há token salvo, valida via /auth/me.
    @MainActor
    func boot() async {
        defer { isBooting = false }
        guard accessToken != nil || refreshToken != nil else { return }
        do {
            user = try await APIClient.shared.get("auth/me")
        } catch let error as APIError where error.isUnauthorized {
            clearSession()
        } catch {
            // Sem rede: mantém tokens; RootView mostra login se user == nil,
            // mas um retry de /auth/me acontece no próximo boot.
        }
    }

    // MARK: - Fluxos

    @MainActor
    func login(email: String, password: String) async throws {
        struct Body: Encodable { let email: String, password: String }
        let response: LoginResponse = try await APIClient.shared.post(
            "auth/login",
            body: Body(email: email, password: password)
        )
        accessToken = response.accessToken
        refreshToken = response.refreshToken
        user = response.user
    }

    @MainActor
    func logout() async {
        // Antes de limpar a sessão: o DELETE precisa do access token ainda
        // válido. Sem isso o aparelho continua recebendo notificação deste
        // terapeuta mesmo depois de outro logar nele.
        await PushManager.shared.unregisterOnLogout()

        if let refreshToken {
            struct Body: Encodable { let refreshToken: String }
            let _: EmptyResponse? = try? await APIClient.shared.post(
                "auth/logout",
                body: Body(refreshToken: refreshToken)
            )
        }
        clearSession()
    }

    /// Refresh single-flight: N requests com 401 simultâneos aguardam UM refresh.
    /// (O backend rotaciona o token e trata reuso como roubo — refresh duplo
    /// revogaria todas as sessões do usuário.)
    private var refreshTask: Task<Bool, Never>?

    func refreshSession() async -> Bool {
        if let existing = refreshTask {
            return await existing.value
        }
        let task = Task<Bool, Never> { [weak self] in
            await self?.performRefresh() ?? false
        }
        refreshTask = task
        let result = await task.value
        refreshTask = nil
        return result
    }

    private func performRefresh() async -> Bool {
        guard let refreshToken else { return false }
        struct Body: Encodable { let refreshToken: String }
        struct TokenPair: Decodable { let accessToken: String, refreshToken: String }
        do {
            let response: TokenPair = try await APIClient.shared.post(
                "auth/refresh",
                body: Body(refreshToken: refreshToken)
            )
            self.accessToken = response.accessToken
            self.refreshToken = response.refreshToken
            return true
        } catch {
            return false
        }
    }

    /// Exposto pra fluxos que precisam preservar a sessão atual no backend
    /// (ex.: troca de senha envia o refresh token pra não revogar esta sessão).
    var currentRefreshToken: String? { refreshToken }

    @MainActor
    func reloadProfile() async {
        user = (try? await APIClient.shared.get("auth/me")) ?? user
    }

    @MainActor
    private func clearSession() {
        accessToken = nil
        refreshToken = nil
        user = nil
        // Sem isto, o próximo terapeuta a logar neste aparelho veria as
        // pendências de perfil do anterior.
        ProfileStatusStore.shared.limpar()
    }
}
