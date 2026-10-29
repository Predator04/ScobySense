class KombuDevice {
  final String id;
  final String deviceId;
  final String? deviceName;
  final String? status;
  final String? f1Status;
  final double? f1Temp;
  final String? f1RemainingTime;
  final String? f2Status;
  final double? f2Temp;
  final String? f2RemainingTime;
  final String? temperatureUnit;
  final bool? wifiConnected;
  final String? firmwareVersion;
  final String? lastSeen;
  final String? iotThingArn;

  KombuDevice({
    required this.id,
    required this.deviceId,
    this.deviceName,
    this.status,
    this.f1Status,
    this.f1Temp,
    this.f1RemainingTime,
    this.f2Status,
    this.f2Temp,
    this.f2RemainingTime,
    this.temperatureUnit,
    this.wifiConnected,
    this.firmwareVersion,
    this.lastSeen,
    this.iotThingArn,
  });

  factory KombuDevice.fromJson(Map<String, dynamic> j) => KombuDevice(
        id: (j['id'] ?? j['deviceId'] ?? '').toString(),
        deviceId: (j['deviceId'] ?? '').toString(),
        deviceName: j['deviceName'] as String?,
        status: j['status'] as String?,
        f1Status: j['f1Status'] as String?,
        f1Temp: (j['f1Temp'] as num?)?.toDouble(),
        f1RemainingTime: j['f1RemainingTime'] as String?,
        f2Status: j['f2Status'] as String?,
        f2Temp: (j['f2Temp'] as num?)?.toDouble(),
        f2RemainingTime: j['f2RemainingTime'] as String?,
        temperatureUnit: j['temperatureUnit'] as String?,
        wifiConnected: j['wifiConnected'] as bool?,
        firmwareVersion: j['firmwareVersion'] as String?,
        lastSeen: j['lastSeen'] as String?,
        iotThingArn: j['iotThingArn'] as String?,
      );

  bool get f1On => (f1Status ?? '').toLowerCase() == 'on';
  bool get f2On => (f2Status ?? '').toLowerCase() == 'on';
}
