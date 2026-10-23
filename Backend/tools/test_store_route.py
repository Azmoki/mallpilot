"""Run Dijkstra between shops using shops.json plus store_node_map_GF.json.

Examples, from MallPilot-Backend root:
  .\\.venv\\Scripts\\python.exe tools\\test_store_route.py --floor GF --start G13 --end G15
  .\\.venv\\Scripts\\python.exe tools\\test_store_route.py --floor GF --start shop_012 --end shop_014

The route output uses original floor-plan pixel coordinates (NOT metres).
"""
import argparse
import json
import math
import sys
from pathlib import Path

import networkx as nx

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from modules.store_manager import StoreDataManager


def calculate_route(graph_data, manager, start_identifier, end_identifier):
    floor = manager.floor
    if graph_data.get("floor") != floor:
        raise ValueError(f"Graph is {graph_data.get('floor')!r} but stores are {floor!r}")
    start = manager.get(start_identifier)
    dest = manager.get(end_identifier)
    if not start.get("node_id") or not dest.get("node_id"):
        missing = [s["name"] for s in (start, dest) if not s.get("node_id")]
        raise ValueError("Shop(s) not mapped to an entrance yet: " + ", ".join(missing) +
                         ". Run tools/map_stores.py first.")

    nodes = graph_data.get("nodes", [])
    network = nx.Graph()
    for node in nodes:
        if node.get("floor", floor) != floor:
            raise ValueError(f"Node {node['id']} belongs to a different floor")
        network.add_node(node["id"], **node)
    for edge in graph_data.get("edges", []):
        distance = float(edge["distance_px"])
        if not math.isfinite(distance) or distance <= 0:
            raise ValueError(f"Invalid distance_px on edge: {edge}")
        a, b = edge["from"], edge["to"]
        if a not in network or b not in network:
            raise ValueError(f"Edge references a nonexistent node: {edge}")
        # If there are parallel edges, keep the smallest distance for the pair.
        if network.has_edge(a, b):
            distance = min(distance, network[a][b]["weight"])
        network.add_edge(a, b, weight=distance)

    a, b = start["node_id"], dest["node_id"]
    if a not in network or b not in network:
        raise ValueError("Mapped entrance node is missing from the mall graph")
    for name, nid in [(start["name"], a), (dest["name"], b)]:
        if network.nodes[nid].get("type") != "store_entrance":
            raise ValueError(f"{name} maps to {nid}, which is not a store_entrance")
    try:
        path_ids = nx.dijkstra_path(network, a, b, weight="weight")
        distance_px = nx.dijkstra_path_length(network, a, b, weight="weight")
    except nx.NetworkXNoPath as exc:
        raise ValueError(f"No walkable path from {start['name']} to {dest['name']}") from exc

    def shop_info(s):
        return {"shop_id": s["id"], "lot_id": s["lot_id"],
                "name": s["name"], "node_id": s["node_id"]}

    return {
        "floor": floor,
        "image_width": graph_data["image_width"],
        "image_height": graph_data["image_height"],
        "start": shop_info(start),
        "destination": shop_info(dest),
        "distance_px": round(distance_px, 2),
        "path": [
            {"node_id": nid, "x": network.nodes[nid]["x"],
             "y": network.nodes[nid]["y"], "floor": floor}
            for nid in path_ids
        ],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--floor", choices=("GF", "1F"), default="GF")
    parser.add_argument("--start", required=True, help="shop_012, G13, or PUMA")
    parser.add_argument("--end", required=True, help="shop_014, G15, or SKECHERS")
    parser.add_argument("--graph", type=Path)
    parser.add_argument("--shops", type=Path)
    parser.add_argument("--mapping", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    graph_file = args.graph or ROOT / "data" / f"mall_graph_{args.floor}.json"
    shops_file = args.shops or ROOT / "data" / "shops.json"
    mapping_file = args.mapping or ROOT / "data" / f"store_node_map_{args.floor}.json"
    outfile = args.output or ROOT / "data" / f"test_store_route_{args.floor}.json"
    manager = StoreDataManager(shops_file, mapping_file, args.floor)
    with graph_file.open("r", encoding="utf-8") as handle:
        graph = json.load(handle)
    result = calculate_route(graph, manager, args.start, args.end)
    outfile.parent.mkdir(parents=True, exist_ok=True)
    with outfile.open("w", encoding="utf-8") as handle:
        json.dump(result, handle, indent=2, ensure_ascii=False)
    print(f"\n{result['start']['name']} -> {result['destination']['name']}")
    print("Path:", " -> ".join(p["node_id"] for p in result["path"]))
    print(f"Distance: {result['distance_px']} image pixels (not metres)")
    print("Route saved:", outfile)


if __name__ == "__main__":
    try:
        main()
    except (KeyError, ValueError, FileNotFoundError, nx.NetworkXError) as exc:
        raise SystemExit(f"ERROR: {exc}") from exc
