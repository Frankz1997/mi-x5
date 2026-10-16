import 'dart:async';
import 'dart:convert';

import 'package:tinytuya/tinytuya.dart';

const modes = {
  'cold': 'Frío',
  'auto': 'Automático',
  'wet': 'Deshumidificar',
  'wind': 'Solo ventilador',
};
const fanSpeeds = {
  'auto': 'Automático',
  'low': 'Bajo',
  'middle': 'Medio',
  'high': 'Alto',
  'strong': 'Turbo',
  'mute': 'Silencioso',
};

const verticalSwings = {'off': 'Fijo', 'same': 'Vertical'};

bool isPrivateIpv4(String value) {
  final parts = value.split('.');
  if (parts.length != 4) return false;
  final octets = parts.map(int.tryParse).toList();
  if (octets.any((n) => n == null || n < 0 || n > 255)) return false;
  if (List.generate(
    4,
    (i) => octets[i].toString() != parts[i],
  ).contains(true)) {
    return false;
  }
  return octets[0] == 10 ||
      (octets[0] == 172 && octets[1]! >= 16 && octets[1]! <= 31) ||
      (octets[0] == 192 && octets[1] == 168);
}

bool isValidDeviceId(String value) =>
    RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(value);

class X5Connection {
  final String deviceId;
  final String ip;
  final String key;

  X5Connection(this.ip, this.key, {required this.deviceId}) {
    if (!isValidDeviceId(deviceId)) {
      throw const FormatException('Introduce el ID del dispositivo de Tuya.');
    }
    if (!isPrivateIpv4(ip)) {
      throw const FormatException('Introduce la IP local del aire.');
    }
    if (key.length != 16 || key.codeUnits.any((c) => c < 32 || c > 126)) {
      throw const FormatException('La clave local debe tener 16 caracteres.');
    }
  }

  factory X5Connection.decode(String source) {
    final data = jsonDecode(source);
    if (data is! Map<String, dynamic> ||
        data['id'] is! String ||
        data['ip'] is! String ||
        data['key'] is! String) {
      throw const FormatException('La configuración de conexión no es válida.');
    }
    // Keep the saved format so existing encrypted connections remain readable.
    return X5Connection(
      data['ip'] as String,
      data['key'] as String,
      deviceId: data['id'] as String,
    );
  }

  String encode() => jsonEncode({'id': deviceId, 'ip': ip, 'key': key});
}

class X5State {
  final Map<String, dynamic> dps;

  X5State(this.dps) {
    if (dps['1'] is! bool ||
        dps['2'] is! int ||
        dps['2'] < 16 ||
        dps['2'] > 32 ||
        dps['3'] is! int ||
        !modes.containsKey(dps['4']) ||
        !fanSpeeds.containsKey(dps['5'])) {
      throw const FormatException('El aire devolvió un estado desconocido.');
    }
  }

  bool get power => dps['1'] as bool;
  int get temperature => dps['2'] as int;
  int get ambient => dps['3'] as int;
  String get mode => dps['4'] as String;
  String get fan => dps['5'] as String;
}

class X5Client {
  final Device _device;

  X5Client(X5Connection connection)
    : _device = Device(
        deviceId: connection.deviceId,
        address: connection.ip,
        localKey: connection.key,
        version: 3.5,
        connectionTimeout: const Duration(seconds: 3),
        socketRetryLimit: 1,
        socketRetryDelay: const Duration(milliseconds: 250),
      );

  Future<Map<String, dynamic>> readDps() async {
    final result = await _device.status();
    if (result['success'] != true || result['dps'] is! Map) {
      throw const FormatException(
        'No se pudo leer el X5. Revisa la conexión, la IP y la clave local.',
      );
    }
    return Map<String, dynamic>.from(result['dps'] as Map);
  }

  Future<X5State> read() async => X5State(await readDps());

  Future<X5State> write(int dp, Object value) async {
    // shortcut: temperatures are limited to 16–30 °C; expand after checking the remote's limits.
    final valid = switch (dp) {
      1 || 25 || 36 => value is bool,
      2 => value is int && value >= 16 && value <= 30,
      4 => modes.containsKey(value),
      5 => fanSpeeds.containsKey(value),
      31 => verticalSwings.containsKey(value),
      _ => false,
    };
    if (!valid) throw ArgumentError('Control o valor no permitido.');
    await _device.setValue(index: dp, value: value);
    // The X5 acknowledges a command before its reported state has changed.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    var state = await read();
    if (state.dps['$dp'] != value) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      state = await read();
    }
    if (state.dps['$dp'] != value) {
      throw const FormatException(
        'El aire no confirmó el cambio. Actualiza e inténtalo de nuevo.',
      );
    }
    return state;
  }

  Future<void> close() => _device.close();
}
