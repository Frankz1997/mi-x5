/// Pure Dart AES-128 ECB implementation
/// Used for Tuya protocols 3.1-3.4 (pre-GCM)
///
/// This is a minimal, vendored implementation to avoid PointyCastle dependency.
/// ECB mode is simpler than GCM - no IV, no authentication tag, just block cipher.
///
/// Based on the AES specification (FIPS-197)

library;

import 'dart:typed_data';

/// Pure Dart AES-128 ECB cipher
///
/// Only supports 128-bit keys (16 bytes) for simplicity.
/// Tuya devices use 16-byte keys, so this is sufficient.
class AesEcb {
  final Uint8List _expandedKey;

  AesEcb._(this._expandedKey);

  /// Create cipher from 16-byte key
  factory AesEcb(Uint8List key) {
    if (key.length != 16) {
      throw ArgumentError('Key must be 16 bytes for AES-128');
    }
    final expandedKey = _keyExpansion(key);
    return AesEcb._(expandedKey);
  }

  /// Encrypt a single 16-byte block
  Uint8List encryptBlock(Uint8List block) {
    if (block.length != 16) {
      throw ArgumentError('Block must be 16 bytes');
    }

    // Copy to state array (4x4 matrix, column-major)
    final state = Uint8List.fromList(block);

    // Initial round key addition
    _addRoundKey(state, 0);

    // 9 main rounds for AES-128
    for (var round = 1; round < 10; round++) {
      _subBytes(state);
      _shiftRows(state);
      _mixColumns(state);
      _addRoundKey(state, round);
    }

    // Final round (no MixColumns)
    _subBytes(state);
    _shiftRows(state);
    _addRoundKey(state, 10);

    return state;
  }

  /// Decrypt a single 16-byte block
  Uint8List decryptBlock(Uint8List block) {
    if (block.length != 16) {
      throw ArgumentError('Block must be 16 bytes');
    }

    final state = Uint8List.fromList(block);

    // Initial round key addition
    _addRoundKey(state, 10);

    // 9 main rounds in reverse
    for (var round = 9; round > 0; round--) {
      _invShiftRows(state);
      _invSubBytes(state);
      _addRoundKey(state, round);
      _invMixColumns(state);
    }

    // Final round
    _invShiftRows(state);
    _invSubBytes(state);
    _addRoundKey(state, 0);

    return state;
  }

  /// Encrypt multiple blocks (ECB mode)
  Uint8List encrypt(Uint8List plaintext) {
    if (plaintext.length % 16 != 0) {
      throw ArgumentError(
        'Plaintext length must be multiple of 16 bytes (use padding)',
      );
    }

    final result = Uint8List(plaintext.length);
    for (var i = 0; i < plaintext.length; i += 16) {
      final block = plaintext.sublist(i, i + 16);
      final encrypted = encryptBlock(block);
      result.setRange(i, i + 16, encrypted);
    }
    return result;
  }

  /// Decrypt multiple blocks (ECB mode)
  Uint8List decrypt(Uint8List ciphertext) {
    if (ciphertext.length % 16 != 0) {
      throw ArgumentError('Ciphertext length must be multiple of 16 bytes');
    }

    final result = Uint8List(ciphertext.length);
    for (var i = 0; i < ciphertext.length; i += 16) {
      final block = ciphertext.sublist(i, i + 16);
      final decrypted = decryptBlock(block);
      result.setRange(i, i + 16, decrypted);
    }
    return result;
  }

  // AES Key Expansion for 128-bit key
  static Uint8List _keyExpansion(Uint8List key) {
    final expanded = Uint8List(176); // 11 round keys * 16 bytes

    // Copy original key
    expanded.setRange(0, 16, key);

    // Generate remaining round keys
    var i = 16;
    while (i < 176) {
      var temp = expanded.sublist(i - 4, i);

      if (i % 16 == 0) {
        // RotWord
        final t = temp[0];
        temp[0] = temp[1];
        temp[1] = temp[2];
        temp[2] = temp[3];
        temp[3] = t;

        // SubWord
        for (var j = 0; j < 4; j++) {
          temp[j] = _sBox[temp[j]];
        }

        // XOR with Rcon
        temp[0] ^= _rcon[i ~/ 16];
      }

      for (var j = 0; j < 4; j++) {
        expanded[i + j] = expanded[i + j - 16] ^ temp[j];
      }

      i += 4;
    }

    return expanded;
  }

  void _addRoundKey(Uint8List state, int round) {
    final offset = round * 16;
    for (var i = 0; i < 16; i++) {
      state[i] ^= _expandedKey[offset + i];
    }
  }

  void _subBytes(Uint8List state) {
    for (var i = 0; i < 16; i++) {
      state[i] = _sBox[state[i]];
    }
  }

  void _invSubBytes(Uint8List state) {
    for (var i = 0; i < 16; i++) {
      state[i] = _invSBox[state[i]];
    }
  }

  void _shiftRows(Uint8List state) {
    // Row 1: shift left by 1
    var temp = state[1];
    state[1] = state[5];
    state[5] = state[9];
    state[9] = state[13];
    state[13] = temp;

    // Row 2: shift left by 2
    temp = state[2];
    state[2] = state[10];
    state[10] = temp;
    temp = state[6];
    state[6] = state[14];
    state[14] = temp;

    // Row 3: shift left by 3
    temp = state[15];
    state[15] = state[11];
    state[11] = state[7];
    state[7] = state[3];
    state[3] = temp;
  }

  void _invShiftRows(Uint8List state) {
    // Row 1: shift right by 1
    var temp = state[13];
    state[13] = state[9];
    state[9] = state[5];
    state[5] = state[1];
    state[1] = temp;

    // Row 2: shift right by 2
    temp = state[2];
    state[2] = state[10];
    state[10] = temp;
    temp = state[6];
    state[6] = state[14];
    state[14] = temp;

    // Row 3: shift right by 3
    temp = state[3];
    state[3] = state[7];
    state[7] = state[11];
    state[11] = state[15];
    state[15] = temp;
  }

  void _mixColumns(Uint8List state) {
    for (var i = 0; i < 16; i += 4) {
      final s0 = state[i];
      final s1 = state[i + 1];
      final s2 = state[i + 2];
      final s3 = state[i + 3];

      state[i] = _gMul(s0, 2) ^ _gMul(s1, 3) ^ s2 ^ s3;
      state[i + 1] = s0 ^ _gMul(s1, 2) ^ _gMul(s2, 3) ^ s3;
      state[i + 2] = s0 ^ s1 ^ _gMul(s2, 2) ^ _gMul(s3, 3);
      state[i + 3] = _gMul(s0, 3) ^ s1 ^ s2 ^ _gMul(s3, 2);
    }
  }

  void _invMixColumns(Uint8List state) {
    for (var i = 0; i < 16; i += 4) {
      final s0 = state[i];
      final s1 = state[i + 1];
      final s2 = state[i + 2];
      final s3 = state[i + 3];

      state[i] = _gMul(s0, 14) ^ _gMul(s1, 11) ^ _gMul(s2, 13) ^ _gMul(s3, 9);
      state[i + 1] =
          _gMul(s0, 9) ^ _gMul(s1, 14) ^ _gMul(s2, 11) ^ _gMul(s3, 13);
      state[i + 2] =
          _gMul(s0, 13) ^ _gMul(s1, 9) ^ _gMul(s2, 14) ^ _gMul(s3, 11);
      state[i + 3] =
          _gMul(s0, 11) ^ _gMul(s1, 13) ^ _gMul(s2, 9) ^ _gMul(s3, 14);
    }
  }

  // Galois Field multiplication
  static int _gMul(int a, int b) {
    var p = 0;
    for (var i = 0; i < 8; i++) {
      if ((b & 1) != 0) {
        p ^= a;
      }
      final hiBitSet = (a & 0x80) != 0;
      a = (a << 1) & 0xFF;
      if (hiBitSet) {
        a ^= 0x1B; // AES irreducible polynomial
      }
      b >>= 1;
    }
    return p & 0xFF;
  }

  // AES S-Box
  static final _sBox = Uint8List.fromList([
    0x63,
    0x7C,
    0x77,
    0x7B,
    0xF2,
    0x6B,
    0x6F,
    0xC5,
    0x30,
    0x01,
    0x67,
    0x2B,
    0xFE,
    0xD7,
    0xAB,
    0x76,
    0xCA,
    0x82,
    0xC9,
    0x7D,
    0xFA,
    0x59,
    0x47,
    0xF0,
    0xAD,
    0xD4,
    0xA2,
    0xAF,
    0x9C,
    0xA4,
    0x72,
    0xC0,
    0xB7,
    0xFD,
    0x93,
    0x26,
    0x36,
    0x3F,
    0xF7,
    0xCC,
    0x34,
    0xA5,
    0xE5,
    0xF1,
    0x71,
    0xD8,
    0x31,
    0x15,
    0x04,
    0xC7,
    0x23,
    0xC3,
    0x18,
    0x96,
    0x05,
    0x9A,
    0x07,
    0x12,
    0x80,
    0xE2,
    0xEB,
    0x27,
    0xB2,
    0x75,
    0x09,
    0x83,
    0x2C,
    0x1A,
    0x1B,
    0x6E,
    0x5A,
    0xA0,
    0x52,
    0x3B,
    0xD6,
    0xB3,
    0x29,
    0xE3,
    0x2F,
    0x84,
    0x53,
    0xD1,
    0x00,
    0xED,
    0x20,
    0xFC,
    0xB1,
    0x5B,
    0x6A,
    0xCB,
    0xBE,
    0x39,
    0x4A,
    0x4C,
    0x58,
    0xCF,
    0xD0,
    0xEF,
    0xAA,
    0xFB,
    0x43,
    0x4D,
    0x33,
    0x85,
    0x45,
    0xF9,
    0x02,
    0x7F,
    0x50,
    0x3C,
    0x9F,
    0xA8,
    0x51,
    0xA3,
    0x40,
    0x8F,
    0x92,
    0x9D,
    0x38,
    0xF5,
    0xBC,
    0xB6,
    0xDA,
    0x21,
    0x10,
    0xFF,
    0xF3,
    0xD2,
    0xCD,
    0x0C,
    0x13,
    0xEC,
    0x5F,
    0x97,
    0x44,
    0x17,
    0xC4,
    0xA7,
    0x7E,
    0x3D,
    0x64,
    0x5D,
    0x19,
    0x73,
    0x60,
    0x81,
    0x4F,
    0xDC,
    0x22,
    0x2A,
    0x90,
    0x88,
    0x46,
    0xEE,
    0xB8,
    0x14,
    0xDE,
    0x5E,
    0x0B,
    0xDB,
    0xE0,
    0x32,
    0x3A,
    0x0A,
    0x49,
    0x06,
    0x24,
    0x5C,
    0xC2,
    0xD3,
    0xAC,
    0x62,
    0x91,
    0x95,
    0xE4,
    0x79,
    0xE7,
    0xC8,
    0x37,
    0x6D,
    0x8D,
    0xD5,
    0x4E,
    0xA9,
    0x6C,
    0x56,
    0xF4,
    0xEA,
    0x65,
    0x7A,
    0xAE,
    0x08,
    0xBA,
    0x78,
    0x25,
    0x2E,
    0x1C,
    0xA6,
    0xB4,
    0xC6,
    0xE8,
    0xDD,
    0x74,
    0x1F,
    0x4B,
    0xBD,
    0x8B,
    0x8A,
    0x70,
    0x3E,
    0xB5,
    0x66,
    0x48,
    0x03,
    0xF6,
    0x0E,
    0x61,
    0x35,
    0x57,
    0xB9,
    0x86,
    0xC1,
    0x1D,
    0x9E,
    0xE1,
    0xF8,
    0x98,
    0x11,
    0x69,
    0xD9,
    0x8E,
    0x94,
    0x9B,
    0x1E,
    0x87,
    0xE9,
    0xCE,
    0x55,
    0x28,
    0xDF,
    0x8C,
    0xA1,
    0x89,
    0x0D,
    0xBF,
    0xE6,
    0x42,
    0x68,
    0x41,
    0x99,
    0x2D,
    0x0F,
    0xB0,
    0x54,
    0xBB,
    0x16,
  ]);

  // AES Inverse S-Box
  static final _invSBox = Uint8List.fromList([
    0x52,
    0x09,
    0x6A,
    0xD5,
    0x30,
    0x36,
    0xA5,
    0x38,
    0xBF,
    0x40,
    0xA3,
    0x9E,
    0x81,
    0xF3,
    0xD7,
    0xFB,
    0x7C,
    0xE3,
    0x39,
    0x82,
    0x9B,
    0x2F,
    0xFF,
    0x87,
    0x34,
    0x8E,
    0x43,
    0x44,
    0xC4,
    0xDE,
    0xE9,
    0xCB,
    0x54,
    0x7B,
    0x94,
    0x32,
    0xA6,
    0xC2,
    0x23,
    0x3D,
    0xEE,
    0x4C,
    0x95,
    0x0B,
    0x42,
    0xFA,
    0xC3,
    0x4E,
    0x08,
    0x2E,
    0xA1,
    0x66,
    0x28,
    0xD9,
    0x24,
    0xB2,
    0x76,
    0x5B,
    0xA2,
    0x49,
    0x6D,
    0x8B,
    0xD1,
    0x25,
    0x72,
    0xF8,
    0xF6,
    0x64,
    0x86,
    0x68,
    0x98,
    0x16,
    0xD4,
    0xA4,
    0x5C,
    0xCC,
    0x5D,
    0x65,
    0xB6,
    0x92,
    0x6C,
    0x70,
    0x48,
    0x50,
    0xFD,
    0xED,
    0xB9,
    0xDA,
    0x5E,
    0x15,
    0x46,
    0x57,
    0xA7,
    0x8D,
    0x9D,
    0x84,
    0x90,
    0xD8,
    0xAB,
    0x00,
    0x8C,
    0xBC,
    0xD3,
    0x0A,
    0xF7,
    0xE4,
    0x58,
    0x05,
    0xB8,
    0xB3,
    0x45,
    0x06,
    0xD0,
    0x2C,
    0x1E,
    0x8F,
    0xCA,
    0x3F,
    0x0F,
    0x02,
    0xC1,
    0xAF,
    0xBD,
    0x03,
    0x01,
    0x13,
    0x8A,
    0x6B,
    0x3A,
    0x91,
    0x11,
    0x41,
    0x4F,
    0x67,
    0xDC,
    0xEA,
    0x97,
    0xF2,
    0xCF,
    0xCE,
    0xF0,
    0xB4,
    0xE6,
    0x73,
    0x96,
    0xAC,
    0x74,
    0x22,
    0xE7,
    0xAD,
    0x35,
    0x85,
    0xE2,
    0xF9,
    0x37,
    0xE8,
    0x1C,
    0x75,
    0xDF,
    0x6E,
    0x47,
    0xF1,
    0x1A,
    0x71,
    0x1D,
    0x29,
    0xC5,
    0x89,
    0x6F,
    0xB7,
    0x62,
    0x0E,
    0xAA,
    0x18,
    0xBE,
    0x1B,
    0xFC,
    0x56,
    0x3E,
    0x4B,
    0xC6,
    0xD2,
    0x79,
    0x20,
    0x9A,
    0xDB,
    0xC0,
    0xFE,
    0x78,
    0xCD,
    0x5A,
    0xF4,
    0x1F,
    0xDD,
    0xA8,
    0x33,
    0x88,
    0x07,
    0xC7,
    0x31,
    0xB1,
    0x12,
    0x10,
    0x59,
    0x27,
    0x80,
    0xEC,
    0x5F,
    0x60,
    0x51,
    0x7F,
    0xA9,
    0x19,
    0xB5,
    0x4A,
    0x0D,
    0x2D,
    0xE5,
    0x7A,
    0x9F,
    0x93,
    0xC9,
    0x9C,
    0xEF,
    0xA0,
    0xE0,
    0x3B,
    0x4D,
    0xAE,
    0x2A,
    0xF5,
    0xB0,
    0xC8,
    0xEB,
    0xBB,
    0x3C,
    0x83,
    0x53,
    0x99,
    0x61,
    0x17,
    0x2B,
    0x04,
    0x7E,
    0xBA,
    0x77,
    0xD6,
    0x26,
    0xE1,
    0x69,
    0x14,
    0x63,
    0x55,
    0x21,
    0x0C,
    0x7D,
  ]);

  // Round constants for key expansion
  static final _rcon = Uint8List.fromList([
    0x00,
    0x01,
    0x02,
    0x04,
    0x08,
    0x10,
    0x20,
    0x40,
    0x80,
    0x1B,
    0x36,
  ]);
}
