import 'package:flutter/material.dart';
import '../data/store_repository.dart';
import '../indoor_map.dart';
import '../lots_data.dart';
import '../models/route_mode.dart';
import '../models/shop.dart';
import '../models/store.dart';
import '../services/mallpilot_api.dart';
import '../services/app_language.dart';
import '../state/trip_settings.dart';
import '../state/pinned_start.dart';

/// Turns Wingki's Stop List into the teammate's full interactive map while
/// retrieving all route geometry from the Stage 8 Python API.
class NavigationPage extends StatefulWidget {
  final RouteMode mode;
  final List<Store> stops;
  final PinnedStart? startPosition;
  final Future<List<Store>> Function(BuildContext context, String lastPlannedShopId,
      Set<String> alreadyPlanned)? onExploreMore;
  const NavigationPage({super.key, required this.mode, required this.stops,
    this.startPosition, this.onExploreMore});

  @override
  State<NavigationPage> createState() => _NavigationPageState();
}

class _NavigationPageState extends State<NavigationPage> {
  late Future<_PreparedNavigation> future;

  @override
  void initState() {
    super.initState();
    future = _prepare();
  }

  Future<_PreparedNavigation> _prepare() async {
    if (widget.stops.isEmpty || (widget.startPosition == null && widget.stops.length < 2)) {
      throw StateError('Pin a starting point and choose at least one GF destination.');
    }
    if (widget.stops.any((s) => s.floorLabel != 'GF')) {
      throw StateError('GF navigation only. 1F routing will be added after its graph is ready.');
    }
    if (widget.stops.length > (widget.startPosition == null ? 11 : 10)) {
      throw StateError('The journey optimiser supports at most ten destination shops.');
    }
    final start = widget.startPosition == null ? widget.stops.first : null;
    final destinations = start == null ? widget.stops : widget.stops.skip(1).toList();
    final points = <Offset>[];
    // Leg boundaries are needed so the guide pauses at EVERY stop.
    final legEndPointIndices = <int>[];
    var totalPx = 0.0;
    List<String> visitIds;
    if (widget.startPosition != null) {
      final result = await MallPilotApi.planFromPin(
        widget.startPosition!.toApi(), destinations.map((s) => s.id).toList(), const [],
        mode: widget.mode == RouteMode.sequence ? 'sequence' : 'shortest',
        timeLimitMinutes: widget.onExploreMore == null ? tripSettings.timeBudgetMinutes : null,
      );
      totalPx = (result['total_distance_px'] as num).toDouble();
      _appendRouteLegs(result, points, legEndPointIndices);
      visitIds = (result['visit_order'] as List<dynamic>)
          .map((raw) => (raw as Map<String, dynamic>)['shop_id'].toString()).toList();
    } else if (widget.mode == RouteMode.shortest && destinations.length > 1) {
      final result = await MallPilotApi.optimizeJourney(
        start!.id, destinations.map((s) => s.id).toList(),
        timeLimitMinutes: tripSettings.timeBudgetMinutes,
      );
      totalPx = (result['total_distance_px'] as num).toDouble();
      _appendRouteLegs(result, points, legEndPointIndices);
      visitIds = (result['visit_order'] as List<dynamic>)
          .map((raw) => (raw as Map<String, dynamic>)['shop_id'].toString()).toList();
    } else {
      var previousId = start!.id;
      visitIds = destinations.map((s) => s.id).toList();
      for (final shop in destinations) {
        final result = await MallPilotApi.route(previousId, shop.id);
        totalPx += (result['distance_px'] as num).toDouble();
        for (final point in MallPilotApi.parsePath(result['path'])) {
          if (points.isEmpty || points.last != point) points.add(point);
        }
        legEndPointIndices.add(points.length - 1);
        previousId = shop.id;
      }
    }
    if (points.length < 2) throw StateError('Backend returned no walkable route.');

    // Always use the same canonical shop IDs and details as the directory.
    final directory = await StoreRepository.loadStores();
    final byId = {for (final store in directory) store.id: store};
    final orders = <Shop>[];
    for (final id in visitIds) {
      final store = byId[id];
      if (store == null) throw StateError('Shop $id is missing from the shared directory.');
      orders.add(_shopFromStore(store));
    }
    if (legEndPointIndices.length != orders.length) {
      throw StateError('Route legs do not match the number of destinations.');
    }
    return _PreparedNavigation(orders, points, totalPx, start?.id,
        directory.map(_shopFromStore).toList(), legEndPointIndices, directory);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLanguage.t('indoor_nav_title'))),
      body: FutureBuilder<_PreparedNavigation>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [const CircularProgressIndicator(), const SizedBox(height: 12),
                Text(AppLanguage.t('calc_route_msg'))],
            ));
          }
          if (snapshot.hasError) {
            return Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.wifi_off, size: 44),
                const SizedBox(height: 16),
                Text('${snapshot.error}', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton.icon(onPressed: () => setState(() => future = _prepare()),
                  icon: const Icon(Icons.refresh), label: Text(AppLanguage.t('btn_retry'))),
              ]),
            ));
          }
          final plan = snapshot.data!;
          return GpsNavigatorScreen(
            allShops: plan.directoryShops,
            allStores: verifiedLotsData,
            initialStartShopId: plan.startShopId,
            initialPinnedStart: widget.startPosition,
            directoryStores: plan.directoryStoresAsStores,
            onExploreMore: widget.onExploreMore,
            initialStops: plan.stops,
            initialRoutePoints: plan.path,
            initialStopEndIndices: plan.legEndPointIndices,
            preserveStopOrder: widget.mode == RouteMode.sequence,
          );
        },
      ),
    );
  }
}

class _PreparedNavigation {
  final List<Shop> stops;
  final List<Offset> path;
  final double distancePx;
  final String? startShopId;
  final List<Shop> directoryShops;
  final List<int> legEndPointIndices;
  final List<Store> directoryStoresAsStores;
  _PreparedNavigation(this.stops, this.path, this.distancePx,
      this.startShopId, this.directoryShops, this.legEndPointIndices,
      this.directoryStoresAsStores);
}

/// Flatten the backend's legs while retaining where each destination ends.
/// This matches MallPilotApi.parseLegs de-duplication of shared junctions.
void _appendRouteLegs(Map<String, dynamic> response, List<Offset> allPoints,
    List<int> endIndices) {
  final legs = (response['legs'] as List<dynamic>? ?? []);
  for (final rawLeg in legs) {
    for (final pt in MallPilotApi.parsePath((rawLeg as Map<String, dynamic>)['path'])) {
      if (allPoints.isEmpty || allPoints.last != pt) allPoints.add(pt);
    }
    endIndices.add(allPoints.length - 1);
  }
}

Shop _shopFromStore(Store s) => Shop(
  id: s.id, lotId: s.lotId,
  lots: s.lotId.split('&').map((p) => p.trim()).toList(),
  primaryLot: s.lotId.split('&').first.trim(),
  name: s.name, status: 'Occupied', floor: s.floorLabel,
  category: s.category, subCategory: s.subCategory,
  priceRange: s.priceText,
  avgVisitTime: '${s.avgVisitMinutes} mins',
  avgVisitTimeMin: s.avgVisitMinutes,
  logoFilename: s.logo,
);

/// Unified directory + indoor map. The StopList is the single selection source.
class MapExplorerPage extends StatefulWidget {
  const MapExplorerPage({super.key});
  @override
  State<MapExplorerPage> createState() => _MapExplorerPageState();
}

class _MapExplorerPageState extends State<MapExplorerPage> {
  late final Future<List<Store>> _future = StoreRepository.loadStores();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(AppLanguage.t('explore_map_and_stores'))),
    body: FutureBuilder<List<Store>>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          if (snapshot.hasError) return Center(child: Text('${snapshot.error}'));
          return const Center(child: CircularProgressIndicator());
        }
        return GpsNavigatorScreen(
          allShops: snapshot.data!.map(_shopFromStore).toList(),
          allStores: verifiedLotsData,
          directoryStores: snapshot.data!,
          syncWithStopList: true,
        );
      },
    ),
  );
}
