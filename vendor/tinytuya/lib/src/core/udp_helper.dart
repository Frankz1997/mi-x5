/// UDP communication helper
/// Ported from tinytuya/core/udp_helper.py

library;

import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'crypto_helper.dart';
import 'header.dart';
import 'message_helper.dart';

/// UDP packet decryption key - from tuya-convert
final Uint8List udpKey = Uint8List.fromList(
  md5.convert(utf8.encode('yGAdlopoPVldABfn')).bytes,
);

/// Encrypt a message with a key
Future<Uint8List> encrypt(Uint8List msg, Uint8List key) async {
  final cipher = AESCipher(key);
  return await cipher.encrypt(
    raw: msg,
    useBase64: false,
    usePad: true,
    useIv: false,
  );
}

/// Decrypt a message with a key
Future<String> decrypt(Uint8List msg, Uint8List key) async {
  final cipher = AESCipher(key);
  return await cipher.decrypt(
        enc: msg,
        useBase64: false,
        decodeText: true,
        useIv: false,
      )
      as String;
}

/// Decrypt UDP broadcast packet
///
/// UDP packets from Tuya devices can be in different formats:
/// - Plain JSON
/// - ECB encrypted (v3.1)
/// - 55AA format with encrypted payload (v3.3)
/// - 6699 format with GCM encrypted payload (v3.5)
Future<String> decryptUdp(Uint8List msg) async {
  // Try to parse header
  TuyaHeader? header;
  try {
    header = parseHeader(msg);
  } catch (e) {
    // No valid header, assume ECB encrypted
    return await decrypt(msg, udpKey);
  }

  if (header.prefix == prefix55aaValue) {
    // 55AA format - unpack to get the encrypted payload
    // Let unpackMessage auto-detect retcode (don't pass noRetcode parameter)
    try {
      final unpacked = await unpackMessage(msg);
      final payload = unpacked.payload;

      // Check if payload is already JSON
      try {
        if (payload.isNotEmpty &&
            payload[0] == 0x7B && // '{'
            payload[payload.length - 1] == 0x7D) {
          // '}'
          return utf8.decode(payload);
        }
      } catch (e) {
        // Not JSON, continue to decrypt
      }

      // Decrypt payload with ECB
      return await decrypt(payload, udpKey);
    } catch (e) {
      // If unpacking fails, try decrypting the whole message minus header
      // Some UDP packets might not follow standard message format
      if (msg.length > 16) {
        return await decrypt(Uint8List.sublistView(msg, 16), udpKey);
      }
      rethrow;
    }
  } else if (header.prefix == prefix6699Value) {
    // 6699 format (v3.5 with GCM)
    // Let unpackMessage auto-detect retcode (Python uses no_retcode=None)
    try {
      final unpacked = await unpackMessage(msg, hmacKey: udpKey);
      var payload = utf8.decode(unpacked.payload);

      // Remove trailing null bytes (app sometimes has extra bytes)
      while (payload.isNotEmpty && payload[payload.length - 1] == '\x00') {
        payload = payload.substring(0, payload.length - 1);
      }

      return payload;
    } catch (e) {
      // 6699 UDP packets might have a different structure, try fallback
      // Skip the header (20 bytes) and decrypt the rest with GCM
      if (msg.length > 20) {
        // Extract IV (12 bytes after header) and encrypted data
        final iv = Uint8List.sublistView(msg, 20, 32);
        final encryptedData = Uint8List.sublistView(
          msg,
          32,
          msg.length - 4,
        ); // Skip 4-byte suffix

        // Use GCM decryption
        final cipher = AESCipher(udpKey);
        final decrypted = await cipher.decrypt(
          enc: encryptedData,
          useBase64: false,
          decodeText: true,
          useIv: true,
          iv: iv,
        );

        var payload = decrypted as String;
        // Remove trailing null bytes
        while (payload.isNotEmpty && payload[payload.length - 1] == '\x00') {
          payload = payload.substring(0, payload.length - 1);
        }
        return payload;
      }
      rethrow;
    }
  }

  // Fallback to ECB decryption
  return await decrypt(msg, udpKey);
}
