/// A single GPS-linked GhostWave field measurement.
///
/// RSSI on a delivery receipt is last-hop RSSI, not necessarily the remote
/// destination's receive strength. Never invent RSSI for a timeout.
enum CoverageOutcome { delivered, failed, pending }

class CoverageSample {
  const CoverageSample({
    required this.sessionId,
    required this.clientMessageId,
    required this.destinationNodeId,
    required this.latitude,
    required this.longitude,
    required this.recordedAt,
    required this.outcome,
    this.rssiDbm,
    this.snrDb,
    this.gpsAccuracyMeters,
  });

  final String sessionId;
  final int clientMessageId;
  final int destinationNodeId;
  final double latitude;
  final double longitude;
  final DateTime recordedAt;
  final CoverageOutcome outcome;
  final int? rssiDbm;
  final double? snrDb;
  final double? gpsAccuracyMeters;

  /// Signal classes apply only to delivered packets with measured RSSI.
  /// These initial thresholds are UI defaults, not calibrated link margins.
  String get mapClass {
    if (outcome == CoverageOutcome.failed) return 'failed';
    if (outcome == CoverageOutcome.pending) return 'pending';
    if (rssiDbm == null) return 'delivered-unmeasured';
    if (rssiDbm! >= -90) return 'strong';
    if (rssiDbm! >= -110) return 'fair';
    return 'weak';
  }

  Map<String, Object?> toJson() => {
    'sessionId': sessionId,
    'clientMessageId': clientMessageId,
    'destinationNodeId': destinationNodeId,
    'latitude': latitude,
    'longitude': longitude,
    'recordedAt': recordedAt.toUtc().toIso8601String(),
    'outcome': outcome.name,
    'rssiDbm': rssiDbm,
    'snrDb': snrDb,
    'gpsAccuracyMeters': gpsAccuracyMeters,
  };

  factory CoverageSample.fromJson(Map<String, dynamic> json) => CoverageSample(
    sessionId: json['sessionId'] as String,
    clientMessageId: json['clientMessageId'] as int,
    destinationNodeId: json['destinationNodeId'] as int,
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
    recordedAt: DateTime.parse(json['recordedAt'] as String),
    outcome: CoverageOutcome.values.byName(json['outcome'] as String),
    rssiDbm: json['rssiDbm'] as int?,
    snrDb: (json['snrDb'] as num?)?.toDouble(),
    gpsAccuracyMeters: (json['gpsAccuracyMeters'] as num?)?.toDouble(),
  );

  String toCsvRow() => [
    sessionId,
    clientMessageId,
    destinationNodeId,
    latitude,
    longitude,
    recordedAt.toUtc().toIso8601String(),
    outcome.name,
    rssiDbm ?? '',
    snrDb ?? '',
    gpsAccuracyMeters ?? '',
  ].join(',');
}

String coverageCsv(Iterable<CoverageSample> samples) => [
  'session_id,client_message_id,destination_node_id,latitude,longitude,recorded_at_utc,outcome,rssi_dbm,snr_db,gps_accuracy_m',
  ...samples.map((sample) => sample.toCsvRow()),
].join('\n');
