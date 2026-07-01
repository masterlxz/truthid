// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Layout exigido pelo EntryPoint v0.7 (ERC-4337). Declarada aqui — não
// importada de um pacote externo — porque este contrato não tem nenhuma
// dependência além do EntryPoint já deployado na chain (decisão travada
// na Sessão 52, Fase 14, ver PROJECT_STATE.md).
struct PackedUserOperation {
    address sender;
    uint256 nonce;
    bytes initCode;
    bytes callData;
    bytes32 accountGasLimits; // verificationGasLimit (128 bits) | callGasLimit (128 bits)
    uint256 preVerificationGas;
    bytes32 gasFees; // maxPriorityFeePerGas (128 bits) | maxFeePerGas (128 bits)
    bytes paymasterAndData;
    bytes signature;
}

// TruthIDAccount — smart account ERC-4337, fork conceitual do SimpleAccount
// (eth-infinitism), escrita do zero sem nenhuma dependência externa.
//
// Dois níveis de signer:
//   - owner (a chave Ledger): acesso total, qualquer chamada.
//   - authorizedDevices (mobile/desktop, dia a dia): só podem chamar
//     `execute`/`executeBatch`, e nunca mirando um destino bloqueado (ver
//     `blockedForDevices`) nem a própria smart account.
//
// Por que bloquear destino == address(this) para devices, e não só
// destino == deviceRegistry? Sem isso, um device autorizado poderia mandar
// `execute(address(this), 0, abi.encodeCall(addDevice, (atacante)))` — uma
// auto-chamada que faz `addDevice` enxergar `msg.sender == address(this)`
// e se autopromover, contornando a restrição de que só o owner gerencia
// devices. Bloquear esse destino já em `validateUserOp` fecha o caminho
// por completo, sem precisar decodificar recursivamente o calldata interno.
//
// Além do DeviceRegistry, qualquer outro contrato que só o owner deveria
// poder mexer (IdentityRegistry.transferController, RecoveryManager) TAMBÉM
// precisa ficar de fora do alcance de devices — senão o tier restrito vira
// só decoração. Por isso a lista de bloqueio (`blockedForDevices`) é um
// mapping semeado no constructor com DeviceRegistry/IdentityRegistry/
// RecoveryManager, e extensível pelo owner via `blockDestinationForDevices`
// — assim um contrato privilegiado adicionado numa fase futura não fica
// esquecido pra sempre (a conta não tem proxy, então um `immutable`
// esquecido hoje seria impossível de corrigir sem reimplantar tudo).
// `address(this)` continua checado à parte, fora do mapping: é o único
// destino que NUNCA pode ser desbloqueado, nem pelo owner.
contract TruthIDAccount {
    // -------------------------------------------------------------------------
    // Constantes
    // -------------------------------------------------------------------------

    uint256 internal constant SIG_VALIDATION_SUCCESS = 0;
    uint256 internal constant SIG_VALIDATION_FAILED = 1;

    // Metade superior da ordem da curva secp256k1. Usada para rejeitar
    // assinaturas não-canônicas (malleability, EIP-2) — o SimpleAccount
    // original ganha essa proteção de graça via OpenZeppelin's ECDSA; como
    // este contrato não usa dependências externas, replicamos manualmente.
    // Vale o custo (~100 gas): diferente do SessionRegistry (que só faz
    // bookkeeping de hash já commitado), esta conta custodia fundos direto.
    uint256 internal constant _SECP256K1N_DIV_2 =
        0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A;

    // -------------------------------------------------------------------------
    // Estado
    // -------------------------------------------------------------------------

    address public immutable entryPoint;
    address public immutable owner; // a chave Ledger — acesso total
    address public immutable deviceRegistry; // referência; comparação real via blockedForDevices
    address public immutable identityRegistry; // idem
    address public immutable recoveryManager; // idem

    // device (endereço derivado da chave pública) → autorizado?
    mapping(address => bool) public authorizedDevices;

    // destino → bloqueado para signers de tier device? Semeado no
    // constructor com DeviceRegistry/IdentityRegistry/RecoveryManager;
    // extensível pelo owner (ver `blockDestinationForDevices`).
    mapping(address => bool) public blockedForDevices;

    // -------------------------------------------------------------------------
    // Eventos
    // -------------------------------------------------------------------------

    event DeviceAdded(address indexed device);
    event DeviceRemoved(address indexed device);
    event DestinationBlockedForDevices(address indexed dest);
    event DestinationUnblockedForDevices(address indexed dest);

    // -------------------------------------------------------------------------
    // Erros customizados
    // -------------------------------------------------------------------------

    error InvalidConstructorArgs();
    error NotEntryPoint();
    error NotAuthorized();
    error InvalidDevice();
    error DeviceAlreadyAuthorized(address device);
    error DeviceNotAuthorized(address device);
    error ArrayLengthMismatch();
    error InvalidSignatureLength();

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(
        address entryPoint_,
        address deviceRegistry_,
        address identityRegistry_,
        address recoveryManager_,
        address owner_
    ) {
        if (
            entryPoint_ == address(0) || deviceRegistry_ == address(0)
                || identityRegistry_ == address(0) || recoveryManager_ == address(0)
                || owner_ == address(0)
        ) {
            revert InvalidConstructorArgs();
        }
        entryPoint = entryPoint_;
        deviceRegistry = deviceRegistry_;
        identityRegistry = identityRegistry_;
        recoveryManager = recoveryManager_;
        owner = owner_;

        blockedForDevices[deviceRegistry_] = true;
        blockedForDevices[identityRegistry_] = true;
        blockedForDevices[recoveryManager_] = true;
    }

    /// Recebe ETH diretamente — usado no setup inicial (Ledger transfere
    /// fundos pra smart account, etapa 14.7) e em reabastecimentos manuais.
    receive() external payable {}

    // -------------------------------------------------------------------------
    // Funções de escrita
    // -------------------------------------------------------------------------

    /// Ponto de entrada do EntryPoint para validar uma UserOperation.
    /// Recupera o signer, decide o nível de acesso e paga o prefund —
    /// sempre, mesmo se a validação falhar, porque o EntryPoint já gastou
    /// gas de validação e precisa ser ressarcido independentemente (mesmo
    /// comportamento do SimpleAccount original).
    function validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external returns (uint256 validationData) {
        if (msg.sender != entryPoint) revert NotEntryPoint();

        validationData = _validateSignature(userOp, userOpHash);

        if (missingAccountFunds != 0) {
            // O retorno de `call` é ignorado de propósito: o EntryPoint
            // confere o saldo efetivamente recebido por conta própria
            // logo em seguida — não há necessidade de revert aqui. A
            // variável é referenciada só pra satisfazer o linter
            // (`unchecked-call`), que sinalizaria isso como esquecimento.
            (bool success,) = payable(msg.sender).call{value: missingAccountFunds}("");
            success;
        }
    }

    /// Executa uma chamada. Chamável pelo EntryPoint (UserOp já validada),
    /// pelo owner diretamente (uso manual/testes) ou pela própria conta
    /// (auto-chamada vinda de outra função interna, ex: addDevice via
    /// execute) — ver `_requireAuthorized`.
    function execute(address dest, uint256 value, bytes calldata func) external {
        _requireAuthorized();
        _call(dest, value, func);
    }

    /// Executa um lote de chamadas. `dest`, `value` e `func` devem ter o
    /// mesmo tamanho (passe zeros explícitos em `value` pra chamadas sem ETH).
    function executeBatch(address[] calldata dest, uint256[] calldata value, bytes[] calldata func)
        external
    {
        _requireAuthorized();
        if (dest.length != func.length || dest.length != value.length) {
            revert ArrayLengthMismatch();
        }

        for (uint256 i = 0; i < dest.length; i++) {
            _call(dest[i], value[i], func[i]);
        }
    }

    /// Autoriza um device (mobile/desktop) a assinar UserOps no tier
    /// restrito. Mesma autorização de `execute` — owner, EntryPoint ou
    /// auto-chamada; os três só chegam aqui quando o signer da UserOp
    /// era o owner, pois o bloqueio de tier em `_isDeviceCallAllowed`
    /// fecha os outros caminhos antes da execução.
    function addDevice(address device) external {
        _requireAuthorized();
        if (device == address(0) || device == owner) revert InvalidDevice();
        if (authorizedDevices[device]) revert DeviceAlreadyAuthorized(device);
        authorizedDevices[device] = true;
        emit DeviceAdded(device);
    }

    /// Revoga um device. Mesma autorização de `addDevice`.
    function removeDevice(address device) external {
        _requireAuthorized();
        if (!authorizedDevices[device]) revert DeviceNotAuthorized(device);
        authorizedDevices[device] = false;
        emit DeviceRemoved(device);
    }

    /// Bloqueia um destino para signers de tier device (ver `_isDestAllowed`).
    /// Permite ao owner fechar o acesso de devices a um contrato privilegiado
    /// adicionado em fase futura, sem precisar reimplantar a conta — mesma
    /// autorização de `addDevice`.
    function blockDestinationForDevices(address dest) external {
        _requireAuthorized();
        blockedForDevices[dest] = true;
        emit DestinationBlockedForDevices(dest);
    }

    /// Desbloqueia um destino para devices. Mesma autorização de `addDevice`.
    /// Não afeta `address(this)`, que é bloqueado separadamente e nunca
    /// pode ser reaberto (ver `_isDestAllowed`).
    function unblockDestinationForDevices(address dest) external {
        _requireAuthorized();
        blockedForDevices[dest] = false;
        emit DestinationUnblockedForDevices(dest);
    }

    // -------------------------------------------------------------------------
    // Funções internas
    // -------------------------------------------------------------------------

    // owner: EOA chamando diretamente (testes/operações manuais).
    // entryPoint: UserOp cujo calldata de topo já é a própria função alvo.
    // address(this): auto-chamada originada de dentro de `execute`/`executeBatch`.
    function _requireAuthorized() internal view {
        if (msg.sender != entryPoint && msg.sender != owner && msg.sender != address(this)) {
            revert NotAuthorized();
        }
    }

    function _validateSignature(PackedUserOperation calldata userOp, bytes32 userOpHash)
        internal
        view
        returns (uint256)
    {
        (bytes32 r, bytes32 s, uint8 v) = _splitSignature(userOp.signature);

        if (uint256(s) > _SECP256K1N_DIV_2 || (v != 27 && v != 28)) {
            return SIG_VALIDATION_FAILED;
        }

        bytes32 ethSignedHash =
            keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", userOpHash));
        address signer = ecrecover(ethSignedHash, v, r, s);
        if (signer == address(0)) {
            return SIG_VALIDATION_FAILED;
        }

        if (signer == owner) {
            return SIG_VALIDATION_SUCCESS;
        }

        if (authorizedDevices[signer] && _isDeviceCallAllowed(userOp.callData)) {
            return SIG_VALIDATION_SUCCESS;
        }

        return SIG_VALIDATION_FAILED;
    }

    // Tier restrito (device): só `execute`/`executeBatch`, e nunca mirando
    // um destino bloqueado (DeviceRegistry/IdentityRegistry/RecoveryManager
    // por padrão, mais o que o owner bloquear depois) nem a própria smart
    // account — ver comentário no topo do arquivo sobre o caminho de
    // auto-promoção via auto-chamada.
    function _isDeviceCallAllowed(bytes calldata callData) internal view returns (bool) {
        if (callData.length < 4) return false;

        bytes4 selector;
        assembly {
            selector := calldataload(callData.offset)
        }

        if (selector == this.execute.selector) {
            // `dest` é o primeiro parâmetro de `execute` (address, uint256,
            // bytes) — sempre ocupa o primeiro word após o seletor, mesmo
            // com `func` (dinâmico) depois. Lê direto por assembly em vez
            // de `abi.decode`, pra não copiar `func` pra memória à toa
            // (mesmo padrão de `_splitSignature` neste arquivo).
            //
            // A máscara é essencial: `calldataload` traz a palavra de 32
            // bytes crua, sem a limpeza que `abi.decode` faria nos bits
            // superiores. Sem ela, um calldata malicioso com bits "sujos"
            // acima do endereço faria `dest != address(this)` comparar a
            // palavra suja inteira (sempre diferente do valor limpo),
            // reabrindo o próprio caminho de auto-promoção que este
            // bloqueio existe pra fechar.
            address dest;
            assembly {
                dest := and(
                    calldataload(add(callData.offset, 4)),
                    0xffffffffffffffffffffffffffffffffffffffff
                )
            }
            return _isDestAllowed(dest);
        }

        if (selector == this.executeBatch.selector) {
            // Decodifica só o primeiro elemento do tuple (`dest[]`) — o
            // primeiro word do calldata é sempre o offset desse elemento,
            // independente de quantos parâmetros dinâmicos vêm depois.
            // Evita copiar `value[]`/`func[]` pra memória, que não são
            // usados aqui.
            (address[] memory dest) = abi.decode(callData[4:], (address[]));
            for (uint256 i = 0; i < dest.length; i++) {
                if (!_isDestAllowed(dest[i])) return false;
            }
            return true;
        }

        return false;
    }

    function _isDestAllowed(address dest) internal view returns (bool) {
        return dest != address(this) && !blockedForDevices[dest];
    }

    function _splitSignature(bytes calldata signature)
        internal
        pure
        returns (bytes32 r, bytes32 s, uint8 v)
    {
        if (signature.length != 65) revert InvalidSignatureLength();
        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 32))
            v := byte(0, calldataload(add(signature.offset, 64)))
        }
    }

    function _call(address target, uint256 value, bytes memory data) internal {
        (bool success, bytes memory result) = target.call{value: value}(data);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }
}
