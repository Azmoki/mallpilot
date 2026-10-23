"""Temporary GF corridor closures, stored *separately* from mall_graph_GF.json.

- Edges are UNDIRECTED and identified by their two original graph node IDs.
- The closure file survives a development-server restart until explicitly reopened.
- Graph and shops source files are never modified by this module.
- JSON writes are atomic; process-local lock supports Uvicorn single-worker dev mode.
- If a graph edge is edited/deleted later, stale closures are reported but not
  applied to unrelated graph edges.
"""

from __future__ import annotations

import json
import os
import threading
from datetime import datetime, timezone
from pathlib import Path


def edge_key(a: str, b: str) -> tuple[str, str]:
    """Canonical identifier for an undirected graph edge."""
    if not isinstance(a, str) or not isinstance(b, str) or not a.strip() or not b.strip():
        raise ValueError("Both node IDs must be non-empty strings")
    a, b = a.strip(), b.strip()
    if a == b:
        raise ValueError("A corridor edge cannot connect a node to itself")
    return tuple(sorted((a, b)))


def graph_edge_keys(graph_data: dict) -> set[tuple[str, str]]:
    return {edge_key(e["from"], e["to"]) for e in graph_data["edges"]}


class CorridorClosureStore:
    def __init__(self, filename: Path, floor: str = "GF"):
        self.filename = Path(filename)
        self.floor = floor
        self._lock = threading.RLock()

    def _load(self) -> list[dict]:
        if not self.filename.exists():
            return []
        with self.filename.open("r", encoding="utf-8") as f:
            document = json.load(f)
        if not isinstance(document, dict) or document.get("floor") != self.floor:
            raise ValueError(f"Closure file must contain floor={self.floor!r}")
        entries = document.get("closures")
        if not isinstance(entries, list):
            raise ValueError("Closure file must contain a 'closures' list")
        seen = set()
        result = []
        for e in entries:
            if not isinstance(e, dict):
                raise ValueError("Each closure must be an object")
            pair = edge_key(e.get("from_node_id"), e.get("to_node_id"))
            if pair in seen:
                raise ValueError(f"Duplicate corridor closure: {pair}")
            seen.add(pair)
            result.append({
                "from_node_id": pair[0],
                "to_node_id": pair[1],
                "reason": str(e.get("reason") or "Temporary closure"),
                "closed_at_utc": str(e.get("closed_at_utc") or ""),
            })
        return result

    def _save(self, entries: list[dict]) -> None:
        self.filename.parent.mkdir(parents=True, exist_ok=True)
        temp_file = self.filename.with_name(self.filename.name + ".tmp")
        try:
            with temp_file.open("w", encoding="utf-8") as f:
                json.dump({"floor": self.floor, "closures": entries}, f,
                          ensure_ascii=False, indent=2)
                f.write("\n")
            os.replace(temp_file, self.filename)
        finally:
            if temp_file.exists():
                temp_file.unlink()

    def status(self, graph_data: dict) -> dict:
        with self._lock:
            entries = self._load()
        existing = graph_edge_keys(graph_data)
        annotated = []
        for e in entries:
            pair = edge_key(e["from_node_id"], e["to_node_id"])
            annotated.append({**e, "exists_in_graph": pair in existing})
        return {
            "floor": self.floor,
            "active_count": sum(e["exists_in_graph"] for e in annotated),
            "stale_count": sum(not e["exists_in_graph"] for e in annotated),
            "closures": annotated,
            "note": "Stale closures refer to graph edges since removed and are ignored by routing.",
        }

    def active_pairs(self, graph_data: dict) -> set[tuple[str, str]]:
        with self._lock:
            recorded = {
                edge_key(e["from_node_id"], e["to_node_id"])
                for e in self._load()
            }
        return recorded & graph_edge_keys(graph_data)

    def close(self, graph_data: dict, a: str, b: str, reason: str = "Temporary closure") -> dict:
        pair = edge_key(a, b)
        if pair not in graph_edge_keys(graph_data):
            raise ValueError(f"No existing corridor edge connects {pair[0]} and {pair[1]}")
        with self._lock:
            entries = self._load()
            matching = next((e for e in entries
                             if edge_key(e["from_node_id"], e["to_node_id"]) == pair), None)
            if matching is not None:
                return {"status": "already_closed", "closure": matching}
            entry = {
                "from_node_id": pair[0],
                "to_node_id": pair[1],
                "reason": reason.strip() or "Temporary closure",
                "closed_at_utc": datetime.now(timezone.utc).isoformat(),
            }
            entries.append(entry)
            self._save(entries)
            return {"status": "closed", "closure": entry}

    def reopen(self, a: str, b: str) -> dict:
        pair = edge_key(a, b)
        with self._lock:
            entries = self._load()
            kept = [e for e in entries
                    if edge_key(e["from_node_id"], e["to_node_id"]) != pair]
            if len(kept) == len(entries):
                return {"status": "already_open", "from_node_id": pair[0], "to_node_id": pair[1]}
            self._save(kept)
            return {"status": "reopened", "from_node_id": pair[0], "to_node_id": pair[1]}

    def reset(self) -> int:
        with self._lock:
            count = len(self._load())
            self._save([])
            return count


def graph_without_edges(graph_data: dict, blocked_pairs: set[tuple[str, str]]) -> dict:
    """Return a filtered graph view WITHOUT altering the source graph or edges."""
    return {
        **graph_data,
        "edges": [edge for edge in graph_data["edges"]
                  if edge_key(edge["from"], edge["to"]) not in blocked_pairs],
    }


def route_from_node(graph_data: dict, manager, current_node_id: str,
                    destination_shop_id: str) -> dict:
    """Recalculate a path from user's current *graph node*, not a past shop."""
    import networkx as nx
    from Backend.modules.journey_optimizer1 import _build_network

    network = _build_network(graph_data, manager.floor)
    if current_node_id not in network:
        raise ValueError(f"Current graph node does not exist: {current_node_id}")
    destination = manager.get(destination_shop_id)
    dest_id = destination.get("node_id")
    if not dest_id:
        raise ValueError(f"Shop not mapped to an entrance yet: {destination['name']}")
    if dest_id not in network or network.nodes[dest_id].get("type") != "store_entrance":
        raise ValueError(f"Invalid mapped store entrance: {dest_id}")
    try:
        path = nx.dijkstra_path(network, current_node_id, dest_id, weight="weight")
        length = nx.dijkstra_path_length(network, current_node_id, dest_id, weight="weight")
    except nx.NetworkXNoPath as exc:
        raise ValueError(f"No walkable path from {current_node_id} to {destination['name']}") from exc
    return {
        "floor": manager.floor,
        "image_width": graph_data["image_width"],
        "image_height": graph_data["image_height"],
        "current_node_id": current_node_id,
        "destination": {
            "shop_id": destination["id"],
            "lot_id": destination["lot_id"],
            "name": destination["name"],
            "node_id": dest_id,
        },
        "distance_px": round(length, 2),
        "path": [
            {"node_id": nid, "x": network.nodes[nid]["x"],
             "y": network.nodes[nid]["y"], "floor": manager.floor}
            for nid in path
        ],
        "note": "Current position must be snapped to an existing graph node by the client; distance is image pixels.",
    }
