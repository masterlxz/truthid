import 'dart:async';

import 'package:flutter/widgets.dart';

import '../services/blockchain_service.dart';
import '../services/wallet_connect_service.dart';

/// Infra compartilhada pelos 4 flows WalletConnect do Mobile (P68) —
/// `CreateIdentityFlow`, `PairDeviceFlow`, `ConfigureGuardiansFlow`,
/// `ActAsGuardianFlow`. `connectWallet`/`_waitForReceipt` eram cópias
/// byte-a-byte nas 4 telas (achado de duplicação, P82 #4). `Step` é o enum
/// de passos próprio de cada flow — a mixin não conhece o enum inteiro, só
/// os 2 valores que ela mesma precisa setar.
mixin WalletConnectFlowMixin<Step> {
  WalletConnectService get walletConnect;
  BlockchainService get blockchain;

  bool get busy;
  set busy(bool value);

  String? get errorMessage;
  set errorMessage(String? value);

  String? get connectedAddress;
  set connectedAddress(String? value);

  Step get connectingWalletStep;
  Step get formStep;
  void setStep(Step step);

  Future<void> connectWallet(BuildContext context) async {
    if (busy) return;
    busy = true;
    errorMessage = null;
    setStep(connectingWalletStep);
    try {
      await walletConnect.init(context);
      await walletConnect.openConnectModal();
      connectedAddress = walletConnect.connectedAddress;
      setStep(formStep);
    } catch (e) {
      errorMessage = e.toString();
      setStep(formStep);
    } finally {
      busy = false;
    }
  }

  Future<bool> waitForReceipt(
    String txHash, {
    Duration timeout = const Duration(minutes: 5),
    Duration pollInterval = const Duration(seconds: 2),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final confirmed = await blockchain.isTransactionConfirmed(txHash);
      if (confirmed != null) return confirmed;
      await Future.delayed(pollInterval);
    }
    throw TimeoutException(
        'Transaction $txHash was not mined within $timeout.');
  }
}
