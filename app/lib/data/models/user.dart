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
  });

  final String id;
  final String fullName;
  final AppRole role;
  final String? rank;
  final String? regimentalNo;
  final Wing? wing;
  final Division? division;
  final int? trainingYear;
  final String? unitName;

  String get firstName => fullName.split(' ').first;

  String get displayName => rank == null ? fullName : '$rank $fullName';
}
