import 'package:flutter_test/flutter_test.dart';

import '../tool/hardware_check.dart' as hardware;

void main() {
  test(
    'DPS diff reports changes, additions and removals without unchanged data',
    () {
      expect(
        hardware.changedDps(
          {
            '1': false,
            '2': 23,
            '900': 'a',
            '99': true,
            '100': [1, 2],
          },
          {
            '1': true,
            '2': 23,
            '900': 'b',
            '25': false,
            '100': [1, 2],
          },
        ),
        {
          '1': {'before': false, 'after': true},
          '900': {'before': 'a', 'after': 'b'},
          '99': {'before': true, 'after': null},
          '25': {'before': null, 'after': false},
        },
      );
    },
  );

  test(
    'Read-only monitor rejects write options before reading credentials',
    () async {
      for (final option in ['--controls', '--write', '--vertical']) {
        await expectLater(
          hardware.main(['--watch', option]),
          throwsArgumentError,
        );
      }
    },
  );
}
