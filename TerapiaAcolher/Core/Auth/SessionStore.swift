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

/// Login de um local (IP) que a terapeuta nunca confirmou: a senha estava
/// certa, mas a sessão só abre com o código mandado por e-mail ou WhatsApp.
struct LoginChallenge: Codable, Hashable {
    let challenge: String
    let canais: [LoginCodeChannel]
}

struct LoginCodeChannel: Codable, Hashable, Identifiable {
    /// "EMAIL" ou "WHATSAPP".
    let canal: String
    /// Destino mascarado ("te***@x.com", "+55 17 *****-2727").
    let destino: String
    var id: String { canal }
    var isWhatsapp: Bool { canal == "WHATSAPP" }
}

/// Resposta de `auth/login/codigo`.
struct LoginCodeSent: Codable {
    let canal: String
    let destino: String
    let reenviarEm: Int
}

/// Resultado do login: sessão aberta, ou código pedido (IP novo).
enum LoginOutcome {
    case loggedIn
    case needsCode(LoginChallenge)
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
    /// Biometria ligada e app recém-aberto: a tela de desbloqueio aparece no
    /// lugar do login até o rosto/digital (ou "Entrar com senha").
    private(set) var travadoPorBiometria = false
    /// Aviso para a tela de login (ex.: biometria do aparelho mudou).
    var avisoDeBiometria: String?

    /// Com a biometria ligada os tokens vivem só em memória; o refresh fica no
    /// cofre biométrico (BiometricVault). Desligada, ficam no Keychain comum.
    private var memAccess: String?
    private var memRefresh: String?

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
        get { BiometricVault.isEnabled ? memAccess : Keychain.get(accessKey) }
        set {
            if BiometricVault.isEnabled {
                memAccess = newValue
            } else if let newValue {
                Keychain.set(newValue, forKey: accessKey)
            } else {
                Keychain.delete(accessKey)
            }
        }
    }

    private var refreshToken: String? {
        get { BiometricVault.isEnabled ? memRefresh : Keychain.get(refreshKey) }
        set {
            if BiometricVault.isEnabled {
                memRefresh = newValue
                // Rotação do token: o cofre guarda sempre o mais novo (gravar
                // não pede biometria; só ler).
                if let newValue { BiometricVault.salvar(newValue) }
            } else if let newValue {
                Keychain.set(newValue, forKey: refreshKey)
            } else {
                Keychain.delete(refreshKey)
            }
        }
    }

    // MARK: - Boot

    /// Chamado na abertura do app: se há token salvo, valida via /auth/me.
    @MainActor
    func boot() async {
        defer { isBooting = false }
        Keychain.migrarAcessibilidade([accessKey, refreshKey])
        // Sobra de uma execução anterior (app encerrado com arquivo aberto).
        ArquivosTemporarios.limparTudo()
        if BiometricVault.isEnabled {
            // Nada de token em texto no disco com a biometria ligada.
            Keychain.delete(accessKey)
            Keychain.delete(refreshKey)
            if memRefresh == nil {
                travadoPorBiometria = true
                return
            }
        }
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
    @discardableResult
    func login(email: String, password: String) async throws -> LoginOutcome {
        struct Body: Encodable { let email: String, password: String }
        /// O mesmo 200 traz os tokens OU o desafio do IP novo.
        struct Resposta: Decodable {
            let accessToken: String?
            let refreshToken: String?
            let user: AuthUser?
            let verificacao: LoginChallenge?
        }
        let response: Resposta = try await APIClient.shared.post(
            "auth/login",
            body: Body(email: email, password: password)
        )
        if let desafio = response.verificacao {
            return .needsCode(desafio)
        }
        guard let access = response.accessToken, let refresh = response.refreshToken, let user = response.user else {
            throw APIError(statusCode: 500, message: "Resposta inesperada do servidor. Tente de novo.", code: nil)
        }
        abrirSessao(LoginResponse(accessToken: access, refreshToken: refresh, user: user))
        return .loggedIn
    }

    /// IP novo: manda o código pelo canal escolhido ("EMAIL" ou "WHATSAPP").
    func sendLoginCode(challenge: String, channel: String) async throws -> LoginCodeSent {
        struct Body: Encodable { let challenge: String, canal: String }
        return try await APIClient.shared.post(
            "auth/login/codigo",
            body: Body(challenge: challenge, canal: channel)
        )
    }

    /// IP novo: código certo abre a sessão como um login normal.
    @MainActor
    func verifyLoginCode(challenge: String, code: String) async throws {
        struct Body: Encodable { let challenge: String, codigo: String }
        let response: LoginResponse = try await APIClient.shared.post(
            "auth/login/verificar",
            body: Body(challenge: challenge, codigo: code)
        )
        abrirSessao(response)
    }

    @MainActor
    private func abrirSessao(_ response: LoginResponse) {
        accessToken = response.accessToken
        refreshToken = response.refreshToken
        user = response.user
    }

    // MARK: - Biometria

    /// Desbloqueio pelo rosto/digital: lê o refresh do cofre e renova a sessão.
    /// Devolve um aviso para a tela, ou nil se entrou (ou se ela cancelou).
    @MainActor
    func desbloquearComBiometria() async -> String? {
        let nome = BiometricVault.biometryName ?? "biometria"
        let token: String
        do {
            token = try await BiometricVault.ler(motivo: "Entrar no Acolher Gestão com \(nome)")
        } catch BiometricVault.Falha.cancelada {
            return nil
        } catch BiometricVault.Falha.invalidada {
            desligarCofre()
            travadoPorBiometria = false
            avisoDeBiometria = "A biometria do aparelho mudou. Por segurança, entre com a senha e ligue de novo em Configurações."
            return avisoDeBiometria
        } catch BiometricVault.Falha.indisponivel(let msg) {
            return msg
        } catch {
            return "Não foi possível usar a biometria. Entre com a senha."
        }
        memRefresh = token
        switch await performRefreshDetalhado() {
        case .ok:
            do {
                user = try await APIClient.shared.get("auth/me")
                travadoPorBiometria = false
                return nil
            } catch {
                return "Não foi possível entrar agora. Verifique a internet e tente de novo."
            }
        case .recusado:
            // Sessão revogada/expirada no servidor: o cofre não serve mais.
            desligarCofre()
            memRefresh = nil
            travadoPorBiometria = false
            avisoDeBiometria = "Sua sessão expirou. Entre com a senha."
            return avisoDeBiometria
        case .semRede:
            memRefresh = nil
            return "Não foi possível entrar agora. Verifique a internet e tente de novo."
        }
    }

    /// "Entrar com senha" na tela de desbloqueio. A biometria continua ligada:
    /// o login com senha grava o token novo no cofre.
    @MainActor
    func usarSenhaEmVezDaBiometria() {
        travadoPorBiometria = false
    }

    /// Liga a entrada por biometria (pede o rosto/digital para confirmar).
    @MainActor
    func ligarBiometria() async throws {
        guard isAuthenticated, let refresh = refreshToken, let access = accessToken else {
            throw APIError(statusCode: 0, message: "Entre de novo para ligar a biometria.", code: nil)
        }
        let nome = BiometricVault.biometryName ?? "biometria"
        try await BiometricVault.confirmarPresenca(motivo: "Confirme para entrar com \(nome) nas próximas vezes")
        guard BiometricVault.salvar(refresh) else {
            throw APIError(statusCode: 0, message: "Não foi possível preparar a biometria neste aparelho.", code: nil)
        }
        memAccess = access
        memRefresh = refresh
        BiometricVault.isEnabled = true
        Keychain.delete(accessKey)
        Keychain.delete(refreshKey)
    }

    /// Desliga: os tokens voltam ao Keychain comum e o cofre é apagado.
    @MainActor
    func desligarBiometria() {
        let access = memAccess, refresh = memRefresh
        desligarCofre()
        if let access { Keychain.set(access, forKey: accessKey) }
        if let refresh { Keychain.set(refresh, forKey: refreshKey) }
    }

    private func desligarCofre() {
        BiometricVault.apagar()
        BiometricVault.isEnabled = false
        memAccess = nil
        memRefresh = nil
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

    private enum ResultadoDoRefresh { case ok, recusado, semRede }

    private func performRefresh() async -> Bool {
        await performRefreshDetalhado() == .ok
    }

    private func performRefreshDetalhado() async -> ResultadoDoRefresh {
        guard let refreshToken else { return .recusado }
        struct Body: Encodable { let refreshToken: String }
        struct TokenPair: Decodable { let accessToken: String, refreshToken: String }
        do {
            let response: TokenPair = try await APIClient.shared.post(
                "auth/refresh",
                body: Body(refreshToken: refreshToken)
            )
            self.accessToken = response.accessToken
            self.refreshToken = response.refreshToken
            return .ok
        } catch let error as APIError where error.isUnauthorized || error.statusCode == 400 || error.statusCode == 403 {
            return .recusado
        } catch {
            return .semRede
        }
    }

    /// Exposto pra fluxos que precisam preservar a sessão atual no backend
    /// (ex.: troca de senha envia o refresh token pra não revogar esta sessão).
    var currentRefreshToken: String? { refreshToken }

    @MainActor
    func reloadProfile() async {
        user = (try? await APIClient.shared.get("auth/me")) ?? user
    }

    // MARK: - Bloqueio por inatividade (auditoria de segurança, 2026-10-07)

    /// Com a biometria ligada, voltar ao app depois de mais que isto em segundo
    /// plano pede o rosto/digital de novo — antes só a abertura do zero pedia.
    static let segundosParaRebloquear: TimeInterval = 5 * 60
    private var foiParaSegundoPlanoEm: Date?

    @MainActor
    func appFoiParaSegundoPlano() {
        if isAuthenticated { foiParaSegundoPlanoEm = Date() }
    }

    @MainActor
    func appVoltouAoPrimeiroPlano() {
        defer { foiParaSegundoPlanoEm = nil }
        guard BiometricVault.isEnabled, isAuthenticated,
              let desde = foiParaSegundoPlanoEm,
              Date().timeIntervalSince(desde) > Self.segundosParaRebloquear
        else { return }
        // Tokens só em memória somem; o cofre continua com o refresh e o
        // desbloqueio refaz a sessão. Os dados em memória também vão embora:
        // quem entrar com senha pode ser outra pessoa.
        memAccess = nil
        memRefresh = nil
        user = nil
        SessionScope.reset()
        travadoPorBiometria = true
    }

    @MainActor
    private func clearSession() {
        accessToken = nil
        refreshToken = nil
        // Logout ou sessão recusada (401): o cofre biométrico vai junto.
        desligarCofre()
        Keychain.delete(accessKey)
        Keychain.delete(refreshKey)
        travadoPorBiometria = false
        user = nil
        // Sem isto, o próximo terapeuta a logar neste aparelho veria as
        // pendências de perfil do anterior.
        ProfileStatusStore.shared.limpar()
        PushOptIn.shared.encerrarSessao()
        // E os pacientes, a agenda e o financeiro dele (ver SessionScope).
        SessionScope.reset()
        // Comprovantes, extratos e anexos baixados não ficam no aparelho.
        ArquivosTemporarios.limparTudo()
    }
}
