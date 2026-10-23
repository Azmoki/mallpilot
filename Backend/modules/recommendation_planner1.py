"""Connect rule-based recommendations to existing Stage 7 Dijkstra optimiser.

Recommendations decide WHICH shops to consider; Stage 7 plans a shortest
walking order between those selected shops. This is a heuristic shop-selection
stage, not a globally optimal joint relevance/budget/orienteering solver.
"""

import math

import networkx as nx

from modules.journey_optimizer import _build_network, optimize_journey
from modules.recommender import recommend_shops


def recommend_journey(graph, manager, *, start_shop_id, interests=None,
                      query=None, budget_rm=None, max_stops=3,
                      time_limit_minutes=None, mode="visit_all",
                      meters_per_pixel=None, walking_speed_m_per_min=60.0):
    if not 1 <= max_stops <= 10:
        raise ValueError("max_stops must be between 1 and 10")
    if mode not in ("visit_all", "fit_time"):
        raise ValueError("mode must be 'visit_all' or 'fit_time'")
    if mode == "fit_time" and (time_limit_minutes is None or meters_per_pixel is None):
        raise ValueError("fit_time needs time_limit_minutes and measured meters_per_pixel")
    if budget_rm is not None and (not math.isfinite(budget_rm) or budget_rm <= 0):
        raise ValueError("budget_rm must be positive")

    starting_shop = manager.get(start_shop_id)
    start_node = starting_shop.get("node_id")
    if not start_node:
        raise ValueError(f"Start shop not mapped to an entrance yet: {starting_shop['name']}")

    network = _build_network(graph, manager.floor)
    if start_node not in network or network.nodes[start_node].get("type") != "store_entrance":
        raise ValueError(f"Invalid mapped start entrance: {start_node}")
    reachable = nx.node_connected_component(network, start_node)

    recommended = recommend_shops(
        manager,
        interests=interests,
        query=query,
        budget_rm=budget_rm,
        max_results=None,
        mapped_only=True,
        exclude_shop_ids=(starting_shop["id"],),
    )
    valid = [shop for shop in recommended["recommendations"]
             if shop["node_id"] in reachable
             and network.nodes[shop["node_id"]].get("type") == "store_entrance"]

    # Prefer uncovered interests (e.g. some sport + some food), then relevance.
    # Respect only NECESSARY budget/time conditions before routing. Without
    # metres_per_pixel, walking-time feasibility is unknown.
    candidates = valid[:]
    chosen = []
    uncovered = set(recommended["interpreted_interests"])
    min_spend = 0.0
    total_visit_mins = 0.0
    while candidates and len(chosen) < max_stops:
        feasible = []
        for shop in candidates:
            low_price = shop["min_price_rm"]
            visit_time = shop["avg_visit_time_min"]
            if budget_rm is not None and (low_price is None or min_spend + low_price > budget_rm + 1e-9):
                continue
            if not isinstance(visit_time, (int, float)) or not math.isfinite(visit_time) or visit_time < 0:
                continue
            if time_limit_minutes is not None:
                if mode == "visit_all" and total_visit_mins + visit_time > time_limit_minutes + 1e-9:
                    continue
                if mode == "fit_time" and visit_time > time_limit_minutes + 1e-9:
                    continue
            new_interests = len(uncovered.intersection(shop["matched_interests"]))
            feasible.append((new_interests, shop["relevance_score"], -(low_price or 0), shop))
        if not feasible:
            break
        # Stable tie-breaker: first item in the earlier deterministic ranking.
        best = max(feasible, key=lambda row: row[:3])[3]
        chosen.append(best)
        candidates.remove(best)
        uncovered.difference_update(best["matched_interests"])
        min_spend += best["min_price_rm"] or 0
        total_visit_mins += best["avg_visit_time_min"]

    base = {
        "floor": manager.floor,
        "method": "preference_matching_plus_exact_shortest_visit_order",
        "interpreted_interests": recommended["interpreted_interests"],
        "start_shop_id": starting_shop["id"],
        "budget_rm": budget_rm,
        "max_stops": max_stops,
        "time_limit_minutes": time_limit_minutes,
        "mapped_matching_shops": recommended["total_matches_before_limit"],
        "reachable_matching_shops": len(valid),
        "candidate_shops": chosen,
        "candidate_minimum_price_total_rm": round(min_spend, 2) if budget_rm is not None else None,
        "budget_warning": (
            "The sum of minimum store price-range values is only an indicative floor, "
            "NOT a predicted basket total or guarantee the journey costs within budget."
        ),
        "selection_notice": (
            "Shop selection is heuristic (interest coverage then relevance); "
            "Stage 7 optimises the walking order of that selection. "
            "This is not joint optimal spending/relevance routing."
        ),
    }
    if not chosen:
        base.update({
            "status": "no_feasible_recommendations",
            "reason": (
                "No matching, mapped and reachable GF shops fit the preliminary "
                "price/visit-time constraints. Map more shops, revise preferences "
                "or increase the budget."
            ),
            "journey": None,
        })
        return base

    journey = optimize_journey(
        graph, manager, starting_shop["id"], [s["shop_id"] for s in chosen],
        mode=mode,
        time_limit_minutes=time_limit_minutes,
        meters_per_pixel=meters_per_pixel,
        walking_speed_m_per_min=walking_speed_m_per_min,
    )
    actually_visited = {shop["shop_id"] for shop in journey["visit_order"]}
    base.update({
        "status": "ok",
        "visit_recommendations": [shop for shop in chosen if shop["shop_id"] in actually_visited],
        "journey": journey,
    })
    if mode == "fit_time":
        base["selection_notice"] += " Time-mode subset selection maximises stop count, not relevance score."
    return base
