r"""MallPilot AI — visual Dijkstra shortest-path tester for the ground floor.

Run from the MallPilot-Backend project root:
    .\.venv\Scripts\python.exe tools\test_dijkstra.py

Requires:
    data/gf_light_map.png
    data/mall_graph_GF.json
    pip install opencv-python networkx

Click start node, then destination node. Green route = shortest path.
R = reset selection; S = export calculated route; Q = quit.
"""

import json
from pathlib import Path

import cv2
import networkx as nx

ROOT = Path(__file__).resolve().parent.parent
IMAGE_FILE = ROOT / "data" / "gf_light_map.png"
GRAPH_FILE = ROOT / "data" / "mall_graph_GF.json"
ROUTE_FILE = ROOT / "data" / "test_route_GF.json"
WINDOW = "MallPilot - Dijkstra Shortest Path"

with GRAPH_FILE.open("r", encoding="utf-8") as file:
    graph_data = json.load(file)

image = cv2.imread(str(IMAGE_FILE))
if image is None:
    raise FileNotFoundError(f"Cannot open map: {IMAGE_FILE}")

image_h, image_w = image.shape[:2]
if (graph_data.get("image_width"), graph_data.get("image_height")) != (image_w, image_h):
    raise ValueError("The floor-plan image does not match the saved graph image dimensions.")

nodes = {node["id"]: node for node in graph_data["nodes"]}
graph = nx.Graph()
for node_id in nodes:
    graph.add_node(node_id)
for edge in graph_data["edges"]:
    a, b = edge["from"], edge["to"]
    if a not in nodes or b not in nodes:
        raise ValueError(f"Edge refers to missing node: {a} -> {b}")
    graph.add_edge(a, b, weight=float(edge["distance_px"]))

if graph.number_of_edges() == 0:
    raise ValueError("No connected edges found. Run connect_edges.py first.")

scale = min(1.0, 1100 / image_w, 750 / image_h)
display_w = round(image_w * scale)
display_h = round(image_h * scale)
background = cv2.resize(image, (display_w, display_h))

start_id = None
destination_id = None
route_ids = []
route_distance_px = None


def xy(node_id):
    node = nodes[node_id]
    return (
        round(node["x"] * display_w / image_w),
        round(node["y"] * display_h / image_h),
    )


def nearest_node(x, y, click_radius=14):
    chosen_id = None
    shortest_squared = click_radius ** 2
    for node_id in nodes:
        px, py = xy(node_id)
        d2 = (x - px) ** 2 + (y - py) ** 2
        if d2 <= shortest_squared:
            shortest_squared = d2
            chosen_id = node_id
    return chosen_id


def on_mouse(event, x, y, flags, userdata):
    global start_id, destination_id, route_ids, route_distance_px
    if event != cv2.EVENT_LBUTTONDOWN:
        return

    clicked_id = nearest_node(x, y)
    if clicked_id is None:
        print("No node near click; try clicking closer to a red dot.")
        return

    # First click selects a start; clicking after an existing result starts a new route.
    if start_id is None or destination_id is not None:
        start_id = clicked_id
        destination_id = None
        route_ids = []
        route_distance_px = None
        print(f"Start: {start_id}. Now click a destination node.")
        return

    if clicked_id == start_id:
        print("Choose a different node as the destination.")
        return

    destination_id = clicked_id
    try:
        route_ids = nx.dijkstra_path(graph, start_id, destination_id, weight="weight")
        route_distance_px = nx.dijkstra_path_length(
            graph, start_id, destination_id, weight="weight"
        )
        print("Shortest route:", " -> ".join(route_ids))
        print(f"Total graph distance: {route_distance_px:.2f} image pixels")
    except nx.NetworkXNoPath:
        route_ids = []
        route_distance_px = None
        print(f"NO PATH from {start_id} to {destination_id}.")
        print("Check whether all relevant junctions are connected by edges.")


def render():
    canvas = background.copy()

    # Existing walkable connections, shown faintly.
    for a, b in graph.edges:
        cv2.line(canvas, xy(a), xy(b), (170, 170, 170), 1, cv2.LINE_AA)

    # Result path from Dijkstra, shown in green.
    for a, b in zip(route_ids, route_ids[1:]):
        cv2.line(canvas, xy(a), xy(b), (0, 180, 0), 4, cv2.LINE_AA)

    # Dots only — no GF_N001 labels.
    for node_id in nodes:
        cv2.circle(canvas, xy(node_id), 3, (0, 0, 255), -1)

    if start_id is not None:
        cv2.circle(canvas, xy(start_id), 7, (255, 0, 0), -1)  # blue start
    if destination_id is not None:
        cv2.circle(canvas, xy(destination_id), 7, (0, 255, 255), -1)  # yellow end

    return canvas


def export_route():
    if not route_ids:
        print("No route to save. Click a start node and a connected destination first.")
        return
    output = {
        "floor": graph_data.get("floor", "GF"),
        "image_width": image_w,
        "image_height": image_h,
        "start_node": start_id,
        "destination_node": destination_id,
        "distance_px": round(route_distance_px, 2),
        "path": [
            {
                "node_id": node_id,
                "floor": nodes[node_id].get("floor", "GF"),
                "x": nodes[node_id]["x"],
                "y": nodes[node_id]["y"],
            }
            for node_id in route_ids
        ],
    }
    with ROUTE_FILE.open("w", encoding="utf-8") as file:
        json.dump(output, file, indent=2)
    print(f"Route saved to {ROUTE_FILE}")


print(f"Loaded {graph.number_of_nodes()} nodes, {graph.number_of_edges()} edges.")
print("Click starting red dot, then destination red dot.")
print("Blue = start, yellow = destination, green = Dijkstra route.")
print("R = reset | S = save result as JSON | Q = quit")

cv2.namedWindow(WINDOW, cv2.WINDOW_AUTOSIZE)
cv2.setMouseCallback(WINDOW, on_mouse)

while True:
    cv2.imshow(WINDOW, render())
    key = cv2.waitKey(20) & 0xFF

    if key == ord("r"):
        start_id = None
        destination_id = None
        route_ids = []
        route_distance_px = None
        print("Route selection reset.")
    elif key == ord("s"):
        export_route()
    elif key == ord("q"):
        break

    if cv2.getWindowProperty(WINDOW, cv2.WND_PROP_VISIBLE) < 1:
        break

cv2.destroyAllWindows()
