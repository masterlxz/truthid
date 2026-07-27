import 'dart:async';

import 'package:flutter/material.dart';

import '../services/autofill_bridge_service.dart';
import '../services/vault_repository.dart';
import '../theme.dart';
import '../widgets/address_summary.dart';
import '../widgets/card_summary.dart';

enum _Status { loading, picking, sending, error }

/// Tela de aprovação do Android Autofill Framework (Fase 15.5) —
/// `TruthIdAutofillService` (nativo) detectou campos num app qualquer e
/// abriu isto via `PendingIntent` de autenticação. Mesmo padrão de picker
/// "1 de N entradas salvas" que a Fase 15.4 introduziu pro autofill via
/// navegador (`autofill_address_approval_screen.dart`/
/// `autofill_creditcard_approval_screen.dart`), mas sem entrega
/// cross-device — tudo local, termina num único `MethodChannel` de volta
/// pro nativo (`AutofillBridgeService.submitResult`), que o Android usa
/// pra preencher o campo de verdade.
///
/// Um único `Widget` cobre os 3 tipos (`entryType`) — a diferença entre
/// eles é só qual filtro/resumo/mapeamento de campo usar, não a estrutura
/// da tela.
class AutofillSystemFillScreen extends StatefulWidget {
  final String entryType;
  final String requestingPackage;
  final VaultRepository? repository;
  final AutofillBridgeService? bridge;

  const AutofillSystemFillScreen({
    super.key,
    required this.entryType,
    required this.requestingPackage,
    this.repository,
    this.bridge,
  });

  @override
  State<AutofillSystemFillScreen> createState() => _AutofillSystemFillScreenState();
}

class _AutofillSystemFillScreenState extends State<AutofillSystemFillScreen> {
  late _Status _status;
  String? _errorMsg;
  List<VaultEntry> _entries = [];

  late final VaultRepository _repository;
  late final AutofillBridgeService _bridge;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? VaultRepository();
    _bridge = widget.bridge ?? AutofillBridgeService();
    _status = _Status.loading;
    unawaited(_load());
  }

  EntryType get _wantedType => switch (widget.entryType) {
        'address' => EntryType.address,
        'creditCard' => EntryType.creditCard,
        _ => EntryType.credential,
      };

  Future<void> _load() async {
    try {
      final entries = await _repository.listEntries();
      final filtered = entries.where((e) => e.type == _wantedType).toList();
      if (!mounted) return;
      setState(() {
        _entries = filtered;
        _status = _Status.picking;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _Status.error;
        _errorMsg = 'Failed to load the Vault: $e';
      });
    }
  }

  Future<void> _pick(VaultEntry entry) async {
    setState(() => _status = _Status.sending);
    try {
      await _bridge.submitResult(_fieldsFor(entry));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _Status.error;
        _errorMsg = 'Failed to respond: $e';
      });
    }
  }

  Future<void> _cancel() async {
    await _bridge.cancel();
  }

  /// Mapeia os campos do `VaultEntry` escolhido pro vocabulário de papel
  /// que o lado nativo espera (`FieldRole.name` em Kotlin — ver
  /// `AutofillHintClassifier.kt`). `EMAIL` duplica o valor de `USERNAME`
  /// como melhor esforço: muitos formulários de login declaram o hint de
  /// e-mail em vez de usuário, e este Vault não distingue os dois campos.
  /// `CARD_EXPIRATION_DATE` (campo único "MM/AA") segue a mesma convenção
  /// que `creditCardFill.ts` (extensão) já usa — ano cortado pra 2 dígitos.
  Map<String, String> _fieldsFor(VaultEntry entry) {
    switch (_wantedType) {
      case EntryType.credential:
        return {
          'USERNAME': entry.username,
          'EMAIL': entry.username,
          'PASSWORD': entry.password,
        };
      case EntryType.address:
        final address = entry.address!;
        final fields = <String, String>{
          'FULL_NAME': address.fullName,
          'STREET_ADDRESS': address.number.isEmpty
              ? address.street
              : '${address.street}, ${address.number}',
          'POSTAL_CODE': address.zipCode,
          'LOCALITY': address.city,
          'REGION': address.state,
          'COUNTRY': address.country,
        };
        if ((address.phone ?? '').isNotEmpty) fields['PHONE'] = address.phone!;
        return fields;
      case EntryType.creditCard:
        final card = entry.creditCard!;
        final shortYear =
            card.expiryYear.length >= 2 ? card.expiryYear.substring(card.expiryYear.length - 2) : card.expiryYear;
        return {
          'CARD_NUMBER': card.cardNumber,
          'CARD_EXPIRATION_MONTH': card.expiryMonth,
          'CARD_EXPIRATION_YEAR': card.expiryYear,
          'CARD_EXPIRATION_DATE': '${card.expiryMonth}/$shortYear',
          'CARD_SECURITY_CODE': card.cvv,
        };
      case EntryType.document:
        return {};
    }
  }

  String _title(VaultEntry entry) => switch (_wantedType) {
        EntryType.address => addressTitle(entry.address!),
        EntryType.creditCard => cardTitle(entry.creditCard!),
        _ => entry.site,
      };

  String _subtitle(VaultEntry entry) => switch (_wantedType) {
        EntryType.address => addressSubtitle(entry.address!),
        EntryType.creditCard => cardSubtitle(entry.creditCard!),
        _ => entry.username,
      };

  String get _emptyMessage => switch (_wantedType) {
        EntryType.address => "You don't have any saved addresses yet.",
        EntryType.creditCard => "You don't have any saved cards yet.",
        _ => "You don't have any saved credentials yet.",
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Autofill request')),
      body: switch (_status) {
        _Status.loading => const Center(child: CircularProgressIndicator()),
        _Status.picking => _buildPickerUI(),
        _Status.sending => const Center(child: CircularProgressIndicator()),
        _Status.error => _buildErrorUI(),
      },
    );
  }

  Widget _buildPickerUI() {
    if (_entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_emptyMessage, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              OutlinedButton(onPressed: _cancel, child: const Text('Close')),
            ],
          ),
        ),
      );
    }
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Choose which saved entry to use to fill this form:',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 16),
            ..._entries.map((entry) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    onTap: () => _pick(entry),
                    title: Text(_title(entry)),
                    subtitle: Text(_subtitle(entry)),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                )),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _cancel,
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Cancel'),
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
              _errorMsg ?? 'Something went wrong.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: _cancel, child: const Text('Close')),
          ],
        ),
      ),
    );
  }
}
