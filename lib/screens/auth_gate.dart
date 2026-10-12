import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/supabase_config.dart';
import 'sign_in_screen.dart';
import 'reset_password_screen.dart';

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
    final auth = AuthService.instance;
    // A recovery-session deep link takes precedence over everything else:
    // the user must set a new password before entering the app.
    if (auth.passwordRecoveryPending) {
      return const ResetPasswordScreen();
    }
    switch (auth.status) {
      case AuthStatus.unknown:
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      case AuthStatus.signedOut:
        return const SignInScreen();
      case AuthStatus.emailVerificationPending:
        return const EmailVerificationScreen();
      case AuthStatus.awaitingApproval:
        return const AwaitingApprovalScreen();
      case AuthStatus.revoked:
        return const RevokedScreen();
      case AuthStatus.signedIn:
        return widget.child;
    }
  }
}

/// Account created but email confirmation is still pending — Supabase
/// email confirmation is enabled, so no session exists until the user
/// taps the link in their inbox.
class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({super.key});

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  bool _resending = false;

  Future<void> _resend() async {
    if (_resending || AuthService.instance.pendingEmail == null) {
      return;
    }
    setState(() => _resending = true);
    try {
      await AuthService.instance.resendConfirmation();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Confirmation email re-sent')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not resend: $e')),
      );
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthMessageScreen(
      icon: Icons.mark_email_unread,
      title: 'Verify Your Email',
      message:
          'We sent a confirmation link to '
          '${AuthService.instance.pendingEmail ?? 'your email address'}.\n\n'
          'Tap the link to verify your account, then return here and '
          'sign in. The app will open automatically when you tap it.',
      actions: [
        ElevatedButton(
          onPressed: _resending ? null : _resend,
          child: Text(_resending ? 'Sending…' : 'Resend Email'),
        ),
        TextButton(
          onPressed: () => AuthService.instance.signOut(),
          child: const Text('Back to Sign In'),
        ),
      ],
    );
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
