/// Message header handling for Tuya protocol
/// Ported from tinytuya/core/header.py

library;

import 'dart:typed_data';
import 'command_types.dart' as ct;

// Protocol Versions and Headers
const protocolVersionBytes31 = '3.1';
const protocolVersionBytes33 = '3.3';
const protocolVersionBytes34 = '3.4';
const protocolVersionBytes35 = '3.5';

// Protocol headers (12 null bytes)
final protocol3xHeader = Uint8List(12);
final protocol33Header = Uint8List.fromList([
  ...protocolVersionBytes33.codeUnits,
  ...protocol3xHeader,
]);
final protocol34Header = Uint8List.fromList([
  ...protocolVersionBytes34.codeUnits,
  ...protocol3xHeader,
]);
final protocol35Header = Uint8List.fromList([
  ...protocolVersionBytes35.codeUnits,
  ...protocol3xHeader,
]);

// Prefix and Suffix values
const prefix55aaValue = 0x000055AA;
const suffix55aaValue = 0x0000AA55;
const prefix6699Value = 0x00006699;
const suffix6699Value = 0x00009966;

// Prefix and Suffix as bytes
final prefix55aaBin = Uint8List.fromList([0x00, 0x00, 0x55, 0xaa]);
final suffix55aaBin = Uint8List.fromList([0x00, 0x00, 0xaa, 0x55]);
final prefix6699Bin = Uint8List.fromList([0x00, 0x00, 0x66, 0x99]);
final suffix6699Bin = Uint8List.fromList([0x00, 0x00, 0x99, 0x66]);

// Commands that don't have protocol headers
final noProtocolHeaderCmds = [
  ct.dpQuery,
  ct.dpQueryNew,
  ct.updatedps,
  ct.heartBeat,
  ct.sessKeyNegStart,
  ct.sessKeyNegResp,
  ct.sessKeyNegFinish,
  ct.lanExtStream,
];

/// Tuya protocol message header
class TuyaHeader {
  final int prefix;
  final int seqno;
  final int cmd;
  final int length;
  final int totalLength;

  TuyaHeader({
    required this.prefix,
    required this.seqno,
    required this.cmd,
    required this.length,
    required this.totalLength,
  });

  @override
  String toString() {
    return 'TuyaHeader(prefix: 0x${prefix.toRadixString(16)}, '
        'seq: $seqno, cmd: $cmd, len: $length, total: $totalLength)';
  }
}

/// Complete Tuya protocol message
class TuyaMessage {
  final int seqno;
  final int cmd;
  final int retcode;
  final Uint8List payload;
  final dynamic crc; // Can be int or Uint8List (for HMAC)
  final bool crcGood;
  final int prefix;
  final Uint8List? iv;

  TuyaMessage({
    required this.seqno,
    required this.cmd,
    this.retcode = 0,
    required this.payload,
    required this.crc,
    this.crcGood = true,
    this.prefix = prefix55aaValue,
    this.iv,
  });

  @override
  String toString() {
    return 'TuyaMessage(seq: $seqno, cmd: $cmd, retcode: $retcode, '
        'payloadLen: ${payload.length}, crcGood: $crcGood, '
        'prefix: 0x${prefix.toRadixString(16)})';
  }
}

/// Message payload structure
class MessagePayload {
  final int cmd;
  final Uint8List payload;

  MessagePayload({required this.cmd, required this.payload});
}
