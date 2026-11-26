import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/tokens.dart';
import '../../data/auth_repository.dart';
import '../../data/models/user.dart';
import '../../data/providers.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _creating = false;
  bool _showDemo = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final auth = ref.read(authControllerProvider.notifier);
    final email = _email.text.trim();
    if (!_creating) return _run(() => auth.signInWithPassword(email, _password.text));
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Enter your full name as it appears on your NCC records.');
      return;
    }
    await _run(() async {
      final signedIn = await auth.signUp(email, _password.text, _name.text.trim());
      if (!signedIn && mounted) {
        setState(() {
          _creating = false;
          _notice = 'Account created. Open the confirmation link we emailed to $email, then sign in.';
        });
      }
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = "Something went wrong. Check your connection and try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDemo = ref.watch(authRepositoryProvider).isDemo;
    final auth = ref.read(authControllerProvider.notifier);
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Space.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Wordmark(),
                  const SizedBox(height: Space.sm),
                  Text('Train. Prepare. Lead.',
                      style: t.titleMedium?.copyWith(color: c.onSurfaceVariant)),
                  const SizedBox(height: Space.xxl),
                  if (isDemo) ...[
                    Text('Demo mode', style: t.titleLarge),
                    const SizedBox(height: Space.xs),
                    Text('No backend is connected, so pick a role to explore with sample data.',
                        style: t.bodyMedium?.copyWith(color: c.onSurfaceVariant)),
                    const SizedBox(height: Space.lg),
                    for (final role in AppRole.values) ...[
                      _RoleButton(
                        role: role,
                        onPressed: _busy ? null : () => _run(() => auth.signInAs(role)),
                      ),
                      const SizedBox(height: Space.md),
                    ],
                  ] else ...[
                    Text(_creating ? 'Create your account' : 'Sign in', style: t.titleLarge),
                    const SizedBox(height: Space.lg),
                    if (_creating) ...[
                      TextField(
                        controller: _name,
                        decoration: const InputDecoration(labelText: 'Full name'),
                        textCapitalization: TextCapitalization.words,
                        autofillHints: const [AutofillHints.name],
                      ),
                      const SizedBox(height: Space.md),
                    ],
                    TextField(
                      controller: _email,
                      decoration: const InputDecoration(labelText: 'Email'),
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                    ),
                    const SizedBox(height: Space.md),
                    TextField(
                      controller: _password,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        helperText: _creating ? 'At least 8 characters' : null,
                      ),
                      obscureText: true,
                      autofillHints: [_creating ? AutofillHints.newPassword : AutofillHints.password],
                      onSubmitted: (_) => _busy ? null : _submit(),
                    ),
                    const SizedBox(height: Space.lg),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: Text(_creating ? 'Create account' : 'Sign in'),
                    ),
                    const SizedBox(height: Space.sm),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _creating = !_creating;
                                _error = null;
                              }),
                      child: Text(_creating ? 'I already have an account' : 'New here? Create an account'),
                    ),
                  ],
                  if (!isDemo) ...[
                    const SizedBox(height: Space.lg),
                    const Divider(),
                    TextButton.icon(
                      onPressed: () => setState(() => _showDemo = !_showDemo),
                      icon: Icon(_showDemo ? Icons.expand_less : Icons.visibility_outlined),
                      label: const Text('Explore with sample data'),
                    ),
                    if (_showDemo)
                      for (final role in AppRole.values) ...[
                        _RoleButton(
                          role: role,
                          onPressed: () => ref.read(authControllerProvider.notifier).exploreDemo(role),
                        ),
                        const SizedBox(height: Space.md),
                      ],
                  ],
                  if (_notice != null) ...[
                    const SizedBox(height: Space.md),
                    Text(_notice!, style: t.bodyMedium?.copyWith(color: c.primary)),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: Space.md),
                    Text(_error!, style: t.bodyMedium?.copyWith(color: c.error)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Row(children: [
      Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(color: c.primary, borderRadius: BorderRadius.circular(Radii.md)),
        child: Icon(Icons.local_fire_department, color: c.onPrimary, size: 28),
      ),
      const SizedBox(width: Space.md),
      Text('PHOENIX', style: Theme.of(context).textTheme.displaySmall?.copyWith(letterSpacing: 2)),
    ]);
  }
}

class _RoleButton extends StatelessWidget {
  const _RoleButton({required this.role, required this.onPressed});

  final AppRole role;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final (icon, blurb) = switch (role) {
      AppRole.cadet => (Icons.person_outline, 'Study, take mocks, keep your training diary'),
      AppRole.seniorCadet => (Icons.military_tech_outlined, 'Everything a cadet has, plus hosting tests'),
      AppRole.ano => (Icons.shield_outlined, 'Run the unit: roster, calendar, tests, knowledge base'),
    };
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.all(Space.lg),
        alignment: Alignment.centerLeft,
      ),
      child: Row(children: [
        Icon(icon),
        const SizedBox(width: Space.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Continue as ${role.label}'),
            Text(blurb,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w400)),
          ]),
        ),
        const Icon(Icons.arrow_forward, size: 18),
      ]),
    );
  }
}
