import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../services/auth_service.dart';
import '../services/ownership_service.dart';
import '../services/zip_backup_service.dart';

/// Explicit ownership-claim wizard (Stage 4B / pre-beta hardening).
///
/// Links all existing unowned local data to the signed-in account.
/// A fresh, verified ZIP backup is created first — the claim never
/// runs without it. The operation is transactional and idempotent;
/// it cannot be undone in this stage (no ownership transfer).
///
/// The claim button stays disabled until the user types their own
/// account email — confirmation can't prove ownership, but it makes
/// the act deliberate and attributable; the email is recorded in the
/// `local_account` audit data.
///
/// [blocking] mode is used by the ownership-resolution gate when an
/// unclaimed database holds records: there is no "Not Now" — the only
/// ways out are to claim the data or sign out.
class ClaimDataScreen extends StatefulWidget {
  const ClaimDataScreen({super.key, this.blocking = false});

  final bool blocking;

  @override
  State<ClaimDataScreen> createState() => _ClaimDataScreenState();
}

class _ClaimDataScreenState extends State<ClaimDataScreen> {
  final _confirmEmailController = TextEditingController();
  bool _busy = false;
  String _status = '';
  ClaimResult? _result;
  String? _error;

  @override
  void dispose() {
    _confirmEmailController.dispose();
    super.dispose();
  }

  bool get _canClaim {
    final accountEmail = AuthService.instance.email;
    if (accountEmail == null) return false;
    return _confirmEmailController.text.trim().toLowerCase() ==
        accountEmail.toLowerCase();
  }

  Future<void> _claim() async {
    final userId = AuthService.instance.userId;
    if (userId == null) {
      setState(() => _error = 'You must be signed in to claim data.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Creating backup…';
    });
    try {
      final dir = await getDownloadsDirectory();
      if (dir == null) {
        throw StateError('Could not access the downloads directory');
      }
      final backupPath = await ZipBackupService.createBackup(
        outputDirectory: dir.path,
        onProgress: (s) => setState(() => _status = s),
      );
      setState(() => _status = 'Claiming data…');
      final result = await OwnershipService.claim(
        userId: userId,
        backupName: path.basename(backupPath),
        claimantEmail: AuthService.instance.email,
      );
      if (!mounted) return;
      setState(() => _result = result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.blocking
          ? null
          : AppBar(title: const Text('Link Data to Account')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _result != null ? _success() : _prompt(),
        ),
      ),
    );
  }

  Widget _prompt() {
    final email = AuthService.instance.email ?? 'your account email';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.link, size: 64, color: Colors.blueGrey),
        const SizedBox(height: 24),
        Text(
            widget.blocking
                ? 'This device has unclaimed fishing data'
                : 'Link this device\'s data to your account',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        Text(
          widget.blocking
              ? 'The catches, trips, photos and other records on this '
                  'device are not linked to any account. To open them, '
                  'link them to your account ($email) — or sign out if '
                  'this isn\'t your data.\n\n'
                  '• A fresh ZIP backup is created first (required).\n'
                  '• Linking binds the data to your account permanently.\n'
                  '• This cannot be undone in the current version.'
              : 'This will assign all catches, trips, photos, spots, tackle '
                  'and achievements on this device to your account '
                  'permanently.\n\n'
                  '• A fresh ZIP backup is created first (required).\n'
                  '• Afterwards, other accounts cannot see this data here.\n'
                  '• This cannot be undone in the current version.',
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _confirmEmailController,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: 'Type $email to confirm',
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        if (_status.isNotEmpty && _busy) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 12),
          Text(_status, textAlign: TextAlign.center),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_error!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center),
          ),
        const Spacer(),
        ElevatedButton(
          onPressed: _busy || !_canClaim ? null : _claim,
          child: Text(_busy ? 'Working…' : 'Create Backup & Link Data'),
        ),
        if (widget.blocking)
          TextButton(
            onPressed:
                _busy ? null : () => AuthService.instance.signOut(),
            child: const Text('Not my data — Sign Out'),
          )
        else
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Not Now'),
          ),
      ],
    );
  }

  Widget _success() {
    final r = _result!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.check_circle_outline,
            size: 64, color: Colors.green),
        const SizedBox(height: 24),
        Text('Data linked to your account',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        Text('${r.rowsClaimed} records claimed.'),
        const SizedBox(height: 8),
        Text('Backup saved: ${r.backupName}'),
        if (widget.blocking) ...[
          const SizedBox(height: 12),
          const Text('Opening your data…',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.blueGrey)),
        ],
        const Spacer(),
        if (!widget.blocking)
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Done'),
          ),
      ],
    );
  }
}
