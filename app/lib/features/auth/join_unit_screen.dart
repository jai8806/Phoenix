import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/tokens.dart';
import '../../data/auth_repository.dart';
import '../../data/providers.dart';

/// Shown to signed-in users who don't belong to a unit yet.
class JoinUnitScreen extends ConsumerStatefulWidget {
  const JoinUnitScreen({super.key});

  @override
  ConsumerState<JoinUnitScreen> createState() => _JoinUnitScreenState();
}

class _JoinUnitScreenState extends ConsumerState<JoinUnitScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final code = _code.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Enter the unit code your ANO shared.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).joinUnit(code);
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Something went wrong. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider);
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Space.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Icon(Icons.groups_outlined, size: 40, color: c.primary),
                const SizedBox(height: Space.md),
                Text('Join your unit', style: t.headlineSmall),
                const SizedBox(height: Space.xs),
                Text(
                  'Welcome${user == null ? '' : ', ${user.firstName}'}. Enter the 8-character code your ANO '
                  'or senior cadet shared to see your unit\'s calendar, tests and study material.',
                  style: t.bodyMedium?.copyWith(color: c.onSurfaceVariant),
                ),
                const SizedBox(height: Space.xl),
                TextField(
                  controller: _code,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')), LengthLimitingTextInputFormatter(12)],
                  decoration: InputDecoration(labelText: 'Unit code', errorText: _error),
                  onSubmitted: (_) => _busy ? null : _join(),
                ),
                const SizedBox(height: Space.lg),
                FilledButton(onPressed: _busy ? null : _join, child: const Text('Join unit')),
                const SizedBox(height: Space.sm),
                TextButton(
                  onPressed: _busy ? null : () => ref.read(authControllerProvider.notifier).signOut(),
                  child: const Text('Sign out'),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
