// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract IdentityRegistry {
    // -------------------------------------------------------------------------
    // Tipos de dados
    // -------------------------------------------------------------------------

    struct Identity {
        uint256 id;          // número único gerado automaticamente (1, 2, 3...)
        string username;     // ex: "fabio.id"
        address controller;  // carteira que controla essa identidade
        bool exists;         // flag para saber se a identidade existe (ver nota abaixo)
    }

    // Nota sobre `exists`: em Solidity, acessar um mapping com uma chave que não
    // existe NÃO dá erro — retorna um valor "zerado" (0, "", address(0), false).
    // Sem esse campo, não conseguiríamos distinguir "identidade inexistente" de
    // "identidade com todos os campos em zero".

    // -------------------------------------------------------------------------
    // Estado (gravado na blockchain)
    // -------------------------------------------------------------------------

    uint256 private _nextId;  // contador de IDs, começa em 0, incrementa a cada criação

    // username → Identity (buscar identidade pelo nome)
    mapping(string => Identity) private _identityByUsername;

    // endereço da carteira → username (saber qual username uma carteira tem)
    mapping(address => string) private _usernameByController;

    // Endereço do RecoveryManager — único contrato autorizado a chamar recoverController.
    // Definido uma única vez após o deploy. Veja setRecoveryManager().
    address private _recoveryManager;

    // Quem fez o deploy deste contrato. Único endereço autorizado a chamar
    // setRecoveryManager — sem isso, qualquer um poderia chamá-la primeiro
    // na janela entre o deploy e a configuração oficial (front-running de
    // inicialização, o mesmo padrão do hack do Parity Multisig em 2017).
    address public immutable owner;

    // -------------------------------------------------------------------------
    // Eventos (notificações para o mundo externo)
    // -------------------------------------------------------------------------

    event IdentityCreated(uint256 indexed id, string username, address indexed controller);
    event ControllerTransferred(string username, address indexed oldController, address indexed newController);
    event RecoveryManagerSet(address indexed recoveryManager);

    // -------------------------------------------------------------------------
    // Erros customizados (mais eficientes que require com string)
    // -------------------------------------------------------------------------

    error UsernameTaken(string username);
    error AddressAlreadyHasIdentity(address controller);
    error IdentityNotFound(string username);
    error NotController(address caller, string username);
    error InvalidUsername();
    error RecoveryManagerAlreadySet();
    error NotRecoveryManager();
    error NotOwner();
    error InvalidNewController();

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor() {
        owner = msg.sender;
    }

    // -------------------------------------------------------------------------
    // Funções de escrita (modificam o estado → custam gas)
    // -------------------------------------------------------------------------

    /// Cria uma nova identidade. O chamador da função se torna o controller.
    function createIdentity(string calldata username) external returns (uint256 id) {
        _validateUsername(username);

        if (_identityByUsername[username].exists) {
            revert UsernameTaken(username);
        }
        if (bytes(_usernameByController[msg.sender]).length > 0) {
            revert AddressAlreadyHasIdentity(msg.sender);
        }

        id = ++_nextId;

        _identityByUsername[username] = Identity({
            id: id,
            username: username,
            controller: msg.sender,
            exists: true
        });

        _usernameByController[msg.sender] = username;

        emit IdentityCreated(id, username, msg.sender);
    }

    /// Transfere o controle da identidade para outra carteira.
    /// Só o controller atual pode fazer isso.
    function transferController(string calldata username, address newController) external {
        Identity storage identity = _identityByUsername[username];

        if (!identity.exists) revert IdentityNotFound(username);
        if (identity.controller != msg.sender) revert NotController(msg.sender, username);
        if (newController == address(0)) revert InvalidNewController();
        if (bytes(_usernameByController[newController]).length > 0) {
            revert AddressAlreadyHasIdentity(newController);
        }

        address oldController = identity.controller;

        delete _usernameByController[oldController];
        _usernameByController[newController] = username;
        identity.controller = newController;

        emit ControllerTransferred(username, oldController, newController);
    }

    // -------------------------------------------------------------------------
    // Funções do RecoveryManager
    // -------------------------------------------------------------------------

    /// Define o endereço do RecoveryManager. Só pode ser chamado uma vez.
    /// Ordem de deploy: (1) IdentityRegistry, (2) RecoveryManager, (3) esta função.
    function setRecoveryManager(address rm) external {
        if (msg.sender != owner) revert NotOwner();
        if (_recoveryManager != address(0)) revert RecoveryManagerAlreadySet();
        _recoveryManager = rm;
        emit RecoveryManagerSet(rm);
    }

    /// Troca o controller de uma identidade via recovery social.
    /// Só o RecoveryManager pode chamar — nunca um usuário diretamente.
    function recoverController(string calldata username, address newController) external {
        if (msg.sender != _recoveryManager) revert NotRecoveryManager();

        Identity storage identity = _identityByUsername[username];
        if (!identity.exists) revert IdentityNotFound(username);
        if (newController == address(0)) revert InvalidNewController();
        if (bytes(_usernameByController[newController]).length > 0) {
            revert AddressAlreadyHasIdentity(newController);
        }

        address oldController = identity.controller;

        delete _usernameByController[oldController];
        _usernameByController[newController] = username;
        identity.controller = newController;

        emit ControllerTransferred(username, oldController, newController);
    }

    // -------------------------------------------------------------------------
    // Funções de leitura (não modificam o estado → sem gas quando chamadas externamente)
    // -------------------------------------------------------------------------

    /// Retorna a identidade completa dado um username.
    function getIdentity(string calldata username) external view returns (Identity memory) {
        if (!_identityByUsername[username].exists) revert IdentityNotFound(username);
        return _identityByUsername[username];
    }

    /// Retorna o username de um controller. Retorna string vazia se não tiver.
    function getUsernameByController(address controller) external view returns (string memory) {
        return _usernameByController[controller];
    }

    /// Verifica se um username já está em uso.
    function isUsernameTaken(string calldata username) external view returns (bool) {
        return _identityByUsername[username].exists;
    }

    /// Retorna quantas identidades foram criadas até agora.
    function totalIdentities() external view returns (uint256) {
        return _nextId;
    }

    // -------------------------------------------------------------------------
    // Funções internas (auxiliares, não chamadas de fora)
    // -------------------------------------------------------------------------

    function _validateUsername(string calldata username) internal pure {
        bytes memory b = bytes(username);

        // Username não pode ser vazio nem muito longo
        if (b.length == 0 || b.length > 64) revert InvalidUsername();

        // Só permite: letras minúsculas, números, hífen e ponto
        for (uint256 i = 0; i < b.length; i++) {
            bytes1 c = b[i];
            bool valid = (c >= 0x61 && c <= 0x7A) // a-z
                || (c >= 0x30 && c <= 0x39)        // 0-9
                || c == 0x2D                        // hífen (-)
                || c == 0x2E;                       // ponto (.)
            if (!valid) revert InvalidUsername();
        }
    }
}
