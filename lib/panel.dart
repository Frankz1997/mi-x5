import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'ac_scene.dart';
import 'desktop_shell.dart';
import 'panel_geometry.dart';
import 'ui_style.dart';
import 'x5.dart';

class X5Panel extends StatefulWidget {
  final X5State? state;
  final bool connected, configured, busy, desktop;
  final String? error;
  final VoidCallback settings, refresh;
  final Future<void> Function(int, Object) write;
  final Widget? settingsContent;
  const X5Panel({
    super.key,
    this.state,
    required this.connected,
    required this.configured,
    required this.busy,
    required this.desktop,
    this.error,
    required this.settings,
    required this.refresh,
    required this.write,
    this.settingsContent,
  });
  @override
  State<X5Panel> createState() => _X5PanelState();
}

enum _Picker { mode, fan }

class _X5PanelState extends State<X5Panel> with SingleTickerProviderStateMixin {
  static const _fanOrder = ['auto', 'mute', 'low', 'middle', 'high', 'strong'];
  static const _fanLabels = [
    'Auto',
    'Silencioso',
    'Bajo',
    'Medio',
    'Alto',
    'Turbo',
  ];
  static const _modeIcons = {
    'cold': X5Glyph.cold,
    'auto': X5Glyph.auto,
    'wet': X5Glyph.dry,
    'wind': X5Glyph.fan,
  };
  static const _modeShort = {
    'cold': 'Frío',
    'auto': 'Auto',
    'wet': 'Seco',
    'wind': 'Vent.',
  };
  double? _draft;
  int? _fanDraft;
  _Picker? _expanded, _hovered;
  final _modeFocus = FocusNode(), _fanFocus = FocusNode();
  late final AnimationController _hop;
  bool get enabled => widget.connected && !widget.busy && widget.state != null;
  bool get _reduce => MediaQuery.disableAnimationsOf(context);
  Color get _surface =>
      widget.desktop ? X5Style.surface : X5Style.mobileSurface;

  @override
  void initState() {
    super.initState();
    _hop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
  }

  @override
  void didUpdateWidget(X5Panel old) {
    super.didUpdateWidget(old);
    if (widget.settingsContent != null) {
      _expanded = null;
      _hovered = null;
    }
  }

  @override
  void dispose() {
    _modeFocus.dispose();
    _fanFocus.dispose();
    _hop.dispose();
    super.dispose();
  }

  void _expand(_Picker? picker) {
    if (!mounted) return;
    if (picker != null && !enabled) return;
    if (_expanded != picker) setState(() => _expanded = picker);
  }

  Widget _header() {
    final state = widget.state;
    return SizedBox(
      height: widget.desktop ? 39 : 44,
      child: Row(
        children: [
          const X5Icon(X5Glyph.thermometer, size: 19),
          const SizedBox(width: 7),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text.rich(
                TextSpan(
                  text: 'Habitación  ',
                  style: const TextStyle(color: X5Style.muted, fontSize: 16),
                  children: [
                    TextSpan(
                      text: '${state?.ambient ?? '—'}°C',
                      style: const TextStyle(color: X5Style.text),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 7),
          X5IconButton(
            key: const ValueKey('sleep-button'),
            label:
                state?.dps['25'] == true ? 'Desactivar Sueño' : 'Activar Sueño',
            glyph: X5Glyph.moon,
            size: 18,
            active: state?.dps['25'] == true,
            onPressed:
                enabled && state!.dps['25'] is bool
                    ? () => widget.write(25, state.dps['25'] != true)
                    : null,
          ),
          const SizedBox(width: 7),
          X5IconButton(
            key: const ValueKey('oscillation-button'),
            label:
                state?.dps['31'] == 'same'
                    ? 'Desactivar oscilación vertical'
                    : 'Activar oscilación vertical',
            glyph: X5Glyph.swing,
            size: 20,
            active: state?.dps['31'] == 'same',
            onPressed:
                enabled && verticalSwings.containsKey(state!.dps['31'])
                    ? () => widget.write(
                      31,
                      state.dps['31'] == 'same' ? 'off' : 'same',
                    )
                    : null,
          ),
          const SizedBox(width: 7),
          X5IconButton(
            key: const ValueKey('power-button'),
            label: state?.power == true ? 'Apagar aire' : 'Encender aire',
            glyph: X5Glyph.power,
            extent: 39,
            active: state?.power == true,
            onPressed: enabled ? () => widget.write(1, !state!.power) : null,
          ),
        ],
      ),
    );
  }

  Widget _temperature() {
    final temperature = _draft?.round() ?? widget.state?.temperature;
    final value = (_draft ?? widget.state?.temperature.toDouble() ?? 23).clamp(
      16.0,
      30.0,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 58,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text.rich(
              TextSpan(
                text: temperature?.toString() ?? '—',
                style: const TextStyle(
                  fontSize: 56,
                  height: 1,
                  letterSpacing: -3,
                  color: X5Style.text,
                ),
                children: const [
                  TextSpan(
                    text: ' °C',
                    style: TextStyle(
                      fontSize: 25,
                      letterSpacing: 0,
                      color: X5Style.muted,
                    ),
                  ),
                ],
              ),
              key: const ValueKey('setpoint'),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            X5IconButton(
              key: const ValueKey('temperature-down'),
              label: 'Bajar temperatura',
              glyph: X5Glyph.minus,
              background: _surface,
              onPressed:
                  enabled && widget.state!.temperature > 16
                      ? () => widget.write(
                        2,
                        (widget.state!.temperature - 1).clamp(16, 30),
                      )
                      : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _slider(
                value: value,
                min: 16,
                max: 30,
                divisions: 14,
                height: 45,
                thumb: const Size(25, 37),
                label: 'Temperatura deseada',
                onChanged: enabled ? (v) => setState(() => _draft = v) : null,
                onEnd:
                    enabled
                        ? (v) async {
                          try {
                            await widget.write(2, v.round());
                          } finally {
                            if (mounted) setState(() => _draft = null);
                          }
                        }
                        : null,
              ),
            ),
            const SizedBox(width: 12),
            X5IconButton(
              key: const ValueKey('temperature-up'),
              label: 'Subir temperatura',
              glyph: X5Glyph.plus,
              background: _surface,
              onPressed:
                  enabled && widget.state!.temperature < 30
                      ? () => widget.write(2, widget.state!.temperature + 1)
                      : null,
            ),
          ],
        ),
        const SizedBox(height: 10),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 57),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('16°', style: TextStyle(color: X5Style.muted, fontSize: 12)),
              Text('30°', style: TextStyle(color: X5Style.muted, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _slider({
    required double value,
    required double min,
    required double max,
    required int divisions,
    required double height,
    required Size thumb,
    required String label,
    required ValueChanged<double>? onChanged,
    required ValueChanged<double>? onEnd,
    double hop = 0,
    double? visualHeight,
  }) {
    final fraction = (value - min) / (max - min);
    final barHeight = visualHeight ?? height;
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Align(
            alignment: Alignment.center,
            child: Container(
              height: barHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(barHeight == 45 ? 14 : 7),
                border: Border.all(color: const Color(0xff272a22)),
                gradient: LinearGradient(
                  colors: [
                    const Color(0xbf5e5a49),
                    const Color(0xbf827e68),
                    const Color(0xbf0d0e0b),
                    const Color(0xbf0b0c09),
                  ],
                  stops: [0, fraction, fraction, 1],
                ),
              ),
            ),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: barHeight,
              thumbShape: _RectThumb(thumb, hop),
              overlayShape: SliderComponentShape.noOverlay,
              activeTrackColor: Colors.transparent,
              inactiveTrackColor: Colors.transparent,
              disabledActiveTrackColor: Colors.transparent,
              disabledInactiveTrackColor: Colors.transparent,
              tickMarkShape: SliderTickMarkShape.noTickMark,
              showValueIndicator: ShowValueIndicator.never,
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              label: label,
              semanticFormatterCallback:
                  (v) => min == 0 ? _fanLabels[v.round()] : '${v.round()} °C',
              onChanged: onChanged,
              onChangeEnd: onEnd,
            ),
          ),
        ],
      ),
    );
  }

  Widget _picker(_Picker kind, double width) {
    final open = _expanded == kind;
    final fan = kind == _Picker.fan;
    final state = widget.state;
    final value =
        fan
            ? _fanLabels[(_fanDraft ?? _fanOrder.indexOf(state?.fan ?? 'auto'))
                .clamp(0, 5)]
            : modes[state?.mode] ?? '—';
    final headingHeight = open ? (fan && !widget.desktop ? 44.0 : 34.0) : 88.0;
    final duration = Duration(milliseconds: _reduce ? 0 : 380);
    final focus = fan ? _fanFocus : _modeFocus;
    return MouseRegion(
      onEnter: (event) {
        if (event.kind == PointerDeviceKind.mouse) {
          _hovered = kind;
          _expand(kind);
        }
      },
      onExit: (_) {
        if (_hovered == kind) {
          _hovered = null;
          _expand(null);
        }
      },
      child: Focus(
        onFocusChange: (hasFocus) {
          if (hasFocus && _expanded != kind) {
            _expand(kind);
          } else if (!hasFocus &&
              _hovered != kind &&
              !widget.busy &&
              _expanded == kind) {
            _expand(null);
          }
        },
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            focus.requestFocus();
            _expand(null);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Container(
          key: ValueKey(fan ? 'fan-card' : 'mode-card'),
          width: width,
          height: widget.desktop ? 88 : 104,
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: X5Style.radius,
            border: Border.all(color: const Color(0xff24261f)),
          ),
          clipBehavior: Clip.antiAliasWithSaveLayer,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: fan && !widget.desktop ? 44 : 34,
                height: widget.desktop ? 54 : (fan ? 60 : 70),
                child: IgnorePointer(
                  ignoring: !open,
                  child: ExcludeSemantics(
                    excluding: !open,
                    child: FocusScope(
                      canRequestFocus: open,
                      skipTraversal: !open,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(end: open ? 1 : 0),
                        duration: duration,
                        curve: const Interval(.3, 1, curve: Curves.easeOut),
                        builder:
                            (_, opacity, child) =>
                                Opacity(opacity: opacity, child: child),
                        child: fan ? _fanOptions(width) : _modeOptions(),
                      ),
                    ),
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: duration,
                curve: Curves.easeOutCubic,
                left: 0,
                right: 0,
                top: 0,
                height: headingHeight,
                child: TextButton(
                  key: ValueKey(fan ? 'fan-button' : 'mode-button'),
                  focusNode: focus,
                  onPressed:
                      enabled
                          ? () =>
                              _expand(open && _hovered != kind ? null : kind)
                          : null,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: X5Style.text,
                    overlayColor:
                        open ? Colors.transparent : Colors.white.withAlpha(5),
                    enabledMouseCursor:
                        open
                            ? SystemMouseCursors.basic
                            : SystemMouseCursors.click,
                    shape: const RoundedRectangleBorder(),
                  ),
                  child: SizedBox.expand(
                    child: Stack(
                      children: [
                        AnimatedPositioned(
                          duration: duration,
                          curve: Curves.easeOutCubic,
                          left: open ? 12 : 11,
                          top: open ? 6 : 10,
                          child: X5Icon(
                            fan
                                ? X5Glyph.fan
                                : _modeIcons[state?.mode] ?? X5Glyph.cold,
                            size: 21,
                          ),
                        ),
                        AnimatedPositioned(
                          duration: duration,
                          curve: Curves.easeOutCubic,
                          left: open ? 42 : 11,
                          top: open ? 8 : 45,
                          child: AnimatedOpacity(
                            opacity: open && width < 250 ? 0 : 1,
                            duration: duration,
                            child: Text(
                              fan ? 'Ventilador' : 'Modo',
                              style: const TextStyle(
                                color: X5Style.muted,
                                fontSize: 13,
                                height: 17 / 13,
                              ),
                            ),
                          ),
                        ),
                        AnimatedPositioned(
                          duration: duration,
                          curve: Curves.easeOutCubic,
                          left:
                              open
                                  ? (width < 250
                                      ? 42
                                      : width - (fan ? 86 : 145))
                                  : 11,
                          right: 12,
                          top: open ? 8 : 65,
                          child: Text(
                            value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign:
                                open && !fan && width >= 250
                                    ? TextAlign.right
                                    : TextAlign.left,
                            style: const TextStyle(
                              color: X5Style.text,
                              fontSize: 15,
                              height: 17 / 15,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modeOptions() => Padding(
    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
    child: Row(
      children: [
        for (final mode in _modeShort.keys)
          Expanded(
            child: Semantics(
              label: modes[mode],
              selected: widget.state?.mode == mode,
              button: true,
              child: TextButton(
                key: ValueKey('mode-$mode'),
                onPressed:
                    enabled
                        ? () {
                          if (widget.state!.mode != mode) widget.write(4, mode);
                        }
                        : null,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  foregroundColor: X5Style.text,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    X5Icon(
                      _modeIcons[mode]!,
                      size: 18,
                      color:
                          widget.state?.mode == mode
                              ? Colors.white
                              : X5Style.muted,
                      glow: widget.state?.mode == mode,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _modeShort[mode]!,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'RobotoCondensed',
                        fontSize: 11,
                        height: 14 / 11,
                        color:
                            widget.state?.mode == mode
                                ? X5Style.text
                                : X5Style.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _fanOptions(double width) {
    final index = (_fanDraft ?? _fanOrder.indexOf(widget.state?.fan ?? 'auto'))
        .clamp(0, 5);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 12,
          right: 12,
          top: 0,
          height: widget.desktop ? 23 : 44,
          child: AnimatedBuilder(
            animation: _hop,
            builder:
                (_, __) => _slider(
                  value: index.toDouble(),
                  min: 0,
                  max: 5,
                  divisions: 5,
                  height: widget.desktop ? 23 : 44,
                  visualHeight: 23,
                  thumb: const Size(14, 17),
                  label: 'Velocidad del ventilador',
                  hop: _reduce ? 0 : math.sin(_hop.value * math.pi),
                  onChanged:
                      enabled || widget.busy
                          ? (v) {
                            if (!enabled || v.round() == index) return;
                            setState(() => _fanDraft = v.round());
                            if (!_reduce) _hop.forward(from: 0);
                          }
                          : null,
                  onEnd:
                      enabled
                          ? (v) async {
                            try {
                              if (_fanOrder[v.round()] != widget.state!.fan) {
                                await widget.write(5, _fanOrder[v.round()]);
                              }
                            } finally {
                              if (mounted) setState(() => _fanDraft = null);
                            }
                          }
                          : null,
                ),
          ),
        ),
        for (var i = 0; i < _fanLabels.length; i++)
          Positioned(
            left: 19 + i / 5 * (width - 38) - 30,
            top: widget.desktop ? 29 : 43,
            width: 60,
            child: IgnorePointer(
              child: Text(
                i == 1 && width < 250 ? 'Sil.' : _fanLabels[i],
                textAlign: TextAlign.center,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 11,
                  height: 14 / 11,
                  color: i == index ? X5Style.text : X5Style.muted,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _pickers() => TapRegion(
    onTapOutside: widget.desktop ? null : (_) => _expand(null),
    child: LayoutBuilder(
      builder:
          (_, constraints) => TweenAnimationBuilder<double>(
            tween: Tween(
              end:
                  _expanded == _Picker.mode
                      ? 2.5 / 3.5
                      : _expanded == _Picker.fan
                      ? 1 / 3.5
                      : .5,
            ),
            duration: Duration(milliseconds: _reduce ? 0 : 380),
            curve: Curves.easeOutCubic,
            builder: (_, fraction, __) {
              final available = constraints.maxWidth - 10;
              final modeWidth =
                  (available * fraction)
                      .clamp(84.0, math.max(84.0, available - 84))
                      .toDouble();
              return Row(
                children: [
                  _picker(_Picker.mode, modeWidth),
                  const SizedBox(width: 10),
                  _picker(_Picker.fan, available - modeWidth),
                ],
              );
            },
          ),
    ),
  );

  Widget _footer() {
    final status =
        widget.busy
            ? 'Sincronizando…'
            : widget.connected
            ? 'Conectado'
            : 'Sin conexión';
    return SizedBox(
      height: widget.desktop ? 36 : 44,
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              label: '$status. Actualizar estado',
              liveRegion: true,
              button: true,
              child: TextButton(
                key: const ValueKey('refresh-button'),
                onPressed:
                    widget.busy || !widget.configured ? null : widget.refresh,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  alignment: Alignment.centerLeft,
                  foregroundColor: X5Style.muted,
                ),
                child: Row(
                  children: [
                    SizedBox.square(
                      dimension: 14,
                      child:
                          widget.busy
                              ? const CircularProgressIndicator(
                                strokeWidth: 2,
                                color: X5Style.accent,
                                semanticsLabel: 'Sincronizando',
                              )
                              : X5Icon(
                                widget.connected
                                    ? X5Glyph.shield
                                    : X5Glyph.wifi,
                                size: 14,
                                color: const Color(0xffb2b59f),
                              ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      status,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 16 / 13,
                        color: X5Style.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          X5IconButton(
            key: const ValueKey('settings-button'),
            label: 'Abrir configuración',
            glyph: X5Glyph.settings,
            extent: 36,
            onPressed: widget.busy ? null : widget.settings,
          ),
        ],
      ),
    );
  }

  Widget _controls() => LayoutBuilder(
    builder:
        (_, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment:
                  widget.desktop
                      ? MainAxisAlignment.start
                      : MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(),
                AcScene(
                  power: widget.state?.power == true,
                  oscillating: widget.state?.dps['31'] == 'same',
                  light: widget.state?.dps['36'] == true,
                  temperature: _draft?.round() ?? widget.state?.temperature,
                  fan: widget.state?.fan ?? 'auto',
                  toggleDisplay:
                      enabled &&
                              widget.state!.power &&
                              widget.state!.dps['36'] is bool
                          ? () =>
                              widget.write(36, widget.state!.dps['36'] != true)
                          : null,
                ),
                if (widget.configured) ...[
                  _temperature(),
                  const SizedBox(height: 16),
                  _pickers(),
                ] else ...[
                  const SizedBox(height: 35),
                  const Text(
                    'Tu aire, a un toque.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 25, color: X5Style.text),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Conéctalo una vez para usarlo en la red de casa.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: X5Style.muted),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: widget.settings,
                    child: const Text('Conectar mi X5'),
                  ),
                ],
                if (widget.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      widget.error!,
                      style: const TextStyle(
                        color: Color(0xffedb5a9),
                        fontSize: 12,
                      ),
                    ),
                  ),
                const SizedBox(height: 14),
                _footer(),
              ],
            ),
          ),
        ),
  );

  Widget _screens() {
    final settings = widget.settingsContent != null;
    final duration = Duration(milliseconds: _reduce ? 0 : 220);
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: settings,
          child: ExcludeFocus(
            excluding: settings,
            child: TickerMode(
              enabled: !settings,
              child: KeyedSubtree(
                key: const ValueKey('controls-screen'),
                child: _controls(),
              ),
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: duration,
          layoutBuilder:
              (current, _) => Stack(
                fit: StackFit.expand,
                children: [if (current != null) current],
              ),
          transitionBuilder:
              (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(.015, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
          child:
              settings
                  ? KeyedSubtree(
                    key: const ValueKey('settings-screen'),
                    child: widget.settingsContent!,
                  )
                  : const SizedBox.shrink(key: ValueKey('settings-hidden')),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<TrayPlacement?>(
    valueListenable: DesktopShell.placement,
    builder: (_, placement, __) {
      final edge =
          widget.desktop ? placement?.edge ?? TrayEdge.bottom : TrayEdge.bottom;
      final anchor = widget.desktop ? placement?.anchor ?? .9 : .9;
      final frame = LayoutBuilder(
        builder:
            (_, constraints) => Center(
              child: SizedBox(
                width:
                    widget.desktop
                        ? math.min(500.0, constraints.maxWidth)
                        : constraints.maxWidth,
                height: math.min(
                  widget.desktop ? 540.0 : constraints.maxHeight,
                  constraints.maxHeight,
                ),
                child: Padding(
                  padding:
                      widget.desktop
                          ? const EdgeInsets.all(8)
                          : EdgeInsets.zero,
                  child: CustomPaint(
                    key: const ValueKey('panel-frame'),
                    painter: _PanelPainter(
                      edge,
                      anchor,
                      desktop: widget.desktop,
                    ),
                    child: ClipPath(
                      clipper: _PanelClip(
                        edge,
                        anchor,
                        desktop: widget.desktop,
                      ),
                      clipBehavior: Clip.antiAliasWithSaveLayer,
                      child: Padding(
                        padding:
                            widget.desktop
                                ? pointerInsets(edge)
                                : EdgeInsets.zero,
                        child: LayoutBuilder(
                          builder:
                              (_, body) => Padding(
                                padding: EdgeInsets.fromLTRB(
                                  body.maxWidth < 400 ? 14 : 18,
                                  14,
                                  body.maxWidth < 400 ? 14 : 18,
                                  9,
                                ),
                                child: DefaultTextStyle(
                                  style: const TextStyle(
                                    fontFamily: 'RobotoCondensed',
                                    color: X5Style.text,
                                  ),
                                  child: _screens(),
                                ),
                              ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
      );
      return PopScope(
        canPop: widget.desktop || _expanded == null,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && !widget.desktop) _expand(null);
        },
        child: Scaffold(
          backgroundColor:
              widget.desktop ? Colors.transparent : X5Style.mobileBackground,
          body: widget.desktop ? frame : SafeArea(child: frame),
        ),
      );
    },
  );
}

class _PanelPainter extends CustomPainter {
  final TrayEdge edge;
  final double anchor;
  final bool desktop;
  const _PanelPainter(this.edge, this.anchor, {this.desktop = true});
  @override
  void paint(Canvas canvas, Size size) {
    final path =
        desktop
            ? panelOutline(size, edge, anchor)
            : (Path()..addRRect(
              RRect.fromRectAndRadius(Offset.zero & size, Radius.zero),
            ));
    canvas.save();
    canvas.clipPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        path,
      ),
    );
    canvas.drawShadow(path, Colors.black.withAlpha(90), 12, true);
    canvas.restore();
    canvas.drawPath(
      path,
      Paint()..color = desktop ? X5Style.background : X5Style.mobileBackground,
    );
  }

  @override
  bool shouldRepaint(_PanelPainter old) =>
      old.edge != edge || old.anchor != anchor || old.desktop != desktop;
}

class _PanelClip extends CustomClipper<Path> {
  final TrayEdge edge;
  final double anchor;
  final bool desktop;
  const _PanelClip(this.edge, this.anchor, {this.desktop = true});
  @override
  Path getClip(Size size) =>
      desktop
          ? panelOutline(size, edge, anchor)
          : (Path()..addRRect(
            RRect.fromRectAndRadius(Offset.zero & size, Radius.zero),
          ));
  @override
  bool shouldReclip(_PanelClip old) =>
      old.edge != edge || old.anchor != anchor || old.desktop != desktop;
}

class _RectThumb extends SliderComponentShape {
  final Size size;
  final double hop;
  const _RectThumb(this.size, this.hop);
  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => size;
  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final rect = Rect.fromCenter(
      center: center.translate(0, -hop * 2),
      width: size.width * (1 + hop * .08),
      height: size.height * (1 + hop * .08),
    );
    final radius = Radius.circular(size.width == 25 ? 10 : 4);
    context.canvas.drawShadow(
      Path()..addRRect(RRect.fromRectAndRadius(rect, radius)),
      Colors.black.withAlpha(80),
      3,
      true,
    );
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(rect, radius),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xffe4e3d7), Color(0xffc9c9b7)],
        ).createShader(rect),
    );
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(rect, radius),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .75
        ..color = const Color(0xff989986),
    );
  }
}
