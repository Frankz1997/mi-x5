import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirage_x5/main.dart';
import 'package:mirage_x5/panel.dart';
import 'package:mirage_x5/x5.dart';
import 'package:mirage_x5/ui_style.dart';

final connection = X5Connection(
  '192.168.1.50',
  '0123456789abcdef',
  deviceId: 'demo-x5-device',
);

class FakeX5Client extends X5Client {
  FakeX5Client() : super(connection);

  X5State state = X5State({
    '1': false,
    '2': 23,
    '3': 28,
    '4': 'cold',
    '5': 'middle',
    '25': false,
    '31': 'off',
    '33': false,
    '36': true,
  });
  final reads = <Completer<X5State>>[];
  final commands = <(int, Object)>[];

  @override
  Future<X5State> read() {
    final read = Completer<X5State>();
    reads.add(read);
    return read.future;
  }

  @override
  Future<X5State> write(int dp, Object value) async {
    commands.add((dp, value));
    state = X5State({...state.dps, '$dp': value});
    return state;
  }

  @override
  Future<void> close() async {}
}

Future<void> showHome(WidgetTester tester, FakeX5Client client) async {
  await tester.binding.setSurfaceSize(const Size(420, 800));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });
  await tester.pumpWidget(
    MaterialApp(
      builder:
          (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
      home: X5Home(connection: connection, client: client, desktop: true),
    ),
  );
  client.reads.single.complete(client.state);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Vertical swing button updates state in both directions', (
    tester,
  ) async {
    final client = FakeX5Client();
    await showHome(tester, client);
    expect(
      tester
          .widget<X5IconButton>(
            find.byKey(const ValueKey('oscillation-button')),
          )
          .active,
      false,
    );

    await tester.tap(find.byKey(const ValueKey('oscillation-button')));
    await tester.pumpAndSettle();
    expect(client.commands, [(31, 'same')]);
    expect(
      tester
          .widget<X5IconButton>(
            find.byKey(const ValueKey('oscillation-button')),
          )
          .active,
      true,
    );

    await tester.tap(find.byKey(const ValueKey('oscillation-button')));
    await tester.pumpAndSettle();
    expect(client.commands, [(31, 'same'), (31, 'off')]);
    expect(
      tester
          .widget<X5IconButton>(
            find.byKey(const ValueKey('oscillation-button')),
          )
          .active,
      false,
    );
    expect(client.state.power, false);
    expect(find.text('Conectado'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Polling keeps controls and layout stable until data changes', (
    tester,
  ) async {
    final client = FakeX5Client();
    await showHome(tester, client);
    final panel = tester.widget<X5Panel>(find.byType(X5Panel));
    final footerPosition = tester.getTopLeft(
      find.byKey(const ValueKey('settings-button')),
    );

    await tester.pump(const Duration(seconds: 15));
    expect(client.reads, hasLength(2));
    expect(tester.widget<X5Panel>(find.byType(X5Panel)), same(panel));
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Conectado'), findsOneWidget);
    expect(
      tester
          .widget<X5IconButton>(find.byKey(const ValueKey('power-button')))
          .onPressed,
      isNotNull,
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('settings-button'))),
      footerPosition,
    );

    client.reads.last.complete(client.state);
    await tester.pumpAndSettle();
    expect(tester.widget<X5Panel>(find.byType(X5Panel)), same(panel));

    await tester.pump(const Duration(seconds: 15));
    expect(client.reads, hasLength(3));
    client.reads.last.complete(X5State({...client.state.dps, '2': 24}));
    await tester.pumpAndSettle();
    expect(find.text('24'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('settings-button'))),
      footerPosition,
    );
  });

  for (final failedRead in [false, true]) {
    testWidgets('A command waits for polling (read failure: $failedRead)', (
      tester,
    ) async {
      final client = FakeX5Client();
      await showHome(tester, client);
      final footerPosition = tester.getTopLeft(
        find.byKey(const ValueKey('settings-button')),
      );
      await tester.pump(const Duration(seconds: 15));

      await tester.tap(find.byKey(const ValueKey('power-button')));
      await tester.pump();
      expect(client.commands, isEmpty);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Sincronizando…'), findsOneWidget);
      expect(find.text('Conectado'), findsNothing);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('settings-button'))),
        footerPosition,
      );
      await tester.pump(const Duration(seconds: 15));
      expect(client.reads, hasLength(2));

      if (failedRead) {
        client.reads.last.completeError(const FormatException('Read failed'));
      } else {
        client.reads.last.complete(client.state);
      }
      await tester.pumpAndSettle();
      expect(client.commands, [(1, true)]);
      expect(
        tester
            .widget<X5IconButton>(find.byKey(const ValueKey('power-button')))
            .active,
        true,
      );
      expect(find.text('Read failed'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Sincronizando…'), findsNothing);
      expect(find.text('Conectado'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'Configuration replaces controls, restores them and keeps the stored key masked',
    (tester) async {
      final client = FakeX5Client();
      await showHome(tester, client);
      final size = tester.getSize(find.byKey(const ValueKey('panel-frame')));
      await tester.tap(find.byKey(const ValueKey('settings-button')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(const ValueKey('settings-screen')), findsOneWidget);
      expect(tester.getSize(find.byKey(const ValueKey('panel-frame'))), size);
      expect(find.byType(SwitchListTile), findsNothing);
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(const ValueKey('local-key')),
                matching: find.byType(EditableText),
              ),
            )
            .obscureText,
        true,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('show-key-button')));
      await tester.tap(find.byKey(const ValueKey('show-key-button')));
      await tester.pump();
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(const ValueKey('local-key')),
                matching: find.byType(EditableText),
              ),
            )
            .obscureText,
        false,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('settings-back')));
      await tester.tap(find.byKey(const ValueKey('settings-back')));
      await tester.pumpAndSettle();
      expect(find.text('Conectado'), findsOneWidget);
      expect(client.commands, isEmpty);
      if (client.reads.length > 1) {
        client.reads.last.complete(client.state);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const ValueKey('settings-button')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(const ValueKey('local-key')),
                matching: find.byType(EditableText),
              ),
            )
            .obscureText,
        true,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('controls-screen')), findsOneWidget);
    },
  );
}
