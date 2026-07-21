import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'backup_cipher_service.dart';
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
        'created_at': createdAt.millisecondsSinceEpoch ~/ 1000,
        'updated_at': updatedAt.millisecondsSinceEpoch ~/ 1000,
      };

  /// Igual a [toJson], mas sem `totp_secret` — usar sempre que a entrada for
  /// sair pro canal da extensão de navegador (LAN/dead-drop em
  /// vault_session_screen.dart). 2FA continua isolado no Device por design
  /// (fatores separados); `passkey` já é enviado desde a Sessão 132 — a
  /// extensão precisa da chave privada pra assinar `navigator.credentials.get`
  /// em sites reais (ver `extension/src/webauthn.ts`).
  Map<String, dynamic> toJsonForExtension() {
    final json = toJson();
    json.remove('totp_secret');
    return json;
  }

  // `totpSecret`/`passkey` usam um sentinel em vez de tipo anulável puro:
  // precisa distinguir "não passei esse argumento" (mantém o valor atual) de
  // "passei null de propósito" (apaga o campo da entrada) — um `?? this.x`
  // comum não permite nunca limpar o campo de volta pra null.
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
        createdAt: createdAt,
        updatedAt: DateTime.now().toUtc(),
      );
}

/// Permissão de escrita de um device no vault (`pubKey` = endereço do device).
/// Normalmente concedida pelo Desktop/controller, mas o Mobile também pode
/// gerenciar (ver `VaultRepository.setDevicePermission`) — trava de UX
/// (mesma que já protege as outras telas de escrita do Vault, `canWrite`),
/// não é imposta pelo contrato (ver PROJECT_STATE.md, Sessão 97).
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
// Container interno (não exposto fora do arquivo)
// ---------------------------------------------------------------------------

class _VaultData {
  final int version;
  final List<VaultEntry> entries;
  /// Nomes de perfis criados pelo usuário (ex: ["Trabalho", "Banco"]) — geridos
  /// só pelo Desktop (Mobile é somente-leitura pro Vault), ver PROJECT_STATE.md
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
  // Caminho injetado nos testes; null = usa path_provider em produção.
  final String? _testPath;

  VaultRepository({
    VaultCipherService? cipherService,
    BackupCipherService? backupCipherService,
    String? testPath,
  })  : _cipherService = cipherService ?? VaultCipherService(),
        _backupCipherService = backupCipherService ?? BackupCipherService(),
        _testPath = testPath;

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
      createdAt: now,
      updatedAt: now,
    );
    await _save(_VaultData(
      version: data.version + 1,
      entries: [...data.entries, entry],
      profileNames: data.profileNames,
      devicePermissions: data.devicePermissions,
    ));
    return entry;
  }

  Future<VaultEntry> updateEntry(VaultEntry entry) async {
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

  // Rastreio de publicação — mirror de mark_published/pending_changes do
  // Desktop (desktop/src-tauri/src/vault.rs), guardado localmente via
  // flutter_secure_storage em vez de um arquivo separado.
  static const _publishedVersionKey = 'vault_last_published_version';
  static const _publishedContentHashKey = 'vault_last_published_content_hash';
  static const _storage = FlutterSecureStorage();

  // Assinatura do conteúdo do vault (tudo, exceto `version`) — usada por
  // pendingChanges() pra distinguir "conteúdo diferente do publicado" de "só
  // a versão local subiu". Achado da Sessão 136: favoritar+desfavoritar bumpa
  // version duas vezes mas devolve o conteúdo exato de antes (setFavorite
  // preserva updatedAt de propósito), e a versão sozinha nunca "cancela".
  // Serialização de Map literal é determinística (mesma ordem de chaves
  // sempre), então o hash é estável pro mesmo conteúdo.
  String _contentSignature(_VaultData data) {
    final map = {
      'entries': data.entries.map((e) => e.toJson()).toList(),
      'profile_names': data.profileNames,
      'device_permissions': data.devicePermissions.map((p) => p.toJson()).toList(),
    };
    return sha256.convert(utf8.encode(jsonEncode(map))).toString();
  }

  Future<void> markPublished(int version) async {
    final data = await _load();
    await _storage.write(
      key: _publishedVersionKey,
      value: version.toString(),
    );
    await _storage.write(
      key: _publishedContentHashKey,
      value: _contentSignature(data),
    );
  }

  // Quantas versões do vault local ainda não foram publicadas. 0 = nada
  // pendente — inclusive quando a versão local subiu mas o conteúdo final é
  // idêntico ao que já foi publicado (ver _contentSignature).
  Future<int> pendingChanges() async {
    final data = await _load();
    final lastHash = await _storage.read(key: _publishedContentHashKey);
    if (lastHash != null && lastHash == _contentSignature(data)) {
      return 0;
    }
    final raw = await _storage.read(key: _publishedVersionKey);
    final last = raw != null ? int.tryParse(raw) ?? 0 : 0;
    final pending = data.version - last;
    return pending > 0 ? pending : 0;
  }

  // Serializa o vault local inteiro e cifra com uma senha de export (PBKDF2 +
  // AES-256-GCM via BackupCipherService), independente da vault key derivada
  // da wallet/pareamento — ver PROJECT_STATE.md, roadmap item 4.
  Future<Uint8List> exportBackup(String password) async {
    final data = await _load();
    return _backupCipherService.encrypt(_serializeVaultData(data), password);
  }

  // Decifra um blob de backup com a senha de export e **sobrescreve** o
  // vault local, recifrando com a vault key deste device via _save() — a
  // senha de export nunca é usada pro armazenamento local. Não altera a
  // `version` do JSON importado: se estiver desatualizada frente à on-chain,
  // VaultSyncService.sync() corrige sozinho no próximo sync (ver
  // vault_sync_service.dart, `if (ref.version <= localVersion)`).
  Future<void> importBackup(Uint8List blob, String password) async {
    final json = await _backupCipherService.decrypt(blob, password);
    await _save(_parseVaultJson(json));
  }

  // -------------------------------------------------------------------------
  // Privado
  // -------------------------------------------------------------------------

  Future<String> _vaultPath() async {
    if (_testPath != null) return _testPath!;
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/vault.enc';
  }

  // Desserializa o JSON plano (já decifrado) do vault — compartilhado entre
  // _load() (lê do vault.enc local) e importBackup() (lê de um backup).
  _VaultData _parseVaultJson(Uint8List json) {
    final map = jsonDecode(utf8.decode(json)) as Map<String, dynamic>;
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

  // Serializa o vault pro JSON plano (ainda não cifrado) — compartilhado
  // entre _save() (grava no vault.enc local) e exportBackup().
  Uint8List _serializeVaultData(_VaultData data) {
    final map = {
      'version': data.version,
      'entries': data.entries.map((e) => e.toJson()).toList(),
      'profile_names': data.profileNames,
      'device_permissions': data.devicePermissions.map((p) => p.toJson()).toList(),
    };
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
    return _parseVaultJson(json);
  }

  Future<void> _save(_VaultData data) async {
    final json = _serializeVaultData(data);
    final blob = await _cipherService.encrypt(json);
    final path = await _vaultPath();
    await File(path).writeAsBytes(blob);
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
