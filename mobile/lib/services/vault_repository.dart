import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'vault_cipher_service.dart';

// ---------------------------------------------------------------------------
// Modelo de entrada do vault
// ---------------------------------------------------------------------------

class VaultEntry {
  final String id;
  final String site;
  final String url;
  final String username;
  final String password;
  final String notes;
  /// Lista de grupos a que esta entrada pertence (ex: ["Trabalho", "Casa"]).
  final List<String> profiles;
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
        'created_at': createdAt.millisecondsSinceEpoch ~/ 1000,
        'updated_at': updatedAt.millisecondsSinceEpoch ~/ 1000,
      };

  VaultEntry copyWith({
    String? site,
    String? url,
    String? username,
    String? password,
    String? notes,
    List<String>? profiles,
  }) =>
      VaultEntry(
        id: id,
        site: site ?? this.site,
        url: url ?? this.url,
        username: username ?? this.username,
        password: password ?? this.password,
        notes: notes ?? this.notes,
        profiles: profiles ?? this.profiles,
        createdAt: createdAt,
        updatedAt: DateTime.now().toUtc(),
      );
}

/// Permissão de escrita de um device no vault (`pubKey` = endereço do device).
/// Concedida só pelo Desktop/controller — o Mobile só lê, nunca escreve esse
/// campo (ver PROJECT_STATE.md, Sessão 97).
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
  /// Permissões de escrita por device — Mobile só lê (ver VaultDevicePermission).
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
  // Caminho injetado nos testes; null = usa path_provider em produção.
  final String? _testPath;

  VaultRepository({VaultCipherService? cipherService, String? testPath})
      : _cipherService = cipherService ?? VaultCipherService(),
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

  Future<VaultEntry> addEntry({
    required String site,
    String url = '',
    required String username,
    required String password,
    String notes = '',
    List<String> profiles = const [],
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
  static const _storage = FlutterSecureStorage();

  Future<void> markPublished(int version) async {
    await _storage.write(
      key: _publishedVersionKey,
      value: version.toString(),
    );
  }

  // Quantas versões do vault local ainda não foram publicadas. 0 = nada
  // pendente.
  Future<int> pendingChanges() async {
    final data = await _load();
    final raw = await _storage.read(key: _publishedVersionKey);
    final last = raw != null ? int.tryParse(raw) ?? 0 : 0;
    final pending = data.version - last;
    return pending > 0 ? pending : 0;
  }

  // -------------------------------------------------------------------------
  // Privado
  // -------------------------------------------------------------------------

  Future<String> _vaultPath() async {
    if (_testPath != null) return _testPath!;
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/vault.enc';
  }

  Future<_VaultData> _load() async {
    final path = await _vaultPath();
    final file = File(path);
    if (!await file.exists()) {
      return const _VaultData(version: 0, entries: []);
    }
    final blob = await file.readAsBytes();
    final json = await _cipherService.decrypt(blob);
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

  Future<void> _save(_VaultData data) async {
    final map = {
      'version': data.version,
      'entries': data.entries.map((e) => e.toJson()).toList(),
      'profile_names': data.profileNames,
      'device_permissions': data.devicePermissions.map((p) => p.toJson()).toList(),
    };
    final json = utf8.encode(jsonEncode(map));
    final blob = await _cipherService.encrypt(Uint8List.fromList(json));
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
