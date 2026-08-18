import 'dart:async';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/l10n_extensions.dart';
import '../services/totp_service.dart';
import '../services/vault_repository.dart';
import '../services/webauthn_service.dart' as webauthn;
import '../theme.dart';
import '../widgets/info_row.dart';
import 'vault_entry_form_screen.dart';

// Detalhe de uma entrada do Vault. Editar/apagar só aparece quando o device
// tem canWriteVault (ver project/INDEX.md, Sessão 97) — quem navega pra cá
// já checou isso (vault_screen.dart). Senha escondida por padrão.
class VaultEntryDetailScreen extends StatefulWidget {
  final VaultEntry entry;
  final bool canWrite;
  final VaultRepository? repository;

  const VaultEntryDetailScreen({
    super.key,
    required this.entry,
    this.canWrite = false,
    this.repository,
  });

  @override
  State<VaultEntryDetailScreen> createState() =>
      _VaultEntryDetailScreenState();
}

class _VaultEntryDetailScreenState extends State<VaultEntryDetailScreen> {
  late final VaultRepository _repository;
  late VaultEntry _entry;
  bool _passwordVisible = false;
  bool _cardNumberVisible = false;
  bool _cvvVisible = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? VaultRepository();
    _entry = widget.entry;
  }

  // Fase 15.3 — título por tipo, substitui `entry.site` hardcoded (AppBar +
  // diálogo de exclusão), mirror do `entryTitle`/título por tipo do Desktop.
  String _title(BuildContext context) => switch (_entry.type) {
        EntryType.credential => _entry.site,
        EntryType.document =>
          _entry.document?.name ?? context.l10n.vaultEntryDetailScreenDocumentFallbackTitle,
        EntryType.address =>
          _entry.address?.label ?? context.l10n.vaultEntryDetailScreenAddressFallbackTitle,
        EntryType.creditCard =>
          _entry.creditCard?.label ?? context.l10n.vaultEntryDetailScreenCardFallbackTitle,
      };

  void _copy(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.vaultEntryDetailScreenCopiedSnackbar(label))),
    );
  }

  String _formatBytes(int n) {
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  // Cache local primeiro (rápido, offline); se ausente (documento
  // adicionado em outro device e nunca buscado aqui),
  // VaultRepository.readDocumentContent busca pelo cid num gateway IPFS
  // público e confere o contentHash antes de decifrar.
  Future<void> _downloadDocument(DocumentData doc) async {
    Uint8List bytes;
    try {
      bytes = await _repository.readDocumentContent(
        _entry.id,
        cid: doc.cid,
        contentHash: doc.contentHash,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(context.l10n.vaultEntryDetailScreenLoadDocumentFailedSnackbar('$e'))),
        );
      }
      return;
    }
    final path = await FilePicker.platform.saveFile(
      fileName: doc.fileName,
      type: FileType.any,
      bytes: bytes,
    );
    if (path == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.vaultEntryDetailScreenDocumentSavedSnackbar)),
    );
  }

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => VaultEntryFormScreen(entry: _entry, repository: _repository),
      ),
    );
    if (saved == true) {
      final entries = await _repository.listEntries();
      final updated = entries.where((e) => e.id == _entry.id).toList();
      if (mounted && updated.isNotEmpty) {
        setState(() => _entry = updated.first);
      }
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.vaultEntryDetailScreenDeleteDialogTitle),
        content: Text(
            ctx.l10n.vaultEntryDetailScreenDeleteDialogContent(_title(ctx))),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(ctx.l10n.vaultEntryDetailScreenCancelButton)),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.l10n.vaultEntryDetailScreenDeleteButton,
                style: const TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _deleting = true);
    await _repository.deleteEntry(_entry.id);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final entry = _entry;

    return Scaffold(
      appBar: AppBar(
        title: Text(_title(context)),
        actions: widget.canWrite
            ? [
                IconButton(icon: const Icon(Icons.edit), onPressed: _deleting ? null : _edit),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _deleting ? null : _delete,
                ),
              ]
            : null,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (entry.type == EntryType.credential) ...[
              InfoRow(label: context.l10n.vaultEntryDetailScreenSiteLabel, value: entry.site),
              if (entry.url.isNotEmpty) ...[
                const SizedBox(height: 8),
                _LinkRow(url: entry.url),
              ],
              const SizedBox(height: 8),
              _CopyableRow(
                label: context.l10n.vaultEntryDetailScreenUsernameLabel,
                value: entry.username,
                onCopy: () =>
                    _copy(context.l10n.vaultEntryDetailScreenUsernameLabel, entry.username),
              ),
              const SizedBox(height: 8),
              _CopyableRow(
                label: context.l10n.vaultEntryDetailScreenPasswordLabel,
                value: entry.password,
                masked: !_passwordVisible,
                onToggleVisibility: () =>
                    setState(() => _passwordVisible = !_passwordVisible),
                onCopy: () =>
                    _copy(context.l10n.vaultEntryDetailScreenPasswordLabel, entry.password),
              ),
              if (entry.totpSecret != null && entry.totpSecret!.isNotEmpty) ...[
                const SizedBox(height: 8),
                _TotpCodeRow(
                  secret: entry.totpSecret!,
                  onCopy: (code) =>
                      _copy(context.l10n.vaultEntryDetailScreenTotpCodeLabel, code),
                ),
              ],
              if (entry.passkey != null) ...[
                const SizedBox(height: 8),
                _PasskeyRow(passkey: entry.passkey!),
              ],
            ],
            if (entry.type == EntryType.document && entry.document != null) ...[
              InfoRow(label: context.l10n.vaultEntryDetailScreenNameLabel, value: entry.document!.name),
              const SizedBox(height: 8),
              InfoRow(label: context.l10n.vaultEntryDetailScreenFileLabel, value: entry.document!.fileName),
              const SizedBox(height: 8),
              InfoRow(
                label: context.l10n.vaultEntryDetailScreenSizeLabel,
                value: context.l10n.vaultEntryDetailScreenSizeValue(
                    _formatBytes(entry.document!.fileSizeBytes), entry.document!.mimeType),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => _downloadDocument(entry.document!),
                icon: const Icon(Icons.download),
                label: Text(context.l10n.vaultEntryDetailScreenSaveToDeviceButton),
              ),
            ],
            if (entry.type == EntryType.address && entry.address != null) ...[
              InfoRow(label: context.l10n.vaultEntryDetailScreenFullNameLabel, value: entry.address!.fullName),
              const SizedBox(height: 8),
              InfoRow(
                label: context.l10n.vaultEntryDetailScreenStreetLabel,
                value: '${entry.address!.street}, ${entry.address!.number}',
              ),
              if (entry.address!.complement != null && entry.address!.complement!.isNotEmpty) ...[
                const SizedBox(height: 8),
                InfoRow(label: context.l10n.vaultEntryDetailScreenComplementLabel, value: entry.address!.complement!),
              ],
              const SizedBox(height: 8),
              InfoRow(label: context.l10n.vaultEntryDetailScreenNeighborhoodLabel, value: entry.address!.neighborhood),
              const SizedBox(height: 8),
              InfoRow(
                label: context.l10n.vaultEntryDetailScreenCityStateLabel,
                value: '${entry.address!.city}/${entry.address!.state}',
              ),
              const SizedBox(height: 8),
              InfoRow(label: context.l10n.vaultEntryDetailScreenZipCodeLabel, value: entry.address!.zipCode),
              const SizedBox(height: 8),
              InfoRow(label: context.l10n.vaultEntryDetailScreenCountryLabel, value: entry.address!.country),
              if (entry.address!.phone != null && entry.address!.phone!.isNotEmpty) ...[
                const SizedBox(height: 8),
                InfoRow(label: context.l10n.vaultEntryDetailScreenPhoneLabel, value: entry.address!.phone!),
              ],
            ],
            if (entry.type == EntryType.creditCard && entry.creditCard != null) ...[
              InfoRow(label: context.l10n.vaultEntryDetailScreenCardHolderLabel, value: entry.creditCard!.cardHolderName),
              const SizedBox(height: 8),
              _CopyableRow(
                label: context.l10n.vaultEntryDetailScreenCardNumberLabel,
                value: entry.creditCard!.cardNumber,
                masked: !_cardNumberVisible,
                onToggleVisibility: () =>
                    setState(() => _cardNumberVisible = !_cardNumberVisible),
                onCopy: () => _copy(
                    context.l10n.vaultEntryDetailScreenCardNumberLabel, entry.creditCard!.cardNumber),
              ),
              const SizedBox(height: 8),
              _CopyableRow(
                label: context.l10n.vaultEntryDetailScreenCvvLabel,
                value: entry.creditCard!.cvv,
                masked: !_cvvVisible,
                onToggleVisibility: () => setState(() => _cvvVisible = !_cvvVisible),
                onCopy: () => _copy(context.l10n.vaultEntryDetailScreenCvvLabel, entry.creditCard!.cvv),
              ),
              const SizedBox(height: 8),
              InfoRow(
                label: context.l10n.vaultEntryDetailScreenExpiryLabel,
                value: '${entry.creditCard!.expiryMonth}/${entry.creditCard!.expiryYear}',
              ),
              const SizedBox(height: 8),
              InfoRow(label: context.l10n.vaultEntryDetailScreenNetworkLabel, value: entry.creditCard!.cardNetwork.name),
              if (entry.creditCard!.bank != null && entry.creditCard!.bank!.isNotEmpty) ...[
                const SizedBox(height: 8),
                InfoRow(label: context.l10n.vaultEntryDetailScreenBankLabel, value: entry.creditCard!.bank!),
              ],
            ],
            if (entry.notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              InfoRow(label: context.l10n.vaultEntryDetailScreenNotesLabel, value: entry.notes),
            ],
            if (entry.profiles.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children:
                    entry.profiles.map((p) => Chip(label: Text(p))).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  final String url;
  const _LinkRow({required this.url});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => launchUrl(
        Uri.parse(url.contains('://') ? url : 'https://$url'),
        mode: LaunchMode.externalApplication,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Text(context.l10n.vaultEntryDetailScreenUrlLabel,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            Expanded(
              child: Text(
                url,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 15,
                  color: AppColors.accent,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
            const Icon(Icons.open_in_new, size: 18, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

// Mostra o código TOTP atual (RFC 6238), com contagem regressiva de 30s —
// mesmo padrão de Timer.periodic + cancel-em-dispose já usado em
// show_device_qr_screen.dart, adaptado pra um tick de 1s em vez de polling.
class _TotpCodeRow extends StatefulWidget {
  final String secret;
  final void Function(String code) onCopy;

  const _TotpCodeRow({required this.secret, required this.onCopy});

  @override
  State<_TotpCodeRow> createState() => _TotpCodeRowState();
}

class _TotpCodeRowState extends State<_TotpCodeRow> {
  static const _tickInterval = Duration(seconds: 1);
  Timer? _tickTimer;
  String _code = '······';
  int _remaining = 30;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tick();
    _tickTimer = Timer.periodic(_tickInterval, (_) => _tick());
  }

  void _tick() {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    try {
      final code = generateTotpCode(widget.secret, now);
      if (mounted) {
        setState(() {
          _code = code;
          _remaining = secondsRemaining(now);
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Text(context.l10n.vaultEntryDetailScreenTotpErrorText('$_error'),
          style: const TextStyle(color: AppColors.danger));
    }
    final formatted = '${_code.substring(0, 3)} ${_code.substring(3)}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Text(context.l10n.vaultEntryDetailScreenTotpLabel,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          Expanded(
            child: Text(formatted,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 15)),
          ),
          Text(context.l10n.vaultEntryDetailScreenTotpSecondsRemaining(_remaining),
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
          IconButton(
            icon: const Icon(Icons.copy, size: 20, color: AppColors.textMuted),
            onPressed: () => widget.onCopy(_code),
          ),
        ],
      ),
    );
  }
}

// Mostra a credencial passkey (RP ID + data de criação) com um botão
// "Testar assinatura" que roda uma cerimônia de asserção local, sem nenhum
// site real envolvido — mesmo papel que _TotpCodeRow cumpre pro 2FA, mas sem
// live-refresh (a passkey não tem "código atual", só uma ação sob demanda).
class _PasskeyRow extends StatefulWidget {
  final Passkey passkey;
  const _PasskeyRow({required this.passkey});

  @override
  State<_PasskeyRow> createState() => _PasskeyRowState();
}

enum _PasskeyTestResult { idle, ok, error }

class _PasskeyRowState extends State<_PasskeyRow> {
  _PasskeyTestResult _result = _PasskeyTestResult.idle;
  String? _error;

  void _test() {
    try {
      final random = Random.secure();
      final challenge = Uint8List.fromList(
        List<int>.generate(32, (_) => random.nextInt(256)),
      );
      webauthn.signAssertion(
        privateKeyHex: widget.passkey.privateKeyHex,
        rpId: widget.passkey.rpId,
        signCount: widget.passkey.signCount,
        challenge: challenge,
        origin: 'https://${widget.passkey.rpId}',
      );
      setState(() {
        _result = _PasskeyTestResult.ok;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _result = _PasskeyTestResult.error;
        _error = '$e';
      });
    }
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _result = _PasskeyTestResult.idle);
    });
  }

  @override
  Widget build(BuildContext context) {
    final created = widget.passkey.createdAt;
    final formattedDate =
        '${created.day.toString().padLeft(2, '0')}/${created.month.toString().padLeft(2, '0')}/${created.year}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Text('🔑 ', style: TextStyle(fontSize: 15)),
          Expanded(
            child: Text(
              '${widget.passkey.rpId} · $formattedDate',
              style: const TextStyle(fontSize: 14, color: AppColors.textMuted),
            ),
          ),
          if (_error != null)
            const Icon(Icons.error_outline, size: 18, color: AppColors.danger),
          TextButton(
            onPressed: _test,
            child: Text(
              _result == _PasskeyTestResult.ok
                  ? '✓'
                  : _result == _PasskeyTestResult.error
                      ? '✕'
                      : context.l10n.vaultEntryDetailScreenTestSignatureButton,
            ),
          ),
        ],
      ),
    );
  }
}

class _CopyableRow extends StatelessWidget {
  final String label;
  final String value;
  final bool masked;
  final VoidCallback? onToggleVisibility;
  final VoidCallback onCopy;

  const _CopyableRow({
    required this.label,
    required this.value,
    this.masked = false,
    this.onToggleVisibility,
    required this.onCopy,
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
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          Expanded(
            child: Text(
              // Máscara de tamanho fixo, não proporcional ao valor real —
              // evita vazar o comprimento da senha mesmo na tela de detalhe.
              masked ? '••••••••' : value,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 15),
            ),
          ),
          if (onToggleVisibility != null)
            IconButton(
              icon: Icon(masked ? Icons.visibility : Icons.visibility_off,
                  size: 20, color: AppColors.textMuted),
              onPressed: onToggleVisibility,
            ),
          IconButton(
            icon: const Icon(Icons.copy, size: 20, color: AppColors.textMuted),
            onPressed: onCopy,
          ),
        ],
      ),
    );
  }
}
