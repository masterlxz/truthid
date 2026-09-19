import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:web3dart/crypto.dart' show keccak256, bytesToHex;

import 'arweave_wallet_service.dart';
import 'backup_cipher_service.dart';
import 'ipfs_gateway_client.dart';
import 'vault_cipher_service.dart';

// ---------------------------------------------------------------------------
// Modelo de entrada do vault
// ---------------------------------------------------------------------------

class _Unset {
  const _Unset();
}

const _unset = _Unset();

/// Credencial WebAuthn (passkey) da entrada, se o usuário gerou uma. A chave
/// privada nunca deve ser incluída no payload enviado à extensão — usar
/// [VaultEntry.toJsonForExtension].
class Passkey {
  final String rpId;
  final String credentialIdB64;
  final String userHandleB64;
  final String privateKeyHex;
  final int signCount;
  final DateTime createdAt;

  const Passkey({
    required this.rpId,
    required this.credentialIdB64,
    required this.userHandleB64,
    required this.privateKeyHex,
    required this.signCount,
    required this.createdAt,
  });

  factory Passkey.fromJson(Map<String, dynamic> json) => Passkey(
        rpId: json['rp_id'] as String,
        credentialIdB64: json['credential_id_b64'] as String,
        userHandleB64: json['user_handle_b64'] as String,
        privateKeyHex: json['private_key_hex'] as String,
        signCount: json['sign_count'] as int,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (json['created_at'] as int) * 1000,
          isUtc: true,
        ),
      );

  Map<String, dynamic> toJson() => {
        'rp_id': rpId,
        'credential_id_b64': credentialIdB64,
        'user_handle_b64': userHandleB64,
        'private_key_hex': privateKeyHex,
        'sign_count': signCount,
        'created_at': createdAt.millisecondsSinceEpoch ~/ 1000,
      };
}

/// Fase 15 — discriminante de tipo da entrada. Ausente no JSON (blob antigo,
/// pré-Fase 15) == [EntryType.credential], o único tipo que existia antes.
enum EntryType {
  credential,
  document,
  address,
  creditCard;

  static EntryType fromJson(String? value) => switch (value) {
        'document' => EntryType.document,
        'address' => EntryType.address,
        'creditCard' => EntryType.creditCard,
        _ => EntryType.credential,
      };

  String toJson() => switch (this) {
        EntryType.credential => 'credential',
        EntryType.document => 'document',
        EntryType.address => 'address',
        EntryType.creditCard => 'creditCard',
      };
}

enum CardNetwork {
  visa,
  mastercard,
  amex,
  elo,
  hipercard,
  other;

  static CardNetwork fromJson(String? value) => switch (value) {
        'visa' => CardNetwork.visa,
        'mastercard' => CardNetwork.mastercard,
        'amex' => CardNetwork.amex,
        'elo' => CardNetwork.elo,
        'hipercard' => CardNetwork.hipercard,
        _ => CardNetwork.other,
      };

  String toJson() => name;
}

class DocumentData {
  final String name;
  final String fileName;
  final int fileSizeBytes;
  final String mimeType;
  /// CID do blob cifrado do documento no IPFS (Fase 15.7) — null até o
  /// próximo publish pinar o conteúdo (ver [VaultPublishService]).
  final String? cid;
  /// keccak256 (hex, prefixo "0x") do blob cifrado do documento — mesmo
  /// padrão de verificação que o vault principal já usa antes de decifrar
  /// um blob baixado do IPFS ([VaultSyncService.sync]). Também usado
  /// localmente pra decidir se o documento mudou desde o último pin.
  final String? contentHash;
  /// Campo legado (pré-Fase 15.7) — conteúdo em base64 embutido direto no
  /// JSON da entrada. Inflava o sync de TODO o vault por causa de qualquer
  /// documento grande, mesmo pra edições não relacionadas (ver
  /// project/PHASE.md, 15.7). Privado ao arquivo: só existe pra
  /// [VaultRepository._migrateLegacyDocuments] mover o conteúdo pro cache
  /// local; nunca incluído em [toJson] — não faz parte do modelo daqui pra
  /// frente (o conteúdo agora vive cifrado à parte, ver
  /// [VaultRepository.readDocumentBlob]).
  final String? _legacyFileData;

  const DocumentData({
    required this.name,
    required this.fileName,
    required this.fileSizeBytes,
    required this.mimeType,
    this.cid,
    this.contentHash,
    this._legacyFileData,
  });

  factory DocumentData.fromJson(Map<String, dynamic> json) => DocumentData(
        name: json['name'] as String,
        fileName: json['file_name'] as String,
        fileSizeBytes: json['file_size_bytes'] as int,
        mimeType: json['mime_type'] as String,
        cid: json['cid'] as String?,
        contentHash: json['content_hash'] as String?,
        legacyFileData: json['file_data'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'file_name': fileName,
        'file_size_bytes': fileSizeBytes,
        'mime_type': mimeType,
        'cid': cid,
        'content_hash': contentHash,
      };
}

class AddressData {
  final String label;
  final String fullName;
  final String street;
  final String number;
  final String? complement;
  final String neighborhood;
  final String city;
  final String state;
  final String zipCode;
  final String country;
  final String? phone;

  const AddressData({
    required this.label,
    required this.fullName,
    required this.street,
    required this.number,
    this.complement,
    required this.neighborhood,
    required this.city,
    required this.state,
    required this.zipCode,
    required this.country,
    this.phone,
  });

  factory AddressData.fromJson(Map<String, dynamic> json) => AddressData(
        label: json['label'] as String,
        fullName: json['full_name'] as String,
        street: json['street'] as String,
        number: json['number'] as String,
        complement: json['complement'] as String?,
        neighborhood: json['neighborhood'] as String,
        city: json['city'] as String,
        state: json['state'] as String,
        zipCode: json['zip_code'] as String,
        country: json['country'] as String,
        phone: json['phone'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'label': label,
        'full_name': fullName,
        'street': street,
        'number': number,
        'complement': complement,
        'neighborhood': neighborhood,
        'city': city,
        'state': state,
        'zip_code': zipCode,
        'country': country,
        'phone': phone,
      };
}

class CreditCardData {
  final String label;
  final String cardHolderName;
  /// Cifrado individualmente (Fase 15.8) na representação em disco/export
  /// (`VaultRepository._save`/`exportBackup`) — em memória, sempre em claro
  /// (pós `_load()`), igual ao resto do app já espera.
  final String cardNumber;
  final String expiryMonth;
  final String expiryYear;
  /// Idem `cardNumber`.
  final String cvv;
  final String? bank;
  final CardNetwork cardNetwork;

  const CreditCardData({
    required this.label,
    required this.cardHolderName,
    required this.cardNumber,
    required this.expiryMonth,
    required this.expiryYear,
    required this.cvv,
    this.bank,
    required this.cardNetwork,
  });

  factory CreditCardData.fromJson(Map<String, dynamic> json) => CreditCardData(
        label: json['label'] as String,
        cardHolderName: json['card_holder_name'] as String,
        cardNumber: json['card_number'] as String,
        expiryMonth: json['expiry_month'] as String,
        expiryYear: json['expiry_year'] as String,
        cvv: json['cvv'] as String,
        bank: json['bank'] as String?,
        cardNetwork: CardNetwork.fromJson(json['card_network'] as String?),
      );

  Map<String, dynamic> toJson() => {
        'label': label,
        'card_holder_name': cardHolderName,
        'card_number': cardNumber,
        'expiry_month': expiryMonth,
        'expiry_year': expiryYear,
        'cvv': cvv,
        'bank': bank,
        'card_network': cardNetwork.toJson(),
      };
}

class VaultEntry {
  final String id;
  final String site;
  final String url;
  final String username;
  final String password;
  final String notes;
  /// Lista de grupos a que esta entrada pertence (ex: ["Trabalho", "Casa"]).
  final List<String> profiles;
  /// Segredo TOTP (RFC 6238) em base32, se 2FA estiver configurado. Nunca deve
  /// ser incluído no payload enviado à extensão — usar [toJsonForExtension].
  final String? totpSecret;
  /// Credencial WebAuthn (passkey) da entrada, se o usuário gerou uma.
  /// Incluída no payload enviado à extensão desde a Sessão 132 — usar
  /// [toJsonForExtension] (que continua removendo só o `totpSecret`).
  final Passkey? passkey;
  /// Favorito — sincroniza entre devices como qualquer outro campo do vault
  /// (não é preferência local). Trocado via [VaultRepository.setFavorite],
  /// não via [VaultRepository.updateEntry], pra não renovar `updatedAt` só
  /// por causa do toggle.
  final bool favorite;
  /// Fase 15: tipo da entrada. Só o grupo correspondente
  /// (document/address/creditCard) deve vir preenchido.
  final EntryType type;
  final DocumentData? document;
  final AddressData? address;
  final CreditCardData? creditCard;
  final DateTime createdAt;
  final DateTime updatedAt;

  const VaultEntry({
    required this.id,
    required this.site,
    required this.url,
    required this.username,
    required this.password,
    required this.notes,
    this.profiles = const [],
    this.totpSecret,
    this.passkey,
    this.favorite = false,
    this.type = EntryType.credential,
    this.document,
    this.address,
    this.creditCard,
    required this.createdAt,
    required this.updatedAt,
  });

  factory VaultEntry.fromJson(Map<String, dynamic> json) {
    // Migração: formato antigo tinha "profile" (string); novo tem "profiles" (lista).
    List<String> profiles;
    if (json['profiles'] != null) {
      profiles = List<String>.from(json['profiles'] as List);
    } else {
      final old = json['profile'] as String? ?? '';
      profiles = old.isNotEmpty ? [old] : [];
    }
    return VaultEntry(
      id: json['id'] as String,
      site: json['site'] as String,
      url: json['url'] as String,
      username: json['username'] as String,
      password: json['password'] as String,
      notes: json['notes'] as String,
      profiles: profiles,
      totpSecret: json['totp_secret'] as String?,
      passkey: json['passkey'] != null
          ? Passkey.fromJson(json['passkey'] as Map<String, dynamic>)
          : null,
      favorite: json['favorite'] as bool? ?? false,
      type: EntryType.fromJson(json['type'] as String?),
      document: json['document'] != null
          ? DocumentData.fromJson(json['document'] as Map<String, dynamic>)
          : null,
      address: json['address'] != null
          ? AddressData.fromJson(json['address'] as Map<String, dynamic>)
          : null,
      creditCard: json['credit_card'] != null
          ? CreditCardData.fromJson(json['credit_card'] as Map<String, dynamic>)
          : null,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (json['created_at'] as int) * 1000,
        isUtc: true,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (json['updated_at'] as int) * 1000,
        isUtc: true,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'site': site,
        'url': url,
        'username': username,
        'password': password,
        'notes': notes,
        'profiles': profiles,
        'totp_secret': totpSecret,
        'passkey': passkey?.toJson(),
        'favorite': favorite,
        'type': type.toJson(),
        'document': document?.toJson(),
        'address': address?.toJson(),
        'credit_card': creditCard?.toJson(),
        'created_at': createdAt.millisecondsSinceEpoch ~/ 1000,
        'updated_at': updatedAt.millisecondsSinceEpoch ~/ 1000,
      };

  /// Igual a [toJson], mas sem `totp_secret`/`document`/`address`/
  /// `credit_card` — usar sempre que a entrada for sair pro canal da
  /// extensão de navegador (LAN/dead-drop em vault_session_screen.dart).
  /// 2FA continua isolado no Device por design (fatores separados);
  /// `passkey` já é enviado desde a Sessão 132 — a extensão precisa da
  /// chave privada pra assinar `navigator.credentials.get` em sites reais
  /// (ver `extension/src/webauthn.ts`). Achado da 15.8: esse canal só
  /// consome username/password/passkey (o tipo `VaultEntry` da própria
  /// extensão nem tem campos pros outros 3 grupos) — document/address/
  /// credit_card nunca deveriam ter chegado lá; sem essa remoção, uma
  /// entrada tipo cartão num perfil sincronizado por esse canal deixava
  /// `card_number`/`cvv` em texto pleno no `chrome.storage.session` da
  /// extensão pelo tempo de vida da sessão.
  Map<String, dynamic> toJsonForExtension() {
    final json = toJson();
    json.remove('totp_secret');
    json.remove('document');
    json.remove('address');
    json.remove('credit_card');
    return json;
  }

  // `totpSecret`/`passkey`/`document`/`address`/`creditCard` usam um sentinel
  // em vez de tipo anulável puro: precisa distinguir "não passei esse
  // argumento" (mantém o valor atual) de "passei null de propósito" (apaga o
  // campo da entrada) — um `?? this.x` comum não permite nunca limpar o campo
  // de volta pra null.
  VaultEntry copyWith({
    String? site,
    String? url,
    String? username,
    String? password,
    String? notes,
    List<String>? profiles,
    Object? totpSecret = _unset,
    Object? passkey = _unset,
    bool? favorite,
    EntryType? type,
    Object? document = _unset,
    Object? address = _unset,
    Object? creditCard = _unset,
  }) =>
      VaultEntry(
        id: id,
        site: site ?? this.site,
        url: url ?? this.url,
        username: username ?? this.username,
        password: password ?? this.password,
        notes: notes ?? this.notes,
        profiles: profiles ?? this.profiles,
        totpSecret:
            identical(totpSecret, _unset) ? this.totpSecret : totpSecret as String?,
        passkey: identical(passkey, _unset) ? this.passkey : passkey as Passkey?,
        favorite: favorite ?? this.favorite,
        type: type ?? this.type,
        document: identical(document, _unset)
            ? this.document
            : document as DocumentData?,
        address:
            identical(address, _unset) ? this.address : address as AddressData?,
        creditCard: identical(creditCard, _unset)
            ? this.creditCard
            : creditCard as CreditCardData?,
        createdAt: createdAt,
        updatedAt: DateTime.now().toUtc(),
      );

  /// Mirror de `VaultEntry::validate` (desktop/src-tauri/src/vault.rs) — o
  /// Mobile não tem nenhuma outra camada de validação desse invariante
  /// (VaultRepository lê/escreve o arquivo cifrado local direto, sem chamada
  /// Rust nesse caminho), então este é o único ponto que impede uma entrada
  /// com `type` e grupo de dados inconsistentes de ser persistida.
  void validate() {
    final hasDocument = document != null;
    final hasAddress = address != null;
    final hasCreditCard = creditCard != null;
    final ok = switch (type) {
      EntryType.credential => !hasDocument && !hasAddress && !hasCreditCard,
      EntryType.document => hasDocument && !hasAddress && !hasCreditCard,
      EntryType.address => !hasDocument && hasAddress && !hasCreditCard,
      EntryType.creditCard => !hasDocument && !hasAddress && hasCreditCard,
    };
    if (!ok) {
      throw Exception(
        "vault entry type ${type.toJson()} doesn't match its data groups "
        '(document=$hasDocument, address=$hasAddress, creditCard=$hasCreditCard)',
      );
    }
  }
}

/// Permissão de escrita de um device no vault (`pubKey` = endereço do device).
/// Normalmente concedida pelo Desktop/controller, mas o Mobile também pode
/// gerenciar (ver `VaultRepository.setDevicePermission`) — trava de UX
/// (mesma que já protege as outras telas de escrita do Vault, `canWrite`),
/// não é imposta pelo contrato (ver project/INDEX.md, Sessão 97).
class VaultDevicePermission {
  final String pubKey;
  final bool canWrite;

  const VaultDevicePermission({required this.pubKey, required this.canWrite});

  factory VaultDevicePermission.fromJson(Map<String, dynamic> json) =>
      VaultDevicePermission(
        pubKey: json['pub_key'] as String,
        canWrite: json['can_write'] as bool,
      );

  Map<String, dynamic> toJson() => {'pub_key': pubKey, 'can_write': canWrite};
}

// ---------------------------------------------------------------------------
// Manifesto remoto (Arweave) — Vault por-entrada
// ---------------------------------------------------------------------------
//
// O CID publicado on-chain (`VaultRegistry`) passa a apontar pra este
// manifesto pequeno em vez do vault inteiro — cada entrada vira um blob
// cifrado próprio, só republicado quando ela muda de verdade (generaliza o
// padrão que os documentos anexados já usam desde a Fase 15.7,
// `DocumentData.cid`/`contentHash`). Mirror de `VaultManifest`
// (desktop/src-tauri/src/vault.rs). Formato local em disco (`vault.enc`)
// não muda — só a camada de publicação/sync remota.

class ManifestEntryRef {
  final String cid;
  final String contentHash;
  final int updatedAt;

  const ManifestEntryRef({
    required this.cid,
    required this.contentHash,
    required this.updatedAt,
  });

  factory ManifestEntryRef.fromJson(Map<String, dynamic> json) =>
      ManifestEntryRef(
        cid: json['cid'] as String,
        contentHash: json['contentHash'] as String,
        updatedAt: json['updatedAt'] as int,
      );

  Map<String, dynamic> toJson() => {
        'cid': cid,
        'contentHash': contentHash,
        'updatedAt': updatedAt,
      };
}

class VaultManifest {
  /// Versão do esquema do manifesto em si (sempre 1 por enquanto) —
  /// independente de [vaultVersion].
  final int version;
  /// Espelha `_VaultData.version` no momento da publicação, pra um leitor
  /// reconstruir o vault local com a versão certa sem precisar adivinhar.
  final int vaultVersion;
  final Map<String, ManifestEntryRef> entries;
  final List<String> profileNames;
  final List<VaultDevicePermission> devicePermissions;

  const VaultManifest({
    required this.version,
    required this.vaultVersion,
    required this.entries,
    this.profileNames = const [],
    this.devicePermissions = const [],
  });

  factory VaultManifest.fromJson(Map<String, dynamic> json) => VaultManifest(
        version: json['version'] as int,
        vaultVersion: json['vaultVersion'] as int,
        entries: (json['entries'] as Map<String, dynamic>).map(
          (key, value) => MapEntry(
            key,
            ManifestEntryRef.fromJson(value as Map<String, dynamic>),
          ),
        ),
        profileNames: json['profileNames'] != null
            ? List<String>.from(json['profileNames'] as List)
            : const <String>[],
        devicePermissions: json['devicePermissions'] != null
            ? (json['devicePermissions'] as List)
                .map((p) =>
                    VaultDevicePermission.fromJson(p as Map<String, dynamic>))
                .toList()
            : const <VaultDevicePermission>[],
      );

  Map<String, dynamic> toJson() => {
        'version': version,
        'vaultVersion': vaultVersion,
        'entries': entries.map((key, value) => MapEntry(key, value.toJson())),
        'profileNames': profileNames,
        'devicePermissions': devicePermissions.map((p) => p.toJson()).toList(),
      };
}

/// Tipo de mudança de uma entrada desde o último baseline (publicado ou
/// conhecido do manifesto remoto) — mirror de `EntryDiffKind`
/// (desktop/src-tauri/src/vault.rs).
enum EntryDiffKind { added, modified, removed }

// ---------------------------------------------------------------------------
// Container interno (não exposto fora do arquivo)
// ---------------------------------------------------------------------------

class _VaultData {
  final int version;
  final List<VaultEntry> entries;
  /// Nomes de perfis criados pelo usuário (ex: ["Trabalho", "Banco"]) — geridos
  /// só pelo Desktop (Mobile é somente-leitura pro Vault), ver project/INDEX.md
  /// Sessão 97.
  final List<String> profileNames;
  /// Permissões de escrita por device (ver VaultDevicePermission).
  final List<VaultDevicePermission> devicePermissions;
  const _VaultData({
    required this.version,
    required this.entries,
    this.profileNames = const [],
    this.devicePermissions = const [],
  });
}

// ---------------------------------------------------------------------------
// Repositório
// ---------------------------------------------------------------------------

class VaultRepository {
  final VaultCipherService _cipherService;
  final BackupCipherService _backupCipherService;
  final ArweaveWalletService _arweaveWalletService;
  // Caminho injetado nos testes; null = usa path_provider em produção.
  final String? _testPath;

  VaultRepository({
    VaultCipherService? cipherService,
    BackupCipherService? backupCipherService,
    ArweaveWalletService? arweaveWalletService,
    this._testPath,
  })  : _cipherService = cipherService ?? VaultCipherService(),
        _backupCipherService = backupCipherService ?? BackupCipherService(),
        _arweaveWalletService = arweaveWalletService ?? ArweaveWalletService();

  Future<List<VaultEntry>> listEntries() async {
    final data = await _load();
    return data.entries;
  }

  Future<List<String>> listProfileNames() async {
    final data = await _load();
    return data.profileNames;
  }

  Future<int> currentVersion() async {
    final data = await _load();
    return data.version;
  }

  // Cria um novo perfil (nome livre, sem duplicatas). No-op se já existir.
  // Mirror de Vault::add_profile (desktop/src-tauri/src/vault.rs).
  Future<void> addProfile(String name) async {
    final data = await _load();
    if (data.profileNames.contains(name)) return;
    await _save(_VaultData(
      version: data.version + 1,
      entries: data.entries,
      profileNames: [...data.profileNames, name],
      devicePermissions: data.devicePermissions,
    ));
  }

  // Renomeia um perfil na lista e em cascata em todas as entradas que o usam.
  // Mirror de Vault::rename_profile.
  Future<void> renameProfile(String oldName, String newName) async {
    final data = await _load();
    if (!data.profileNames.contains(oldName)) return;
    final profileNames =
        data.profileNames.map((p) => p == oldName ? newName : p).toList();
    final entries = data.entries
        .map((e) => e.profiles.contains(oldName)
            ? e.copyWith(profiles: e.profiles.map((p) => p == oldName ? newName : p).toList())
            : e)
        .toList();
    await _save(_VaultData(
      version: data.version + 1,
      entries: entries,
      profileNames: profileNames,
      devicePermissions: data.devicePermissions,
    ));
  }

  // Remove um perfil da lista e limpa essa tag de todas as entradas que a
  // usam. Mirror de Vault::delete_profile.
  Future<void> deleteProfile(String name) async {
    final data = await _load();
    if (!data.profileNames.contains(name)) return;
    final profileNames = data.profileNames.where((p) => p != name).toList();
    final entries = data.entries
        .map((e) => e.profiles.contains(name)
            ? e.copyWith(profiles: e.profiles.where((p) => p != name).toList())
            : e)
        .toList();
    await _save(_VaultData(
      version: data.version + 1,
      entries: entries,
      profileNames: profileNames,
      devicePermissions: data.devicePermissions,
    ));
  }

  // Permissão de escrita do device `myPubKey`. `false` por padrão — um
  // device precisa ter sido explicitamente autorizado pelo Desktop.
  Future<bool> canWriteVault(String myPubKey) async {
    final data = await _load();
    for (final p in data.devicePermissions) {
      if (p.pubKey.toLowerCase() == myPubKey.toLowerCase()) return p.canWrite;
    }
    return false;
  }

  // Todas as permissões de device conhecidas — usado pela tela de
  // "Device permissions" pra cruzar com a lista de devices vinda on-chain.
  Future<List<VaultDevicePermission>> listDevicePermissions() async {
    final data = await _load();
    return data.devicePermissions;
  }

  // Marca/desmarca uma entrada como favorita. Mirror de Vault::set_favorite
  // (desktop/src-tauri/src/vault.rs) — não usa copyWith de propósito
  // (copyWith sempre renova updatedAt); reconstrução direta preserva o
  // updatedAt original, mesmo motivo do lado Rust. Lança se o id não existir.
  Future<void> setFavorite(String id, bool favorite) async {
    final data = await _load();
    final index = data.entries.indexWhere((e) => e.id == id);
    if (index < 0) {
      throw Exception('Vault entry not found: $id');
    }
    final target = data.entries[index];
    final updatedEntry = VaultEntry(
      id: target.id,
      site: target.site,
      url: target.url,
      username: target.username,
      password: target.password,
      notes: target.notes,
      profiles: target.profiles,
      totpSecret: target.totpSecret,
      passkey: target.passkey,
      favorite: favorite,
      createdAt: target.createdAt,
      updatedAt: target.updatedAt,
    );
    final entries = [...data.entries];
    entries[index] = updatedEntry;
    await _save(_VaultData(
      version: data.version + 1,
      entries: entries,
      profileNames: data.profileNames,
      devicePermissions: data.devicePermissions,
    ));
  }

  // Fase 15.7 — grava o cid/contentHash do blob separado de um documento
  // depois de pinado, chamado só por VaultPublishService antes de publicar o
  // blob principal (mesmo espírito de setFavorite: entra pelo find-by-id,
  // não por updateEntry, porque não é uma edição de usuário).
  Future<void> setDocumentPinInfo(
    String entryId, {
    required String cid,
    required String contentHash,
  }) async {
    final data = await _load();
    final index = data.entries.indexWhere((e) => e.id == entryId);
    if (index < 0 || data.entries[index].document == null) return;
    final target = data.entries[index];
    final doc = target.document!;
    final updatedEntry = VaultEntry(
      id: target.id,
      site: target.site,
      url: target.url,
      username: target.username,
      password: target.password,
      notes: target.notes,
      profiles: target.profiles,
      totpSecret: target.totpSecret,
      passkey: target.passkey,
      favorite: target.favorite,
      type: target.type,
      document: DocumentData(
        name: doc.name,
        fileName: doc.fileName,
        fileSizeBytes: doc.fileSizeBytes,
        mimeType: doc.mimeType,
        cid: cid,
        contentHash: contentHash,
      ),
      address: target.address,
      creditCard: target.creditCard,
      createdAt: target.createdAt,
      updatedAt: target.updatedAt,
    );
    final entries = [...data.entries];
    entries[index] = updatedEntry;
    await _save(_VaultData(
      version: data.version + 1,
      entries: entries,
      profileNames: data.profileNames,
      devicePermissions: data.devicePermissions,
    ));
  }

  // Concede/revoga a permissão de escrita de um device. Mirror de
  // Vault::set_device_permission (desktop/src-tauri/src/vault.rs) —
  // find-or-insert por pubKey (case-insensitive, mesma comparação de
  // canWriteVault), bump de versão.
  Future<void> setDevicePermission(String pubKey, bool canWrite) async {
    final data = await _load();
    final updated = [...data.devicePermissions];
    final index = updated
        .indexWhere((p) => p.pubKey.toLowerCase() == pubKey.toLowerCase());
    final entry = VaultDevicePermission(pubKey: pubKey, canWrite: canWrite);
    if (index >= 0) {
      updated[index] = entry;
    } else {
      updated.add(entry);
    }
    await _save(_VaultData(
      version: data.version + 1,
      entries: data.entries,
      profileNames: data.profileNames,
      devicePermissions: updated,
    ));
  }

  Future<VaultEntry> addEntry({
    required String site,
    String url = '',
    required String username,
    required String password,
    String notes = '',
    List<String> profiles = const [],
    String? totpSecret,
    Passkey? passkey,
    EntryType type = EntryType.credential,
    DocumentData? document,
    AddressData? address,
    CreditCardData? creditCard,
  }) async {
    final data = await _load();
    final now = DateTime.now().toUtc();
    final entry = VaultEntry(
      id: _generateId(),
      site: site,
      url: url,
      username: username,
      password: password,
      notes: notes,
      profiles: profiles,
      totpSecret: totpSecret,
      passkey: passkey,
      type: type,
      document: document,
      address: address,
      creditCard: creditCard,
      createdAt: now,
      updatedAt: now,
    );
    entry.validate();
    await _save(_VaultData(
      version: data.version + 1,
      entries: [...data.entries, entry],
      profileNames: data.profileNames,
      devicePermissions: data.devicePermissions,
    ));
    return entry;
  }

  Future<VaultEntry> updateEntry(VaultEntry entry) async {
    entry.validate();
    final data = await _load();
    if (!data.entries.any((e) => e.id == entry.id)) {
      throw Exception('Vault entry not found: ${entry.id}');
    }
    final updated = entry.copyWith(); // renova updatedAt via copyWith
    final entries = data.entries
        .map((e) => e.id == entry.id ? updated : e)
        .toList();
    await _save(_VaultData(
      version: data.version + 1,
      entries: entries,
      profileNames: data.profileNames,
      devicePermissions: data.devicePermissions,
    ));
    return updated;
  }

  Future<void> deleteEntry(String id) async {
    final data = await _load();
    final entries = data.entries.where((e) => e.id != id).toList();
    // Incrementa version só se algo foi removido
    final newVersion = entries.length < data.entries.length
        ? data.version + 1
        : data.version;
    await _save(_VaultData(
      version: newVersion,
      entries: entries,
      profileNames: data.profileNames,
      devicePermissions: data.devicePermissions,
    ));
  }

  // Sobrescreve o cache local com um blob já cifrado vindo de fora (ex: o
  // vault baixado do IPFS pelo VaultSyncService, já verificado por hash).
  // Não recifra nada — o blob já está no formato correto (mesma chave), só
  // grava. Uma chamada subsequente a listEntries()/_load() decifra e faz
  // parse normalmente, sem duplicar essa lógica aqui.
  Future<void> overwriteCache(Uint8List encryptedBlob) async {
    final path = await _vaultPath();
    await File(path).writeAsBytes(encryptedBlob);
  }

  // Lê o vault.enc cru (ainda cifrado) — é isso que se pina no IPFS e se
  // hasheia pro VaultRegistry, mesmo formato que o Desktop publica
  // (nunca decifra pra publicar, só pra exibir localmente).
  Future<Uint8List> readRawBlob() async {
    final path = await _vaultPath();
    return File(path).readAsBytes();
  }

  // Mirror do guard já existente no Desktop (vault_publish, lib.rs: `if
  // !path.exists() { return Err(...) }`) — sem isso, um device sem cache
  // local (ex: um pareamento novo que falhou ao sincronizar, ver
  // VaultSyncStatus.syncFailedNoCache) que tentasse publicar sobrescreveria
  // o vault on-chain com um blob vazio, apagando o vault de verdade doutro
  // device pra sempre.
  Future<bool> hasLocalVault() async {
    final path = await _vaultPath();
    return File(path).exists();
  }

  // Rastreio de publicação — mirror de mark_published/pending_changes do
  // Desktop (desktop/src-tauri/src/vault.rs), guardado localmente via
  // flutter_secure_storage em vez de um arquivo separado.
  static const _publishedVersionKey = 'vault_last_published_version';
  static const _publishedContentHashKey = 'vault_last_published_content_hash';
  static const _storage = FlutterSecureStorage();

  // Assinatura do conteúdo do vault (tudo, exceto `version`) — usada só como
  // fallback em pendingChanges() pra vaults publicados antes da Sessão 139
  // (sem snapshot local ainda, ver _loadPublishedSnapshot).
  String _contentSignature(_VaultData data) {
    final map = {
      'entries': data.entries.map((e) => e.toJson()).toList(),
      'profile_names': data.profileNames,
      'device_permissions': data.devicePermissions.map((p) => p.toJson()).toList(),
    };
    return sha256.convert(utf8.encode(jsonEncode(map))).toString();
  }

  Future<String> _publishedSnapshotPath() async {
    if (_testPath != null) return '$_testPath.published';
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/vault.published.enc';
  }

  // Cópia cifrada (mesma chave do vault.enc) do conteúdo publicado pela
  // última vez — usada por pendingChanges() pra diffar entrada por entrada,
  // em vez de só comparar hash global. Retorna null se ainda não existe
  // (vault nunca publicado desde que este mecanismo foi introduzido).
  Future<_VaultData?> _loadPublishedSnapshot() async {
    final path = await _publishedSnapshotPath();
    final file = File(path);
    if (!await file.exists()) return null;
    final blob = await file.readAsBytes();
    final json = await _cipherService.decrypt(blob);
    return _parseVaultJson(json);
  }

  // Escreve `data` num arquivo temporário no mesmo diretório e troca pro
  // destino com `rename` (atômico no mesmo filesystem) — mirror de
  // `write_file_atomic` (desktop/src-tauri/src/vault.rs). Achado #8 do
  // /code-review (Sessão 140): uma escrita direta interrompida por crash/
  // disco cheio no meio do snapshot deixava `vault.published.enc` truncado/
  // corrompido, o que faz `_loadPublishedSnapshot` lançar na próxima leitura.
  Future<void> _writeFileAtomic(String path, Uint8List data) async {
    final tmpPath = '$path.tmp';
    await File(tmpPath).writeAsBytes(data);
    await File(tmpPath).rename(path);
  }

  Future<void> _savePublishedSnapshot(_VaultData data) async {
    final json = _serializeVaultData(data);
    final blob = await _cipherService.encrypt(json);
    final path = await _publishedSnapshotPath();
    await _writeFileAtomic(path, blob);
  }

  // Conta mudanças reais de conteúdo entre o vault atual e o último snapshot
  // publicado — cada entrada adicionada/removida/modificada conta 1, idem
  // pra permissão de device e nome de perfil. Mirror exato de diff_count
  // (desktop/src-tauri/src/vault.rs). Achado da Sessão 139: o diff por hash
  // global (Sessão 138) só zerava quando o vault voltava 100% idêntico ao
  // publicado — com qualquer outra pendência real no meio (ex: uma entrada
  // nova ainda não publicada), o toggle de favorito voltava a "vazar" porque
  // caía no diff por version, que é monotônica e nunca cancela.
  int _diffCount(_VaultData current, _VaultData published) {
    var count = _diffEntries(current, published).length;

    final publishedPerms = {
      for (final p in published.devicePermissions) p.pubKey.toLowerCase(): p.canWrite,
    };
    final currentPerms = {
      for (final p in current.devicePermissions) p.pubKey.toLowerCase(): p.canWrite,
    };
    for (final entry in currentPerms.entries) {
      final prev = publishedPerms[entry.key];
      if (prev == null || prev != entry.value) count++;
    }
    for (final key in publishedPerms.keys) {
      if (!currentPerms.containsKey(key)) count++;
    }

    final publishedProfiles = published.profileNames.toSet();
    final currentProfiles = current.profileNames.toSet();
    count += currentProfiles.difference(publishedProfiles).length;
    count += publishedProfiles.difference(currentProfiles).length;

    return count;
  }

  // Persiste a versão + assinatura de conteúdo do vault que acabou de ser
  // publicado no IPFS (fallback pra vaults sem snapshot ainda, ver
  // pendingChanges), e um snapshot cifrado do conteúdo pra diff futuro.
  //
  // Recebe o blob que foi de fato publicado (em vez de reler o vault atual
  // do disco) — achado da Sessão 153 (M3, `/code-review high`): o publish
  // real (pin no IPFS + UserOperation on-chain) leva ~60s, e reler do disco
  // depois desse tempo capturava qualquer edição feita nesse meio-tempo como
  // se já tivesse sido publicada, mesmo sem nunca ter ido on-chain.
  Future<void> markPublished(int version, Uint8List publishedBlob) async {
    final json = await _cipherService.decrypt(publishedBlob);
    final parsed = _parseVaultJson(json);
    // Fase 15.8: normaliza card_number/cvv pra texto plano antes de marcar
    // publicado — crítico pra corretude do diff em pendingChanges(), que
    // sempre compara contra _load() (também em claro). Sem isso, o
    // snapshot guardaria os campos cifrados (nonce novo a cada save), e
    // qualquer vault com cartão veria "pendência fantasma" pra sempre.
    final data = _VaultData(
      version: parsed.version,
      entries: await _decryptCardFieldsInEntries(parsed.entries),
      profileNames: parsed.profileNames,
      devicePermissions: parsed.devicePermissions,
    );
    // Achado #8 do /code-review (Sessão 140), mirror do Desktop
    // (vault.rs::mark_published): o snapshot vai primeiro, de propósito.
    // `pendingChanges()` sempre prefere o snapshot quando ele existe (as
    // chaves de storage só são olhadas como fallback pra vaults sem
    // snapshot ainda) — se o app morrer entre as duas escritas, gravar o
    // snapshot primeiro garante que o diff por entrada já reflete a
    // publicação real mesmo com as chaves ainda desatualizadas (que nesse
    // ponto já são irrelevantes, o snapshot ganha). Na ordem antiga
    // (storage primeiro), o mesmo crash deixava pendingChanges() comparando
    // contra um snapshot velho e superestimando o que ainda faltava
    // publicar.
    await _savePublishedSnapshot(data);
    await _storage.write(
      key: _publishedVersionKey,
      value: version.toString(),
    );
    await _storage.write(
      key: _publishedContentHashKey,
      value: _contentSignature(data),
    );
  }

  // Quantas mudanças de conteúdo o vault local tem em relação ao último
  // publicado no IPFS. 0 = nada pendente.
  Future<int> pendingChanges() async {
    final data = await _load();
    final snapshot = await _loadPublishedSnapshot();
    if (snapshot != null) {
      return _diffCount(data, snapshot);
    }
    final lastHash = await _storage.read(key: _publishedContentHashKey);
    if (lastHash == null) {
      // Achado #1 do /code-review (Sessão 140), mirror do Desktop
      // (vault.rs::pending_changes_from): nunca publicado, nem no esquema
      // antigo — não existe baseline nenhum, então `data.version` cru
      // reproduzia o mesmo bug que `_diffCount` (Sessão 139) já tinha
      // corrigido pro caso "já publicado ao menos uma vez": version é
      // monotônica e não cancela um toggle (favoritar+desfavoritar, por
      // exemplo) antes do primeiro publish. O baseline correto pra "nunca
      // publicado" é um vault vazio.
      return _diffCount(data, const _VaultData(version: 0, entries: []));
    }
    if (lastHash == _contentSignature(data)) {
      // Achado #4 do /code-review (Sessão 140), mirror do Desktop: sem
      // isto, este branch podia nunca migrar pro esquema novo até o
      // próximo publish de verdade — toda chamada repetia o mesmo fallback
      // impreciso indefinidamente. O conteúdo atual bate byte a byte com o
      // que foi publicado da última vez, então já sabemos exatamente o que
      // gravar como snapshot — migra na hora. Best-effort: uma falha de
      // escrita aqui não pode quebrar uma leitura que já tem a resposta
      // certa (0).
      try {
        await _savePublishedSnapshot(data);
      } catch (_) {
        // ignora — não impede a leitura, que já tem a resposta certa
      }
      return 0;
    }
    final raw = await _storage.read(key: _publishedVersionKey);
    final last = raw != null ? int.tryParse(raw) ?? 0 : 0;
    final pending = data.version - last;
    return pending > 0 ? pending : 0;
  }

  // ---------------------------------------------------------------------------
  // Manifesto remoto — publicação/sync por entrada
  // ---------------------------------------------------------------------------
  //
  // Mesmo espírito do cache de documentos (Fase 15.7) generalizado pra todas
  // as entradas: o blob principal publicado no Arweave passa a ser um
  // manifesto pequeno (entryId -> cid/contentHash), cada entrada vira um
  // blob cifrado próprio no cache local (`vault_entries/<id>.enc`), só
  // republicado/buscado de novo quando ela muda de verdade. Formato local em
  // disco (`vault.enc`) não muda — essas funções só alimentam/consomem a
  // camada de publicação (VaultPublishService) e sync (VaultSyncService).

  // Prefixo mágico ASCII "TIDM1" — só em blobs de manifesto, nunca em blobs
  // de entrada nem no vault legado inteiro. Permite a um leitor decidir
  // "isso é um manifesto ou o vault inteiro (formato antigo)?" só olhando os
  // primeiros bytes, sem gastar uma decifra. Mirror de `MANIFEST_MAGIC`
  // (desktop/src-tauri/src/vault.rs).
  static const List<int> _manifestMagic = [0x54, 0x49, 0x44, 0x4D, 0x31];

  bool _bytesStartWith(Uint8List bytes, List<int> prefix) {
    if (bytes.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[i] != prefix[i]) return false;
    }
    return true;
  }

  Future<String> _manifestCachePath() async {
    if (_testPath != null) return '$_testPath.manifest';
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/vault.manifest.enc';
  }

  /// Peek no prefixo mágico antes de tentar decifrar — devolve `null` sem
  /// custo de decifra se `bytes` não for um manifesto (blob legado, vault
  /// inteiro). Quem chama cai pro comportamento legado exato de hoje nesse
  /// caso (ver [VaultSyncService.sync]).
  Future<VaultManifest?> tryDecodeManifest(Uint8List bytes) async {
    if (!_bytesStartWith(bytes, _manifestMagic)) return null;
    final json =
        await _cipherService.decrypt(bytes.sublist(_manifestMagic.length));
    return VaultManifest.fromJson(
        jsonDecode(utf8.decode(json)) as Map<String, dynamic>);
  }

  Future<Uint8List> encryptManifestBlob(VaultManifest manifest) async {
    final json =
        Uint8List.fromList(utf8.encode(jsonEncode(manifest.toJson())));
    final blob = await _cipherService.encrypt(json);
    return Uint8List.fromList([..._manifestMagic, ...blob]);
  }

  /// Último manifesto aplicado (sync) ou publicado (publish) com sucesso
  /// por este device — baseline pra diffar contra o manifesto remoto novo
  /// (sync) ou contra as entradas atuais (publish).
  /// Tira do caminho o cache local que já não decifra com a vault key atual
  /// (P89): quando outro device rotaciona a DEK, `tryRecoverFromChain` troca
  /// a chave deste device e tudo que foi cifrado com a antiga — `vault.enc`,
  /// snapshot publicado, manifesto e blobs de entrada — vira erro de
  /// decifra. O `sync()` então nunca chegava a buscar o vault novo: falhava
  /// em `currentVersion()` e caía no fallback de cache, que também não lê.
  ///
  /// O `vault.enc` **não** é apagado: vai pra `vault.enc.unreadable`
  /// (sobrescrevendo uma cópia anterior). Uma falha de decifra pode ser
  /// transitória (chave errada por um instante) e o arquivo pode ter edições
  /// ainda não publicadas — o que é derivável (snapshot, manifesto, cache de
  /// entradas) é descartado, o que não é fica guardado.
  Future<void> setAsideUnreadableLocalCache() async {
    final vaultFile = File(await _vaultPath());
    if (await vaultFile.exists()) {
      await vaultFile.copy('${vaultFile.path}.unreadable');
      await vaultFile.delete();
    }
    for (final path in [
      await _publishedSnapshotPath(),
      await _manifestCachePath(),
    ]) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    final entriesDir = Directory(await _entryDir());
    if (await entriesDir.exists()) await entriesDir.delete(recursive: true);
    await _storage.delete(key: _publishedVersionKey);
    await _storage.delete(key: _publishedContentHashKey);
  }

  Future<VaultManifest?> loadLastManifest() async {
    final path = await _manifestCachePath();
    final file = File(path);
    if (!await file.exists()) return null;
    final blob = await file.readAsBytes();
    final json = await _cipherService.decrypt(blob);
    return VaultManifest.fromJson(
        jsonDecode(utf8.decode(json)) as Map<String, dynamic>);
  }

  Future<void> saveLastManifest(VaultManifest manifest) async {
    final json =
        Uint8List.fromList(utf8.encode(jsonEncode(manifest.toJson())));
    final blob = await _cipherService.encrypt(json);
    final path = await _manifestCachePath();
    await _writeFileAtomic(path, blob);
  }

  Future<String> _entryDir() async {
    if (_testPath != null) return '$_testPath.entries';
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/vault_entries';
  }

  Future<String> _entryPath(String entryId) async =>
      '${await _entryDir()}/$entryId.enc';

  /// Lê o blob cifrado de uma entrada do cache local, se existir. `null` se
  /// essa entrada nunca foi buscada/publicada neste device.
  Future<Uint8List?> readEntryBlob(String entryId) async {
    final file = File(await _entryPath(entryId));
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  /// Cifra uma entrada (mesma cifra individual de `card_number`/`cvv` que o
  /// vault local já aplica em disco, ver `_encryptCardFieldsInEntries`) e
  /// grava no cache local. Retorna o blob cifrado, pra publicar sem reler.
  Future<Uint8List> writeEntryBlob(String entryId, VaultEntry entry) async {
    final forDisk = (await _encryptCardFieldsInEntries([entry])).first;
    final json =
        Uint8List.fromList(utf8.encode(jsonEncode(forDisk.toJson())));
    final blob = await _cipherService.encrypt(json);
    await cacheEntryBlobRaw(entryId, blob);
    return blob;
  }

  /// Grava um blob **já cifrado** no cache local (buscado por cid via
  /// sync), sem recifrar.
  Future<void> cacheEntryBlobRaw(String entryId, Uint8List encrypted) async {
    final dir = Directory(await _entryDir());
    if (!await dir.exists()) await dir.create(recursive: true);
    await File(await _entryPath(entryId)).writeAsBytes(encrypted);
  }

  /// Decifra um blob de entrada de volta pra [VaultEntry] em claro
  /// (`card_number`/`cvv` inclusive — mesma normalização de `_load()`).
  Future<VaultEntry> decryptEntryBlob(Uint8List blob) async {
    final json = await _cipherService.decrypt(blob);
    final entry = VaultEntry.fromJson(
        jsonDecode(utf8.decode(json)) as Map<String, dynamic>);
    final decrypted = await _decryptCardFieldsInEntries([entry]);
    return decrypted.first;
  }

  // Extraído de `_diffCount` pra ser reaproveitado por
  // `diffEntriesSinceLastPublish` — mesma lógica exata (achada/modificada/
  // removida por id), agora devolvendo os ids + tipo em vez de só contar.
  // `_diffCount` chama isto e soma `.length`, comportamento/assinatura
  // pública inalterados.
  Map<String, EntryDiffKind> _diffEntries(
      _VaultData current, _VaultData published) {
    final result = <String, EntryDiffKind>{};
    final publishedById = {for (final e in published.entries) e.id: e};
    final currentById = {for (final e in current.entries) e.id: e};
    for (final entry in currentById.entries) {
      final prev = publishedById[entry.key];
      if (prev == null) {
        result[entry.key] = EntryDiffKind.added;
      } else if (jsonEncode(entry.value.toJson()) != jsonEncode(prev.toJson())) {
        result[entry.key] = EntryDiffKind.modified;
      }
    }
    for (final id in publishedById.keys) {
      if (!currentById.containsKey(id)) result[id] = EntryDiffKind.removed;
    }
    return result;
  }

  /// Quais entradas mudaram desde o último snapshot publicado — usado por
  /// [VaultPublishService] pra saber quais blobs de entrada precisam de uma
  /// publicação nova no Arweave (entradas inalteradas mantêm o cid/hash já
  /// registrado no último manifesto).
  Future<Map<String, EntryDiffKind>> diffEntriesSinceLastPublish() async {
    final current = await _load();
    final snapshot =
        await _loadPublishedSnapshot() ?? const _VaultData(version: 0, entries: []);
    return _diffEntries(current, snapshot);
  }

  /// Diferença entre `manifest.entries` e `lastManifest?.entries` por
  /// `contentHash` — usado pelo sync pra saber quais blobs de entrada
  /// precisam ser buscados de novo (id ausente no manifesto anterior também
  /// conta como mudança, cobre cold-start/device novo).
  Set<String> manifestChangedEntryIds(
      VaultManifest manifest, VaultManifest? lastManifest) {
    final prev = lastManifest?.entries ?? const <String, ManifestEntryRef>{};
    return {
      for (final entry in manifest.entries.entries)
        if (prev[entry.key]?.contentHash != entry.value.contentHash) entry.key,
    };
  }

  /// Reconstrói o vault local (`_VaultData`/`vault.enc`) a partir de um
  /// manifesto + entradas já cacheadas/buscadas ([cacheEntryBlobRaw]/
  /// [readEntryBlob]) — entradas fora de `changedEntryIds` são preservadas
  /// do vault local atual (evita decifrar de novo o que não mudou); as
  /// demais vêm do cache por-entrada. Funciona também a partir de um vault
  /// local vazio (cold-start, device novo pareado sem cache ainda) — toda
  /// entrada do manifesto conta como "mudada" nesse caso.
  Future<void> reassembleFromManifest(
    VaultManifest manifest, {
    required Set<String> changedEntryIds,
  }) async {
    final hasLocal = await hasLocalVault();
    final current =
        hasLocal ? await _load() : const _VaultData(version: 0, entries: []);
    final byId = {for (final e in current.entries) e.id: e};
    final newEntries = <VaultEntry>[];
    for (final id in manifest.entries.keys) {
      if (changedEntryIds.contains(id) || !byId.containsKey(id)) {
        final blob = await readEntryBlob(id);
        if (blob == null) continue; // caller busca antes de chamar
        newEntries.add(await decryptEntryBlob(blob));
      } else {
        newEntries.add(byId[id]!);
      }
    }
    await _save(_VaultData(
      version: manifest.vaultVersion,
      entries: newEntries,
      profileNames: manifest.profileNames,
      devicePermissions: manifest.devicePermissions,
    ));
  }

  // Serializa o vault local inteiro e cifra com uma senha de export (PBKDF2 +
  // AES-256-GCM via BackupCipherService), independente da vault key derivada
  // da wallet/pareamento — ver project/INDEX.md, roadmap item 4.
  //
  // Se houver uma wallet Arweave local, ela viaja embutida no mesmo backup
  // (campo extra no envelope, nunca no _VaultData/vault.enc local — ver
  // `_vaultDataToJsonMap`) — é a única forma de recuperá-la numa
  // reinstalação/troca de device, já que ela não tem nenhum vínculo com a
  // wallet Ethereum/identidade (achado real, Sessão 221: wallet órfã depois
  // de reinstalar, saldo perdido por não ter backup nenhum).
  Future<Uint8List> exportBackup(String password) async {
    final data = await _load();
    // Fase 15.8: backup exportado sai de circulação (USB, nuvem, etc.) —
    // card_number/cvv ganham a mesma cifra individual extra que vault.enc
    // já tem, além da cifra por senha do backup em si.
    final forExport = _VaultData(
      version: data.version,
      entries: await _encryptCardFieldsInEntries(data.entries),
      profileNames: data.profileNames,
      devicePermissions: data.devicePermissions,
    );
    final map = _vaultDataToJsonMap(forExport);
    final walletJson = await _arweaveWalletService.exportJwkJson();
    if (walletJson != null) {
      map['arweave_wallet_jwk'] = walletJson;
    }
    return _backupCipherService.encrypt(
      Uint8List.fromList(utf8.encode(jsonEncode(map))),
      password,
    );
  }

  // Decifra um blob de backup com a senha de export e **sobrescreve** o
  // vault local, recifrando com a vault key deste device via _save() — a
  // senha de export nunca é usada pro armazenamento local. Não altera a
  // `version` do JSON importado: se estiver desatualizada frente à on-chain,
  // VaultSyncService.sync() corrige sozinho no próximo sync (ver
  // vault_sync_service.dart, `if (ref.version <= localVersion)`).
  //
  // Se o backup carrega uma wallet Arweave embutida e este device ainda não
  // tem nenhuma, ela é restaurada — mas nunca sobrescrevendo uma wallet
  // local já existente (poderia estar fundada; é a mesma classe do bug real
  // que motivou isso, só que no sentido import→overwrite em vez de
  // generate→overwrite).
  Future<void> importBackup(Uint8List blob, String password) async {
    final json = await _backupCipherService.decrypt(blob, password);
    final map = jsonDecode(utf8.decode(json)) as Map<String, dynamic>;
    final parsed = _vaultDataFromJsonMap(map);

    final walletJson = map['arweave_wallet_jwk'] as String?;
    if (walletJson != null && !(await _arweaveWalletService.exists())) {
      await _arweaveWalletService.import(walletJson);
    }

    // Fase 15.8: normaliza card_number/cvv pra texto plano antes de
    // _save() — o backup carrega os campos já cifrados (ver
    // exportBackup); sem isso, _save() cifraria de novo em cima de um
    // valor já cifrado.
    await _save(_VaultData(
      version: parsed.version,
      entries: await _decryptCardFieldsInEntries(parsed.entries),
      profileNames: parsed.profileNames,
      devicePermissions: parsed.devicePermissions,
    ));
  }

  // -------------------------------------------------------------------------
  // Privado
  // -------------------------------------------------------------------------

  Future<String> _vaultPath() async {
    if (_testPath != null) return _testPath;
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/vault.enc';
  }

  // Converte o Map JSON já decodificado pro _VaultData — extraído de
  // _parseVaultJson pra ser reaproveitado por importBackup() sem passar
  // pelo passo de decode/encode duas vezes, e pra manter o parsing
  // separado de qualquer campo extra (como arweave_wallet_jwk) que só
  // existe no envelope do backup, nunca no _VaultData em si.
  _VaultData _vaultDataFromJsonMap(Map<String, dynamic> map) {
    final entries = (map['entries'] as List)
        .map((e) => VaultEntry.fromJson(e as Map<String, dynamic>))
        .toList();
    final profileNames = map['profile_names'] != null
        ? List<String>.from(map['profile_names'] as List)
        : const <String>[];
    final devicePermissions = map['device_permissions'] != null
        ? (map['device_permissions'] as List)
            .map((p) => VaultDevicePermission.fromJson(p as Map<String, dynamic>))
            .toList()
        : const <VaultDevicePermission>[];
    return _VaultData(
      version: (map['version'] as int?) ?? 0,
      entries: entries,
      profileNames: profileNames,
      devicePermissions: devicePermissions,
    );
  }

  // Desserializa o JSON plano (já decifrado) do vault — compartilhado entre
  // _load() (lê do vault.enc local) e o path de sync.
  _VaultData _parseVaultJson(Uint8List json) {
    final map = jsonDecode(utf8.decode(json)) as Map<String, dynamic>;
    return _vaultDataFromJsonMap(map);
  }

  // Converte o _VaultData pro Map JSON (ainda não codificado/cifrado) —
  // extraído de _serializeVaultData pra ser reaproveitado por
  // exportBackup(), que precisa inserir um campo extra (arweave_wallet_jwk)
  // no Map antes de codificar, sem que esse campo nunca chegue a passar
  // por aqui de volta pro vault.enc local.
  Map<String, dynamic> _vaultDataToJsonMap(_VaultData data) => {
        'version': data.version,
        'entries': data.entries.map((e) => e.toJson()).toList(),
        'profile_names': data.profileNames,
        'device_permissions': data.devicePermissions.map((p) => p.toJson()).toList(),
      };

  // Serializa o vault pro JSON plano (ainda não cifrado) — compartilhado
  // entre _save() (grava no vault.enc local) e o path de sync.
  Uint8List _serializeVaultData(_VaultData data) {
    final map = _vaultDataToJsonMap(data);
    return Uint8List.fromList(utf8.encode(jsonEncode(map)));
  }

  Future<_VaultData> _load() async {
    final path = await _vaultPath();
    final file = File(path);
    if (!await file.exists()) {
      return const _VaultData(version: 0, entries: []);
    }
    final blob = await file.readAsBytes();
    final json = await _cipherService.decrypt(blob);
    final data = _parseVaultJson(json);
    await _migrateLegacyDocuments(data.entries);
    // Fase 15.8: decifra card_number/cvv — em memória, o resto do app
    // sempre vê texto plano (fallback automático pra entradas anteriores à
    // 15.8, ainda em claro no disco).
    final entries = await _decryptCardFieldsInEntries(data.entries);
    return _VaultData(
      version: data.version,
      entries: entries,
      profileNames: data.profileNames,
      devicePermissions: data.devicePermissions,
    );
  }

  // Serializa o vault, cifra os campos individuais de cartão numa cópia
  // (nunca muta `data` do caller, que continua em claro depois desta
  // chamada) e grava em disco.
  Future<void> _save(_VaultData data) async {
    final forDisk = _VaultData(
      version: data.version,
      entries: await _encryptCardFieldsInEntries(data.entries),
      profileNames: data.profileNames,
      devicePermissions: data.devicePermissions,
    );
    final json = _serializeVaultData(forDisk);
    final blob = await _cipherService.encrypt(json);
    final path = await _vaultPath();
    await File(path).writeAsBytes(blob);
  }

  // ---------------------------------------------------------------------------
  // Cache local de documentos (Fase 15.7)
  // ---------------------------------------------------------------------------
  //
  // Conteúdo cifrado de cada documento vive à parte do blob principal do
  // vault — só um cid/hash aponta pra cá de dentro do vault.enc (ver
  // DocumentData.cid/contentHash). Motivo: um documento grande não deve
  // inflar o blob que é sincronizado a cada edição não relacionada (ver
  // project/PHASE.md, 15.7).

  Future<String> _documentDir() async {
    if (_testPath != null) return '$_testPath.documents';
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/vault_documents';
  }

  Future<String> _documentPath(String entryId) async =>
      '${await _documentDir()}/$entryId.enc';

  /// Lê o blob cifrado do documento de uma entrada, se existir localmente.
  /// `null` se essa entrada nunca teve conteúdo salvo neste device (ex:
  /// documento adicionado em outro device, ainda não buscado por cid).
  Future<Uint8List?> readDocumentBlob(String entryId) async {
    final file = File(await _documentPath(entryId));
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  /// Cifra e grava o conteúdo em claro de um documento no cache local.
  /// Retorna o blob cifrado (evita reler do disco pra computar o hash na
  /// hora de pinar).
  Future<Uint8List> writeDocumentBlob(String entryId, Uint8List plaintext) async {
    final blob = await _cipherService.encrypt(plaintext);
    await cacheDocumentBlobRaw(entryId, blob);
    return blob;
  }

  /// Grava um blob **já cifrado** no cache local, sem recifrar — usado ao
  /// buscar o conteúdo de um documento por cid (já vem cifrado do IPFS).
  Future<void> cacheDocumentBlobRaw(String entryId, Uint8List encrypted) async {
    final dir = Directory(await _documentDir());
    if (!await dir.exists()) await dir.create(recursive: true);
    await File(await _documentPath(entryId)).writeAsBytes(encrypted);
  }

  /// Lê o conteúdo (em claro) do documento de uma entrada — cache local
  /// primeiro (rápido, offline); se ausente (documento adicionado em outro
  /// device e nunca buscado aqui), busca pelo `cid` num gateway IPFS
  /// público, confere `contentHash` antes de decifrar (mesmo padrão
  /// defensivo de [VaultSyncService.sync]), e grava no cache local pra
  /// próxima vez.
  Future<Uint8List> readDocumentContent(
    String entryId, {
    String? cid,
    String? contentHash,
    IpfsGatewayClient? gatewayClient,
  }) async {
    var blob = await readDocumentBlob(entryId);
    if (blob == null) {
      if (cid == null) {
        throw Exception(
            'document has no local content and was never published');
      }
      final client = gatewayClient ?? IpfsGatewayClient();
      final fetched = await client.fetch(cid);
      if (contentHash != null) {
        final actual = bytesToHex(keccak256(fetched), include0x: true);
        if (actual != contentHash) {
          throw Exception(
              'document hash mismatch — blob corrupted or tampered');
        }
      }
      await cacheDocumentBlobRaw(entryId, fetched);
      blob = fetched;
    }
    return _cipherService.decrypt(blob);
  }

  /// Decide se o conteúdo local de um documento precisa ser (re)pinado —
  /// `true` se nunca foi pinado (`storedHash` null) ou se o hash do blob
  /// local não bate com o último hash pinado. Evita rechamar o pin (rede)
  /// numa publicação onde só outra entrada do vault mudou.
  bool documentNeedsPin(Uint8List localBlob, String? storedHash) {
    if (storedHash == null) return true;
    final actual = bytesToHex(keccak256(localBlob), include0x: true);
    return actual != storedHash;
  }

  // ---------------------------------------------------------------------------
  // Cifra individual de card_number/cvv (Fase 15.8)
  // ---------------------------------------------------------------------------
  //
  // Princípio único: card_number/cvv são SEMPRE texto plano na representação
  // em memória (o resto do app nunca muda) e SEMPRE cifrados individualmente
  // na representação em disco/export. A fronteira entre as duas é só nos
  // pontos de parse/serialize bruto — ver _decryptCardFieldsInEntries (usado
  // em _load()/markPublished()/importBackup()) e _encryptCardFieldsInEntries
  // (usado em _save()/exportBackup()). Reusa a mesma vault key/cifra de
  // _cipherService (mesmo precedente da 15.7 com documentos) — sem sub-chave
  // derivada, ver justificativa em project/PHASE.md, 15.8.

  Future<String> _encryptCardField(String value) async {
    final blob = await _cipherService.encrypt(Uint8List.fromList(utf8.encode(value)));
    return base64Encode(blob);
  }

  /// Tenta decifrar um campo individualmente cifrado. Se falhar por
  /// qualquer motivo (base64 inválido, blob curto demais, tag AEAD não
  /// bate), assume que é uma entrada anterior à 15.8 (ainda em texto
  /// plano) e devolve o valor como está — mesmo padrão de fallback que o
  /// Rust (`vault.rs::try_decrypt_card_field`) usa.
  Future<String> _tryDecryptCardField(String value) async {
    try {
      final blob = base64Decode(value);
      final plain = await _cipherService.decrypt(blob);
      return utf8.decode(plain);
    } catch (_) {
      return value;
    }
  }

  CreditCardData _withCardFields(CreditCardData card, String cardNumber, String cvv) =>
      CreditCardData(
        label: card.label,
        cardHolderName: card.cardHolderName,
        cardNumber: cardNumber,
        expiryMonth: card.expiryMonth,
        expiryYear: card.expiryYear,
        cvv: cvv,
        bank: card.bank,
        cardNetwork: card.cardNetwork,
      );

  /// Decifra card_number/cvv de toda entrada tipo cartão, devolvendo uma
  /// nova lista (VaultEntry é imutável). Chamado por `_load()`,
  /// `markPublished()` e `importBackup()` — os 3 pontos que fazem
  /// parse bruto de um Vault vindo de fora da representação em memória já
  /// normalizada por `_load()`. Crítico pra corretude em `markPublished()`,
  /// não só consistência: sem essa normalização ali, o snapshot local
  /// ficaria com os campos cifrados (nonce novo a cada save) enquanto
  /// `pendingChanges()` compara contra `_load()` (sempre em claro) —
  /// qualquer vault com cartão veria "pendência fantasma" pra sempre.
  Future<List<VaultEntry>> _decryptCardFieldsInEntries(List<VaultEntry> entries) async {
    final result = <VaultEntry>[];
    for (final entry in entries) {
      final card = entry.creditCard;
      if (card == null) {
        result.add(entry);
        continue;
      }
      result.add(entry.copyWith(
        creditCard: _withCardFields(
          card,
          await _tryDecryptCardField(card.cardNumber),
          await _tryDecryptCardField(card.cvv),
        ),
      ));
    }
    return result;
  }

  /// Cifra card_number/cvv individualmente numa nova lista, pra
  /// serialização em disco/export — nunca muta as entradas do caller.
  /// Chamado por `_save()` e `exportBackup()`.
  Future<List<VaultEntry>> _encryptCardFieldsInEntries(List<VaultEntry> entries) async {
    final result = <VaultEntry>[];
    for (final entry in entries) {
      final card = entry.creditCard;
      if (card == null) {
        result.add(entry);
        continue;
      }
      result.add(entry.copyWith(
        creditCard: _withCardFields(
          card,
          await _encryptCardField(card.cardNumber),
          await _encryptCardField(card.cvv),
        ),
      ));
    }
    return result;
  }

  // Migração (Fase 15.7): documentos antigos guardavam o conteúdo em base64
  // embutido direto no JSON da entrada (DocumentData._legacyFileData, só
  // populado por fromJson pra esse fim). Uma entrada com esse campo ainda
  // preenchido e cid ausente não passou pela migração ainda — decifra o
  // base64 legado e escreve no cache local; cid/contentHash continuam null
  // até o próximo publish pinar como blob separado.
  Future<void> _migrateLegacyDocuments(List<VaultEntry> entries) async {
    for (final entry in entries) {
      final doc = entry.document;
      if (doc == null || doc.cid != null) continue;
      final legacy = doc._legacyFileData;
      if (legacy == null || legacy.isEmpty) continue;
      try {
        await writeDocumentBlob(entry.id, base64Decode(legacy));
      } catch (_) {
        // base64 inválido — não trava o load, só não migra essa entrada
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Helper interno
// ---------------------------------------------------------------------------

String _generateId() {
  final r = Random.secure();
  return List.generate(16, (_) => r.nextInt(256))
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}
