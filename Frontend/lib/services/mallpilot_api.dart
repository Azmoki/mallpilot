import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

/// Stage 8 FastAPI contract. The Android emulator can reach host PC at 10.0.2.2.
/// For Windows/Web desktop, defaults to localhost (127.0.0.1).
/// For a physical phone, pass your PC LAN IP via --dart-define.
class MallPilotApi {
  static const String _configuredUrl = String.fromEnvironment(
    'MALLPILOT_API_BASE_URL', defaultValue: '',
  );
  static String get baseUrl {
    if (_configuredUrl.isNotEmpty) {
      return _configuredUrl.replaceFirst(RegExp(r'/$'), '');
    }
    if (kIsWeb) {
      final host = Uri.base.host.isNotEmpty ? Uri.base.host : '127.0.0.1';
      return 'http://$host:8001';
    }
    if (defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.linux) {
      return 'http://127.0.0.1:8001';
    }
    return 'http://10.0.2.2:8001';
  }

  static Future<Map<String, dynamic>> _send(String method, String path,
      [Map<String, dynamic>? payload]) async {
    final uri = Uri.parse('$baseUrl$path');
    late http.Response res;
    try {
      res = await (method == 'GET'
          ? http.get(uri)
          : http.post(uri, headers: {'Content-Type': 'application/json'},
              body: jsonEncode(payload ?? {})))
          .timeout(const Duration(seconds: 20));
    } catch (error) {
      throw Exception('Cannot reach MallPilot backend at $baseUrl. '
          'Make sure uvicorn is running and the device can reach your PC. ($error)');
    }
    Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('Backend returned an invalid JSON response (HTTP ${res.statusCode}).');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Backend HTTP ${res.statusCode}: ${decoded['detail'] ?? decoded['message'] ?? res.reasonPhrase}');
    }
    return decoded;
  }

  static Future<List<Map<String, dynamic>>> shops() async {
    final response = await _send('GET', '/shops');
    return (response['shops'] as List<dynamic>).cast<Map<String, dynamic>>();
  }

  static Future<Map<String, dynamic>> route(String startShopId, String endShopId) =>
      _send('POST', '/route', {
        'start_shop_id': startShopId,
        'end_shop_id': endShopId,
      });

  static Future<Map<String, dynamic>> optimizeJourney(
      String startShopId, List<String> destinationIds, {int? timeLimitMinutes}) =>
      _send('POST', '/optimize-journey', {
        'start_shop_id': startShopId,
        'shop_ids': destinationIds,
        'mode': 'visit_all',
        if (timeLimitMinutes != null) 'time_limit_minutes': timeLimitMinutes,
      });

  static Future<Map<String, dynamic>> recommendShops(String query,
          {int maxResults = 6, double? budgetRm}) =>
      _send('POST', '/recommend-shops', {
        'query': query,
        'mapped_only': true,
        'max_results': maxResults,
        if (budgetRm != null) 'budget_rm': budgetRm,
      });

  static Future<Map<String, dynamic>> recommendJourney(
      String startShopId, String query,
      {int maxStops = 3, int? timeLimitMinutes, double? budgetRm}) =>
      _send('POST', '/recommend-journey', {
        'start_shop_id': startShopId,
        'query': query,
        'max_stops': maxStops,
        'mode': 'visit_all',
        if (budgetRm != null) 'budget_rm': budgetRm,
        if (timeLimitMinutes != null) 'time_limit_minutes': timeLimitMinutes,
      });

  /// Nodes are in original 1737x930 image pixels, keyed by graph node ID.
  static Future<Map<String, dynamic>> groundFloorGraph() =>
      _send('GET', '/graph/GF');

  /// Live facility definitions maintained in Backend/data/public_services_GF.json.
  static Future<List<Map<String, dynamic>>> publicServices() async {
    final response = await _send('GET', '/public-services');
    return (response['services'] as List<dynamic>)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  static Future<Map<String, dynamic>> snapPosition(Offset point) =>
      _send('POST', '/snap-position', {'x': point.dx, 'y': point.dy, 'floor': 'GF'});

  static Future<Map<String, dynamic>> planFromPin(
    Map<String, dynamic> position, List<String> shopIds,
    List<String> publicServiceIds, {required String mode, int? timeLimitMinutes,
      List<String> destinationOrder = const []}
  ) => _send('POST', '/plan-route', {
    'start_position': position,
    'shop_ids': shopIds,
    'public_service_ids': publicServiceIds,
    'destination_order': destinationOrder,
    'mode': mode,
    if (timeLimitMinutes != null) 'time_limit_minutes': timeLimitMinutes,
  });

  static Future<Map<String, dynamic>> recommendFromPin(
    Map<String, dynamic> position, String query,
    {int maxStops = 3, int? timeLimitMinutes, double? budgetRm}
  ) => _send('POST', '/recommend-journey-from-pin', {
    'start_position': position,
    'query': query,
    'max_stops': maxStops,
    if (budgetRm != null) 'budget_rm': budgetRm,
    if (timeLimitMinutes != null) 'time_limit_minutes': timeLimitMinutes,
  });

  /// Progressive recommendations. Initial calls keep the existing Pin My Start;
  /// follow-up calls start from the last pending destination shop.
  static Future<Map<String, dynamic>> adaptiveJourney({
    Map<String, dynamic>? startPosition, String? startShopId,
    required List<String> interests, required String spending,
    required String style, int? maxStops,
    List<String> excludedShopIds = const [],
    List<String> historyShopIds = const [],
    List<String> lockedShopIds = const [], int variation = 0,
  }) => _send('POST', '/adaptive-journey', {
    if (startPosition != null) 'start_position': startPosition,
    if (startShopId != null) 'start_shop_id': startShopId,
    'interests': interests,
    'spending': spending, 'style': style,
    if (maxStops != null) 'max_stops': maxStops,
    'excluded_shop_ids': excludedShopIds,
    'history_shop_ids': historyShopIds,
    'locked_shop_ids': lockedShopIds,
    'variation': variation,
  });

  /// Route coordinates are in the backend graph's original 1000x1000 map pixels.
  static List<Offset> parsePath(dynamic rawPath) {
    if (rawPath is! List) return [];
    return rawPath.map((raw) {
      final p = raw as Map<String, dynamic>;
      return Offset((p['x'] as num).toDouble(), (p['y'] as num).toDouble());
    }).toList();
  }

  static List<Offset> parseLegs(Map<String, dynamic> response) {
    final points = <Offset>[];
    for (final rawLeg in (response['legs'] as List<dynamic>? ?? [])) {
      for (final point in parsePath((rawLeg as Map<String, dynamic>)['path'])) {
        if (points.isEmpty || points.last != point) points.add(point);
      }
    }
    return points;
  }
}
