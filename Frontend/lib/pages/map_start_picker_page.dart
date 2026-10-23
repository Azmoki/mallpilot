import '../config/elmina_map_config.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/mallpilot_api.dart';
import '../services/app_language.dart';
import '../state/pinned_start.dart';

/// Tap the existing GF floor plan to set your APPROXIMATE current location.
/// The backend snaps the tap to the actual walkable corridor network.
class MapStartPickerPage extends StatefulWidget {
  final PinnedStart? initial;
  const MapStartPickerPage({super.key, this.initial});

  @override
  State<MapStartPickerPage> createState() => _MapStartPickerPageState();
}

class _MapStartPickerPageState extends State<MapStartPickerPage> {
  final TransformationController _controller = TransformationController();
  PinnedStart? _selection;
  Offset? _tapped;
  bool _loading = false;
  String? _error;
  Size? _screenSize;
  bool _fitted = false;
  int _requestNumber = 0;

  @override
  void initState() {
    super.initState();
    _selection = widget.initial;
    _tapped = widget.initial == null
        ? null : Offset(widget.initial!.originalX, widget.initial!.originalY);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _fit(Size viewport) {
    final scale = math.min(viewport.width / ElminaMapConfig.imageWidth, viewport.height / ElminaMapConfig.imageHeight) * 0.96;
    _controller.value = Matrix4.diagonal3Values(scale, scale, 1)
      ..setTranslationRaw((viewport.width - ElminaMapConfig.imageWidth * scale) / 2,
          (viewport.height - ElminaMapConfig.imageHeight * scale) / 2, 0);
  }

  Future<void> _placePin(Offset tap) async {
    if (tap.dx < 0 || tap.dy < 0 || tap.dx > ElminaMapConfig.imageWidth || tap.dy > ElminaMapConfig.imageHeight) return;
    if (!ElminaMapConfig.routesReady) {
      setState(() {
        _tapped = tap;
        _selection = null;
        _error = 'Location snapping is not available until Stage 2 pedestrian paths are mapped.';
      });
      return;
    }
    final requestId = ++_requestNumber;
    setState(() { _tapped = tap; _selection = null; _loading = true; _error = null; });
    try {
      final result = await MallPilotApi.snapPosition(tap);
      if (!mounted || requestId != _requestNumber) return;
      setState(() { _selection = PinnedStart.fromApi(result); _loading = false; });
    } catch (error) {
      if (!mounted || requestId != _requestNumber) return;
      var msg = error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      msg = msg.replaceFirst(RegExp(r'^Backend HTTP \d+:\s*'), '');
      if (msg.contains('too far') || msg.contains('corridor')) {
        msg = AppLanguage.t('point_too_far_err');
      }
      setState(() { _error = msg; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(AppLanguage.t('pin_location_title'))),
    body: Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Text(AppLanguage.t('pin_location_intro')),
      ),
      Expanded(child: LayoutBuilder(builder: (context, limits) {
        final size = Size(limits.maxWidth, limits.maxHeight);
        if (_screenSize != size) {
          _screenSize = size;
          if (!_fitted) {
            _fitted = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _fit(size);
            });
          }
        }
        return Container(
          color: const Color(0xFFF1F5F9),
          child: InteractiveViewer(
            transformationController: _controller,
            constrained: false,
            minScale: 0.15,
            maxScale: 8,
            boundaryMargin: const EdgeInsets.all(400),
            child: SizedBox(
              width: ElminaMapConfig.imageWidth, height: ElminaMapConfig.imageHeight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) => _placePin(details.localPosition),
                child: Stack(children: [
                  Positioned.fill(child: Image.asset(ElminaMapConfig.imageAsset, fit: BoxFit.fill)),
                  if (_tapped != null)
                    Positioned(left: _tapped!.dx - 12, top: _tapped!.dy - 12,
                      child: const IgnorePointer(child: Icon(Icons.touch_app, color: Colors.orange, size: 24))),
                  if (_selection != null)
                    Positioned(left: _selection!.x - 18, top: _selection!.y - 38,
                      child: const IgnorePointer(child: Icon(
                        Icons.location_on, color: Color(0xFF10B981), size: 38,
                        shadows: [Shadow(color: Colors.black87, blurRadius: 5)],
                      ))),
                ]),
              ),
            ),
          ),
        );
      })),
      SafeArea(top: false, child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (_selection != null) Text(AppLanguage.t('pin_start_success'),
              style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF10B981)),
              textAlign: TextAlign.center),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: FilledButton.icon(
            onPressed: _selection == null || _loading ? null : () => Navigator.pop(context, _selection),
            icon: const Icon(Icons.check), label: Text(AppLanguage.t('use_this_start')),
          )),
        ]),
      )),
    ]),
  );
}
