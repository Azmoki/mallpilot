import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'indoor_map.dart';
import 'models/shop.dart';

/// User Transit Preference for Multi-Floor Navigation
enum TransitPreference {
  escalator, // 🪜 Escalator Preferred
  elevator,  // 🛗 Lift / Elevator Preferred (Wheelchair / Stroller Accessible)
}

/// Official Mall Entrance Model
class MallEntrance {
  final String id;
  final String name;
  final String description;
  final String floor;
  final Offset position;
  final IconData icon;

  const MallEntrance({
    required this.id,
    required this.name,
    required this.description,
    required this.floor,
    required this.position,
    this.icon = Icons.door_front_door_rounded,
  });
}

/// The 6 Official Entrances matching blueprint & green arrows
final List<MallEntrance> mallEntrances = [];

/// Public Facility Types
enum FacilityType {
  serviceHub,    // Integrated service hub (Restrooms + OKU + Surau + Baby Care)
  elevator,      // Passenger Lift
  escalator,     // Dual Escalator
  infoCounter,   // Information Counter
}

/// Public Facility Location Model
class PublicFacility {
  final String id;
  final String name;
  final String description;
  final String floor;
  final Offset position;
  final FacilityType type;
  final IconData icon;
  final bool verified;
  final String category;
  final bool routeEnabled;
  /// Size of the tappable/selected region in map-image coordinates.
  /// Toilets use one capsule covering both male and female floor-plan icons.
  final Size markerSize;

  const PublicFacility({
    required this.id,
    required this.name,
    required this.description,
    required this.floor,
    required this.position,
    required this.type,
    required this.icon,
    this.verified = false,
    this.category = '',
    this.routeEnabled = true,
    this.markerSize = const Size(32, 32),
  });

  factory PublicFacility.fromJson(Map<String, dynamic> json) {
    final category = (json['category'] ?? '').toString().toLowerCase();
    final FacilityType type;
    final IconData icon;
    switch (category) {
      case 'lift':
      case 'elevator':
        type = FacilityType.elevator;
        icon = Icons.elevator_rounded;
        break;
      case 'escalator':
        type = FacilityType.escalator;
        icon = Icons.escalator_rounded;
        break;
      case 'information':
      case 'info':
        type = FacilityType.infoCounter;
        icon = Icons.info_rounded;
        break;
      default:
        type = FacilityType.serviceHub;
        switch (category) {
          case 'drop_off':
            icon = Icons.directions_car_rounded;
            break;
          case 'parking':
            icon = Icons.local_parking_rounded;
            break;
          case 'toilet':
          case 'restroom':
            icon = Icons.wc_rounded;
            break;
          case 'nursing_room':
          case 'baby_care':
            icon = Icons.child_care_rounded;
            break;
          case 'surau':
            icon = Icons.mosque_rounded;
            break;
          case 'atm':
            icon = Icons.atm_rounded;
            break;
          case 'playground':
            icon = Icons.toys_rounded;
            break;
          default:
            icon = Icons.place_rounded;
        }
    }
    return PublicFacility(
      id: json['id'].toString(),
      name: json['name'].toString(),
      description: (json['description'] ?? '').toString(),
      floor: (json['floor'] ?? 'GF').toString(),
      position: Offset((json['x'] as num).toDouble(),
          (json['y'] as num).toDouble()),
      type: type,
      icon: icon,
      verified: json['verified'] == true,
      category: category,
      routeEnabled: json['route_enabled'] != false,
      markerSize: Size(
        ((json['marker_width'] as num?)?.toDouble() ?? 32.0).clamp(24.0, 100.0).toDouble(),
        ((json['marker_height'] as num?)?.toDouble() ?? 32.0).clamp(24.0, 100.0).toDouble(),
      ),
    );
  }
}

// The frontend now fetches Elmina's service markers from FastAPI.
// No AEON/placeholder coordinates are inserted into the new mall.
final List<PublicFacility> publicFacilities = [];

class _CorridorNode {
  final String id;
  final String floor;
  final Offset pos;
  final List<String> neighbors;

  const _CorridorNode(this.id, this.floor, this.pos, this.neighbors);
}

/// Navigation Route Leg on a specific floor
class RouteLeg {
  final String floor;
  final List<Offset> points;
  const RouteLeg({required this.floor, required this.points});
}

/// Comprehensive Multi-Floor Navigation Plan
class NavigationPlan {
  final List<RouteLeg> legs;
  final bool requiresFloorTransition;
  final String? transitMessage;
  final String? transitConnectorName;
  final Offset? transitPoint;
  final String? targetFloor;

  const NavigationPlan({
    required this.legs,
    this.requiresFloorTransition = false,
    this.transitMessage,
    this.transitConnectorName,
    this.transitPoint,
    this.targetFloor,
  });

  /// Get route points for the requested floor
  List<Offset> routeForFloor(String floor) {
    for (final leg in legs) {
      if (leg.floor == floor) return leg.points;
    }
    return [];
  }
}

/// Indoor Walkway Corridor Routing Engine (Strictly on grey paths, 100% avoiding shops)
class CorridorRouter {
  // Key vertical transit points (same coordinates on GF & 1F)
  static const Offset escWest = Offset.zero;
  static const Offset escCenter = Offset.zero;
  static const Offset escEast = Offset.zero;
  static const Offset liftCenter = Offset.zero;
  static const Offset liftNE = Offset.zero;

  // Backward compatibility aliases
  static const Offset escalatorGf = escCenter;
  static const Offset escalator1f = escCenter;

  // Corridor Graph Waypoints on 1000x1000 Canvas matching user drawings
  // Do not reuse the old mall graph; new Elmina routing is server-generated.
  static final Map<String, _CorridorNode> _nodes = {};

  /// Find nearest corridor node ID for any given coordinate on a specific floor
  static String findNearestNodeId(Offset pt, String floor) {
    if (_nodes.isEmpty) {
      throw StateError('Elmina pedestrian graph has not been mapped yet');
    }
    String bestId = (floor == 'GF') ? 'GF_ENT_SOUTH' : '1F_ATRIUM_RING_W';
    double bestDist = double.infinity;

    for (final entry in _nodes.entries) {
      if (entry.value.floor != floor) continue;
      final d = (entry.value.pos - pt).distance;
      if (d < bestDist) {
        bestDist = d;
        bestId = entry.key;
      }
    }
    return bestId;
  }

  /// Get the store's door position outside its polygon into the grey corridor
  static Offset getStoreDoor(StoreLotAnchor store) {
    final c = store.position;
    final nearestId = findNearestNodeId(c, store.floor);
    final nearestNodePos = _nodes[nearestId]!.pos;

    final delta = nearestNodePos - c;
    final d = delta.distance;
    if (d > 0.1) {
      return c + (delta / d) * math.min(d, 35.0);
    }
    return nearestNodePos;
  }

  /// Shortest path finding on the single-floor or cross-floor corridor graph using Dijkstra / A*
  static List<Offset> findRawCorridorPath(
    Offset start,
    String startFloor,
    Offset dest,
    String destFloor, {
    TransitPreference preference = TransitPreference.escalator,
  }) {
    final startNodeId = findNearestNodeId(start, startFloor);
    final endNodeId = findNearestNodeId(dest, destFloor);

    final dist = <String, double>{};
    final prev = <String, String?>{};
    final unvisited = _nodes.keys.toSet();

    for (final id in unvisited) {
      dist[id] = double.infinity;
      prev[id] = null;
    }
    dist[startNodeId] = 0;

    while (unvisited.isNotEmpty) {
      String? current;
      double bestDist = double.infinity;
      for (final id in unvisited) {
        if (dist[id]! < bestDist) {
          bestDist = dist[id]!;
          current = id;
        }
      }
      if (current == null || bestDist == double.infinity) break;
      if (current == endNodeId) break;

      unvisited.remove(current);
      final node = _nodes[current]!;
      for (final neighborId in node.neighbors) {
        if (!unvisited.contains(neighborId)) continue;
        final neighborNode = _nodes[neighborId]!;

        double cost = (node.pos - neighborNode.pos).distance;

        // Multi-floor edge penalty based on user preference
        if (node.floor != neighborNode.floor) {
          final isElevatorEdge = current.contains('HUB_CENTER') || neighborId.contains('HUB_CENTER');
          if (preference == TransitPreference.elevator) {
            cost = isElevatorEdge ? 10.0 : 800.0; // Strongly prioritize elevator
          } else {
            cost = isElevatorEdge ? 800.0 : 30.0; // Strongly prioritize escalator
          }
        }

        final alt = dist[current]! + cost;
        if (alt < dist[neighborId]!) {
          dist[neighborId] = alt;
          prev[neighborId] = current;
        }
      }
    }

    final rawPath = <Offset>[];
    String? curr = endNodeId;
    while (curr != null) {
      rawPath.insert(0, _nodes[curr]!.pos);
      curr = prev[curr];
    }

    final fullPath = <Offset>[start];
    for (final pt in rawPath) {
      if ((fullPath.last - pt).distance > 1.5) {
        fullPath.add(pt);
      }
    }
    if ((fullPath.last - dest).distance > 1.5) {
      fullPath.add(dest);
    }
    return fullPath;
  }

  /// Compute high-level multi-floor navigation plan with transition cards
  static NavigationPlan planRoute({
    required Offset startPos,
    required String startFloor,
    required Offset destPos,
    required String destFloor,
    TransitPreference preference = TransitPreference.escalator,
  }) {
    if (startFloor == destFloor) {
      // Single floor navigation
      final path = findRawCorridorPath(startPos, startFloor, destPos, destFloor, preference: preference);
      return NavigationPlan(
        legs: [RouteLeg(floor: startFloor, points: path)],
        requiresFloorTransition: false,
      );
    }

    // Cross-floor navigation: Determine best connector based on start location and preference
    Offset connectorPos;
    String connectorName;
    String transitionMsg;

    if (preference == TransitPreference.elevator) {
      connectorPos = liftCenter;
      connectorName = 'Central Passenger Lift';
      transitionMsg = 'Arrived at Lift. Please take the elevator to $destFloor';
    } else {
      // Choose nearest escalator to start position
      final dWest = (startPos - escWest).distance;
      final dCenter = (startPos - escCenter).distance;
      final dEast = (startPos - escEast).distance;

      if (dWest <= dCenter && dWest <= dEast) {
        connectorPos = escWest;
        connectorName = 'West Dual Escalator';
      } else if (dEast <= dCenter && dEast <= dWest) {
        connectorPos = escEast;
        connectorName = 'East Dual Escalator';
      } else {
        connectorPos = escCenter;
        connectorName = 'Center Main Escalator';
      }
      transitionMsg = 'Arrived at Escalator. Please take the escalator to $destFloor';
    }

    // Leg 1: On start floor to connector
    final leg1Points = findRawCorridorPath(startPos, startFloor, connectorPos, startFloor, preference: preference);

    // Leg 2: On destination floor from connector to destination
    final leg2Points = findRawCorridorPath(connectorPos, destFloor, destPos, destFloor, preference: preference);

    return NavigationPlan(
      legs: [
        RouteLeg(floor: startFloor, points: leg1Points),
        RouteLeg(floor: destFloor, points: leg2Points),
      ],
      requiresFloorTransition: true,
      transitMessage: transitionMsg,
      transitConnectorName: connectorName,
      transitPoint: connectorPos,
      targetFloor: destFloor,
    );
  }

  /// Multi-stop itinerary routing from starting position through all shops in currentStops
  static NavigationPlan computeItineraryPlan({
    required Offset startPos,
    required String startFloor,
    required List<Shop> stops,
    required List<StoreLotAnchor> allStores,
    TransitPreference preference = TransitPreference.escalator,
  }) {
    if (stops.isEmpty) {
      return const NavigationPlan(legs: []);
    }

    final firstStop = stops.first;
    final storeMatch = allStores.cast<StoreLotAnchor?>().firstWhere(
      (s) => s?.lotId == firstStop.primaryLot || s?.lotId == firstStop.lotId,
      orElse: () => null,
    );
    if (storeMatch == null) {
      return const NavigationPlan(legs: []);
    }

    final targetDoor = getStoreDoor(storeMatch);
    return planRoute(
      startPos: startPos,
      startFloor: startFloor,
      destPos: targetDoor,
      destFloor: storeMatch.floor,
      preference: preference,
    );
  }

  /// Backward compatible route calculation returning points for the current floor
  static List<Offset> computeItineraryRoute({
    required Offset startPos,
    required String startFloor,
    required List<Shop> stops,
    required List<StoreLotAnchor> allStores,
    TransitPreference preference = TransitPreference.escalator,
  }) {
    final plan = computeItineraryPlan(
      startPos: startPos,
      startFloor: startFloor,
      stops: stops,
      allStores: allStores,
      preference: preference,
    );
    return plan.routeForFloor(startFloor);
  }
}
