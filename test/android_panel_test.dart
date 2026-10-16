import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirage_x5/panel.dart';
import 'package:mirage_x5/main.dart';
import 'package:mirage_x5/ui_style.dart';
import 'package:mirage_x5/x5.dart';
import 'panel_test.dart' show savePreview;

void main() {
  setUpAll(() async {
    final bytes =
        await File('assets/RobotoCondensed-Regular.ttf').readAsBytes();
    await (FontLoader('RobotoCondensed')
      ..addFont(Future.value(bytes.buffer.asByteData()))).load();
  });
  for (final size in [
    const Size(360, 780),
    const Size(320, 568),
    const Size(780, 360),
  ]) {
    testWidgets('Android touch UI, selectors and settings fit $size', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var state = X5State({
        '1': true,
        '2': 23,
        '3': 28,
        '4': 'cold',
        '5': 'auto',
        '25': false,
        '31': 'same',
        '36': true,
      });
      var settings = false;
      final boundary = GlobalKey();
      final commands = <(int, Object)>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: X5Style.theme,
          builder:
              (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: child!,
              ),
          home: StatefulBuilder(
            builder:
                (context, update) => RepaintBoundary(
                  key: boundary,
                  child: X5Panel(
                    desktop: false,
                    state: state,
                    connected: true,
                    configured: true,
                    busy: false,
                    settings: () => update(() => settings = true),
                    refresh: () {},
                    write: (dp, value) async {
                      commands.add((dp, value));
                      update(
                        () => state = X5State({...state.dps, '$dp': value}),
                      );
                    },
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
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        X5Style.mobileBackground,
      );
      expect(tester.getSize(find.byKey(const ValueKey('panel-frame'))), size);
      if (size.width == 360) {
        await savePreview(tester, boundary, 'android-controls');
      }
      await tester.ensureVisible(find.byKey(const ValueKey('fan-button')));
      await tester.tap(find.byKey(const ValueKey('fan-button')));
      await tester.pumpAndSettle();
      final fanSlider = find.byType(Slider).last;
      final slider = tester.widget<Slider>(fanSlider);
      slider.onChanged!(5);
      slider.onChangeEnd!(5);
      await tester.pumpAndSettle();
      expect(commands.last, (5, 'strong'));
      if (size.width == 360) await savePreview(tester, boundary, 'android-fan');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const ValueKey('fan-card'))).width,
        closeTo(
          tester.getSize(find.byKey(const ValueKey('mode-card'))).width,
          .1,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('mode-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mode-wet')));
      await tester.pumpAndSettle();
      expect(commands.last, (4, 'wet'));
      await tester.ensureVisible(find.byKey(const ValueKey('settings-button')));
      await tester.tap(find.byKey(const ValueKey('settings-button')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('fan-button')).hitTestable(),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('local-key')), findsOneWidget);
      if (size.width == 360) {
        await savePreview(tester, boundary, 'android-settings');
      }
      final save = find.widgetWithText(FilledButton, 'Comprobar y guardar');
      expect(save.hitTestable(), findsOneWidget);
      await tester.binding.setSurfaceSize(
        Size(size.width, size.height > 500 ? size.height - 280 : 250),
      );
      await tester.pumpAndSettle();
      expect(save.hitTestable(), findsOneWidget);
      expect(
        tester.getBottomRight(save).dy,
        lessThanOrEqualTo(
          tester.getBottomRight(find.byKey(const ValueKey('panel-frame'))).dy,
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.binding.setSurfaceSize(size);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('settings-back')));
      await tester.tap(find.byKey(const ValueKey('settings-back')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('controls-screen')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
