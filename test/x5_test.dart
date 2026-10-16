import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirage_x5/main.dart';
import 'package:mirage_x5/x5.dart';

void main() {
  test(
    'Saved connections keep their own device ID, including the legacy JSON format',
    () {
      const key = '0123456789abcdef'; // Public test fixture, never a real key.
      for (final id in ['demo-x5-device', 'second-demo-device']) {
        final connection = X5Connection.decode(
          '{"id":"$id","ip":"192.168.1.50","key":"$key"}',
        );
        final restored = X5Connection.decode(connection.encode());
        expect(restored.deviceId, id);
        expect(restored.ip, '192.168.1.50');
        expect(restored.key, key);
      }
      for (final id in ['', 'has spaces', 'invalid/id', 'x' * 65]) {
        expect(
          () => X5Connection('192.168.1.50', key, deviceId: id),
          throwsFormatException,
        );
      }
      for (final json in [
        'null',
        '[]',
        '{}',
        '{"id":3,"ip":"192.168.1.50","key":"$key"}',
      ]) {
        expect(() => X5Connection.decode(json), throwsFormatException);
      }
    },
  );

  testWidgets('A new connection has empty fields and requires a device ID', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(500, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const X5App());
    await tester.tap(find.text('Conectar mi X5'));
    await tester.pumpAndSettle();
    for (final field in ['device-id', 'local-ip', 'local-key']) {
      expect(
        tester
            .widget<TextFormField>(find.byKey(ValueKey(field)))
            .controller!
            .text,
        isEmpty,
      );
    }
    await tester.tap(find.text('Comprobar y guardar'));
    await tester.pump();
    expect(find.text('Introduce el ID del dispositivo.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  test('Only literal private IPs and valid keys can be saved', () {
    for (final ip in [
      '192.168.1.50',
      '10.0.0.8',
      '172.16.0.2',
      '172.31.255.1',
    ]) {
      expect(isPrivateIpv4(ip), isTrue);
    }
    for (final ip in [
      '192.0.2.1',
      '127.0.0.1',
      '172.32.0.1',
      '192.168.1.999',
      'localhost',
      '192.168.1',
      '192.168.1.01',
      '+192.168.1.5',
    ]) {
      expect(isPrivateIpv4(ip), isFalse, reason: ip);
    }
    expect(
      () => X5Connection('192.168.1.50', 'short', deviceId: 'demo-x5-device'),
      throwsFormatException,
    );
    expect(
      () => X5Connection.decode('{"ip":"10.0.0.8","key":"0123456789abcdef"}'),
      throwsFormatException,
    );
  });

  test(
    'Unsupported commands are rejected before any network request',
    () async {
      final client = X5Client(
        X5Connection(
          '192.168.1.50',
          '0123456789abcdef',
          deviceId: 'demo-x5-device',
        ),
      );
      for (final temp in [15, 31, 90]) {
        await expectLater(client.write(2, temp), throwsArgumentError);
      }
      await expectLater(client.write(1, 'true'), throwsArgumentError);
      await expectLater(client.write(4, 'unknown'), throwsArgumentError);
      await expectLater(client.write(4, 'hot'), throwsArgumentError);
      await expectLater(client.write(105, true), throwsArgumentError);
      await expectLater(client.write(33, true), throwsArgumentError);
      await expectLater(client.write(31, true), throwsArgumentError);
      await expectLater(client.write(31, 'unknown'), throwsArgumentError);
      await client.close();
    },
  );

  test('Unexpected temperature units do not appear as Celsius', () {
    final dps = <String, dynamic>{
      '1': false,
      '2': 23,
      '3': 28,
      '4': 'cold',
      '5': 'middle',
    };
    expect(X5State(dps).temperature, 23);
    expect(() => X5State({...dps, '2': 73}), throwsFormatException);
    expect(() => X5State({...dps, '4': 'unknown'}), throwsFormatException);
  });

  testWidgets('Phone layout and settings reject a public address', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const X5App());
    for (final tooltip in tester.stateList<TooltipState>(
      find.byType(Tooltip),
    )) {
      expect(tooltip.ensureTooltipVisible(), isFalse);
    }
    await tester.tap(find.text('Conectar mi X5'));
    await tester.pumpAndSettle();
    for (final tooltip in tester.stateList<TooltipState>(
      find.byType(Tooltip),
    )) {
      expect(tooltip.ensureTooltipVisible(), isFalse);
    }
    await tester.enterText(find.byKey(const ValueKey('local-ip')), '192.0.2.1');
    await tester.tap(find.text('Comprobar y guardar'));
    await tester.pump();
    expect(find.text('Introduce una IP local válida.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
