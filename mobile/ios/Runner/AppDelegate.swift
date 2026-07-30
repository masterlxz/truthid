import AuthenticationServices
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerAutofillIdentityChannel(with: engineBridge)
    registerVaultSyncChannel(with: engineBridge)
  }

  // Fase 15.6, fatia 1 — só registra identidades de credencial no
  // ASCredentialIdentityStore do sistema (pra aparecer em Ajustes > Senhas /
  // QuickType bar). A extensão (`AutofillExtension`, alvo separado) ainda
  // não decifra o Vault — ver `project/PHASE.md` 15.6 pro porquê: diferente
  // do Android, a extensão iOS não consegue delegar pro app principal e
  // receber o resultado de volta.
  private func registerAutofillIdentityChannel(with engineBridge: FlutterImplicitEngineBridge) {
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "IosAutofillIdentityChannel")
    let channel = FlutterMethodChannel(
      name: "truthid/ios_autofill_identities",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "syncCredentialIdentities" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let items = call.arguments as? [[String: String]] else {
        result(FlutterError(code: "invalid_arguments", message: "expected a list of maps", details: nil))
        return
      }

      // Quem decide qual credencial vira uma identidade é o Dart
      // (`IosAutofillIdentityService`, já filtrado por EntryType.credential
      // e com o hostname derivado) — este código só traduz pro tipo do
      // framework.
      let identities = items.compactMap { item -> ASPasswordCredentialIdentity? in
        guard let service = item["serviceIdentifier"], !service.isEmpty,
              let username = item["username"],
              let recordId = item["id"] else {
          return nil
        }
        let serviceIdentifier = ASCredentialServiceIdentifier(identifier: service, type: .domain)
        return ASPasswordCredentialIdentity(
          serviceIdentifier: serviceIdentifier,
          user: username,
          recordIdentifier: recordId
        )
      }

      ASCredentialIdentityStore.shared.replaceCredentialIdentities(identities) { _, error in
        DispatchQueue.main.async {
          if let error = error {
            result(FlutterError(code: "identity_store_error", message: error.localizedDescription, details: nil))
          } else {
            result(nil)
          }
        }
      }
    }
  }

  // Fase 15.6, fatia 2 — espelha pro Keychain Access Group / App Group
  // compartilhados (`SharedVaultAccess`) a chave do vault e o blob cifrado
  // (`vault.enc`), pra que `CredentialProviderViewController` (processo
  // separado da extensão) consiga decifrar sozinha. Contrato próprio, não
  // depende do schema interno do `flutter_secure_storage`.
  private func registerVaultSyncChannel(with engineBridge: FlutterImplicitEngineBridge) {
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "IosAutofillVaultSyncChannel")
    let channel = FlutterMethodChannel(
      name: "truthid/ios_autofill_vault_sync",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "syncVaultKey":
        guard let args = call.arguments as? [String: Any],
              let keyBase64 = args["keyBase64"] as? String,
              let keyData = Data(base64Encoded: keyBase64) else {
          result(FlutterError(code: "invalid_arguments", message: "expected base64 vault key", details: nil))
          return
        }
        let status = SharedVaultAccess.writeVaultKey(keyData)
        if status == errSecSuccess {
          result(nil)
        } else {
          result(FlutterError(code: "keychain_error", message: "SecItemAdd failed (\(status))", details: nil))
        }
      case "syncVaultBlob":
        guard let args = call.arguments as? [String: Any],
              let blobData = (args["bytes"] as? FlutterStandardTypedData)?.data else {
          result(FlutterError(code: "invalid_arguments", message: "expected raw bytes", details: nil))
          return
        }
        do {
          try SharedVaultAccess.writeVaultBlob(blobData)
          result(nil)
        } catch {
          result(FlutterError(code: "app_group_error", message: error.localizedDescription, details: nil))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
