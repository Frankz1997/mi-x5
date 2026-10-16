/// Tuya Smart Light/Bulb Device
/// Ported from tinytuya/BulbDevice.py

library;

import 'dart:math' as math;
import 'core/device.dart';

/// Represents a Tuya based Smart Light/Bulb
class BulbDevice extends Device {
  // Mode constants
  static const String dpsModeWhite = "white";
  static const String dpsModeColour = "colour";
  static const String dpsModeScene = "scene";
  static const String dpsModeMusic = "music";
  static const String dpsModeScene1 = "scene_1"; // nature
  static const String dpsModeScene2 = "scene_2";
  static const String dpsModeScene3 = "scene_3"; // rave
  static const String dpsModeScene4 = "scene_4"; // rainbow

  // Feature constants
  static const String bulbFeatureMode = 'mode';
  static const String bulbFeatureBrightness = 'brightness';
  static const String bulbFeatureColourtemp = 'colourtemp';
  static const String bulbFeatureColour = 'colour';
  static const String bulbFeatureScene = 'scene';
  static const String bulbFeatureSceneData = 'scene_data';
  static const String bulbFeatureTimer = 'timer';
  static const String bulbFeatureMusic = 'music';

  // Music transition constants
  static const int musicTransitionJump = 0;
  static const int musicTransitionFade = 1;

  // Default DPS mappings for different bulb types
  static const Map<String, dynamic> defaultDpSetA = {
    'switch': 1,
    'mode': 2,
    'brightness': 3,
    'colourtemp': 4,
    'colour': 5,
    'scene': 6,
    'scene_data': null, // Type A sets mode to 'scene_N'
    'timer': 7,
    'music': 8,
    'value_min': 25,
    'value_max': 255,
    'value_hexformat': 'rgb8',
  };

  static const Map<String, dynamic> defaultDpSetB = {
    'switch': 20,
    'mode': 21,
    'brightness': 22,
    'colourtemp': 23,
    'colour': 24,
    'scene': 25,
    'scene_data': 25, // Type B prefixes scene data with idx
    'timer': 26,
    'music': 28,
    'value_min': 10,
    'value_max': 1000,
    'value_hexformat': 'hsv16',
  };

  static const Map<String, dynamic> defaultDpSetC = {
    'switch': 1,
    'mode': null,
    'brightness': 2,
    'colourtemp': 3,
    'colour': null,
    'scene': null,
    'scene_data': null,
    'timer': null,
    'music': null,
    'value_min': 25,
    'value_max': 255,
    'value_hexformat': 'rgb8',
  };

  static const Map<String, dynamic> defaultDpSetNone = {
    'switch': 1,
    'mode': null,
    'brightness': null,
    'colourtemp': null,
    'colour': null,
    'scene': null,
    'scene_data': null,
    'timer': null,
    'music': null,
    'value_min': 0,
    'value_max': 255,
    'value_hexformat': 'rgb8',
  };

  // Instance variables
  bool bulbConfigured = false;
  String? bulbType;
  bool? hasBrightness;
  bool? hasColourtemp;
  bool? hasColour;
  bool triedStatus = false;
  late Map<String, dynamic> dpset;

  BulbDevice({
    required super.deviceId,
    required super.address,
    required super.localKey,
    super.version,
    super.devType,
    super.port,
  }) {
    // Initialize dpset with default values
    dpset = {
      'switch': null,
      'mode': null,
      'brightness': null,
      'colourtemp': null,
      'colour': null,
      'scene': null,
      'scene_data': null,
      'timer': null,
      'music': null,
      'value_min': -1,
      'value_max': -1,
      'value_hexformat': 'hsv16',
    };
  }

  @override
  Future<Map<String, dynamic>> status() async {
    final result = await super.status();
    triedStatus = true;
    if (result.isNotEmpty && !bulbConfigured && result.containsKey('dps')) {
      detectBulb(response: result);
    }
    return result;
  }

  /// Convert RGB values (0-255) to hex representation for Tuya bulb
  ///
  /// Args:
  ///   r: Red value 0-255
  ///   g: Green value 0-255
  ///   b: Blue value 0-255
  ///   hexformat: Either "rgb8" (rrggbb0hhhssvv) or "hsv16" (hhhhssssvvvv)
  static String rgbToHexvalue(int r, int g, int b, String hexformat) {
    if (r < 0 || r > 255) {
      throw ArgumentError(
        'rgb_to_hexvalue: red value must be between 0 and 255',
      );
    }
    if (g < 0 || g > 255) {
      throw ArgumentError(
        'rgb_to_hexvalue: green value must be between 0 and 255',
      );
    }
    if (b < 0 || b > 255) {
      throw ArgumentError(
        'rgb_to_hexvalue: blue value must be between 0 and 255',
      );
    }

    // Convert RGB to HSV
    final hsv = _rgbToHsv(r / 255.0, g / 255.0, b / 255.0);

    if (hexformat == 'rgb8') {
      // r:0-255,g:0-255,b:0-255 + h:0-360,s:0-255,v:0-255
      // Use truncate() to match Python's int() behavior
      final rgbHex =
          '${r.toRadixString(16).padLeft(2, '0')}'
          '${g.toRadixString(16).padLeft(2, '0')}'
          '${b.toRadixString(16).padLeft(2, '0')}';
      final hsvHex =
          '${(hsv[0] * 360).truncate().toRadixString(16).padLeft(4, '0')}'
          '${(hsv[1] * 255).truncate().toRadixString(16).padLeft(2, '0')}'
          '${(hsv[2] * 255).truncate().toRadixString(16).padLeft(2, '0')}';
      return rgbHex + hsvHex;
    } else if (hexformat == 'hsv16') {
      // h:0-360,s:0-1000,v:0-1000
      // Use truncate() to match Python's int() behavior
      return '${(hsv[0] * 360).truncate().toRadixString(16).padLeft(4, '0')}'
          '${(hsv[1] * 1000).truncate().toRadixString(16).padLeft(4, '0')}'
          '${(hsv[2] * 1000).truncate().toRadixString(16).padLeft(4, '0')}';
    } else {
      throw ArgumentError(
        'rgb_to_hexvalue: hexformat must be either "rgb8" or "hsv16"',
      );
    }
  }

  /// Convert HSV values (0-1) to hex representation for Tuya bulb
  ///
  /// Args:
  ///   h: Hue 0-1
  ///   s: Saturation 0-1
  ///   v: Value 0-1
  ///   hexformat: Either "rgb8" (rrggbb0hhhssvv) or "hsv16" (hhhhssssvvvv)
  static String hsvToHexvalue(double h, double s, double v, String hexformat) {
    if (h < 0 || h > 1) {
      throw ArgumentError('hsv_to_hexvalue: Hue must be between 0 and 1');
    }
    if (s < 0 || s > 1) {
      throw ArgumentError(
        'hsv_to_hexvalue: Saturation must be between 0 and 1',
      );
    }
    if (v < 0 || v > 1) {
      throw ArgumentError('hsv_to_hexvalue: Value must be between 0 and 1');
    }

    if (hexformat == 'rgb8') {
      // Convert to RGB first
      final rgb = _hsvToRgb(h, s, v);
      return rgbToHexvalue(
        (rgb[0] * 255).round(),
        (rgb[1] * 255).round(),
        (rgb[2] * 255).round(),
        hexformat,
      );
    } else if (hexformat == 'hsv16') {
      // h:0-360,s:0-1000,v:0-1000
      // Use truncate() to match Python's int() behavior
      return '${(h * 360).truncate().toRadixString(16).padLeft(4, '0')}'
          '${(s * 1000).truncate().toRadixString(16).padLeft(4, '0')}'
          '${(v * 1000).truncate().toRadixString(16).padLeft(4, '0')}';
    } else {
      throw ArgumentError(
        'hsv_to_hexvalue: hexformat must be either "rgb8" or "hsv16"',
      );
    }
  }

  /// Convert hex representation to RGB values (0-255)
  ///
  /// Args:
  ///   hexvalue: Hex string from bulb
  ///   hexformat: "rgb8", "hsv16", or null for auto-detect
  static List<int> hexvalueToRgb(String hexvalue, {String? hexformat}) {
    final hexvalueLen = hexvalue.length;

    hexformat ??= _detectHexformat(hexvalueLen);

    if (hexformat == 'rgb8') {
      if (hexvalueLen < 6) {
        throw ArgumentError('RGB value string must have 6 or 14 hex digits');
      }
      final r = int.parse(hexvalue.substring(0, 2), radix: 16);
      final g = int.parse(hexvalue.substring(2, 4), radix: 16);
      final b = int.parse(hexvalue.substring(4, 6), radix: 16);
      return [r, g, b];
    } else if (hexformat == 'hsv16') {
      // hexvalue is in hsv
      if (hexvalueLen < 12) {
        throw ArgumentError('HSV value string must have 12 hex digits');
      }
      final h = int.parse(hexvalue.substring(0, 4), radix: 16) / 360.0;
      final s = int.parse(hexvalue.substring(4, 8), radix: 16) / 1000.0;
      final v = int.parse(hexvalue.substring(8, 12), radix: 16) / 1000.0;
      final rgb = _hsvToRgb(h, s, v);
      return [
        (rgb[0] * 255).round(),
        (rgb[1] * 255).round(),
        (rgb[2] * 255).round(),
      ];
    } else {
      throw ArgumentError(
        'hexvalue_to_rgb: hexformat must be null, "rgb8" or "hsv16"',
      );
    }
  }

  /// Convert hex representation to HSV values (0-1)
  ///
  /// Args:
  ///   hexvalue: Hex string from bulb
  ///   hexformat: "rgb8", "hsv16", or null for auto-detect
  static List<double> hexvalueToHsv(String hexvalue, {String? hexformat}) {
    final hexvalueLen = hexvalue.length;

    hexformat ??= _detectHexformat(hexvalueLen);

    if (hexformat == 'rgb8') {
      if (hexvalueLen < 6) {
        throw ArgumentError(
          'RGB[HSV] value string must have 6 or 14 hex digits',
        );
      }
      if (hexvalueLen < 14) {
        // hexvalue is in rgb only
        final rgb = hexvalueToRgb(hexvalue, hexformat: 'rgb8');
        return _rgbToHsv(rgb[0] / 255.0, rgb[1] / 255.0, rgb[2] / 255.0);
      } else {
        // hexvalue includes hsv
        final h = int.parse(hexvalue.substring(7, 10), radix: 16) / 360.0;
        final s = int.parse(hexvalue.substring(10, 12), radix: 16) / 255.0;
        final v = int.parse(hexvalue.substring(12, 14), radix: 16) / 255.0;
        return [h, s, v];
      }
    } else if (hexformat == 'hsv16') {
      // hexvalue is in hsv
      if (hexvalueLen < 12) {
        throw ArgumentError('HSV value string must have 12 hex digits');
      }
      final h = int.parse(hexvalue.substring(0, 4), radix: 16) / 360.0;
      final s = int.parse(hexvalue.substring(4, 8), radix: 16) / 1000.0;
      final v = int.parse(hexvalue.substring(8, 12), radix: 16) / 1000.0;
      return [h, s, v];
    } else {
      throw ArgumentError(
        'hexvalue_to_hsv: hexformat must be null, "rgb8" or "hsv16"',
      );
    }
  }

  // Helper method to detect hex format from length
  static String _detectHexformat(int hexvalueLen) {
    if (hexvalueLen == 6 || hexvalueLen == 14) {
      return 'rgb8';
    } else if (hexvalueLen == 12) {
      return 'hsv16';
    } else {
      throw ArgumentError(
        'Unable to detect hexvalue format. Value string must have 6, 12 or 14 hex digits.',
      );
    }
  }

  // RGB to HSV conversion (values 0-1)
  static List<double> _rgbToHsv(double r, double g, double b) {
    final max = math.max(r, math.max(g, b));
    final min = math.min(r, math.min(g, b));
    final delta = max - min;

    double h = 0;
    if (delta != 0) {
      if (max == r) {
        h = ((g - b) / delta) % 6;
      } else if (max == g) {
        h = (b - r) / delta + 2;
      } else {
        h = (r - g) / delta + 4;
      }
      h /= 6;
      if (h < 0) h += 1;
    }

    final s = max == 0 ? 0.0 : delta / max;
    final v = max;

    return [h, s, v];
  }

  // HSV to RGB conversion (values 0-1)
  static List<double> _hsvToRgb(double h, double s, double v) {
    final c = v * s;
    final x = c * (1 - ((h * 6) % 2 - 1).abs());
    final m = v - c;

    double r, g, b;
    final hSector = (h * 6).floor();

    switch (hSector) {
      case 0:
        r = c;
        g = x;
        b = 0;
        break;
      case 1:
        r = x;
        g = c;
        b = 0;
        break;
      case 2:
        r = 0;
        g = c;
        b = x;
        break;
      case 3:
        r = 0;
        g = x;
        b = c;
        break;
      case 4:
        r = x;
        g = 0;
        b = c;
        break;
      default:
        r = c;
        g = 0;
        b = x;
    }

    return [r + m, g + m, b + m];
  }

  /// Check if bulb has a specific capability
  bool bulbHasCapability(String feature) {
    if (!bulbConfigured) {
      detectBulb();
      if (!bulbConfigured) {
        throw StateError(
          'Bulb not configured, cannot get device capabilities.',
        );
      }
    }
    return dpset[feature] != null;
  }

  /// Helper to set values only if they have changed
  Future<Map<String, dynamic>> _setValuesCheck(
    Map<String, dynamic> checkValues, {
    bool nowait = false,
  }) async {
    final dpsValues = <dynamic, dynamic>{};

    // Check to see which DPs need to be set
    final state = await cachedStatus(historic: false);
    if (state != null && state.containsKey('dps') && state['dps'] != null) {
      // Last state is cached, so check to see which values need updating
      final stateDps = state['dps'] as Map<String, dynamic>;
      for (final key in checkValues.keys) {
        final dp = dpset[key];
        if (dp != null) {
          final dpStr = dp.toString();
          if (!stateDps.containsKey(dpStr) ||
              stateDps[dpStr] != checkValues[key]) {
            dpsValues[dpStr] = checkValues[key];
          }
        }
      }
    }

    if (dpsValues.isEmpty) {
      // Last state not cached or everything already set, so send them all
      for (final key in checkValues.keys) {
        final dp = dpset[key];
        if (dp != null) {
          dpsValues[dp.toString()] = checkValues[key];
        }
      }
    }

    return await setMultipleValues(dpsValues, nowait: nowait);
  }

  /// Turn the bulb on or off
  Future<Map<String, dynamic>> turnOnOff(
    bool on, {
    int switchDp = 0,
    bool nowait = false,
  }) async {
    if (switchDp == 0) {
      if (!triedStatus) {
        detectBulb();
      }
      // Default to '1' if we can't detect it
      switchDp = dpset['switch'] ?? 1;
    }
    return await setStatus(
      on: on,
      switchNum: switchDp.toString(),
      nowait: nowait,
    );
  }

  /// Turn the bulb on
  @override
  Future<Map<String, dynamic>> turnOn({
    String switchNum = '1',
    bool nowait = false,
  }) async {
    final switchDp = int.tryParse(switchNum) ?? 0;
    return await turnOnOff(true, switchDp: switchDp, nowait: nowait);
  }

  /// Turn the bulb off
  @override
  Future<Map<String, dynamic>> turnOff({
    String switchNum = '1',
    bool nowait = false,
  }) async {
    final switchDp = int.tryParse(switchNum) ?? 0;
    return await turnOnOff(false, switchDp: switchDp, nowait: nowait);
  }

  /// Set bulb mode (white, colour, scene, music)
  Future<Map<String, dynamic>> setMode(
    String mode, {
    bool nowait = false,
  }) async {
    if (!bulbHasCapability('mode')) {
      return {'Error': 'Bulb does not support mode setting'};
    }

    final checkValues = {'mode': mode, 'switch': true};

    return await _setValuesCheck(checkValues, nowait: nowait);
  }

  /// Set bulb to scene mode
  Future<Map<String, dynamic>> setScene(
    int scene, {
    String? sceneData,
    bool nowait = false,
  }) async {
    if (!bulbHasCapability('scene')) {
      return {'Error': 'Bulb does not support scenes'};
    }

    final dpsValues = <String, dynamic>{};

    // Type A: scene idx is part of the mode
    if (dpset['scene_data'] == null || dpset['scene_data'] == dpset['mode']) {
      if (scene < 1 || scene > 4) {
        throw ArgumentError(
          'Scene value must be between 1 and 4 for Type A bulbs',
        );
      }
      dpsValues['mode'] = '${dpsModeScene}_$scene';
    } else {
      // Type B: separate scene and scene_data DPs
      final sceneHex = scene.toRadixString(16).padLeft(2, '0');
      dpsValues['scene'] = sceneHex;
      dpsValues['mode'] = dpsModeScene;

      if (sceneData != null) {
        if (dpset['scene_data'] == true ||
            dpset['scene_data'] == dpset['scene']) {
          dpsValues['scene'] = sceneHex + sceneData;
        } else {
          dpsValues['scene_data'] = sceneData;
        }
      }
    }

    return await _setValuesCheck(dpsValues, nowait: nowait);
  }

  /// Set bulb color using RGB values (0-255)
  Future<Map<String, dynamic>> setColour(
    int r,
    int g,
    int b, {
    bool nowait = false,
  }) async {
    if (!bulbHasCapability('colour')) {
      return {'Error': 'Device does not support color'};
    }

    final checkValues = {
      'colour': rgbToHexvalue(r, g, b, dpset['value_hexformat'] as String),
      'mode': dpsModeColour,
      'switch': true,
    };

    return await _setValuesCheck(checkValues, nowait: nowait);
  }

  /// Set bulb color using HSV values (0-1)
  Future<Map<String, dynamic>> setHsv(
    double h,
    double s,
    double v, {
    bool nowait = false,
  }) async {
    if (!bulbHasCapability('colour')) {
      return {'Error': 'Device does not support color'};
    }

    final checkValues = {
      'colour': hsvToHexvalue(h, s, v, dpset['value_hexformat'] as String),
      'mode': dpsModeColour,
      'switch': true,
    };

    return await _setValuesCheck(checkValues, nowait: nowait);
  }

  /// Set white mode with brightness and color temperature (percentage 0-100)
  Future<Map<String, dynamic>> setWhitePercentage({
    int brightness = 100,
    int colourtemp = 0,
    bool nowait = false,
  }) async {
    if (brightness < 0 || brightness > 100) {
      throw ArgumentError('Brightness must be between 0 and 100');
    }
    if (colourtemp < 0 || colourtemp > 100) {
      throw ArgumentError('Colourtemp must be between 0 and 100');
    }

    final valueMax = dpset['value_max'] as int;
    final b = (valueMax * brightness / 100).truncate();
    final c = (valueMax * colourtemp / 100).truncate();

    return await setWhite(brightness: b, colourtemp: c, nowait: nowait);
  }

  /// Set white mode with raw brightness and color temperature values
  Future<Map<String, dynamic>> setWhite({
    int brightness = -1,
    int colourtemp = -1,
    bool nowait = false,
  }) async {
    if (!bulbHasCapability('brightness')) {
      return {'Error': 'Device does not support brightness'};
    }

    final valueMin = dpset['value_min'] as int;
    final valueMax = dpset['value_max'] as int;

    // Brightness (default: Max)
    if (brightness < 0) {
      brightness = valueMax;
    } else if (brightness > valueMax) {
      throw ArgumentError('Brightness must be between $valueMin and $valueMax');
    }

    // Colourtemp (default: Min)
    if (colourtemp < 0) {
      colourtemp = 0;
    } else if (colourtemp > valueMax) {
      throw ArgumentError('Colourtemp must be between 0 and $valueMax');
    }

    final checkValues = <String, dynamic>{};
    if (brightness >= valueMin) {
      checkValues['brightness'] = brightness;
    }
    if (colourtemp >= 0 && bulbHasCapability('colourtemp')) {
      checkValues['colourtemp'] = colourtemp;
    }
    if (checkValues.isNotEmpty) {
      checkValues['mode'] = dpsModeWhite;
    }
    checkValues['switch'] = brightness >= valueMin;

    return await _setValuesCheck(checkValues, nowait: nowait);
  }

  /// Set brightness (percentage 0-100)
  Future<Map<String, dynamic>> setBrightnessPercentage(
    int brightness, {
    bool nowait = false,
  }) async {
    if (brightness < 0 || brightness > 100) {
      throw ArgumentError('Brightness must be between 0 and 100');
    }
    final valueMax = dpset['value_max'] as int;
    final b = (valueMax * brightness / 100).truncate();
    return await setBrightness(b, nowait: nowait);
  }

  /// Set brightness (raw value based on bulb type)
  Future<Map<String, dynamic>> setBrightness(
    int brightness, {
    bool nowait = false,
  }) async {
    if (!bulbHasCapability('brightness')) {
      return {'Error': 'Device does not support brightness'};
    }

    final valueMin = dpset['value_min'] as int;
    final valueMax = dpset['value_max'] as int;

    if (brightness < 0) {
      brightness = valueMax;
    } else if (brightness < valueMin) {
      return await turnOff(nowait: nowait);
    } else if (brightness > valueMax) {
      throw ArgumentError('Brightness must be between $valueMin and $valueMax');
    }

    // Get current state to determine mode
    final state = await cachedStatus(historic: false);
    if (state == null || !state.containsKey('dps')) {
      return {'Error': 'Could not get device state'};
    }

    final modeDp = dpset['mode'];
    final stateDps = state['dps'] as Map<String, dynamic>?;
    final currentMode = modeDp != null && stateDps != null
        ? stateDps[modeDp.toString()]
        : null;

    if (currentMode != dpsModeColour) {
      // Use white mode
      return await setWhite(
        brightness: brightness,
        colourtemp: -1,
        nowait: nowait,
      );
    } else {
      // For colour mode, adjust HSV value
      final value = brightness / valueMax.toDouble();
      final colourDp = dpset['colour'];
      if (colourDp == null) {
        return {'Error': 'Colour DP not available'};
      }

      final colourHex = stateDps != null
          ? stateDps[colourDp.toString()] as String?
          : null;
      if (colourHex == null) {
        return {'Error': 'Could not get current colour'};
      }

      final hsv = hexvalueToHsv(
        colourHex,
        hexformat: dpset['value_hexformat'] as String,
      );
      return await setHsv(hsv[0], hsv[1], value, nowait: nowait);
    }
  }

  /// Set color temperature (percentage 0-100)
  Future<Map<String, dynamic>> setColourTempPercentage(
    int colourtemp, {
    bool nowait = false,
  }) async {
    if (colourtemp < 0 || colourtemp > 100) {
      throw ArgumentError('Colourtemp must be between 0 and 100');
    }
    final valueMax = dpset['value_max'] as int;
    final c = (valueMax * colourtemp / 100).truncate();
    return await setColourTemp(c, nowait: nowait);
  }

  /// Set color temperature (raw value based on bulb type)
  Future<Map<String, dynamic>> setColourTemp(
    int colourtemp, {
    bool nowait = false,
  }) async {
    if (!bulbHasCapability('colourtemp')) {
      return {'Error': 'Device does not support color temperature'};
    }

    final valueMax = dpset['value_max'] as int;

    if (colourtemp < 0) {
      colourtemp = 0;
    } else if (colourtemp > valueMax) {
      throw ArgumentError('Colourtemp must be between 0 and $valueMax');
    }

    return await setWhite(
      brightness: -1,
      colourtemp: colourtemp,
      nowait: nowait,
    );
  }

  /// Detect bulb type and capabilities from status response
  void detectBulb({Map<String, dynamic>? response}) {
    // Note: cachedStatus is async, so we can't call it from this sync method
    // If response is null, bulb detection will happen later when status() is called
    if (response == null) {
      return;
    }

    if (!response.containsKey('dps') || response['dps'] == null) {
      return;
    }

    final dps = response['dps'] as Map<String, dynamic>;

    // Determine bulb type based on DPS keys
    if (dps.containsKey('20') && dps.containsKey('1')) {
      // Both 1 and 20 present - probably not a bulb
      bulbConfigured = true;
      bulbType = 'None';
    } else if (dps.containsKey('20') && dps.containsKey('21')) {
      // Type B bulb
      bulbConfigured = true;
      bulbType = 'B';
    } else if (dps.containsKey('1') && dps.containsKey('2')) {
      bulbConfigured = true;
      // Type A if DP 2 is string (mode), Type C if DP 2 is int (brightness)
      bulbType = dps['2'] is String ? 'A' : 'C';
    }

    if (bulbType != null) {
      // Get default DPS set for this bulb type
      Map<String, dynamic>? defaultSet;
      switch (bulbType) {
        case 'A':
          defaultSet = defaultDpSetA;
          break;
        case 'B':
          defaultSet = defaultDpSetB;
          break;
        case 'C':
          defaultSet = defaultDpSetC;
          break;
        case 'None':
          defaultSet = defaultDpSetNone;
          break;
      }

      if (defaultSet != null) {
        // Copy value_* settings
        dpset['value_min'] = defaultSet['value_min'];
        dpset['value_max'] = defaultSet['value_max'];
        dpset['value_hexformat'] = defaultSet['value_hexformat'];
        dpset['music'] = defaultSet['music'];

        // Map DPS indices that are present in the response
        for (final key in defaultSet.keys) {
          if (key.startsWith('value_')) continue;
          final defaultDp = defaultSet[key];
          if (defaultDp != null) {
            final dpStr = defaultDp.toString();
            if (dps.containsKey(dpStr)) {
              dpset[key] = dpStr;
            }
          }
        }

        // Set has_* attributes for backwards compatibility
        hasBrightness = dpset['brightness'] != null;
        hasColourtemp = dpset['colourtemp'] != null;
        hasColour = dpset['colour'] != null;
      }
    }
  }
}
