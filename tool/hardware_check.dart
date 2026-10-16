import 'dart:convert';
import 'dart:io';

import 'package:mirage_x5/x5.dart';

Map<String, Map<String, dynamic>> changedDps(
  Map<String, dynamic> before,
  Map<String, dynamic> after,
) => {
  for (final dp in {...before.keys, ...after.keys})
    if (before.containsKey(dp) != after.containsKey(dp) ||
        jsonEncode(before[dp]) != jsonEncode(after[dp]))
      dp: {'before': before[dp], 'after': after[dp]},
};

Future<void> main(List<String> args) async {
  if (args.contains('--watch') &&
      (args.contains('--controls') ||
          args.contains('--write') ||
          args.contains('--vertical'))) {
    throw ArgumentError(
      '--watch es solo lectura; no se combina con escrituras.',
    );
  }
  final config = X5Connection.decode(
    await stdin.transform(utf8.decoder).join(),
  );
  final client = X5Client(config);
  try {
    if (args.contains('--watch')) {
      var previous = await client.readDps();
      stdout.writeln(
        jsonEncode({'monitor': 'start', 'seconds': 90, 'dps': previous}),
      );
      final elapsed = Stopwatch()..start();
      while (elapsed.elapsed < const Duration(seconds: 90)) {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (elapsed.elapsed >= const Duration(seconds: 90)) break;
        final current = await client.readDps();
        final changes = changedDps(previous, current);
        if (changes.isNotEmpty) {
          stdout.writeln(
            jsonEncode({
              'elapsedSeconds': elapsed.elapsed.inSeconds,
              'changes': changes,
            }),
          );
        }
        previous = current;
      }
      stdout.writeln(jsonEncode({'monitor': 'finished'}));
      return;
    }
    final before = await client.read();
    if (args.contains('--vertical')) {
      final original = before.dps['31'];
      if (!verticalSwings.containsKey(original)) {
        throw StateError('Unknown vertical swing state');
      }
      try {
        final changed = await client.write(
          31,
          original == 'same' ? 'off' : 'same',
        );
        if (changed.power != before.power) {
          throw StateError('Unexpected power state change');
        }
        stdout.writeln(
          jsonEncode({'vertical': changed.dps['31'], 'holdSeconds': 30}),
        );
        await Future<void>.delayed(const Duration(seconds: 30));
      } finally {
        final restored = await client.write(31, original);
        if (restored.power != before.power) {
          throw StateError('Unexpected power state change');
        }
        assert(restored.dps['31'] == original);
        stdout.writeln(jsonEncode({'verticalRestored': restored.dps['31']}));
      }
    }
    final checks = <Map<String, Object>>[];
    if (args.contains('--controls')) {
      // shortcut: this checks reported settings without changing power, verify physical operation separately.
      final probes = <int, List<Object>>{
        2: [
          if (before.temperature <= 30)
            before.temperature == 30 ? 29 : before.temperature + 1,
        ],
        4: modes.keys.where((mode) => mode != before.mode).toList(),
        5: fanSpeeds.keys.where((fan) => fan != before.fan).toList(),
        25: [before.dps['25'] != true],
        36: [before.dps['36'] != true],
      };
      for (final probe in probes.entries) {
        final original = before.dps['${probe.key}'];
        if (original == null) continue;
        for (final value in probe.value) {
          final check = <String, Object>{'dp': probe.key, 'value': value};
          try {
            final changed = await client.write(probe.key, value);
            if (changed.power != before.power) {
              throw StateError('Unexpected power state change');
            }
            check['confirmed'] = true;
          } catch (error) {
            check['confirmed'] = false;
            check['error'] = error.toString();
          } finally {
            final restored = await client.write(probe.key, original);
            if (restored.power != before.power) {
              throw StateError('Unexpected power state change');
            }
            assert(restored.dps['${probe.key}'] == original);
            check['restored'] = true;
          }
          checks.add(check);
          stdout.writeln(jsonEncode(check));
        }
      }
      final after = await client.read();
      for (final dp in [1, 2, 4, 5, 25, 36]) {
        if (after.dps['$dp'] != before.dps['$dp']) {
          throw StateError('Initial setting DP $dp was not restored');
        }
      }
    }
    if (args.contains('--write')) {
      final original = before.dps['36'] as bool;
      try {
        final changed = await client.write(36, !original);
        assert(changed.dps['36'] == !original);
      } finally {
        final restored = await client.write(36, original);
        if (restored.power != before.power) {
          throw StateError('Unexpected power state change');
        }
      }
    }
    stdout.writeln(
      jsonEncode({
        'read': true,
        'writeAndRestore': args.contains('--write'),
        'power': before.power,
        'setCelsius': before.temperature,
        'ambientCelsius': before.ambient,
        'dps': before.dps,
        if (args.contains('--controls')) 'controlChecks': checks,
      }),
    );
    if (checks.any((check) => check['confirmed'] != true)) exitCode = 1;
  } finally {
    await client.close();
  }
}
