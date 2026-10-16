/// Cover/Blind device implementation
/// Ported from tinytuya/CoverDevice.py

library;

import 'core/device.dart';

/// Smart cover/blind device
class CoverDevice extends Device {
  static const String dpsIndexMove = '1';
  static const String dpsIndexBl = '101';

  CoverDevice({
    required super.deviceId,
    required super.address,
    required super.localKey,
    super.version,
    super.devType,
    super.port,
  });

  /// Open the cover
  ///
  /// Args:
  ///   switchNum: The switch to control (default '1')
  ///   nowait: True to send without waiting for response
  Future<Map<String, dynamic>> openCover({
    String switchNum = '1',
    bool nowait = false,
  }) async {
    return await setStatus(on: true, switchNum: switchNum, nowait: nowait);
  }

  /// Close the cover
  ///
  /// Args:
  ///   switchNum: The switch to control (default '1')
  ///   nowait: True to send without waiting for response
  Future<Map<String, dynamic>> closeCover({
    String switchNum = '1',
    bool nowait = false,
  }) async {
    return await setStatus(on: false, switchNum: switchNum, nowait: nowait);
  }

  /// Stop the motion of the cover
  ///
  /// Args:
  ///   switchNum: The switch to control (default '1')
  ///   nowait: True to send without waiting for response
  Future<Map<String, dynamic>> stopCover({
    String switchNum = '1',
    bool nowait = false,
  }) async {
    return await setValue(index: switchNum, value: 'stop', nowait: nowait);
  }
}
