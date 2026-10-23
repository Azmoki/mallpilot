import '../services/app_language.dart';

/// One mall shop using the team's canonical `shops.json` + optional mapped node.
/// IDs are shop_XXX, never lot IDs or route node IDs.
class Store {
  final String id;
  final String lotId;
  final String name;
  final String category;
  final String subCategory;
  final int floor;
  final String floorLabel;
  final int? priceMin;
  final int? priceMax;
  final int avgVisitMinutes;
  final List<String> tags;
  final String nodeId;
  final String logo;

  const Store({
    required this.id, required this.lotId, required this.name,
    required this.category, required this.subCategory,
    required this.floor, required this.floorLabel,
    required this.priceMin, required this.priceMax,
    required this.avgVisitMinutes, required this.tags,
    required this.nodeId, required this.logo,
  });

  String get localizedSubCategory => AppLanguage.subCategory(subCategory);

  factory Store.fromJson(Map<String, dynamic> j) {
    final floorLabel = (j['floor'] ?? 'GF').toString();
    final range = (j['price_range'] ?? '').toString();
    final amounts = RegExp(r'\d[\d,]*').allMatches(range)
        .map((m) => int.tryParse(m.group(0)!.replaceAll(',', '')))
        .whereType<int>().toList();
    final tags = <String>[
      (j['category'] ?? '').toString(),
      (j['sub_category'] ?? '').toString(),
      (j['name'] ?? '').toString(),
    ];
    return Store(
      id: (j['id'] ?? '').toString(),
      lotId: (j['lot_id'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      category: (j['category'] ?? '').toString(),
      subCategory: (j['sub_category'] ?? '').toString(),
      floor: floorLabel == '1F' ? 1 : 0,
      floorLabel: floorLabel,
      priceMin: j['min_price_rm'] is num ? (j['min_price_rm'] as num).round()
          : (amounts.isNotEmpty ? amounts.first : null),
      priceMax: j['max_price_rm'] is num ? (j['max_price_rm'] as num).round()
          : (amounts.length >= 2 ? amounts[1] : null),
      avgVisitMinutes: (j['avg_visit_time_min'] is num)
          ? (j['avg_visit_time_min'] as num).round() : 20,
      tags: tags,
      nodeId: (j['node_id'] ?? '').toString(),
      logo: (j['logo_filename'] ?? '').toString(),
    );
  }

  String get priceText => priceMin == null || priceMax == null
      ? AppLanguage.t('price_not_listed') : 'RM $priceMin - RM $priceMax';
  bool get isRouteReady => floor == 0 && nodeId.isNotEmpty;
  bool matches(String query) {
    if (query.trim().isEmpty) return true;
    final q = query.toLowerCase();
    return name.toLowerCase().contains(q) ||
        lotId.toLowerCase().contains(q) ||
        tags.any((s) => s.toLowerCase().contains(q));
  }
}
