

class RepCard {
  final int repNumber;
  final int formScore;
  final double? peakVelocity;
  final double? avgVelocity;
  final int? romMm;
  final List<String> flags;
  final DateTime timestamp;

  RepCard({
    required this.repNumber,
    required this.formScore,
    this.peakVelocity,
    this.avgVelocity,
    this.romMm,
    this.flags = const [],
    required this.timestamp,
  });

  String get formGrade {
    if (formScore >= 90) return 'A';
    if (formScore >= 80) return 'B';
    if (formScore >= 70) return 'C';
    if (formScore >= 60) return 'D';
    return 'F';
  }

  Map<String, dynamic> toMap() => {
    'repNumber': repNumber,
    'formScore': formScore,
    'peakVelocity': peakVelocity,
    'avgVelocity': avgVelocity,
    'romMm': romMm,
    'flags': flags,
    'timestamp': timestamp.toIso8601String(),
  };

  factory RepCard.fromMap(Map<String, dynamic> map) => RepCard(
    repNumber: (map['repNumber'] as num).toInt(),
    formScore: (map['formScore'] as num).toInt(),
    peakVelocity: (map['peakVelocity'] as num?)?.toDouble(),
    avgVelocity: (map['avgVelocity'] as num?)?.toDouble(),
    romMm: (map['romMm'] as num?)?.toInt(),
    flags: List<String>.from(map['flags'] as List? ?? []),
    timestamp: DateTime.parse(map['timestamp'] as String),
  );
}
