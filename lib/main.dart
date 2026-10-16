import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';

import 'x5.dart';
import 'panel.dart';
import 'desktop_shell.dart';
import 'ui_style.dart';
import 'connection_storage.dart';
import 'home_widget.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
  }
  X5Connection? connection;
  String? startupError;
  try {
    final saved = await storage.read(key: storageKey);
    final setup = saved;
    if (setup != null) {
      connection = X5Connection.decode(setup);
    }
  } catch (_) {
    startupError =
        'No se pudo abrir la configuración guardada. Vuelve a configurar la conexión.';
  }
  final desktop = Platform.isWindows || Platform.isMacOS;
  runApp(
    X5App(connection: connection, startupError: startupError, desktop: desktop),
  );
  if (desktop) {
    try {
      await DesktopShell().start();
    } catch (_) {
      await windowManager.show();
    }
  }
}

class X5App extends StatelessWidget {
  final X5Connection? connection;
  final String? startupError;
  final bool desktop;
  const X5App({
    super.key,
    this.connection,
    this.startupError,
    this.desktop = false,
  });

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Mi X5',
    debugShowCheckedModeBanner: false,
    builder:
        (_, child) => TooltipVisibility(
          visible: false,
          child: ValueListenableBuilder<bool>(
            valueListenable: DesktopShell.panelVisible,
            builder:
                (_, visible, __) =>
                    TickerMode(enabled: !desktop || visible, child: child!),
          ),
        ),
    theme: X5Style.theme,
    home: X5Home(
      connection: connection,
      startupError: startupError,
      desktop: desktop,
    ),
  );
}

class X5Home extends StatefulWidget {
  final X5Connection? connection;
  @visibleForTesting
  final X5Client? client;
  final String? startupError;
  final bool desktop;
  const X5Home({
    super.key,
    this.connection,
    this.client,
    this.startupError,
    this.desktop = false,
  });

  @override
  State<X5Home> createState() => _X5HomeState();
}

class _X5HomeState extends State<X5Home> with WidgetsBindingObserver {
  X5Connection? _connection;
  X5Client? _client;
  X5State? _state;
  String? _error;
  bool _busy = false;
  bool _online = false;
  bool _configuring = false;
  bool _foreground = true;
  Future<void>? _updating;
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _connection = widget.connection;
    _error = widget.startupError;
    if (_connection != null) {
      _client = widget.client ?? X5Client(_connection!);
      unawaited(_update());
    } else {
      unawaited(X5HomeWidget.publish(configured: false));
    }
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_foreground) unawaited(_update());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) unawaited(_update());
  }

  @override
  void dispose() {
    _timer.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (_client != null) unawaited(_client!.close());
    super.dispose();
  }

  Future<void> _update([int? dp, Object? value]) async {
    if (_busy || _configuring || _client == null) return;
    if (dp == null && _updating != null) return;
    final busy = dp != null || _state == null;
    if (busy) setState(() => _busy = true);
    if (busy) await X5HomeWidget.publish(configured: true, busy: true);
    // Wait for a background read so a user's command is never dropped.
    if (_updating != null) await _updating;
    if (!mounted) return;
    final completed = Completer<void>();
    _updating = completed.future;
    try {
      final state =
          dp == null ? await _client!.read() : await _client!.write(dp, value!);
      await X5HomeWidget.publish(state: state, configured: true);
      if (!mounted) return;
      if (!_online || _error != null || !mapEquals(_state?.dps, state.dps)) {
        setState(() {
          _state = state;
          _online = true;
          _error = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      final error =
          e is FormatException
              ? e.message
              : 'No se pudo conectar. Comprueba que estás en la misma red que el X5.';
      unawaited(
        X5HomeWidget.publish(
          configured: true,
          message: 'Sin conexión · toca para reintentar',
        ),
      );
      if (_online || _error != error) {
        setState(() {
          _online = false;
          _error = error;
        });
      }
    } finally {
      _updating = null;
      if (mounted && busy) setState(() => _busy = false);
      completed.complete();
    }
  }

  void _settings() {
    if (!_busy) setState(() => _configuring = true);
  }

  void _cancelSettings() {
    setState(() => _configuring = false);
    unawaited(_update());
  }

  Future<void> _saveSettings(X5Connection result) async {
    if (_updating != null) await _updating;
    if (!mounted) return;
    if (_client != null) await _client!.close();
    if (!mounted) return;
    setState(() {
      _connection = result;
      _client = X5Client(result);
      _state = null;
      _online = false;
      _configuring = false;
    });
    await _update();
  }

  @override
  Widget build(BuildContext context) => X5Panel(
    state: _state,
    connected: _online,
    configured: _connection != null,
    busy: _busy,
    desktop: widget.desktop,
    error: _error,
    settings: _settings,
    refresh: _update,
    write: (dp, value) => _update(dp, value),
    settingsContent:
        _configuring
            ? ConnectionSettings(
              connection: _connection,
              onBack: _cancelSettings,
              onSaved: _saveSettings,
            )
            : null,
  );
}

class ConnectionSettings extends StatefulWidget {
  final X5Connection? connection;
  final VoidCallback onBack;
  final Future<void> Function(X5Connection) onSaved;
  const ConnectionSettings({
    super.key,
    this.connection,
    required this.onBack,
    required this.onSaved,
  });
  @override
  State<ConnectionSettings> createState() => _ConnectionSettingsState();
}

class _ConnectionSettingsState extends State<ConnectionSettings> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _deviceId;
  late final TextEditingController _ip;
  late final TextEditingController _key;
  bool _showKey = false;
  bool _saving = false;
  String? _error;
  bool _canPinWidget = false;

  @override
  void initState() {
    super.initState();
    _deviceId = TextEditingController(text: widget.connection?.deviceId);
    _ip = TextEditingController(text: widget.connection?.ip);
    _key = TextEditingController(text: widget.connection?.key);
    if (Platform.isAndroid) unawaited(_checkWidgetSupport());
  }

  Future<void> _checkWidgetSupport() async {
    final supported = await HomeWidget.isRequestPinWidgetSupported();
    if (mounted) setState(() => _canPinWidget = supported == true);
  }

  Future<void> _pinWidget() async {
    if (_canPinWidget) {
      await HomeWidget.requestPinWidget(androidName: widgetProvider);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Mantén pulsada la pantalla de inicio → Widgets → Mi X5.',
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _deviceId.dispose();
    _ip.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _showKey = false;
      _error = null;
    });
    X5Client? probe;
    try {
      final connection = X5Connection(
        _ip.text.trim(),
        _key.text,
        deviceId: _deviceId.text.trim(),
      );
      probe = X5Client(connection);
      await probe.read();
      if (!mounted) return;
      await storage.write(key: storageKey, value: connection.encode());
      await probe.close();
      probe = null;
      if (mounted) await widget.onSaved(connection);
    } catch (e) {
      if (mounted) {
        setState(
          () =>
              _error =
                  e is FormatException
                      ? e.message
                      : 'No se pudo guardar la conexión.',
        );
      }
    } finally {
      await probe?.close();
      if (mounted) setState(() => _saving = false);
    }
  }

  void _back() {
    if (_saving) return;
    setState(() => _showKey = false);
    widget.onBack();
  }

  InputDecoration _decoration(X5Glyph glyph, String hint, {Widget? suffix}) =>
      InputDecoration(
        filled: true,
        fillColor: Platform.isAndroid ? X5Style.mobileSurface : X5Style.surface,
        helperText: hint,
        helperStyle: const TextStyle(color: X5Style.muted, fontSize: 12),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 13,
        ),
        prefixIcon: Padding(
          padding: const EdgeInsets.all(13),
          child: X5Icon(glyph, size: 18),
        ),
        suffixIcon: suffix,
        border: OutlineInputBorder(
          borderRadius: X5Style.radius,
          borderSide: const BorderSide(color: X5Style.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: X5Style.radius,
          borderSide: const BorderSide(color: X5Style.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: X5Style.radius,
          borderSide: const BorderSide(color: X5Style.accent),
        ),
      );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _back();
    },
    child: CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _back},
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder:
              (_, constraints) => Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                X5IconButton(
                                  key: const ValueKey('settings-back'),
                                  label: 'Volver a los controles',
                                  glyph: X5Glyph.back,
                                  onPressed: _saving ? null : _back,
                                ),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'MI X5',
                                        style: TextStyle(
                                          color: X5Style.muted,
                                          fontSize: 10,
                                          letterSpacing: 2,
                                        ),
                                      ),
                                      Text(
                                        'Configuración',
                                        style: TextStyle(
                                          color: X5Style.text,
                                          fontSize: 26,
                                          height: 30 / 26,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Configura el equipo en tu red de casa.',
                              style: TextStyle(
                                color: X5Style.muted,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 22),
                            const Text(
                              'ID del dispositivo',
                              style: TextStyle(
                                color: X5Style.text,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              key: const ValueKey('device-id'),
                              controller: _deviceId,
                              enabled: !_saving,
                              autocorrect: false,
                              enableSuggestions: false,
                              style: const TextStyle(
                                fontFamily: 'RobotoCondensed',
                                color: X5Style.text,
                                fontSize: 16,
                              ),
                              decoration: _decoration(
                                X5Glyph.swing,
                                'Identificador de tu equipo en Tuya.',
                              ),
                              validator:
                                  (v) =>
                                      isValidDeviceId(v?.trim() ?? '')
                                          ? null
                                          : 'Introduce el ID del dispositivo.',
                            ),
                            const SizedBox(height: 18),
                            const Text(
                              'IP local',
                              style: TextStyle(
                                color: X5Style.text,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              key: const ValueKey('local-ip'),
                              controller: _ip,
                              enabled: !_saving,
                              style: const TextStyle(
                                fontFamily: 'RobotoCondensed',
                                color: X5Style.text,
                                fontSize: 16,
                              ),
                              decoration: _decoration(
                                X5Glyph.wifi,
                                'Dirección del minisplit en tu red.',
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              validator:
                                  (v) =>
                                      isPrivateIpv4(v?.trim() ?? '')
                                          ? null
                                          : 'Introduce una IP local válida.',
                            ),
                            const SizedBox(height: 18),
                            const Text(
                              'Clave local',
                              style: TextStyle(
                                color: X5Style.text,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              key: const ValueKey('local-key'),
                              controller: _key,
                              enabled: !_saving,
                              obscureText: !_showKey,
                              autocorrect: false,
                              enableSuggestions: false,
                              style: const TextStyle(
                                fontFamily: 'RobotoCondensed',
                                color: X5Style.text,
                                fontSize: 16,
                              ),
                              decoration: _decoration(
                                X5Glyph.key,
                                'Clave de 16 caracteres del equipo.',
                                suffix: X5IconButton(
                                  key: const ValueKey('show-key-button'),
                                  label:
                                      _showKey
                                          ? 'Ocultar clave'
                                          : 'Mostrar clave',
                                  glyph: X5Glyph.eye,
                                  size: 19,
                                  active: _showKey,
                                  onPressed:
                                      _saving
                                          ? null
                                          : () => setState(
                                            () => _showKey = !_showKey,
                                          ),
                                ),
                              ),
                              validator:
                                  (v) =>
                                      v != null &&
                                              v.length == 16 &&
                                              v.codeUnits.every(
                                                (c) => c >= 32 && c <= 126,
                                              )
                                          ? null
                                          : 'La clave debe tener 16 caracteres.',
                              onFieldSubmitted: (_) {
                                if (!_saving) _save();
                              },
                            ),
                            if (_error != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: Text(
                                  _error!,
                                  style: const TextStyle(
                                    color: Color(0xffedb5a9),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 18),
                            const Text(
                              'La clave se guarda protegida en este dispositivo.',
                              style: TextStyle(
                                color: X5Style.muted,
                                fontSize: 12,
                              ),
                            ),
                            if (Platform.isAndroid) ...[
                              const SizedBox(height: 16),
                              OutlinedButton.icon(
                                onPressed: _saving ? null : _pinWidget,
                                icon: const X5Icon(X5Glyph.plus, size: 16),
                                label: const Text('Agregar widget'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 22),
                      child: Column(
                        children: [
                          const Divider(color: Color(0x18ffffff), height: 1),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _saving ? null : _back,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: X5Style.muted,
                                    side: const BorderSide(
                                      color: X5Style.border,
                                    ),
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: X5Style.radius,
                                    ),
                                    minimumSize: const Size(0, 44),
                                  ),
                                  child: const Text('Volver'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: FilledButton(
                                  onPressed: _saving ? null : _save,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: X5Style.accent.withAlpha(
                                      191,
                                    ),
                                    foregroundColor: const Color(0xff151810),
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: X5Style.radius,
                                    ),
                                    minimumSize: const Size(0, 44),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      if (_saving) ...[
                                        const SizedBox.square(
                                          dimension: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: X5Style.accent,
                                          ),
                                        ),
                                        const SizedBox(width: 7),
                                      ],
                                      Flexible(
                                        child: Text(
                                          _saving
                                              ? 'Comprobando…'
                                              : 'Comprobar y guardar',
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
        ),
      ),
    ),
  );
}
