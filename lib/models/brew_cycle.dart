class BrewStage {
  final String id;
  final String? eventType;
  final String? side;
  final String? status;
  final String? timestamp;
  final String? expectedEndTime;
  final int? durationDays;
  final String? notes;

  BrewStage({
    required this.id,
    this.eventType,
    this.side,
    this.status,
    this.timestamp,
    this.expectedEndTime,
    this.durationDays,
    this.notes,
  });

  factory BrewStage.fromJson(Map<String, dynamic> j) => BrewStage(
        id: (j['id'] ?? '').toString(),
        eventType: j['eventType'] as String?,
        side: j['side'] as String?,
        status: j['status'] as String?,
        timestamp: j['timestamp'] as String?,
        expectedEndTime: j['expectedEndTime'] as String?,
        durationDays: (j['durationDays'] as num?)?.toInt(),
        notes: j['notes'] as String?,
      );

  BrewStage copyWith({String? notes}) => BrewStage(
        id: id,
        eventType: eventType,
        side: side,
        status: status,
        timestamp: timestamp,
        expectedEndTime: expectedEndTime,
        durationDays: durationDays,
        notes: notes ?? this.notes,
      );
}

class BrewBatch {
  final int? batchNumber;
  final bool isComplete;
  final BrewStage? f1;
  final BrewStage? f2;

  BrewBatch({
    this.batchNumber,
    required this.isComplete,
    this.f1,
    this.f2,
  });

  factory BrewBatch.fromJson(Map<String, dynamic> j) => BrewBatch(
        batchNumber: (j['batchNumber'] as num?)?.toInt(),
        isComplete: (j['isComplete'] as bool?) ?? false,
        f1: j['f1'] is Map
            ? BrewStage.fromJson((j['f1'] as Map).cast<String, dynamic>())
            : null,
        f2: j['f2'] is Map
            ? BrewStage.fromJson((j['f2'] as Map).cast<String, dynamic>())
            : null,
      );
}

class BrewCycleReport {
  final int total;
  final BrewStage? activeF1;
  final BrewStage? activeF2;
  final List<BrewBatch> batches;

  BrewCycleReport({
    required this.total,
    this.activeF1,
    this.activeF2,
    required this.batches,
  });

  factory BrewCycleReport.fromJson(Map<String, dynamic> j) {
    final list = (j['batches'] as List?) ?? const [];
    return BrewCycleReport(
      total: (j['total'] as num?)?.toInt() ?? 0,
      activeF1: j['activeF1'] is Map
          ? BrewStage.fromJson((j['activeF1'] as Map).cast<String, dynamic>())
          : null,
      activeF2: j['activeF2'] is Map
          ? BrewStage.fromJson((j['activeF2'] as Map).cast<String, dynamic>())
          : null,
      batches: list
          .map((e) => BrewBatch.fromJson(
              (e as Map).cast<String, dynamic>()))
          .toList(),
    );
  }
}
