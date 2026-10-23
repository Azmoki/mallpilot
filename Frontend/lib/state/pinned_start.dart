import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/app_language.dart';

/// User-placed map location, snapped to an existing GF walking corridor.
/// This is NOT GPS / live indoor positioning.
@immutable
class PinnedStart {
  final double x;
  final double y;
  final double originalX;
  final double originalY;
  final double snapDistancePx;

  const PinnedStart({
    required this.x,
    required this.y,
    required this.originalX,
    required this.originalY,
    required this.snapDistancePx,
  });

  Offset get point => Offset(x, y);
  Map<String, dynamic> toApi() => {'x': x, 'y': y, 'floor': 'GF'};
  String get label => AppLanguage.t('pinned_start_label');

  factory PinnedStart.fromApi(Map<String, dynamic> data) => PinnedStart(
    x: (data['x'] as num).toDouble(),
    y: (data['y'] as num).toDouble(),
    originalX: (data['requested_x'] as num).toDouble(),
    originalY: (data['requested_y'] as num).toDouble(),
    snapDistancePx: (data['snap_distance_px'] as num).toDouble(),
  );
}

/// Explore Map and Plan Recommended Journey share the same manually-set pin.
final ValueNotifier<PinnedStart?> pinnedStart = ValueNotifier<PinnedStart?>(null);
