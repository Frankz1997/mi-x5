/// Custom exceptions for tinytuya library
/// Ported from tinytuya/core/exceptions.py

library;

/// Base exception for all tinytuya errors
class TinyTuyaException implements Exception {
  final String message;

  TinyTuyaException(this.message);

  @override
  String toString() => 'TinyTuyaException: $message';
}

/// Exception raised when decryption fails
class DecryptionException extends TinyTuyaException {
  DecryptionException(super.message);

  @override
  String toString() => 'DecryptionException: $message';
}

/// Exception raised when device connection fails
class ConnectionException extends TinyTuyaException {
  ConnectionException(super.message);

  @override
  String toString() => 'ConnectionException: $message';
}

/// Exception raised when device timeout occurs
class TimeoutException extends TinyTuyaException {
  TimeoutException(super.message);

  @override
  String toString() => 'TimeoutException: $message';
}

/// Exception raised when message decoding fails
class DecodeError extends TinyTuyaException {
  DecodeError(super.message);

  @override
  String toString() => 'DecodeError: $message';
}
