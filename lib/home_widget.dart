import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:home_widget/home_widget.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'connection_storage.dart';
import 'x5.dart';

const widgetProvider = 'MiX5Widget';
const widgetActions = {
  'refresh',
  'power',
  'down',
  'up',
  'mode',
  'fan',
  'sleep',
  'swing',
  'display',
};
const widgetFanOrder = ['auto', 'mute', 'low', 'middle', 'high', 'strong'];
const widgetOperationTimeout = Duration(seconds: 8);

// Read the actual device before toggling: the launcher can display an old snapshot.
Future<X5State> performWidgetAction(String action, X5Client client) async {
  if (!widgetActions.contains(action)) {
    throw ArgumentError('Acción desconocida.');
  }
  final state = await client.read().timeout(widgetOperationTimeout);
  final (int, Object)? command = switch (action) {
    'power' => (1, !state.power),
    'down' => (2, (state.temperature - 1).clamp(16, 30)),
    'up' => (2, (state.temperature + 1).clamp(16, 30)),
    'mode' => (
      4,
      modes.keys.elementAt(
        (modes.keys.toList().indexOf(state.mode) + 1) % modes.length,
      ),
    ),
    'fan' => (
      5,
      widgetFanOrder[(widgetFanOrder.indexOf(state.fan) + 1) %
          widgetFanOrder.length],
    ),
    'sleep' when state.dps['25'] is bool => (25, state.dps['25'] != true),
    'swing' when verticalSwings.containsKey(state.dps['31']) => (
      31,
      state.dps['31'] == 'same' ? 'off' : 'same',
    ),
    'display' when state.power && state.dps['36'] is bool => (
      36,
      state.dps['36'] != true,
    ),
    _ => null,
  };
  if (command == null || state.dps['${command.$1}'] == command.$2) return state;
  return client.write(command.$1, command.$2).timeout(widgetOperationTimeout);
}

abstract final class X5HomeWidget {
  static Future<void> publish({
    X5State? state,
    required bool configured,
    bool busy = false,
    String? message,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      final previous = await HomeWidget.getWidgetData<String>('snapshot');
      final data =
          previous == null
              ? <String, dynamic>{}
              : jsonDecode(previous) as Map<String, dynamic>;
      // Only display data goes to SharedPreferences; credentials stay in secure storage.
      if (state != null) {
        data['dps'] = state.dps;
        data['updated'] = DateTime.now().millisecondsSinceEpoch;
      }
      data['configured'] = configured;
      data['busy'] = busy;
      data['message'] = message;
      await HomeWidget.saveWidgetData('snapshot', jsonEncode(data));
      await HomeWidget.updateWidget(androidName: widgetProvider);
    } catch (_) {
      // A launcher failure must not prevent using the app's controls.
    }
  }
}

@pragma('vm:entry-point')
Future<void> widgetServiceMain(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('mi_x5/widget_service');
  try {
    final uri = arguments.length == 1 ? Uri.tryParse(arguments.single) : null;
    final action = widgetActionFromUri(uri);
    if (action != null) await _runWidgetAction(action);
  } finally {
    // Android holds the foreground service until this asynchronous operation finishes.
    await channel.invokeMethod<void>('completed');
  }
}

String? widgetActionFromUri(Uri? uri) {
  if (uri?.scheme != 'mix5' || uri?.host != 'widget') return null;
  final action = uri!.pathSegments.length == 1 ? uri.pathSegments.single : '';
  return widgetActions.contains(action) ? action : null;
}

Future<void> _runWidgetAction(String action) async {
  X5Client? client;
  try {
    final saved = await storage.read(key: storageKey);
    if (saved == null) {
      await X5HomeWidget.publish(
        configured: false,
        message: 'Configura Mi X5 en la app',
      );
      return;
    }
    await X5HomeWidget.publish(configured: true, busy: true);
    client = X5Client(X5Connection.decode(saved));
    final state = await performWidgetAction(action, client);
    await X5HomeWidget.publish(state: state, configured: true);
  } catch (_) {
    await X5HomeWidget.publish(
      configured: true,
      message: 'Sin conexión · toca para reintentar',
    );
  } finally {
    try {
      await client?.close().timeout(const Duration(seconds: 1));
    } catch (_) {
      // Cleanup cannot strand later clicks in a failed queue.
    }
  }
}
