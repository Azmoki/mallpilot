import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../config/elmina_map_config.dart';
import 'navigation_page.dart';

/// Ground Floor display of the active Elmina mall. Taps show image-pixel coordinates
/// for planning/coordinate inspection only; use MapExplorerPage for routes.
class ElminaMapPage extends StatefulWidget {
  const ElminaMapPage({super.key});

  @override
  State<ElminaMapPage> createState() => _ElminaMapPageState();
}

class _ElminaMapPageState extends State<ElminaMapPage> {
  final TransformationController _viewController = TransformationController();
  Offset? _tappedPoint;
  Size? _viewportSize;

  @override
  void dispose() {
    _viewController.dispose();
    super.dispose();
  }

  void _fitMap(Size viewport) {
    if (viewport.width <= 0 || viewport.height <= 0) return;
    // Same scale in X and Y, with padding; does not deform the original map.
    final scale = math.min(
      viewport.width / ElminaMapConfig.imageWidth,
      viewport.height / ElminaMapConfig.imageHeight,
    ) * 0.96;
    _viewController.value = Matrix4.diagonal3Values(scale, scale, 1)
      ..setTranslationRaw(
        (viewport.width - ElminaMapConfig.imageWidth * scale) / 2,
        (viewport.height - ElminaMapConfig.imageHeight * scale) / 2,
        0,
      );
  }

  void _onMapTap(TapUpDetails details) {
    final point = details.localPosition;
    if (point.dx < 0 || point.dy < 0 ||
        point.dx > ElminaMapConfig.imageWidth ||
        point.dy > ElminaMapConfig.imageHeight) return;
    setState(() => _tappedPoint = point);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Elmina · Ground Floor'),
      actions: [
        IconButton(
          icon: const Icon(Icons.route),
          tooltip: 'Open route-enabled map',
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const MapExplorerPage())),
        ),
        IconButton(
          icon: const Icon(Icons.center_focus_strong),
          tooltip: 'Fit map to screen',
          onPressed: () {
            if (_viewportSize != null) _fitMap(_viewportSize!);
          },
        ),
      ],
    ),
    body: Column(
      children: [
        Container(
          width: double.infinity,
          color: const Color(0xFFE8F7F1),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: const Text(
            'Elmina map · coordinate inspector (1737 × 930). Pedestrian routing is '
            'available from Explore Map & Stores on the home page.',
            style: TextStyle(color: Color(0xFF14532D), fontSize: 12),
          ),
        ),
        Expanded(
          child: LayoutBuilder(builder: (context, limits) {
            final viewport = Size(limits.maxWidth, limits.maxHeight);
            if (_viewportSize != viewport) {
              _viewportSize = viewport;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _viewportSize == viewport) _fitMap(viewport);
              });
            }
            return Container(
              color: const Color(0xFFF1F5F9),
              child: InteractiveViewer(
                transformationController: _viewController,
                constrained: false,
                minScale: 0.12,
                maxScale: 5,
                boundaryMargin: const EdgeInsets.all(500),
                child: SizedBox(
                  width: ElminaMapConfig.imageWidth,
                  height: ElminaMapConfig.imageHeight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: _onMapTap,
                    child: Stack(children: [
                      Positioned.fill(
                        child: Image.asset(
                          ElminaMapConfig.imageAsset,
                          fit: BoxFit.fill, // exact native image-size canvas
                          filterQuality: FilterQuality.high,
                          errorBuilder: (_, error, __) => Center(
                            child: Text('Map asset unavailable: $error',
                              style: const TextStyle(color: Colors.white)),
                          ),
                        ),
                      ),
                      if (_tappedPoint != null)
                        Positioned(
                          left: _tappedPoint!.dx - 14,
                          top: _tappedPoint!.dy - 28,
                          child: const IgnorePointer(
                            child: Icon(Icons.location_on,
                              color: Color(0xFF10B981), size: 30),
                          ),
                        ),
                    ]),
                  ),
                ),
              ),
            );
          }),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Text(
              _tappedPoint == null
                  ? 'Tap the map to inspect pixel coordinates · 1737 × 930'
                  : 'Selected image point: '
                    '(${_tappedPoint!.dx.round()}, ${_tappedPoint!.dy.round()}) · '
                    'Coordinate inspection only — not saved as a node',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    ),
  );
}
