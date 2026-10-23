class Shop {
  final String id;
  final String lotId;
  final List<String> lots;
  final String primaryLot;
  final String name;
  final String status;
  final String floor; // "GF" or "1F"
  final String category;
  final String subCategory;
  final String priceRange;
  final String avgVisitTime;
  final int avgVisitTimeMin;
  final String logoFilename;

  Shop({
    required this.id,
    required this.lotId,
    required this.lots,
    required this.primaryLot,
    required this.name,
    required this.status,
    required this.floor,
    required this.category,
    required this.subCategory,
    required this.priceRange,
    required this.avgVisitTime,
    required this.avgVisitTimeMin,
    required this.logoFilename,
  });

  bool get isOccupied => status == 'Occupied';
  bool get isVacant => status == 'Vacant';

  String get logoAssetPath =>
      logoFilename.isNotEmpty ? 'assets/logos/$logoFilename' : '';

  factory Shop.fromJson(Map<String, dynamic> json) {
    var rawLots = json['lots'];
    List<String> parsedLots = [];
    if (rawLots is List) {
      parsedLots = rawLots.map((e) => e.toString()).toList();
    } else if (json['lot_id'] != null) {
      parsedLots = [json['lot_id'].toString()];
    }

    return Shop(
      id: json['id'] ?? '',
      lotId: json['lot_id'] ?? '',
      lots: parsedLots,
      primaryLot: json['primary_lot'] ?? (parsedLots.isNotEmpty ? parsedLots.first : ''),
      name: json['name'] ?? 'Unknown Shop',
      status: json['status'] ?? 'Occupied',
      floor: json['floor'] ?? 'GF',
      category: json['category'] ?? 'General',
      subCategory: json['sub_category'] ?? '',
      priceRange: json['price_range'] ?? 'N/A',
      avgVisitTime: json['avg_visit_time'] ?? '20 mins',
      avgVisitTimeMin: json['avg_visit_time_min'] ?? 20,
      logoFilename: json['logo_filename'] ?? '',
    );
  }
}
