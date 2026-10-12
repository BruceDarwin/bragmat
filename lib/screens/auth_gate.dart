import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/supabase_config.dart';
import 'sign_in_screen.dart';

/// Routes between the app and auth screens based on [AuthService] status.
///
/// When Supabase is not configured (dev/test builds without credentials)
/// the gate is transparent and the app runs unauthenticated — beta builds
/// always ship configured.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.child});

  final Widget child;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    if (SupabaseConfig.isConfigured) {
      AuthService.instance.addListener(_onAuthChanged);
    }
  }

  @override
  void dispose() {
    if (SupabaseConfig.isConfigured) {
      AuthService.instance.removeListener(_onAuthChanged);
    }
    super.dispose();
  }

  void _onAuthChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    if (!SupabaseConfig.isConfigured) {
      return widget.child;
    }
    switch (AuthService.instance.status) {
      case AuthStatus.unknown:
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      case AuthStatus.signedOut:
        return const SignInScreen();
      case AuthStatus.awaitingApproval:
        return const AwaitingApprovalScreen();
      case AuthStatus.revoked:
        return const RevokedScreen();
      case AuthStatus.signedIn:
        return widget.child;
    }
  }
}

/// Signed in but the email is not (yet) on the beta allowlist.
class AwaitingApprovalScreen extends StatelessWidget {
  const AwaitingApprovalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _AuthMessageScreen(
      icon: Icons.hourglass_top,
      title: 'Awaiting Invitation',
      message:
          'Bragmat is currently in invitation-only beta. Your account '
          '(${AuthService.instance.email ?? 'unknown'}) has been created but '
          'is not yet approved for access.\n\nAsk the administrator to add '
          'your email to the beta tester list, then pull down or reopen the '
          'app.',
      actions: [
        ElevatedButton(
          onPressed: () => AuthService.instance
              .refresh(forceEntitlementCheck: true),
          child: const Text('Check Again'),
        ),
        TextButton(
          onPressed: () => AuthService.instance.signOut(),
          child: const Text('Use a Different Account'),
        ),
      ],
    );
  }
}

/// Previously approved account that has been revoked by an admin.
/// Local data is intentionally retained — only cloud identity is removed.
class RevokedScreen extends StatelessWidget {
  const RevokedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _AuthMessageScreen(
      icon: Icons.block,
      title: 'Access Removed',
      message:
          'Beta access for this account has been revoked. Your catches, '
          'trips and photos are still stored on this device.\n\n'
          'If you believe this is a mistake, contact the administrator.',
      actions: [
        ElevatedButton(
          onPressed: () => AuthService.instance.signOut(),
          child: const Text('Back to Sign In'),
        ),
      ],
    );
  }
}

class _AuthMessageScreen extends StatelessWidget {
  const _AuthMessageScreen({
    required this.icon,
    required this.title,
    required this.message,
    required this.actions,
  });

  final IconData icon;
  final String title;
  final String message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 64, color: Colors.blueGrey),
                const SizedBox(height: 24),
                Text(title,
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 16),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 32),
                ...actions.map(
                  (a) => Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: a,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
