import AuthenticationServices
import CryptoKit
import UIKit

/// Extensão de "AutoFill Credential Provider" (Fase 15.6). A fatia 1 só
/// registrava identidades (`ASCredentialIdentityStore`, lado Dart) e mostrava
/// uma tela informativa. Esta fatia (2) decifra o Vault de verdade, dentro do
/// processo da extensão.
///
/// Diferente do `TruthIdAutofillService` do Android (Fase 15.5), esta
/// extensão **não pode** abrir o app principal e receber o resultado de
/// volta: uma vez que uma extensão chama `extensionContext.open(_:)` pra sair
/// pro app contêiner, ela perde o controle e a chamada original (Safari, por
/// exemplo) só recebe cancelamento. Por isso a decifra precisa acontecer
/// aqui — chave e blob chegam via Keychain Access Group / App Group
/// compartilhados (`SharedVaultAccess.swift`), sincronizados pelo app
/// principal (`IosAutofillVaultSyncService`) sempre que a tela do Vault
/// recarrega.
///
/// **Nunca compilado nem executado neste ambiente** (Linux, sem Xcode/
/// simulador) — ver P35/P36 em `project/PENDING.md`. Só confirmável num Mac
/// real.
class CredentialProviderViewController: ASCredentialProviderViewController {

    private enum DecryptError: Error {
        case keyUnavailable
        case blobUnavailable
        case invalidVaultFormat
    }

    /// Populado por `prepareCredentialList`, usado na seleção — evita
    /// decifrar duas vezes (lista + escolha) e a janela de erro que isso
    /// abriria se o blob mudasse entre as duas chamadas.
    private var cachedCredentialEntries: [[String: Any]] = []

    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        do {
            cachedCredentialEntries = try decryptCredentialEntries()
        } catch {
            cachedCredentialEntries = []
        }
        showCredentialPicker()
    }

    override func prepareInterfaceToProvideCredential(for credentialIdentity: ASPasswordCredentialIdentity) {
        do {
            let entries = try decryptCredentialEntries()
            guard
                let entry = entries.first(where: { ($0["id"] as? String) == credentialIdentity.recordIdentifier }),
                let username = entry["username"] as? String,
                let password = entry["password"] as? String
            else {
                cancel(withErrorCode: .credentialIdentityNotFound)
                return
            }
            complete(username: username, password: password)
        } catch {
            cancel(withErrorCode: .failed)
        }
    }

    override func provideCredentialWithoutUserInteraction(for credentialIdentity: ASPasswordCredentialIdentity) {
        // Força o caminho interativo acima — o próprio iOS já exige Face
        // ID/passcode antes de invocar a extensão pra autofill de senha,
        // então não duplicamos esse gate aqui (mesmo padrão da fatia 1).
        cancel(withErrorCode: .userInteractionRequired)
    }

    // MARK: - Decifra

    /// Lê a chave + o blob do compartilhamento (Keychain/App Group) e
    /// decifra com AES-256-GCM (`CryptoKit`). O layout do blob
    /// (`nonce(12) || ciphertext || tag(16)`, `vault_cipher_service.dart`)
    /// bate byte-a-byte com o formato `combined` do `AES.GCM.SealedBox` —
    /// não precisa fatiar manualmente. Retorna só as entradas
    /// `type == "credential"` (único tipo que o iOS expõe extension point
    /// pra preencher).
    private func decryptCredentialEntries() throws -> [[String: Any]] {
        guard let keyData = SharedVaultAccess.readVaultKey() else {
            throw DecryptError.keyUnavailable
        }
        guard let blobData = SharedVaultAccess.readVaultBlob() else {
            throw DecryptError.blobUnavailable
        }

        let sealedBox = try AES.GCM.SealedBox(combined: blobData)
        let key = SymmetricKey(data: keyData)
        let plaintext = try AES.GCM.open(sealedBox, using: key)

        guard
            let json = try JSONSerialization.jsonObject(with: plaintext) as? [String: Any],
            let entries = json["entries"] as? [[String: Any]]
        else {
            throw DecryptError.invalidVaultFormat
        }

        return entries.filter { ($0["type"] as? String) == "credential" }
    }

    private func complete(username: String, password: String) {
        extensionContext.completeRequest(
            withSelectedCredential: ASPasswordCredential(user: username, password: password),
            completionHandler: nil
        )
    }

    private func cancel(withErrorCode code: ASExtensionError.Code) {
        extensionContext.cancelRequest(
            withError: NSError(domain: ASExtensionErrorDomain, code: code.rawValue)
        )
    }

    // MARK: - Picker ("Other Passwords" / seleção manual)

    private func showCredentialPicker() {
        guard !cachedCredentialEntries.isEmpty else {
            showMessage(
                "No saved passwords found, or the TruthID app hasn't synced yet. " +
                "Open the TruthID app once (unlock the Vault) and try again."
            )
            return
        }

        let tableView = UITableView(frame: view.bounds, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func showMessage(_ message: String) {
        let label = UILabel()
        label.text = message
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
        cancel(withErrorCode: .userCanceled)
    }
}

extension CredentialProviderViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        cachedCredentialEntries.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        let entry = cachedCredentialEntries[indexPath.row]
        cell.textLabel?.text = (entry["site"] as? String) ?? "TruthID"
        cell.detailTextLabel?.text = entry["username"] as? String
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let entry = cachedCredentialEntries[indexPath.row]
        guard let username = entry["username"] as? String, let password = entry["password"] as? String else {
            cancel(withErrorCode: .failed)
            return
        }
        complete(username: username, password: password)
    }
}
