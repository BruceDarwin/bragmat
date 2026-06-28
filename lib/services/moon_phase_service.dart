import 'dart:math';

class MoonPhaseService {
  static final MoonPhaseService _instance = MoonPhaseService._internal();
  factory MoonPhaseService() => _instance;
  MoonPhaseService._internal();

  /// Calculate moon phase for a given date and optional location
  /// Returns a value between 0 and 1, where:
  /// 0 = New Moon
  /// 0.25 = First Quarter
  /// 0.5 = Full Moon
  /// 0.75 = Last Quarter
  double calculateMoonPhase(DateTime date, {double? latitude, double? longitude}) {
    // Location doesn't significantly affect moon phase calculation
    // but we accept it for API consistency and future enhancements
    
    // Use a simplified algorithm based on the known new moon date
    // Reference: January 6, 2000 was a new moon
    final referenceNewMoon = DateTime.utc(2000, 1, 6, 12, 24);
    
    // Calculate days since reference
    final daysSinceReference = date.difference(referenceNewMoon).inDays.toDouble();
    
    // Synodic month is approximately 29.53058867 days
    final synodicMonth = 29.53058867;
    
    // Calculate phase (0 to 1)
    double phase = (daysSinceReference % synodicMonth) / synodicMonth;
    
    // Normalize to 0-1 range
    if (phase < 0) phase += 1;
    
    return phase;
  }

  /// Get moon phase name from phase value
  String getMoonPhaseName(double phase) {
    if (phase < 0.03 || phase > 0.97) return 'New Moon';
    if (phase < 0.22) return 'Waxing Crescent';
    if (phase < 0.28) return 'First Quarter';
    if (phase < 0.47) return 'Waxing Gibbous';
    if (phase < 0.53) return 'Full Moon';
    if (phase < 0.72) return 'Waning Gibbous';
    if (phase < 0.78) return 'Last Quarter';
    return 'Waning Crescent';
  }

  /// Calculate moon illumination percentage (0-100)
  double calculateMoonIllumination(double phase) {
    // Illumination follows a sinusoidal pattern
    // 0% at new moon, 100% at full moon
    return (1 - cos(phase * 2 * pi)) / 2 * 100;
  }

  /// Get moon phase emoji for display
  String getMoonPhaseEmoji(double phase) {
    if (phase < 0.03 || phase > 0.97) return '🌑';
    if (phase < 0.22) return '🌒';
    if (phase < 0.28) return '🌓';
    if (phase < 0.47) return '🌔';
    if (phase < 0.53) return '🌕';
    if (phase < 0.72) return '🌖';
    if (phase < 0.78) return '🌗';
    return '🌘';
  }

  /// Get complete moon phase information
  MoonPhaseInfo getMoonPhaseInfo(DateTime date, {double? latitude, double? longitude}) {
    final phase = calculateMoonPhase(date, latitude: latitude, longitude: longitude);
    return MoonPhaseInfo(
      phase: phase,
      phaseName: getMoonPhaseName(phase),
      illumination: calculateMoonIllumination(phase),
      emoji: getMoonPhaseEmoji(phase),
    );
  }
}

class MoonPhaseInfo {
  final double phase;
  final String phaseName;
  final double illumination;
  final String emoji;

  MoonPhaseInfo({
    required this.phase,
    required this.phaseName,
    required this.illumination,
    required this.emoji,
  });

  @override
  String toString() {
    return '$emoji $phaseName (${illumination.toStringAsFixed(1)}% illuminated)';
  }
}
