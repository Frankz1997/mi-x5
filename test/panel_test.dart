import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirage_x5/ac_scene.dart';
import 'package:mirage_x5/main.dart';
import 'package:mirage_x5/panel.dart';
import 'package:mirage_x5/panel_geometry.dart';
import 'package:mirage_x5/x5.dart';
import 'package:mirage_x5/ui_style.dart';

final initial = X5State({
  '1': true,
  '2': 23,
  '3': 23,
  '4': 'cold',
  '5': 'auto',
  '25': false,
  '31': 'same',
  '36': true,
});

Future<void> savePreview(
  WidgetTester tester,
  GlobalKey boundary,
  String name,
) async {
  final directory = Platform.environment['MIRAGE_PREVIEW_DIR'];
  if (directory == null) return;
  await tester.runAsync(() async {
    await Directory(directory).create(recursive: true);
    final image = await (boundary.currentContext!.findRenderObject()
            as RenderRepaintBoundary)
        .toImage(pixelRatio: 2);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$directory/$name.png').writeAsBytes(png!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final bytes =
        await File('assets/RobotoCondensed-Regular.ttf').readAsBytes();
    await (FontLoader('RobotoCondensed')
      ..addFont(Future.value(bytes.buffer.asByteData()))).load();
  });

  test(
    'Tray placement follows all four edges, stays in the work area and handles a second monitor',
    () {
      const work = Rect.fromLTWH(0, 40, 1920, 1000);
      const size = Size(500, 540);
      for (final (edge, icon) in [
        (TrayEdge.top, const Rect.fromLTWH(1700, 0, 24, 24)),
        (TrayEdge.bottom, const Rect.fromLTWH(1700, 1050, 24, 24)),
        (TrayEdge.left, const Rect.fromLTWH(-30, 900, 24, 24)),
        (TrayEdge.right, const Rect.fromLTWH(1930, 900, 24, 24)),
      ]) {
        final placement = trayPanelPlacement(icon, work, size);
        expect(placement.edge, edge);
        final bounds = placement.position & size;
        expect(
          bounds.left >= work.left &&
              bounds.top >= work.top &&
              bounds.right <= work.right &&
              bounds.bottom <= work.bottom,
          true,
        );
        final path = panelOutline(const Size(484, 524), edge, placement.anchor);
        expect(path.contains(const Offset(242, 262)), true);
        expect(path.getBounds().width, closeTo(482, .1));
        expect(path.getBounds().height, closeTo(522, .1));
      }
      final second = trayPanelPlacement(
        const Rect.fromLTWH(-20, 0, 20, 24),
        const Rect.fromLTWH(-1920, 24, 1920, 1056),
        size,
      );
      expect(second.edge, TrayEdge.top);
      expect(second.position.dx, -500);
      for (final edge in TrayEdge.values) {
        final horizontal = edge == TrayEdge.top || edge == TrayEdge.bottom;
        final anchor = horizontal ? 242.0 : 262.0;
        final point = switch (edge) {
          TrayEdge.top => Offset(anchor, 2),
          TrayEdge.bottom => Offset(anchor, 522),
          TrayEdge.left => Offset(2, anchor),
          TrayEdge.right => Offset(482, anchor),
        };
        expect(
          panelOutline(const Size(484, 524), edge, .5).contains(point),
          true,
        );
      }
    },
  );

  test(
    'Native backdrop follows the rounded panel and pointer with fractional coordinates',
    () {
      const window = Size(500, 540);
      for (final edge in TrayEdge.values) {
        final coordinates = backdropOutline(window, edge, .5);
        expect(coordinates.length.isEven, true);
        expect(
          coordinates.any((value) => value != value.roundToDouble()),
          true,
        );
        final vertices = <Offset>[];
        for (var i = 0; i < coordinates.length; i += 2) {
          vertices.add(Offset(coordinates[i], coordinates[i + 1]));
        }
        final sampled = Path()..addPolygon(vertices, true);
        final panel = panelOutline(
          const Size(484, 524),
          edge,
          .5,
        ).shift(const Offset(8, 8));
        final bounds = sampled.getBounds();
        expect(bounds.left, closeTo(panel.getBounds().left, .3));
        expect(bounds.top, closeTo(panel.getBounds().top, .3));
        expect(bounds.right, closeTo(panel.getBounds().right, .3));
        expect(bounds.bottom, closeTo(panel.getBounds().bottom, .3));
        expect(sampled.contains(const Offset(250, 270)), true);
        for (final corner in const [
          Offset(10, 10),
          Offset(490, 10),
          Offset(10, 530),
          Offset(490, 530),
        ]) {
          expect(sampled.contains(corner), false);
        }
        final tip = switch (edge) {
          TrayEdge.top => const Offset(250, 10),
          TrayEdge.bottom => const Offset(250, 530),
          TrayEdge.left => const Offset(10, 270),
          TrayEdge.right => const Offset(490, 270),
        };
        expect(sampled.contains(tip), true);
      }
    },
  );

  for (final width in [360.0, 420.0, 500.0]) {
    testWidgets(
      'Approved UI sends the correct Wi-Fi commands at width $width',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 540));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final boundary = GlobalKey();
        final commands = <(int, Object)>[];
        var state = initial;
        await tester.pumpWidget(
          MaterialApp(
            theme: X5Style.theme,
            builder:
                (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(disableAnimations: true),
                  child: child!,
                ),
            home: StatefulBuilder(
              builder:
                  (context, update) => RepaintBoundary(
                    key: boundary,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Color(0xffd5d5cf),
                            Color(0xffb6c0c2),
                            Color(0xff6b705b),
                          ],
                        ),
                      ),
                      child: X5Panel(
                        state: state,
                        connected: true,
                        configured: true,
                        busy: false,
                        desktop: true,
                        settings: () {},
                        refresh: () {},
                        write: (dp, value) async {
                          commands.add((dp, value));
                          update(
                            () => state = X5State({...state.dps, '$dp': value}),
                          );
                        },
                      ),
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
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(PopupMenuButton<String>), findsNothing);
        expect(find.byType(SwitchListTile), findsNothing);
        if (width == 500) await savePreview(tester, boundary, 'controls');
        await tester.tap(find.byKey(const ValueKey('display-button')));
        await tester.pumpAndSettle();
        expect(commands.last, (36, false));
        await tester.tap(find.byKey(const ValueKey('sleep-button')));
        await tester.pumpAndSettle();
        expect(commands.last, (25, true));
        await tester.tap(find.byKey(const ValueKey('oscillation-button')));
        await tester.pumpAndSettle();
        expect(commands.last, (31, 'off'));
        await tester.tap(find.byKey(const ValueKey('temperature-down')));
        await tester.pumpAndSettle();
        expect(commands.last, (2, 22));
        await tester.tap(find.byKey(const ValueKey('temperature-up')));
        await tester.pumpAndSettle();
        expect(commands.last, (2, 23));
        await tester.tap(find.byKey(const ValueKey('mode-button')));
        await tester.pumpAndSettle();
        final modeWidth =
            tester.getSize(find.byKey(const ValueKey('mode-card'))).width;
        expect(
          modeWidth >
              tester.getSize(find.byKey(const ValueKey('fan-card'))).width,
          true,
        );
        for (final mode in ['auto', 'wet', 'wind', 'cold']) {
          await tester.tap(find.byKey(ValueKey('mode-$mode')));
          await tester.pumpAndSettle();
          expect(commands.last, (4, mode));
        }
        await tester.tap(find.byKey(const ValueKey('fan-button')));
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.byKey(const ValueKey('fan-card'))).width >
              tester.getSize(find.byKey(const ValueKey('mode-card'))).width,
          true,
        );
        for (var i = 1; i < 6; i++) {
          final slider = tester.widget<Slider>(find.byType(Slider).last);
          slider.onChanged!(i.toDouble());
          slider.onChangeEnd!(i.toDouble());
          await tester.pumpAndSettle();
          expect(commands.last, (
            5,
            ['auto', 'mute', 'low', 'middle', 'high', 'strong'][i],
          ));
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('power-button')));
        await tester.pumpAndSettle();
        expect(commands.last, (1, false));
        expect(
          tester
              .widget<TextButton>(find.byKey(const ValueKey('display-button')))
              .onPressed,
          isNull,
        );
        expect(state.dps['36'], false);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'Hover morph closes on exit and keyboard Escape restores both card widths',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 540));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: X5Style.theme,
          home: X5Panel(
            state: X5State({...initial.dps, '1': false}),
            connected: true,
            configured: true,
            busy: false,
            desktop: true,
            settings: () {},
            refresh: () {},
            write: (_, __) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final before = tester.getRect(find.byKey(const ValueKey('fan-card')));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(before.center);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 420));
      final expanded = tester.getRect(find.byKey(const ValueKey('fan-card')));
      expect(expanded.width > before.width, true);
      expect(expanded.top, before.top);
      expect(expanded.height, before.height);
      final fanHeader = tester.widget<TextButton>(
        find.byKey(const ValueKey('fan-button')),
      );
      expect(
        fanHeader.style!.overlayColor!.resolve({WidgetState.hovered}),
        Colors.transparent,
      );
      expect(
        fanHeader.style!.mouseCursor!.resolve({WidgetState.hovered}),
        SystemMouseCursors.basic,
      );
      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const ValueKey('fan-card'))).width,
        closeTo(before.width, .1),
      );
      tester
          .widget<TextButton>(find.byKey(const ValueKey('mode-button')))
          .focusNode!
          .requestFocus();
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const ValueKey('mode-card'))).width >
            before.width,
        true,
      );
      final modeHeader = tester.widget<TextButton>(
        find.byKey(const ValueKey('mode-button')),
      );
      expect(
        modeHeader.style!.overlayColor!.resolve({WidgetState.hovered}),
        Colors.transparent,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const ValueKey('mode-card'))).width,
        closeTo(before.width, .1),
      );
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Animated settings never paints over controls and preserves the scene on return',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 540));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final boundary = GlobalKey();
      var configuring = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: X5Style.theme,
          home: StatefulBuilder(
            builder:
                (context, update) => RepaintBoundary(
                  key: boundary,
                  child: X5Panel(
                    state: initial,
                    connected: true,
                    configured: true,
                    busy: false,
                    desktop: true,
                    settings: () => update(() => configuring = true),
                    refresh: () {},
                    write: (_, __) async {},
                    settingsContent:
                        configuring
                            ? ConnectionSettings(
                              connection: X5Connection(
                                '192.168.1.50',
                                '0123456789abcdef',
                                deviceId: 'demo-x5-device',
                              ),
                              onBack: () => update(() => configuring = false),
                              onSaved: (_) async {},
                            )
                            : null,
                  ),
                ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      final scene = tester.state(find.byType(AcScene));
      final frameSize = tester.getSize(
        find.byKey(const ValueKey('panel-frame')),
      );
      for (var cycle = 0; cycle < 2; cycle++) {
        await tester.tap(find.byKey(const ValueKey('settings-button')));
        await tester.pump();
        expect(find.byKey(const ValueKey('controls-screen')), findsNothing);
        expect(find.text('Habitación  '), findsNothing);
        expect(
          tester.state(find.byType(AcScene, skipOffstage: false)),
          same(scene),
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Configuración'), findsOneWidget);
        expect(find.text('Conectado'), findsNothing);
        expect(
          tester.getSize(find.byKey(const ValueKey('panel-frame'))),
          frameSize,
        );
        if (cycle == 0) await savePreview(tester, boundary, 'settings-opened');
        await tester.tap(find.byKey(const ValueKey('settings-back')));
        await tester.pump();
        expect(find.text('Configuración'), findsNothing);
        expect(find.byKey(const ValueKey('controls-screen')), findsOneWidget);
        expect(tester.state(find.byType(AcScene)), same(scene));
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Panel matches the HTML tint over a light backdrop without an outline',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 540));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: X5Style.theme,
          home: RepaintBoundary(
            key: boundary,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: ColoredBox(color: Colors.black)),
                    Expanded(child: ColoredBox(color: Color(0xffd5d5cf))),
                  ],
                ),
                X5Panel(
                  connected: false,
                  configured: false,
                  busy: false,
                  desktop: true,
                  settings: () {},
                  refresh: () {},
                  write: (_, __) async {},
                  settingsContent: const SizedBox.expand(),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final pixels = await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        image.dispose();
        return data!;
      });
      for (var channel = 0; channel < 3; channel++) {
        final overBlack = pixels!.getUint8((200 * 500 + 125) * 4 + channel);
        final overWhite = pixels.getUint8((200 * 500 + 375) * 4 + channel);
        expect(overWhite, closeTo([63, 64, 60][channel], 2));
        expect((overWhite - overBlack).abs(), greaterThan(45));
        final edge = pixels.getUint8((200 * 500 + 9) * 4 + channel);
        expect(edge, lessThan(20));
        final outsideBlack = pixels.getUint8(channel);
        final outsideWhite = pixels.getUint8(499 * 4 + channel);
        expect((outsideWhite - outsideBlack).abs(), greaterThan(200));
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Settings has no duplicate display control and renders within the same panel',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 540));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: X5Style.theme,
          builder:
              (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: child!,
              ),
          home: RepaintBoundary(
            key: boundary,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xffd5d5cf),
                    Color(0xffb6c0c2),
                    Color(0xff6b705b),
                  ],
                ),
              ),
              child: X5Panel(
                state: initial,
                connected: true,
                configured: true,
                busy: false,
                desktop: true,
                settings: () {},
                refresh: () {},
                write: (_, __) async {},
                settingsContent: ConnectionSettings(
                  connection: X5Connection(
                    '192.168.1.50',
                    '0123456789abcdef',
                    deviceId: 'demo-x5-device',
                  ),
                  onBack: () {},
                  onSaved: (_) async {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(SwitchListTile), findsNothing);
      await savePreview(tester, boundary, 'settings');
      await tester.pumpWidget(const SizedBox());
    },
  );
}
