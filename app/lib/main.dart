import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'data/auth_repository.dart';
import 'data/models/user.dart';
import 'data/providers.dart';
import 'data/unit_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  final AuthRepository auth;
  UnitRepository Function(AppUser)? unitRepository;
  if (Env.hasBackend) {
    await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseKey);
    final client = Supabase.instance.client;
    auth = SupabaseAuthRepository(client);
    unitRepository = (user) => SupabaseUnitRepository(client, user);
  } else {
    auth = DemoAuthRepository();
  }
  final initialUser = await auth.restoreSession();

  runApp(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      authRepositoryProvider.overrideWithValue(auth),
      initialUserProvider.overrideWithValue(initialUser),
      unitRepositoryFactoryProvider.overrideWithValue(unitRepository),
    ],
    child: const PhoenixApp(),
  ));
}
