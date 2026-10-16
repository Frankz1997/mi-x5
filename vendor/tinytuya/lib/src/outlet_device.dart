/// Outlet/Switch device implementation
/// Ported from tinytuya/OutletDevice.py

library;

import 'core/device.dart';

/// Smart outlet/switch device
class OutletDevice extends Device {
  OutletDevice({
    required super.deviceId,
    required super.address,
    required super.localKey,
    super.version,
    super.devType,
    super.port,
  });

  /// Set dimmer value
  ///
  /// Args:
  ///   percentage: Percentage dim 0-100
  ///   value: Direct value for switch 0-255
  ///   dpsId: DPS index for dimmer value (default 3)
  ///   nowait: True to send without waiting for response
  Future<Map<String, dynamic>> setDimmer({
    int? percentage,
    int? value,
    int dpsId = 3,
    bool nowait = false,
  }) async {
    int? level;

    if (percentage != null) {
      level = (percentage * 255.0 / 100.0).round();
    } else {
      level = value;
    }

    if (level == 0) {
      return await turnOff(nowait: nowait);
    } else if (level != null) {
      if (level < 25) level = 25;
      if (level > 255) level = 255;
      await turnOn(nowait: nowait);
      return await setValue(index: dpsId, value: level, nowait: nowait);
    }

    return {'error': 'No percentage or value provided'};
  }
}
