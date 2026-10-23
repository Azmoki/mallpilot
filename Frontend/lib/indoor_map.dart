import 'config/elmina_map_config.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'widgets/mall_glass_card.dart';
import 'package:flutter/services.dart';
import 'models/shop.dart';
import 'lots_data.dart';
import 'corridor_router.dart';
import 'services/mallpilot_api.dart';
import 'models/store.dart';
import 'widgets/store_logo.dart';
import 'models/route_mode.dart';
import 'state/stop_list.dart';
import 'pages/store_directory_page.dart';
import 'pages/map_start_picker_page.dart';
import 'state/pinned_start.dart';
import 'services/app_language.dart';

IconData _getCategoryIcon(String category) {
  final cat = category.toLowerCase();
  if (cat.contains('grocer') || cat.contains('supermarket')) return Icons.local_grocery_store_rounded;
  if (cat.contains('beauty') || cat.contains('cosmetic') || cat.contains('health') || cat.contains('pharmacy')) return Icons.medical_services_rounded;
  if (cat.contains('optic') || cat.contains('eye')) return Icons.remove_red_eye_rounded;
  if (cat.contains('jewel') || cat.contains('accessori')) return Icons.diamond_rounded;
  if (cat.contains('fashion') || cat.contains('apparel') || cat.contains('cloth')) return Icons.checkroom_rounded;
  if (cat.contains('sport')) return Icons.sports_basketball_rounded;
  if (cat.contains('dining') || cat.contains('food') || cat.contains('cafe') || cat.contains('restaurant')) return Icons.restaurant_rounded;
  if (cat.contains('book')) return Icons.menu_book_rounded;
  if (cat.contains('cinema') || cat.contains('entertain')) return Icons.movie_rounded;
  if (cat.contains('home') || cat.contains('hardware')) return Icons.handyman_rounded;
  return Icons.storefront_rounded;
}

class StoreLotAnchor {
  final String lotId;
  final String name;
  final String category;
  final String floor;
  final Offset position; // Exact centroid of the shop
  final Size lotSize;     // Physical lot dimensions
  final IconData icon;
  final List<Offset>? polygon; // True CAD boundary corners
  final bool isVerified;

  const StoreLotAnchor({
    required this.lotId,
    required this.name,
    required this.category,
    required this.floor,
    required this.position,
    required this.lotSize,
    required this.icon,
    this.polygon,
    this.isVerified = false,
  });

  factory StoreLotAnchor.fromJson(Map<String, dynamic> json) {
    final lotId = json['lotId'] as String? ?? '';
    final name = json['name'] as String? ?? '';
    final category = json['category'] as String? ?? 'General';
    final floor = json['floor'] as String? ?? 'GF';

    // Check if verifiedLotsData already has an authoritative definition for this lotId
    final verifiedMatch = verifiedLotsData.cast<StoreLotAnchor?>().firstWhere(
      (v) => v?.lotId == lotId,
      orElse: () => null,
    );
    if (verifiedMatch != null) {
      return verifiedMatch;
    }

    final isVerified = (json['isVerified'] as bool? ?? false);

    Offset position = const Offset(500, 500);
    if (json['centroid'] is List) {
      final list = json['centroid'] as List;
      if (list.length >= 2) {
        position = Offset((list[0] as num).toDouble(), (list[1] as num).toDouble());
      }
    } else if (json['centroid'] is Map) {
      final map = json['centroid'] as Map;
      position = Offset((map['x'] as num).toDouble(), (map['y'] as num).toDouble());
    }

    List<Offset>? poly;
    final rawPoly = json['corners'] ?? json['polygon'];
    if (rawPoly is List) {
      poly = rawPoly.map((pt) {
        if (pt is List && pt.length >= 2) {
          return Offset((pt[0] as num).toDouble(), (pt[1] as num).toDouble());
        } else if (pt is Map) {
          return Offset((pt['x'] as num).toDouble(), (pt['y'] as num).toDouble());
        }
        return const Offset(0, 0);
      }).toList();
    }

    return StoreLotAnchor(
      lotId: lotId,
      name: name,
      category: category,
      floor: floor,
      position: position,
      lotSize: const Size(40, 40),
      icon: _getCategoryIcon(category),
      polygon: poly,
      isVerified: isVerified,
    );
  }

  Rect get lotRect => Rect.fromCenter(center: position, width: lotSize.width, height: lotSize.height);

  Path get path {
    if (polygon != null && polygon!.isNotEmpty) {
      final p = Path();
      p.moveTo(polygon!.first.dx, polygon!.first.dy);
      for (int i = 1; i < polygon!.length; i++) {
        p.lineTo(polygon![i].dx, polygon![i].dy);
      }
      p.close();
      return p;
    }
    return Path()..addRRect(RRect.fromRectAndRadius(lotRect, const Radius.circular(8)));
  }
}

StoreLotAnchor buildStoreLot({
  required String lotId,
  required String name,
  required String category,
  required String floor,
  required List<Offset> corners,
  Offset? center,
  IconData? icon,
}) {
  double sumX = 0, sumY = 0;
  for (final pt in corners) {
    sumX += pt.dx;
    sumY += pt.dy;
  }
  final centroid = Offset(
    double.parse((sumX / corners.length).toStringAsFixed(1)),
    double.parse((sumY / corners.length).toStringAsFixed(1)),
  );
  return StoreLotAnchor(
    lotId: lotId,
    name: name,
    category: category,
    floor: floor,
    position: center ?? centroid,
    lotSize: const Size(40, 40),
    icon: icon ?? _getCategoryIcon(category),
    polygon: corners,
    isVerified: true,
  );
}

// ==========================================
// PURE GPS INDOOR NAVIGATOR SCREEN
// ==========================================
class GpsNavigatorScreen extends StatefulWidget {
  final List<Shop> allShops;
  final List<StoreLotAnchor> allStores;
  final String? initialStartShopId;
  final PinnedStart? initialPinnedStart;
  final List<Shop> initialStops;
  final List<Offset> initialRoutePoints;
  /// End index of each destination leg in initialRoutePoints.
  final List<int> initialStopEndIndices;
  final bool preserveStopOrder;
  /// The unified explorer uses the same selected shops as the directory/chat.
  final bool syncWithStopList;
  final List<Store> directoryStores;
  /// Called only after a confirmed arrival, with one planned shop remaining.
  final Future<List<Store>> Function(BuildContext context, String lastPlannedShopId,
      Set<String> alreadyPlanned)? onExploreMore;

  const GpsNavigatorScreen({
    super.key,
    required this.allShops,
    required this.allStores,
    this.initialStartShopId,
    this.initialPinnedStart,
    this.initialStops = const [],
    this.initialRoutePoints = const [],
    this.initialStopEndIndices = const [],
    this.preserveStopOrder = false,
    this.syncWithStopList = false,
    this.directoryStores = const [],
    this.onExploreMore,
  });

  @override
  State<GpsNavigatorScreen> createState() => _GpsNavigatorScreenState();
}

class _GpsNavigatorScreenState extends State<GpsNavigatorScreen>
    with TickerProviderStateMixin {
  String currentFloor = 'GF';
  // Elmina uses a consistent light interface (no theme toggle).
  final bool isDarkMode = false;
  final TransformationController _transformController = TransformationController();
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _routeAnimController;

  StoreLotAnchor? selectedStore;
  List<Shop> currentStops = [];
  String? _backendStartShopId;
  double? _backendDistancePixels;
  int _routeRequestGeneration = 0;
  bool _routeLoading = false;
  RouteMode? _generatedRouteMode;
  PinnedStart? _pinnedStart;
  final Set<String> _selectedPublicServices = {};
  List<PublicFacility> _facilities = [];
  // Store ID -> graph entrance point in Elmina image coordinates.
  Map<String, Offset> _mappedEntrancePoints = {};
  String? _overlayError;
  final List<String> _destinationSelectionOrder = [];
  List<String> _routeDestinationNames = [];
  List<Offset> _routeDestinationPoints = [];
  /// Graph-path indices where each planned destination is reached.
  List<int> _stopEndPointIndices = [];
  bool _awaitingArrival = false;
  bool _awaitingContinue = false;
  bool _journeyCompleted = false;
  bool _adaptivePrompted = false;
  bool _adaptivePromptInProgress = false;
  String _publicServiceQuery = '';

  // Live User Location (Defaults to South Main Entrance)
  String currentStartName = 'Main South Entrance';
  Offset userPosition = const Offset(585.0, 528.0);
  double userHeading = 0.0;
  bool _followUserCamera = true;
  bool _userIsTouchingMap = false;
  bool _didScaleDuringInteraction = false;
  bool _hadMultiTouch = false;
  Timer? _resumeFollowTimer;

  // Navigation Engine State
  bool isNavigating = false;
  bool isNavPaused = false;
  double simSpeed = 1.0;
  Timer? _navTimer;
  List<Offset> currentRoutePoints = [];
  int currentTargetPointIdx = 0;
  int activeStopIdx = 0;
  String navInstruction = AppLanguage.t('nav_follow_arrows');
  int distanceRemainingMeters = 0;

  // Transit mode preference & active navigation plan
  NavigationPlan? _activeNavigationPlan;

  // Escalator position connecting GF and 1F
  static const Offset escalatorGf = CorridorRouter.escalatorGf;

  List<StoreLotAnchor> get allStores => verifiedLotsData;

  @override
  void initState() {
    super.initState();
    // Keep the floor plan centered in its dedicated map viewport whenever it
    // fits, including during pinch gestures and inertial panning.
    _transformController.addListener(_constrainMapCamera);
    _backendStartShopId = widget.initialStartShopId;
    _pinnedStart = widget.initialPinnedStart ?? pinnedStart.value;
    currentStops = List.of(widget.initialStops);
    currentRoutePoints = List.of(widget.initialRoutePoints);
    _stopEndPointIndices = List.of(widget.initialStopEndIndices);
    _routeDestinationNames = currentStops.map((shop) => shop.name).toList();
    if (currentRoutePoints.isNotEmpty) {
      userPosition = currentRoutePoints.first;
      currentStartName = widget.allShops
          .where((shop) => shop.id == _backendStartShopId)
          .map((shop) => shop.name)
          .firstOrNull ?? 'Selected GF shop';
    }
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _pulseAnimation = Tween<double>(begin: 0.7, end: 1.3).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _routeAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    // Store selection uses traced polygons and grey shop badges. Keep graph
    // entrance nodes for searching/untraced locations and load map services.
    _loadMapOverlays();
    // Both Explore Map & Stores and Plan My Journey need the same pinned start.
    pinnedStart.addListener(_onPinnedStartChanged);
    if (widget.syncWithStopList) {
      stopList.addListener(_syncFromStopList);
      _syncFromStopList(notify: false);
    }
  }

  @override
  void dispose() {
    pinnedStart.removeListener(_onPinnedStartChanged);
    if (widget.syncWithStopList) {
      stopList.removeListener(_syncFromStopList);
    }
    _pulseController.dispose();
    _routeAnimController.dispose();
    _transformController.removeListener(_constrainMapCamera);
    _transformController.dispose();
    _navTimer?.cancel();
    _resumeFollowTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadMapOverlays() async {
    try {
      final graph = await MallPilotApi.groundFloorGraph();
      final nodes = <String, Offset>{};
      for (final raw in (graph['nodes'] as List<dynamic>)) {
        final node = raw as Map<String, dynamic>;
        nodes[node['id'].toString()] = Offset(
          (node['x'] as num).toDouble(), (node['y'] as num).toDouble());
      }
      final mapped = <String, Offset>{};
      for (final store in widget.directoryStores) {
        final pt = nodes[store.nodeId];
        if (store.floorLabel == 'GF' && pt != null) mapped[store.id] = pt;
      }
      if (mounted) setState(() => _mappedEntrancePoints = mapped);
    } catch (error) {
      if (mounted) setState(() => _overlayError = 'Could not load mapped shop entrances: $error');
    }
    try {
      final raw = await MallPilotApi.publicServices();
      // Keep parking out of the visitor-facing services, even when an older
      // backend is still running with the previous parking entries.
      final parsed = raw.where((item) =>
          (item['category'] ?? '').toString().toLowerCase() != 'parking')
          .map(PublicFacility.fromJson).toList();
      if (mounted) setState(() => _facilities = parsed);
    } catch (error) {
      if (mounted) setState(() => _overlayError = 'Could not load public services: $error');
    }
  }

  Size? _viewportSize;
  bool _mapCameraInitialized = false;

  // Tune the zoom-out size relative to fitting the WHOLE image in the map
  // viewing area. 0.90 means 10% of the fit size is reserved as space around
  // the mall. Do not use a fixed minimum such as 0.15 across phone sizes.
  static const double _minimumFitFraction = 0.90;
  static const double _initialFitFraction = 0.96;

  // Keep the map viewport separate from the search bar, app bar and bottom
  // navigation buttons. Otherwise the map may be mathematically centered in
  // the full Scaffold but appear stuck beneath its overlaid top search bar.
  static const double _mapSideMargin = 16.0;
  static const double _mapTopControlClearance = 140.0;
  static const double _mapBottomControlClearance = 20.0;

  /// The scale where the entire floor plan is visible on any screen size.
  /// Using min ("contain"), not max ("cover"), is important on phones.
  double get _fullMapFitScale {
    final viewport = _viewportSize;
    if (viewport == null || viewport.width <= 0 || viewport.height <= 0) {
      return 1.0;
    }
    return math.min(
      viewport.width / ElminaMapConfig.imageWidth,
      viewport.height / ElminaMapConfig.imageHeight,
    );
  }

  double get _minimumMapScale => _fullMapFitScale * _minimumFitFraction;

  // When a scaled axis is smaller than the viewport, keep it exactly centered
  // instead of allowing a pan that sticks the image to the top or left.
  double _boundedMapOffset(double offset, double mapExtent, double viewportExtent) {
    if (mapExtent <= viewportExtent) {
      return (viewportExtent - mapExtent) / 2;
    }
    return offset.clamp(viewportExtent - mapExtent, 0.0).toDouble();
  }

  bool _adjustingCamera = false;
  Matrix4? _previousInteractionMatrix;

  /// For every pinch and mouse-wheel zoom, preserve the map point currently
  /// underneath the exact CENTER of the viewport, rather than the point under
  /// the user's fingers / cursor. Drag-only gestures still pan normally.
  void _onMapInteractionStart(ScaleStartDetails details) {
    _userIsTouchingMap = true;
    _resumeFollowTimer?.cancel();
    _hadMultiTouch = details.pointerCount >= 2;
    _didScaleDuringInteraction = false;
    _previousInteractionMatrix = Matrix4.copy(_transformController.value);
  }

  void _onMapInteractionUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount >= 2) {
      _hadMultiTouch = true;
    }
    final previous = _previousInteractionMatrix;
    final viewport = _viewportSize;
    final current = _transformController.value;
    if (previous == null || viewport == null ||
        viewport.width <= 0 || viewport.height <= 0) {
      _previousInteractionMatrix = Matrix4.copy(current);
      return;
    }

    final oldScale = previous.getMaxScaleOnAxis();
    final newScale = current.getMaxScaleOnAxis();
    if (oldScale > 0 && newScale > 0 &&
        (oldScale - newScale).abs() > 0.0000001) {
      if ((oldScale - newScale).abs() > 0.002) {
        _didScaleDuringInteraction = true;
      }
      // The scene coordinate at the middle of the view before this zoom.
      final centerX = viewport.width / 2;
      final centerY = viewport.height / 2;
      final sceneX = (centerX - previous.storage[12]) / oldScale;
      final sceneY = (centerY - previous.storage[13]) / oldScale;

      // Put that exact scene coordinate back under the screen midpoint.
      // Clamping centers any axis that fits and prevents losing the map while
      // zoomed in. It also prevents the image sticking to the top bar.
      final centeredX = _boundedMapOffset(
        centerX - sceneX * newScale,
        ElminaMapConfig.imageWidth * newScale,
        viewport.width,
      );
      final centeredY = _boundedMapOffset(
        centerY - sceneY * newScale,
        ElminaMapConfig.imageHeight * newScale,
        viewport.height,
      );
      if ((current.storage[12] - centeredX).abs() > 0.01 ||
          (current.storage[13] - centeredY).abs() > 0.01) {
        final centered = Matrix4.copy(current)
          ..setTranslationRaw(centeredX, centeredY, 0.0);
        _transformController.value = centered;
      }
    }
    _previousInteractionMatrix = Matrix4.copy(_transformController.value);
  }

  void _onMapInteractionEnd(ScaleEndDetails details) {
    _userIsTouchingMap = false;
    _previousInteractionMatrix = null;
    _constrainMapCamera();
    if (isNavigating) {
      if (_hadMultiTouch || _didScaleDuringInteraction) {
        // Multi-touch pinch zoom finished: immediately continue following at the new zoom!
        _hadMultiTouch = false;
        _didScaleDuringInteraction = false;
        setState(() => _followUserCamera = true);
      } else {
        // Single finger pan: pause follow, but auto-resume after 2.5s of no touch!
        _resumeFollowTimer?.cancel();
        _resumeFollowTimer = Timer(const Duration(milliseconds: 2500), () {
          if (mounted && isNavigating && !_userIsTouchingMap) {
            setState(() => _followUserCamera = true);
          }
        });
      }
    }
  }

  /// Enforce visible map bounds on BOTH axes. InteractiveViewer needs generous
  /// boundaries to zoom out below the viewport size, so we constrain its
  /// TransformationController here instead. This also handles kinetic panning.
  void _constrainMapCamera() {
    if (_adjustingCamera) return;
    final viewport = _viewportSize;
    if (viewport == null || viewport.width <= 0 || viewport.height <= 0) return;

    final matrix = _transformController.value;
    final scale = matrix.getMaxScaleOnAxis();
    if (scale <= 0) return;
    final currentX = matrix.storage[12];
    final currentY = matrix.storage[13];
    final correctedX = _boundedMapOffset(
      currentX,
      ElminaMapConfig.imageWidth * scale,
      viewport.width,
    );
    final correctedY = _boundedMapOffset(
      currentY,
      ElminaMapConfig.imageHeight * scale,
      viewport.height,
    );
    if ((currentX - correctedX).abs() < 0.01 &&
        (currentY - correctedY).abs() < 0.01) {
      return;
    }
    _adjustingCamera = true;
    try {
      final corrected = Matrix4.copy(matrix);
      corrected.setTranslationRaw(correctedX, correctedY, 0.0);
      _transformController.value = corrected;
    } finally {
      _adjustingCamera = false;
    }
  }

  /// Show the entire map in the middle of the unobstructed viewing area.
  /// Only called for the first layout and when the user taps the reset button.
  /// Navigation must never invoke it implicitly, since it discards user zoom.
  void _resetMapCamera() {
    final viewport = _viewportSize;
    if (viewport == null || viewport.width <= 0 || viewport.height <= 0) {
      return;
    }
    final scale = _fullMapFitScale * _initialFitFraction;
    final tx = (viewport.width - ElminaMapConfig.imageWidth * scale) / 2;
    final ty = (viewport.height - ElminaMapConfig.imageHeight * scale) / 2;
    _mapCameraInitialized = true;
    _transformController.value = Matrix4.diagonal3Values(scale, scale, 1.0)
      ..setTranslationRaw(tx, ty, 0.0);
  }

  /// Navigation's bottom controls change height when starting, arriving,
  /// continuing and replaying. That changes the available map viewport but
  /// must NOT reset the user's chosen zoom and pan. Keep the same map point
  /// beneath the center of the viewport, at exactly the current scale.
  void _preserveMapCameraOnViewportResize(Size oldSize, Size newSize, Matrix4 oldCamera) {
    if (!_mapCameraInitialized || oldSize.width <= 0 || oldSize.height <= 0) {
      _resetMapCamera();
      return;
    }
    final scale = oldCamera.getMaxScaleOnAxis();
    if (scale <= 0) {
      _resetMapCamera();
      return;
    }

    final sceneX = (oldSize.width / 2 - oldCamera.storage[12]) / scale;
    final sceneY = (oldSize.height / 2 - oldCamera.storage[13]) / scale;
    final newX = _boundedMapOffset(
      newSize.width / 2 - sceneX * scale,
      ElminaMapConfig.imageWidth * scale,
      newSize.width,
    );
    final newY = _boundedMapOffset(
      newSize.height / 2 - sceneY * scale,
      ElminaMapConfig.imageHeight * scale,
      newSize.height,
    );

    _transformController.value = Matrix4.copy(oldCamera)
      ..setTranslationRaw(newX, newY, 0.0);
  }

  void _centerMapOn(Offset pt, {double? targetScale}) {
    final viewport = _viewportSize;
    if (viewport == null || viewport.width <= 0 || viewport.height <= 0) {
      return;
    }
    final currentScale = _transformController.value.getMaxScaleOnAxis();
    final scale = targetScale ?? (currentScale > _minimumMapScale ? currentScale : math.max(1.5, _minimumMapScale));
    final tx = _boundedMapOffset(
      viewport.width / 2 - pt.dx * scale,
      ElminaMapConfig.imageWidth * scale,
      viewport.width,
    );
    final ty = _boundedMapOffset(
      viewport.height / 2 - pt.dy * scale,
      ElminaMapConfig.imageHeight * scale,
      viewport.height,
    );
    _transformController.value = Matrix4.diagonal3Values(scale, scale, 1.0)
      ..setTranslationRaw(tx, ty, 0.0);
  }

  /// Shops and services are destinations. A separately pinned corridor
  /// coordinate is the starting location, never the first selected shop.
  void _syncFromStopList({bool notify = true}) {
    final byId = {for (final shop in widget.allShops) shop.id: shop};
    void update() {
      _routeRequestGeneration++;
      _navTimer?.cancel();
      isNavigating = false;
      isNavPaused = false;
      _routeLoading = false;
      _generatedRouteMode = null;
      _backendDistancePixels = null;
      currentRoutePoints = [];
      _routeDestinationNames = [];
      _routeDestinationPoints = [];
      _stopEndPointIndices = [];
      _awaitingArrival = false;
      _awaitingContinue = false;
      _journeyCompleted = false;
      activeStopIdx = 0;
      _backendStartShopId = null;
      currentStops = stopList.stops.map((s) => byId[s.id]).whereType<Shop>().toList();
      final shopIds = stopList.stops.map((s) => s.id).toSet();
      _destinationSelectionOrder.removeWhere((id) =>
          id.startsWith('facility:') ? !_selectedPublicServices.contains(id.substring(9))
              : !shopIds.contains(id));
      for (final shop in stopList.stops) {
        if (!_destinationSelectionOrder.contains(shop.id)) _destinationSelectionOrder.add(shop.id);
      }
      // Respect directory/Stop List drag-and-drop order while keeping
      // public-service stops in their original relative positions.
      final requestedShopIds = stopList.stops.map((s) => s.id).iterator;
      for (var i = 0; i < _destinationSelectionOrder.length; i++) {
        if (!_destinationSelectionOrder[i].startsWith('facility:') &&
            requestedShopIds.moveNext()) {
          _destinationSelectionOrder[i] = requestedShopIds.current;
        }
      }
      navInstruction = AppLanguage.t('pin_start_and_generate_path');
    }
    if (notify) {
      if (mounted) setState(update);
    } else {
      update();
    }
  }

  void _onPinnedStartChanged() {
    // Read the *latest* pin, not widget.initialPinnedStart: that is only the
    // value passed when the recommendation map was first opened.
    final changedPin = pinnedStart.value;
    if (changedPin == null) return;
    final routeWasGenerated = currentRoutePoints.length >= 2 &&
        _routeDestinationNames.isNotEmpty;
    final selectionOrder = _generatedRouteMode == RouteMode.sequence ||
        (!widget.syncWithStopList && widget.preserveStopOrder);
    setState(() {
      _pinnedStart = changedPin;
      userPosition = changedPin.point;
      currentFloor = 'GF';
      _routeRequestGeneration++; // Invalidate earlier in-flight route requests.
      currentRoutePoints = [];
      _backendDistancePixels = null;
      _routeDestinationNames = [];
      _routeDestinationPoints = [];
      _stopEndPointIndices = [];
      _navTimer?.cancel();
      isNavigating = false;
      isNavPaused = false;
      _awaitingArrival = false;
      _awaitingContinue = false;
      _journeyCompleted = false;
      _adaptivePrompted = false;
      activeStopIdx = 0;
      _backendStartShopId = null;
    });
    // Only redraw an existing route. Picking a pin before Generate Path must
    // not unexpectedly trigger path generation on the regular Explore map.
    if ((routeWasGenerated || !widget.syncWithStopList) &&
        (currentStops.isNotEmpty || _selectedPublicServices.isNotEmpty)) {
      _recalculateRoute(preserveSelectionOrder: selectionOrder);
    }
  }

  Future<void> _pickStartingPoint() async {
    final result = await Navigator.push<PinnedStart>(context,
      MaterialPageRoute(builder: (_) => MapStartPickerPage(initial: _pinnedStart)));
    if (!mounted || result == null) return;
    pinnedStart.value = result;
    _centerMapOn(result.point);
  }

  List<Shop> get _highlightedStops {
    if (!widget.syncWithStopList) return currentStops;
    final byId = {for (final shop in widget.allShops) shop.id: shop};
    return stopList.stops.map((s) => byId[s.id]).whereType<Shop>().toList();
  }

  void _togglePublicService(PublicFacility facility) {
    if (!facility.routeEnabled) {
      _showRouteMessage('${AppLanguage.facilityName(facility.name)}: ${AppLanguage.t('pedestrian_path_not_mapped_desc')}');
      return;
    }
    if (facility.floor != 'GF') {
      _showRouteMessage(AppLanguage.t('msg_1f_services_preview'));
      return;
    }
    final hadRoute = !widget.syncWithStopList && currentRoutePoints.length >= 2;
    setState(() {
      if (!_selectedPublicServices.add(facility.id)) {
        _selectedPublicServices.remove(facility.id);
        _destinationSelectionOrder.remove('facility:${facility.id}');
      } else {
        _destinationSelectionOrder.add('facility:${facility.id}');
      }
      _routeRequestGeneration++;
      _routeLoading = false;
      _generatedRouteMode = null;
      currentRoutePoints = [];
      _backendDistancePixels = null;
      _routeDestinationNames = [];
      _routeDestinationPoints = [];
      _stopEndPointIndices = [];
      _awaitingArrival = false;
      _awaitingContinue = false;
      _navTimer?.cancel();
      isNavigating = false;
    });
    if (!widget.syncWithStopList && _pinnedStart != null &&
        (hadRoute || currentStops.isNotEmpty || _selectedPublicServices.isNotEmpty)) {
      _recalculateRoute(preserveSelectionOrder: widget.preserveStopOrder);
    }
  }

  static const List<String> _serviceCategories = [
    'drop_off', 'toilet', 'nursing_room',
    'atm', 'surau', 'information', 'playground',
  ];

  String _serviceCategoryName(String category) {
    switch (category) {
      case 'drop_off': return AppLanguage.t('svc_drop_off');
      case 'toilet': return AppLanguage.t('svc_toilet');
      case 'nursing_room': return AppLanguage.t('svc_nursing_room');
      case 'atm': return AppLanguage.t('svc_atm');
      case 'surau': return AppLanguage.t('svc_surau');
      case 'information': return AppLanguage.t('svc_information');
      case 'playground': return AppLanguage.t('svc_playground');
      default: return AppLanguage.t('svc_other');
    }
  }

  void _openPublicServicesSheet() {
    _publicServiceQuery = '';
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, updateSheet) {
          final query = _publicServiceQuery.trim().toLowerCase();
          final matching = _facilities.where((facility) =>
              facility.floor == 'GF' &&
              (query.isEmpty ||
                  ('${facility.name} ${AppLanguage.facilityName(facility.name)} '
                   '${facility.description} ${AppLanguage.facilityDescription(facility.description)} '
                   '${_serviceCategoryName(facility.category)}')
                      .toLowerCase().contains(query))).toList();
          return SafeArea(
            child: FractionallySizedBox(
              heightFactor: 0.76,
              child: Column(children: [
                ListTile(
                  leading: const Icon(Icons.place_rounded, color: Color(0xFF65002E)),
                  title: Text(AppLanguage.t('public_services')),
                  subtitle: Text(AppLanguage.t('select_facility_hint')),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: AppLanguage.t('search_services_hint'),
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (value) => updateSheet(
                        () => _publicServiceQuery = value.toLowerCase()),
                  ),
                ),
                if (_facilities.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No facilities loaded. Check the backend '
                        'public_services_GF.json file and API connection.'),
                  ),
                Expanded(
                  child: ListView(
                    children: [
                      for (final category in _serviceCategories)
                        if (matching.any((f) => f.category == category))
                          ExpansionTile(
                            key: PageStorageKey('services_$category'),
                            initiallyExpanded: query.isNotEmpty,
                            leading: Icon(matching
                                .firstWhere((f) => f.category == category).icon,
                                color: const Color(0xFF65002E)),
                            title: Text(_serviceCategoryName(category)),
                            subtitle: Text('${matching.where((f) => f.category == category).length} ${AppLanguage.t('locations_suffix')}'),
                            children: [
                              for (final facility in matching.where((f) => f.category == category))
                                ListTile(
                                  contentPadding: const EdgeInsets.only(left: 28, right: 12),
                                  title: Text(AppLanguage.facilityName(facility.name)),
                                  subtitle: Text(facility.routeEnabled
                                      ? AppLanguage.facilityDescription(facility.description)
                                      : '${AppLanguage.facilityDescription(facility.description)} — ${AppLanguage.t('map_only')}'),
                                  onTap: () {
                                    Navigator.pop(sheetContext);
                                    _showFacilityDetails(facility);
                                  },
                                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                    IconButton(
                                      tooltip: AppLanguage.t('find_on_map'),
                                      icon: const Icon(Icons.location_searching_rounded),
                                      onPressed: () {
                                        Navigator.pop(sheetContext);
                                        setState(() => currentFloor = 'GF');
                                        _centerMapOn(facility.position);
                                      },
                                    ),
                                    IconButton(
                                      tooltip: facility.routeEnabled
                                          ? (_selectedPublicServices.contains(facility.id)
                                              ? AppLanguage.t('remove_from_route') : AppLanguage.t('add_to_route'))
                                          : AppLanguage.t('pedestrian_not_mapped'),
                                      onPressed: facility.routeEnabled ? () {
                                        _togglePublicService(facility);
                                        updateSheet(() {});
                                      } : null,
                                      icon: Icon(
                                        _selectedPublicServices.contains(facility.id)
                                            ? Icons.check_circle : Icons.add_circle_outline,
                                        color: facility.routeEnabled
                                            ? const Color(0xFF10B981) : Colors.grey,
                                      ),
                                    ),
                                  ]),
                                ),
                            ],
                          ),
                      if (_facilities.isNotEmpty && matching.isEmpty)
                        ListTile(title: Text(AppLanguage.t('no_matching_services'))),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Text(AppLanguage.t('facility_disclaimer'),
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  void _showFacilityDetails(PublicFacility facility) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
          child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(facility.icon, color: const Color(0xFF65002E), size: 30),
                const SizedBox(width: 12),
                Expanded(child: Text(AppLanguage.facilityName(facility.name),
                    style: Theme.of(sheetContext).textTheme.titleLarge)),
              ]),
              const SizedBox(height: 8),
              Text('${_serviceCategoryName(facility.category)} · ${AppLanguage.t('ground_floor_label')}'),
              const SizedBox(height: 6),
              Text(AppLanguage.facilityDescription(facility.description)),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: OutlinedButton.icon(
                  icon: const Icon(Icons.location_searching_rounded),
                  label: Text(AppLanguage.t('show_on_map')),
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _centerMapOn(facility.position);
                  },
                )),
                const SizedBox(width: 12),
                Expanded(child: FilledButton.icon(
                  icon: Icon(_selectedPublicServices.contains(facility.id)
                      ? Icons.remove_circle_outline : Icons.add_rounded),
                  label: Text(!facility.routeEnabled ? AppLanguage.t('map_only')
                      : _selectedPublicServices.contains(facility.id)
                          ? AppLanguage.t('remove_from_route') : AppLanguage.t('add_to_route')),
                  onPressed: !facility.routeEnabled ? null : () {
                    Navigator.pop(sheetContext);
                    _togglePublicService(facility);
                  },
                )),
              ]),
              if (!facility.routeEnabled)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(AppLanguage.t('pedestrian_path_not_mapped_desc'),
                      style: const TextStyle(color: MallGlassStyle.accent)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  bool isStoreInItinerary(StoreLotAnchor store) {
    return _highlightedStops.any((s) => s.primaryLot == store.lotId || s.lots.contains(store.lotId) || s.lotId == store.lotId);
  }

  int getStoreStopIndex(StoreLotAnchor store) {
    final idx = _highlightedStops.indexWhere((s) => s.primaryLot == store.lotId || s.lots.contains(store.lotId) || s.lotId == store.lotId);
    return idx != -1 ? idx + 1 : 0;
  }

  void toggleStoreInItinerary(StoreLotAnchor store) {
    if (widget.syncWithStopList) {
      for (final s in widget.directoryStores) {
        final lots = s.lotId.split('&').map((lot) => lot.trim());
        if (s.floorLabel == store.floor && lots.contains(store.lotId)) {
          stopList.toggle(s); // map and searchable directory update together
          return;
        }
      }
      _showRouteMessage(AppLanguage.t('msg_lot_not_in_directory'));
      return;
    }
    if (store.floor != 'GF') {
      _showRouteMessage(AppLanguage.t('msg_only_gf_routing'));
      return;
    }
    Shop? matched;
    for (final shop in widget.allShops) {
      if (shop.floor == 'GF' && shop.status == 'Occupied' &&
          (shop.lots.contains(store.lotId) || shop.primaryLot == store.lotId)) {
        matched = shop;
        break;
      }
    }
    if (matched == null) {
      _showRouteMessage(AppLanguage.t('msg_shop_not_in_directory'));
      return;
    }
    final shop = matched;
    setState(() {
      final idx = currentStops.indexWhere((s) => s.id == shop.id);
      if (idx != -1) {
        currentStops.removeAt(idx);
      } else if (shop.id != _backendStartShopId) {
        currentStops.add(shop);
      }
    });
    _recalculateRoute();
  }

  void _showRouteMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

void _selectEntrance(MallEntrance ent) {
    if (widget.syncWithStopList) {
      _showRouteMessage(AppLanguage.t('msg_routing_first_shop'));
      return;
    }
    setState(() {
      userPosition = ent.position;
      currentFloor = ent.floor;
      currentStartName = '${ent.name} (preview only)';
      _backendStartShopId = null;
      _recalculateRoute();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('📍 ${AppLanguage.t('start_point_set')}: ${ent.name}'),
        backgroundColor: MallGlassStyle.accent,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _openEntranceSelectorSheet() {
    if (widget.syncWithStopList) {
      _showRouteMessage(AppLanguage.t('msg_set_start_before_route'));
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = isDarkMode;
        final bgColor = isDark ? const Color(0xFF0F172A) : Colors.white;
        final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
        final subtextColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
        final borderColor = isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08);

        return Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 20)],
          ),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.78,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: MallGlassStyle.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.location_on_rounded, color: MallGlassStyle.accent, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLanguage.t('select_start_location_title'),
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor),
                        ),
                        Text(
                          AppLanguage.t('select_start_location_subtitle'),
                          style: TextStyle(fontSize: 11, color: subtextColor),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: mallEntrances.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, idx) {
                  final ent = mallEntrances[idx];
                  final isSelected = currentStartName == ent.name;

                  return Material(
                    color: isSelected
                        ? MallGlassStyle.accent.withValues(alpha: isDark ? 0.25 : 0.08)
                        : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC)),
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      onTap: () {
                        Navigator.pop(ctx);
                        _selectEntrance(ent);
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected ? MallGlassStyle.accent : borderColor,
                            width: isSelected ? 1.5 : 1.0,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? MallGlassStyle.accent
                                    : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                ent.icon,
                                size: 18,
                                color: isSelected ? Colors.white : subtextColor,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        ent.name,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: isSelected ? MallGlassStyle.accent : textColor,
                                        ),
                                      ),
                                      if (ent.id == 'ENT_SOUTH') ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: MallGlassStyle.accent,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(AppLanguage.t('badge_recommended'), style: const TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    ent.description,
                                    style: TextStyle(fontSize: 11, color: subtextColor),
                                  ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              const Icon(Icons.check_circle_rounded, color: MallGlassStyle.accent, size: 20),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.hub_rounded, color: Color(0xFF2563EB), size: 18),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    AppLanguage.t('public_facilities_quick_start'),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textColor),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _facilities.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, idx) {
                  final fac = _facilities[idx];
                  final isSelected = currentStartName == fac.name;
                  return Material(
                    color: isSelected
                        ? MallGlassStyle.accent.withValues(alpha: isDark ? 0.25 : 0.08)
                        : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC)),
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      onTap: () {
                        Navigator.pop(ctx);
                        setState(() {
                          userPosition = fac.position;
                          currentFloor = fac.floor;
                          currentStartName = fac.name;
                          _recalculateRoute();
                        });
                        _centerMapOn(fac.position);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('${AppLanguage.t('start_point_set')}: ${AppLanguage.facilityName(fac.name)} (${fac.floor})'),
                            backgroundColor: MallGlassStyle.accent,
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected ? MallGlassStyle.accent : borderColor,
                            width: isSelected ? 1.5 : 1.0,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: _getFacilityColor(fac.type).withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(fac.icon, size: 17, color: _getFacilityColor(fac.type)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        AppLanguage.facilityName(fac.name),
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: isSelected ? MallGlassStyle.accent : textColor,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: (fac.floor == 'GF' ? const Color(0xFF10B981) : const Color(0xFF6366F1)).withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          fac.floor,
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: fac.floor == 'GF' ? const Color(0xFF10B981) : const Color(0xFF6366F1),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    AppLanguage.facilityDescription(fac.description),
                                    style: TextStyle(fontSize: 10.5, color: subtextColor),
                                  ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              const Icon(Icons.check_circle_rounded, color: MallGlassStyle.accent, size: 18),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
      },
    );
  }

  /// Ground Floor routes come ONLY from the Python backend graph, not the
  /// source project's separate hardcoded CorridorRouter navigation graph.
  Future<void> _recalculateRoute({bool? preserveSelectionOrder}) async {
    final requestId = ++_routeRequestGeneration;
    _navTimer?.cancel();
    isNavigating = false;
    isNavPaused = false;
    _awaitingArrival = false;
    _awaitingContinue = false;
    _journeyCompleted = false;
    _stopEndPointIndices = [];
    if (widget.syncWithStopList) {
      final pin = _pinnedStart;
      final selected = stopList.stops;
      final serviceIds = _selectedPublicServices.toList();
      if (pin == null || (selected.isEmpty && serviceIds.isEmpty)) {
        setState(() {
          currentRoutePoints = [];
          _backendDistancePixels = null;
          _routeLoading = false;
          navInstruction = pin == null ? AppLanguage.t('pin_start_hint')
              : AppLanguage.t('add_destinations_hint');
        });
        return;
      }
      if (selected.any((s) => !s.isRouteReady) || selected.length + serviceIds.length > 10) {
        _showRouteMessage(AppLanguage.t('msg_choose_up_to_10'));
        return;
      }
      setState(() {
        _routeLoading = true;
        currentRoutePoints = [];
        navInstruction = AppLanguage.t('finding_corridor_routes');
      });
      try {
        final result = await MallPilotApi.planFromPin(
          pin.toApi(), selected.map((s) => s.id).toList(), serviceIds,
          mode: (preserveSelectionOrder ?? false) ? 'sequence' : 'shortest',
          destinationOrder: _destinationSelectionOrder,
        );
        if (!mounted || requestId != _routeRequestGeneration) return;
        final byId = {for (final s in widget.allShops) s.id: s};
        final plannedStops = (result['visit_order'] as List<dynamic>)
            .map((raw) => byId[(raw as Map<String, dynamic>)['shop_id']])
            .whereType<Shop>().toList();
        final destinations = (result['visit_order'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        final legs = (result['legs'] as List<dynamic>).cast<Map<String, dynamic>>();
        final points = <Offset>[];
        final destinationPoints = <Offset>[];
        final stopEndIndices = <int>[];
        for (final leg in legs) {
          for (final point in MallPilotApi.parsePath(leg['path'])) {
            if (points.isEmpty || points.last != point) points.add(point);
          }
          // Keep leg boundaries even when a leg has zero walking distance.
          if (points.isNotEmpty) {
            destinationPoints.add(points.last);
            stopEndIndices.add(points.length - 1);
          }
        }
        setState(() {
          currentStops = plannedStops;
          _routeDestinationNames = destinations.map((item) => item['name'].toString()).toList();
          _routeDestinationPoints = destinationPoints;
          _stopEndPointIndices = stopEndIndices;
          currentRoutePoints = points;
          _backendDistancePixels = (result['total_distance_px'] as num).toDouble();
          _routeLoading = false;
          if (points.isNotEmpty) userPosition = points.first;
        });
        _updateDistanceAndInstruction();
      } catch (error) {
        if (!mounted || requestId != _routeRequestGeneration) return;
        setState(() {
          _routeLoading = false;
          _generatedRouteMode = null;
          currentRoutePoints = [];
          _backendDistancePixels = null;
          _routeDestinationNames = [];
          _routeDestinationPoints = [];
          _stopEndPointIndices = [];
          navInstruction = AppLanguage.t('route_unavailable');
        });
        _showRouteMessage('$error');
      }
      return;
    }

    // Plan My Journey also starts at a pinned *corridor point*, not a shop ID.
    // The old shop-to-shop-only branch discarded the route when Start Pin
    // changed because _backendStartShopId is null for recommended journeys.
    if (!widget.syncWithStopList && _pinnedStart != null &&
        currentFloor == 'GF' &&
        (currentStops.isNotEmpty || _selectedPublicServices.isNotEmpty)) {
      setState(() {
        _routeLoading = true;
        currentRoutePoints = [];
        navInstruction = AppLanguage.t('updating_route_from_pin');
      });
      try {
        final serviceIds = _selectedPublicServices.toList();
        if (currentStops.length + serviceIds.length > 10) {
          throw StateError('Select at most 10 shops and public services.');
        }
        final result = await MallPilotApi.planFromPin(
          _pinnedStart!.toApi(), currentStops.map((s) => s.id).toList(), serviceIds,
          mode: (preserveSelectionOrder ?? widget.preserveStopOrder)
              ? 'sequence' : 'shortest',
        );
        if (!mounted || requestId != _routeRequestGeneration) return;
        final byId = {for (final shop in currentStops) shop.id: shop};
        final visitOrder = (result['visit_order'] as List<dynamic>);
        final orderedStops = visitOrder
            .map((raw) => byId[(raw as Map)['shop_id']])
            .whereType<Shop>().toList();
        final points = <Offset>[];
        final endIndices = <int>[];
        for (final raw in result['legs'] as List<dynamic>) {
          final leg = raw as Map;
          for (final point in MallPilotApi.parsePath(leg['path'])) {
            if (points.isEmpty || points.last != point) points.add(point);
          }
          endIndices.add(points.length - 1);
        }
        if (orderedStops.length != currentStops.length ||
            endIndices.length != currentStops.length + serviceIds.length ||
            endIndices.any((i) => i < 0) || points.length < 2) {
          throw StateError('The updated pinned-start route is incomplete.');
        }
        setState(() {
          currentStops = orderedStops;
          currentRoutePoints = points;
          _stopEndPointIndices = endIndices;
          _routeDestinationNames = visitOrder.map((raw) =>
              (raw as Map)['name'].toString()).toList();
          _routeDestinationPoints = endIndices.map((i) => points[i]).toList();
          _backendDistancePixels =
              (result['total_distance_px'] as num).toDouble();
          userPosition = points.first;
          _routeLoading = false;
        });
        _updateDistanceAndInstruction();
      } catch (error) {
        if (!mounted || requestId != _routeRequestGeneration) return;
        setState(() {
          _routeLoading = false;
          _backendDistancePixels = null;
          currentRoutePoints = [];
          _routeDestinationNames = [];
          _routeDestinationPoints = [];
          _stopEndPointIndices = [];
          navInstruction = AppLanguage.t('route_unavailable');
        });
        _showRouteMessage('Could not update the start pin route: $error');
      }
      return;
    }

    // Other entry points still support their existing shop-to-shop routes.
    if (currentStops.isEmpty || _backendStartShopId == null || currentFloor != 'GF') {
      setState(() {
        _activeNavigationPlan = null;
        currentRoutePoints = [];
        _backendDistancePixels = null;
        _routeLoading = false;
      });
      return;
    }
    final startId = _backendStartShopId!;
    final destinations = currentStops.map((s) => s.id).where((id) => id != startId).toList();
    setState(() { _routeLoading = true; currentRoutePoints = []; });
    try {
      List<Offset> points = [];
      final stopEndIndices = <int>[];
      double totalDistance = 0;
      List<Shop>? optimizedStops;
      if ((preserveSelectionOrder ?? widget.preserveStopOrder) || destinations.length == 1) {
        var previous = startId;
        for (final id in destinations) {
          final result = await MallPilotApi.route(previous, id);
          totalDistance += (result['distance_px'] as num).toDouble();
          for (final point in MallPilotApi.parsePath(result['path'])) {
            if (points.isEmpty || points.last != point) points.add(point);
          }
          stopEndIndices.add(points.length - 1);
          previous = id;
        }
      } else {
        final result = await MallPilotApi.optimizeJourney(startId, destinations);
        totalDistance = (result['total_distance_px'] as num).toDouble();
        final legs = (result['legs'] as List<dynamic>).cast<Map<String, dynamic>>();
        for (final leg in legs) {
          for (final pt in MallPilotApi.parsePath(leg['path'])) {
            if (points.isEmpty || points.last != pt) points.add(pt);
          }
          stopEndIndices.add(points.length - 1);
        }
        final byId = {for (final shop in currentStops) shop.id: shop};
        optimizedStops = (result['visit_order'] as List<dynamic>)
            .map((s) => byId[(s as Map<String, dynamic>)['shop_id']])
            .whereType<Shop>().toList();
      }
      if (!mounted || requestId != _routeRequestGeneration) return;
      setState(() {
        if (optimizedStops != null) currentStops = optimizedStops!;
        _routeDestinationNames = currentStops.map((shop) => shop.name).toList();
        _stopEndPointIndices = stopEndIndices;
        currentRoutePoints = points;
        _backendDistancePixels = totalDistance;
        _routeLoading = false;
        if (points.isNotEmpty) userPosition = points.first;
      });
      _updateDistanceAndInstruction();
    } catch (error) {
      if (!mounted || requestId != _routeRequestGeneration) return;
      setState(() {
        _routeLoading = false;
        currentRoutePoints = [];
        _backendDistancePixels = null;
      });
      _showRouteMessage('$error');
    }
  }

  /// Review a draft visit order before generating a My sequence route.
  /// Cancel discards edits; OK commits the order/removals in one shared update.
  Future<bool> _reviewAddedShopsBeforeRoute() async {
    final shopsById = {for (final shop in stopList.stops) shop.id: shop};
    final facilitiesById = {for (final facility in _facilities) facility.id: facility};
    final activeIds = <String>{
      ...shopsById.keys,
      for (final id in _selectedPublicServices) 'facility:$id',
    };
    final draftOrder = <String>[
      ..._destinationSelectionOrder.where(activeIds.contains),
    ];
    for (final id in activeIds) {
      if (!draftOrder.contains(id)) draftOrder.add(id);
    }

    final confirmedOrder = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, updateDraft) => SizedBox(
          height: math.min(MediaQuery.of(sheetContext).size.height * 0.75, 650.0),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(AppLanguage.t('added_destinations'),
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(AppLanguage.t('drag_reorder_hint')),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: draftOrder.isEmpty
                    ? Center(child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(AppLanguage.t('no_destinations_left')),
                      ))
                    : ReorderableListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        buildDefaultDragHandles: false,
                        itemCount: draftOrder.length,
                        onReorder: (oldIndex, newIndex) {
                          updateDraft(() {
                            if (newIndex > oldIndex) newIndex--;
                            final id = draftOrder.removeAt(oldIndex);
                            draftOrder.insert(newIndex, id);
                          });
                        },
                        itemBuilder: (context, index) {
                          final id = draftOrder[index];
                          final shop = shopsById[id];
                          final facility = id.startsWith('facility:')
                              ? facilitiesById[id.substring(9)] : null;
                          return ListTile(
                            key: ValueKey(id),
                            leading: CircleAvatar(child: Text('${index + 1}')),
                            title: Text(shop?.name ?? (facility != null ? AppLanguage.facilityName(facility.name) : id)),
                            subtitle: Text(shop == null
                                ? AppLanguage.t('public_service_label')
                                : shop.lotId),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (shop != null) ...[
                                  SizedBox(width: 32, height: 32,
                                      child: StoreLogo(store: shop)),
                                  const SizedBox(width: 4),
                                ],
                                IconButton(
                                  tooltip: AppLanguage.t('remove_destination'),
                                  icon: const Icon(Icons.delete_outline_rounded),
                                  onPressed: () => updateDraft(
                                      () => draftOrder.removeAt(index)),
                                ),
                                ReorderableDragStartListener(
                                  index: index,
                                  child: const Padding(
                                    padding: EdgeInsets.all(8),
                                    child: Icon(Icons.drag_handle_rounded),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    Expanded(child: OutlinedButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      child: Text(AppLanguage.t('btn_cancel')),
                    )),
                    const SizedBox(width: 12),
                    Expanded(child: FilledButton.icon(
                      onPressed: draftOrder.isEmpty ? null : () =>
                          Navigator.pop(sheetContext, List<String>.of(draftOrder)),
                      icon: const Icon(Icons.check_rounded),
                      label: Text(AppLanguage.t('btn_ok_generate_path')),
                    )),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmedOrder == null || !mounted) return false;
    final confirmedShops = confirmedOrder
        .map((id) => shopsById[id]).whereType<Store>().toList();
    final confirmedServices = confirmedOrder
        .where((id) => id.startsWith('facility:'))
        .map((id) => id.substring(9)).toSet();

    // Set the combined visit order before notifying listeners: _syncFromStopList
    // preserves public-service positions while refreshing the shop selection.
    setState(() {
      _destinationSelectionOrder
        ..clear()
        ..addAll(confirmedOrder);
      _selectedPublicServices
        ..clear()
        ..addAll(confirmedServices);
    });
    stopList.replaceAll(confirmedShops);
    return true;
  }

  Future<void> _generatePathFromMap() async {
    if (!widget.syncWithStopList) return;
    final selected = stopList.stops;
    if (selected.isEmpty && _selectedPublicServices.isEmpty) {
      _showRouteMessage(AppLanguage.t('msg_add_destination_first'));
      return;
    }
    if (selected.length + _selectedPublicServices.length > 10) {
      _showRouteMessage(AppLanguage.t('msg_choose_up_to_10'));
      return;
    }
    if (selected.any((store) => !store.isRouteReady)) {
      _showRouteMessage(AppLanguage.t('only_gf_destinations_routed'));
      return;
    }
    if (_pinnedStart == null) {
      await _pickStartingPoint();
      if (!mounted || _pinnedStart == null) return;
    }
    final choice = await showDialog<RouteMode>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppLanguage.t('generate_walking_path_title')),
        content: Text(AppLanguage.t('generate_walking_path_desc')),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.format_list_numbered),
            label: Text(AppLanguage.t('btn_my_sequence')),
            onPressed: () => Navigator.pop(dialogContext, RouteMode.sequence),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.alt_route),
            label: Text(AppLanguage.t('btn_shortest_path')),
            onPressed: () => Navigator.pop(dialogContext, RouteMode.shortest),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == RouteMode.sequence) {
      final confirmed = await _reviewAddedShopsBeforeRoute();
      if (!confirmed || !mounted) return;
    }
    setState(() {
      currentFloor = 'GF';
      selectedStore = null;
      _generatedRouteMode = choice;
    });
    await _recalculateRoute(preserveSelectionOrder: choice == RouteMode.sequence);
  }

  Future<void> _selectSimulationSpeed() async {
    final speed = await showModalBottomSheet<double>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(AppLanguage.t('sim_speed_title')),
              subtitle: Text(AppLanguage.t('sim_speed_desc')),
            ),
            for (final value in const [0.5, 1.0, 2.0, 3.0])
              ListTile(
                leading: Icon(simSpeed == value ? Icons.check_circle : Icons.speed),
                title: Text('${value == value.roundToDouble() ? value.toInt() : value}x'),
                onTap: () => Navigator.pop(ctx, value),
              ),
          ],
        ),
      ),
    );
    if (speed != null && mounted) setState(() => simSpeed = speed);
  }

  int get _navigationStopCount => _routeDestinationNames.length;

  String get _currentDestination =>
      activeStopIdx < _routeDestinationNames.length
          ? AppLanguage.facilityName(_routeDestinationNames[activeStopIdx])
          : AppLanguage.t('destination_label');

  /// Directions come from the saved corridor graph (image coordinates).
  /// They are not GPS readings, and pixel distances are not metres.
  String _nextGraphDirection() {
    if (currentTargetPointIdx >= currentRoutePoints.length) {
      return '${AppLanguage.t('nav_follow_arrows')} $_currentDestination';
    }
    final next = currentRoutePoints[currentTargetPointIdx];
    final forward = next - userPosition;
    final upcomingIdx = currentTargetPointIdx + 1;
    final legEnd = activeStopIdx < _stopEndPointIndices.length
        ? _stopEndPointIndices[activeStopIdx]
        : currentRoutePoints.length - 1;
    if (upcomingIdx <= legEnd && forward.distance < 45) {
      final outgoing = currentRoutePoints[upcomingIdx] - next;
      final cross = forward.dx * outgoing.dy - forward.dy * outgoing.dx;
      final dot = forward.dx * outgoing.dx + forward.dy * outgoing.dy;
      final turn = math.atan2(cross, dot);
      if (turn > 0.55) return AppLanguage.t('nav_turn_right');
      if (turn < -0.55) return AppLanguage.t('nav_turn_left');
    }
    return '${AppLanguage.t('nav_follow_arrows')} $_currentDestination';
  }

  void _updateDistanceAndInstruction() {
    // Map geometry is not calibrated, so don't present invented metres.
    distanceRemainingMeters = (_backendDistancePixels ?? 0).round();
    if (_journeyCompleted) {
      navInstruction = AppLanguage.t('nav_journey_complete');
    } else if (_awaitingArrival) {
      navInstruction = '$_currentDestination · ${AppLanguage.t('nav_tap_arrived')}';
    } else if (_awaitingContinue) {
      final nextShop = activeStopIdx + 1 < _routeDestinationNames.length
          ? AppLanguage.facilityName(_routeDestinationNames[activeStopIdx + 1])
          : '';
      navInstruction = '${AppLanguage.t('continue_to_btn')} $nextShop';
    } else if (isNavigating) {
      navInstruction = _nextGraphDirection();
    } else if (_routeDestinationNames.isNotEmpty) {
      navInstruction = '${AppLanguage.t('ready_to_visit')} ${AppLanguage.facilityName(_routeDestinationNames.first)}';
    } else {
      navInstruction = AppLanguage.t('pin_start_hint');
    }
  }

  void _startSimulationNavigation() {
    if (currentRoutePoints.length < 2 ||
        _navigationStopCount == 0 ||
        _stopEndPointIndices.length != _navigationStopCount) {
      _showRouteMessage(AppLanguage.t('msg_generate_route_first'));
      return;
    }

    _navTimer?.cancel();
    setState(() {
      isNavigating = true;
      isNavPaused = false;
      _awaitingArrival = false;
      _awaitingContinue = false;
      _journeyCompleted = false;
      _adaptivePrompted = false;
      currentTargetPointIdx = 1;
      activeStopIdx = 0;
      userPosition = currentRoutePoints.first;
      if (currentRoutePoints.length >= 2) {
        final initialDelta = currentRoutePoints[1] - currentRoutePoints[0];
        if (initialDelta.distance > 0.001) {
          userHeading = math.atan2(initialDelta.dy, initialDelta.dx);
        }
      }
      _followUserCamera = true;
      _updateDistanceAndInstruction();
    });
    _centerMapOn(userPosition, targetScale: 1.5);
    _runNavigationTimer();
  }

  /// Animated demo stops at EVERY planned shop/service rather than skipping
  /// straight to the end of the complete journey.
  void _runNavigationTimer() {
    _navTimer?.cancel();
    _navTimer = Timer.periodic(const Duration(milliseconds: 40), (timer) {
      if (!mounted) { timer.cancel(); return; }
      if (!isNavigating || isNavPaused || _awaitingArrival || _awaitingContinue) return;
      if (activeStopIdx >= _stopEndPointIndices.length) { timer.cancel(); return; }
      final endIdx = _stopEndPointIndices[activeStopIdx];

      if (currentTargetPointIdx > endIdx) {
        timer.cancel();
        setState(() {
          _awaitingArrival = true;
          _updateDistanceAndInstruction();
        });
        return;
      }
      if (currentTargetPointIdx >= currentRoutePoints.length) {
        timer.cancel();
        setState(() {
          _awaitingArrival = true;
          _updateDistanceAndInstruction();
        });
        return;
      }

      setState(() {
        final target = currentRoutePoints[currentTargetPointIdx];
        final delta = target - userPosition;
        final distance = delta.distance;
        final step = 2.5 * simSpeed;
        if (distance > 1.2) {
          final targetHeading = math.atan2(delta.dy, delta.dx);
          var diff = (targetHeading - userHeading) % (2 * math.pi);
          if (diff > math.pi) diff -= 2 * math.pi;
          if (diff < -math.pi) diff += 2 * math.pi;
          userHeading += diff * 0.35;
        }
        if (distance <= step) {
          userPosition = target;
          currentTargetPointIdx++;
          if (currentTargetPointIdx > endIdx) {
            timer.cancel();
            _awaitingArrival = true;
          }
        } else {
          userPosition += delta / distance * step;
        }
        if (_followUserCamera && !_userIsTouchingMap) {
          _centerMapOn(userPosition);
        }
        _updateDistanceAndInstruction();
      });
    });
  }

  /// Acknowledges reaching the destination; no automatic skipping ahead.
  void _confirmStopArrival() {
    if (!isNavigating || !_awaitingArrival) return;
    _navTimer?.cancel();
    final isLast = activeStopIdx >= _navigationStopCount - 1;
    setState(() {
      _awaitingArrival = false;
      _awaitingContinue = !isLast;
      if (isLast) {
        isNavigating = false;
        _journeyCompleted = true;
      }
      _updateDistanceAndInstruction();
    });
    if (isLast) _showArrivalDialog();
    // In an adaptive trip, ask only after the shopper confirms a visit.
    // One original destination is still pending, so the app never assumes
    // the user is physically at a shop from the animation alone.
    if (!isLast && widget.onExploreMore != null && !_adaptivePrompted &&
        _selectedPublicServices.isEmpty &&
        activeStopIdx == _navigationStopCount - 2) {
      _adaptivePrompted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _askForMoreShops();
      });
    }
  }

  Shop _storeToNavigationShop(Store s) => Shop(
    id: s.id, lotId: s.lotId,
    lots: s.lotId.split('&').map((part) => part.trim()).toList(),
    primaryLot: s.lotId.split('&').first.trim(),
    name: s.name, status: 'Occupied', floor: s.floorLabel,
    category: s.category, subCategory: s.subCategory,
    priceRange: s.priceText, avgVisitTime: '', avgVisitTimeMin: 0,
    logoFilename: s.logo,
  );

  Future<void> _askForMoreShops() async {
    if (_adaptivePromptInProgress || !isNavigating || !_awaitingContinue ||
        currentStops.isEmpty || widget.onExploreMore == null) return;
    _adaptivePromptInProgress = true;
    try {
      final pendingLast = currentStops.last.id;
      final excluded = currentStops.map((shop) => shop.id).toSet();
      final additions = await widget.onExploreMore!(context, pendingLast, excluded);
      if (!mounted || additions.isEmpty) return;
      if (additions.any((store) => !store.isRouteReady || excluded.contains(store.id))) {
        throw StateError('Follow-up shops must be new mapped GF destinations.');
      }
      if (currentStops.length + additions.length > 20) {
        throw StateError('This journey already contains too many destinations.');
      }
      // Reorder the accepted follow-up subset by the real corridor graph.
      final orderedAdditions = List<Store>.of(additions);
      if (orderedAdditions.length > 1) {
        final optimized = await MallPilotApi.optimizeJourney(
          pendingLast, orderedAdditions.map((s) => s.id).toList());
        if (!mounted) return;
        final byId = {for (final shop in orderedAdditions) shop.id: shop};
        final visitOrder = (optimized['visit_order'] as List<dynamic>?) ?? const [];
        final resolved = [for (final raw in visitOrder)
          if (byId[(raw as Map)['shop_id']] != null) byId[raw['shop_id']]!];
        if (resolved.length == orderedAdditions.length) {
          orderedAdditions..clear()..addAll(resolved);
        }
      }
      // Preserve the original route, already visited shops and the current
      // map transformation. Append only the newly accepted legs.
      final appendedPoints = <Offset>[];
      final appendedEnds = <int>[];
      final appendStartLength = currentRoutePoints.length;
      var precedingId = pendingLast;
      var extraDistance = 0.0;
      for (final store in orderedAdditions) {
        final leg = await MallPilotApi.route(precedingId, store.id);
        if (!mounted) return;
        extraDistance += ((leg['distance_px'] as num?) ?? 0).toDouble();
        for (final point in MallPilotApi.parsePath(leg['path'])) {
          final previous = appendedPoints.isEmpty
              ? (currentRoutePoints.isEmpty ? null : currentRoutePoints.last)
              : appendedPoints.last;
          if (previous == null || previous != point) appendedPoints.add(point);
        }
        appendedEnds.add(appendStartLength + appendedPoints.length - 1);
        precedingId = store.id;
      }
      if (appendedPoints.isEmpty || appendedEnds.any((end) => end < appendStartLength)) {
        throw StateError('No additional walkable path was returned.');
      }
      setState(() {
        currentRoutePoints.addAll(appendedPoints);
        _stopEndPointIndices.addAll(appendedEnds);
        currentStops.addAll(orderedAdditions.map(_storeToNavigationShop));
        _routeDestinationNames.addAll(orderedAdditions.map((store) => store.name));
        _backendDistancePixels = (_backendDistancePixels ?? 0) + extraDistance;
        _adaptivePrompted = false; // A new batch can trigger another offer.
        _updateDistanceAndInstruction();
      });
      // No camera reset: user zoom and pan are retained during extension.
    } catch (error) {
      if (mounted) _showRouteMessage('Could not add follow-up shops: $error');
    } finally {
      _adaptivePromptInProgress = false;
    }
  }

  /// The shopper controls when to leave a shop and continue the next leg.
  void _continueToNextStop() {
    if (!isNavigating || !_awaitingContinue ||
        activeStopIdx >= _navigationStopCount - 1) return;
    setState(() {
      activeStopIdx++;
      _awaitingContinue = false;
      _awaitingArrival = false;
      isNavPaused = false;
      _followUserCamera = true;
      _updateDistanceAndInstruction();
    });
    _centerMapOn(userPosition);
    _runNavigationTimer();
  }

  /// Replay the animated arrows from the previous stop to the current one.
  void _replayCurrentLeg() {
    if (!isNavigating || !_awaitingArrival) return;
    final startIdx = activeStopIdx == 0 ? 0 : _stopEndPointIndices[activeStopIdx - 1];
    if (startIdx < 0 || startIdx >= currentRoutePoints.length) return;
    setState(() {
      userPosition = currentRoutePoints[startIdx];
      currentTargetPointIdx = startIdx + 1;
      _awaitingArrival = false;
      isNavPaused = false;
      _followUserCamera = true;
      _updateDistanceAndInstruction();
    });
    _centerMapOn(userPosition);
    _runNavigationTimer();
  }

  void _pauseResumeNavigation() {
    if (!isNavigating || _awaitingArrival || _awaitingContinue) return;
    setState(() => isNavPaused = !isNavPaused);
  }

  void _stopNavigation() {
    _navTimer?.cancel();
    setState(() {
      isNavigating = false;
      isNavPaused = false;
      _awaitingArrival = false;
      _awaitingContinue = false;
    });
  }

  void _showArrivalDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 28),
            const SizedBox(width: 10),
            Text(AppLanguage.t('itinerary_completed'), style: const TextStyle(color: Color(0xFF0F172A), fontSize: 18)),
          ],
        ),
        content: Text(
          AppLanguage.t('itinerary_completed_msg'),
          style: const TextStyle(color: Color(0xFF475569), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLanguage.t('btn_done'), style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// Use the real logo from the shared directory rather than a generic
  /// category icon in the selected-store card.
  String? _logoAssetForStore(StoreLotAnchor lot) {
    for (final store in widget.directoryStores) {
      if (store.logo.isNotEmpty &&
          store.lotId.split('&').map((id) => id.trim()).contains(lot.lotId)) {
        return 'assets/logos/${store.logo}';
      }
    }
    // The navigation-only screen may have Shop objects but no Store directory.
    for (final shop in widget.allShops) {
      if (shop.logoFilename.isNotEmpty &&
          (shop.lots.contains(lot.lotId) || shop.primaryLot == lot.lotId)) {
        return 'assets/logos/${shop.logoFilename}';
      }
    }
    return null;
  }

  void _handleMapTap(TapUpDetails details) {
    final tapPos = details.localPosition;
    final stores = allStores.where((s) => s.floor == currentFloor && s.isVerified).toList();

    // 1) Inside store cell polygon: precise hit
    for (final store in stores) {
      if (store.path.contains(tapPos)) {
        setState(() => selectedStore = store);
        return;
      }
    }
    // 2) Outside polygon: snap to nearest badge within 14px threshold
    StoreLotAnchor? nearest;
    var best = 14.0;
    for (final store in stores) {
      final d = (store.position - tapPos).distance;
      if (d < best) {
        best = d;
        nearest = store;
      }
    }
    setState(() => selectedStore = nearest);
  }

  /// Keep the recommendation map's selection private to its journey, while
  /// giving it exactly the same search/results/preview UI as Explore Map.
  bool _toggleRecommendedShopFromSearch(Store store) {
    if (!store.isRouteReady) {
      _showRouteMessage(AppLanguage.t('msg_only_gf_stores_route'));
      return false;
    }
    final matches = widget.allShops.where((shop) => shop.id == store.id);
    if (matches.isEmpty) {
      _showRouteMessage(AppLanguage.t('msg_shop_not_in_directory'));
      return false;
    }
    setState(() {
      if (currentStops.any((shop) => shop.id == store.id)) {
        currentStops.removeWhere((shop) => shop.id == store.id);
      } else {
        currentStops.add(matches.first);
      }
    });
    _routeRequestGeneration++; // Invalidate any earlier pending route.
    _recalculateRoute(preserveSelectionOrder: widget.preserveStopOrder);
    return true;
  }

  void _clearRecommendedShopsFromSearch() {
    _navTimer?.cancel();
    setState(() {
      _routeRequestGeneration++;
      currentStops.clear();
      selectedStore = null;
      currentRoutePoints = [];
      _routeDestinationNames = [];
      _routeDestinationPoints = [];
      _stopEndPointIndices = [];
      _backendDistancePixels = null;
      _routeLoading = false;
      _awaitingArrival = false;
      _awaitingContinue = false;
      isNavigating = false;
      _journeyCompleted = false;
    });
  }

  void _openStoreSearchSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: SizedBox(
          height: MediaQuery.of(sheetContext).size.height * 0.88,
          child: StoreDirectoryPage(
            embeddedInMap: true,
            initialSelectedStores: widget.syncWithStopList ? null : [
              for (final store in widget.directoryStores)
                if (currentStops.any((s) => s.id == store.id)) store,
            ],
            onToggleSelectedStore: widget.syncWithStopList
                ? null : _toggleRecommendedShopFromSearch,
            onClearSelectedStores: widget.syncWithStopList
                ? null : _clearRecommendedShopsFromSearch,
            onLocateStore: (store) {
              Navigator.pop(sheetContext);
              final lotIds = store.lotId.split('&').map((s) => s.trim()).toSet();
              StoreLotAnchor? anchor;
              for (final item in allStores) {
                if (item.floor == store.floorLabel && lotIds.contains(item.lotId)) {
                  anchor = item;
                  break;
                }
              }
              if (anchor != null) {
                setState(() {
                  currentFloor = store.floorLabel;
                  selectedStore = anchor;
                });
                _centerMapOn(anchor.position);
              } else {
                final entrance = _mappedEntrancePoints[store.id];
                if (entrance == null) {
                  _showRouteMessage(AppLanguage.t('msg_no_entrance_node'));
                  return;
                }
                setState(() {
                  currentFloor = store.floorLabel;
                  selectedStore = null;
                });
                _centerMapOn(entrance);
                _showRouteMessage(AppLanguage.t('msg_no_polygon'));
              }
            },
          ),
        ),
      ),
    );
  }

  /// Use identical full-width navigation actions in both Explore Map & Stores
  /// and Plan My Journey. The parent Column stretches to the map side margins.
  Widget _buildStartNavigationButton() => SizedBox(
    width: double.infinity,
    height: 48,
    child: FilledButton.icon(
      onPressed: _routeLoading ? null : _startSimulationNavigation,
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF10B981),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      icon: const Icon(Icons.navigation_rounded),
      label: Text(AppLanguage.t('start_navigation'),
          style: const TextStyle(fontWeight: FontWeight.w800)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final bgColor = isDarkMode ? const Color(0xFF0B1325) : const Color(0xFFF1F5F9);
    // Consistent frosted white panel tone for search, routing and popups.
    final cardBgColor = isDarkMode
        ? const Color(0xFF161F30).withValues(alpha: 0.94)
        : MallGlassStyle.surfaceColor;
    final textColor = isDarkMode ? Colors.white : const Color(0xFF0F172A);
    final subtextColor = isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final borderColor = isDarkMode
        ? Colors.white.withValues(alpha: 0.12)
        : MallGlassStyle.borderColor;

    final mapAssetPath = currentFloor == 'GF'
        ? ElminaMapConfig.imageAsset
        : 'assets/maps/1f_light_map.png';

    final currentFloorStores = allStores.where((s) => s.floor == currentFloor).toList();
    final hasGeneratedRoute = widget.syncWithStopList &&
        _generatedRouteMode != null && currentRoutePoints.length >= 2;
    // The floating camera/reset button and the map viewport must both use
    // the ACTUAL height of the bottom actions (rather than a separate guess
    // for each entry point). This keeps them in the same location relative to
    // the actions whether the route came from Explore or Plan My Journey.
    final bottomDeckHeight = isNavigating
        ? (_awaitingArrival ? 108.0 : _awaitingContinue ? 58.0 : 65.0)
        : widget.syncWithStopList
            ? (hasGeneratedRoute ? 106.0 : 56.0) // 48 + 8 + 42 + 8 / 48 + 8
            : (currentStops.isNotEmpty && currentRoutePoints.length >= 2
                ? 48.0 : 0.0);
    final floatingCardBottom = 20.0 + MediaQuery.of(context).padding.bottom +
        bottomDeckHeight + 12.0;

    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          // 1. The actual MAP viewport, with space on all sides. Its center
          // is below the top search bar and above the route buttons. Calculate
          // the camera scale and translation using THIS viewport's dimensions,
          // not the full Scaffold (which extends underneath those controls).
          Positioned(
            left: _mapSideMargin,
            right: _mapSideMargin,
            top: MediaQuery.of(context).padding.top + _mapTopControlClearance,
            bottom: MediaQuery.of(context).padding.bottom +
                bottomDeckHeight + _mapBottomControlClearance,
            child: ClipRect(
              child: LayoutBuilder(
              builder: (context, constraints) {
                final currentSize = Size(constraints.maxWidth, constraints.maxHeight);
                if (_viewportSize != currentSize) {
                  final previousSize = _viewportSize;
                  final previousCamera = Matrix4.copy(_transformController.value);
                  _viewportSize = currentSize;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted || _viewportSize != currentSize) return;
                    if (!_mapCameraInitialized || previousSize == null) {
                      // First display: fit the floor plan to the available area.
                      _resetMapCamera();
                    } else {
                      // Start / arrive / next shop / replay: preserve user zoom.
                      _preserveMapCameraOnViewportResize(
                        previousSize, currentSize, previousCamera);
                    }
                  });
                }
                return InteractiveViewer(
                  transformationController: _transformController,
                  // Match the camera math to the original map coordinates.
                  // The translation below explicitly centers the image; this
                  // alignment only defines the transform origin.
                  alignment: Alignment.topLeft,
                  onInteractionStart: _onMapInteractionStart,
                  onInteractionUpdate: _onMapInteractionUpdate,
                  onInteractionEnd: _onMapInteractionEnd,
                  constrained: false, // Keep the native map-coordinate canvas.
                  minScale: _minimumMapScale,
                  maxScale: math.max(6.0, _minimumMapScale * 5.0),
                  // Allow "contain" scaling below the viewport dimensions.
                  // Camera listener above prevents the map from drifting away.
                  boundaryMargin: const EdgeInsets.all(double.infinity),
                  child: SizedBox(
                    width: ElminaMapConfig.imageWidth,
                    height: ElminaMapConfig.imageHeight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: _handleMapTap,
                      child: Stack(
                      children: [
                        // Layer 1: Clean CAD Floor Plan Base Map (1:1 Native Resolution)
                        Positioned.fill(
                          child: currentFloor == 'GF'
                              ? Image.network(
                                  '${MallPilotApi.baseUrl}/map/GF/image',
                                  width: ElminaMapConfig.imageWidth,
                                  height: ElminaMapConfig.imageHeight,
                                  fit: BoxFit.fill,
                                  filterQuality: FilterQuality.high,
                                  errorBuilder: (_, __, ___) => Image.asset(
                                    mapAssetPath,
                                    width: ElminaMapConfig.imageWidth,
                                    height: ElminaMapConfig.imageHeight,
                                    fit: BoxFit.fill,
                                  ),
                                )
                              : Image.asset(
                                  mapAssetPath,
                                  width: ElminaMapConfig.imageWidth,
                                  height: ElminaMapConfig.imageHeight,
                                  fit: BoxFit.fill,
                                  filterQuality: FilterQuality.high,
                                ),
                        ),

                        // Layer 2: Store polygons and tappable grey shop badges
                        Positioned.fill(
                          child: CustomPaint(
                            size: const Size(ElminaMapConfig.imageWidth, ElminaMapConfig.imageHeight),
                            painter: _StoreLotPainter(
                              stores: currentFloorStores,
                              currentStops: _highlightedStops,
                              selectedLotId: selectedStore?.lotId,
                              isDarkMode: isDarkMode,
                            ),
                          ),
                        ),

                        // Layer 3: Waze Corridor Navigation Polyline with Dynamic Glow & Pulse
                        if (currentFloor == 'GF' && currentRoutePoints.length >= 2)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: AnimatedBuilder(
                                animation: _routeAnimController,
                                builder: (context, _) {
                                  return CustomPaint(
                                    size: const Size(ElminaMapConfig.imageWidth, ElminaMapConfig.imageHeight),
                                    painter: _CorridorRoutePainter(
                                      points: currentRoutePoints,
                                      animPhase: _routeAnimController.value,
                                      isDarkMode: isDarkMode,
                                      navigating: isNavigating && !_awaitingArrival && !_awaitingContinue,
                                      userPosition: userPosition,
                                      nextPointIndex: currentTargetPointIdx,
                                      activeLegEndIndex: activeStopIdx < _stopEndPointIndices.length
                                          ? _stopEndPointIndices[activeStopIdx]
                                          : currentRoutePoints.length - 1,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),

                        // No blue backend-entrance dots or separate entrance popup.
                        // Backend entrance coordinates remain available to locate
                        // untraced shops via search, not as map tap targets.

                        // Layer 4: Public-service hit targets. The actual maroon
                        // icons are part of the floor-plan PNG. For each toilet,
                        // one capsule surrounds BOTH male/female icons and taps
                        // anywhere inside it select the SAME toilet destination.
                        for (final facility in _facilities.where((f) => f.floor == currentFloor))
                          Positioned(
                            left: facility.position.dx - facility.markerSize.width / 2,
                            top: facility.position.dy - facility.markerSize.height / 2,
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => _showFacilityDetails(facility),
                                borderRadius: BorderRadius.circular(999),
                                child: Tooltip(
                                  message: '${AppLanguage.facilityName(facility.name)}\n${AppLanguage.t('tap_for_details')}',
                                  child: Container(
                                    width: facility.markerSize.width,
                                    height: facility.markerSize.height,
                                    decoration: BoxDecoration(
                                      // Rounded-pill outline groups the two
                                      // toilet icons; regular 32x32 stays round.
                                      borderRadius: BorderRadius.circular(999),
                                      color: Colors.transparent,
                                      border: Border.all(
                                        color: _selectedPublicServices.contains(facility.id)
                                            ? const Color(0xFF10B981)
                                            : Colors.transparent,
                                        width: 3,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),

                        // Layer 5: Waze Live User GPS Location Puck with Heading Arrow
                        if (!widget.syncWithStopList || _pinnedStart != null) Positioned(
                          left: userPosition.dx - 40,
                          top: userPosition.dy - 40,
                          child: IgnorePointer(
                            child: AnimatedBuilder(
                              animation: _pulseAnimation,
                              builder: (context, _) {
                                return SizedBox(
                                  width: 80,
                                  height: 80,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      // Outer Radar Circle
                                      Container(
                                        width: 65 * _pulseAnimation.value,
                                        height: 65 * _pulseAnimation.value,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: const Color(0xFF0284C7).withValues(alpha: 0.18),
                                          border: Border.all(
                                            color: const Color(0xFF38BDF8).withValues(alpha: 0.5),
                                            width: 1.5,
                                          ),
                                        ),
                                      ),
                                      // Inner Core Blue Puck with Direction Arrow
                                      Transform.rotate(
                                        angle: userHeading + math.pi / 2,
                                        child: Container(
                                          width: 24,
                                          height: 24,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: const Color(0xFF0284C7),
                                            border: Border.all(color: Colors.white, width: 3),
                                            boxShadow: [
                                              BoxShadow(
                                                color: const Color(0xFF0284C7).withValues(alpha: 0.9),
                                                blurRadius: 12,
                                                spreadRadius: 2,
                                              ),
                                            ],
                                          ),
                                          child: const Center(
                                            child: Icon(
                                              Icons.navigation_rounded,
                                              size: 13,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
            ), // LayoutBuilder
            ), // ClipRect: never paint underneath the top or bottom controls.
          ), // Positioned: map viewport

          // 2. Top Navigation Turn-By-Turn HUD (Active during navigation)
          if (isNavigating)
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF10B981), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF10B981).withValues(alpha: 0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(_awaitingArrival ? Icons.place_rounded
                          : _awaitingContinue ? Icons.check_circle_rounded
                          : Icons.navigation_rounded, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            navInstruction,
                            style: const TextStyle(
                              color: const Color(0xFF0F172A),
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${AppLanguage.stopProgress(activeStopIdx + 1, _navigationStopCount)} • '
                            '${_awaitingArrival ? AppLanguage.t('status_arrival_confirm') : _awaitingContinue ? AppLanguage.t('status_ready_next') : AppLanguage.t('status_animated_demo')}',
                            style: const TextStyle(color: Color(0xFF10B981), fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    InkWell(
                      onTap: _selectSimulationSpeed,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${simSpeed == simSpeed.roundToDouble() ? simSpeed.toInt() : simSpeed}x',
                          style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(isNavPaused ? Icons.play_arrow_rounded : Icons.pause_rounded, color: const Color(0xFF0F172A)),
                      onPressed: _awaitingArrival || _awaitingContinue
                          ? null : _pauseResumeNavigation,
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                      onPressed: _stopNavigation,
                    ),
                  ],
                ),
              ),
            )
          else ...[
            // Search/store selection: primary action at the TOP of the map.
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              left: 16,
              right: 16,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _openStoreSearchSheet,
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                    decoration: BoxDecoration(
                      color: cardBgColor,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: _highlightedStops.isNotEmpty || _selectedPublicServices.isNotEmpty
                            ? const Color(0xFF10B981).withValues(alpha: 0.5)
                            : borderColor,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDarkMode ? 0.45 : 0.1),
                          blurRadius: 14,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.search_rounded,
                          color: _highlightedStops.isNotEmpty || _selectedPublicServices.isNotEmpty
                              ? const Color(0xFF10B981) : subtextColor,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Keep the search hint visible even after stores
                              // have been added to the route.
                              Text(
                                AppLanguage.t('tap_search_stores'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: textColor,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${_highlightedStops.length} ${AppLanguage.t('stores_selected_suffix')}'
                                '${_selectedPublicServices.isEmpty ? '' : ' · ${_selectedPublicServices.length} ${AppLanguage.t('services_selected_suffix')}'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: _highlightedStops.isEmpty && _selectedPublicServices.isEmpty
                                      ? subtextColor
                                      : const Color(0xFF10B981),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Store controls below search (no branded demo header)
            Positioned(
              top: MediaQuery.of(context).padding.top + 78,
              left: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Public services replace the old "Start:" dropdown.
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    ActionChip(
                      avatar: const Icon(Icons.wc_rounded, size: 16, color: Color(0xFF10B981)),
                      label: Text(_selectedPublicServices.isEmpty
                          ? AppLanguage.t('public_services')
                          : '${AppLanguage.t('public_services')} (${_selectedPublicServices.length})'),
                      onPressed: _openPublicServicesSheet,
                      backgroundColor: cardBgColor,
                      side: BorderSide(color: borderColor),
                    ),
                    ActionChip(
                      avatar: Icon(Icons.my_location_rounded, size: 16,
                          color: _pinnedStart == null ? MallGlassStyle.accent : const Color(0xFF10B981)),
                      label: Text(_pinnedStart == null ? AppLanguage.t('pin_my_start') : AppLanguage.t('change_start_pin')),
                      onPressed: _pickStartingPoint,
                      backgroundColor: cardBgColor,
                      side: BorderSide(color: borderColor),
                    ),
                  ]),

                ],
              ),
            ),

          ],

          // 3. Bottom-Left: Target Crosshair Locator Button (⌖)
          Positioned(
            bottom: selectedStore != null
                ? floatingCardBottom + 136
                : floatingCardBottom + 12,
            left: 16,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  if (isNavigating) {
                    setState(() => _followUserCamera = true);
                    _centerMapOn(userPosition, targetScale: 1.5);
                  } else {
                    _resetMapCamera();
                  }
                },
                borderRadius: BorderRadius.circular(25),
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: isNavigating && !_followUserCamera
                        ? const Color(0xFF0284C7)
                        : cardBgColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isNavigating && !_followUserCamera
                          ? Colors.white
                          : borderColor,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDarkMode ? 0.45 : 0.1),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    isNavigating && !_followUserCamera
                        ? Icons.gps_fixed_rounded
                        : Icons.my_location_rounded,
                    color: isNavigating && !_followUserCamera
                        ? Colors.white
                        : textColor,
                    size: 22,
                  ),
                ),
              ),
            ),
          ),

          // 4. Floating store info card stays above the expanded action deck.
          if (selectedStore != null)
            Positioned(
              bottom: floatingCardBottom,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardBgColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isStoreInItinerary(selectedStore!)
                        ? const Color(0xFF10B981)
                        : (isDarkMode ? Colors.white24 : Colors.black12),
                    width: isStoreInItinerary(selectedStore!) ? 2.0 : 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isStoreInItinerary(selectedStore!)
                          ? const Color(0xFF10B981).withValues(alpha: 0.35)
                          : Colors.black.withValues(alpha: 0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: borderColor),
                          ),
                          child: _logoAssetForStore(selectedStore!) == null
                              ? Icon(selectedStore!.icon,
                                  color: const Color(0xFF64748B), size: 24)
                              : ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.asset(
                                    _logoAssetForStore(selectedStore!)!,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) => Icon(
                                      selectedStore!.icon,
                                      color: const Color(0xFF64748B), size: 24),
                                  ),
                                ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                selectedStore!.name,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Lot: ${selectedStore!.lotId} • ${AppLanguage.category(selectedStore!.category)}',
                                style: TextStyle(fontSize: 12, color: subtextColor),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close_rounded, color: subtextColor, size: 20),
                          onPressed: () => setState(() => selectedStore = null),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        // Only store action: select or remove this route stop.
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => toggleStoreInItinerary(selectedStore!),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isStoreInItinerary(selectedStore!)
                                  ? const Color(0xFF10B981)
                                  : MallGlassStyle.accent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: Icon(
                              isStoreInItinerary(selectedStore!) ? Icons.check_rounded : Icons.add_rounded,
                              size: 16,
                            ),
                            label: Text(
                              isStoreInItinerary(selectedStore!)
                                  ? '${AppLanguage.t('stop_selected_prefix')}${getStoreStopIndex(selectedStore!)}${AppLanguage.t('stop_selected_suffix')}'
                                  : AppLanguage.t('btn_add_to_route'),
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          // 4.5. Floating Floor Transition Action Card (When routing across floors)
          if (selectedStore == null &&
              _activeNavigationPlan != null &&
              _activeNavigationPlan!.requiresFloorTransition &&
              currentFloor != _activeNavigationPlan!.targetFloor)
            Positioned(
              bottom: floatingCardBottom,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardBgColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: MallGlassStyle.accent,
                    width: 1.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: MallGlassStyle.accent.withValues(alpha: 0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: MallGlassStyle.accent,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.swap_vert_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Text(
                                _activeNavigationPlan!.transitConnectorName ?? 'Transit Hub',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: MallGlassStyle.accent.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  AppLanguage.t('transit_guide'),
                                  style: const TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    color: MallGlassStyle.accent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _activeNavigationPlan!.transitMessage ?? AppLanguage.t('take_escalator_lift_hint'),
                            style: TextStyle(fontSize: 11.5, color: subtextColor),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: MallGlassStyle.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 2,
                      ),
                      onPressed: () {
                        final targetFl = _activeNavigationPlan!.targetFloor!;
                        final connectorPos = _activeNavigationPlan!.transitPoint!;
                        final connectorName = _activeNavigationPlan!.transitConnectorName ?? 'Transit Hub';
                        setState(() {
                          currentFloor = targetFl;
                          userPosition = connectorPos;
                          currentStartName = '$connectorName ($targetFl Exit)';
                          currentRoutePoints = _activeNavigationPlan!.routeForFloor(targetFl);
                        });
                        _updateDistanceAndInstruction();
                        _centerMapOn(userPosition);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('${AppLanguage.t('arrived_at_floor')} $targetFl. ${AppLanguage.t('continuing_route')}'),
                            backgroundColor: MallGlassStyle.accent,
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${AppLanguage.t('arrived_at_floor')} ${_activeNavigationPlan!.targetFloor} ➔',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 5. Route controls at the bottom; store search lives at the top.
          Positioned(
            bottom: 20 + MediaQuery.of(context).padding.bottom,
            left: 16,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isNavigating) ...[
                  if (_awaitingArrival) ...[
                    SizedBox(height: 48, child: FilledButton.icon(
                      onPressed: _confirmStopArrival,
                      icon: const Icon(Icons.check_circle_rounded),
                      label: Text('${AppLanguage.t('arrived_btn')} · $_currentDestination', maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                      ),
                    )),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _replayCurrentLeg,
                      icon: const Icon(Icons.replay_rounded),
                      label: Text(AppLanguage.t('replay_guidance')),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: cardBgColor, foregroundColor: textColor,
                      ),
                    ),
                  ] else if (_awaitingContinue) ...[
                    SizedBox(height: 48, child: FilledButton.icon(
                      onPressed: _continueToNextStop,
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: Text('${AppLanguage.t('continue_to_btn')} ${AppLanguage.facilityName(_routeDestinationNames[activeStopIdx + 1])}',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                      ),
                    )),
                  ] else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: cardBgColor,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF10B981)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.assistant_direction_rounded,
                          color: Color(0xFF10B981)),
                        const SizedBox(width: 10),
                        Expanded(child: Text(isNavPaused
                          ? AppLanguage.t('demo_paused_msg')
                          : AppLanguage.t('follow_green_arrows_corridor'),
                          style: TextStyle(color: textColor, fontSize: 12))),
                      ]),
                    ),
                  const SizedBox(height: 8),
                ],
                if (widget.syncWithStopList && !isNavigating) ...[
                  if (hasGeneratedRoute) ...[
                    _buildStartNavigationButton(),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 42,
                      child: OutlinedButton.icon(
                        onPressed: _routeLoading ? null : _generatePathFromMap,
                        style: OutlinedButton.styleFrom(
                          backgroundColor: cardBgColor,
                          foregroundColor: textColor,
                          side: const BorderSide(color: Color(0xFF10B981)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        icon: const Icon(Icons.alt_route_rounded, size: 18),
                        label: Text('${AppLanguage.t('change_route_label')} · '
                            '${_generatedRouteMode == RouteMode.sequence ? AppLanguage.t('btn_my_sequence') : AppLanguage.t('btn_shortest_path')}'),
                      ),
                    ),
                  ] else
                    SizedBox(
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: _routeLoading ? null : _generatePathFromMap,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        ),
                        icon: _routeLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.alt_route_rounded),
                        label: Text(_routeLoading ? AppLanguage.t('finding_path') : AppLanguage.t('btn_generate_path'),
                            style: const TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ),
                  const SizedBox(height: 8),
                ],
                if (!widget.syncWithStopList && currentStops.isNotEmpty &&
                    !isNavigating && currentRoutePoints.length >= 2) ...[
                  _buildStartNavigationButton(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getFacilityColor(FacilityType type) {
    switch (type) {
      case FacilityType.escalator:
        return const Color(0xFF7C3AED); // Purple
      case FacilityType.elevator:
        return const Color(0xFFD97706); // Amber
      case FacilityType.serviceHub:
        return const Color(0xFF2563EB); // Royal Blue
      case FacilityType.infoCounter:
        return const Color(0xFFEA580C); // Warm Orange
    }
  }
}

// ==========================================
// STORE LOT PAINTER (POLYGON HIGHLIGHTS & SELECTED STOP BADGES)
// ==========================================
class _StoreLotPainter extends CustomPainter {
  final List<StoreLotAnchor> stores;
  final List<Shop> currentStops;
  final String? selectedLotId;
  final bool isDarkMode;

  _StoreLotPainter({
    required this.stores,
    required this.currentStops,
    required this.selectedLotId,
    required this.isDarkMode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final store in stores) {
      // ONLY draw stores that have true, verified CAD polygons
      if (store.polygon == null || store.polygon!.isEmpty || !store.isVerified) continue;

      final isAdded = currentStops.any((s) => s.primaryLot == store.lotId || s.lots.contains(store.lotId) || s.lotId == store.lotId);
      final stopIdx = currentStops.indexWhere((s) => s.primaryLot == store.lotId || s.lots.contains(store.lotId) || s.lotId == store.lotId);
      final isSelected = selectedLotId == store.lotId;

      final storePath = store.path;

      // ========================================================
      // PLAN A: NATURAL AMBIENT LIGHTING (NO HARSH WIREFRAME)
      // Removes ugly cyan outlines; uses soft ambient fill & glowing badges
      // ========================================================
      if (isAdded) {
        // Route Stop: Soft glowing emerald green ambient light
        canvas.drawPath(
          storePath,
          Paint()
            ..color = const Color(0xFF10B981).withValues(alpha: 0.25)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
        );
        canvas.drawPath(
          storePath,
          Paint()
            ..color = const Color(0xFF10B981).withValues(alpha: 0.35)
            ..style = PaintingStyle.fill,
        );
      } else if (isSelected) {
        // Green store footprint immediately on tap; after "Add to route"
        // the isAdded branch above keeps the same lot green.
        canvas.drawPath(
          storePath,
          Paint()
            ..color = const Color(0xFF10B981).withValues(alpha: 0.35)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
        );
        canvas.drawPath(
          storePath,
          Paint()..color = const Color(0xFF10B981).withValues(alpha: 0.45),
        );
        canvas.drawPath(
          storePath,
          Paint()
            ..color = const Color(0xFF059669)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0,
        );
      }

      // 2. CENTROID POI BADGE (Lock-centered right in the middle of each shop)
      final c = store.position;

      if (isAdded) {
        // Radiant Green Badge with Stop Order Number (①, ②, ③...)
        canvas.drawCircle(
          c,
          14,
          Paint()
            ..color = const Color(0xFF10B981).withValues(alpha: 0.5)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
        canvas.drawCircle(
          c,
          11,
          Paint()..color = const Color(0xFF10B981),
        );
        canvas.drawCircle(
          c,
          11,
          Paint()
            ..color = Colors.white
            ..strokeWidth = 1.8
            ..style = PaintingStyle.stroke,
        );

        final tp = TextPainter(
          text: TextSpan(
            text: '${stopIdx + 1}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 11,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(c.dx - tp.width / 2, c.dy - tp.height / 2));
      } else if (isSelected) {
        // Same green accent as selected route destinations, without stop number.
        canvas.drawCircle(
          c,
          14,
          Paint()
            ..color = const Color(0xFF10B981).withValues(alpha: 0.45)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
        canvas.drawCircle(
          c,
          10,
          Paint()..color = const Color(0xFF10B981),
        );
        canvas.drawCircle(
          c,
          10,
          Paint()
            ..color = Colors.white
            ..strokeWidth = 1.8
            ..style = PaintingStyle.stroke,
        );
        canvas.drawCircle(c, 3.5, Paint()..color = Colors.white);
      } else {
        // Grey centroid marker for every unselected traced store.
        // Map taps near this badge (or inside its polygon) open the one
        // store-action card with Add to Route / remove-stop only.
        canvas.drawCircle(
          c,
          8,
          Paint()..color = isDarkMode ? const Color(0xFF1E293B) : const Color(0xFF94A3B8),
        );
        canvas.drawCircle(
          c,
          8,
          Paint()
            ..color = isDarkMode ? Colors.white70 : Colors.white
            ..strokeWidth = 1.2
            ..style = PaintingStyle.stroke,
        );
        canvas.drawCircle(
          c,
          2.5,
          Paint()..color = Colors.white,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _StoreLotPainter oldDelegate) {
    return oldDelegate.currentStops != currentStops ||
        oldDelegate.selectedLotId != selectedLotId ||
        oldDelegate.isDarkMode != isDarkMode ||
        oldDelegate.stores != stores;
  }
}

// ==========================================
// CORRIDOR ROUTE PAINTER (POLYLINE)
// ==========================================
class _CorridorRoutePainter extends CustomPainter {
  final List<Offset> points;
  final double animPhase;
  final bool isDarkMode;
  final bool navigating;
  final Offset userPosition;
  final int nextPointIndex;
  final int activeLegEndIndex;

  _CorridorRoutePainter({
    required this.points,
    required this.animPhase,
    required this.isDarkMode,
    required this.navigating,
    required this.userPosition,
    required this.nextPointIndex,
    required this.activeLegEndIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final path = Path();
    path.moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }

    // Outer Neon Glow
    final glowPaint = Paint()
      ..color = const Color(0xFF10B981).withValues(alpha: 0.35)
      ..strokeWidth = 10.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawPath(path, glowPaint);

    // Inner Core Solid Route Line
    final corePaint = Paint()
      ..color = const Color(0xFF10B981)
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, corePaint);

    // Waypoints remain visible without pretending they are GPS locations.
    for (final p in points) {
      canvas.drawCircle(p, 3.0, Paint()..color = Colors.white);
    }

    if (navigating && nextPointIndex <= activeLegEndIndex) {
      // Looping chevrons cover only the remaining part of the current leg.
      // They guide the shopper through junctions and stop at each destination.
      final upcoming = <Offset>[userPosition];
      for (var i = nextPointIndex;
          i <= activeLegEndIndex && i < points.length; i++) {
        upcoming.add(points[i]);
      }
      var travelled = 0.0;
      var nextArrowAt = animPhase * 55.0 + 8.0;
      for (var i = 0; i + 1 < upcoming.length; i++) {
        final start = upcoming[i];
        final delta = upcoming[i + 1] - start;
        final length = delta.distance;
        if (length < 0.001) continue;
        final angle = math.atan2(delta.dy, delta.dx);
        while (nextArrowAt < travelled + length) {
          final t = (nextArrowAt - travelled) / length;
          if (t >= 0 && t <= 1) {
            final center = start + delta * t;
            canvas.save();
            canvas.translate(center.dx, center.dy);
            canvas.rotate(angle);
            final arrow = Path()
              ..moveTo(9, 0)
              ..lineTo(-5, -6)
              ..lineTo(-1, 0)
              ..lineTo(-5, 6)
              ..close();
            canvas.drawPath(arrow, Paint()
              ..color = Colors.white
              ..style = PaintingStyle.fill);
            canvas.restore();
          }
          nextArrowAt += 55.0;
        }
        travelled += length;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CorridorRoutePainter oldDelegate) {
    return oldDelegate.animPhase != animPhase || oldDelegate.points != points ||
        oldDelegate.userPosition != userPosition ||
        oldDelegate.nextPointIndex != nextPointIndex ||
        oldDelegate.activeLegEndIndex != activeLegEndIndex ||
        oldDelegate.navigating != navigating;
  }
}

// ==========================================
// STORE DIRECTORY & ROUTE BOTTOM SHEET
// ==========================================
class _StoreSearchSheet extends StatefulWidget {
  final List<Shop> allShops;
  final List<Shop> currentStops;
  final List<StoreLotAnchor> allStores;
  final bool isDarkMode;
  final Function(StoreLotAnchor) onSelectStore;
  final Function(Shop) onToggleShop;
  final VoidCallback onClearAll;

  const _StoreSearchSheet({
    required this.allShops,
    required this.currentStops,
    required this.allStores,
    required this.isDarkMode,
    required this.onSelectStore,
    required this.onToggleShop,
    required this.onClearAll,
  });

  @override
  State<_StoreSearchSheet> createState() => _StoreSearchSheetState();
}

class _StoreSearchSheetState extends State<_StoreSearchSheet> {
  String searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isDarkMode ? const Color(0xFF161F30) : Colors.white;
    final textColor = widget.isDarkMode ? Colors.white : const Color(0xFF0F172A);
    final subtextColor = widget.isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    final filteredShops = widget.allShops.where((s) {
      if (!s.isOccupied) return false;
      if (searchQuery.isEmpty) return true;
      final q = searchQuery.toLowerCase();
      return s.name.toLowerCase().contains(q) ||
          s.primaryLot.toLowerCase().contains(q) ||
          s.category.toLowerCase().contains(q) ||
          s.lots.any((l) => l.toLowerCase().contains(q));
    }).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 24,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: subtextColor.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLanguage.t('store_directory_title'),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    Text(
                      '${AppLanguage.t('selected_destinations')}: ${widget.currentStops.length} ${AppLanguage.t('stores_unit')}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF10B981)),
                    ),
                  ],
                ),
                if (widget.currentStops.isNotEmpty)
                  TextButton.icon(
                    onPressed: widget.onClearAll,
                    icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Color(0xFFEF4444)),
                    label: Text(
                      AppLanguage.t('btn_clear_route'),
                      style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13),
                    ),
                  ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (val) => setState(() => searchQuery = val),
              style: TextStyle(color: textColor, fontSize: 14),
              decoration: InputDecoration(
                hintText: AppLanguage.t('tap_search_stores'),
                hintStyle: TextStyle(color: subtextColor, fontSize: 13),
                prefixIcon: Icon(Icons.search_rounded, color: subtextColor),
                suffixIcon: searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear_rounded, color: subtextColor),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: widget.isDarkMode
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.04),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),

          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              itemCount: filteredShops.length,
              itemBuilder: (context, i) {
                final shop = filteredShops[i];
                final isAdded = widget.currentStops.any(
                  (s) => s.primaryLot == shop.primaryLot || s.lotId == shop.lotId,
                );
                final stopIndex = widget.currentStops.indexWhere(
                  (s) => s.primaryLot == shop.primaryLot || s.lotId == shop.lotId,
                );

                final storeMatch = widget.allStores.cast<StoreLotAnchor?>().firstWhere(
                  (s) => s?.lotId == shop.primaryLot || s?.lotId == shop.lotId,
                  orElse: () => null,
                );

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isAdded
                        ? const Color(0xFF10B981).withValues(alpha: 0.12)
                        : (widget.isDarkMode ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02)),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isAdded
                          ? const Color(0xFF10B981).withValues(alpha: 0.5)
                          : (widget.isDarkMode ? Colors.white12 : Colors.black12),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isAdded
                              ? const Color(0xFF10B981)
                              : (widget.isDarkMode ? const Color(0xFF334155) : const Color(0xFF94A3B8)),
                        ),
                        child: Center(
                          child: isAdded
                              ? Text(
                                  '${stopIndex + 1}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                )
                              : const Icon(
                                  Icons.storefront_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              shop.name,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: textColor,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: (widget.isDarkMode ? Colors.white24 : Colors.black12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    shop.primaryLot,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: textColor,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '${shop.floor} • ${AppLanguage.category(shop.category)}',
                                  style: TextStyle(fontSize: 11, color: subtextColor),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (storeMatch != null)
                        IconButton(
                          tooltip: AppLanguage.t('view_on_map'),
                          icon: const Icon(Icons.place_rounded, color: Color(0xFF0284C7), size: 20),
                          onPressed: () => widget.onSelectStore(storeMatch),
                        ),
                      ElevatedButton(
                        onPressed: () => widget.onToggleShop(shop),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isAdded ? const Color(0xFF10B981) : const Color(0xFF334155),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          minimumSize: const Size(60, 32),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text(
                          isAdded ? AppLanguage.t('btn_added') : AppLanguage.t('btn_add'),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
