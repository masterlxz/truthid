import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/totp_service.dart';
import '../services/vault_repository.dart';
import '../services/webauthn_service.dart' as webauthn;
import '../theme.dart';
import '../utils/password_generator.dart';
import '../utils/password_strength.dart';
import 'scan_screen.dart';

// Tela compartilhada de criar/editar uma entrada do vault — mirror do
// `EntryForm` do Desktop (`VaultManagement.tsx`). `entry` null = criar.
// Só alcançável quando o device tem canWriteVault (checado por quem navega
// pra cá, ver vault_screen.dart), ver project/INDEX.md, Sessão 97.
class VaultEntryFormScreen extends StatefulWidget {
  final VaultEntry? entry;
  final VaultRepository? repository;

  const VaultEntryFormScreen({super.key, this.entry, this.repository});

  @override
  State<VaultEntryFormScreen> createState() => _VaultEntryFormScreenState();
}

class _VaultEntryFormScreenState extends State<VaultEntryFormScreen> {
  late final VaultRepository _repository;
  final _siteCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _totpSecretCtrl = TextEditingController();

  // Fase 15.3 — endereço
  final _addrLabelCtrl = TextEditingController();
  final _addrFullNameCtrl = TextEditingController();
  final _addrStreetCtrl = TextEditingController();
  final _addrNumberCtrl = TextEditingController();
  final _addrComplementCtrl = TextEditingController();
  final _addrNeighborhoodCtrl = TextEditingController();
  final _addrCityCtrl = TextEditingController();
  final _addrStateCtrl = TextEditingController();
  final _addrZipCodeCtrl = TextEditingController();
  final _addrCountryCtrl = TextEditingController();
  final _addrPhoneCtrl = TextEditingController();

  // Fase 15.3 — cartão de crédito
  final _cardLabelCtrl = TextEditingController();
  final _cardHolderNameCtrl = TextEditingController();
  final _cardNumberCtrl = TextEditingController();
  final _cardExpiryMonthCtrl = TextEditingController();
  final _cardExpiryYearCtrl = TextEditingController();
  final _cardCvvCtrl = TextEditingController();
  final _cardBankCtrl = TextEditingController();
  CardNetwork _cardNetwork = CardNetwork.visa;

  // Fase 15.3 — documento (sem controller pros campos derivados do arquivo)
  final _docNameCtrl = TextEditingController();
  String? _docFileName;
  /// Base64 do arquivo escolhido nesta sessão de edição (Fase 15.7) — só em
  /// memória local, nunca vai no payload de addEntry/updateEntry. Vazio
  /// numa edição que não troca o arquivo (o conteúdo já publicado continua
  /// intocado, ver [_docCid]/[_docContentHash]).
  String? _docFileData;
  String? _docMimeType;
  int? _docFileSizeBytes;
  /// true se esta entrada (edição) já tinha um documento salvo antes —
  /// permite salvar sem re-escolher o arquivo.
  bool _docHasStoredContent = false;
  String? _docCid;
  String? _docContentHash;
  String? _docError;

  List<String> _profileOptions = [];
  final Set<String> _selectedProfiles = {};
  bool _showPassword = false;
  bool _loadingProfiles = true;
  bool _saving = false;
  String? _error;
  String? _totpError;
  Passkey? _passkey;
  EntryType _type = EntryType.credential;

  bool get _isEditing => widget.entry != null;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? VaultRepository();
    final entry = widget.entry;
    if (entry != null) {
      _type = entry.type;
      _siteCtrl.text = entry.site;
      _urlCtrl.text = entry.url;
      _usernameCtrl.text = entry.username;
      _passwordCtrl.text = entry.password;
      _notesCtrl.text = entry.notes;
      _selectedProfiles.addAll(entry.profiles);
      _totpSecretCtrl.text = entry.totpSecret ?? '';
      _passkey = entry.passkey;

      final document = entry.document;
      if (document != null) {
        _docNameCtrl.text = document.name;
        _docFileName = document.fileName;
        _docMimeType = document.mimeType;
        _docFileSizeBytes = document.fileSizeBytes;
        _docHasStoredContent = true;
        _docCid = document.cid;
        _docContentHash = document.contentHash;
      }

      final address = entry.address;
      if (address != null) {
        _addrLabelCtrl.text = address.label;
        _addrFullNameCtrl.text = address.fullName;
        _addrStreetCtrl.text = address.street;
        _addrNumberCtrl.text = address.number;
        _addrComplementCtrl.text = address.complement ?? '';
        _addrNeighborhoodCtrl.text = address.neighborhood;
        _addrCityCtrl.text = address.city;
        _addrStateCtrl.text = address.state;
        _addrZipCodeCtrl.text = address.zipCode;
        _addrCountryCtrl.text = address.country;
        _addrPhoneCtrl.text = address.phone ?? '';
      }

      final creditCard = entry.creditCard;
      if (creditCard != null) {
        _cardLabelCtrl.text = creditCard.label;
        _cardHolderNameCtrl.text = creditCard.cardHolderName;
        _cardNumberCtrl.text = creditCard.cardNumber;
        _cardExpiryMonthCtrl.text = creditCard.expiryMonth;
        _cardExpiryYearCtrl.text = creditCard.expiryYear;
        _cardCvvCtrl.text = creditCard.cvv;
        _cardBankCtrl.text = creditCard.bank ?? '';
        _cardNetwork = creditCard.cardNetwork;
      }
    }
    _loadProfileOptions();
  }

  // Deriva um hostname pra usar como RP ID — tenta a URL, cai pro nome do
  // site (sanitizado) se estiver vazia/inválida. Sem redução pra domínio
  // registrável (eTLD+1) nesta fase, mesmo critério do Desktop
  // (VaultManagement.tsx, hostnameOf).
  String _hostnameOf(String url, String site) {
    final uri = Uri.tryParse(url);
    if (uri != null && uri.host.isNotEmpty) return uri.host;
    final sanitized = site.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9.-]'), '');
    return sanitized.isNotEmpty ? sanitized : 'unknown';
  }

  void _generatePasskey() {
    final rpId = _hostnameOf(_urlCtrl.text, _siteCtrl.text);
    final random = Random.secure();
    final challenge = Uint8List.fromList(List<int>.generate(32, (_) => random.nextInt(256)));
    final created = webauthn.createPasskey(
      rpId: rpId,
      challenge: challenge,
      origin: 'https://$rpId',
    );
    setState(() {
      _passkey = Passkey(
        rpId: rpId,
        credentialIdB64: created.credentialIdB64,
        userHandleB64: created.userHandleB64,
        privateKeyHex: created.privateKeyHex,
        signCount: created.signCount,
        createdAt: DateTime.fromMillisecondsSinceEpoch(created.createdAt * 1000, isUtc: true),
      );
    });
  }

  // Abre o painel de opções do gerador de senha (mirror do painel inline do
  // Desktop em VaultManagement.tsx) e devolve a senha escolhida, ou null se
  // o usuário cancelar sem confirmar. showModalBottomSheet + StatefulBuilder
  // é o único precedente de painel de opções com estado mutável no Mobile
  // (ver wallet_screen.dart, _showDepositSheet).
  Future<void> _openPasswordGenerator() async {
    var options = const PasswordGeneratorOptions(
      length: 16,
      uppercase: true,
      lowercase: true,
      numbers: true,
      symbols: true,
    );
    var preview = '';
    String? error;

    void regenerate() {
      try {
        preview = generatePassword(options);
        error = null;
      } catch (e) {
        preview = '';
        error = '$e';
      }
    }

    regenerate();

    final generated = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 32,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Generate password',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('Length', style: TextStyle(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: options.length <= 1
                          ? null
                          : () => setSheetState(() {
                                options = options.copyWith(length: options.length - 1);
                                regenerate();
                              }),
                    ),
                    Text('${options.length}', style: const TextStyle(fontSize: 16)),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: () => setSheetState(() {
                        options = options.copyWith(length: options.length + 1);
                        regenerate();
                      }),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    ('Uppercase', options.uppercase,
                        (bool v) => options.copyWith(uppercase: v)),
                    ('Lowercase', options.lowercase,
                        (bool v) => options.copyWith(lowercase: v)),
                    ('Numbers', options.numbers, (bool v) => options.copyWith(numbers: v)),
                    ('Symbols', options.symbols, (bool v) => options.copyWith(symbols: v)),
                  ].map((entry) {
                    final (label, selected, apply) = entry;
                    return FilterChip(
                      label: Text(label),
                      selected: selected,
                      onSelected: (v) => setSheetState(() {
                        options = apply(v);
                        regenerate();
                      }),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          preview.isNotEmpty ? preview : '—',
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 15),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Regenerate',
                        onPressed: () => setSheetState(regenerate),
                      ),
                    ],
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
                ],
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: preview.isEmpty ? null : () => Navigator.of(ctx).pop(preview),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.background,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Use this password'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (generated != null) setState(() => _passwordCtrl.text = generated);
  }

  static const _strengthColors = [
    AppColors.danger,
    AppColors.warning,
    AppColors.accent,
    AppColors.success,
  ];

  Widget _buildStrengthMeter() {
    if (_passwordCtrl.text.isEmpty) return const SizedBox.shrink();
    final result = passwordStrength(_passwordCtrl.text);
    final color = _strengthColors[result.score];
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: List.generate(4, (i) {
                return Expanded(
                  child: Container(
                    height: 4,
                    margin: EdgeInsets.only(right: i < 3 ? 3 : 0),
                    decoration: BoxDecoration(
                      color: i <= result.score ? color : AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(width: 8),
          Text(result.label, style: TextStyle(fontSize: 11, color: color)),
        ],
      ),
    );
  }

  Future<void> _loadProfileOptions() async {
    final names = await _repository.listProfileNames();
    if (mounted) setState(() { _profileOptions = names; _loadingProfiles = false; });
  }

  @override
  void dispose() {
    _siteCtrl.dispose();
    _urlCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _notesCtrl.dispose();
    _totpSecretCtrl.dispose();
    _addrLabelCtrl.dispose();
    _addrFullNameCtrl.dispose();
    _addrStreetCtrl.dispose();
    _addrNumberCtrl.dispose();
    _addrComplementCtrl.dispose();
    _addrNeighborhoodCtrl.dispose();
    _addrCityCtrl.dispose();
    _addrStateCtrl.dispose();
    _addrZipCodeCtrl.dispose();
    _addrCountryCtrl.dispose();
    _addrPhoneCtrl.dispose();
    _cardLabelCtrl.dispose();
    _cardHolderNameCtrl.dispose();
    _cardNumberCtrl.dispose();
    _cardExpiryMonthCtrl.dispose();
    _cardExpiryYearCtrl.dispose();
    _cardCvvCtrl.dispose();
    _cardBankCtrl.dispose();
    _docNameCtrl.dispose();
    super.dispose();
  }

  bool get _canSaveForm => switch (_type) {
        EntryType.credential =>
          _siteCtrl.text.trim().isNotEmpty &&
              _usernameCtrl.text.trim().isNotEmpty &&
              _passwordCtrl.text.trim().isNotEmpty,
        EntryType.document =>
          _docNameCtrl.text.trim().isNotEmpty &&
              (_docFileData != null || _docHasStoredContent),
        EntryType.address =>
          _addrLabelCtrl.text.trim().isNotEmpty &&
              _addrFullNameCtrl.text.trim().isNotEmpty &&
              _addrStreetCtrl.text.trim().isNotEmpty &&
              _addrNumberCtrl.text.trim().isNotEmpty &&
              _addrNeighborhoodCtrl.text.trim().isNotEmpty &&
              _addrCityCtrl.text.trim().isNotEmpty &&
              _addrStateCtrl.text.trim().isNotEmpty &&
              _addrZipCodeCtrl.text.trim().isNotEmpty &&
              _addrCountryCtrl.text.trim().isNotEmpty,
        EntryType.creditCard =>
          _cardLabelCtrl.text.trim().isNotEmpty &&
              _cardHolderNameCtrl.text.trim().isNotEmpty &&
              _cardNumberCtrl.text.trim().isNotEmpty &&
              _cardExpiryMonthCtrl.text.trim().isNotEmpty &&
              _cardExpiryYearCtrl.text.trim().isNotEmpty &&
              _cardCvvCtrl.text.trim().isNotEmpty,
      };

  // 50MB — limite definitivo da Fase 15.7 (mirror de MAX_DOCUMENT_BYTES em
  // VaultManagement.tsx). Documentos agora vivem em blobs IPFS separados do
  // vault principal, então um documento grande não infla mais o sync de
  // senhas/endereços/cartões — o antigo limite de 10MB era só provisório,
  // escolhido quando tudo ainda vivia embutido no mesmo blob.
  static const _maxDocumentBytes = 50 * 1024 * 1024;

  static const _mimeByExt = {
    'pdf': 'application/pdf', 'png': 'image/png', 'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg', 'gif': 'image/gif', 'webp': 'image/webp',
    'bmp': 'image/bmp', 'svg': 'image/svg+xml', 'txt': 'text/plain',
    'csv': 'text/csv', 'json': 'application/json',
    'doc': 'application/msword',
    'docx':
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx':
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  };

  String _formatBytes(int n) {
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _pickDocument() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (bytes == null || !mounted) return;
    if (bytes.length > _maxDocumentBytes) {
      setState(() => _docError =
          'File too large (${_formatBytes(bytes.length)}) — limit is ${_formatBytes(_maxDocumentBytes)}.');
      return;
    }
    final ext = file!.name.split('.').last.toLowerCase();
    setState(() {
      _docError = null;
      _docFileName = file.name;
      _docFileData = base64Encode(bytes);
      _docFileSizeBytes = bytes.length;
      _docMimeType = _mimeByExt[ext] ?? 'application/octet-stream';
      if (_docNameCtrl.text.trim().isEmpty) _docNameCtrl.text = file.name;
    });
  }

  // Fase 15.3 — monta os 3 grupos opcionais de uma vez só, só o do `_type`
  // ativo fica não-nulo. Chamado num único call site em `_save()`, que
  // sempre espalha os 3 campos — diferente do Desktop (VaultManagement.tsx),
  // onde um switch com 4 branches cada um tinha que lembrar de zerar os
  // outros 2 grupos (e um deles esqueceu, na Sessão 168), aqui não existe
  // branch nenhum que só devolva o grupo novo sem tocar nos outros 2.
  ({DocumentData? document, AddressData? address, CreditCardData? creditCard})
      get _dataGroups => (
            document: _type == EntryType.document
                ? DocumentData(
                    name: _docNameCtrl.text.trim(),
                    fileName: _docFileName ?? '',
                    fileSizeBytes: _docFileSizeBytes ?? 0,
                    mimeType: _docMimeType ?? 'application/octet-stream',
                    // Um arquivo novo invalida o pin antigo — o próximo
                    // publish repina o conteúdo novo (ver
                    // VaultPublishService.publish).
                    cid: _docFileData != null ? null : _docCid,
                    contentHash: _docFileData != null ? null : _docContentHash,
                  )
                : null,
            address: _type == EntryType.address
                ? AddressData(
                    label: _addrLabelCtrl.text.trim(),
                    fullName: _addrFullNameCtrl.text.trim(),
                    street: _addrStreetCtrl.text.trim(),
                    number: _addrNumberCtrl.text.trim(),
                    complement: _addrComplementCtrl.text.trim().isEmpty
                        ? null
                        : _addrComplementCtrl.text.trim(),
                    neighborhood: _addrNeighborhoodCtrl.text.trim(),
                    city: _addrCityCtrl.text.trim(),
                    state: _addrStateCtrl.text.trim(),
                    zipCode: _addrZipCodeCtrl.text.trim(),
                    country: _addrCountryCtrl.text.trim(),
                    phone: _addrPhoneCtrl.text.trim().isEmpty
                        ? null
                        : _addrPhoneCtrl.text.trim(),
                  )
                : null,
            creditCard: _type == EntryType.creditCard
                ? CreditCardData(
                    label: _cardLabelCtrl.text.trim(),
                    cardHolderName: _cardHolderNameCtrl.text.trim(),
                    cardNumber: _cardNumberCtrl.text.trim(),
                    expiryMonth: _cardExpiryMonthCtrl.text.trim(),
                    expiryYear: _cardExpiryYearCtrl.text.trim(),
                    cvv: _cardCvvCtrl.text.trim(),
                    bank: _cardBankCtrl.text.trim().isEmpty
                        ? null
                        : _cardBankCtrl.text.trim(),
                    cardNetwork: _cardNetwork,
                  )
                : null,
          );

  void _onTotpChanged(String value) {
    setState(() {
      if (value.trim().isEmpty) {
        _totpError = null;
        return;
      }
      try {
        parseTotpSecret(value);
        _totpError = null;
      } catch (e) {
        _totpError = '$e';
      }
    });
  }

  // Reaproveita a mesma câmera do pareamento (mobile_scanner), agora
  // generalizada em ScanScreen<T>. parseTotpSecret já sabe extrair o secret
  // de um otpauth://... (formato que a maioria dos sites codifica no QR de
  // configuração do 2FA) — QR inválido faz a tela de scan mostrar o aviso e
  // continuar escaneando, sem fechar.
  Future<void> _scanTotpQr() async {
    final secret = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => ScanScreen<String>(
          title: 'Scan 2FA QR code',
          instructions:
              'Point the camera at the QR code shown when setting up 2FA',
          parse: (raw) {
            try {
              return parseTotpSecret(raw);
            } catch (_) {
              return null;
            }
          },
        ),
      ),
    );
    if (secret == null || !mounted) return;
    _totpSecretCtrl.text = secret;
    _onTotpChanged(secret);
  }

  // Alternativa ao scan ao vivo: escolhe uma imagem já salva (print de tela,
  // foto do QR impresso) e decodifica com o mesmo motor nativo do
  // mobile_scanner (`analyzeImage`, ML Kit/Vision — não depende da câmera
  // estar aberta). Útil quando o QR está numa outra tela/documento e não dá
  // pra apontar a câmera ao vivo pra ele.
  Future<void> _pickTotpQrImage() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = result?.files.single.path;
    if (path == null || !mounted) return;

    final controller = MobileScannerController();
    BarcodeCapture? capture;
    try {
      capture = await controller.analyzeImage(path);
    } finally {
      await controller.dispose();
    }
    if (!mounted) return;

    final raw = capture?.barcodes.firstOrNull?.rawValue;
    if (raw == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No QR code found in that image')),
      );
      return;
    }

    try {
      final secret = parseTotpSecret(raw);
      _totpSecretCtrl.text = secret;
      _onTotpChanged(secret);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('QR found but not a valid 2FA secret: $e')),
      );
    }
  }

  Future<void> _save() async {
    final isCredential = _type == EntryType.credential;

    String? totpSecret;
    if (isCredential && _totpSecretCtrl.text.trim().isNotEmpty) {
      try {
        totpSecret = parseTotpSecret(_totpSecretCtrl.text);
      } catch (e) {
        setState(() => _totpError = '$e');
        return;
      }
    }

    setState(() { _saving = true; _error = null; });
    try {
      final groups = _dataGroups;
      VaultEntry saved;
      if (_isEditing) {
        saved = await _repository.updateEntry(widget.entry!.copyWith(
          site: isCredential ? _siteCtrl.text.trim() : '',
          url: isCredential ? _urlCtrl.text.trim() : '',
          username: isCredential ? _usernameCtrl.text.trim() : '',
          password: isCredential ? _passwordCtrl.text.trim() : '',
          notes: _notesCtrl.text.trim(),
          profiles: _selectedProfiles.toList(),
          totpSecret: totpSecret,
          passkey: isCredential ? _passkey : null,
          type: _type,
          document: groups.document,
          address: groups.address,
          creditCard: groups.creditCard,
        ));
      } else {
        saved = await _repository.addEntry(
          site: isCredential ? _siteCtrl.text.trim() : '',
          url: isCredential ? _urlCtrl.text.trim() : '',
          username: isCredential ? _usernameCtrl.text.trim() : '',
          password: isCredential ? _passwordCtrl.text.trim() : '',
          notes: _notesCtrl.text.trim(),
          profiles: _selectedProfiles.toList(),
          totpSecret: totpSecret,
          passkey: isCredential ? _passkey : null,
          type: _type,
          document: groups.document,
          address: groups.address,
          creditCard: groups.creditCard,
        );
      }
      // Fase 15.7: o conteúdo do documento só é gravado no cache local
      // cifrado depois que a entrada existe de verdade com um id — o pin
      // de verdade no IPFS acontece no próximo publish
      // (VaultPublishService), não aqui.
      if (_type == EntryType.document && _docFileData != null) {
        await _repository.writeDocumentBlob(saved.id, base64Decode(_docFileData!));
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = '$e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit entry' : 'New entry')),
      body: _loadingProfiles
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 8,
                    children: [
                      (EntryType.credential, '🔑 Password'),
                      (EntryType.document, '📄 Document'),
                      (EntryType.address, '🏠 Address'),
                      (EntryType.creditCard, '💳 Card'),
                    ].map((e) {
                      final (type, label) = e;
                      return ChoiceChip(
                        label: Text(label),
                        selected: _type == type,
                        onSelected: (_) => setState(() => _type = type),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  if (_type == EntryType.credential) ...[
                    TextField(
                      controller: _siteCtrl,
                      decoration: const InputDecoration(labelText: 'Site *', hintText: 'ex: github.com'),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _urlCtrl,
                      decoration: const InputDecoration(labelText: 'URL', hintText: 'https://...'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _usernameCtrl,
                      decoration: const InputDecoration(labelText: 'Username *'),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _passwordCtrl,
                            obscureText: !_showPassword,
                            decoration: InputDecoration(
                              labelText: 'Password *',
                              suffixIcon: IconButton(
                                icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                                onPressed: () => setState(() => _showPassword = !_showPassword),
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.casino_outlined),
                          tooltip: 'Generate password',
                          onPressed: _openPasswordGenerator,
                        ),
                      ],
                    ),
                    _buildStrengthMeter(),
                    const SizedBox(height: 12),
                  ],
                  if (_type == EntryType.document) ...[
                    TextField(
                      controller: _docNameCtrl,
                      decoration: const InputDecoration(labelText: 'Name *', hintText: 'ex: ID card, Passport, Contract'),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _pickDocument,
                      icon: const Icon(Icons.attach_file),
                      label: Text(_docFileName == null ? 'Choose file' : 'Change file'),
                    ),
                    if (_docFileName != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        '$_docFileName · ${_formatBytes(_docFileSizeBytes ?? 0)} · $_docMimeType',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                    ],
                    if (_docError != null) ...[
                      const SizedBox(height: 8),
                      Text(_docError!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
                    ],
                    const SizedBox(height: 12),
                  ],
                  if (_type == EntryType.address) ...[
                    TextField(
                      controller: _addrLabelCtrl,
                      decoration: const InputDecoration(labelText: 'Label *', hintText: 'ex: Home, Work, Delivery'),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _addrFullNameCtrl,
                      decoration: const InputDecoration(labelText: 'Full name *'),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _addrStreetCtrl,
                      decoration: const InputDecoration(labelText: 'Street *'),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _addrNumberCtrl,
                      decoration: const InputDecoration(labelText: 'Number *'),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _addrComplementCtrl,
                      decoration: const InputDecoration(labelText: 'Complement'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _addrNeighborhoodCtrl,
                      decoration: const InputDecoration(labelText: 'Neighborhood *'),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _addrCityCtrl,
                      decoration: const InputDecoration(labelText: 'City *'),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _addrStateCtrl,
                      decoration: const InputDecoration(labelText: 'State *'),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _addrZipCodeCtrl,
                      decoration: const InputDecoration(labelText: 'ZIP code *'),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _addrCountryCtrl,
                      decoration: const InputDecoration(labelText: 'Country *'),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _addrPhoneCtrl,
                      decoration: const InputDecoration(labelText: 'Phone'),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_type == EntryType.creditCard) ...[
                    TextField(
                      controller: _cardLabelCtrl,
                      decoration: const InputDecoration(labelText: 'Label *', hintText: 'ex: Nubank, Itaú Platinum'),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _cardHolderNameCtrl,
                      decoration: const InputDecoration(labelText: 'Card holder *'),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _cardNumberCtrl,
                      decoration: const InputDecoration(labelText: 'Card number *'),
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<CardNetwork>(
                      initialValue: _cardNetwork,
                      decoration: const InputDecoration(labelText: 'Network *'),
                      items: CardNetwork.values
                          .map((n) => DropdownMenuItem(value: n, child: Text(n.name)))
                          .toList(),
                      onChanged: (v) => setState(() => _cardNetwork = v ?? _cardNetwork),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _cardExpiryMonthCtrl,
                            decoration: const InputDecoration(labelText: 'Exp. month *', hintText: 'MM'),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _cardExpiryYearCtrl,
                            decoration: const InputDecoration(labelText: 'Exp. year *', hintText: 'YYYY'),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _cardCvvCtrl,
                      decoration: const InputDecoration(labelText: 'CVV *'),
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _cardBankCtrl,
                      decoration: const InputDecoration(labelText: 'Bank'),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: _notesCtrl,
                    decoration: const InputDecoration(labelText: 'Notes'),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  if (_type == EntryType.credential) ...[
                    TextField(
                      controller: _totpSecretCtrl,
                      decoration: InputDecoration(
                        labelText: '2FA secret (optional)',
                        hintText: 'base32 secret or otpauth://... URI',
                        errorText: _totpError,
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.qr_code_scanner),
                              tooltip: 'Scan QR code',
                              onPressed: _scanTotpQr,
                            ),
                            IconButton(
                              icon: const Icon(Icons.photo_library_outlined),
                              tooltip: 'Upload QR from photo',
                              onPressed: _pickTotpQrImage,
                            ),
                          ],
                        ),
                      ),
                      onChanged: _onTotpChanged,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('Passkey: ', style: TextStyle(fontWeight: FontWeight.bold)),
                        if (_passkey != null)
                          Expanded(
                            child: Text(_passkey!.rpId,
                                style: const TextStyle(color: AppColors.textMuted),
                                overflow: TextOverflow.ellipsis),
                          ),
                        TextButton(
                          onPressed: _generatePasskey,
                          child: Text(_passkey == null ? 'Gerar passkey' : 'Recriar'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  const Text('Profiles', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (_profileOptions.isEmpty)
                    const Text(
                      'No profiles created yet — create one from the Desktop app.',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      children: _profileOptions.map((p) {
                        final selected = _selectedProfiles.contains(p);
                        return FilterChip(
                          label: Text(p),
                          selected: selected,
                          onSelected: (v) => setState(
                              () => v ? _selectedProfiles.add(p) : _selectedProfiles.remove(p)),
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 24),
                  if (_error != null) ...[
                    Text(_error!, style: const TextStyle(color: AppColors.danger)),
                    const SizedBox(height: 12),
                  ],
                  ElevatedButton(
                    onPressed: (_saving ||
                            !_canSaveForm ||
                            (_type == EntryType.credential && _totpError != null))
                        ? null
                        : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: AppColors.background,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.background))
                        : const Text('Save'),
                  ),
                ],
              ),
            ),
    );
  }
}
