
import json
import networkx as nx
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GRAPH_FILE = ROOT / "data" / "mall_graph_GF.json"

with open(GRAPH_FILE, "r", encoding="utf-8") as f:
    data = json.load(f)

graph = nx.Graph()

# Load nodes
for node in data["nodes"]:
    graph.add_node(node["id"], **node)

# Load edges
for edge in data["edges"]:
    graph.add_edge(
        edge["from"],
        edge["to"],
        weight=edge["distance_px"]
    )

print("=== Mall Graph Validation ===")
print("Total nodes:", graph.number_of_nodes())
print("Total edges:", graph.number_of_edges())

# Find isolated nodes
isolated = list(nx.isolates(graph))

print("\nIsolated nodes:", len(isolated))

for node_id in isolated:
    print(" -", node_id)

# Check whether all nodes are connected
components = list(nx.connected_components(graph))

print("\nConnected components:", len(components))

# Check store entrances
store_nodes = [
    node_id
    for node_id, attributes in graph.nodes(data=True)
    if attributes.get("type") == "store_entrance"
]

print("\nStore entrance nodes:", len(store_nodes))

disconnected_stores = [
    node_id
    for node_id in store_nodes
    if graph.degree(node_id) == 0
]

print("Store entrances without edges:", len(disconnected_stores))

for node_id in disconnected_stores:
    print(" -", node_id)
