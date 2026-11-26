import 'dart:math' as math;

/// Rules for sitting a certificate exam. Kept as data so a change in the
/// rules needs a content update, not a code change.
class EligibilityRule {
  const EligibilityRule({
    required this.certificate,
    this.minAttendance = 0.75,
    this.campRequired = true,
    this.prerequisite,
  });

  final String certificate;

  /// Share of training periods a cadet must attend, from 0 to 1.
  final double minAttendance;
  final bool campRequired;

  /// Certificate the cadet must already hold, if any.
  final String? prerequisite;
}

const bCertificateRule = EligibilityRule(certificate: 'B');
const cCertificateRule = EligibilityRule(certificate: 'C', prerequisite: 'B');

class EligibilityStatus {
  const EligibilityStatus({
    required this.attendance,
    required this.periodsNeeded,
    required this.campDone,
    required this.prerequisiteMet,
    required this.rule,
  });

  final EligibilityRule rule;

  /// Current attendance share, from 0 to 1.
  final double attendance;

  /// Consecutive periods the cadet must still attend to reach the minimum.
  final int periodsNeeded;
  final bool campDone;
  final bool prerequisiteMet;

  bool get attendanceMet => periodsNeeded == 0;

  bool get isEligible =>
      attendanceMet && (campDone || !rule.campRequired) && prerequisiteMet;

  /// What is still missing, in plain words.
  List<String> get blockers => [
        if (!attendanceMet) 'Attend $periodsNeeded more training period${periodsNeeded == 1 ? '' : 's'}',
        if (rule.campRequired && !campDone) 'Attend an Annual Training Camp',
        if (!prerequisiteMet) 'Hold the ${rule.prerequisite} certificate',
      ];
}

EligibilityStatus checkEligibility({
  required EligibilityRule rule,
  required int periodsAttended,
  required int periodsHeld,
  required bool campDone,
  Set<String> certificatesHeld = const {},
}) {
  assert(periodsAttended >= 0 && periodsHeld >= 0 && periodsAttended <= periodsHeld);
  final attendance = periodsHeld == 0 ? 0.0 : periodsAttended / periodsHeld;

  // Smallest x with (attended + x) / (held + x) >= min, assuming every
  // future period is attended.
  final min = rule.minAttendance;
  final raw = (min * periodsHeld - periodsAttended) / (1 - min);
  // Small epsilon so float noise (e.g. 3.0000000001) does not add a period.
  final needed = math.max(0, (raw - 1e-9).ceil());

  return EligibilityStatus(
    rule: rule,
    attendance: attendance,
    periodsNeeded: periodsHeld == 0 ? 0 : needed,
    campDone: campDone,
    prerequisiteMet: rule.prerequisite == null || certificatesHeld.contains(rule.prerequisite),
  );
}
