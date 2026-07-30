import Foundation
import Security

// Fase 15.6, fatia 2 — contrato próprio de compartilhamento entre o app
// principal (Runner) e a extensão de autofill (AutofillExtension), via
// Keychain Access Group + App Group. Deliberadamente NÃO depende do schema
// interno do plugin `flutter_secure_storage` (não é contrato público) —
// este arquivo é duplicado (mesmo conteúdo) em
// `AutofillExtension/SharedVaultAccess.swift`, mesmo padrão de duplicação
// por canal que `sign_request.rs`/`sign_message.rs` já seguem no Desktop.
enum SharedVaultAccess {
  static let appGroupIdentifier = "group.com.truthid.truthidMobile"
  static let keychainAccessGroup = "com.truthid.truthidMobile.shared"
  static let keychainService = "com.truthid.truthidMobile.vaultkey"
  static let keychainAccount = "vault_key"
  static let blobFileName = "vault.enc"

  static var containerURL: URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
  }

  /// Sobrescreve a chave do vault (32 bytes) no Keychain compartilhado.
  /// Só existe 1 chave por vez — apaga a anterior antes de gravar, já que
  /// `SecItemAdd` falha (`errSecDuplicateItem`) se o item já existir.
  static func writeVaultKey(_ keyData: Data) -> OSStatus {
    let baseQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: keychainAccount,
      kSecAttrAccessGroup as String: keychainAccessGroup,
    ]
    SecItemDelete(baseQuery as CFDictionary)

    var addQuery = baseQuery
    addQuery[kSecValueData as String] = keyData
    addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
    return SecItemAdd(addQuery as CFDictionary, nil)
  }

  /// Sobrescreve o blob cifrado do vault (`vault.enc`) no container do App
  /// Group — a extensão decifra este blob sozinha, ver
  /// `CredentialProviderViewController.swift`.
  static func writeVaultBlob(_ blobData: Data) throws {
    guard let containerURL = containerURL else {
      throw NSError(
        domain: "SharedVaultAccess",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "App Group container indisponível"]
      )
    }
    try blobData.write(to: containerURL.appendingPathComponent(blobFileName), options: .atomic)
  }
}
