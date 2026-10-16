/// Network scanner for discovering Tuya devices
/// Ported from tinytuya/scanner.py

library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'core/const.dart';
import 'core/udp_helper.dart';

/// Discovered device information
class DiscoveredDevice {
  final String ip;
  final String? gwId;
  final String? productKey;
  final String? version;
  final String? mac;
  final String? name;
  final String? key;
  final Map<String, dynamic> rawData;

  DiscoveredDevice({
    required this.ip,
    this.gwId,
    this.productKey,
    this.version,
    this.mac,
    this.name,
    this.key,
    required this.rawData,
  });

  Map<String, dynamic> toJson() => {
    'ip': ip,
    if (gwId != null) 'gwId': gwId,
    if (productKey != null) 'productKey': productKey,
    if (version != null) 'version': version,
    if (mac != null) 'mac': mac,
    if (name != null) 'name': name,
    if (key != null) 'key': key,
    'raw': rawData,
  };
}

/// Scan the network for Tuya devices
///
/// Args:
///   scanTime: How many seconds to wait for device responses (default 18)
///   verbose: Print discovered devices to stdout
///
/// Returns:
///   List of discovered devices
Future<List<DiscoveredDevice>> deviceScan({
  int scanTime = scanTime,
  bool verbose = false,
}) async {
  final devices = <String, DiscoveredDevice>{}; // Map by IP to avoid duplicates
  final listeners = <RawDatagramSocket>[];

  try {
    // Create UDP listeners on all three ports
    final ports = [udpPort, udpPortS, udpPortApp];

    for (final port in ports) {
      try {
        final socket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          port,
        );
        socket.broadcastEnabled = true;
        listeners.add(socket);

        if (verbose) {
          print('Listening on UDP port $port');
        }
      } catch (e) {
        if (verbose) {
          print('Warning: Could not bind to port $port: $e');
        }
      }
    }

    if (listeners.isEmpty) {
      throw Exception('Could not bind to any UDP ports');
    }

    // Send broadcast request to port 7000 for v3.5 devices
    try {
      final broadcastSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
      );
      broadcastSocket.broadcastEnabled = true;

      // Request device info (command 0x25 = reqDevinfo)
      final request = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'from': 'app',
            't': (DateTime.now().millisecondsSinceEpoch / 1000).floor(),
          }),
        ),
      );

      broadcastSocket.send(
        request,
        InternetAddress('255.255.255.255'),
        udpPortApp,
      );

      if (verbose) {
        print('Sent broadcast discovery packet to port $udpPortApp');
      }

      broadcastSocket.close();
    } catch (e) {
      if (verbose) {
        print('Warning: Could not send broadcast: $e');
      }
    }

    // Listen for responses
    final deadline = DateTime.now().add(Duration(seconds: scanTime));

    for (final socket in listeners) {
      socket.listen((event) async {
        if (event == RawSocketEvent.read) {
          final datagram = socket.receive();
          if (datagram == null) return;

          try {
            if (verbose) {
              print(
                '  Received ${datagram.data.length} bytes from ${datagram.address.address}',
              );
              // Print first 40 bytes in hex for debugging
              final hexStr = datagram.data
                  .take(40)
                  .map((b) => b.toRadixString(16).padLeft(2, '0'))
                  .join('');
              print('    First 40 bytes: $hexStr');
            }

            // Decrypt UDP packet
            final decrypted = await decryptUdp(datagram.data);
            final data = jsonDecode(decrypted) as Map<String, dynamic>;

            // Extract device info
            final ip = datagram.address.address;

            if (devices.containsKey(ip)) {
              // Already discovered this device
              return;
            }

            final device = DiscoveredDevice(
              ip: ip,
              gwId: data['gwId'] as String?,
              productKey: data['productKey'] as String?,
              version: data['version'] as String?,
              mac: data['mac'] as String?,
              name: data['name'] as String?,
              key: data['key'] as String?,
              rawData: data,
            );

            devices[ip] = device;

            if (verbose) {
              print('Found device: $ip');
              print('  Device ID: ${device.gwId ?? "unknown"}');
              print('  Product Key: ${device.productKey ?? "unknown"}');
              print('  Version: ${device.version ?? "unknown"}');
              if (device.name != null) print('  Name: ${device.name}');
            }
          } catch (e) {
            // Ignore decrypt/parse errors
            if (verbose) {
              print(
                'Warning: Could not decrypt/parse packet from ${datagram.address.address}: $e',
              );
            }
          }
        }
      });
    }

    // Wait for scan time
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 100));
    }

    return devices.values.toList();
  } finally {
    // Close all listeners
    for (final socket in listeners) {
      socket.close();
    }
  }
}
