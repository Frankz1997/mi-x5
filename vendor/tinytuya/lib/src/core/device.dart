/// Base Device class for Tuya devices
/// Ported from tinytuya/core/XenonDevice.py and Device.py

library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'crypto_helper.dart';
import 'header.dart';
import 'payload_dict.dart';
import 'command_types.dart';
import 'message_helper.dart';
import 'exceptions.dart';
import 'const.dart';

/// Base class for Tuya device communication
class Device {
  final String deviceId;
  final String address;
  final String localKey;
  final double version;
  final String devType;
  final int port;
  final Duration connectionTimeout;
  final int socketRetryLimit;
  final Duration socketRetryDelay;
  final bool socketNoDelay;
  final bool persist;

  int _seqno = 1; // Start at 1 to match Python behavior
  AESCipher? _cipher;
  Map<int, CommandConfig>? _payloadDict;
  String _lastDevType = '';
  Map<String, dynamic> dpsToRequest = {};
  Map<String, dynamic>? _lastStatus;
  Socket? _socket;
  StreamSubscription<Uint8List>? _socketSubscription;
  final List<int> _receiveBuffer = [];
  final List<Completer<void>> _bufferWaiters = [];
  Uint8List _versionHeader = Uint8List(0);

  // Operation mutex to prevent concurrent device operations
  // This prevents race conditions in session key negotiation
  Completer<void>? _operationLock;

  // Session key negotiation fields (for v3.4+)
  late final String _realLocalKey; // Original local key
  late String
  _sessionKey; // Negotiated session key (replaces localKey after negotiation)
  Uint8List? _localNonce; // Local nonce for session key negotiation
  Uint8List? _remoteNonce; // Remote nonce from device
  bool _sessionKeyNegotiated =
      false; // Track if session key has been negotiated for current connection

  Device({
    required this.deviceId,
    required this.address,
    required this.localKey,
    this.version = 3.3,
    this.devType = 'default',
    this.port = tcpPort,
    this.connectionTimeout = const Duration(seconds: 5),
    this.socketRetryLimit = 5,
    this.socketRetryDelay = const Duration(seconds: 5),
    this.socketNoDelay = true,
    this.persist =
        false, // Default false to match Python's socketPersistent=False
  }) {
    _initVersionHeader();
    _realLocalKey = localKey;
    _sessionKey =
        localKey; // Initially use the real key, will be replaced after negotiation
  }

  /// Get version string (e.g., "3.3" -> "v3.3", "3.4" -> "v3.4")
  String get versionStr {
    // Special handling for versions
    if (version >= 3.4 && version < 3.5) {
      return 'v3.4';
    } else if (version >= 3.5) {
      return 'v3.5';
    }
    return 'v${version.toStringAsFixed(1)}';
  }

  /// Initialize the version header for protocol 3.x
  void _initVersionHeader() {
    final versionBytes = Uint8List.fromList(
      version.toStringAsFixed(1).codeUnits,
    );
    _versionHeader = Uint8List.fromList([...versionBytes, ...protocol3xHeader]);
  }

  /// Initialize the cipher
  void _initCipher() {
    // Always create a new cipher to ensure we use the current session key
    _cipher = AESCipher.fromString(_sessionKey);
  }

  /// Close the socket connection
  Future<void> _closeSocket() async {
    // Complete any waiting operations with error BEFORE cancelling subscription
    while (_bufferWaiters.isNotEmpty) {
      final waiter = _bufferWaiters.removeAt(0);
      if (!waiter.isCompleted) {
        waiter.completeError(DecodeError('Socket closed'));
      }
    }

    // CRITICAL: Close socket FIRST, then cancel subscription
    // This prevents "StreamSink is bound to a stream" errors
    if (_socket != null) {
      try {
        await _socket!.close();
      } catch (e) {
        // Ignore errors during close
      }
      _socket = null;
    }

    // Cancel subscription after socket is closed
    if (_socketSubscription != null) {
      try {
        await _socketSubscription!.cancel();
      } catch (e) {
        // Ignore errors during cancel
      }
      _socketSubscription = null;
    }

    // Clear buffers
    _receiveBuffer.clear();

    // Reset session key state for next connection
    _sessionKeyNegotiated = false;
    _sessionKey = _realLocalKey; // Reset to original key
  }

  /// Check if socket should be closed (matches Python's _check_socket_close)
  ///
  /// Closes socket if force=true or if persist=false (not persistent mode).
  /// This matches Python TinyTuya's socketPersistent behavior.
  Future<void> _checkSocketClose({bool force = false}) async {
    if ((force || !persist) && _socket != null) {
      await _closeSocket();
      // Clear cached status (matches Python's cache_clear())
      _lastStatus = null;
    }
  }

  /// Acquire operation lock to prevent concurrent device operations
  Future<void> _acquireLock() async {
    while (_operationLock != null) {
      // Wait for the current operation to complete
      await _operationLock!.future;
    }
    // Now create a new lock for this operation
    _operationLock = Completer<void>();
  }

  /// Release operation lock
  void _releaseLock() {
    if (_operationLock != null && !_operationLock!.isCompleted) {
      _operationLock!.complete();
      _operationLock = null;
    }
  }

  /// Negotiate session key for v3.4+ devices
  /// Returns true if successful, false otherwise
  Future<bool> _negotiateSessionKey() async {
    try {
      // Step 1: Send local nonce
      _localNonce = Uint8List.fromList(
        '0123456789abcdef'.codeUnits,
      ); // 16 bytes
      _remoteNonce = null;

      final step1Payload = MessagePayload(
        cmd: sessKeyNegStart,
        payload: _localNonce!,
      );

      // Send step 1 and receive step 2 response
      final response = await _sendReceiveQuick(
        step1Payload,
        expectCmd: sessKeyNegResp,
      );
      if (response == null) {
        return false;
      }

      // Step 2: Process response
      if (!await _negotiateSessionKeyStep2(response)) {
        return false;
      }

      // Step 3: Send HMAC of remote nonce
      final step3Payload = await _negotiateSessionKeyStep3();
      if (step3Payload == null) {
        return false;
      }

      await _sendReceiveQuick(
        step3Payload,
        expectCmd: null,
      ); // No response expected

      // Finalize: Generate session key
      await _negotiateSessionKeyFinalize();

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Process step 2 of session key negotiation
  Future<bool> _negotiateSessionKeyStep2(TuyaMessage response) async {
    var payload = response.payload;

    // For v3.4, decrypt the response payload first
    if (version == 3.4) {
      try {
        final cipher = AESCipher(Uint8List.fromList(_realLocalKey.codeUnits));
        payload =
            await cipher.decrypt(
                  enc: payload,
                  useBase64: false,
                  decodeText: false,
                )
                as Uint8List;
      } catch (e) {
        return false;
      }
    }

    // For v3.5, skip the 4-byte retcode prefix
    var offset = 0;
    if (version >= 3.5) {
      if (payload.length < 52) {
        // 4 (retcode) + 16 (nonce) + 32 (hmac)
        return false;
      }
      offset = 4; // Skip retcode
    } else {
      if (payload.length < 48) {
        return false;
      }
    }

    // Extract remote nonce (first 16 bytes after offset)
    _remoteNonce = payload.sublist(offset, offset + 16);

    // Validate HMAC (next 32 bytes should be HMAC of local nonce)
    final hmacCheck = await _calculateHmac(_realLocalKey, _localNonce!);
    final receivedHmac = payload.sublist(offset + 16, offset + 48);

    if (!_bytesEqual(hmacCheck, receivedHmac)) {
      return false;
    }

    return true;
  }

  /// Generate step 3 payload (HMAC of remote nonce)
  Future<MessagePayload?> _negotiateSessionKeyStep3() async {
    if (_remoteNonce == null) {
      return null;
    }

    final hmac = await _calculateHmac(_realLocalKey, _remoteNonce!);
    return MessagePayload(cmd: sessKeyNegFinish, payload: hmac);
  }

  /// Finalize session key negotiation by generating the session key
  Future<void> _negotiateSessionKeyFinalize() async {
    if (_localNonce == null || _remoteNonce == null) {
      throw TinyTuyaException('Cannot finalize session key: missing nonces');
    }

    // XOR local and remote nonces
    final xored = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      xored[i] = _localNonce![i] ^ _remoteNonce![i];
    }

    // Encrypt the XOR'd result to get session key
    final cipher = AESCipher(Uint8List.fromList(_realLocalKey.codeUnits));

    if (version == 3.4) {
      // For v3.4: Encrypt with AES-ECB (no IV, no padding)
      final encrypted = await cipher.encrypt(
        raw: xored,
        useBase64: false,
        usePad: false,
      );
      _sessionKey = String.fromCharCodes(encrypted);
    } else {
      // For v3.5: Encrypt with AES-GCM using IV from local nonce, take bytes [12:28]
      final iv = _localNonce!.sublist(0, 12);
      final encrypted = await cipher.encrypt(
        raw: xored,
        useBase64: false,
        usePad: false,
        useIv: true,
        iv: iv,
      );
      _sessionKey = String.fromCharCodes(encrypted.sublist(12, 28));
    }
  }

  /// Helper to calculate HMAC-SHA256
  Future<Uint8List> _calculateHmac(String key, Uint8List data) async {
    final hmac = crypto.Hmac(crypto.sha256, Uint8List.fromList(key.codeUnits));
    final digest = hmac.convert(data);
    return Uint8List.fromList(digest.bytes);
  }

  /// Helper to compare byte arrays
  bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Send/receive for session key negotiation (quick mode)
  Future<TuyaMessage?> _sendReceiveQuick(
    MessagePayload payload, {
    int? expectCmd,
  }) async {
    try {
      // Encode and send
      final encodedMsg = await _encodeMessage(payload);
      _socket!.add(encodedMsg);
      await _socket!.flush();

      if (expectCmd == null) {
        return null; // No response expected
      }

      // Receive response
      final response = await _receive();

      if (response.cmd != expectCmd) {
        return null;
      }

      return response;
    } catch (e) {
      return null;
    }
  }

  /// Receive exact number of bytes from socket
  Future<Uint8List> _recvAll(int length) async {
    final result = <int>[];
    var tries = 2;

    while (result.length < length) {
      // If buffer doesn't have enough data, wait for more
      if (_receiveBuffer.isEmpty) {
        final completer = Completer<void>();
        _bufferWaiters.add(completer);

        try {
          await completer.future.timeout(connectionTimeout);
        } catch (e) {
          _bufferWaiters.remove(completer);
          if (e is TimeoutException) {
            tries--;
            if (tries == 0) {
              throw DecodeError('Timeout receiving data');
            }
            continue;
          }
          rethrow;
        }

        // Check if we actually got data
        if (_receiveBuffer.isEmpty) {
          tries--;
          if (tries == 0) {
            throw DecodeError('No data received - connection closed?');
          }
          await Future.delayed(const Duration(milliseconds: 10));
          continue;
        }
      }

      // Take what we need from buffer
      final needed = length - result.length;
      final available = _receiveBuffer.length;
      final toTake = needed < available ? needed : available;

      result.addAll(_receiveBuffer.take(toTake));
      _receiveBuffer.removeRange(0, toTake);
      tries = 2; // Reset tries on successful read
    }

    return Uint8List.fromList(result);
  }

  /// Get or create socket connection
  Future<bool> _getSocket({bool renew = false}) async {
    if (renew && _socket != null) {
      await _closeSocket();
    }

    if (_socket != null) {
      return true; // Existing socket active
    }

    // Validate local key for v3.2+
    if (version > 3.1 && (localKey.isEmpty || localKey.length < 16)) {
      throw TinyTuyaException('Invalid local key for version $version');
    }

    var retries = 0;
    while (retries < socketRetryLimit) {
      try {
        retries++;

        // Create socket and connect
        _socket = await Socket.connect(
          address,
          port,
          timeout: connectionTimeout,
        );

        if (socketNoDelay) {
          _socket!.setOption(SocketOption.tcpNoDelay, true);
        }

        // Set up stream subscription to populate receive buffer
        _socketSubscription = _socket!.listen(
          (data) {
            _receiveBuffer.addAll(data);
            // Wake up any waiters
            while (_bufferWaiters.isNotEmpty) {
              final waiter = _bufferWaiters.removeAt(0);
              if (!waiter.isCompleted) {
                waiter.complete();
              }
            }
          },
          onError: (error) {
            // Complete all waiters with error
            while (_bufferWaiters.isNotEmpty) {
              final waiter = _bufferWaiters.removeAt(0);
              if (!waiter.isCompleted) {
                waiter.completeError(error);
              }
            }
          },
          onDone: () {
            // Complete all waiters (connection closed)
            while (_bufferWaiters.isNotEmpty) {
              final waiter = _bufferWaiters.removeAt(0);
              if (!waiter.isCompleted) {
                waiter.complete();
              }
            }
          },
          cancelOnError: false,
        );

        // For v3.4+, perform session key negotiation (only once per connection)
        if (version >= 3.4 && !_sessionKeyNegotiated) {
          final negotiated = await _negotiateSessionKey();
          if (!negotiated) {
            await _closeSocket();
            throw TinyTuyaException('Session key negotiation failed');
          }
          _sessionKeyNegotiated = true;
        }

        return true;
      } on SocketException {
        await _closeSocket();
        if (retries < socketRetryLimit) {
          await Future.delayed(socketRetryDelay);
        }
      } on TimeoutException {
        await _closeSocket();
        if (retries < socketRetryLimit) {
          await Future.delayed(socketRetryDelay);
        }
      }
    }

    throw TinyTuyaException(
      'Unable to connect to device after $socketRetryLimit attempts',
    );
  }

  /// Get next sequence number
  int get seqno {
    final current = _seqno;
    _seqno++;
    return current;
  }

  /// Build the merged payload dictionary for this device
  Map<int, CommandConfig> _buildPayloadDict() {
    final result = <int, CommandConfig>{};

    // Start with default
    mergePayloadDicts(result, payloadDict['default']!);

    // Add version-specific overrides
    final versionKey = versionStr;
    if (payloadDict.containsKey(versionKey)) {
      mergePayloadDicts(result, payloadDict[versionKey]!);
    }

    // Add device type specific overrides
    if (devType != 'default' && payloadDict.containsKey(devType)) {
      mergePayloadDicts(result, payloadDict[devType]!);
    }

    return result;
  }

  /// Encode a MessagePayload into bytes for transmission
  Future<Uint8List> _encodeMessage(MessagePayload msg) async {
    _initCipher();

    Uint8List? hmacKey;
    bool useIv = false;
    var payload = msg.payload;

    if (version >= 3.4) {
      hmacKey = Uint8List.fromList(_sessionKey.codeUnits);

      // Add version header to payload (unless it's a special command)
      if (!noProtocolHeaderCmds.contains(msg.cmd)) {
        payload = Uint8List.fromList([..._versionHeader, ...payload]);
      }

      if (version >= 3.5) {
        useIv = true;
      } else {
        // For v3.4, encrypt payload with AES-ECB before packing
        payload = await _cipher!.encrypt(
          raw: payload,
          useBase64: false,
          usePad: true,
        );
      }
    } else if (version >= 3.2) {
      // For v3.2/v3.3: Encrypt FIRST, then add version header
      payload = await _cipher!.encrypt(
        raw: payload,
        useBase64: false,
        usePad: true,
      );

      // Then add version header (unless it's a special command)
      if (!noProtocolHeaderCmds.contains(msg.cmd)) {
        payload = Uint8List.fromList([..._versionHeader, ...payload]);
      }
    }

    // Create TuyaMessage
    final tuyaMsg = TuyaMessage(
      seqno: _seqno++,
      cmd: msg.cmd,
      retcode: 0,
      payload: payload,
      crc: 0,
      crcGood: true,
      prefix: version >= 3.5 ? prefix6699Value : prefix55aaValue,
      iv: useIv ? null : null, // Let packMessage generate IV if needed
    );

    // Pack the message
    final packed = await packMessage(tuyaMsg, hmacKey: hmacKey);

    return packed;
  }

  /// Receive a message from the device
  Future<TuyaMessage> _receive() async {
    // Minimum message lengths
    const minLen55aa = 16 + 4 + 4 + 4; // header + retcode + crc + suffix
    const minLen6699 =
        20 + 12 + 4 + 16 + 4; // header + iv + retcode + tag + suffix
    const minLen = minLen55aa < minLen6699 ? minLen55aa : minLen6699;

    // Read minimum amount of data
    var data = await _recvAll(minLen);

    // Search for message prefix
    var prefix55aaOffset = _findBytes(data, prefix55aaBin);
    var prefix6699Offset = _findBytes(data, prefix6699Bin);

    // Align to message start
    while (prefix55aaOffset != 0 && prefix6699Offset != 0) {
      if (prefix55aaOffset < 0 && prefix6699Offset < 0) {
        // No prefix found, keep last 3 bytes and read more
        data = Uint8List.fromList([
          ...data.sublist(data.length - 3),
          ...await _recvAll(minLen - 3),
        ]);
      } else {
        // Prefix found but not at start, skip to it
        final offset = prefix6699Offset < 0
            ? prefix55aaOffset
            : prefix6699Offset;
        data = Uint8List.fromList([
          ...data.sublist(offset),
          ...await _recvAll(minLen - (data.length - offset)),
        ]);
      }
      prefix55aaOffset = _findBytes(data, prefix55aaBin);
      prefix6699Offset = _findBytes(data, prefix6699Bin);
    }

    // Parse header to get total message length
    final header = parseHeader(data);
    final remaining = header.totalLength - data.length;

    if (remaining > 0) {
      data = Uint8List.fromList([...data, ...await _recvAll(remaining)]);
    }

    // Unpack message
    final hmacKey = version >= 3.4
        ? Uint8List.fromList(_sessionKey.codeUnits)
        : null;
    return await unpackMessage(data, hmacKey: hmacKey, header: header);
  }

  /// Find bytes in a Uint8List, returns index or -1
  int _findBytes(Uint8List data, Uint8List pattern) {
    for (var i = 0; i <= data.length - pattern.length; i++) {
      var found = true;
      for (var j = 0; j < pattern.length; j++) {
        if (data[i + j] != pattern[j]) {
          found = false;
          break;
        }
      }
      if (found) return i;
    }
    return -1;
  }

  /// Decode and decrypt payload from device
  Future<Map<String, dynamic>> _decodePayload(Uint8List payload) async {
    var data = payload;

    if (version == 3.4) {
      // For v3.4: Decrypt FIRST, then check for version header
      // Python: "3.4 devices encrypt the version header in addition to the payload"
      final cipher = AESCipher(Uint8List.fromList(_sessionKey.codeUnits));
      data =
          await cipher.decrypt(enc: data, useBase64: false, decodeText: false)
              as Uint8List;

      // After decryption, check if it starts with version header
      final versionBytes = utf8.encode(version.toString());
      if (data.length >= versionBytes.length + 12) {
        var hasVersionHeader = true;
        for (var i = 0; i < versionBytes.length; i++) {
          if (data[i] != versionBytes[i]) {
            hasVersionHeader = false;
            break;
          }
        }
        if (hasVersionHeader) {
          // Remove version string + PROTOCOL_3x_HEADER (12 null bytes)
          data = data.sublist(versionBytes.length + 12);
        }
      }
    } else if (version >= 3.2) {
      // For v3.2/v3.3/v3.5: Check for version header FIRST
      final versionStr = version.toString();
      final versionBytes = utf8.encode(versionStr);

      var offset = 0;

      // For v3.5, check if payload starts with 4-byte retcode (all zeros)
      // Control responses have format: retcode + version header + JSON
      if (version >= 3.5 &&
          data.length >= 4 &&
          data[0] == 0 &&
          data[1] == 0 &&
          data[2] == 0 &&
          data[3] == 0) {
        // Check if after retcode comes version string
        if (data.length >= 4 + versionBytes.length) {
          var hasVersionAfterRetcode = true;
          for (var i = 0; i < versionBytes.length; i++) {
            if (data[4 + i] != versionBytes[i]) {
              hasVersionAfterRetcode = false;
              break;
            }
          }
          if (hasVersionAfterRetcode) {
            // Skip the retcode
            offset = 4;
          }
        }
      }

      var hasVersionHeader = false;
      if (data.length >= offset + versionBytes.length) {
        hasVersionHeader = true;
        for (var i = 0; i < versionBytes.length; i++) {
          if (data[offset + i] != versionBytes[i]) {
            hasVersionHeader = false;
            break;
          }
        }
      }

      if (hasVersionHeader) {
        // Remove version string + PROTOCOL_3x_HEADER (12 bytes, may contain non-zero values)
        final totalHeaderSize = versionBytes.length + 12;
        data = data.sublist(offset + totalHeaderSize);
      } else if (offset > 0) {
        // Had retcode but no version header - just skip retcode
        data = data.sublist(offset);
      }

      // For v3.3, decrypt after removing header
      // For v3.5, control responses are plain JSON (not GCM encrypted)
      if (version < 3.4) {
        // Decrypt the remaining data using AES-ECB with localKey
        final cipher = AESCipher(Uint8List.fromList(localKey.codeUnits));
        data =
            await cipher.decrypt(enc: data, useBase64: false, decodeText: false)
                as Uint8List;
      }
      // v3.5 with version header is plain JSON, no decryption needed
    }

    // Check if payload is empty or contains only null bytes (empty ACK)
    // v3.5 devices sometimes send [0, 0, 0, 0] as an acknowledgement
    if (data.isEmpty || data.every((byte) => byte == 0)) {
      // Empty acknowledgement - command was successful but no data returned
      return {};
    }

    // Try to parse as JSON
    try {
      final payloadStr = utf8.decode(data);
      return jsonDecode(payloadStr) as Map<String, dynamic>;
    } catch (e) {
      return {'Error': 'Failed to decode payload: $e', 'raw': data};
    }
  }

  /// Send a payload and receive response
  Future<Map<String, dynamic>> _sendReceive(
    MessagePayload payload, {
    bool getResponse = true,
    int retryCount = 0,
  }) async {
    // Acquire lock to prevent concurrent operations
    await _acquireLock();

    try {
      // Get socket connection
      await _getSocket();

      // Encode and send message
      final encodedMsg = await _encodeMessage(payload);
      _socket!.add(encodedMsg);
      await _socket!.flush();

      if (!getResponse) {
        // Close socket if not in persistent mode (matches Python behavior)
        await _checkSocketClose();
        return {'success': true};
      }

      // Give device time to respond (matches Python's sendWait)
      await Future.delayed(const Duration(milliseconds: 10));

      // Receive response with retries for empty payloads
      // Devices may send empty ACK first, then actual response
      // v3.5 needs more retries due to GCM encryption overhead
      final maxRecvRetries = version >= 3.5 ? 4 : 2;
      var recvRetries = 0;
      TuyaMessage? response;

      while (recvRetries <= maxRecvRetries) {
        response = await _receive();

        // If we got a non-empty payload, we're done
        if (response.payload.isNotEmpty) {
          break;
        }

        // Empty payload - retry if we haven't exceeded limit
        recvRetries++;
        if (recvRetries <= maxRecvRetries) {
          // Wait a bit before next receive attempt
          // v3.5 needs longer waits
          final delay = version >= 3.5 ? 100 : 50;
          await Future.delayed(Duration(milliseconds: delay));
        }
      }

      // Decode and decrypt payload
      if (response != null && response.payload.isNotEmpty) {
        final decoded = await _decodePayload(response.payload);

        // Normalize response: if dps is nested in 'data', copy it to top level
        // This matches Python's behavior for consistent API
        final result = {'success': response.crcGood, ...decoded};

        // If data.dps exists but top-level dps doesn't, copy it up
        if (result['data'] is Map &&
            (result['data'] as Map).containsKey('dps') &&
            !result.containsKey('dps')) {
          result['dps'] = (result['data'] as Map)['dps'];
        }

        // Close socket if not in persistent mode (matches Python behavior)
        await _checkSocketClose();
        return result;
      }

      // Close socket if not in persistent mode (matches Python behavior)
      await _checkSocketClose();
      return {'success': response?.crcGood ?? false};
    } catch (e) {
      // Check if this is a timeout/connection error that we should retry
      final errorStr = e.toString();
      final isTimeoutError =
          errorStr.contains('Timeout') ||
          errorStr.contains('timeout') ||
          e is TimeoutException ||
          e is DecodeError;

      if (isTimeoutError && retryCount < 1) {
        // Socket connection has died (likely idle timeout)
        // Close the dead socket and retry with a fresh connection
        _releaseLock();
        await _closeSocket();

        // Retry once with a new connection
        return await _sendReceive(
          payload,
          getResponse: getResponse,
          retryCount: retryCount + 1,
        );
      }

      // CRITICAL: Always close socket on error to ensure clean state for next operation
      // Any error indicates the socket/buffer is in an unknown/corrupted state
      await _closeSocket();

      return {'Error': e.toString()};
    } finally {
      // CRITICAL: Always release lock, even if an exception escapes this method
      // This ensures we never deadlock if a timeout occurs from outside this method
      _releaseLock();
    }
  }

  /// Generate the payload to send
  ///
  /// Args:
  ///   command: The type of command (from command_types.dart)
  ///   data: The data to send (will be passed via 'dps' or 'dpId' entry depending on command)
  ///   gwId: Optional gwId override
  ///   devId: Optional devId override
  ///   uid: Optional uid override
  MessagePayload generatePayload({
    required int command,
    dynamic data,
    String? gwId,
    String? devId,
    String? uid,
  }) {
    // Build payload dict if needed or if dev_type changed
    if (_payloadDict == null || _lastDevType != devType) {
      _payloadDict = _buildPayloadDict();
      _lastDevType = devType;
    }

    Map<String, dynamic>? jsonData;
    int? commandOverride;

    // Get command configuration from payload dict
    if (_payloadDict!.containsKey(command)) {
      final config = _payloadDict![command]!;
      jsonData = config.copyCommand();
      commandOverride = config.commandOverride;
    }

    // Use command override if specified
    commandOverride ??= command;

    // Default payload structure if not defined
    jsonData ??= {'gwId': '', 'devId': '', 'uid': '', 't': ''};

    // Fill in gwId
    if (jsonData.containsKey('gwId')) {
      jsonData['gwId'] = gwId ?? deviceId;
    }

    // Fill in devId
    if (jsonData.containsKey('devId')) {
      jsonData['devId'] = devId ?? deviceId;
    }

    // Fill in uid
    if (jsonData.containsKey('uid')) {
      jsonData['uid'] = uid ?? deviceId;
    }

    // Fill in timestamp
    if (jsonData.containsKey('t')) {
      if (jsonData['t'] == 'int') {
        jsonData['t'] = (DateTime.now().millisecondsSinceEpoch / 1000).floor();
      } else {
        jsonData['t'] = ((DateTime.now().millisecondsSinceEpoch / 1000).floor())
            .toString();
      }
    }

    // Add data if provided
    if (data != null) {
      if (jsonData.containsKey('dpId')) {
        jsonData['dpId'] = data;
      } else if (jsonData.containsKey('data')) {
        // Handle nested 'data' field (for v3.4+)
        final dataField = jsonData['data'];
        if (dataField is Map) {
          final dataMap = Map<String, dynamic>.from(dataField);
          dataMap['dps'] = data;
          jsonData['data'] = dataMap;
        }
      } else {
        jsonData['dps'] = data;
      }
    } else if (devType == 'device22' && command == dpQuery) {
      jsonData['dps'] = dpsToRequest;
    }

    // Convert to JSON string
    final payloadStr = jsonEncode(jsonData);
    // Remove spaces - device does not respond with spaces!
    final payloadStrCompact = payloadStr.replaceAll(' ', '');
    final payloadBytes = Uint8List.fromList(utf8.encode(payloadStrCompact));

    return MessagePayload(cmd: commandOverride, payload: payloadBytes);
  }

  /// Set status of the device to 'on' or 'off'
  ///
  /// Args:
  ///   on: True for 'on', False for 'off'
  ///   switch: The switch to set (default '1')
  ///   nowait: True to send without waiting for response
  Future<Map<String, dynamic>> setStatus({
    required bool on,
    String switchNum = '1',
    bool nowait = false,
  }) async {
    final payload = generatePayload(command: control, data: {switchNum: on});

    return await _sendReceive(payload, getResponse: !nowait);
  }

  /// Set value of any index
  ///
  /// Args:
  ///   index: Index to set (as string or int)
  ///   value: New value for the index
  ///   nowait: True to send without waiting for response
  Future<Map<String, dynamic>> setValue({
    required dynamic index,
    required dynamic value,
    bool nowait = false,
  }) async {
    final indexStr = index is int ? index.toString() : index as String;

    final payload = generatePayload(command: control, data: {indexStr: value});

    return await _sendReceive(payload, getResponse: !nowait);
  }

  /// Get device status
  Future<Map<String, dynamic>> status() async {
    // Clear receive buffer to avoid reading stale responses
    // For v3.5, do multiple flush cycles to ensure all stale data is cleared
    if (version >= 3.5) {
      for (var i = 0; i < 3; i++) {
        await Future.delayed(const Duration(milliseconds: 30));
        _receiveBuffer.clear();
      }
    } else {
      // For v3.3/v3.4, single flush is sufficient
      await Future.delayed(const Duration(milliseconds: 50));
      _receiveBuffer.clear();
    }

    final payload = generatePayload(command: dpQuery);
    final result = await _sendReceive(payload);
    _lastStatus = result;
    return result;
  }

  /// Send heartbeat to keep connection alive
  Future<Map<String, dynamic>> heartbeat({bool nowait = true}) async {
    final payload = generatePayload(command: heartBeat);
    return await _sendReceive(payload, getResponse: !nowait);
  }

  /// Turn the device on
  ///
  /// Args:
  ///   switchNum: The switch to turn on (default '1')
  ///   nowait: True to send without waiting for response
  Future<Map<String, dynamic>> turnOn({
    String switchNum = '1',
    bool nowait = false,
  }) async {
    return await setStatus(on: true, switchNum: switchNum, nowait: nowait);
  }

  /// Turn the device off
  ///
  /// Args:
  ///   switchNum: The switch to turn off (default '1')
  ///   nowait: True to send without waiting for response
  Future<Map<String, dynamic>> turnOff({
    String switchNum = '1',
    bool nowait = false,
  }) async {
    return await setStatus(on: false, switchNum: switchNum, nowait: nowait);
  }

  /// Set a timer
  ///
  /// Args:
  ///   numSecs: Number of seconds for the timer
  ///   dpsId: DPS index for timer (default 0)
  ///   nowait: True to send without waiting for response
  Future<Map<String, dynamic>> setTimer({
    required int numSecs,
    int dpsId = 0,
    bool nowait = false,
  }) async {
    final indexStr = dpsId.toString();
    return await setValue(index: indexStr, value: numSecs, nowait: nowait);
  }

  /// Request device to update specific DPS indices
  ///
  /// Args:
  ///   index: List of DPS indices to update (defaults to [1])
  ///   nowait: True to send without waiting for response
  Future<Map<String, dynamic>> updateDps({
    List<int>? index,
    bool nowait = false,
  }) async {
    index ??= [1];

    final payload = generatePayload(command: updatedps, data: index);

    return await _sendReceive(payload, getResponse: !nowait);
  }

  /// Get cached status without querying device
  ///
  /// Args:
  ///   historic: If true, return last status even if empty
  Future<Map<String, dynamic>?> cachedStatus({bool historic = false}) async {
    if (_lastStatus != null || historic) {
      return _lastStatus;
    }
    // If no cached status and not historic, get fresh status
    return await status();
  }

  /// Set multiple DPS values at once
  ///
  /// Args:
  ///   dps: Map of DPS index to value
  ///   nowait: True to send without waiting for response
  Future<Map<String, dynamic>> setMultipleValues(
    Map<dynamic, dynamic> dps, {
    bool nowait = false,
  }) async {
    final payload = generatePayload(command: control, data: {'dps': dps});
    final result = await _sendReceive(payload, getResponse: !nowait);
    if (result.isNotEmpty) {
      _lastStatus = result;
    }
    return result;
  }

  /// Close connection
  Future<void> close() async {
    await _closeSocket();
  }

  /// Get socket state for debugging/testing
  /// Returns true if socket is active, false if closed
  bool get isSocketActive => _socket != null;
}
