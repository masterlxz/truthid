import 'dart:convert';
import 'dart:io';

import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart' show EthereumAddress;

import '../utils/user_operation.dart';

// Monta a URL do bundler Pimlico a partir da chave de API e da rede
// ("base", "base-sepolia", ...). Sem valor default de rede de propósito: o
// app hoje não tem nenhum conceito de chain selecionável — quem quiser rodar
// contra um bundler self-hosted constrói o próprio Uri e ignora este helper.
Uri pimlicoBundlerUrl({required String apiKey, required String network}) {
  return Uri.parse('https://api.pimlico.io/v2/$network/rpc?apikey=$apiKey');
}

// Transporte JSON-RPC genérico (método + params) usado pelo PimlicoBundlerClient.
// Espelha o dart:io HttpClient cru já usado em BlockchainService._ethCall,
// isolado numa classe (em vez de uma função solta) pra poder ser mockado com
// mocktail no mesmo padrão já usado no resto do app (ex: VaultKeyService).
class JsonRpcTransport {
  Future<dynamic> call(Uri url, String method, List<dynamic> params) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(url);
      request.headers.set('content-type', 'application/json');
      request.write(jsonEncode({
        'jsonrpc': '2.0',
        'method': method,
        'params': params,
        'id': 1,
      }));

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;

      if (json.containsKey('error')) {
        throw Exception('RPC error: ${json['error']}');
      }

      return json['result'];
    } finally {
      client.close();
    }
  }
}

String _bigIntToHex(BigInt value) => '0x${value.toRadixString(16)}';

BigInt _hexToBigInt(String hex) => BigInt.parse(hex.substring(2), radix: 16);

// Serializa uma UserOperationV07 para o formato "não empacotado" que o
// bundler espera via JSON-RPC — diferente do PackedUserOperation usado
// on-chain: aqui `factory`/`factoryData` e os 4 campos de paymaster ficam
// separados (não fundidos em initCode/paymasterAndData), espelhando
// `formatUserOperationRequest` do viem/account-abstraction.
Map<String, dynamic> _userOperationToRpc(UserOperationV07 op) {
  final json = <String, dynamic>{
    'sender': op.sender.hexEip55,
    'nonce': _bigIntToHex(op.nonce),
    'callData': bytesToHex(op.callData, include0x: true),
    'callGasLimit': _bigIntToHex(op.callGasLimit),
    'verificationGasLimit': _bigIntToHex(op.verificationGasLimit),
    'preVerificationGas': _bigIntToHex(op.preVerificationGas),
    'maxFeePerGas': _bigIntToHex(op.maxFeePerGas),
    'maxPriorityFeePerGas': _bigIntToHex(op.maxPriorityFeePerGas),
    'signature': bytesToHex(op.signature, include0x: true),
  };

  if (op.factory != null) {
    json['factory'] = op.factory!.hexEip55;
    json['factoryData'] = bytesToHex(op.factoryData, include0x: true);
  }

  if (op.paymaster != null) {
    json['paymaster'] = op.paymaster!.hexEip55;
    json['paymasterVerificationGasLimit'] =
        _bigIntToHex(op.paymasterVerificationGasLimit);
    json['paymasterPostOpGasLimit'] = _bigIntToHex(op.paymasterPostOpGasLimit);
    json['paymasterData'] = bytesToHex(op.paymasterData, include0x: true);
  }

  return json;
}

// Estimativa de gas devolvida por eth_estimateUserOperationGas. Os dois campos
// de paymaster só vêm preenchidos se a UserOperation enviada tinha paymaster.
class UserOperationGasEstimate {
  final BigInt callGasLimit;
  final BigInt verificationGasLimit;
  final BigInt preVerificationGas;
  final BigInt? paymasterVerificationGasLimit;
  final BigInt? paymasterPostOpGasLimit;

  const UserOperationGasEstimate({
    required this.callGasLimit,
    required this.verificationGasLimit,
    required this.preVerificationGas,
    this.paymasterVerificationGasLimit,
    this.paymasterPostOpGasLimit,
  });

  factory UserOperationGasEstimate._fromRpc(Map<String, dynamic> json) {
    return UserOperationGasEstimate(
      callGasLimit: _hexToBigInt(json['callGasLimit'] as String),
      verificationGasLimit:
          _hexToBigInt(json['verificationGasLimit'] as String),
      preVerificationGas: _hexToBigInt(json['preVerificationGas'] as String),
      paymasterVerificationGasLimit:
          json['paymasterVerificationGasLimit'] != null
              ? _hexToBigInt(json['paymasterVerificationGasLimit'] as String)
              : null,
      paymasterPostOpGasLimit: json['paymasterPostOpGasLimit'] != null
          ? _hexToBigInt(json['paymasterPostOpGasLimit'] as String)
          : null,
    );
  }
}

// Recibo devolvido por eth_getUserOperationReceipt — só os campos que o app
// consome hoje (não modela o tx receipt/logs completos, que ninguém usa ainda).
class UserOperationReceipt {
  final String userOpHash;
  final bool success;
  final BigInt actualGasCost;
  final BigInt actualGasUsed;
  final String transactionHash;

  const UserOperationReceipt({
    required this.userOpHash,
    required this.success,
    required this.actualGasCost,
    required this.actualGasUsed,
    required this.transactionHash,
  });

  factory UserOperationReceipt._fromRpc(Map<String, dynamic> json) {
    final receipt = json['receipt'] as Map<String, dynamic>;
    return UserOperationReceipt(
      userOpHash: json['userOpHash'] as String,
      success: json['success'] as bool,
      actualGasCost: _hexToBigInt(json['actualGasCost'] as String),
      actualGasUsed: _hexToBigInt(json['actualGasUsed'] as String),
      transactionHash: receipt['transactionHash'] as String,
    );
  }
}

// Cliente JSON-RPC do bundler Pimlico (ERC-4337 v0.7) — só as 3 chamadas de
// estimativa/envio/consulta de UserOperation. Sem lógica de assinatura
// (etapa 14.9.4) nem integração no fluxo real (etapa 14.9.5).
class PimlicoBundlerClient {
  final Uri bundlerUrl;
  final EthereumAddress entryPoint;
  final JsonRpcTransport _transport;

  PimlicoBundlerClient({
    required this.bundlerUrl,
    EthereumAddress? entryPoint,
    JsonRpcTransport? transport,
  })  : entryPoint =
            entryPoint ?? EthereumAddress.fromHex(entryPointV07Address),
        _transport = transport ?? JsonRpcTransport();

  Future<UserOperationGasEstimate> estimateUserOperationGas(
      UserOperationV07 op) async {
    final result = await _transport.call(
      bundlerUrl,
      'eth_estimateUserOperationGas',
      [_userOperationToRpc(op), entryPoint.hexEip55],
    );
    return UserOperationGasEstimate._fromRpc(result as Map<String, dynamic>);
  }

  Future<String> sendUserOperation(UserOperationV07 op) async {
    final result = await _transport.call(
      bundlerUrl,
      'eth_sendUserOperation',
      [_userOperationToRpc(op), entryPoint.hexEip55],
    );
    return result as String;
  }

  // Enquanto a UserOperation ainda não foi minerada, o bundler devolve
  // `result: null` (sem `error`) — por isso o retorno é anulável.
  Future<UserOperationReceipt?> getUserOperationReceipt(
      String userOpHash) async {
    final result = await _transport.call(
      bundlerUrl,
      'eth_getUserOperationReceipt',
      [userOpHash],
    );
    if (result == null) return null;
    return UserOperationReceipt._fromRpc(result as Map<String, dynamic>);
  }
}
