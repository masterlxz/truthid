import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/vault_repository.dart';
import '../theme.dart';

// Backup criptografado exportável do vault inteiro (item 4 do roadmap
// pós-Fase 14) — mirror do "Backup" no Desktop (VaultBackup.tsx). Cifrado com
// uma senha de exportação separada (PBKDF2+AES-256-GCM, ver
// BackupCipherService), não a vault key derivada do pareamento — restaurar
// não deve exigir re-parear com o Desktop. Disponível independente de
// canWriteVault (ver vault_screen.dart) — mesmo device só-leitura pode fazer
// backup do que já vê.
class VaultBackupScreen extends StatefulWidget {
  final VaultRepository? repository;

  const VaultBackupScreen({super.key, this.repository});

  @override
  State<VaultBackupScreen> createState() => _VaultBackupScreenState();
}

class _VaultBackupScreenState extends State<VaultBackupScreen> {
  late final VaultRepository _repository;

  final _exportPasswordCtrl = TextEditingController();
  final _exportPasswordConfirmCtrl = TextEditingController();
  bool _exporting = false;
  String? _exportError;
  bool _exportDone = false;

  Uint8List? _pickedFileBytes;
  String? _pickedFileName;
  final _importPasswordCtrl = TextEditingController();
  bool _importing = false;
  String? _importError;
  bool _importDone = false;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? VaultRepository();
  }

  @override
  void dispose() {
    _exportPasswordCtrl.dispose();
    _exportPasswordConfirmCtrl.dispose();
    _importPasswordCtrl.dispose();
    super.dispose();
  }

  bool get _exportInvalid =>
      _exportPasswordCtrl.text.trim().isEmpty ||
      _exportPasswordCtrl.text != _exportPasswordConfirmCtrl.text;

  Future<void> _export() async {
    setState(() {
      _exportError = null;
      _exporting = true;
      _exportDone = false;
    });
    try {
      final blob = await _repository.exportBackup(_exportPasswordCtrl.text);
      final path = await FilePicker.platform.saveFile(
        fileName: 'vault-backup.truthid-backup',
        type: FileType.custom,
        allowedExtensions: ['truthid-backup'],
        bytes: blob,
      );
      if (path == null) {
        // Usuário cancelou o diálogo.
        setState(() => _exporting = false);
        return;
      }
      _exportPasswordCtrl.clear();
      _exportPasswordConfirmCtrl.clear();
      setState(() {
        _exporting = false;
        _exportDone = true;
      });
    } catch (e) {
      setState(() {
        _exportError = '$e';
        _exporting = false;
      });
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['truthid-backup'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    setState(() {
      _pickedFileBytes = result.files.single.bytes;
      _pickedFileName = result.files.single.name;
      _importDone = false;
      _importError = null;
    });
  }

  Future<void> _import() async {
    if (_pickedFileBytes == null || _importPasswordCtrl.text.trim().isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import backup?'),
        content: const Text(
          'This will overwrite your ENTIRE local vault on this device with '
          'the contents of the backup file. This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Import', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _importError = null;
      _importing = true;
      _importDone = false;
    });
    try {
      await _repository.importBackup(_pickedFileBytes!, _importPasswordCtrl.text);
      _importPasswordCtrl.clear();
      setState(() {
        _importing = false;
        _importDone = true;
        _pickedFileBytes = null;
        _pickedFileName = null;
      });
    } catch (e) {
      setState(() {
        _importError = '$e';
        _importing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup / restore')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: ListView(
          children: [
            const Text(
              'Export or restore the entire vault (passwords, 2FA, passkeys, '
              'profiles) as a .truthid-backup file. Encrypted with its own '
              'password, separate from your wallet — keep it safe, it cannot '
              'be recovered.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 24),

            const Text('Export', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            TextField(
              controller: _exportPasswordCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Export password'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _exportPasswordConfirmCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Confirm password'),
              onChanged: (_) => setState(() {}),
            ),
            if (_exportError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_exportError!, style: const TextStyle(color: AppColors.danger)),
              ),
            if (_exportDone)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Backup saved ✓', style: TextStyle(color: AppColors.textMuted)),
              ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: (_exportInvalid || _exporting) ? null : _export,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.background,
              ),
              child: Text(_exporting ? 'Exporting...' : 'Export backup'),
            ),

            const SizedBox(height: 32),

            const Text('Import', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _pickFile,
              child: Text(_pickedFileName ?? 'Choose .truthid-backup file'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _importPasswordCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Backup password'),
              onChanged: (_) => setState(() {}),
            ),
            if (_importError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_importError!, style: const TextStyle(color: AppColors.danger)),
              ),
            if (_importDone)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Backup imported ✓', style: TextStyle(color: AppColors.textMuted)),
              ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: (_pickedFileBytes == null ||
                      _importPasswordCtrl.text.trim().isEmpty ||
                      _importing)
                  ? null
                  : _import,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger,
                side: const BorderSide(color: AppColors.danger),
              ),
              child: Text(_importing ? 'Importing...' : 'Import'),
            ),
          ],
        ),
      ),
    );
  }
}
