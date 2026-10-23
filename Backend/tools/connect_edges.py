r"""MallPilot AI — graphical editor for the connections in a floor-plan graph.

Run from the MallPilot-Backend project root:
    .\.venv\Scripts\python.exe tools\connect_edges.py

Files:
    data/gf_light_map.png
    data/mall_graph_GF.json

C: connect two nodes (default)
D: select an edge by clicking its line; X: confirm deletion
E: select an edge by clicking its line; click two nodes to replace it
F: find a node by typing its ID in the map window, then press Enter
U: undo last change in this session
Esc: cancel selection
S: save; Q: save and quit

This editor draws dots and lines WITHOUT node-ID labels, except for a searched node.
"""

import copy
import json
import math
import os
import shutil
from datetime import datetime
from pathlib import Path

import cv2

ROOT = Path(__file__).resolve().parent.parent
IMAGE_FILE = ROOT / "data" / "gf_light_map.png"
GRAPH_FILE = ROOT / "data" / "mall_graph_GF.json"
WINDOW_NAME = "MallPilot - Edit Connections"

# Display colours are in OpenCV's BGR format.
NODE_RED = (0, 0, 255)
SELECTED_YELLOW = (0, 255, 255)
EDGE_GREEN = (0, 180, 0)
FOUND_CYAN = (255, 255, 0)  # BGR, used only for searched nodes


class EdgeEditor:
    def __init__(self):
        if not GRAPH_FILE.exists():
            raise FileNotFoundError(
                f"Missing {GRAPH_FILE}. Run pick_points.py first."
            )

        with GRAPH_FILE.open("r", encoding="utf-8") as f:
            self.graph_data = json.load(f)

        self.image = cv2.imread(str(IMAGE_FILE))
        if self.image is None:
            raise FileNotFoundError(f"Cannot open floor-plan image: {IMAGE_FILE}")

        self.image_h, self.image_w = self.image.shape[:2]
        saved_dimensions = (
            self.graph_data.get("image_width"),
            self.graph_data.get("image_height"),
        )
        if saved_dimensions != (self.image_w, self.image_h):
            raise ValueError(
                "Image dimensions do not match mall_graph_GF.json. "
                "Use the same original floor-plan image."
            )

        raw_nodes = self.graph_data.get("nodes", [])
        self.nodes = {node["id"]: node for node in raw_nodes}
        if not self.nodes:
            raise ValueError("No nodes found. Mark nodes using pick_points.py first.")
        if len(self.nodes) != len(raw_nodes):
            raise ValueError("Duplicate node IDs found. Fix these before editing edges.")

        self.edges = self.graph_data.setdefault("edges", [])
        for edge in self.edges:
            if edge["from"] not in self.nodes or edge["to"] not in self.nodes:
                raise ValueError(f"Edge refers to a missing node: {edge}")

        scale = min(1.0, 1100 / self.image_w, 750 / self.image_h)
        self.display_w = max(1, round(self.image_w * scale))
        self.display_h = max(1, round(self.image_h * scale))
        self.background = cv2.resize(
            self.image, (self.display_w, self.display_h)
        )

        self.mode = "connect"  # connect, delete, edit
        self.first_node_id = None
        self.selected_edge_index = None
        self.history = []
        self.dirty = False
        self.backup_created = False
        self.search_active = False
        self.search_text = ""
        self.found_node_id = None

    def display_xy(self, node):
        return (
            round(node["x"] * self.display_w / self.image_w),
            round(node["y"] * self.display_h / self.image_h),
        )

    def nearest_node(self, x, y, radius=13):
        closest_id = None
        closest_dist_sq = radius ** 2
        for node_id, node in self.nodes.items():
            nx, ny = self.display_xy(node)
            distance_sq = (x - nx) ** 2 + (y - ny) ** 2
            if distance_sq <= closest_dist_sq:
                closest_id = node_id
                closest_dist_sq = distance_sq
        return closest_id

    @staticmethod
    def distance_to_segment(px, py, ax, ay, bx, by):
        vx, vy = bx - ax, by - ay
        length_sq = vx * vx + vy * vy
        if length_sq == 0:
            return math.hypot(px - ax, py - ay)
        t = max(0, min(1, ((px - ax) * vx + (py - ay) * vy) / length_sq))
        return math.hypot(px - (ax + t * vx), py - (ay + t * vy))

    def nearest_edge(self, x, y, radius=8):
        closest_index = None
        closest_distance = radius
        for index, edge in enumerate(self.edges):
            ax, ay = self.display_xy(self.nodes[edge["from"]])
            bx, by = self.display_xy(self.nodes[edge["to"]])
            distance = self.distance_to_segment(x, y, ax, ay, bx, by)
            if distance <= closest_distance:
                closest_index, closest_distance = index, distance
        return closest_index

    def connection_exists(self, a, b, ignore_index=None):
        return any(
            index != ignore_index and {edge["from"], edge["to"]} == {a, b}
            for index, edge in enumerate(self.edges)
        )

    def make_edge(self, first_id, second_id):
        a, b = self.nodes[first_id], self.nodes[second_id]
        distance = math.hypot(b["x"] - a["x"], b["y"] - a["y"])
        if distance == 0:
            raise ValueError("These nodes have the same coordinates.")
        return {
            "from": first_id,
            "to": second_id,
            "distance_px": round(distance, 2),
        }

    def remember_change(self):
        # A full snapshot is simple and safe for a small hackathon graph.
        self.history.append(copy.deepcopy(self.edges))
        self.dirty = True

    def cancel_selection(self):
        self.first_node_id = None
        self.selected_edge_index = None

    def set_mode(self, mode):
        self.mode = mode
        self.cancel_selection()
        if mode == "connect":
            print("CONNECT mode: click two nodes to add a green edge.")
        elif mode == "delete":
            print("DELETE mode: click an existing green line, then press X.")
        elif mode == "edit":
            print("EDIT mode: click a green line, then click TWO new endpoint nodes.")

    def begin_find(self):
        """Type node ID into the OpenCV window, not the terminal."""
        self.cancel_selection()
        self.search_active = True
        self.search_text = ""
        print("FIND: Type a node ID in the map window (e.g., GF_N051), then Enter.")
        print("Backspace = erase; Esc = cancel search.")

    def find_node(self, query):
        """Highlight the matching node and report whether it has any edges."""
        query = query.strip().upper()
        match = next((node_id for node_id in self.nodes if node_id.upper() == query), None)
        if match is None:
            self.found_node_id = None
            print(f"Node '{query}' not found. Check the ID in mall_graph_GF.json.")
            return

        self.found_node_id = match
        node = self.nodes[match]
        incident_edges = [
            edge for edge in self.edges if match in (edge["from"], edge["to"])
        ]
        print(f"\nFOUND: {match}")
        print(f"  Type: {node.get('type', 'unknown')}")
        print(f"  Floor: {node.get('floor', '?')}")
        print(f"  Original image coordinates: ({node['x']}, {node['y']})")
        print(f"  Connected edges: {len(incident_edges)}")
        if not incident_edges:
            print("  STATUS: ISOLATED — this node currently has no edges.")
        else:
            for edge in incident_edges:
                neighbor = edge["to"] if edge["from"] == match else edge["from"]
                length = edge.get("distance_px", "unknown")
                print(f"  -> {neighbor} ({length} image px)")
        print("  The cyan ring on the map marks this node. Press Esc to clear.\n")

    def handle_search_key(self, key):
        """Capture search text while focus remains in the map window."""
        if key in (13, 10):  # Enter
            self.search_active = False
            if self.search_text.strip():
                self.find_node(self.search_text)
            else:
                print("Empty ID; search cancelled.")
            self.search_text = ""
        elif key == 27:  # Esc
            self.search_active = False
            self.search_text = ""
            print("Search cancelled.")
        elif key in (8, 127):  # Backspace or Delete
            self.search_text = self.search_text[:-1]
        elif 32 <= key <= 126 and len(self.search_text) < 40:
            self.search_text += chr(key)

    def click_node_for_connection(self, node_id):
        if self.first_node_id is None:
            self.first_node_id = node_id
            print(f"First node: {node_id}. Click the second node.")
            return

        first_id = self.first_node_id
        self.first_node_id = None
        if first_id == node_id:
            print("Cancelled: you selected the same node twice.")
            return
        if self.connection_exists(first_id, node_id):
            print(f"Already connected: {first_id} <-> {node_id}")
            return
        try:
            new_edge = self.make_edge(first_id, node_id)
        except ValueError as exc:
            print(exc)
            return
        self.remember_change()
        self.edges.append(new_edge)
        print(f"Added: {first_id} <-> {node_id} ({new_edge['distance_px']} px)")

    def click_node_for_edit(self, node_id):
        if self.first_node_id is None:
            self.first_node_id = node_id
            print(f"New first endpoint: {node_id}. Click the new second endpoint.")
            return
        first_id = self.first_node_id
        self.first_node_id = None

        if first_id == node_id:
            print("Cancelled: both endpoints cannot be the same node.")
            return
        index = self.selected_edge_index
        if index is None:
            print("Select an existing edge before editing it.")
            return
        if self.connection_exists(first_id, node_id, ignore_index=index):
            print("Another edge already connects these two nodes. No change made.")
            return
        try:
            replacement = self.make_edge(first_id, node_id)
        except ValueError as exc:
            print(exc)
            return

        original = self.edges[index]
        if {original["from"], original["to"]} == {first_id, node_id}:
            print("These are already the edge's endpoints. No change made.")
            self.selected_edge_index = None
            return

        extras = set(original) - {"from", "to", "distance_px"}
        if extras:
            print(
                "Note: old edge-specific fields were not copied: "
                + ", ".join(sorted(extras))
            )
        self.remember_change()
        self.edges[index] = replacement
        self.selected_edge_index = None
        print(f"Updated: {first_id} <-> {node_id} ({replacement['distance_px']} px)")

    def on_mouse(self, event, x, y, flags, userdata):
        if self.search_active:
            return
        if event != cv2.EVENT_LBUTTONDOWN:
            return

        if self.mode == "connect":
            node_id = self.nearest_node(x, y)
            if node_id is None:
                print("Click closer to a red node.")
                return
            self.click_node_for_connection(node_id)
            return

        if self.mode == "delete":
            edge_index = self.nearest_edge(x, y)
            self.selected_edge_index = edge_index
            if edge_index is None:
                print("Click near the MIDDLE of a green line to select an edge.")
            else:
                edge = self.edges[edge_index]
                print(
                    f"Selected edge: {edge['from']} <-> {edge['to']}. "
                    "Press X to delete (or Esc to cancel)."
                )
            return

        # Edit mode: pick edge, then click two nodes to replace its endpoints.
        if self.selected_edge_index is None:
            edge_index = self.nearest_edge(x, y)
            if edge_index is None:
                print("Click near the middle of an existing green line first.")
                return
            self.selected_edge_index = edge_index
            edge = self.edges[edge_index]
            print(
                f"Editing {edge['from']} <-> {edge['to']}. "
                "Now click TWO new endpoint nodes."
            )
        else:
            node_id = self.nearest_node(x, y)
            if node_id is None:
                print("Click closer to a red node.")
                return
            self.click_node_for_edit(node_id)

    def draw(self):
        canvas = self.background.copy()
        for index, edge in enumerate(self.edges):
            a = self.nodes[edge["from"]]
            b = self.nodes[edge["to"]]
            color = SELECTED_YELLOW if index == self.selected_edge_index else EDGE_GREEN
            thickness = 3 if index == self.selected_edge_index else 2
            cv2.line(canvas, self.display_xy(a), self.display_xy(b), color, thickness)

        for node_id, node in self.nodes.items():
            color = SELECTED_YELLOW if node_id == self.first_node_id else NODE_RED
            radius = 5 if node_id == self.first_node_id else 3
            cv2.circle(canvas, self.display_xy(node), radius, color, -1)

        # Highlight ONLY the searched node. Other nodes remain small red dots.
        if self.found_node_id in self.nodes:
            node = self.nodes[self.found_node_id]
            x, y = self.display_xy(node)
            cv2.circle(canvas, (x, y), 15, FOUND_CYAN, 2, cv2.LINE_AA)
            cv2.circle(canvas, (x, y), 5, FOUND_CYAN, -1, cv2.LINE_AA)

            label = self.found_node_id
            font = cv2.FONT_HERSHEY_SIMPLEX
            font_scale = 0.55
            thickness = 2
            (label_w, label_h), _ = cv2.getTextSize(label, font, font_scale, thickness)
            # Keep label inside the image, even near its right/top edges.
            lx = x + 19 if x + label_w + 21 < self.display_w else x - label_w - 19
            ly = y - 16 if y - 16 > label_h else y + label_h + 19
            lx = max(0, min(lx, self.display_w - label_w - 1))
            ly = max(label_h + 1, min(ly, self.display_h - 1))
            cv2.putText(canvas, label, (lx, ly), font, font_scale,
                        FOUND_CYAN, thickness, cv2.LINE_AA)

        # Show a small, temporary search box while typing a node ID.
        if self.search_active:
            cv2.rectangle(canvas, (0, 0), (min(580, self.display_w), 38),
                          (35, 35, 35), -1)
            cv2.putText(canvas, "Find node: " + self.search_text + "_",
                        (8, 26), cv2.FONT_HERSHEY_SIMPLEX,
                        0.6, (255, 255, 255), 1, cv2.LINE_AA)
        return canvas

    def undo(self):
        self.cancel_selection()
        if not self.history:
            print("Nothing to undo in this session.")
            return
        self.edges[:] = self.history.pop()
        self.dirty = True
        print("Undid the last change.")

    def delete_selected_edge(self):
        if self.mode != "delete" or self.selected_edge_index is None:
            print("Switch to D, click an edge, then press X to delete.")
            return
        self.remember_change()
        edge = self.edges.pop(self.selected_edge_index)
        self.cancel_selection()
        print(f"Deleted: {edge['from']} <-> {edge['to']}")

    def save(self):
        if not self.dirty:
            print("No changes to save.")
            return

        # Save the previous on-disk version once per run before overwriting it.
        if not self.backup_created and GRAPH_FILE.exists():
            stamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
            backup = GRAPH_FILE.with_name(f"{GRAPH_FILE.stem}_backup_{stamp}.json")
            shutil.copy2(GRAPH_FILE, backup)
            self.backup_created = True
            print(f"Backup created: {backup.name}")

        temp_path = GRAPH_FILE.with_suffix(".json.tmp")
        try:
            with temp_path.open("w", encoding="utf-8") as f:
                json.dump(self.graph_data, f, ensure_ascii=False, indent=2)
            os.replace(temp_path, GRAPH_FILE)
        finally:
            if temp_path.exists():
                temp_path.unlink()

        self.dirty = False
        print(f"Saved {len(self.nodes)} nodes and {len(self.edges)} edges.")

    def run(self):
        print("\nMallPilot AI — Editable Graph Connections")
        print("C = connect  |  D = delete  |  E = edit endpoints")
        print("F = find node: type ID in map window then press Enter")
        print("U = undo     |  Esc = cancel |  X = confirm delete")
        print("S = save     |  Q = save and quit")
        print("Red dots = nodes; green lines = edges; yellow = selected")
        print("IMPORTANT: connect only direct walkable paths, not paths through walls.\n")

        cv2.namedWindow(WINDOW_NAME, cv2.WINDOW_AUTOSIZE)
        cv2.setMouseCallback(WINDOW_NAME, self.on_mouse)
        while True:
            cv2.imshow(WINDOW_NAME, self.draw())
            key = cv2.waitKey(20) & 0xFF
            if self.search_active:
                self.handle_search_key(key)
                continue
            if key == ord("f"):
                self.begin_find()
            elif key == ord("c"):
                self.set_mode("connect")
            elif key == ord("d"):
                self.set_mode("delete")
            elif key == ord("e"):
                self.set_mode("edit")
            elif key == ord("x"):
                self.delete_selected_edge()
            elif key == ord("u"):
                self.undo()
            elif key == 27:  # Escape
                self.cancel_selection()
                self.found_node_id = None
                print("Selection and search highlight cleared.")
            elif key == ord("s"):
                self.save()
            elif key == ord("q"):
                self.save()
                break

            try:
                if cv2.getWindowProperty(WINDOW_NAME, cv2.WND_PROP_VISIBLE) < 1:
                    self.save()
                    break
            except cv2.error:
                self.save()
                break
        cv2.destroyAllWindows()


if __name__ == "__main__":
    EdgeEditor().run()
