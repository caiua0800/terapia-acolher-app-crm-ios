import Foundation
import Security

/// Wrapper mínimo do Keychain pra tokens (dados sensíveis nunca em UserDefaults).
///
/// `ThisDeviceOnly` (auditoria de segurança, 2026-10-07): o token não vai no
/// backup do iPhone nem migra para outro aparelho restaurado — sem isso, um
/// refresh de 30 dias sobrevivia num backup criptografado.
enum Keychain {
    private static let service = "com.ccypher.terapiaacolher"
    private static let acessibilidade = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    @discardableResult
    static func set(_ value: String, forKey key: String) -> Bool {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = acessibilidade
        let status = SecItemAdd(attributes as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Itens gravados por versões antigas (sem `ThisDeviceOnly`) são regravados
    /// uma vez com a acessibilidade nova. Chamado no boot da sessão.
    static func migrarAcessibilidade(_ chaves: [String]) {
        let marca = "keychain.acessibilidade.v2"
        guard !UserDefaults.standard.bool(forKey: marca) else { return }
        for chave in chaves {
            if let valor = get(chave) { set(valor, forKey: chave) }
        }
        UserDefaults.standard.set(true, forKey: marca)
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
