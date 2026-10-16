/// Cryptographic helper functions for device communication
/// Ported from tinytuya/core/crypto_helper.py
/// Uses 'cryptography' package for GCM (Protocol 3.5)
/// Uses vendored pure-Dart AES-ECB for pre-3.5 protocols

library;

import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'exceptions.dart';
import 'aes_ecb.dart';

/// AES cipher for encrypting/decrypting Tuya device messages
///
/// Supports both ECB mode (for protocols 3.1-3.4) and GCM mode (for protocol 3.5)
class AESCipher {
  final Uint8List key;
  static const String cryptoLib = 'cryptography';
  static const bool cryptoLibHasGcm = true;

  AESCipher(this.key);

  /// Create an AES cipher from a key string
  factory AESCipher.fromString(String keyString) {
    // Convert key string to bytes using codeUnits (preserves byte values 0-255)
    // DO NOT use utf8.encode() as it will mangle bytes > 127
    final keyBytes = Uint8List.fromList(keyString.codeUnits);

    // Pad or truncate to 16 bytes for AES-128
    final paddedKey = Uint8List(16);
    final length = keyBytes.length > 16 ? 16 : keyBytes.length;
    paddedKey.setRange(0, length, keyBytes);

    return AESCipher(paddedKey);
  }

  /// PKCS7 padding - add padding bytes to make data length a multiple of blockSize
  static Uint8List pad(Uint8List data, int blockSize) {
    final padNum = blockSize - (data.length % blockSize);
    final padding = Uint8List(padNum);
    padding.fillRange(0, padNum, padNum);
    return Uint8List.fromList([...data, ...padding]);
  }

  /// PKCS7 unpadding - remove padding bytes
  static Uint8List unpad(Uint8List data, {bool verifyPadding = false}) {
    if (data.isEmpty) {
      throw ArgumentError('Cannot unpad empty data');
    }

    final padLen = data[data.length - 1];

    if (padLen < 1 || padLen > 16) {
      throw DecryptionException('Invalid padding length byte: $padLen');
    }

    if (verifyPadding) {
      // Verify all padding bytes are correct
      for (var i = data.length - padLen; i < data.length; i++) {
        if (data[i] != padLen) {
          throw DecryptionException('Invalid padding data');
        }
      }
    }

    return Uint8List.sublistView(data, 0, data.length - padLen);
  }

  /// Generate encryption IV (nonce) for GCM mode
  /// If iv is true, generates a 12-byte IV
  static Uint8List getEncryptionIv({bool generateIv = false, Uint8List? iv}) {
    if (iv != null) return iv;
    if (generateIv) {
      // Generate IV from timestamp (similar to Python implementation)
      final timestamp = DateTime.now().millisecondsSinceEpoch / 100;
      final ivString = timestamp.toStringAsFixed(0);
      // Take first 12 characters or pad with zeros
      final paddedIv = ivString.length >= 12
          ? ivString.substring(0, 12)
          : ivString.padRight(12, '0');
      return Uint8List.fromList(paddedIv.codeUnits);
    }
    throw ArgumentError(
      'IV generation requires generateIv=true or providing iv',
    );
  }

  /// Extract decryption IV from data for GCM mode
  /// Returns [iv, remainingData]
  static (Uint8List, Uint8List) getDecryptionIv(
    Uint8List data, {
    Uint8List? iv,
  }) {
    if (iv != null) {
      return (iv, data);
    }
    // Extract first 12 bytes as IV
    if (data.length < 12) {
      throw DecryptionException('Data too short to contain IV');
    }
    final extractedIv = Uint8List.sublistView(data, 0, 12);
    final remainingData = Uint8List.sublistView(data, 12);
    return (extractedIv, remainingData);
  }

  /// Encrypt data
  ///
  /// [raw] - Raw bytes to encrypt
  /// [useBase64] - Return base64 encoded result
  /// [usePad] - Apply PKCS7 padding (for ECB mode)
  /// [useIv] - Use GCM mode with IV/nonce (true) or ECB mode (false)
  /// [header] - Additional authenticated data for GCM mode
  Future<dynamic> encrypt({
    required Uint8List raw,
    bool useBase64 = true,
    bool usePad = true,
    bool useIv = false,
    Uint8List? iv,
    Uint8List? header,
  }) async {
    Uint8List cryptedText;

    if (useIv) {
      // GCM mode (for protocol 3.5)
      final nonce = iv ?? getEncryptionIv(generateIv: true);
      final algorithm = AesGcm.with128bits();
      final secretKey = SecretKey(key);

      final secretBox = await algorithm.encrypt(
        raw,
        secretKey: secretKey,
        nonce: nonce,
        aad: header ?? [],
      );

      // Combine: nonce + ciphertext + tag
      cryptedText = Uint8List.fromList([
        ...secretBox.nonce,
        ...secretBox.cipherText,
        ...secretBox.mac.bytes,
      ]);
    } else {
      // ECB mode (for protocols 3.1-3.4)
      // Using vendored pure-Dart AES-ECB implementation
      final cipher = AesEcb(key);
      final dataToEncrypt = usePad ? pad(raw, 16) : raw;
      cryptedText = cipher.encrypt(dataToEncrypt);
    }

    return useBase64 ? base64.encode(cryptedText) : cryptedText;
  }

  /// Decrypt data
  ///
  /// [enc] - Encrypted data (base64 string or bytes)
  /// [useBase64] - Input is base64 encoded
  /// [decodeText] - Decode result as UTF-8 text
  /// [verifyPadding] - Verify PKCS7 padding is correct
  /// [useIv] - GCM mode with IV (true) or ECB mode (false)
  /// [header] - Additional authenticated data for GCM mode
  /// [tag] - Authentication tag for GCM mode (if separate from data)
  Future<dynamic> decrypt({
    required dynamic enc,
    bool useBase64 = true,
    bool decodeText = true,
    bool verifyPadding = false,
    bool useIv = false,
    Uint8List? iv,
    Uint8List? header,
    Uint8List? tag,
  }) async {
    Uint8List encData;

    // Handle base64 decoding
    if (!useIv && useBase64 && enc is String) {
      encData = base64.decode(enc);
    } else if (enc is String) {
      encData = Uint8List.fromList(enc.codeUnits);
    } else if (enc is Uint8List) {
      encData = enc;
    } else {
      throw ArgumentError('enc must be String or Uint8List');
    }

    // Validate length for non-GCM modes
    if (!useIv && encData.length % 16 != 0) {
      throw DecryptionException('Invalid length: ${encData.length}');
    }

    Uint8List raw;

    if (useIv) {
      // GCM mode
      Uint8List nonce;
      Uint8List cipherText;
      Uint8List authTag;

      if (iv != null) {
        nonce = iv;
        if (tag != null) {
          // IV and tag provided separately
          authTag = tag;
          cipherText = encData;
        } else {
          // Extract tag from end (last 16 bytes)
          if (encData.length < 16) {
            throw DecryptionException('Data too short for GCM tag');
          }
          authTag = Uint8List.sublistView(encData, encData.length - 16);
          cipherText = Uint8List.sublistView(encData, 0, encData.length - 16);
        }
      } else {
        // Extract IV from beginning, tag from end
        final (extractedIv, remaining) = getDecryptionIv(encData);
        nonce = extractedIv;
        if (remaining.length < 16) {
          throw DecryptionException('Data too short for GCM tag');
        }
        authTag = Uint8List.sublistView(remaining, remaining.length - 16);
        cipherText = Uint8List.sublistView(remaining, 0, remaining.length - 16);
      }

      final algorithm = AesGcm.with128bits();
      final secretKey = SecretKey(key);
      final secretBox = SecretBox(cipherText, nonce: nonce, mac: Mac(authTag));

      final decrypted = await algorithm.decrypt(
        secretBox,
        secretKey: secretKey,
        aad: header ?? [],
      );

      raw = Uint8List.fromList(decrypted);
    } else {
      // ECB mode (using vendored pure-Dart implementation)
      final cipher = AesEcb(key);
      final decrypted = cipher.decrypt(encData);
      raw = unpad(decrypted, verifyPadding: verifyPadding);
    }

    return decodeText ? utf8.decode(raw) : raw;
  }
}
