enum AppRole {
  cadet('Cadet'),
  seniorCadet('Senior Cadet'),
  ano('ANO');

  const AppRole(this.label);
  final String label;

  /// Senior cadets (SUO/JUO) and the ANO can run the Command Center.
  bool get canAdminister => this != AppRole.cadet;

  /// Only the ANO can change roles and verify records.
  bool get isAno => this == AppRole.ano;
}

/// Cadet appointments. CSUO and SUO command the unit with the ANO; JUO,
/// CSM and CQMS assist them.
enum Appointment {
  csuo('CSUO', 'Company Senior Under Officer'),
  suo('SUO', 'Senior Under Officer'),
  juo('JUO', 'Junior Under Officer'),
  csm('CSM', 'Company Sergeant Major'),
  cqms('CQMS', 'Company Quarter Master Sergeant');

  const Appointment(this.label, this.fullName);
  final String label;
  final String fullName;

  /// Full authority with the ANO: roster, publishing mocks, anonymous queries.
  bool get isCommand => this == Appointment.csuo || this == Appointment.suo;
}

enum Wing {
  army('Army'),
  navy('Navy'),
  air('Air Force'),
  rvc('RVC');

  const Wing(this.label);
  final String label;
}

enum Division {
  jd('Junior Division'),
  jw('Junior Wing'),
  sd('Senior Division'),
  sw('Senior Wing');

  const Division(this.label);
  final String label;

  bool get isSenior => this == Division.sd || this == Division.sw;
}

class AppUser {
  const AppUser({
    required this.id,
    required this.fullName,
    required this.role,
    this.rank,
    this.regimentalNo,
    this.wing,
    this.division,
    this.trainingYear,
    this.unitName,
    this.unitId,
    this.isSample = false,
    this.appointment,
  });

  final String id;

  /// Only senior cadets hold one.
  final Appointment? appointment;
  final String fullName;
  final AppRole role;
  final String? rank;
  final String? regimentalNo;
  final Wing? wing;
  final Division? division;
  final int? trainingYear;
  final String? unitName;
  final String? unitId;

  /// Sample users (demo mode, or "Explore with sample data") never touch the backend.
  final bool isSample;

  String get firstName => fullName.split(' ').first;

  String get displayName => rank == null ? fullName : '$rank $fullName';

  /// New accounts have no unit until they join with the code their ANO shares.
  bool get hasUnit => unitName != null;

  /// ANO, CSUO or SUO: manages the roster and publishes mocks.
  bool get isCommand => role.isAno || (role == AppRole.seniorCadet && (appointment?.isCommand ?? false));

  /// Can read anonymous queries. [toAllSeniors]: the asker let JUO, CSM and
  /// CQMS see it too. Never the ANO.
  bool canHandleQueries({bool toAllSeniors = false}) =>
      role == AppRole.seniorCadet && appointment != null && (appointment!.isCommand || toAllSeniors);

  /// "CSUO" / "ANO" / "Senior cadet" / "Cadet".
  String get position => role.isAno ? 'ANO' : appointment?.label ?? role.label;

  /// A copy with the fields a member edits on their own profile, or an ANO
  /// edits for them. Pass the current value to keep it.
  AppUser copyWith({
    String? fullName,
    AppRole? role,
    String? Function()? rank,
    String? Function()? regimentalNo,
    Wing? Function()? wing,
    Division? Function()? division,
    int? Function()? trainingYear,
    Appointment? Function()? appointment,
  }) =>
      AppUser(
        id: id,
        fullName: fullName ?? this.fullName,
        role: role ?? this.role,
        rank: rank == null ? this.rank : rank(),
        regimentalNo: regimentalNo == null ? this.regimentalNo : regimentalNo(),
        wing: wing == null ? this.wing : wing(),
        division: division == null ? this.division : division(),
        trainingYear: trainingYear == null ? this.trainingYear : trainingYear(),
        unitName: unitName,
        unitId: unitId,
        isSample: isSample,
        appointment: appointment == null ? this.appointment : appointment(),
      );
}

/// Ranks cadets hold, lowest first, for pickers.
const cadetRanks = ['CDT', 'LCPL', 'CPL', 'SGT', 'CQMS', 'CSM', 'JUO', 'SUO', 'CSUO'];

/// Database names for roles.
String roleToDb(AppRole r) => switch (r) {
      AppRole.ano => 'ano',
      AppRole.seniorCadet => 'senior_cadet',
      AppRole.cadet => 'cadet',
    };

AppRole roleFromDb(String? v) => switch (v) {
      'ano' => AppRole.ano,
      'senior_cadet' => AppRole.seniorCadet,
      _ => AppRole.cadet,
    };

T? enumByName<T extends Enum>(List<T> values, String? name) {
  if (name == null) return null;
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}

/// A `profiles` row (optionally with `units(name)`) as an [AppUser].
AppUser appUserFromRow(Map<String, dynamic> row) => AppUser(
      id: row['id'] as String,
      fullName: row['full_name'] as String,
      role: roleFromDb(row['role'] as String?),
      rank: row['rank'] as String?,
      regimentalNo: row['regimental_no'] as String?,
      wing: enumByName(Wing.values, row['wing'] as String?),
      division: enumByName(Division.values, row['division'] as String?),
      trainingYear: (row['training_year'] as num?)?.toInt(),
      unitName: (row['units'] as Map<String, dynamic>?)?['name'] as String?,
      unitId: row['unit_id'] as String?,
      appointment: enumByName(Appointment.values, row['appointment'] as String?),
    );

/// The editable profile fields as a `profiles` update.
Map<String, dynamic> profileToRow(AppUser u) => {
      'full_name': u.fullName,
      'rank': u.rank,
      'regimental_no': u.regimentalNo,
      'wing': u.wing?.name,
      'division': u.division?.name,
      'training_year': u.trainingYear,
    };
