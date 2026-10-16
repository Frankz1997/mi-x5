// Local test fixture only: binds loopback and uses a public dummy key, never an AC.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:tinytuya/src/core/command_types.dart' as command;
import 'package:tinytuya/src/core/crypto_helper.dart';
import 'package:tinytuya/src/core/header.dart';
import 'package:tinytuya/src/core/message_helper.dart';

class WidgetTuyaSimulator {
  static const key = '0123456789abcdef';
  final ServerSocket server;
  final sockets = <Socket>{};
  final writes = <Map<String, dynamic>>[];
  final dps = <String, dynamic>{
    '1': true,
    '2': 23,
    '3': 28,
    '4': 'cold',
    '5': 'auto',
    '25': false,
    '31': 'off',
    '36': true,
  };
  WidgetTuyaSimulator._(this.server) {
    server.listen(_accept);
  }
  static Future<WidgetTuyaSimulator> start({int port = 0}) async =>
      WidgetTuyaSimulator._(
        await ServerSocket.bind(InternetAddress.loopbackIPv4, port),
      );

  void _accept(Socket socket) {
    sockets.add(socket);
    final buffer = <int>[];
    var cipherKey = Uint8List.fromList(key.codeUnits);
    Uint8List? localNonce;
    final remoteNonce = Uint8List.fromList(List.generate(16, (i) => 0x90 + i));
    Future<void> pending = Future.value();
    socket.listen(
      (chunk) {
        buffer.addAll(chunk);
        pending = pending
            .then((_) async {
              while (buffer.length >= 18) {
                final header = parseHeader(
                  Uint8List.fromList(buffer.sublist(0, 18)),
                );
                if (buffer.length < header.totalLength) return;
                final bytes = Uint8List.fromList(
                  buffer.sublist(0, header.totalLength),
                );
                buffer.removeRange(0, header.totalLength);
                final message = await unpackMessage(
                  bytes,
                  hmacKey: cipherKey,
                  noRetcode: true,
                );
                if (!message.crcGood) throw StateError('Authentication failed');
                Uint8List hmac(Uint8List nonce) => Uint8List.fromList(
                  crypto.Hmac(
                    crypto.sha256,
                    key.codeUnits,
                  ).convert(nonce).bytes,
                );
                Future<void> reply(int cmd, List<int> payload) async {
                  socket.add(
                    await packMessage(
                      TuyaMessage(
                        seqno: message.seqno,
                        cmd: cmd,
                        payload: Uint8List.fromList(payload),
                        crc: 0,
                        prefix: prefix6699Value,
                      ),
                      hmacKey: cipherKey,
                    ),
                  );
                  await socket.flush();
                }

                if (message.cmd == command.sessKeyNegStart) {
                  localNonce = message.payload;
                  await reply(command.sessKeyNegResp, [
                    0,
                    0,
                    0,
                    0,
                    ...remoteNonce,
                    ...hmac(localNonce!),
                  ]);
                } else if (message.cmd == command.sessKeyNegFinish) {
                  if (base64Encode(message.payload) !=
                      base64Encode(hmac(remoteNonce))) {
                    throw StateError('Invalid handshake');
                  }
                  final xor = Uint8List.fromList(
                    List.generate(16, (i) => localNonce![i] ^ remoteNonce[i]),
                  );
                  final encrypted = await AESCipher(
                    Uint8List.fromList(key.codeUnits),
                  ).encrypt(
                    raw: xor,
                    useBase64: false,
                    usePad: false,
                    useIv: true,
                    iv: localNonce!.sublist(0, 12),
                  );
                  cipherKey = encrypted.sublist(12, 28);
                } else if (message.cmd == command.dpQueryNew) {
                  await Future<void>.delayed(const Duration(milliseconds: 150));
                  await reply(message.cmd, [
                    0,
                    0,
                    0,
                    0,
                    ...utf8.encode(jsonEncode({'dps': dps})),
                  ]);
                } else if (message.cmd == command.controlNew) {
                  final raw = message.payload.sublist(protocol35Header.length);
                  final payload =
                      jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
                  final changes = Map<String, dynamic>.from(
                    payload['data']['dps'] as Map,
                  );
                  writes.add(changes);
                  dps.addAll(changes);
                  stdout.writeln('SIMULATED_WRITE ${jsonEncode(changes)}');
                  await reply(message.cmd, [
                    0,
                    0,
                    0,
                    0,
                    ...protocol35Header,
                    ...utf8.encode(jsonEncode({'dps': dps})),
                  ]);
                } else {
                  throw StateError('Unexpected command ${message.cmd}');
                }
              }
            })
            .catchError((Object error) {
              stdout.writeln('SIMULATOR_ERROR ${error.runtimeType}');
              socket.destroy();
            });
      },
      onDone: () => sockets.remove(socket),
      onError: (_) => sockets.remove(socket),
    );
  }

  Future<void> close() async {
    for (final socket in sockets.toList()) {
      socket.destroy();
    }
    await server.close();
  }
}

Future<void> main() async {
  final simulator = await WidgetTuyaSimulator.start(port: 6668);
  stdout.writeln('SIMULATOR_READY loopback:6668');
  await stdin.transform(utf8.decoder).transform(const LineSplitter()).first;
  await simulator.close();
}
