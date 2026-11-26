import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'data/auth_repository.dart';
import 'data/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  final AuthRepository auth;
  if (Env.hasBackend) {
    await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseKey);
    auth = SupabaseAuthRepository(Supabase.instance.client);
  } else {
    auth = DemoAuthRepository();
  }
  final initialUser = await auth.restoreSession();

  runApp(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      authRepositoryProvider.overrideWithValue(auth),
      initialUserProvider.overrideWithValue(initialUser),
    ],
    child: const PhoenixApp(),
  ));
}
