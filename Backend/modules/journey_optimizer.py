"""Exact GF multi-stop route planning for the MallPilot AI prototype.

Uses an undirected, image-pixel weighted graph. Optimises walking *distance*,
not store recommendation relevance. For up to MAX_STOPS destinations, a Held–Karp
subset DP finds a shortest open tour (start at selected shop; no return trip).

Budget modes:
- visit_all: includes all specified destinations and reports feasibility.
- fit_time: maximises destination count subject to visit + calibrated walking
  minutes, then minimises total elapsed time (ties: walking distance).

Never infer walking minutes from image pixels without metres_per_pixel.
"""

import math
from typing import Optional

import networkx as nx

MAX_STOPS = 10


def _brief(shop):
    return {
        "shop_id": shop["id"],
        "name": shop["name"],
        "lot_id": shop["lot_id"],
        "node_id": shop["node_id"],
        "avg_visit_time_min": float(shop["avg_visit_time_min"]),
        "kind": shop.get("kind", "shop"),
    }


def _build_network(graph_data, floor):
    if graph_data.get("floor") != floor:
        raise ValueError(f"Mall graph floor must be {floor}")
    network = nx.Graph()
    for node in graph_data["nodes"]:
        if node.get("floor", floor) != floor:
            raise ValueError(f"Node {node['id']} has a different floor")
        if node["id"] in network:
            raise ValueError(f"Duplicate node ID: {node['id']}")
        network.add_node(node["id"], **node)
    for edge in graph_data["edges"]:
        a, b = edge["from"], edge["to"]
        length = float(edge["distance_px"])
        if a not in network or b not in network:
            raise ValueError(f"Edge references a nonexistent node: {a}, {b}")
        if not math.isfinite(length) or length <= 0:
            raise ValueError(f"Invalid edge distance: {a}, {b}")
        if network.has_edge(a, b):
            length = min(length, network[a][b]["weight"])
        network.add_edge(a, b, weight=length)
    return network


def optimize_journey(
    graph_data,
    manager,
    start_identifier,
    shop_identifiers,
    *,
    mode="visit_all",
    time_limit_minutes: Optional[float] = None,
    meters_per_pixel: Optional[float] = None,
    walking_speed_m_per_min=60.0,
):
    """Return an efficient ordered trip with detailed Dijkstra route segments."""
    if mode not in ("visit_all", "fit_time"):
        raise ValueError("mode must be 'visit_all' or 'fit_time'")
    if not shop_identifiers or len(shop_identifiers) > MAX_STOPS:
        raise ValueError(f"Specify between 1 and {MAX_STOPS} destination shops")
    if time_limit_minutes is not None and (not math.isfinite(time_limit_minutes) or time_limit_minutes <= 0):
        raise ValueError("time_limit_minutes must be positive")
    if meters_per_pixel is not None and (not math.isfinite(meters_per_pixel) or meters_per_pixel <= 0):
        raise ValueError("meters_per_pixel must be positive")
    if not math.isfinite(walking_speed_m_per_min) or walking_speed_m_per_min <= 0:
        raise ValueError("walking_speed_m_per_min must be positive")
    if mode == "fit_time" and (time_limit_minutes is None or meters_per_pixel is None):
        raise ValueError("fit_time needs time_limit_minutes and calibrated meters_per_pixel")

    shops = [manager.get(start_identifier)] + [manager.get(i) for i in shop_identifiers]
    ids = [shop["id"] for shop in shops]
    if len(set(ids)) != len(ids):
        raise ValueError("Start and destination shops must be distinct; no duplicates")

    network = _build_network(graph_data, manager.floor)
    for shop in shops:
        node_id = shop.get("node_id")
        if not node_id:
            raise ValueError(f"Shop not mapped to an entrance yet: {shop['name']}")
        if node_id not in network:
            raise ValueError(f"Mapped entrance node missing from graph: {shop['name']} ({node_id})")
        if not shop.get("virtual_waypoint") and network.nodes[node_id].get("type") != "store_entrance":
            raise ValueError(f"Shop {shop['name']} maps to {node_id}, which is not a store_entrance")
        minutes = shop.get("avg_visit_time_min")
        if isinstance(minutes, bool) or not isinstance(minutes, (float, int)) or not math.isfinite(minutes) or minutes < 0:
            raise ValueError(f"Invalid avg_visit_time_min for {shop['name']}")

    # Compute shortest paths once from each selected shop, in original pixels.
    count = len(shops)
    distances = [[math.inf] * count for _ in range(count)]
    paths = {}
    for i, source in enumerate(shops):
        distances[i][i] = 0.0
        lengths, all_paths = nx.single_source_dijkstra(network, source["node_id"], weight="weight")
        for j, dest in enumerate(shops):
            node = dest["node_id"]
            if node in lengths:
                distances[i][j] = lengths[node]
                paths[(i, j)] = all_paths[node]

    n = len(shop_identifiers)
    all_mask = (1 << n) - 1
    visit_minutes = [float(shop["avg_visit_time_min"]) for shop in shops[1:]]
    visit_sums = [0.0] * (1 << n)
    for mask in range(1, all_mask + 1):
        bit = mask & -mask
        j = bit.bit_length() - 1
        visit_sums[mask] = visit_sums[mask ^ bit] + visit_minutes[j]

    # Held-Karp DP: shortest open path from start visiting exactly a subset.
    costs = {}
    parents = {}
    for j in range(n):
        if math.isfinite(distances[0][j + 1]):
            costs[(1 << j, j)] = distances[0][j + 1]
            parents[(1 << j, j)] = None

    for mask in range(1, all_mask + 1):
        for last in range(n):
            old_cost = costs.get((mask, last))
            if old_cost is None:
                continue
            for nxt in range(n):
                if mask & (1 << nxt):
                    continue
                leg = distances[last + 1][nxt + 1]
                if not math.isfinite(leg):
                    continue
                new_mask = mask | (1 << nxt)
                new_cost = old_cost + leg
                key = (new_mask, nxt)
                if key not in costs or new_cost < costs[key] - 1e-9:
                    costs[key] = new_cost
                    parents[key] = last

    meters_to_minutes = (
        meters_per_pixel / walking_speed_m_per_min if meters_per_pixel is not None else None
    )

    if mode == "visit_all":
        choices = [(cost, j) for (mask, j), cost in costs.items() if mask == all_mask]
        if not choices:
            raise ValueError("No walkable path can reach all requested destination shops")
        _, last = min(choices, key=lambda row: (row[0], row[1]))
        selected_mask = all_mask
    else:
        # Every selected destination has equal priority. Maximise count,
        # then minimise total elapsed time, and then walking distance.
        feasible = [(-0, 0.0, 0.0, 0, None)]  # start-only fallback
        for (mask, j), length in costs.items():
            elapsed = visit_sums[mask] + length * meters_to_minutes
            if elapsed <= time_limit_minutes + 1e-9:
                feasible.append((-mask.bit_count(), elapsed, length, mask, j))
        _, _, _, selected_mask, last = min(feasible)

    ordered_indexes = []
    mask = selected_mask
    while last is not None:
        ordered_indexes.append(last + 1)
        previous = parents[(mask, last)]
        mask ^= 1 << last
        last = previous
    ordered_indexes.reverse()

    legs = []
    journey_distance = 0.0
    previous_shop_index = 0
    for shop_index in ordered_indexes:
        a, b = shops[previous_shop_index], shops[shop_index]
        distance = distances[previous_shop_index][shop_index]
        ids_in_path = paths[(previous_shop_index, shop_index)]
        legs.append({
            "from_shop_id": a["id"],
            "to_shop_id": b["id"],
            "distance_px": round(distance, 2),
            "path": [
                {
                    "node_id": nid,
                    "x": network.nodes[nid]["x"],
                    "y": network.nodes[nid]["y"],
                    "floor": manager.floor,
                }
                for nid in ids_in_path
            ],
        })
        journey_distance += distance
        previous_shop_index = shop_index

    total_visits = visit_sums[selected_mask]
    walking_mins = journey_distance * meters_to_minutes if meters_to_minutes is not None else None
    total_mins = total_visits + walking_mins if walking_mins is not None else None
    if time_limit_minutes is None:
        budget_status = "not_requested"
        fits = None
    elif total_visits > time_limit_minutes + 1e-9:
        budget_status = "exceeds_budget_even_without_walking"
        fits = False
    elif total_mins is None:
        budget_status = "unknown_without_map_scale"
        fits = None
    elif total_mins <= time_limit_minutes + 1e-9:
        budget_status = "within_estimated_budget"
        fits = True
    else:
        budget_status = "exceeds_estimated_budget"
        fits = False

    selected_set = set(ordered_indexes)
    return {
        "floor": manager.floor,
        "mode": mode,
        "optimization_method": "exact_subset_dynamic_programming",
        "distance_unit": "image_pixels",
        "image_width": graph_data["image_width"],
        "image_height": graph_data["image_height"],
        "start": _brief(shops[0]),
        "visit_order": [_brief(shops[i]) for i in ordered_indexes],
        "skipped_shops": [_brief(shops[i]) for i in range(1, count) if i not in selected_set],
        "legs": legs,
        "total_distance_px": round(journey_distance, 2),
        "total_visit_minutes": round(total_visits, 2),
        "estimated_walking_minutes": round(walking_mins, 2) if walking_mins is not None else None,
        "estimated_total_minutes": round(total_mins, 2) if total_mins is not None else None,
        "time_limit_minutes": time_limit_minutes,
        "fits_time_limit": fits,
        "budget_status": budget_status,
        "calibration": {
            "meters_per_pixel": meters_per_pixel,
            "assumed_walking_speed_m_per_min": walking_speed_m_per_min if meters_per_pixel else None,
        },
        "notes": [
            "Start shop is the current position; its visit time is not counted.",
            "Walking estimates require a measured metres-per-pixel map calibration.",
            "No return to the start shop is included.",
            "Stops have equal priority; personalised recommendations are a future stage.",
        ],
    }
