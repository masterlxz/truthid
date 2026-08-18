import 'package:flutter/material.dart';

import '../services/vault_repository.dart';
import '../theme.dart';
import '../l10n/l10n_extensions.dart';

// Gerenciar perfis nomeados pelo usuário — mirror da seção "Gerenciar
// perfis" do Desktop (VaultManagement.tsx). Só alcançável quando o device
// tem canWriteVault (checado em vault_screen.dart antes de navegar pra cá).
// Ver project/INDEX.md, Sessão 97.
class VaultProfilesScreen extends StatefulWidget {
  final VaultRepository? repository;

  const VaultProfilesScreen({super.key, this.repository});

  @override
  State<VaultProfilesScreen> createState() => _VaultProfilesScreenState();
}

class _VaultProfilesScreenState extends State<VaultProfilesScreen> {
  late final VaultRepository _repository;
  List<String> _profiles = [];
  bool _loading = true;
  String? _error;
  final _newNameCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? VaultRepository();
    _load();
  }

  @override
  void dispose() {
    _newNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final profiles = await _repository.listProfileNames();
    if (mounted) setState(() { _profiles = profiles; _loading = false; });
  }

  Future<void> _add() async {
    final name = _newNameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _error = null);
    try {
      await _repository.addProfile(name);
      _newNameCtrl.clear();
      await _load();
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  Future<void> _rename(String oldName) async {
    final controller = TextEditingController(text: oldName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.vaultProfilesScreenRenameTitle),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(context.l10n.vaultProfilesScreenCancelButton)),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text(context.l10n.vaultProfilesScreenRenameButton),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == oldName) return;

    setState(() => _error = null);
    try {
      await _repository.renameProfile(oldName, newName);
      await _load();
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  Future<void> _delete(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.vaultProfilesScreenDeleteTitle),
        content: Text(context.l10n.vaultProfilesScreenDeleteBody(name)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(context.l10n.vaultProfilesScreenCancelButton)),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(context.l10n.vaultProfilesScreenDeleteButton,
                style: const TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _error = null);
    try {
      await _repository.deleteProfile(name);
      await _load();
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.vaultProfilesScreenTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.l10n.vaultProfilesScreenIntro,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(_error!, style: const TextStyle(color: AppColors.danger)),
                    ),
                  Expanded(
                    child: _profiles.isEmpty
                        ? Center(
                            child: Text(context.l10n.vaultProfilesScreenEmptyState,
                                style: const TextStyle(color: AppColors.textMuted)),
                          )
                        : ListView(
                            children: _profiles
                                .map((p) => Card(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      child: ListTile(
                                        title: Text(p),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: const Icon(Icons.edit),
                                              tooltip: context.l10n
                                                  .vaultProfilesScreenRenameTooltip,
                                              onPressed: () => _rename(p),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                                              tooltip: context.l10n
                                                  .vaultProfilesScreenDeleteTooltip,
                                              onPressed: () => _delete(p),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ))
                                .toList(),
                          ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _newNameCtrl,
                          decoration: InputDecoration(
                              labelText:
                                  context.l10n.vaultProfilesScreenNewNameLabel),
                          onSubmitted: (_) => _add(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _add,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: AppColors.background,
                        ),
                        child: Text(context.l10n.vaultProfilesScreenAddButton),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}
