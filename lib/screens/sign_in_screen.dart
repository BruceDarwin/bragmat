import 'package:flutter/material.dart';

import '../services/auth_service.dart';

/// Email/password sign-in for invited beta testers, with account creation
/// and password-reset request. Beta access itself is enforced server-side:
/// uninvited accounts land on the awaiting-approval screen.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;
  bool _isSignUp = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _busy = true);
    try {
      final auth = AuthService.instance;
      if (_isSignUp) {
        await auth.signUp(
          _emailController.text.trim(),
          _passwordController.text,
        );
      } else {
        await auth.signIn(
          _emailController.text.trim(),
          _passwordController.text,
        );
      }
      // The AuthGate reacts to the resulting status change.
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('not confirmed') || msg.contains('not_confirmed')) {
        _showMessage(
          'This email is not verified yet — check your inbox for the '
          'confirmation link, then sign in.',
        );
      } else {
        _showMessage(
          _isSignUp ? 'Sign up failed: $e' : 'Sign in failed: $e',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _showMessage('Enter your email address first');
      return;
    }
    setState(() => _busy = true);
    try {
      await AuthService.instance.requestPasswordReset(email);
      _showMessage(
        'If that email has an account, a reset link is on its way.',
      );
    } catch (e) {
      _showMessage('Could not send reset email: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.phishing,
                      size: 64, color: Theme.of(context).primaryColor),
                  const SizedBox(height: 16),
                  Text(
                    'Bragmat Beta',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Invitation-only beta — sign in with your invited email.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.length < 6)
                        ? 'Minimum 6 characters'
                        : null,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_isSignUp ? 'Create Account' : 'Sign In'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _isSignUp = !_isSignUp),
                    child: Text(
                      _isSignUp
                          ? 'Already have an account? Sign in'
                          : 'Invited? Create an account',
                    ),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _resetPassword,
                    child: const Text('Forgot password?'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
