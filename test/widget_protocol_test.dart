import 'package:flutter_test/flutter_test.dart';
import 'package:tinytuya/tinytuya.dart';
import '../tool/widget_tuya_simulator.dart';

void main() {
  test(
    'Tuya simulator authenticates 3.5, receives encrypted commands and reports them',
    () async {
      final server = await WidgetTuyaSimulator.start();
      final client = Device(
        deviceId: 'test',
        address: '127.0.0.1',
        port: server.server.port,
        localKey: WidgetTuyaSimulator.key,
        version: 3.5,
        connectionTimeout: const Duration(seconds: 1),
        socketRetryLimit: 1,
      );
      addTearDown(() async {
        await client.close();
        await server.close();
      });
      final initial = await client.status();
      expect(initial['success'], true);
      expect(initial['dps']['1'], true);
      await client.setValue(index: 1, value: false);
      expect(server.writes, [
        {'1': false},
      ]);
      final updated = await client.status();
      expect(updated['dps']['1'], false);
    },
  );
}
