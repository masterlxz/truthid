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
}
