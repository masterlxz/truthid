import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/l10n_extensions.dart';
import '../services/cross_device_delivery_channel.dart';
import '../services/ecies_service.dart';
import '../services/ipfs_pin_client.dart';
import '../services/pinning_provider_service.dart';
import '../services/remote_signer_lan_server.dart';
import '../services/result_delivery_channel.dart';
import '../services/vault_lan_server_service.dart';
import '../services/vault_repository.dart';
import '../theme.dart';
import '../widgets/card_summary.dart';
import '../widgets/info_row.dart';

// Mesmo desenho de `AutofillAddressApprovalScreen` (Fase 15.4, fatia 1) —
// fatia 2 troca só o tipo de dado pedido/entregue. Estados idênticos, só
// renomeados pra clareza (loadingCards/pickingCard em vez de
// loadingAddresses/pickingAddress).
enum _Status {
  loadingCards,
  pickingCard,
  confirming,
  sending,
  sent,
  timeout,
  error,
}

/// Tela de aprovação de `truthid-autofill-creditcard` — a extensão de
/// navegador detectou um campo de cartão num formulário de checkout e pede
/// um dos cartões salvos no Vault. Mesmo padrão de picker "1 de N" que
/// `AutofillAddressApprovalScreen` introduziu na fatia 1 — número e CVV só
/// aparecem em claro na tela de confirmação (nunca no picker, que usa
/// `cardSubtitle` mascarado).
///
/// Schema do QR v1: { action: 'truthid-autofill-creditcard', v: 1,
///   sessionId, ephemeralPubKey, expiresAt, appName }
class AutofillCreditCardApprovalScreen extends StatefulWidget {
  final Map<String, dynamic> payload;
  final VaultRepository? repository;
  final EciesService? eciesService;
  final RemoteSignerLanServer? lanServer;
  final IpfsPinClient? ipfsPinClient;
  final PinningProviderService? pinningProviderService;
  final ResultDeliveryChannel? deliveryChannel;

  const AutofillCreditCardApprovalScreen({
    super.key,
    required this.payload,
    this.repository,
    this.eciesService,
    this.lanServer,
    this.ipfsPinClient,
    this.pinningProviderService,
    this.deliveryChannel,
  });

  @override
  State<AutofillCreditCardApprovalScreen> createState() =>
      _AutofillCreditCardApprovalScreenState();
}

class _AutofillCreditCardApprovalScreenState
    extends State<AutofillCreditCardApprovalScreen> {
  late _Status _status;
  String? _sessionId;
  String? _requesterPubKeyHex;
  DateTime? _expiresAt;
  String? _appName;
  String? _errorMsg;
  List<String> _localIps = [];
  String? _deadDropIpnsName;
  String? _deadDropError;

  List<VaultEntry> _cards = [];
  VaultEntry? _selected;
  bool _cardNumberVisible = false;
  bool _cvvVisible = false;

  late final VaultRepository _repository;
  late final EciesService _ecies;
  late final RemoteSignerLanServer _lanServer;
  late final IpfsPinClient _ipfsPinClient;
  late final PinningProviderService _pinningProviderService;
  ResultDeliveryChannel? _deliveryChannel;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? VaultRepository();
    _ecies = widget.eciesService ?? EciesService();
    _lanServer = widget.lanServer ?? RemoteSignerLanServer();
    _ipfsPinClient = widget.ipfsPinClient ?? IpfsPinClient();
    _pinningProviderService =
        widget.pinningProviderService ?? PinningProviderService();

    final validationError = _validatePayload();
    if (validationError != null) {
      _status = validationError;
      return;
    }
    _status = _Status.loadingCards;
    unawaited(_loadCards());
  }

  ResultDeliveryChannel _resolveDeliveryChannel() {
    return widget.deliveryChannel ??
        CrossDeviceDeliveryChannel(
          requesterPubKeyHex: _requesterPubKeyHex!,
          ecies: _ecies,
          lanServer: _lanServer,
          ipfsPinClient: _ipfsPinClient,
          pinningProviderService: _pinningProviderService,
        );
  }

  _Status? _validatePayload() {
    final v = widget.payload['v'];
    if (v != 1) {
      _errorMsg = context.l10n.autofillCreditcardApprovalScreenErrorInvalidVersion;
      return _Status.error;
    }

    final sessionId = widget.payload['sessionId'] as String?;
    if (sessionId == null || sessionId.isEmpty) {
      _errorMsg = context.l10n.autofillCreditcardApprovalScreenErrorMissingSessionId;
      return _Status.error;
    }

    final ephemeralPubKey = widget.payload['ephemeralPubKey'] as String?;
    if (ephemeralPubKey == null || ephemeralPubKey.isEmpty) {
      _errorMsg = context.l10n.autofillCreditcardApprovalScreenErrorMissingPubKey;
      return _Status.error;
    }

    final expiresAtMs = widget.payload['expiresAt'];
    if (expiresAtMs is! int) {
      _errorMsg = context.l10n.autofillCreditcardApprovalScreenErrorMissingExpiresAt;
      return _Status.error;
    }
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(expiresAtMs);
    if (expiresAt.isBefore(DateTime.now())) {
      _errorMsg = context.l10n.autofillCreditcardApprovalScreenErrorExpiredQr;
      return _Status.error;
    }

    final appName = (widget.payload['appName'] as String?)?.trim() ?? '';
    if (appName.isEmpty) {
      _errorMsg = context.l10n.autofillCreditcardApprovalScreenErrorMissingAppName;
      return _Status.error;
    }

    _sessionId = sessionId;
    _requesterPubKeyHex = ephemeralPubKey;
    _expiresAt = expiresAt;
    _appName = appName;
    return null;
  }

  Future<void> _loadCards() async {
    final entries = await _repository.listEntries();
    final cards =
        entries.where((e) => e.type == EntryType.creditCard).toList();
    if (!mounted) return;

    if (cards.isEmpty) {
      await _deliver({'status': 'no-cards'});
      return;
    }

    setState(() {
      _cards = cards;
      _status = _Status.pickingCard;
    });
  }

  void _pick(VaultEntry entry) {
    setState(() {
      _selected = entry;
      _cardNumberVisible = false;
      _cvvVisible = false;
      _status = _Status.confirming;
    });
  }

  void _backToPicker() {
    setState(() {
      _selected = null;
      _status = _Status.pickingCard;
    });
  }

  Future<void> _approve() async {
    final selected = _selected!;
    await _deliver({
      'status': 'filled',
      'card': selected.creditCard!.toJson(),
    });
  }

  Future<void> _reject() async {
    await _deliver({'status': 'rejected'});
  }

  Future<void> _deliver(Map<String, dynamic> result) async {
    setState(() {
      _status = _Status.sending;
      _deadDropIpnsName = null;
      _deadDropError = null;
    });

    unawaited(
      VaultLanServerService.getLocalIpAddresses()
          .then((ips) => setState(() => _localIps = ips))
          .catchError((_) => <String>[]),
    );

    try {
      final expiresAt = _expiresAt!;
      if (expiresAt.isBefore(DateTime.now())) {
        setState(() {
          _status = _Status.error;
          _errorMsg = context.l10n.autofillCreditcardApprovalScreenErrorSessionExpired;
        });
        return;
      }

      _deliveryChannel ??= _resolveDeliveryChannel();
      final delivered = await _deliveryChannel!.deliver(
        result: result,
        sessionId: _sessionId!,
        expiresAt: expiresAt,
      );

      if (!mounted) return;
      setState(() {
        _status = delivered.outcome == DeliveryOutcome.sent
            ? _Status.sent
            : _Status.timeout;
        _deadDropIpnsName = delivered.deadDropIpnsName;
        _deadDropError = delivered.deadDropError;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _Status.error;
        _errorMsg = context.l10n.autofillCreditcardApprovalScreenErrorRespondFailed('$e');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.autofillCreditcardApprovalScreenTitle)),
      body: switch (_status) {
        _Status.loadingCards =>
          const Center(child: CircularProgressIndicator()),
        _Status.pickingCard => _buildPickerUI(),
        _Status.confirming => _buildConfirmingUI(),
        _Status.sending => _buildSendingUI(),
        _Status.sent => _buildSentUI(),
        _Status.timeout => _buildTimeoutUI(),
        _Status.error => _buildErrorUI(),
      },
    );
  }

  Widget _buildPickerUI() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.credit_card, size: 64, color: AppColors.accent),
            const SizedBox(height: 16),
            Text(
              context.l10n.autofillCreditcardApprovalScreenPickerHeading(_appName ?? ''),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.autofillCreditcardApprovalScreenPickerPrompt,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 16),
            ..._cards.map((entry) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    onTap: () => _pick(entry),
                    title: Text(cardTitle(entry.creditCard!)),
                    subtitle: Text(cardSubtitle(entry.creditCard!)),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                )),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _reject,
              icon: const Icon(Icons.cancel_outlined),
              label: Text(context.l10n.autofillCreditcardApprovalScreenDenyButton),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger,
                side: const BorderSide(color: AppColors.danger),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfirmingUI() {
    final card = _selected!.creditCard!;
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.credit_card, size: 64, color: AppColors.accent),
            const SizedBox(height: 16),
            Text(
              context.l10n.autofillCreditcardApprovalScreenConfirmHeading(_appName ?? ''),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            InfoRow(label: context.l10n.autofillCreditcardApprovalScreenFieldLabel, value: card.label),
            const SizedBox(height: 8),
            InfoRow(
              label: context.l10n.autofillCreditcardApprovalScreenFieldCardHolder,
              value: card.cardHolderName,
            ),
            const SizedBox(height: 8),
            _MaskedInfoRow(
              label: context.l10n.autofillCreditcardApprovalScreenFieldCardNumber,
              value: card.cardNumber,
              visible: _cardNumberVisible,
              onToggle: () =>
                  setState(() => _cardNumberVisible = !_cardNumberVisible),
            ),
            const SizedBox(height: 8),
            InfoRow(
              label: context.l10n.autofillCreditcardApprovalScreenFieldExpiry,
              value: '${card.expiryMonth}/${card.expiryYear}',
            ),
            const SizedBox(height: 8),
            _MaskedInfoRow(
              label: context.l10n.autofillCreditcardApprovalScreenFieldCvv,
              value: card.cvv,
              visible: _cvvVisible,
              onToggle: () => setState(() => _cvvVisible = !_cvvVisible),
            ),
            const SizedBox(height: 8),
            InfoRow(
              label: context.l10n.autofillCreditcardApprovalScreenFieldNetwork,
              value: card.cardNetwork.name,
            ),
            if (card.bank != null && card.bank!.isNotEmpty) ...[
              const SizedBox(height: 8),
              InfoRow(label: context.l10n.autofillCreditcardApprovalScreenFieldBank, value: card.bank!),
            ],
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _approve,
              icon: const Icon(Icons.check_circle_outline),
              label: Text(
                context.l10n.autofillCreditcardApprovalScreenApproveButton,
                style: const TextStyle(fontSize: 18),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: AppColors.background,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _reject,
              icon: const Icon(Icons.cancel_outlined),
              label: Text(
                context.l10n.autofillCreditcardApprovalScreenRejectButton,
                style: const TextStyle(fontSize: 18),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger,
                side: const BorderSide(color: AppColors.danger),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            if (_cards.length > 1) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: _backToPicker,
                child: Text(context.l10n.autofillCreditcardApprovalScreenChooseDifferentButton),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSendingUI() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 48),
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 24),
            Text(
              context.l10n.autofillCreditcardApprovalScreenWaitingTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.autofillCreditcardApprovalScreenWaitingSubtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted),
            ),
            if (_localIps.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                context.l10n.autofillCreditcardApprovalScreenManualIpPrompt,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: 8),
              ..._localIps.map(
                (ip) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    ip,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSentUI() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_outline,
                size: 72, color: AppColors.accent),
            const SizedBox(height: 16),
            Text(
              context.l10n.autofillCreditcardApprovalScreenSentTitle,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.autofillCreditcardApprovalScreenSentSubtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted),
            ),
            if (_deadDropIpnsName != null) ...[
              const SizedBox(height: 8),
              Text(
                context.l10n.autofillCreditcardApprovalScreenDeadDropPublished,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ] else if (_deadDropError != null) ...[
              const SizedBox(height: 8),
              Text(
                context.l10n.autofillCreditcardApprovalScreenDeadDropUnavailable,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.l10n.autofillCreditcardApprovalScreenDoneButton),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeoutUI() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off, size: 72, color: AppColors.textMuted),
            const SizedBox(height: 16),
            Text(
              context.l10n.autofillCreditcardApprovalScreenTimeoutTitle,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.autofillCreditcardApprovalScreenTimeoutSubtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.l10n.autofillCreditcardApprovalScreenBackButton),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorUI() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 72, color: AppColors.danger),
            const SizedBox(height: 16),
            Text(
              _errorMsg ?? context.l10n.autofillCreditcardApprovalScreenGenericError,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.l10n.autofillCreditcardApprovalScreenBackButton),
            ),
          ],
        ),
      ),
    );
  }
}

// Mesmo layout de `InfoRow`, mas com valor mascarado por padrão + botão de
// revelar — número de cartão e CVV são mais sensíveis que os campos de
// endereço que `InfoRow` sozinho já cobria na fatia 1, então não reusa o
// widget puro aqui.
class _MaskedInfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool visible;
  final VoidCallback onToggle;

  const _MaskedInfoRow({
    required this.label,
    required this.value,
    required this.visible,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Text(
            context.l10n.autofillCreditcardApprovalScreenMaskedLabelSuffix(label),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          Expanded(
            child: Text(
              // Máscara de tamanho fixo, não proporcional ao valor real —
              // evita vazar o comprimento do número/CVV mesmo mascarado
              // (achado da 15.8: `'•' * value.length` distinguia um CVV de
              // 3 x 4 dígitos, ou um PAN Amex de 15 x Visa/Master de 16).
              // Mesmo padrão de `_CopyableRow` em vault_entry_detail_screen.dart.
              visible ? value : '••••••••',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 15),
            ),
          ),
          IconButton(
            icon: Icon(visible ? Icons.visibility_off : Icons.visibility),
            onPressed: onToggle,
          ),
        ],
      ),
    );
  }
}
