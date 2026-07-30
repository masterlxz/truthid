import Foundation
import Security

// Fase 15.6, fatia 2 — mesmo contrato de `Runner/SharedVaultAccess.swift`
// (duplicado de propósito, cada lado só implementa a direção que usa: o
// app grava, a extensão só lê). Ver o arquivo irmão pro contexto completo.
enum SharedVaultAccess {
  static let appGroupIdentifier = "group.com.truthid.truthidMobile"
  static let keychainAccessGroup = "com.truthid.truthidMobile.shared"
  static let keychainService = "com.truthid.truthidMobile.vaultkey"
  static let keychainAccount = "vault_key"
  static let blobFileName = "vault.enc"

  static var containerURL: URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
  }

  /// Lê a chave do vault (32 bytes) do Keychain compartilhado. `nil` se o
  /// app principal nunca sincronizou (ex: usuário nunca abriu o app depois
  /// de instalar, ou pareamento ainda não entregou a chave).
  static func readVaultKey() -> Data? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: keychainAccount,
      kSecAttrAccessGroup as String: keychainAccessGroup,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess else { return nil }
    return result as? Data
  }

  /// Lê o blob cifrado do vault (`vault.enc`) do container do App Group.
  /// `nil` se o app principal nunca sincronizou ainda.
  static func readVaultBlob() -> Data? {
    guard let containerURL = containerURL else { return nil }
    return try? Data(contentsOf: containerURL.appendingPathComponent(blobFileName))
  }
}
