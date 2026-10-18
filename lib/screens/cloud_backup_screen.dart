import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../services/backup_envelope.dart';
import '../services/cloud_backup_service.dart';
import '../services/secure_storage_service.dart';
import '../services/zip_backup_service.dart';

/// Stage 4C-4 — Cloud Backup settings.
///
/// Flow: consent (approved wording) → passphrase create/confirm →
/// one-time recovery code display/confirm → enabled state with manual
/// Back Up Now, backup list, per-item restore/delete, disable and
/// permanent remote deletion.
///
/// SECURITY: passphrases and recovery codes are never logged and are
/// kept only in device secure storage. Remote uploads only ever happen
/// after explicit consent.
class CloudBackupScreen extends StatefulWidget {
  const CloudBackupScreen({super.key, this.service});

  /// Injectable for widget tests — defaults to the production instance.
  final CloudBackupService? service;

  @override
  State<CloudBackupScreen> createState() => _CloudBackupScreenState();
}

class _CloudBackupScreenState extends State<CloudBackupScreen> {
  CloudBackupService get _service =>
      widget.service ?? CloudBackupService.instance;

  bool _enabled = false;
  bool _loading = true;
  String? _busy; // non-null → an operation is running (progress label)
  List<RemoteBackupInfo> _backups = [];
  CloudBackupCancelToken? _token;

  static const String consentText = '''
Cloud Backup lets you securely store an encrypted copy of your Bragmat fishing records and photographs — including catch locations and photo metadata — so you can restore them if you lose or replace your phone.

Your backup is encrypted on your device before it is uploaded. Bragmat administrators and our cloud storage provider (Supabase) cannot read the contents of your encrypted backup.

You will need your backup passphrase or recovery code to restore it on another device. Your recovery code is shown once during setup and is not stored by Bragmat. If you lose both, your encrypted cloud backups cannot be recovered by anyone.

Cloud Backup is optional and turned off by default. Your fishing records remain stored on your device whether or not you enable it.

Bragmat retains up to your three most recent verified cloud backups; older backups are removed automatically. You can view and delete your cloud backups from the application.

You can disable Cloud Backup at any time. Disabling future backups does not automatically delete backups already stored online.''';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _token?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final enabled = await CloudBackupService.isEnabled;
    List<RemoteBackupInfo> backups = const [];
    if (enabled) {
      try {
        backups = await _service.listBackups();
      } catch (_) {
        // Listing failure is shown as an empty list + banner, not fatal.
      }
    }
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _backups = backups;
      _loading = false;
    });
  }

  // ── Enable flow ───────────────────────────────────────────────────────

  Future<void> _enableFlow() async {
    if (!await _showConsentDialog()) return;

    // Existing remote backups + no stored credentials → the user may be
    // re-enabling on a wiped device. Give them the choice to reuse their
    // recorded credentials rather than silently minting a divergent code.
    final storedCode = await SecureStorageService.getCloudBackupRecoveryCode();
    String? recoveryCode = storedCode;
    if (storedCode == null &&
        await _service.listBackups().then((l) => l.isNotEmpty)
            .catchError((_) => false)) {
      if (!mounted) return;
      recoveryCode = await _reuseOrGenerateCodeDialog();
      if (recoveryCode == null) return;
    }

    if (!mounted) return;
    final passphrase = await _passphraseSetupDialog();
    if (passphrase == null || !mounted) return;

    recoveryCode ??= await _recoveryCodeDialog();
    if (recoveryCode == null || !mounted) return;

    await SecureStorageService.setCloudBackupPassphrase(passphrase);
    await SecureStorageService.setCloudBackupRecoveryCode(recoveryCode);
    await CloudBackupService.grantConsent();
    await _refresh();
  }

  Future<bool> _showConsentDialog() async {
    var confirmed = false;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Enable Cloud Backup'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(consentText),
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: confirmed,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'I understand that Cloud Backup is optional, that my '
                    'passphrase or recovery code is the only way to restore '
                    'my backups, and that I am responsible for keeping it '
                    'safe.',
                    style: TextStyle(fontSize: 13),
                  ),
                  onChanged: (v) => setDialog(() => confirmed = v ?? false),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: confirmed
                  ? () => Navigator.pop(context, true)
                  : null,
              child: const Text('Enable'),
            ),
          ],
        ),
      ),
    );
    return result == true;
  }

  Future<String?> _passphraseSetupDialog() => showDialog<String>(
        context: context,
        builder: (_) => const _PassphraseSetupDialog(),
      );

  /// Generate + display the recovery code; the user must tick that they
  /// have recorded it before continuing. Never logged.
  Future<String?> _recoveryCodeDialog() async {
    final code = await BackupEnvelope.generateRecoveryCode();
    var confirmed = false;
    if (!mounted) return null;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Your Recovery Code'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Write this code down and keep it somewhere safe. It is '
                'shown once and is not stored by Bragmat — it is the only '
                'other way to restore your backups.',
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    code,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 15,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
              CheckboxListTile(
                value: confirmed,
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'I have written down my recovery code',
                  style: TextStyle(fontSize: 13),
                ),
                onChanged: (v) => setDialog(() => confirmed = v ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: confirmed
                  ? () => Navigator.pop(context, true)
                  : null,
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
    return accepted == true ? code : null;
  }

  /// Offered when remote backups exist but no recovery code is stored —
  /// never silently regenerate a divergent code.
  Future<String?> _reuseOrGenerateCodeDialog() async =>
      (await showDialog<_CredentialResult>(
        context: context,
        builder: (_) => _CredentialDialog(
          title: 'Existing Cloud Backups Found',
          description:
              'You already have cloud backups. To keep a single recovery '
              'code for all backups, enter the code you recorded when you '
              'set up Cloud Backup.',
          fieldLabel: 'Recovery code',
          confirmLabel: 'Use this code',
          // Explicit choice: a NEW code applies to future backups only —
          // existing backups keep their original code.
          extraActions: {
            'Generate new code': BackupEnvelope.generateRecoveryCode,
          },
        ),
      ))
          ?.value;

  // ── Backup ────────────────────────────────────────────────────────────

  Future<void> _backUpNow() async {
    final passphrase = await SecureStorageService.getCloudBackupPassphrase();
    if (passphrase == null) {
      _showError('Backup passphrase not found on this device. Disable '
          'and re-enable Cloud Backup to set credentials again.');
      return;
    }
    var recoveryCode =
        await SecureStorageService.getCloudBackupRecoveryCode();
    if (recoveryCode == null) {
      recoveryCode = await _missingRecoveryCodeDialog();
      if (recoveryCode == null) return;
      await SecureStorageService.setCloudBackupRecoveryCode(recoveryCode);
    }
    if (!mounted) return;

    final token = CloudBackupCancelToken();
    setState(() => _token = token);
    try {
      final result = await _service.uploadNow(
        passphrase: passphrase,
        recoveryCode: recoveryCode,
        cancellation: token,
        onProgress: (m) => setState(() => _busy = m),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Cloud backup uploaded and verified (${_formatSize(result.size)})')));
      await _refresh();
    } on CloudBackupCancelledException {
      _showError('Backup cancelled.');
    } on CloudQuotaExceededException {
      _showError(
          'Backup exceeds the cloud storage limit. Use Backup Data to '
          'create a local backup instead.');
    } catch (e) {
      _showError('Cloud backup failed: $e');
    } finally {
      if (mounted) setState(() { _busy = null; _token = null; });
    }
  }

  /// The stored code is missing (secure storage cleared). The user must
  /// consciously choose — never silently mint a divergent code.
  Future<String?> _missingRecoveryCodeDialog() async =>
      (await showDialog<_CredentialResult>(
        context: context,
        builder: (_) => _CredentialDialog(
          title: 'Recovery Code Needed',
          description:
              'Your saved recovery code is not available on this device. '
              'Enter the code you recorded at setup so all backups keep '
              'one credential — or generate a new code for future backups '
              'only (older backups will still need their original code).',
          fieldLabel: 'Recovery code',
          confirmLabel: 'Use this code',
          extraActions: {
            'Generate new code': BackupEnvelope.generateRecoveryCode,
          },
        ),
      ))
          ?.value;

  // ── Restore ───────────────────────────────────────────────────────────

  Future<void> _restore(RemoteBackupInfo backup) async {
    final cred = await showDialog<_CredentialResult>(
      context: context,
      builder: (_) => const _CredentialDialog(
        title: 'Restore Cloud Backup',
        warning:
            'This will REPLACE all fishing records and photos on this '
            'device with the backup contents. Create a local backup '
            'first if unsure.',
        fieldLabel: 'Backup passphrase',
        recoveryFieldLabel: 'Recovery code',
        confirmLabel: 'Restore',
      ),
    );
    if (cred == null || !mounted) return;
    final credential = cred.value;
    final useRecovery = cred.isRecovery;

    final token = CloudBackupCancelToken();
    setState(() => _token = token);
    try {
      final result = await _service.restoreFromCloud(
        remoteName: backup.name,
        passphrase: useRecovery ? null : credential,
        recoveryCode: useRecovery ? credential : null,
        confirmUnownedRestore: _confirmUnownedRestore,
        createSafetyBackup: _createSafetyBackup,
        cancellation: token,
        onProgress: (m) => setState(() => _busy = m),
      );
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Restore Complete'),
          content: Text('Restore completed successfully — '
              '${result.manifest.statistics.catches} catches, '
              '${result.manifest.statistics.trips} trips, '
              '${result.mediaFilesRestored} photos restored.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } on IncorrectSecretException {
      _showError('Incorrect passphrase or recovery code.');
    } on RestoreCancelledException {
      _showError('Restore cancelled — your existing data is unchanged.');
    } on CloudBackupCancelledException {
      _showError('Restore cancelled.');
    } on CloudIntegrityException {
      _showError(
          'The downloaded backup failed integrity checks and was not '
          'restored. Your existing data is unchanged.');
    } catch (e) {
      _showError('Restore failed: $e');
    } finally {
      if (mounted) setState(() { _busy = null; _token = null; });
    }
  }

  /// Shown when a cloud backup whose records aren't linked to an account
  /// would replace the account-owned data on this device — identical to
  /// the local-restore confirmation in Settings.
  Future<bool> _confirmUnownedRestore() async {
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Backup Is Not Linked to an Account'),
            content: const Text(
              'This backup is not linked to any account. Restoring it '
              'will replace the data currently linked to your account '
              'with unclaimed records.\n\n'
              '• A verified safety backup of your current data is '
              'created first.\n'
              '• The restored records stay unclaimed — you\'ll need to '
              'link them to your account explicitly afterwards.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Restore Anyway'),
              ),
            ],
          ),
        ) ??
        false;
  }

  /// Verified ZIP safety backup of the current data, created before an
  /// unowned cloud backup is allowed to replace it. Returns the backup's
  /// file name, or null when it could not be created (aborts restore).
  Future<String?> _createSafetyBackup() async {
    final dir = await getDownloadsDirectory();
    if (dir == null) return null;
    final backupPath =
        await ZipBackupService.createBackup(outputDirectory: dir.path);
    return path.basename(backupPath);
  }

  // ── Delete / disable ──────────────────────────────────────────────────

  Future<void> _deleteBackup(RemoteBackupInfo backup) async {
    final ok = await _confirm(
      title: 'Delete Cloud Backup',
      body:
          'Permanently delete ${_describeBackup(backup)}? This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (ok != true) return;
    try {
      await _service.deleteBackup(backup.name);
      await _refresh();
    } catch (e) {
      _showError('Delete failed: $e');
    }
  }

  Future<void> _deleteAll() async {
    final ok = await _confirm(
      title: 'Delete All Cloud Backups',
      body: 'Permanently delete ALL of your cloud backups? This cannot '
          'be undone — make sure you have a local backup if you still '
          'need one.',
      confirmLabel: 'Delete All',
    );
    if (ok != true) return;
    try {
      final n = await _service.deleteAllBackups();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted $n cloud backup(s)')));
      await _refresh();
    } catch (e) {
      _showError('Delete failed: $e');
    }
  }

  Future<void> _disable() async {
    var alsoDelete = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Disable Cloud Backup'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Cloud Backup will be turned off. Backups already stored '
                'online are kept unless you choose to delete them. Your '
                'local data is unaffected.',
              ),
              CheckboxListTile(
                value: alsoDelete,
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Also permanently delete all my cloud backups',
                  style: TextStyle(fontSize: 13, color: Colors.red),
                ),
                onChanged: (v) => setDialog(() => alsoDelete = v ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Disable'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final deleted = await _service.disable(deleteRemote: alsoDelete);
    // Stored credentials are removed; existing backups still decrypt
    // with the credentials the user recorded at setup.
    await SecureStorageService.clearCloudBackupCredentials();
    if (!mounted) return;
    if (alsoDelete && deleted < 0) {
      _showError('Cloud Backup disabled, but remote deletion failed. '
          'You can retry deletion from this screen.');
    }
    await _refresh();
  }

  Future<bool?> _confirm(
      {required String title,
      required String body,
      required String confirmLabel}) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ── Display helpers ───────────────────────────────────────────────────

  static final _namePattern =
      RegExp(r'^bragmat_backup_(\d{4}-\d{2}-\d{2})T(\d{2})-(\d{2})-(\d{2})');

  static String _describeBackup(RemoteBackupInfo b) {
    final m = _namePattern.firstMatch(b.name);
    if (m == null) return b.name;
    return 'backup from ${m[1]} ${m[2]}:${m[3]}:${m[4]}';
  }

  static String _formatSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '$bytes B';
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cloud Backup')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (!_enabled) _buildDisabled(),
                    if (_enabled) ..._buildEnabled(),
                  ],
                ),
                if (_busy != null)
                  Container(
                    color: Colors.black45,
                    child: Center(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CircularProgressIndicator(),
                              const SizedBox(height: 16),
                              Text(_busy!),
                              const SizedBox(height: 12),
                              TextButton(
                                onPressed: () => _token?.cancel(),
                                child: const Text('Cancel'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildDisabled() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.cloud_off),
              title: Text('Cloud Backup is off'),
              subtitle: Text(
                  'Your data stays on this device. Enabling is optional.'),
            ),
            FilledButton.icon(
              onPressed: _busy == null ? _enableFlow : null,
              icon: const Icon(Icons.cloud_upload),
              label: const Text('Enable Cloud Backup'),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildEnabled() {
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.cloud_done),
                title: Text('Cloud Backup is on'),
                subtitle: Text(
                    'Encrypted backups only — up to 3 verified copies '
                    'are kept.'),
              ),
              FilledButton.icon(
                onPressed: _busy == null ? _backUpNow : null,
                icon: const Icon(Icons.backup),
                label: const Text('Back Up Now'),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('Cloud Backups',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: _busy == null ? _refresh : null,
                  ),
                ],
              ),
              if (_backups.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('No cloud backups yet.'),
                )
              else
                for (final b in _backups)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.cloud),
                    title: Text(_describeBackup(b)),
                    subtitle: Text(_formatSize(b.size)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Restore this backup',
                          icon: const Icon(Icons.restore),
                          onPressed:
                              _busy == null ? () => _restore(b) : null,
                        ),
                        IconButton(
                          tooltip: 'Delete this backup',
                          icon: const Icon(Icons.delete_outline),
                          onPressed:
                              _busy == null ? () => _deleteBackup(b) : null,
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      Card(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.cloud_off),
              title: const Text('Disable Cloud Backup'),
              subtitle: const Text('Turn off; choose whether to also '
                  'delete stored backups'),
              onTap: _busy == null ? _disable : null,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text('Delete All Cloud Backups',
                  style: TextStyle(color: Colors.red)),
              subtitle: const Text(
                  'Permanently remove every cloud backup'),
              onTap: _busy == null ? _deleteAll : null,
            ),
          ],
        ),
      ),
    ];
  }
}

/// What a credential dialog produced: the entered/generated secret plus
/// whether it should be used as the recovery code (vs the passphrase).
class _CredentialResult {
  const _CredentialResult(this.value, {this.isRecovery = false});
  final String value;
  final bool isRecovery;
}

/// Single-field credential prompt. Owns its TextEditingController so it
/// is disposed with the dialog's own element — disposing a controller
/// in the caller after `showDialog` returns races the pop transition
/// (the TextField is still mounted while the route animates out).
class _CredentialDialog extends StatefulWidget {
  const _CredentialDialog({
    required this.title,
    this.description,
    this.warning,
    required this.fieldLabel,
    this.recoveryFieldLabel,
    this.confirmLabel = 'Continue',
    this.extraActions = const {},
  });

  final String title;
  final String? description;
  final String? warning;
  final String fieldLabel;

  /// Non-null → offer a passphrase/recovery-code toggle.
  final String? recoveryFieldLabel;
  final String confirmLabel;

  /// Extra action buttons: label → async factory that produces a value
  /// the dialog pops with (marked as a recovery code).
  final Map<String, Future<String?> Function()> extraActions;

  @override
  State<_CredentialDialog> createState() => _CredentialDialogState();
}

class _CredentialDialogState extends State<_CredentialDialog> {
  final _ctrl = TextEditingController();
  var _useRecovery = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isRecovery =
        widget.recoveryFieldLabel != null && _useRecovery;
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.warning != null)
            Text(widget.warning!,
                style: const TextStyle(color: Colors.red)),
          if (widget.description != null) Text(widget.description!),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            obscureText: !isRecovery,
            decoration: InputDecoration(
              labelText:
                  isRecovery ? widget.recoveryFieldLabel : widget.fieldLabel,
              border: const OutlineInputBorder(),
            ),
          ),
          if (widget.recoveryFieldLabel != null)
            TextButton(
              onPressed: () =>
                  setState(() => _useRecovery = !_useRecovery),
              child: Text(isRecovery
                  ? 'Use passphrase instead'
                  : 'Use recovery code instead'),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        for (final e in widget.extraActions.entries)
          TextButton(
            onPressed: () async {
              final v = await e.value();
              if (v != null && context.mounted) {
                Navigator.pop(
                    context, _CredentialResult(v, isRecovery: true));
              }
            },
            child: Text(e.key),
          ),
        FilledButton(
          onPressed: () {
            final v = _ctrl.text.trim();
            if (v.isNotEmpty) {
              Navigator.pop(
                  context, _CredentialResult(v, isRecovery: isRecovery));
            }
          },
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// Create + confirm a backup passphrase. Owns its controllers for the
/// same pop-transition reason as [_CredentialDialog].
class _PassphraseSetupDialog extends StatefulWidget {
  const _PassphraseSetupDialog();

  @override
  State<_PassphraseSetupDialog> createState() =>
      _PassphraseSetupDialogState();
}

class _PassphraseSetupDialogState extends State<_PassphraseSetupDialog> {
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create Backup Passphrase'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Choose a passphrase for encrypting your backups. It is '
            'required to restore them on another device.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passCtrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Passphrase',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _confirmCtrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Confirm passphrase',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final p = _passCtrl.text;
            if (p.length < 8) {
              setState(() =>
                  _error = 'Passphrase must be at least 8 characters');
              return;
            }
            if (p != _confirmCtrl.text) {
              setState(() => _error = 'Passphrases do not match');
              return;
            }
            Navigator.pop(context, p);
          },
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
