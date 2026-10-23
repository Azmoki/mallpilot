/// Single source of truth for Elmina map image coordinates (original pixels).
/// The new floor plan is landscape, 1737 × 930. Never resize/crop it without
/// rebuilding the route graph and any store/facility coordinates.
class ElminaMapConfig {
  ElminaMapConfig._();
  static const String mallName = 'Elmina Lakeside Mall';
  static const String floor = 'GF';
  static const double imageWidth = 1737;
  static const double imageHeight = 930;
  static const String imageAsset = 'assets/maps/gf_light_map.png';
  // GF routing is enabled: graph and mapped shops exist, but facilities and
  // shop polygons must be verified separately before production use.
  static const bool routesReady = true;
}
