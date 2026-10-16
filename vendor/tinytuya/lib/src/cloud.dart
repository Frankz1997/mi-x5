/// Tuya Cloud API Client
/// Ported from tinytuya/Cloud.py

library;

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

/// Cloud API client for Tuya IoT Platform
///
/// Provides methods to:
/// - Authenticate with Tuya Cloud
/// - Get list of devices with local keys
/// - Get device status and specifications
/// - Send commands to devices via cloud
class Cloud {
  /// API Key (Client ID)
  final String apiKey;

  /// API Secret
  final String apiSecret;

  /// API Region (us, eu, cn, in, sg, etc.)
  String apiRegion;

  /// API endpoint hostname
  String urlHost = '';

  /// Access token for authenticated requests
  String? token;

  /// Whether to use new signing algorithm (post June 30, 2021)
  final bool newSignAlgorithm;

  /// Server time offset in seconds
  int serverTimeOffset = 0;

  /// Last error message
  Map<String, dynamic>? error;

  /// Region to URL host mapping
  static const Map<String, String> regionHosts = {
    'cn': 'openapi.tuyacn.com', // China Data Center
    'us': 'openapi.tuyaus.com', // Western America Data Center
    'az': 'openapi.tuyaus.com', // Alias for us
    'us-e': 'openapi-ueaz.tuyaus.com', // Eastern America Data Center
    'ue': 'openapi-ueaz.tuyaus.com', // Alias for us-e
    'eu': 'openapi.tuyaeu.com', // Central Europe Data Center
    'eu-w': 'openapi-weaz.tuyaeu.com', // Western Europe Data Center
    'we': 'openapi-weaz.tuyaeu.com', // Alias for eu-w
    'in': 'openapi.tuyain.com', // India Data Center
    'sg': 'openapi-sg.iotbing.com', // Singapore Data Center
  };

  /// Constructor
  Cloud({
    required this.apiKey,
    required this.apiSecret,
    required this.apiRegion,
    this.token,
    this.newSignAlgorithm = true,
  }) {
    setRegion(apiRegion);
  }

  /// Initialize the cloud connection by obtaining an access token
  ///
  /// This should be called after construction to authenticate with the cloud.
  /// Returns true if successful, false otherwise.
  Future<bool> init() async {
    if (token != null) {
      return true; // Already have a token
    }

    final result = await _getToken();
    return result != null;
  }

  /// Set the API region and corresponding URL host
  void setRegion(String region) {
    apiRegion = region.toLowerCase();
    urlHost = regionHosts[apiRegion] ?? regionHosts['cn']!;
  }

  /// Generate HMAC-SHA256 signature for API request
  ///
  /// Args:
  ///   timestamp: Current timestamp in milliseconds
  ///   action: HTTP method (GET, POST, PUT, DELETE)
  ///   body: Request body (for POST/PUT)
  ///   headers: Request headers
  ///   urlPath: URL path for signature calculation
  @visibleForTesting
  String generateSignature({
    required int timestamp,
    required String action,
    String? body,
    Map<String, String>? headers,
    String? urlPath,
  }) {
    // Build payload for signature
    String payload;
    if (token == null) {
      payload = apiKey + timestamp.toString();
    } else {
      payload = apiKey + token! + timestamp.toString();
    }

    // Add new signature algorithm components
    if (newSignAlgorithm) {
      // HTTPMethod
      payload += '$action\n';

      // Content-SHA256
      final bodyBytes = utf8.encode(body ?? '');
      final bodySha256 = sha256.convert(bodyBytes).toString();
      payload += '$bodySha256\n';

      // Headers (sorted by Signature-Headers)
      if (headers != null && headers.containsKey('Signature-Headers')) {
        final signatureHeaders = headers['Signature-Headers']!.split(':');
        for (final key in signatureHeaders) {
          if (key.isNotEmpty && headers.containsKey(key)) {
            payload += '$key:${headers[key]}\n';
          }
        }
      }
      payload += '\n';

      // URL Path (without protocol and host)
      if (urlPath != null) {
        // Extract path from full URL: https://host/path?query -> /path?query
        // Python: '/' + sign_url.split('//', 1)[-1].split('/', 1)[-1]
        final pathMatch = RegExp(r'//[^/]+(/.*)').firstMatch(urlPath);
        if (pathMatch != null) {
          payload += pathMatch.group(1)!;
        } else {
          payload += urlPath;
        }
      }
    }

    // Generate HMAC-SHA256 signature
    final key = utf8.encode(apiSecret);
    final bytes = utf8.encode(payload);
    final hmacSha256 = Hmac(sha256, key);
    final digest = hmacSha256.convert(bytes);

    return digest.toString().toUpperCase();
  }

  /// Get OAuth2 token from Tuya Cloud
  Future<String?> _getToken() async {
    token = null;
    final responseDict = await _tuyaPlatform('token?grant_type=1');

    if (responseDict == null ||
        !responseDict.containsKey('success') ||
        responseDict['success'] != true) {
      error = {
        'error': 'Token acquisition failed',
        'message': responseDict?['msg'] ?? 'Unknown error',
      };
      return null;
    }

    // Update server time offset
    if (responseDict.containsKey('t')) {
      final serverTime = (responseDict['t'] as num).toDouble() / 1000.0;
      final localTime = DateTime.now().millisecondsSinceEpoch / 1000.0;
      // Round to 2 minutes to factor out processing delays
      serverTimeOffset = ((serverTime - localTime) / 120).round() * 120;
    }

    token = responseDict['result']['access_token'] as String;
    return token;
  }

  /// Make authenticated request to Tuya Cloud Platform
  ///
  /// Args:
  ///   uri: API endpoint URI (without version prefix)
  ///   action: HTTP method (GET, POST, PUT, DELETE)
  ///   post: POST body data (will be JSON encoded)
  ///   ver: API version (v1.0, v1.1, etc.) - null for no version prefix
  ///   recursive: Internal flag to prevent infinite recursion on token refresh
  ///   query: Query parameters as Map or String
  ///
  /// Returns:
  ///   Response dictionary or null on error
  Future<Map<String, dynamic>?> _tuyaPlatform(
    String uri, {
    String action = 'GET',
    dynamic post,
    String? ver = 'v1.0',
    bool recursive = false,
    dynamic query,
  }) async {
    // Build URL
    String url;
    if (ver != null && ver.isNotEmpty) {
      url = 'https://$urlHost/$ver/$uri';
    } else if (uri.startsWith('/')) {
      url = 'https://$urlHost$uri';
    } else {
      url = 'https://$urlHost/$uri';
    }

    // Prepare headers and body
    final headers = <String, String>{};
    String? body;
    String signUrl = url;

    if (post != null) {
      body = jsonEncode(post);
      headers['Content-Type'] = 'application/json';
    }

    // Add query parameters
    if (query != null) {
      if (query is String) {
        // String query - use as-is
        if (query.startsWith('?')) {
          url += query;
        } else {
          url += '?$query';
        }
        signUrl = url;
      } else if (query is Map<String, dynamic>) {
        // Map query - sort keys alphabetically for signature
        final sortedKeys = query.keys.toList()..sort();
        final queryParts = <String>[];
        for (final key in sortedKeys) {
          queryParts.add('$key=${query[key]}');
        }
        final queryString = queryParts.join('&');

        // Sign URL without encoding
        signUrl += '?$queryString';

        // Actual URL with encoding
        final encodedParts = <String>[];
        for (final key in sortedKeys) {
          encodedParts.add(
            '$key=${Uri.encodeComponent(query[key].toString())}',
          );
        }
        url += '?${encodedParts.join('&')}';
      }
    }

    // Add Signature-Headers if we have headers
    if (headers.isNotEmpty) {
      headers['Signature-Headers'] = headers.keys.join(':');
    }

    // Generate timestamp
    final now =
        DateTime.now().millisecondsSinceEpoch + (serverTimeOffset * 1000);

    // Add secret header if no token
    if (token == null) {
      headers['secret'] = apiSecret;
    }

    // Generate signature
    final signature = generateSignature(
      timestamp: now,
      action: action,
      body: body,
      headers: headers,
      urlPath: signUrl,
    );

    // Add authentication headers
    headers['client_id'] = apiKey;
    headers['sign'] = signature;
    headers['t'] = now.toString();
    headers['sign_method'] = 'HMAC-SHA256';
    headers['mode'] = 'cors';

    if (token != null) {
      headers['access_token'] = token!;
    }

    // Make HTTP request
    http.Response response;
    try {
      if (action == 'GET') {
        response = await http.get(Uri.parse(url), headers: headers);
      } else if (action == 'POST') {
        response = await http.post(
          Uri.parse(url),
          headers: headers,
          body: body,
        );
      } else if (action == 'PUT') {
        response = await http.put(Uri.parse(url), headers: headers, body: body);
      } else if (action == 'DELETE') {
        response = await http.delete(Uri.parse(url), headers: headers);
      } else {
        throw ArgumentError('Invalid HTTP action: $action');
      }
    } catch (e) {
      error = {'error': 'HTTP request failed', 'message': e.toString()};
      return null;
    }

    // Check for token expiration
    if (response.body.contains('token invalid')) {
      if (recursive) {
        error = {'error': 'Failed to renew token after retry'};
        return null;
      }

      // Try to get new token
      await _getToken();
      if (token == null) {
        error = {'error': 'Failed to renew token'};
        return null;
      }

      // Retry request with new token
      return await _tuyaPlatform(
        uri,
        action: action,
        post: post,
        ver: ver,
        recursive: true,
        query: query,
      );
    }

    // Parse response
    Map<String, dynamic> responseDict;
    try {
      responseDict = jsonDecode(response.body) as Map<String, dynamic>;
      error = null;
    } catch (e) {
      error = {'error': 'Invalid JSON response', 'message': response.body};
      return null;
    }

    return responseDict;
  }

  /// Make a generic cloud request
  ///
  /// Args:
  ///   url: The URL to fetch (e.g., "/v1.0/devices/0011223344556677/logs")
  ///   action: HTTP method (GET, POST, PUT, DELETE) - defaults to POST if post data provided
  ///   post: POST body data (will be JSON encoded)
  ///   query: Query parameters
  Future<Map<String, dynamic>?> cloudRequest(
    String url, {
    String? action,
    dynamic post,
    dynamic query,
  }) async {
    if (token == null) {
      return error;
    }

    final httpAction = action ?? (post != null ? 'POST' : 'GET');
    return await _tuyaPlatform(
      url,
      action: httpAction,
      post: post,
      ver: null, // Use null to handle version in URL
      query: query,
    );
  }

  /// Get device status
  Future<Map<String, dynamic>?> getStatus(String deviceId) async {
    if (token == null) {
      return error;
    }

    final uri = 'iot-03/devices/$deviceId/status';
    final response = await _tuyaPlatform(uri);

    if (response == null || response['success'] != true) {
      error = {
        'error': 'Failed to get device status',
        'message': response?['msg'] ?? 'Unknown error',
      };
      return response;
    }

    return response;
  }

  /// Send command to device
  Future<Map<String, dynamic>?> sendCommand(
    String deviceId,
    Map<String, dynamic> commands,
  ) async {
    if (token == null) {
      return error;
    }

    final uri = 'iot-03/devices/$deviceId/commands';
    final response = await _tuyaPlatform(uri, action: 'POST', post: commands);

    if (response == null || response['success'] != true) {
      error = {
        'error': 'Failed to send command',
        'message': response?['msg'] ?? 'Unknown error',
      };
      return response;
    }

    return response;
  }

  /// Get device DPS specifications
  Future<Map<String, dynamic>?> getDps(String deviceId) async {
    if (token == null) {
      return error;
    }

    final uri = 'devices/$deviceId/specifications';
    final response = await _tuyaPlatform(uri, ver: 'v1.1');

    if (response == null || response['success'] != true) {
      error = {
        'error': 'Failed to get DPS specifications',
        'message': response?['msg'] ?? 'Unknown error',
      };
      return response;
    }

    return response;
  }

  /// Get device functions
  Future<Map<String, dynamic>?> getFunctions(String deviceId) async {
    if (token == null) {
      return error;
    }

    final uri = 'iot-03/devices/$deviceId/functions';
    final response = await _tuyaPlatform(uri);

    if (response == null || response['success'] != true) {
      error = {
        'error': 'Failed to get device functions',
        'message': response?['msg'] ?? 'Unknown error',
      };
      return response;
    }

    return response;
  }

  /// Get device properties/specifications
  Future<Map<String, dynamic>?> getProperties(String deviceId) async {
    if (token == null) {
      return error;
    }

    final uri = 'iot-03/devices/$deviceId/specification';
    final response = await _tuyaPlatform(uri);

    if (response == null || response['success'] != true) {
      error = {
        'error': 'Failed to get device properties',
        'message': response?['msg'] ?? 'Unknown error',
      };
      return response;
    }

    return response;
  }

  /// Get list of devices with their local keys
  ///
  /// This is the main method to get device information from the cloud,
  /// including the local_key needed for direct device communication.
  Future<List<Map<String, dynamic>>> getDevices() async {
    // Ensure we have a token
    if (token == null) {
      await _getToken();
      if (token == null) {
        return [];
      }
    }

    // Get all devices using the v1.0 API
    final uri = '/v1.0/iot-01/associated-users/devices';
    final query = {'size': '100'};

    final devices = <Map<String, dynamic>>[];
    String? lastRowKey;
    bool hasMore = true;

    // Paginate through all devices
    while (hasMore) {
      if (lastRowKey != null) {
        query['last_row_key'] = lastRowKey;
      }

      final response = await cloudRequest(uri, query: query);

      if (response == null || response['success'] != true) {
        error = {
          'error': 'Failed to get device list',
          'message': response?['msg'] ?? 'Unknown error',
        };
        break;
      }

      final result = response['result'] as Map<String, dynamic>?;
      if (result == null) break;

      // Add devices from this page
      if (result.containsKey('devices')) {
        final pageDevices = result['devices'] as List;
        for (final device in pageDevices) {
          if (device is Map<String, dynamic>) {
            devices.add(device);
          }
        }
      }

      // Check for more pages
      hasMore = result['has_more'] as bool? ?? false;
      if (hasMore && result.containsKey('last_row_key')) {
        lastRowKey = result['last_row_key'] as String;
      } else {
        hasMore = false;
      }
    }

    return devices;
  }
}
