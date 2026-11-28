import '../../domain/eligibility.dart';
import 'user.dart';

/// One cadet as the unit sees them: identity plus the records that drive
/// eligibility and readiness.
class RosterCadet {
  const RosterCadet({
    required this.user,
    required this.periodsAttended,
    required this.periodsHeld,
    required this.campDone,
    this.certificatesHeld = const {},
    this.mockAverage,
  });

  final AppUser user;
  final int periodsAttended;
  final int periodsHeld;
  final bool campDone;
  final Set<String> certificatesHeld;

  /// Average mock test percentage, if the cadet has taken any.
  final double? mockAverage;

  double get attendance => periodsHeld == 0 ? 0 : periodsAttended / periodsHeld;

  /// Senior cadets in their third year aim for C; everyone else for B.
  EligibilityRule get targetRule =>
      (user.trainingYear ?? 1) >= 3 ? cCertificateRule : bCertificateRule;

  EligibilityStatus get eligibility => checkEligibility(
        rule: targetRule,
        periodsAttended: periodsAttended,
        periodsHeld: periodsHeld,
        campDone: campDone,
        certificatesHeld: certificatesHeld,
      );
}
