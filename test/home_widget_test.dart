import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirage_x5/home_widget.dart';
import 'package:mirage_x5/x5.dart';

class WidgetClient extends X5Client {
  WidgetClient()
    : super(
        X5Connection(
          '192.168.1.50',
          '0123456789abcdef',
          deviceId: 'demo-x5-device',
        ),
      );
  var state = X5State({
    '1': true,
    '2': 23,
    '3': 28,
    '4': 'cold',
    '5': 'auto',
    '25': false,
    '31': 'off',
    '36': true,
  });
  var reads = 0;
  var failRead = false;
  Completer<X5State>? readGate;
  final writes = <(int, Object)>[];
  @override
  Future<X5State> read() async {
    reads++;
    if (readGate != null) return readGate!.future;
    if (failRead) throw const FormatException('Offline');
    return state;
  }

  @override
  Future<X5State> write(int dp, Object value) async {
    writes.add((dp, value));
    return state = X5State({...state.dps, '$dp': value});
  }
}

void main() {
  testWidgets('A timed out widget read never sends a late command', (
    tester,
  ) async {
    final client = WidgetClient()..readGate = Completer<X5State>();
    Object? failure;
    final request = performWidgetAction('power', client).catchError((
      Object error,
    ) {
      failure = error;
      return client.state;
    });
    await tester.pump(const Duration(seconds: 9));
    expect(failure, isA<TimeoutException>());
    client.readGate!.complete(client.state);
    await tester.pump();
    await request;
    expect(client.writes, isEmpty);
  });
  test(
    'Widget actions read fresh state and use only confirmed X5 commands',
    () async {
      final client = WidgetClient();
      for (final (action, expected) in [
        ('power', (1, false)),
        ('power', (1, true)),
        ('down', (2, 22)),
        ('up', (2, 23)),
        ('sleep', (25, true)),
        ('sleep', (25, false)),
        ('swing', (31, 'same')),
        ('swing', (31, 'off')),
        ('display', (36, false)),
        ('display', (36, true)),
      ]) {
        final reads = client.reads;
        await performWidgetAction(action, client);
        expect(client.reads, reads + 1);
        expect(client.writes.last, expected);
      }
      for (final mode in ['auto', 'wet', 'wind', 'cold']) {
        await performWidgetAction('mode', client);
        expect(client.writes.last, (4, mode));
      }
      for (final fan in ['mute', 'low', 'middle', 'high', 'strong', 'auto']) {
        await performWidgetAction('fan', client);
        expect(client.writes.last, (5, fan));
      }
      final count = client.writes.length;
      await performWidgetAction('refresh', client);
      expect(client.writes.length, count);
    },
  );
  test(
    'Widget respects temperature limits, missing DPs and failed reads',
    () async {
      final client = WidgetClient();
      client.state = X5State({...client.state.dps, '2': 16});
      await performWidgetAction('down', client);
      client.state = X5State({...client.state.dps, '2': 30});
      await performWidgetAction('up', client);
      client.state = X5State({
        '1': false,
        '2': 23,
        '3': 28,
        '4': 'cold',
        '5': 'auto',
      });
      for (final action in ['display', 'sleep', 'swing']) {
        await performWidgetAction(action, client);
      }
      expect(client.writes, isEmpty);
      client.failRead = true;
      await expectLater(
        performWidgetAction('power', client),
        throwsFormatException,
      );
      expect(client.writes, isEmpty);
      final count = client.reads;
      await expectLater(
        performWidgetAction('eco', client),
        throwsArgumentError,
      );
      expect(client.reads, count);
    },
  );
  test('Widget service ignores malformed and foreign URLs', () {
    expect(widgetActionFromUri(null), isNull);
    expect(widgetActionFromUri(Uri.parse('https://widget/power')), isNull);
    expect(widgetActionFromUri(Uri.parse('mix5://widget/eco')), isNull);
    expect(widgetActionFromUri(Uri.parse('mix5://widget/power/extra')), isNull);
    expect(widgetActionFromUri(Uri.parse('mix5://widget/power')), 'power');
  });
}
