import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../models/store.dart';
import '../services/mallpilot_api.dart';

/// Same store IDs on Flutter and FastAPI. GF is live; 1F is directory-only.
/// Offline fallback uses the corrected shared shops.json for browsing.
class StoreRepository {
  static Future<List<Store>> loadStores() async {
    final fallback = await _bundled();
    try {
      final live = (await MallPilotApi.shops())
          .map(Store.fromJson).toList();
      final onlyFirstFloor = fallback.where((s) => s.floorLabel == '1F');
      final result = [...live, ...onlyFirstFloor];
      if (live.isNotEmpty) return result;
    } catch (e) {
      debugPrint('Backend unavailable; using bundled directory: $e');
    }
    return fallback;
  }

  static Future<List<Store>> _bundled() async {
    final body = await rootBundle.loadString('assets/data/shops.json');
    return (jsonDecode(body) as List<dynamic>)
        .map((s) => Store.fromJson(s as Map<String, dynamic>))
        .where((s) => s.id.isNotEmpty && s.name != 'Vacant Lot')
        .toList();
  }
}
