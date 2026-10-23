r"""MallPilot AI — Ground Floor FastAPI backend (through Stage 8).

This is a NEW file named api.py, intentionally separate from any existing main.py.
It reuses the TESTED Stage 4 store manager and Dijkstra calculation:
    modules/store_manager.py
    tools/test_store_route.py

Run from the MallPilot-Backend folder in VS Code PowerShell:
    .\.venv\Scripts\python.exe -m uvicorn api:app --host 0.0.0.0 --port 8000 --reload

Shop and graph source files are READ-ONLY. Mapping changes are picked up on
new requests without needing to restart the API.
"""

import json
from pathlib import Path
from typing import Optional, Literal

import networkx as nx
from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field

from modules.store_manager import StoreDataManager
from tools.test_store_route import calculate_route
from modules.journey_optimizer import optimize_journey

ROOT = Path(__file__).resolve().parent
DATA_DIR = ROOT / "data"
FLOOR = "GF"  # Current implementation. Add 1F once its graph exists.
SHOPS_FILE = DATA_DIR / "shops.json"
MAPPING_FILE = DATA_DIR / "store_node_map_GF.json"
GRAPH_FILE = DATA_DIR / "mall_graph_GF.json"
IMAGE_FILE = DATA_DIR / "gf_light_map.png"

app = FastAPI(
    title="MallPilot AI — Elmina Lakeside Mall GF API",
    version="0.9.0",
    description="Shop search, Dijkstra, multi-stop optimisation and preference-based recommendations (GF).",
)

# Prototype/dev access for Flutter/web frontends. Restrict origins before deployment.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)


class RouteRequest(BaseModel):
    # Prefer stable team IDs such as 'shop_012', but lot IDs and exact names
    # also work because the shared StoreDataManager resolves those identifiers.
    start_shop_id: str = Field(min_length=1, examples=["shop_012"])
    end_shop_id: str = Field(min_length=1, examples=["shop_014"])


def require_file(path: Path) -> None:
    if not path.is_file():
        raise HTTPException(
            status_code=503,
            detail=f"Required data file not found: data/{path.name}",
        )


def load_manager() -> StoreDataManager:
    require_file(SHOPS_FILE)
    try:
        # The mapping file may be absent while shops are being assigned.
        return StoreDataManager(SHOPS_FILE, MAPPING_FILE, FLOOR)
    except (ValueError, KeyError, OSError, json.JSONDecodeError) as exc:
        raise HTTPException(status_code=500, detail=f"Invalid store data: {exc}") from exc


def load_graph() -> dict:
    require_file(GRAPH_FILE)
    try:
        with GRAPH_FILE.open("r", encoding="utf-8") as handle:
            graph = json.load(handle)
        if not isinstance(graph, dict) or graph.get("floor") != FLOOR:
            raise ValueError(f"Expected a {FLOOR!r} graph")
        for key in ("nodes", "edges", "image_width", "image_height"):
            if key not in graph:
                raise ValueError(f"Missing graph field: {key}")
        return graph
    except (ValueError, OSError, json.JSONDecodeError) as exc:
        raise HTTPException(status_code=500, detail=f"Invalid mall graph: {exc}") from exc


def require_pedestrian_graph() -> dict:
    """Return 503 until the Elmina pedestrian path network has been drawn."""
    graph = load_graph()
    if not graph.get('nodes') or not graph.get('edges'):
        raise HTTPException(
            status_code=503,
            detail='Elmina pedestrian paths are not mapped yet (Stage 2 required).',
        )
    return graph


@app.get("/", tags=["Info"])
def homepage():
    return {
        "service": "MallPilot AI Ground Floor API",
        "documentation": "/docs",
        "endpoints": ["/health", "/shops", "/shops/{shop_id}",
                      "/graph/GF", "/map/GF/image", "/route", "/optimize-journey",
                      "/recommend-shops", "/recommend-journey", "/public-services",
                      "/snap-position", "/plan-route", "/recommend-journey-from-pin"],
    }


@app.get("/health", tags=["Info"])
def health():
    manager = load_manager()
    graph = load_graph()
    return {
        "status": "mapping_required" if not graph["edges"] or not manager.mapped_stores() else "ok",
        "mall": "Elmina Lakeside Mall",
        "image_width": graph["image_width"],
        "image_height": graph["image_height"],
        "floor": FLOOR,
        "occupied_shops": len(manager.shops),
        "mapped_shops": len(manager.mapped_stores()),
        "graph_nodes": len(graph["nodes"]),
        "graph_edges": len(graph["edges"]),
        "distance_unit": "image_pixels",
    }


@app.get("/shops", tags=["Shops"])
def list_shops(
    q: Optional[str] = Query(default=None, description="Search name, lot ID or category"),
    mapped_only: bool = Query(default=False),
):
    manager = load_manager()
    result = manager.mapped_stores() if mapped_only else manager.all_stores()
    if q and q.strip():
        query = q.strip().casefold()
        result = [
            shop for shop in result
            if any(query in str(shop.get(field, "")).casefold() for field in
                   ("id", "name", "lot_id", "primary_lot", "category", "sub_category"))
            or any(query in str(lot).casefold() for lot in (shop.get("lots") or []))
        ]
    return {"floor": FLOOR, "count": len(result), "shops": result}


@app.get("/shops/{shop_id}", tags=["Shops"])
def shop_detail(shop_id: str):
    manager = load_manager()
    try:
        return manager.get(shop_id)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=f"Shop not found: {shop_id}") from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.get("/graph/GF", tags=["Map"])
def ground_floor_graph():
    """Image-pixel node coordinates and corridor edges for Flutter to draw."""
    return load_graph()


@app.get("/map/GF/image", tags=["Map"])
def ground_floor_image():
    require_file(IMAGE_FILE)
    return FileResponse(IMAGE_FILE, media_type="image/png")


@app.post("/route", tags=["Routing"])
def route(request: RouteRequest):
    """Shortest route for two occupied, mapped GF shops.

    Coordinates and distance are in ORIGINAL floor-plan image pixels.
    This route has not yet been calibrated to metres or walking minutes.
    """
    manager = load_manager()
    graph = require_pedestrian_graph()
    try:
        return calculate_route(
            graph, manager, request.start_shop_id, request.end_shop_id
        )
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=f"Unknown shop: {exc}") from exc
    except (ValueError, nx.NetworkXError) as exc:
        message = str(exc)
        if message.startswith("No walkable path"):
            raise HTTPException(status_code=409, detail=message) from exc
        if "not mapped" in message or "not a store_entrance" in message:
            raise HTTPException(status_code=422, detail=message) from exc
        raise HTTPException(status_code=400, detail=message) from exc


class JourneyRequest(BaseModel):
    # Stable shared IDs such as shop_012 are recommended. Lot IDs also work.
    start_shop_id: str = Field(min_length=1, examples=["shop_012"])
    shop_ids: list[str] = Field(min_length=1, max_length=10,
                                examples=[["shop_014", "shop_004", "shop_034"]])
    time_limit_minutes: Optional[float] = Field(default=None, gt=0, examples=[120])
    mode: Literal["visit_all", "fit_time"] = "visit_all"
    # IMPORTANT: This is not a guess. Supply only once the floor map is calibrated.
    meters_per_pixel: Optional[float] = Field(default=None, gt=0)
    walking_speed_m_per_min: float = Field(default=60.0, gt=0)


@app.post("/optimize-journey", tags=["Routing"])
def optimize_journey_endpoint(request: JourneyRequest):
    """Optimise visiting order of mapped GF shops using actual Dijkstra paths.

    visit_all: exact shortest open tour, reports time budget only when measurable.
    fit_time: maximises shops visited given calibrated walking time and shop time.
    """
    manager = load_manager()
    graph = require_pedestrian_graph()
    try:
        return optimize_journey(
            graph, manager, request.start_shop_id, request.shop_ids,
            mode=request.mode,
            time_limit_minutes=request.time_limit_minutes,
            meters_per_pixel=request.meters_per_pixel,
            walking_speed_m_per_min=request.walking_speed_m_per_min,
        )
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=f"Unknown shop: {exc}") from exc
    except (ValueError, nx.NetworkXError) as exc:
        message = str(exc)
        if message.startswith("No walkable path"):
            code = 409
        elif "not mapped" in message or "not a store_entrance" in message:
            code = 422
        else:
            code = 400
        raise HTTPException(status_code=code, detail=message) from exc


# ----------------------- Stage 8: Shop Recommendations -----------------------
from modules.recommender import recommend_shops
from modules.recommendation_planner import recommend_journey


class RecommendShopsRequest(BaseModel):
    # Examples: interests=["sportswear", "food"] or a simple text query.
    interests: list[str] = Field(default_factory=list, max_length=8)
    query: Optional[str] = Field(default=None, max_length=300)
    budget_rm: Optional[float] = Field(default=None, gt=0)
    max_results: int = Field(default=10, ge=1, le=30)
    mapped_only: bool = False


@app.post("/recommend-shops", tags=["Recommendations"])
def recommend_shops_endpoint(request: RecommendShopsRequest):
    """Rank occupied GF shops using the team's existing categories and prices."""
    manager = load_manager()
    try:
        return recommend_shops(
            manager,
            interests=request.interests,
            query=request.query,
            budget_rm=request.budget_rm,
            max_results=request.max_results,
            mapped_only=request.mapped_only,
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc


class RecommendJourneyRequest(BaseModel):
    start_shop_id: str = Field(min_length=1, examples=["shop_012"])
    interests: list[str] = Field(default_factory=list, max_length=8)
    query: Optional[str] = Field(default=None, max_length=300)
    budget_rm: Optional[float] = Field(default=None, gt=0)
    max_stops: int = Field(default=3, ge=1, le=10)
    time_limit_minutes: Optional[float] = Field(default=None, gt=0)
    mode: Literal["visit_all", "fit_time"] = "visit_all"
    # Only include this once a physical corridor measurement calibrates the map.
    meters_per_pixel: Optional[float] = Field(default=None, gt=0)
    walking_speed_m_per_min: float = Field(default=60.0, gt=0)


@app.post("/recommend-journey", tags=["Recommendations"])
def recommend_journey_endpoint(request: RecommendJourneyRequest):
    """Pick relevant reachable mapped shops; optimise their visiting order."""
    manager = load_manager()
    graph = require_pedestrian_graph()
    try:
        return recommend_journey(
            graph, manager,
            start_shop_id=request.start_shop_id,
            interests=request.interests,
            query=request.query,
            budget_rm=request.budget_rm,
            max_stops=request.max_stops,
            time_limit_minutes=request.time_limit_minutes,
            mode=request.mode,
            meters_per_pixel=request.meters_per_pixel,
            walking_speed_m_per_min=request.walking_speed_m_per_min,
        )
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=f"Unknown shop: {exc}") from exc
    except (ValueError, nx.NetworkXError) as exc:
        message = str(exc)
        if "not mapped" in message or "Invalid mapped" in message:
            code = 422
        elif message.startswith("No walkable path"):
            code = 409
        else:
            code = 400
        raise HTTPException(status_code=code, detail=message) from exc

# ---------------- Map-pinned start + public service routing (GF) ----------------
from modules.pin_routing import (
    WaypointManager, prepare_pinned_graph, snap_point, virtual_stop,
)

PUBLIC_SERVICES_FILE = DATA_DIR / 'public_services_GF.json'


def load_public_services():
    require_file(PUBLIC_SERVICES_FILE)
    with PUBLIC_SERVICES_FILE.open('r', encoding='utf-8') as file:
        # Parking locations are intentionally excluded from public services
        # and route destinations, including if an older JSON is deployed.
        return {
            item['id']: item for item in json.load(file)
            if str(item.get('category', '')).lower() != 'parking'
        }


class MapPosition(BaseModel):
    x: float = Field(ge=0)
    y: float = Field(ge=0)
    floor: Literal['GF'] = 'GF'


class PinPlanRequest(BaseModel):
    start_position: MapPosition
    shop_ids: list[str] = Field(default_factory=list, max_length=10)
    public_service_ids: list[str] = Field(default_factory=list, max_length=10)
    destination_order: list[str] = Field(default_factory=list, max_length=10)
    mode: Literal['sequence', 'shortest'] = 'shortest'
    time_limit_minutes: Optional[float] = Field(default=None, gt=0)


@app.get('/public-services', tags=['Map'])
def public_services():
    """Elmina floor-plan markers; each item has its own verification flag."""
    items = list(load_public_services().values())
    source = ('verified' if items and all(item.get('verified', False) for item in items)
              else 'mixed' if any(item.get('verified', False) for item in items)
              else 'prototype_unverified')
    return {'floor': FLOOR, 'services': items, 'source': source}


@app.post('/snap-position', tags=['Routing'])
def snap_position(position: MapPosition):
    """Project a manually placed location pin to the nearest known corridor."""
    try:
        snap = snap_point(require_pedestrian_graph(), position.x, position.y)
        return {k: v for k, v in snap.items() if k != 'fraction'}
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc


def _prepare_route_waypoints(graph, manager, start_position, service_ids):
    facilities = load_public_services()
    if len(service_ids) != len(set(service_ids)):
        raise ValueError('Duplicate public service destinations')
    pins = {'__start': {'x': start_position.x, 'y': start_position.y}}
    for service_id in service_ids:
        if service_id not in facilities:
            raise ValueError(f'Unknown Ground Floor public service: {service_id}')
        service = facilities[service_id]
        if service.get('route_enabled') is False:
            raise ValueError(
                f'{service["name"]}: pedestrian connection is not mapped yet. '
                'This location is map-only until a walkable route is verified.'
            )
        pins[f'facility:{service_id}'] = service
    routed_graph, snapped = prepare_pinned_graph(graph, pins)
    virtual = {'__start': virtual_stop('__start', 'Pinned starting position',
                                       snapped['__start'], kind='start')}
    for service_id in service_ids:
        key = f'facility:{service_id}'
        virtual[key] = virtual_stop(key, facilities[service_id]['name'],
                                    snapped[key], kind='public_service')
    return routed_graph, WaypointManager(manager, virtual), snapped


@app.post('/plan-route', tags=['Routing'])
def plan_route(request: PinPlanRequest):
    """Route from a user-placed corridor pin through shops and/or facilities.

    Selection order is preserved for `sequence` and optimised with the existing
    Held-Karp engine for `shortest`. No cross-floor routing in this prototype.
    """
    manager = load_manager()
    graph = require_pedestrian_graph()
    shop_ids, services = request.shop_ids, request.public_service_ids
    if not shop_ids and not services:
        raise HTTPException(status_code=422, detail='Select at least one shop or public service')
    if len(shop_ids) + len(services) > 10:
        raise HTTPException(status_code=422, detail='Up to ten destinations are supported')
    try:
        # Reject the same shop listed twice and ensure each shop is routable.
        resolved_ids = [manager.get(i)['id'] for i in shop_ids]
        if len(resolved_ids) != len(set(resolved_ids)):
            raise ValueError('Duplicate shop destinations')
        graph, waypoint_manager, snapped = _prepare_route_waypoints(
            graph, manager, request.start_position, services,
        )
        ids = resolved_ids + [f'facility:{name}' for name in services]
        if request.destination_order:
            if len(request.destination_order) != len(ids) or set(request.destination_order) != set(ids):
                raise ValueError('Destination sequence does not match selected shops and facilities')
            ids = request.destination_order
        if request.mode == 'shortest':
            journey = optimize_journey(graph, waypoint_manager, '__start', ids,
                                       time_limit_minutes=request.time_limit_minutes)
        else:
            # Use the existing Dijkstra route graph for each individual leg.
            # A fixed sequence has exactly one possible visit order.
            from modules.journey_optimizer import _build_network, _brief
            net = _build_network(graph, FLOOR)
            stops = [waypoint_manager.get('__start')] + [waypoint_manager.get(i) for i in ids]
            legs = []
            total_px = 0.0
            for a, b in zip(stops, stops[1:]):
                path = nx.dijkstra_path(net, a['node_id'], b['node_id'], weight='weight')
                distance = nx.dijkstra_path_length(net, a['node_id'], b['node_id'], weight='weight')
                total_px += distance
                legs.append({
                    'from_shop_id': a['id'], 'to_shop_id': b['id'],
                    'distance_px': round(distance, 2),
                    'path': [{'node_id': p, 'x': net.nodes[p]['x'], 'y': net.nodes[p]['y'],
                              'floor': FLOOR} for p in path],
                })
            journey = {
                'floor': FLOOR, 'mode': 'sequence', 'distance_unit': 'image_pixels',
                'start': _brief(stops[0]), 'visit_order': [_brief(s) for s in stops[1:]],
                'legs': legs, 'total_distance_px': round(total_px, 2),
                'total_visit_minutes': sum(s['avg_visit_time_min'] for s in stops[1:]),
                'estimated_walking_minutes': None,
                'budget_status': 'unknown_without_map_scale' if request.time_limit_minutes else 'not_requested',
            }
        journey['snapped_start'] = {
            k: v for k, v in snapped['__start'].items() if k not in ('fraction',)
        }
        journey['service_locations_unverified'] = any(not load_public_services()[service_id].get('verified', False) for service_id in services)
        return journey
    except nx.NetworkXNoPath as exc:
        raise HTTPException(status_code=409, detail='No walkable graph route between selected destinations') from exc
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=f'Unknown shop: {exc}') from exc
    except ValueError as exc:
        msg = str(exc)
        status = 409 if 'No walkable path' in msg else 422
        raise HTTPException(status_code=status, detail=msg) from exc


class RecommendFromPinRequest(BaseModel):
    start_position: MapPosition
    query: str = Field(default='', max_length=300)
    budget_rm: Optional[float] = Field(default=None, gt=0)
    time_limit_minutes: Optional[float] = Field(default=None, gt=0)
    max_stops: int = Field(default=3, ge=1, le=10)


@app.post('/recommend-journey-from-pin', tags=['Recommendations'])
def recommend_journey_from_pin(request: RecommendFromPinRequest):
    from modules.recommendation_planner import recommend_journey
    graph, manager = require_pedestrian_graph(), load_manager()
    try:
        graph, waypoint_manager, snapped = _prepare_route_waypoints(
            graph, manager, request.start_position, [],
        )
        result = recommend_journey(
            graph, waypoint_manager, start_shop_id='__start', query=request.query,
            budget_rm=request.budget_rm, max_stops=request.max_stops,
            time_limit_minutes=request.time_limit_minutes,
        )
        result['snapped_start'] = {k: v for k, v in snapped['__start'].items() if k != 'fraction'}
        return result
    except nx.NetworkXNoPath as exc:
        raise HTTPException(status_code=409, detail='No walkable path from pinned start') from exc
    except (KeyError, ValueError) as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc


# --------------------- Adaptive / progressive recommendations ---------------------
from modules.adaptive_journey import recommend_adaptive


class AdaptiveJourneyRequest(BaseModel):
    # Initial batch: pin the start. Follow-up: use the last pending shop as
    # the starting node, while excluding everything already visited/planned.
    start_position: Optional[MapPosition] = None
    start_shop_id: Optional[str] = None
    interests: list[str] = Field(min_length=1, max_length=8)
    spending: Literal['affordable', 'balanced', 'premium'] = 'balanced'
    style: Literal['quick', 'balanced', 'discovery'] = 'balanced'
    max_stops: Optional[int] = Field(default=None, ge=1, le=7)
    excluded_shop_ids: list[str] = Field(default_factory=list, max_length=100)
    history_shop_ids: list[str] = Field(default_factory=list, max_length=100)
    locked_shop_ids: list[str] = Field(default_factory=list, max_length=7)
    variation: int = Field(default=0, ge=0, le=100000)


@app.post('/adaptive-journey', tags=['Recommendations'])
def adaptive_journey_endpoint(request: AdaptiveJourneyRequest):
    if (request.start_position is None) == (request.start_shop_id is None):
        raise HTTPException(status_code=422, detail='Provide either a pinned start or a start shop ID')
    manager = load_manager()
    graph = require_pedestrian_graph()
    try:
        if request.start_position is not None:
            graph, manager, _ = _prepare_route_waypoints(
                graph, manager, request.start_position, [])
            starting_id = '__start'
        else:
            starting_id = request.start_shop_id
        return recommend_adaptive(
            graph, manager, start_shop_id=starting_id,
            interests=request.interests, spending=request.spending,
            style=request.style, max_stops=request.max_stops,
            excluded_shop_ids=request.excluded_shop_ids,
            history_shop_ids=request.history_shop_ids, locked_shop_ids=request.locked_shop_ids,
            variation=request.variation,
        )
    except (ValueError, nx.NetworkXError) as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=f'Unknown shop: {exc}') from exc
