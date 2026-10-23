"""MallPilot AI: editable floor-plan graph node editor.

Run from the MallPilot-Backend root:
    .\\.venv\\Scripts\\python.exe tools\\pick_points.py

Uses:
    data/gf_light_map.png
    data/mall_graph_GF.json

Keys:
    1..6  choose node type
    A     add mode (click empty area)
    M     move mode (click node, then click new position)
    D     delete mode (click node, then press X to confirm)
    T     change type mode (choose type 1..6, then click node)
    I     insert/split mode (click directly on existing edge)
    U     undo most recent edit (this session)
    Esc   cancel pending selection
    S     save
    Q     save and quit

Note: Image coordinates and distance_px use image pixels, not metres.
"""

import copy
import json
import math
import re
import shutil
from datetime import datetime
from pathlib import Path

import cv2

ROOT = Path(__file__).resolve().parent.parent
IMAGE_FILE = ROOT / "data" / "gf_light_map.png"
GRAPH_FILE = ROOT / "data" / "mall_graph_GF.json"
FLOOR = "GF"
WINDOW = "MallPilot - Node Editor"

NODE_TYPES = {
    ord("1"): "junction",
    ord("2"): "store_entrance",
    ord("3"): "lift",
    ord("4"): "escalator",
    ord("5"): "mall_entrance",
    ord("6"): "stairs",
}


def pixel_distance(a, b):
    return round(math.hypot(b["x"] - a["x"], b["y"] - a["y"]), 2)


class MallNodeEditor:
    def __init__(self, image_file=IMAGE_FILE, graph_file=GRAPH_FILE, floor=FLOOR):
        self.image_file = Path(image_file)
        self.graph_file = Path(graph_file)
        self.floor = floor
        self.image = cv2.imread(str(self.image_file))
        if self.image is None:
            raise FileNotFoundError(f"Could not read floor image: {self.image_file}")

        self.image_h, self.image_w = self.image.shape[:2]
        if self.graph_file.exists():
            with self.graph_file.open("r", encoding="utf-8") as f:
                self.data = json.load(f)
            actual = (self.data.get("image_width"), self.data.get("image_height"))
            expected = (self.image_w, self.image_h)
            if actual != expected:
                raise ValueError(
                    f"Map size mismatch: JSON={actual}, image={expected}. "
                    "Use exactly the same original map image."
                )
            print(f"Loaded existing graph: {self.graph_file}")
        else:
            self.data = {
                "floor": self.floor,
                "image_width": self.image_w,
                "image_height": self.image_h,
                "nodes": [],
                "edges": [],
            }
            print("Graph JSON not found. Starting a new floor graph.")

        self.nodes = self.data.setdefault("nodes", [])
        self.edges = self.data.setdefault("edges", [])

        node_ids = [n["id"] for n in self.nodes]
        if len(set(node_ids)) != len(node_ids):
            raise ValueError("Duplicate node IDs found in graph JSON")
        self.nodes_by_id = {n["id"]: n for n in self.nodes}
        for edge in self.edges:
            if edge["from"] not in self.nodes_by_id or edge["to"] not in self.nodes_by_id:
                raise ValueError(f"Edge references a missing node: {edge}")

        used_numbers = []
        for node_id in node_ids:
            match = re.fullmatch(rf"{re.escape(self.floor)}_N(\d+)", node_id)
            if match:
                used_numbers.append(int(match.group(1)))
        self.data["next_node_number"] = max(
            int(self.data.get("next_node_number", 1)),
            max(used_numbers, default=0) + 1,
        )

        scale = min(1.0, 1100 / self.image_w, 750 / self.image_h)
        self.display_w = max(1, round(self.image_w * scale))
        self.display_h = max(1, round(self.image_h * scale))
        self.background = cv2.resize(self.image, (self.display_w, self.display_h))

        self.mode = "add"
        self.node_type = "junction"
        self.selected_id = None
        self.history = []
        self.has_backed_up = False

    def record_undo(self):
        self.history.append((copy.deepcopy(self.nodes), copy.deepcopy(self.edges)))
        if len(self.history) > 50:
            self.history.pop(0)

    def rebuild_index(self):
        self.nodes_by_id = {n["id"]: n for n in self.nodes}

    def original_xy(self, display_x, display_y):
        return (
            max(0, min(self.image_w - 1, round(display_x * self.image_w / self.display_w))),
            max(0, min(self.image_h - 1, round(display_y * self.image_h / self.display_h))),
        )

    def display_xy(self, node):
        return (
            round(node["x"] * self.display_w / self.image_w),
            round(node["y"] * self.display_h / self.image_h),
        )

    def nearest_node(self, x, y, radius=12, exclude_id=None):
        closest = None
        best_d2 = radius ** 2
        for node in self.nodes:
            if node["id"] == exclude_id:
                continue
            px, py = self.display_xy(node)
            d2 = (x - px) ** 2 + (y - py) ** 2
            if d2 <= best_d2:
                best_d2, closest = d2, node
        return closest

    def add_node(self, x, y, node_type=None):
        self.record_undo()
        number = self.data["next_node_number"]
        self.data["next_node_number"] = number + 1
        node = {
            "id": f"{self.floor}_N{number:03d}",
            "type": node_type or self.node_type,
            "floor": self.floor,
            "x": int(x),
            "y": int(y),
        }
        self.nodes.append(node)
        self.nodes_by_id[node["id"]] = node
        print(f"Added {node['id']} ({node['type']}) at ({x}, {y})")
        return node

    def move_node(self, node_id, x, y):
        node = self.nodes_by_id[node_id]
        if node["x"] == x and node["y"] == y:
            return
        self.record_undo()
        node["x"], node["y"] = int(x), int(y)
        connected = 0
        needs_review = False
        for edge in self.edges:
            if node_id in (edge["from"], edge["to"]):
                a = self.nodes_by_id[edge["from"]]
                b = self.nodes_by_id[edge["to"]]
                edge["distance_px"] = pixel_distance(a, b)
                connected += 1
                if any(k in edge for k in ("distance_m", "travel_time_s", "weight")):
                    needs_review = True
        print(f"Moved {node_id} to ({x}, {y}); updated {connected} pixel distances")
        if needs_review:
            print("WARNING: Review calibrated metre/time/weight fields after moving this node.")

    def delete_node(self, node_id):
        connected = sum(node_id in (e["from"], e["to"]) for e in self.edges)
        self.record_undo()
        self.nodes[:] = [n for n in self.nodes if n["id"] != node_id]
        self.edges[:] = [e for e in self.edges if node_id not in (e["from"], e["to"])]
        self.rebuild_index()
        print(f"Deleted {node_id} and {connected} connected edge(s). Reconnect neighbours if needed.")

    def change_type(self, node_id, new_type):
        node = self.nodes_by_id[node_id]
        if node.get("type") == new_type:
            return
        self.record_undo()
        old = node.get("type")
        node["type"] = new_type
        print(f"Updated {node_id}: {old} -> {new_type}")

    def nearest_edge(self, x, y, tolerance=11):
        closest = None
        best = tolerance ** 2
        for index, edge in enumerate(self.edges):
            a = self.nodes_by_id[edge["from"]]
            b = self.nodes_by_id[edge["to"]]
            ax, ay = self.display_xy(a)
            bx, by = self.display_xy(b)
            dx, dy = bx - ax, by - ay
            squared_length = dx * dx + dy * dy
            if squared_length == 0:
                continue
            t = max(0.0, min(1.0, ((x - ax) * dx + (y - ay) * dy) / squared_length))
            proj_x, proj_y = ax + t * dx, ay + t * dy
            d2 = (x - proj_x) ** 2 + (y - proj_y) ** 2
            if d2 < best:
                best = d2
                closest = (index, t, math.sqrt(squared_length))
        return closest

    def split_edge(self, index, t):
        old = self.edges[index]
        a = self.nodes_by_id[old["from"]]
        b = self.nodes_by_id[old["to"]]
        x = round(a["x"] + t * (b["x"] - a["x"]))
        y = round(a["y"] + t * (b["y"] - a["y"]))
        if (x, y) in ((a["x"], a["y"]), (b["x"], b["y"])):
            print("Too close to an endpoint; select the existing junction instead.")
            return

        # One undo step should revert both the new node and both new edges.
        self.record_undo()
        number = self.data["next_node_number"]
        self.data["next_node_number"] = number + 1
        new_node = {
            "id": f"{self.floor}_N{number:03d}",
            "type": "junction",
            "floor": self.floor,
            "x": x,
            "y": y,
        }
        self.nodes.append(new_node)
        self.nodes_by_id[new_node["id"]] = new_node

        # Preserve additional edge properties, splitting additive measurements.
        a_edge = copy.deepcopy(old)
        b_edge = copy.deepcopy(old)
        a_edge["from"], a_edge["to"] = old["from"], new_node["id"]
        b_edge["from"], b_edge["to"] = new_node["id"], old["to"]
        for key in ("distance_px", "distance_m", "travel_time_s", "travel_time_minutes", "weight"):
            if isinstance(old.get(key), (int, float)) and not isinstance(old.get(key), bool):
                total = float(old[key])
                first = round(total * t, 4)
                a_edge[key] = first
                b_edge[key] = round(total - first, 4)
        if "distance_px" not in old:
            a_edge["distance_px"] = pixel_distance(a, new_node)
            b_edge["distance_px"] = pixel_distance(new_node, b)

        self.edges[index:index + 1] = [a_edge, b_edge]
        print(
            f"Split {old['from']} <-> {old['to']} at {new_node['id']}. "
            "Original edge replaced with two edges."
        )

    def undo(self):
        if not self.history:
            print("Nothing to undo in this session.")
            return
        old_nodes, old_edges = self.history.pop()
        self.nodes[:] = old_nodes
        self.edges[:] = old_edges
        self.rebuild_index()
        self.selected_id = None
        print("Undid previous edit.")

    def save(self):
        self.graph_file.parent.mkdir(parents=True, exist_ok=True)
        if self.graph_file.exists() and not self.has_backed_up:
            stamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
            backup = self.graph_file.with_name(f"{self.graph_file.stem}.backup_{stamp}.json")
            shutil.copy2(self.graph_file, backup)
            self.has_backed_up = True
            print(f"Backup created: {backup}")
        tmp_file = self.graph_file.with_name(self.graph_file.name + ".tmp")
        with tmp_file.open("w", encoding="utf-8") as f:
            json.dump(self.data, f, ensure_ascii=False, indent=2)
        tmp_file.replace(self.graph_file)
        print(f"Saved {len(self.nodes)} nodes, {len(self.edges)} edges: {self.graph_file}")

    def on_mouse(self, event, x, y, flags, userdata):
        if event != cv2.EVENT_LBUTTONDOWN:
            return
        closest = self.nearest_node(x, y)
        if self.mode == "add":
            if closest:
                print(f"Near existing {closest['id']}; choose another position or M to move it.")
            else:
                self.add_node(*self.original_xy(x, y))
        elif self.mode == "move":
            if self.selected_id is None:
                if closest:
                    self.selected_id = closest["id"]
                    print(f"Moving {self.selected_id}: click new position.")
                else:
                    print("Click an existing red dot to select a node.")
            else:
                if closest and closest["id"] != self.selected_id:
                    print("Target overlaps another node; choose a different position.")
                    return
                self.move_node(self.selected_id, *self.original_xy(x, y))
                self.selected_id = None
        elif self.mode == "delete":
            if closest:
                self.selected_id = closest["id"]
                connected = sum(self.selected_id in (e["from"], e["to"]) for e in self.edges)
                print(f"Selected {self.selected_id} for deletion ({connected} connected edges). Press X to confirm.")
            else:
                print("Click an existing dot, then press X to confirm deletion.")
        elif self.mode == "type":
            if closest:
                self.change_type(closest["id"], self.node_type)
            else:
                print("Click an existing dot to change its type.")
        elif self.mode == "insert":
            result = self.nearest_edge(x, y)
            if result is None:
                print("Click directly on an existing green edge to insert a junction.")
            else:
                index, t, length = result
                if min(t, 1 - t) * length < 12:
                    print("Too close to an edge endpoint. Click farther along the corridor.")
                else:
                    self.split_edge(index, t)

    def draw(self):
        canvas = self.background.copy()
        # Subtle edge display (helps identify existing links without clutter).
        for edge in self.edges:
            a = self.nodes_by_id[edge["from"]]
            b = self.nodes_by_id[edge["to"]]
            cv2.line(canvas, self.display_xy(a), self.display_xy(b), (0, 155, 0), 1, cv2.LINE_AA)
        for node in self.nodes:
            x, y = self.display_xy(node)
            is_selected = node["id"] == self.selected_id
            cv2.circle(
                canvas, (x, y), 6 if is_selected else 3,
                (0, 255, 255) if is_selected else (0, 0, 255),
                -1, cv2.LINE_AA,
            )
        return canvas

    def run(self):
        print("\nMallPilot Node Editor — existing graph is preserved")
        print("1:Junction  2:Store  3:Lift  4:Escalator  5:Entrance  6:Stairs")
        print("A:Add  M:Move  D:Delete (press X to confirm)  T:Type  I:Split edge")
        print("U:Undo  Esc:Cancel  S:Save  Q:Save+Quit")
        print(f"Loaded {len(self.nodes)} nodes and {len(self.edges)} edges. Mode: ADD, Type: Junction\n")
        cv2.namedWindow(WINDOW, cv2.WINDOW_AUTOSIZE)
        cv2.setMouseCallback(WINDOW, self.on_mouse)
        try:
            while True:
                cv2.imshow(WINDOW, self.draw())
                key = cv2.waitKey(20) & 0xFF
                if key in NODE_TYPES:
                    self.node_type = NODE_TYPES[key]
                    print(f"Selected node type: {self.node_type}")
                elif key in (ord("a"), ord("m"), ord("d"), ord("t"), ord("i")):
                    self.mode = {
                        ord("a"): "add", ord("m"): "move", ord("d"): "delete",
                        ord("t"): "type", ord("i"): "insert",
                    }[key]
                    self.selected_id = None
                    print(f"Mode: {self.mode.upper()}")
                elif key == ord("x") and self.mode == "delete" and self.selected_id:
                    self.delete_node(self.selected_id)
                    self.selected_id = None
                elif key == ord("u"):
                    self.undo()
                elif key == 27:
                    self.selected_id = None
                    print("Selection cancelled.")
                elif key == ord("s"):
                    self.save()
                elif key == ord("q"):
                    self.save()
                    break
                try:
                    if cv2.getWindowProperty(WINDOW, cv2.WND_PROP_VISIBLE) < 1:
                        self.save()
                        break
                except cv2.error:
                    self.save()
                    break
        finally:
            cv2.destroyAllWindows()


if __name__ == "__main__":
    MallNodeEditor().run()
