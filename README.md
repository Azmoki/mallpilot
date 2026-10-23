# MallPilot AI — merged Flutter app + Stage 8 Python API

This is a **merged integration source project**, combining the two groupmates' Flutter work and connecting it to the user's **existing** MallPilot FastAPI Stage 8 backend. **It has not been compiled here** because Flutter/Dart SDK and an Android build environment are unavailable. Run `flutter analyze` and a device build on your computer before calling it production-ready.

## What was merged

- **From `mallpilot-main(Wingki).zip`:** complete Flutter platform scaffolding, home page, store directory, AI chat interface, stop list/reordering, estimated shopping duration, logo assets, and optional local keyword fallback.
- **From `MallPilot_SourceCode.zip`:** interactive 1000×1000 map, verified CAD store polygons, floor maps, pinch/zoom, lot highlighting, map store search, route overlays and simulated walking display.
- **From user's Stage 8 Python backend (run separately):** `/shops`, `/route`, `/optimize-journey`, `/recommend-shops`, `/recommend-journey`, `/map/GF/image`. The Flutter integration never recalculates the authoritative GF walking graph locally. The source project's `corridor_router.dart` is retained only for its door/facility models; its independent routing is **not used** for navigation.
- **Shared data:** bundled `assets/data/shops.json` is corrected to 155 records, including G52 JOHNNY'S, G53 BURGER KING, and G54 vacant. When connected to FastAPI, `GET /shops` supplies live GF stores and `node_id` mappings. Bundled JSON supports offline directory browsing; offline navigation is not available.

## Prerequisites

1. Have **Flutter installed** with an Android emulator or phone and a compatible Dart SDK (project `pubspec.yaml`: Dart `^3.12.2`).
2. Have your **existing** MallPilot backend directory, e.g. `D:\Downloads\MallPilot-Backend`, with your actual `mall_graph_GF.json`, `store_node_map_GF.json`, `shops.json`, and Stage 8 `api.py`.
3. Ensure FastAPI `/health` and `/route` worked in Swagger previously. **Do not replace backend files using this Flutter ZIP**.

## Run on Windows with Android emulator

Terminal A, existing **backend** directory:

```powershell
cd D:\Downloads\MallPilot-Backend
.\.venv\Scripts\python.exe -m uvicorn api:app --host 0.0.0.0 --port 8001 --reload
```

Check <http://127.0.0.1:8001/docs>. If port 8001 is in use, stop the old server or choose another port and update the Flutter command.

Terminal B, this **Flutter project** folder:

```powershell
flutter pub get
flutter analyze
flutter run --dart-define=MALLPILOT_API_BASE_URL=http://10.0.2.2:8001
```

`10.0.2.2` is the Android emulator's special address for the host PC. It is **not** your normal LAN IP. For Flutter **Windows desktop** run:

```powershell
flutter run -d windows --dart-define=MALLPILOT_API_BASE_URL=http://127.0.0.1:8001
```

For a **real Android phone**, connect the phone and PC to a reachable local network, find the PC IP with `ipconfig`, then run (example only, replace the address):

```powershell
flutter run --dart-define=MALLPILOT_API_BASE_URL=http://192.168.1.23:8001
```

Windows Firewall may need to allow TCP 8001. Android cleartext HTTP is enabled for **local prototype development only**; for deployment, use HTTPS and tighten network/CORS security.

## App usage

1. **Store Directory:** loads GF data/mappings from FastAPI, plus bundled 1F browse-only records. Filter, search and add to Stop List. Only GF is routable today.
2. **Stop List:** the **first store is the starting position**, all later stores are destinations. Add at least two mapped GF stores. Choose “Follow my sequence” for pairwise `/route` calls, or “Shortest path” for `/optimize-journey`. The app renders the backend's original pixel path over the backend's **canonical image** from `/map/GF/image`.
3. **AI Recommendation:** Wingki's chat UX now sends the prompt to the rule-based Stage 8 `/recommend-shops` endpoint. When offline, it falls back to local keyword recommendations (not a trained language model).
4. **Plan Recommended Journey:** select a mapped GF start shop, enter interests, budget and time, call `/recommend-journey`, view shop suggestions and open the mapped route.
5. **Explore Indoor Map:** zoom/pan around GF or preview 1F. On GF, select an occupied mapped store as your starting point and add further GF stores to request backend paths.

## Ground Floor map alignment

FastAPI returns coordinates such as `{ "x": 539, "y": 371 }`, measured on the original **1000×1000 pixel** GF image. The map canvas stays 1000×1000, and the GF base image is served from `/map/GF/image` to avoid coordinate misalignment from slightly different floor-plan drawings. If the backend is offline the app shows the bundled image instead, but cannot calculate paths.

## Backend / frontend contract

| Action | Endpoint | Request | Response fields used |
|---|---|---|---|
| Load GF directory | `GET /shops` | none | `shops: [{id, name, floor, lot_id, node_id, ...}]` |
| Pairwise Dijkstra | `POST /route` | `{start_shop_id, end_shop_id}` | `path: [{x, y, node_id}], distance_px` |
| Order selected stores | `POST /optimize-journey` | `{start_shop_id, shop_ids, mode:"visit_all"}` | `visit_order, legs[].path, total_distance_px` |
| Chat recommendations | `POST /recommend-shops` | `{query, mapped_only:true, max_results:6}` | `recommendations[].shop_id` |
| Automated plan | `POST /recommend-journey` | `{start_shop_id, query, budget_rm, time_limit_minutes, max_stops, mode:"visit_all"}` | `journey.visit_order, journey.legs, journey.total_distance_px` |
| Canonical map image | `GET /map/GF/image` | none | PNG 1000×1000 |

`shop_XXX` IDs are authoritative. Lot numbers such as `G13` are labels, and `GF_N009` is an internal routing node. They must **not** be interchanged.

## Scope and known limitations

- **Only GF routes** are backed by your validated Python graph. 1F can be previewed but 1F and vertical floor-to-floor routing are **not yet implemented**.
- **No real-time GPS / indoor positioning.** The blue position on the map and `Start Navigation` are a **simulation** along the server-computed path; the current start is explicitly set to a shop. Mall entrances without mapped graph anchors do not have a route yet.
- **No reliable walking minutes or true metres**: `distance_px` is image pixels. Real travel-time constraints require measured map-scale calibration.
- Rule-based recommendation scores and store price ranges are estimates, not trained AI recommendations or product-level quotes.
- Stage 9 corridor closure/rerouting is **not included**.
- Flutter `analyze`, Android emulator run, and a physical-device demo still must be done by your team. This container has no Flutter/Dart SDK.

## Main integration files

- `lib/services/mallpilot_api.dart` — API client, JSON → polyline points.
- `lib/data/store_repository.dart`, `lib/models/store.dart` — canonical shops.json and live GF mapping adapter.
- `lib/services/chat_service.dart` — remote rules-based recommendation + offline fallback.
- `lib/pages/stop_list_page.dart`, `lib/pages/navigation_page.dart` — pairwise vs optimised route integration.
- `lib/pages/recommended_journey_page.dart` — recommendation→journey flow.
- `lib/indoor_map.dart`, `lib/lots_data.dart`, `lib/corridor_router.dart` — teammate's interactive map and lot display, adapted to render FastAPI paths.

If the Flutter build fails on your local installed SDK, capture `flutter --version` and the **first `flutter analyze` error**; fixes should be made without resetting either groupmate's UI work.
