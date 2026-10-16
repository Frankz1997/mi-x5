/// Message packing and unpacking helpers
/// Ported from tinytuya/core/message_helper.py

library;

import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'header.dart';
import 'crypto_helper.dart';
import 'exceptions.dart';

/// Parse header from raw bytes
TuyaHeader parseHeader(Uint8List data) {
  // Check for 6699 prefix
  final is6699 =
      data.length >= 4 &&
      data[0] == 0x00 &&
      data[1] == 0x00 &&
      data[2] == 0x66 &&
      data[3] == 0x99;

  final headerLen = is6699
      ? 18
      : 16; // 6699: I+H+I+I+I = 4+2+4+4+4 = 18 bytes, 55AA: 4*I = 16 bytes

  if (data.length < headerLen) {
    throw DecodeError('Not enough data to unpack header');
  }

  final byteData = ByteData.sublistView(data);

  int prefix, seqno, cmd, payloadLen, totalLength;

  if (is6699) {
    // 6699 format: prefix(4), unknown(2), seqno(4), cmd(4), length(4) = 18 bytes total
    // Python format string: >IHIII
    prefix = byteData.getUint32(0, Endian.big); // offset 0-3
    // unknown uint16 at offset 4-5 (skip it)
    seqno = byteData.getUint32(6, Endian.big); // offset 6-9
    cmd = byteData.getUint32(10, Endian.big); // offset 10-13
    payloadLen = byteData.getUint32(14, Endian.big); // offset 14-17
    totalLength = payloadLen + headerLen + 4; // +4 for suffix
  } else {
    // 55AA format: prefix(4), seqno(4), cmd(4), length(4)
    prefix = byteData.getUint32(0, Endian.big);
    seqno = byteData.getUint32(4, Endian.big);
    cmd = byteData.getUint32(8, Endian.big);
    payloadLen = byteData.getUint32(12, Endian.big);
    totalLength = payloadLen + headerLen;

    // Validate prefix
    if (prefix != prefix55aaValue && prefix != prefix6699Value) {
      throw DecodeError(
        'Header prefix wrong! 0x${prefix.toRadixString(16).padLeft(8, '0')} '
        'is not 0x${prefix55aaValue.toRadixString(16).padLeft(8, '0')} '
        'or 0x${prefix6699Value.toRadixString(16).padLeft(8, '0')}',
      );
    }
  }

  // Sanity check - max payload is around 300 bytes typically
  if (payloadLen > 1000) {
    throw DecodeError(
      'Header claims the packet size is over 1000 bytes! '
      'It is most likely corrupt. Claimed size: $payloadLen bytes',
    );
  }

  return TuyaHeader(
    prefix: prefix,
    seqno: seqno,
    cmd: cmd,
    length: payloadLen,
    totalLength: totalLength,
  );
}

/// Calculate CRC32 checksum
int calculateCrc32(Uint8List data) {
  // Use package:crypto for CRC32
  // Note: Dart doesn't have built-in CRC32, so we'll implement a simple version
  // or use a package. For now, let's implement a basic CRC32
  var crc = 0xFFFFFFFF;

  for (var byte in data) {
    crc ^= byte;
    for (var j = 0; j < 8; j++) {
      if ((crc & 1) != 0) {
        crc = (crc >> 1) ^ 0xEDB88320;
      } else {
        crc = crc >> 1;
      }
    }
  }

  return ~crc & 0xFFFFFFFF;
}

/// Pack a TuyaMessage into bytes
Future<Uint8List> packMessage(TuyaMessage msg, {Uint8List? hmacKey}) async {
  final buffer = BytesBuilder();

  if (msg.prefix == prefix55aaValue) {
    // 55AA format
    final endFmtSize = hmacKey != null ? 36 : 8; // HMAC (32+4) or CRC (4+4)
    final msgLen = msg.payload.length + endFmtSize;

    // Pack header: prefix, seqno, cmd, length
    final header = ByteData(16);
    header.setUint32(0, msg.prefix, Endian.big);
    header.setUint32(4, msg.seqno, Endian.big);
    header.setUint32(8, msg.cmd, Endian.big);
    header.setUint32(12, msgLen, Endian.big);

    buffer.add(header.buffer.asUint8List());
    buffer.add(msg.payload);

    // Calculate and add CRC or HMAC
    final dataForCrc = buffer.toBytes();
    if (hmacKey != null) {
      final hmac = crypto.Hmac(crypto.sha256, hmacKey);
      final digest = hmac.convert(dataForCrc);
      buffer.add(digest.bytes);
    } else {
      final crc = calculateCrc32(dataForCrc);
      final crcBytes = ByteData(4);
      crcBytes.setUint32(0, crc, Endian.big);
      buffer.add(crcBytes.buffer.asUint8List());
    }

    // Add suffix
    buffer.add(suffix55aaBin);
  } else if (msg.prefix == prefix6699Value) {
    // 6699 format - requires HMAC key
    if (hmacKey == null) {
      throw TypeError();
    }

    final endFmtSize = 16; // Tag size
    var msgLen = msg.payload.length + endFmtSize + 12; // +12 for IV
    if (msg.retcode != 0) {
      msgLen += 4; // retcode size
    }

    // Pack header: prefix(4), unknown(2), seqno(4), cmd(4), length(4) = 18 bytes
    // Python format: >IHIII
    final header = ByteData(18);
    header.setUint32(0, msg.prefix, Endian.big); // offset 0-3
    header.setUint16(4, 0, Endian.big); // offset 4-5: unknown field (uint16)
    header.setUint32(6, msg.seqno, Endian.big); // offset 6-9
    header.setUint32(10, msg.cmd, Endian.big); // offset 10-13
    header.setUint32(14, msgLen, Endian.big); // offset 14-17

    buffer.add(header.buffer.asUint8List());

    // Encrypt payload
    final cipher = AESCipher(hmacKey);
    Uint8List raw;
    if (msg.retcode != 0) {
      final retcodeBytes = ByteData(4);
      retcodeBytes.setUint32(0, msg.retcode, Endian.big);
      raw = Uint8List.fromList([
        ...retcodeBytes.buffer.asUint8List(),
        ...msg.payload,
      ]);
    } else {
      raw = msg.payload;
    }

    // Encrypt with GCM, using header bytes 4-17 (14 bytes) as AAD
    final headerAad = header.buffer.asUint8List(4);
    final encrypted = await cipher.encrypt(
      raw: raw,
      useBase64: false,
      usePad: false,
      useIv: true,
      iv: msg.iv,
      header: headerAad,
    );

    buffer.add(encrypted);
    buffer.add(suffix6699Bin);
  } else {
    throw ArgumentError(
      'pack_message() cannot handle message format 0x${msg.prefix.toRadixString(16)}',
    );
  }

  return buffer.toBytes();
}

/// Unpack bytes into a TuyaMessage
Future<TuyaMessage> unpackMessage(
  Uint8List data, {
  Uint8List? hmacKey,
  TuyaHeader? header,
  bool? noRetcode,
}) async {
  header ??= parseHeader(data);

  final is55aa = header.prefix == prefix55aaValue;
  final is6699 = header.prefix == prefix6699Value;

  if (!is55aa && !is6699) {
    throw ArgumentError(
      'unpack_message() cannot handle message format 0x${header.prefix.toRadixString(16)}',
    );
  }

  int headerLen, endFmtSize, retcodeLen, msgLen;
  Uint8List payload;
  dynamic crc;
  bool crcGood = false;
  Uint8List? iv;
  int retcode = 0;

  if (is55aa) {
    headerLen = 16;
    endFmtSize = hmacKey != null ? 36 : 8;
    msgLen = headerLen + header.length;

    if (data.length < msgLen) {
      throw DecodeError('Not enough data to unpack payload');
    }

    // Auto-detect retcode presence if not explicitly specified
    // If noRetcode is null or false, check if payload starts with '{'
    if (noRetcode == true) {
      retcodeLen = 0;
    } else if (noRetcode == null) {
      // Auto-detect: if first byte after header is '{' (0x7B), no retcode
      // Otherwise, check if 5th byte is '{', which indicates first 4 bytes are retcode
      final firstByte = data[headerLen];
      if (firstByte == 0x7B) {
        retcodeLen = 0;
      } else if (header.length >= 4 && data[headerLen + 4] == 0x7B) {
        retcodeLen = 4;
      } else {
        retcodeLen = 4; // Default to retcode present (like Python) if unclear
      }
    } else {
      retcodeLen = 4; // noRetcode == false means there IS a retcode
    }

    // Extract retcode if present
    if (retcodeLen > 0 && header.length >= retcodeLen) {
      final retcodeData = ByteData.sublistView(
        data,
        headerLen,
        headerLen + retcodeLen,
      );
      retcode = retcodeData.getUint32(0, Endian.big);
    }

    // Extract payload (after retcode, before CRC/HMAC and suffix)
    // The header.length includes retcode + payload + CRC/suffix
    // So payload is from (headerLen + retcodeLen) to (headerLen + header.length - endFmtSize)
    final payloadStart = headerLen + retcodeLen;
    final payloadEnd = headerLen + header.length - endFmtSize;
    payload = Uint8List.sublistView(data, payloadStart, payloadEnd);

    // Extract and verify CRC/HMAC
    final endData = data.sublist(msgLen - endFmtSize, msgLen);
    if (hmacKey != null) {
      // HMAC verification
      crc = endData.sublist(0, 32);
      final dataForHmac = data.sublist(0, msgLen - endFmtSize);
      final hmac = crypto.Hmac(crypto.sha256, hmacKey);
      final calculatedHmac = hmac.convert(dataForHmac);
      crcGood = _bytesEqual(crc, calculatedHmac.bytes);
    } else {
      // CRC32 verification
      final crcData = ByteData.sublistView(endData, 0, 4);
      crc = crcData.getUint32(0, Endian.big);
      final dataForCrc = data.sublist(0, msgLen - endFmtSize);
      final calculatedCrc = calculateCrc32(dataForCrc);
      crcGood = crc == calculatedCrc;
    }

    // Verify suffix
    final suffixData = ByteData.sublistView(
      endData,
      endFmtSize - 4,
      endFmtSize,
    );
    final suffix = suffixData.getUint32(0, Endian.big);
    if (suffix != suffix55aaValue) {
      // Log warning but continue
    }
  } else {
    // 6699 format
    if (hmacKey == null) {
      throw TypeError();
    }

    headerLen = 18; // 6699 header is 18 bytes (not 20)
    endFmtSize = 20; // 16 bytes tag + 4 bytes suffix
    msgLen = headerLen + header.length + 4;

    if (data.length < msgLen) {
      throw DecodeError('Not enough data to unpack payload');
    }

    // Extract encrypted payload
    payload = Uint8List.sublistView(
      data,
      headerLen,
      msgLen - 4,
    ); // -4 for suffix

    // Extract IV (first 12 bytes of payload)
    iv = payload.sublist(0, 12);
    final encryptedData = payload.sublist(12);

    // Extract tag (last 16 bytes before suffix)
    final tag = encryptedData.sublist(encryptedData.length - 16);
    final ciphertext = encryptedData.sublist(0, encryptedData.length - 16);

    // Decrypt
    try {
      final cipher = AESCipher(hmacKey);
      final headerAad = data.sublist(4, headerLen);
      payload =
          await cipher.decrypt(
                enc: ciphertext,
                useBase64: false,
                decodeText: false,
                useIv: true,
                iv: iv,
                header: headerAad,
                tag: tag,
              )
              as Uint8List;
      crcGood = true;
    } catch (e) {
      crcGood = false;
      // Return empty payload on decryption failure
      payload = Uint8List(0);
    }

    // Extract retcode if present
    retcodeLen = 0;
    if (noRetcode == false) {
      retcodeLen = 4;
    } else if (noRetcode == null && payload.isNotEmpty) {
      // Auto-detect retcode
      if (payload[0] != 0x7B && payload.length > 4 && payload[4] == 0x7B) {
        retcodeLen = 4;
      }
    }

    if (retcodeLen > 0 && payload.length >= retcodeLen) {
      final retcodeData = ByteData.sublistView(payload, 0, retcodeLen);
      retcode = retcodeData.getUint32(0, Endian.big);
      payload = payload.sublist(retcodeLen);
    }

    crc = tag;
  }

  return TuyaMessage(
    seqno: header.seqno,
    cmd: header.cmd,
    retcode: retcode,
    payload: payload,
    crc: crc,
    crcGood: crcGood,
    prefix: header.prefix,
    iv: iv,
  );
}

/// Helper to compare byte arrays
bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Check if payload has valid Tuya suffix
bool hasSuffix(Uint8List payload) {
  if (payload.length < 4) return false;
  return _bytesEqual(payload.sublist(payload.length - 4), suffix55aaBin);
}
