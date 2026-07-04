// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Interface mínima da factory — só o suficiente pra createIdentity conseguir
// perguntar "qual smart account esse endereco + indice vao ter?" sem precisar
// importar o contrato inteiro da TruthIDAccountFactory (evita criar um ciclo de
// import, ja que a factory por sua vez recebe o endereco deste registry no
// construtor). O indice 0 eh a conta principal; indices maiores permitem
// reset/multiplas contas por owner (debito #25).
interface ITruthIDAccountFactory {
    function getAddress(address owner, uint256 index) external view returns (address);
}

contract IdentityRegistry {
    // -------------------------------------------------------------------------
    // Tipos de dados
    // -------------------------------------------------------------------------

    struct Identity {
        uint256 id; // número único gerado automaticamente (1, 2, 3...)
        string username; // ex: "fabio.id"
        address controller; // carteira que controla essa identidade
        bool exists; // flag para saber se a identidade existe (ver nota abaixo)
    }

    // Nota sobre `exists`: em Solidity, acessar um mapping com uma chave que não
    // existe NÃO dá erro — retorna um valor "zerado" (0, "", address(0), false).
    // Sem esse campo, não conseguiríamos distinguir "identidade inexistente" de
    // "identidade com todos os campos em zero".

    // -------------------------------------------------------------------------
    // Estado (gravado na blockchain)
    // -------------------------------------------------------------------------

    uint256 private _nextId; // contador de IDs, começa em 0, incrementa a cada criação

    // username → Identity (buscar identidade pelo nome)
    mapping(string => Identity) private _identityByUsername;

    // endereço da carteira → username (saber qual username uma carteira tem)
    mapping(address => string) private _usernameByController;

    // Endereço do RecoveryManager — único contrato autorizado a chamar recoverController.
    // Definido uma única vez após o deploy. Veja setRecoveryManager().
    address private _recoveryManager;

    // Endereço da TruthIDAccountFactory confiável — usado só em createIdentity, pra
    // verificar que um `controller` do tipo "smart account pré-deploy" (CREATE2) é
    // realmente derivado do signer que assinou o consentimento (ver createIdentity).
    // Diferente do _recoveryManager, esse endereço PODE ser trocado depois de já
    // definido — a factory já foi redeployada 2x no histórico do projeto por motivos
    // de gas/limpeza, sem relação nenhuma com identidade; travar em "define uma vez só"
    // quebraria esse fluxo na próxima vez que a factory precisar de um redeploy.
    address private _factory;

    // Quem fez o deploy deste contrato. Único endereço autorizado a chamar
    // setRecoveryManager — sem isso, qualquer um poderia chamá-la primeiro
    // na janela entre o deploy e a configuração oficial (front-running de
    // inicialização, o mesmo padrão do hack do Parity Multisig em 2017).
    address public immutable owner;

    // -------------------------------------------------------------------------
    // Eventos (notificações para o mundo externo)
    // -------------------------------------------------------------------------

    event IdentityCreated(uint256 indexed id, string username, address indexed controller);
    event ControllerTransferred(
        string username, address indexed oldController, address indexed newController
    );
    event RecoveryManagerSet(address indexed recoveryManager);
    event FactorySet(address indexed factory);

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
    error InvalidConsentSignature();

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor() {
        owner = msg.sender;
    }

    // -------------------------------------------------------------------------
    // Funções de escrita (modificam o estado → custam gas)
    // -------------------------------------------------------------------------

    /// Cria uma nova identidade. O `controller` (quem vai controlar a identidade) pode ser
    /// qualquer endereço — tipicamente uma smart account pré-computada via CREATE2.
    /// O chamador (msg.sender) paga o gas mas não precisa ser o controller.
    ///
    /// Débito #17: antes desta versão, qualquer um podia chamar esta função com o
    /// `controller` de outra pessoa (ex: o endereço CREATE2 previsto da smart account
    /// alheia, calculável por qualquer um a partir do endereço Ledger público dela) e
    /// "carimbar" esse endereço antes do dono de verdade — griefing gratuito. Agora
    /// exigimos uma assinatura (v, r, s) provando consentimento sobre exatamente este
    /// par (username, controller), em uma das duas formas:
    ///   1. `controller` é um EOA comum: ele mesmo assina (signer == controller).
    ///   2. `controller` é uma smart account que ainda não existe on-chain: quem assina
    ///      é o dono da chave que vai virar o "owner" dela (ex: o Ledger). Como a smart
    ///      account em si não tem chave própria pra assinar antes de existir, verificamos
    ///      através da factory: `factory.getAddress(signer) == controller`.
    function createIdentity(
        string calldata username,
        address controller,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 id) {
        _validateUsername(username);
        if (controller == address(0)) revert InvalidNewController();
        if (v != 27 && v != 28) revert InvalidConsentSignature();

        if (_identityByUsername[username].exists) {
            revert UsernameTaken(username);
        }
        if (bytes(_usernameByController[controller]).length > 0) {
            revert AddressAlreadyHasIdentity(controller);
        }

        // Mesma convenção de assinatura já usada em TruthIDAccount/SessionRegistry:
        // hash cru dos dados relevantes, prefixo manual do "Ethereum Signed Message"
        // (é isso que uma carteira faz ao assinar via personal_sign/eth_sign), depois
        // ecrecover pra descobrir quem assinou. `abi.encode` (não `encodePacked`) aqui
        // porque `username` é de tamanho variável — encode evita ambiguidade entre
        // campos dinâmicos vizinhos.
        bytes32 hash = keccak256(abi.encode(block.chainid, address(this), username, controller));
        bytes32 ethSignedHash =
            keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
        address signer = ecrecover(ethSignedHash, v, r, s);
        if (signer == address(0)) revert InvalidConsentSignature();

        bool consented = signer == controller;
        if (!consented && _factory != address(0)) {
            consented = ITruthIDAccountFactory(_factory).getAddress(signer, 0) == controller;
        }
        if (!consented) revert InvalidConsentSignature();

        id = ++_nextId;

        _identityByUsername[username] =
            Identity({id: id, username: username, controller: controller, exists: true});

        _usernameByController[controller] = username;

        emit IdentityCreated(id, username, controller);
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

    /// Define (ou troca) o endereço da TruthIDAccountFactory confiável, usada em
    /// createIdentity pra validar consentimento de controllers do tipo smart account
    /// pré-deploy. Ao contrário de setRecoveryManager, pode ser chamada mais de uma
    /// vez — de propósito, pra acompanhar redeploys futuros da factory (já aconteceu
    /// 2x no histórico do projeto, por motivos de gas/limpeza sem relação com isto).
    function setFactory(address factory_) external {
        if (msg.sender != owner) revert NotOwner();
        _factory = factory_;
        emit FactorySet(factory_);
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
                || (c >= 0x30 && c <= 0x39) // 0-9
                || c == 0x2D // hífen (-)
                || c == 0x2E; // ponto (.)
            if (!valid) revert InvalidUsername();
        }
    }
}
