// Render the real Flutter UI with public fixtures; never connect to a device.
// Run explicitly: flutter test tool/capture_docs.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirage_x5/main.dart';
import 'package:mirage_x5/panel.dart';
import 'package:mirage_x5/ui_style.dart';
import 'package:mirage_x5/x5.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final images = Directory('docs/images');
  final frames = Directory('build/docs-frames');
  setUpAll(() async {
    final font = await File('assets/RobotoCondensed-Regular.ttf').readAsBytes();
    await (FontLoader('RobotoCondensed')
      ..addFont(Future.value(font.buffer.asByteData()))).load();
    await images.create(recursive: true);
    await frames.create(recursive: true);
  });
  testWidgets('Render documentation using simulated device data', (
    tester,
  ) async {
    final boundary = GlobalKey();
    late StateSetter update;
    var settings = false;
    var state = X5State({
      '1': true,
      '2': 23,
      '3': 25,
      '4': 'cold',
      '5': 'auto',
      '25': false,
      '31': 'same',
      '36': true,
    });

    Future<void> capture(String path, {double scale = 2}) async {
      await tester.runAsync(() async {
        final image = await (boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage(pixelRatio: scale);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(path).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    Future<void> show({required bool desktop, bool configuring = false}) async {
      await tester.pumpWidget(const SizedBox());
      settings = configuring;
      await tester.binding.setSurfaceSize(
        desktop ? const Size(500, 540) : const Size(360, 780),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: X5Style.theme,
          debugShowCheckedModeBanner: false,
          home: RepaintBoundary(
            key: boundary,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xffd5d7cc),
                    Color(0xffb5c0bd),
                    Color(0xff777d65),
                  ],
                ),
              ),
              child: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return X5Panel(
                    state: state,
                    connected: true,
                    configured: true,
                    busy: false,
                    desktop: desktop,
                    settings: () => update(() => settings = true),
                    refresh: () {},
                    write:
                        (dp, value) async => update(
                          () => state = X5State({...state.dps, '$dp': value}),
                        ),
                    settingsContent:
                        settings
                            ? ConnectionSettings(
                              connection: X5Connection(
                                '192.168.1.50',
                                '0123456789abcdef',
                                deviceId: 'demo-x5-device',
                              ),
                              onBack: () => update(() => settings = false),
                              onSaved: (_) async {},
                            )
                            : null,
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => precacheImage(
          const AssetImage('assets/mini-split.png'),
          tester.element(find.byType(X5Panel)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 1200));
    }

    await show(desktop: true);
    await capture('${images.path}/windows.png');
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(0, 0));
    final fanCenter = tester.getCenter(
      find.byKey(const ValueKey('fan-button')),
    );
    await mouse.moveTo(fanCenter);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester.getSize(find.byKey(const ValueKey('fan-card'))).width,
      greaterThan(
        tester.getSize(find.byKey(const ValueKey('mode-card'))).width,
      ),
    );
    await capture('${images.path}/windows-fan.png');
    await mouse.moveTo(const Offset(20, 20));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    update(() => state = X5State({...state.dps, '1': false}));
    await tester.pump(const Duration(milliseconds: 1200));
    for (var frame = 0; frame < 72; frame++) {
      if (frame == 6) {
        await tester.tap(find.byKey(const ValueKey('power-button')));
      }
      if (frame == 36) await mouse.moveTo(fanCenter);
      if (frame == 58) await mouse.moveTo(const Offset(20, 20));
      await tester.pump(const Duration(milliseconds: 83));
      await capture(
        '${frames.path}/${frame.toString().padLeft(3, '0')}.png',
        scale: 1,
      );
    }
    await mouse.removePointer();
    await show(desktop: false);
    await capture('${images.path}/android.png');
    await show(desktop: false, configuring: true);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('device-id')))
          .controller!
          .text,
      'demo-x5-device',
    );
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(const ValueKey('local-key')),
              matching: find.byType(EditableText),
            ),
          )
          .obscureText,
      isTrue,
    );
    await capture('${images.path}/settings.png');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });
}
