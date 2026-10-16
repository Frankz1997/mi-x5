import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'panel_geometry.dart';

class DesktopShell with TrayListener, WindowListener {
  static const panelSize = Size(500, 540);
  static final placement = ValueNotifier<TrayPlacement?>(null);
  static final panelVisible = ValueNotifier<bool>(false);
  static const _window = MethodChannel('mi_x5/window');

  Future<void> start() async {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: panelSize,
        skipTaskbar: true,
        backgroundColor: Colors.transparent,
        titleBarStyle: TitleBarStyle.hidden,
        windowButtonVisibility: false,
        title: 'Mi X5',
      ),
    );
    await windowManager.setAsFrameless();
    await windowManager.setResizable(false);
    await windowManager.setPreventClose(true);
    await windowManager.setAlwaysOnTop(true);
    await trayManager.setIcon(
      Platform.isWindows ? 'assets/tray.ico' : 'assets/tray.png',
      isTemplate: Platform.isMacOS,
    );
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'show', label: 'Abrir controles'),
          MenuItem.separator(),
          MenuItem(key: 'exit', label: 'Salir de Mi X5'),
        ],
      ),
    );
    trayManager.addListener(this);
    windowManager.addListener(this);
    await windowManager.hide();
  }

  Future<void> showPanel() async {
    final bounds = await trayManager.getBounds();
    final displays = await screenRetriever.getAllDisplays();
    final display = displays.firstWhere(
      (d) => Rect.fromLTWH(
        d.visiblePosition?.dx ?? 0,
        d.visiblePosition?.dy ?? 0,
        d.visibleSize?.width ?? d.size.width,
        d.visibleSize?.height ?? d.size.height,
      ).inflate(80).contains(bounds?.center ?? Offset.zero),
      orElse: () => displays.first,
    );
    final workArea = Rect.fromLTWH(
      display.visiblePosition?.dx ?? 0,
      display.visiblePosition?.dy ?? 0,
      display.visibleSize?.width ?? display.size.width,
      display.visibleSize?.height ?? display.size.height,
    );
    final actualSize = Size(
      panelSize.width.clamp(0, workArea.width),
      panelSize.height.clamp(0, workArea.height),
    );
    final next = trayPanelPlacement(
      bounds ??
          Rect.fromLTWH(
            workArea.right - 24,
            Platform.isMacOS ? workArea.top : workArea.bottom,
            24,
            0,
          ),
      workArea,
      actualSize,
    );
    placement.value = next;
    await windowManager.setSize(actualSize);
    await windowManager.setPosition(next.position);
    if (Platform.isWindows) {
      try {
        final applied = await _window.invokeMethod<bool>(
          'setBlur',
          backdropOutline(actualSize, next.edge, next.anchor),
        );
        assert(() {
          debugPrint('Mi X5: blur recortado activo = $applied');
          return true;
        }());
        if (applied != true) {
          debugPrint('No se pudo aplicar el difuminado de Windows.');
        }
      } on PlatformException {
        debugPrint('No se pudo aplicar el difuminado de Windows.');
      } on MissingPluginException {
        debugPrint('El difuminado requiere recompilar la app de Windows.');
      }
    }
    panelVisible.value = true;
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  void onTrayIconMouseDown() => unawaited(showPanel());

  @visibleForTesting
  Future<bool> capturePanelReview() async =>
      await _window.invokeMethod<bool>('capturePanelReview') ?? false;

  @override
  void onTrayIconRightMouseDown() => unawaited(trayManager.popUpContextMenu());

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show') unawaited(showPanel());
    if (menuItem.key == 'exit') unawaited(_exit());
  }

  Future<void> _exit() async {
    await trayManager.destroy();
    await windowManager.destroy();
  }

  @override
  void onWindowClose() {
    panelVisible.value = false;
    unawaited(windowManager.hide());
  }

  @override
  void onWindowBlur() {
    panelVisible.value = false;
    unawaited(windowManager.hide());
  }
}
