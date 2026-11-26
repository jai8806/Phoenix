import 'package:supabase_flutter/supabase_flutter.dart';

import 'demo/demo_data.dart';
import 'models/user.dart';

abstract interface class AuthRepository {
  bool get isDemo;
  Future<AppUser?> restoreSession();
  Future<AppUser> signInAs(AppRole role);
  Future<AppUser> signInWithPassword({required String email, required String password});

  /// Creates an account. Returns the signed-in user, or null when the project
  /// requires the email address to be confirmed first.
  Future<AppUser?> signUp({required String email, required String password, required String fullName});

  /// Joins the unit whose code the ANO shared, and returns the updated user.
  Future<AppUser> joinUnit(String code);
  Future<void> signOut();
}

/// Thrown with a message that is safe to show to the user.
class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;

  @override
  String toString() => message;
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
  Future<AppUser?> signUp({required String email, required String password, required String fullName}) =>
      throw UnsupportedError('Accounts need a Supabase backend.');

  @override
  Future<AppUser> joinUnit(String code) => throw UnsupportedError('Units need a Supabase backend.');

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
    try {
      final res = await _client.auth.signInWithPassword(email: email, password: password);
      return await _loadProfile(res.user!.id);
    } on AuthException catch (e) {
      throw AuthFailure(e.code == 'email_not_confirmed'
          ? 'Confirm your email address first: open the link we sent you, then sign in.'
          : "We couldn't sign you in. Check your email and password, then try again.");
    }
  }

  @override
  Future<AppUser?> signUp({required String email, required String password, required String fullName}) async {
    try {
      final res = await _client.auth.signUp(email: email, password: password, data: {'full_name': fullName});
      if (res.session == null || res.user == null) return null; // email confirmation pending
      return await _loadProfile(res.user!.id);
    } on AuthException catch (e) {
      throw AuthFailure(switch (e.code) {
        'user_already_exists' || 'email_exists' => 'An account with this email already exists. Sign in instead.',
        'weak_password' => 'Choose a longer password: at least 8 characters, mixing letters and numbers.',
        _ => "We couldn't create your account. Check your details and try again.",
      });
    }
  }

  @override
  Future<AppUser> joinUnit(String code) async {
    try {
      await _client.rpc('join_unit', params: {'code': code});
    } on PostgrestException catch (e) {
      throw AuthFailure(e.message.contains('Unknown unit code')
          ? "That code doesn't match a unit. Check it with your ANO and try again."
          : e.message.contains('already belong')
              ? 'You already belong to a unit. Ask your ANO if you need to move.'
              : "We couldn't join the unit just now. Try again in a moment.");
    }
    return _loadProfile(_client.auth.currentUser!.id);
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
