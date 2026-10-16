/// Tuya Device Dictionary - Command and Payload Overrides
/// Ported from tinytuya/core/XenonDevice.py
///
/// 'default' devices require the 0a command for the DP_QUERY request
/// 'device22' devices require the 0d command for the DP_QUERY request and a list of
///            dps used set to Null in the request payload
///
/// Any command not defined in payloadDict will be sent as-is with a
///  payload of {"gwId": "", "devId": "", "uid": "", "t": ""}

library;

import 'command_types.dart';

/// Command payload configuration
class CommandConfig {
  final Map<String, dynamic> command;
  final int? commandOverride;

  CommandConfig({required this.command, this.commandOverride});

  /// Deep copy of command map
  Map<String, dynamic> copyCommand() {
    return _deepCopy(command);
  }

  static Map<String, dynamic> _deepCopy(Map<String, dynamic> map) {
    final result = <String, dynamic>{};
    for (final key in map.keys) {
      if (map[key] is Map<String, dynamic>) {
        result[key] = _deepCopy(map[key] as Map<String, dynamic>);
      } else if (map[key] is List) {
        result[key] = List.from(map[key] as List);
      } else {
        result[key] = map[key];
      }
    }
    return result;
  }
}

/// Payload dictionary for different device types and versions
final Map<String, Map<int, CommandConfig>> payloadDict = {
  // Default Device
  'default': {
    apConfig: CommandConfig(
      command: {'gwId': '', 'devId': '', 'uid': '', 't': ''},
    ),
    control: CommandConfig(command: {'devId': '', 'uid': '', 't': ''}),
    status: CommandConfig(command: {'gwId': '', 'devId': ''}),
    heartBeat: CommandConfig(command: {'gwId': '', 'devId': ''}),
    dpQuery: CommandConfig(
      command: {'gwId': '', 'devId': '', 'uid': '', 't': ''},
    ),
    controlNew: CommandConfig(command: {'devId': '', 'uid': '', 't': ''}),
    dpQueryNew: CommandConfig(command: {'devId': '', 'uid': '', 't': ''}),
    updatedps: CommandConfig(
      command: {
        'dpId': [18, 19, 20],
      },
    ),
    lanExtStream: CommandConfig(command: {'reqType': '', 'data': {}}),
  },

  // Special Case Device with 22 character ID
  'device22': {
    dpQuery: CommandConfig(
      commandOverride: controlNew, // Uses CONTROL_NEW command
      command: {'devId': '', 'uid': '', 't': ''},
    ),
  },

  // v3.4 devices do not need devId/gwId/uid
  'v3.4': {
    control: CommandConfig(
      commandOverride: controlNew, // Uses CONTROL_NEW command
      command: {'protocol': 5, 't': 'int', 'data': {}},
    ),
    controlNew: CommandConfig(command: {'protocol': 5, 't': 'int', 'data': {}}),
    dpQuery: CommandConfig(commandOverride: dpQueryNew, command: {}),
    dpQueryNew: CommandConfig(command: {}),
  },

  // v3.5 is just a copy of v3.4
  'v3.5': {
    control: CommandConfig(
      commandOverride: controlNew, // Uses CONTROL_NEW command
      command: {'protocol': 5, 't': 'int', 'data': {}},
    ),
    controlNew: CommandConfig(command: {'protocol': 5, 't': 'int', 'data': {}}),
    dpQuery: CommandConfig(commandOverride: dpQueryNew, command: {}),
    dpQueryNew: CommandConfig(command: {}),
  },

  // Placeholders
  'gateway': {},
  'gateway_v3.4': {},
  'gateway_v3.5': {},

  // Zigbee devices
  'zigbee': {
    control: CommandConfig(command: {'t': 'int', 'cid': ''}),
    dpQuery: CommandConfig(command: {'t': 'int', 'cid': ''}),
  },

  'zigbee_v3.4': {
    control: CommandConfig(
      commandOverride: controlNew,
      command: {
        'protocol': 5,
        't': 'int',
        'data': {'cid': ''},
      },
    ),
    controlNew: CommandConfig(
      command: {
        'protocol': 5,
        't': 'int',
        'data': {'cid': ''},
      },
    ),
    dpQuery: CommandConfig(
      commandOverride: dpQueryNew,
      command: {
        'protocol': 5,
        't': 'int',
        'data': {'cid': ''},
      },
    ),
    dpQueryNew: CommandConfig(
      command: {
        'protocol': 5,
        't': 'int',
        'data': {'cid': ''},
      },
    ),
  },

  'zigbee_v3.5': {
    control: CommandConfig(
      commandOverride: controlNew,
      command: {
        'protocol': 5,
        't': 'int',
        'data': {'cid': ''},
      },
    ),
    controlNew: CommandConfig(
      command: {
        'protocol': 5,
        't': 'int',
        'data': {'cid': ''},
      },
    ),
    dpQuery: CommandConfig(
      commandOverride: dpQueryNew,
      command: {
        'protocol': 5,
        't': 'int',
        'data': {'cid': ''},
      },
    ),
    dpQueryNew: CommandConfig(
      command: {
        'protocol': 5,
        't': 'int',
        'data': {'cid': ''},
      },
    ),
  },
};

/// Merge payload dictionaries
/// dict2 will be merged into dict1
void mergePayloadDicts(
  Map<int, CommandConfig> dict1,
  Map<int, CommandConfig> dict2,
) {
  for (final cmd in dict2.keys) {
    dict1[cmd] = dict2[cmd]!;
  }
}
