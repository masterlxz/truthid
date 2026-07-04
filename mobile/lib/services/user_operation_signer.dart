import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart' show EthereumAddress;

import 'device_key_service.dart';
import '../utils/user_operation.dart';

// Assina uma UserOperationV07 com a device key (etapa 14.9.4).
//
// Reaproveita `computeUserOperationHash` (14.9.2, função pura, sem rede)
// para o hash e `DeviceKeyService.signHash` (já em produção via
// `SessionRegistry.createSession`) para a assinatura -- o formato produzido
// (personal_sign sobre o hash de 32 bytes -> r(32)||s(32)||v(1), s
// canônico/low-s, v em {27,28}) é exatamente o que
// `TruthIDAccount._validateSignature` espera. Nenhuma primitiva nova.
//
// Não depende de nada da 14.9.5 (montagem do fluxo real) -- recebe uma
// UserOperationV07 já preenchida (exceto a assinatura) e devolve uma cópia
// com `signature` setado, pronta para ser serializada pelo
// PimlicoBundlerClient.
Future<UserOperationV07> signUserOperation({
  required UserOperationV07 userOperation,
  required EthereumAddress entryPoint,
  required BigInt chainId,
  required DeviceKeyService deviceKeyService,
}) async {
  final userOpHash = computeUserOperationHash(
    userOperation: userOperation,
    entryPoint: entryPoint,
    chainId: chainId,
  );

  final signatureHex = await deviceKeyService.signHash(userOpHash);
  final signatureBytes = hexToBytes(signatureHex);

  assert(
    signatureBytes.length == 65,
    'DeviceKeyService.signHash deveria sempre devolver r(32)||s(32)||v(1) '
    '(65 bytes); recebeu ${signatureBytes.length}',
  );

  return userOperation.copyWith(signature: signatureBytes);
}
