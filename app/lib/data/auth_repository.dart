import 'package:supabase_flutter/supabase_flutter.dart';

import 'demo/demo_data.dart';
import 'models/user.dart';

abstract interface class AuthRepository {
  bool get isDemo;
  Future<AppUser?> restoreSession();
  Future<AppUser> signInAs(AppRole role);
  Future<AppUser> signInWithPassword({required String email, required String password});
  Future<void> signOut();
}

/// Demo mode: pick a role, get a sample user. Nothing leaves the device.
class DemoAuthRepository implements AuthRepository {
  @override
  bool get isDemo => true;

  @override
  Future<AppUser?> restoreSession() async => null;

  @override
  Future<AppUser> signInAs(AppRole role) async => DemoData.forRole(role);

  @override
  Future<AppUser> signInWithPassword({required String email, required String password}) =>
      throw UnsupportedError('Password sign-in needs a Supabase backend.');

  @override
  Future<void> signOut() async {}
}

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);

  final SupabaseClient _client;

  @override
  bool get isDemo => false;

  @override
  Future<AppUser?> restoreSession() async {
    final user = _client.auth.currentUser;
    return user == null ? null : _loadProfile(user.id);
  }

  @override
  Future<AppUser> signInAs(AppRole role) =>
      throw UnsupportedError('Role picking is only available in demo mode.');

  @override
  Future<AppUser> signInWithPassword({required String email, required String password}) async {
    final res = await _client.auth.signInWithPassword(email: email, password: password);
    return _loadProfile(res.user!.id);
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  Future<AppUser> _loadProfile(String id) async {
    final row = await _client
        .from('profiles')
        .select('id, full_name, role, rank, regimental_no, wing, division, training_year, units(name)')
        .eq('id', id)
        .single();
    return AppUser(
      id: row['id'] as String,
      fullName: row['full_name'] as String,
      role: _role(row['role'] as String),
      rank: row['rank'] as String?,
      regimentalNo: row['regimental_no'] as String?,
      wing: _byName(Wing.values, row['wing'] as String?),
      division: _byName(Division.values, row['division'] as String?),
      trainingYear: row['training_year'] as int?,
      unitName: (row['units'] as Map<String, dynamic>?)?['name'] as String?,
    );
  }

  static AppRole _role(String v) => switch (v) {
        'ano' => AppRole.ano,
        'senior_cadet' => AppRole.seniorCadet,
        _ => AppRole.cadet,
      };

  static T? _byName<T extends Enum>(List<T> values, String? name) {
    if (name == null) return null;
    for (final v in values) {
      if (v.name == name) return v;
    }
    return null;
  }
}
