import AuthenticationServices
import UIKit

/// Extensão de "AutoFill Credential Provider" (Fase 15.6, fatia 1) — registra
/// o TruthID como fonte de senhas em Ajustes > Senhas do iOS.
///
/// Diferente do `TruthIdAutofillService` do Android (Fase 15.5), esta
/// extensão **não consegue** abrir o app principal e receber o resultado de
/// volta: uma vez que uma extensão chama `extensionContext.open(_:)` pra
/// sair pro app contêiner, ela perde o controle e a chamada original
/// (Safari, por exemplo) só recebe cancelamento. Por isso a decifra do Vault
/// precisa acontecer aqui dentro — trabalho de uma fatia futura (ver
/// `project/PHASE.md`, Fase 15.6). Esta fatia só registra as identidades
/// (lado Dart, `IosAutofillIdentityService`, via `ASCredentialIdentityStore`)
/// pra aparecerem na lista do sistema, e mostra uma tela informativa quando
/// o usuário toca numa delas — preenchimento de verdade ainda não existe.
class CredentialProviderViewController: ASCredentialProviderViewController {

    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        showFillingNotAvailableYet()
    }

    override func prepareInterfaceToProvideCredential(for credentialIdentity: ASPasswordCredentialIdentity) {
        showFillingNotAvailableYet()
    }

    override func provideCredentialWithoutUserInteraction(for credentialIdentity: ASPasswordCredentialIdentity) {
        // Sem decifra implementada ainda nesta fatia — força o caminho
        // interativo acima, que também só informa e cancela por ora.
        extensionContext.cancelRequest(
            withError: NSError(domain: ASExtensionErrorDomain, code: ASExtensionError.userInteractionRequired.rawValue)
        )
    }

    private func showFillingNotAvailableYet() {
        let label = UILabel()
        label.text = "TruthID autofill isn't available yet on iOS. Open the TruthID app to copy your password."
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        let closeButton = UIButton(type: .system)
        closeButton.setTitle("Close", for: .normal)
        closeButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [label, closeButton])
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    @objc private func cancelTapped() {
        extensionContext.cancelRequest(
            withError: NSError(domain: ASExtensionErrorDomain, code: ASExtensionError.userCanceled.rawValue)
        )
    }
}
