# TinyTuya Dart

A Dart/Flutter port of [Python TinyTuya](https://github.com/jasonacox/tinytuya) - a library to control Tuya WiFi smart devices.

[![pub package](https://img.shields.io/pub/v/tinytuya.svg)](https://pub.dev/packages/tinytuya)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Features

- ✅ **Complete Protocol Support**: v3.1, v3.3, v3.4, and v3.5 (including GCM encryption)
- ✅ **Device Control**: Direct local network communication with Tuya devices
- ✅ **Device Discovery**: UDP scanner to find devices on your network
- ✅ **Cloud API**: Full Tuya Cloud API support for device management
- ✅ **Device Types**: Outlets, Bulbs (RGB/HSV), Covers, and generic devices
- ✅ **Python Compatible**: Byte-for-byte compatible with Python TinyTuya
- ✅ **Well Tested**: 56+ tests with Python comparison validation

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  tinytuya: ^0.1.0
```

Then run:

```bash
dart pub get
# or
flutter pub get
```

## Quick Start

### 1. Control a Device

```dart
import 'package:tinytuya/tinytuya.dart';

void main() async {
  // Create device instance
  final device = Device(
    devId: 'your_device_id',
    address: '192.168.1.100',
    localKey: 'your_local_key',
    version: 3.3,
  );

  // Connect and get status
  try {
    final status = await device.status();
    print('Device status: $status');

    // Turn on
    await device.turnOn();

    // Set brightness (outlet devices)
    final outlet = OutletDevice(
      devId: 'your_device_id',
      address: '192.168.1.100',
      localKey: 'your_local_key',
    );
    await outlet.setDimmer(percentage: 75);

  } finally {
    device.close();
  }
}
```

### 2. Discover Devices

```dart
import 'package:tinytuya/tinytuya.dart';

void main() async {
  print('Scanning for Tuya devices...');

  final devices = await deviceScan(scanTime: 10);

  print('Found ${devices.length} devices:');
  for (final device in devices) {
    print('  ${device.ip} - ${device.gwId} (v${device.version})');
  }
}
```

### 3. Use Cloud API

```dart
import 'package:tinytuya/tinytuya.dart';

void main() async {
  // Create cloud client
  final cloud = Cloud(
    apiKey: 'your_api_key',
    apiSecret: 'your_api_secret',
    apiRegion: 'us', // us, eu, cn, in, sg
  );

  // Authenticate
  final success = await cloud.init();
  if (!success) {
    print('Authentication failed: ${cloud.error}');
    return;
  }

  // Get all devices
  final devices = await cloud.getDevices();
  for (final device in devices) {
    print('${device['name']}: ${device['id']}');
    print('  Local Key: ${device['local_key']}');
  }

  // Get device status
  final status = await cloud.getStatus('device_id');
  print('Status: ${status?['result']}');
}
```

## Device Types

### Generic Device

All devices support these methods:

```dart
final device = Device(
  devId: 'device_id',
  address: '192.168.1.100',
  localKey: 'local_key',
  version: 3.3,
);

// Control methods
await device.turnOn(switch: 1);
await device.turnOff(switch: 2);
await device.setValue(index: 1, value: 100);
await device.setTimer(numSecs: 3600);

// Query methods
final status = await device.status();
final dpsValues = await device.detectAvailableDps();

// Low-level methods
final payload = device.generatePayload(command: dpQuery);
await device.send(payload);
final response = await device.receive();
```

### OutletDevice (Smart Plugs)

```dart
final outlet = OutletDevice(
  devId: 'device_id',
  address: '192.168.1.100',
  localKey: 'local_key',
);

// Set dimmer/brightness
await outlet.setDimmer(percentage: 75);  // 0-100%
```

### BulbDevice (Smart Bulbs)

```dart
final bulb = BulbDevice(
  devId: 'device_id',
  address: '192.168.1.100',
  localKey: 'local_key',
);

// Auto-detect bulb type (A, B, or C)
bulb.detectBulb();

// Color control
await bulb.setColour(255, 0, 0);  // Red
await bulb.setHsv(0.5, 1.0, 1.0);  // HSV

// White control
await bulb.setWhite(brightness: 255, colourTemp: 128);
await bulb.setWhitePercentage(brightness: 100, colourTemp: 50);

// Brightness
await bulb.setBrightness(200);  // 0-255
await bulb.setBrightnessPercentage(80);  // 0-100%

// Color temperature
await bulb.setColourTemp(150);  // Raw value
await bulb.setColourTempPercentage(60);  // 0-100%

// Modes and scenes
await bulb.setMode('colour');  // white, colour, scene, music
await bulb.setScene(3);  // 1=nature, 3=rave, 4=rainbow

// Query color state
final rgb = bulb.colourRgb();  // [r, g, b]
final hsv = bulb.colourHsv();  // [h, s, v]
final brightness = bulb.brightness();
final temp = bulb.colourTemp();
```

### CoverDevice (Blinds/Curtains)

```dart
final cover = CoverDevice(
  devId: 'device_id',
  address: '192.168.1.100',
  localKey: 'local_key',
);

await cover.openCover();
await cover.closeCover();
await cover.stopCover();
```

## Scanner

Discover Tuya devices on your local network:

```dart
// Scan for 10 seconds (default)
final devices = await deviceScan();

// Custom scan time
final devices = await deviceScan(scanTime: 20);

// Verbose output
final devices = await deviceScan(verbose: true);

// Each device contains:
print(device.ip);           // IP address
print(device.gwId);         // Gateway ID (device ID)
print(device.version);      // Protocol version
print(device.productKey);   // Product key
print(device.rawData);      // Full JSON data
```

The scanner listens on multiple UDP ports (6666, 6667, 7000) and decrypts UDP broadcast packets from all protocol versions (v3.1-v3.5).

## Cloud API

The Cloud API provides access to the Tuya IoT Platform for device management and control:

```dart
final cloud = Cloud(
  apiKey: 'your_api_key',
  apiSecret: 'your_api_secret',
  apiRegion: 'us',  // or 'eu', 'cn', 'in', 'sg'
);

// Initialize (get access token)
await cloud.init();

// Get all devices with local keys
final devices = await cloud.getDevices();

// Get device status
final status = await cloud.getStatus('device_id');

// Send command
await cloud.sendCommand('device_id', {
  'commands': [
    {'code': 'switch_1', 'value': true}
  ]
});

// Get device specifications
final specs = await cloud.getDps('device_id');
final functions = await cloud.getFunctions('device_id');
final properties = await cloud.getProperties('device_id');

// Generic cloud request
final response = await cloud.cloudRequest(
  '/v1.0/devices/device_id/logs',
  action: 'GET',
);
```

### Getting Cloud Credentials

1. Sign up at [Tuya IoT Platform](https://iot.tuya.com/)
2. Create a Cloud Project
3. Link your devices to the project
4. Get your API Key and Secret from the project overview

## Configuration

### Finding Device Parameters

You need three pieces of information to control a device:

1. **Device ID** (`devId`): Found in the Tuya/Smart Life app
2. **Local Key**: Obtained via Cloud API or [tinytuya wizard](https://github.com/jasonacox/tinytuya)
3. **IP Address**: Use the scanner or check your router

### Protocol Versions

- **v3.1**: Older devices, basic encryption
- **v3.3**: Most common, improved security
- **v3.4**: Additional HMAC validation
- **v3.5**: Latest, uses AES-GCM encryption

The library automatically handles all protocol versions.

### Socket Persistence

The `persist` parameter controls socket connection behavior:

```dart
// persist=false (default) - Socket closes after each operation
// Matches Python TinyTuya's socketPersistent=False
final device = Device(
  deviceId: 'your_device_id',
  address: '192.168.1.100',
  localKey: 'your_local_key',
  version: 3.3,
  persist: false,  // Default - socket closes after each operation
);

// persist=true - Socket stays open between operations
// Better for frequent operations, but connection may timeout after ~1 minute idle
final devicePersistent = Device(
  deviceId: 'your_device_id',
  address: '192.168.1.100',
  localKey: 'your_local_key',
  version: 3.3,
  persist: true,  // Keep socket open
);
```

**Recommendations**:
- Use `persist=false` (default) for reliability - socket closes/reopens for each operation
- Use `persist=true` for performance when making many rapid consecutive operations
- The library automatically handles session timeout and reconnection in both modes

## Examples

See the [`example/`](example/) directory for complete examples:

- `device_control_example.dart` - Basic device control
- `bulb_example.dart` - Smart bulb control
- `scanner_example.dart` - Device discovery
- `cloud_example.dart` - Cloud API usage

## Testing

The library includes comprehensive tests with Python comparison validation:

```bash
# Run all tests
dart test

# Run specific test suite
dart test test/bulb_color_conversion_test.dart

# Run scanner comparison (requires devices on network)
./example/compare_scanners.sh
```

Tests include:
- AES encryption (ECB and GCM)
- Message packing/unpacking
- Payload generation
- Device helper methods
- Bulb color conversion
- Cloud API signatures
- Scanner functionality

All tests compare output byte-for-byte with Python TinyTuya to ensure compatibility.

## Troubleshooting

### Device Connection Issues

**Problem**: Cannot connect to device

**Solutions**:
- Verify device is on same network
- Check firewall settings
- Ensure correct protocol version
- Verify local key is correct

**Problem**: "Invalid JSON" errors

**Solutions**:
- Try different protocol versions (3.1, 3.3, 3.4, 3.5)
- Some devices require protocol auto-detection

### Cloud API Issues

**Problem**: Authentication fails

**Solutions**:
- Verify API key and secret
- Check API region matches your account
- Ensure devices are linked to your cloud project

**Problem**: "Device not found"

**Solutions**:
- Link device to cloud project in Tuya IoT Platform
- Wait a few minutes after linking for propagation

## Comparison with Python TinyTuya

This Dart port maintains full compatibility with Python TinyTuya:

| Feature | Python TinyTuya | TinyTuya Dart |
|---------|----------------|---------------|
| Protocol Support | v3.1-v3.5 | ✅ v3.1-v3.5 |
| Device Control | ✅ | ✅ |
| Cloud API | ✅ | ✅ |
| Scanner | ✅ | ✅ |
| Bulb Control | ✅ | ✅ |
| Payload Generation | ✅ | ✅ (byte-compatible) |
| Encryption | ✅ | ✅ (byte-compatible) |

All cryptographic operations and message formats are validated against Python TinyTuya to ensure interoperability.

## Why Not PointyCastle?

This port uses the `cryptography` package instead of PointyCastle because:
- PointyCastle has known issues with GCM counter mode
- IV/nonce and tag size handling problems in cross-language scenarios
- The `cryptography` package provides proper AES-GCM implementation
- Better cross-platform support and performance

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass: `dart test`
5. Submit a pull request

## Credits

This is a port of [Python TinyTuya](https://github.com/jasonacox/tinytuya) by Jason Cox.

Original Python TinyTuya credits:
- **TuyaAPI** by codetheweb and blackrozes - Protocol reverse engineering
- **PyTuya** by clach04 - Original Python implementation
- **LocalTuya** by rospogrigio - Device ID support improvements

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Resources

- [Python TinyTuya](https://github.com/jasonacox/tinytuya)
- [Tuya IoT Platform](https://iot.tuya.com/)
- [Tuya Developer Documentation](https://developer.tuya.com/)
- [Getting Local Keys Guide](https://github.com/jasonacox/tinytuya#setup-wizard---getting-local-keys)
