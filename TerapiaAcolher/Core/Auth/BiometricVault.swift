import Foundation
import LocalAuthentication
import Security

/// Cofre do "Entrar com Face ID / Touch ID".
///
/// O refresh token fica num item do Keychain protegido por biometria:
/// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` (não vai para backup nem
/// para outro aparelho) + `.biometryCurrentSet` (se a biometria do aparelho
/// mudar — rosto ou digital novos —, o item fica inacessível para sempre).
/// Ler exige o rosto/digital; gravar (rotação do token) não pede nada.
/// A senha nunca é guardada.
enum BiometricVault {
    private static let service = "com.ccypher.terapiaacolher.biometria"
    private static let account = "refreshToken.v1"
    private static let flagKey = "acolher.biometria.ligada"

    enum Falha: Error {
        /// Ela cancelou o prompt (ou escolheu a senha).
        case cancelada
        /// Biometria do aparelho mudou / item não existe mais.
        case invalidada
        /// Biometria indisponível agora (bloqueada por tentativas, sem cadastro).
        case indisponivel(String)
    }

    /// Ligado neste aparelho (não é segredo: só diz qual tela mostrar).
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: flagKey) }
        set { UserDefaults.standard.set(newValue, forKey: flagKey) }
    }

    /// "Face ID", "Touch ID" ou "Optic ID" — nil se o aparelho não tem biometria cadastrada.
    static var biometryName: String? {
        let ctx = LAContext()
        var erro: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &erro) else { return nil }
        switch ctx.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return nil
        }
    }

    /// Por que não dá para ligar (aparelho sem biometria, sem cadastro, bloqueada).
    static var motivoIndisponivel: String {
        let ctx = LAContext()
        var erro: NSError?
        if ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &erro) { return "" }
        switch LAError.Code(rawValue: erro?.code ?? 0) {
        case .biometryNotEnrolled:
            return "Cadastre o Face ID ou o Touch ID nos Ajustes do iPhone para usar."
        case .biometryLockout:
            return "A biometria está bloqueada. Desbloqueie o iPhone com o código e tente de novo."
        case .passcodeNotSet:
            return "Defina um código no iPhone para usar a biometria."
        default:
            return "Este aparelho não tem biometria disponível."
        }
    }

    /// Pede o rosto/digital (sem ler nada) — usado para ligar a opção.
    static func confirmarPresenca(motivo: String) async throws {
        let ctx = LAContext()
        ctx.localizedCancelTitle = "Cancelar"
        do {
            _ = try await ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: motivo)
        } catch {
            throw mapear(error)
        }
    }

    /// Guarda (ou rotaciona) o refresh token. Não pede biometria.
    @discardableResult
    static func salvar(_ token: String) -> Bool {
        apagar()
        var erroAC: Unmanaged<CFError>?
        guard let acesso = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryCurrentSet,
            &erroAC
        ) else { return false }
        let atributos: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccessControl as String: acesso,
        ]
        return SecItemAdd(atributos as CFDictionary, nil) == errSecSuccess
    }

    /// Lê o refresh token pedindo o rosto/digital.
    static func ler(motivo: String) async throws -> String {
        let ctx = LAContext()
        ctx.localizedCancelTitle = "Entrar com senha"
        do {
            _ = try await ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: motivo)
        } catch {
            throw mapear(error)
        }
        // Mesmo contexto já autenticado: o Keychain não pede de novo.
        let busca: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: ctx,
        ]
        var resultado: AnyObject?
        let status = SecItemCopyMatching(busca as CFDictionary, &resultado)
        switch status {
        case errSecSuccess:
            guard let data = resultado as? Data, let token = String(data: data, encoding: .utf8) else {
                throw Falha.invalidada
            }
            return token
        case errSecUserCanceled:
            throw Falha.cancelada
        default:
            // errSecItemNotFound / errSecAuthFailed depois de uma biometria
            // válida = item invalidado (biometria do aparelho mudou).
            throw Falha.invalidada
        }
    }

    static func apagar() {
        let busca: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(busca as CFDictionary)
    }

    private static func mapear(_ error: Error) -> Falha {
        guard let la = error as? LAError else { return .indisponivel("Não foi possível usar a biometria. Entre com a senha.") }
        switch la.code {
        case .userCancel, .appCancel, .systemCancel, .userFallback:
            return .cancelada
        case .biometryLockout:
            return .indisponivel("A biometria está bloqueada por tentativas. Entre com a senha.")
        case .biometryNotEnrolled, .biometryNotAvailable, .passcodeNotSet:
            return .indisponivel(motivoIndisponivel)
        default:
            return .indisponivel("Não foi possível confirmar a biometria.")
        }
    }
}
