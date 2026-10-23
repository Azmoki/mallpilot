"""MallPilot: map the team's GF shops to your existing graph entrance nodes.

Run from your MallPilot-Backend folder (with the OpenCV window focused):
  .\\.venv\\Scripts\\python.exe tools\\map_stores.py --floor GF

Reads only (never changes):
  data/shops.json
  data/mall_graph_GF.json
  data/gf_light_map.png

Writes mappings only:
  data/store_node_map_GF.json

Keys: F=find shop ID/lot/name; N/P=next/previous shop; click red/cyan
store-entrance dot to assign; U=unmap; S=save; Q=save+quit; Esc=cancel search.
"""
import argparse
import json
import os
import shutil
import sys
from datetime import datetime
from pathlib import Path

import cv2

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from modules.store_manager import StoreDataManager

# OpenCV colour order is BGR.
RED = (0, 0, 255)
CYAN = (255, 255, 0)
YELLOW = (0, 255, 255)
GREEN = (0, 145, 0)
GREY = (130, 130, 130)
WHITE = (255, 255, 255)


class StoreMapper:
    def __init__(self, floor, graph_file, image_file, shops_file, mapping_file):
        self.floor = floor
        self.graph_file = Path(graph_file)
        self.image_file = Path(image_file)
        self.mapping_file = Path(mapping_file)
        self.manager = StoreDataManager(shops_file, mapping_file, floor)
        self.shops = self.manager.all_stores()
        self.mappings = dict(self.manager.mappings)
        if not self.shops:
            raise ValueError(f"No occupied shops found for {floor} in {shops_file}")

        with self.graph_file.open("r", encoding="utf-8") as handle:
            self.graph = json.load(handle)
        if self.graph.get("floor") != floor:
            raise ValueError(f"Graph is labelled {self.graph.get('floor')!r}, expected {floor!r}")
        raw_nodes = self.graph.get("nodes", [])
        self.nodes = {node["id"]: node for node in raw_nodes}
        if len(self.nodes) != len(raw_nodes) or not self.nodes:
            raise ValueError("Graph must contain nodes with unique IDs")
        wrong_floor = [nid for nid, node in self.nodes.items()
                       if node.get("floor", floor) != floor]
        if wrong_floor:
            raise ValueError(f"Node floors don't match {floor}: {wrong_floor[:5]}")
        self.entrances = {nid: node for nid, node in self.nodes.items()
                          if node.get("type") == "store_entrance"}
        if not self.entrances:
            raise ValueError("Graph has no store_entrance nodes to click")
        invalid_mappings = self.manager.validate_nodes(self.nodes)
        if invalid_mappings:
            raise ValueError(f"Mapped shops refer to missing/non-entrance nodes: {invalid_mappings}")
        for edge in self.graph.get("edges", []):
            if edge["from"] not in self.nodes or edge["to"] not in self.nodes:
                raise ValueError(f"Edge refers to a missing node: {edge}")

        self.image = cv2.imread(str(self.image_file))
        if self.image is None:
            raise FileNotFoundError(f"Cannot open mall image: {self.image_file}")
        self.ih, self.iw = self.image.shape[:2]
        if (self.iw, self.ih) != (self.graph.get("image_width"), self.graph.get("image_height")):
            raise ValueError("Image dimensions don't match graph JSON. Use the original map image.")
        scale = min(1.0, 1100 / self.iw, 750 / self.ih)
        self.dw, self.dh = max(1, round(self.iw * scale)), max(1, round(self.ih * scale))
        self.background = cv2.resize(self.image, (self.dw, self.dh))
        self.index = 0
        self.searching = False
        self.search_text = ""
        self.changed = False
        self.backup_done = False
        self.window = f"MallPilot - Shop to Entrance Mapping ({floor})"

    def display_xy(self, node):
        return (round(node["x"] * self.dw / self.iw),
                round(node["y"] * self.dh / self.ih))

    def nearest_entrance(self, x, y, radius=13):
        best_id, best_sq = None, radius * radius
        for node_id, node in self.entrances.items():
            nx, ny = self.display_xy(node)
            delta = (x - nx) ** 2 + (y - ny) ** 2
            if delta <= best_sq:
                best_id, best_sq = node_id, delta
        return best_id

    def assign(self, node_id):
        """Assign selected shop to one entrance; return True if mapping changed."""
        if node_id not in self.entrances:
            print(f"{node_id} is not a store_entrance node. No change.")
            return False
        shop = self.shops[self.index]
        shop_id = shop["id"]
        existing_owner = next((sid for sid, nid in self.mappings.items()
                               if nid == node_id and sid != shop_id), None)
        if existing_owner:
            owner = self.manager.by_id[existing_owner.casefold()]
            print(f"Cannot assign {node_id}: already used by {owner['name']} ({existing_owner}).")
            return False
        if self.mappings.get(shop_id) == node_id:
            print(f"Already mapped: {shop_id} -> {node_id}")
            return False
        old_node = self.mappings.get(shop_id)
        self.mappings[shop_id] = node_id
        self.changed = True
        print(f"Mapped {shop_id} ({shop['lot_id']}, {shop['name']}) -> {node_id}" +
              (f" (was {old_node})" if old_node else ""))
        return True

    def on_mouse(self, event, x, y, flags, userdata):
        if event != cv2.EVENT_LBUTTONDOWN or self.searching:
            return
        node_id = self.nearest_entrance(x, y)
        if not node_id:
            print("Click close to a store-entrance dot (not a grey junction).")
            return
        if self.assign(node_id):
            self.index = (self.index + 1) % len(self.shops)

    def unmap(self):
        shop = self.shops[self.index]
        old_node = self.mappings.pop(shop["id"], None)
        if old_node:
            self.changed = True
            print(f"Unmapped {shop['id']} ({shop['name']}) from {old_node}")
        else:
            print(f"{shop['name']} is not mapped yet")

    def find_shop(self, query):
        query = query.strip().casefold()
        if not query:
            print("Search is empty. Enter a shop ID, lot ID, or name.")
            return False
        matches = []
        for i, shop in enumerate(self.shops):
            terms = [shop["id"], shop.get("lot_id", ""),
                     shop.get("primary_lot", ""), shop.get("name", "")]
            terms.extend(shop.get("lots") or [])
            if any(query in str(term).casefold() for term in terms):
                matches.append(i)
        if not matches:
            print(f"No occupied {self.floor} shop matched {query!r}")
            return False
        # Prefer exact ID/lot/name matches over partial matches.
        exact = [i for i in matches if query in (
            str(self.shops[i].get("id", "")).casefold(),
            str(self.shops[i].get("lot_id", "")).casefold(),
            str(self.shops[i].get("primary_lot", "")).casefold(),
            str(self.shops[i].get("name", "")).casefold(),
        ) or query in [str(v).casefold() for v in (self.shops[i].get("lots") or [])]]
        self.index = exact[0] if exact else matches[0]
        s = self.shops[self.index]
        print(f"Selected {s['id']} | Lot {s['lot_id']} | {s['name']}"
              + (f" (found {len(matches)} possible matches)" if len(matches)>1 else ""))
        return True

    def save(self):
        if not self.changed:
            print("No mapping changes to save.")
            return
        # Do not modify your teammate's shops.json or the mall graph.
        self.mapping_file.parent.mkdir(parents=True, exist_ok=True)
        if not self.backup_done and self.mapping_file.exists():
            stamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
            backup = self.mapping_file.with_name(
                f"{self.mapping_file.stem}_backup_{stamp}.json")
            shutil.copy2(self.mapping_file, backup)
            print(f"Mapping backup created: {backup.name}")
            self.backup_done = True
        output = {"floor": self.floor, "shop_nodes": dict(sorted(self.mappings.items()))}
        tmp = self.mapping_file.with_suffix(".json.tmp")
        try:
            with tmp.open("w", encoding="utf-8") as handle:
                json.dump(output, handle, indent=2, ensure_ascii=False)
            os.replace(tmp, self.mapping_file)
        finally:
            if tmp.exists():
                tmp.unlink()
        self.changed = False
        print(f"Saved {len(self.mappings)}/{len(self.shops)} shop mappings to {self.mapping_file}")

    def draw(self):
        canvas = self.background.copy()
        # Draw walking corridors as thin lines, keeping the floor plan visible.
        for edge in self.graph.get("edges", []):
            cv2.line(canvas,
                     self.display_xy(self.nodes[edge["from"]]),
                     self.display_xy(self.nodes[edge["to"]]), GREEN, 1)
        mapped_nodes = set(self.mappings.values())
        # Grey junctions; store entrances red unless mapped (cyan).
        for node_id, node in self.nodes.items():
            color = CYAN if node_id in mapped_nodes else (
                RED if node_id in self.entrances else GREY)
            cv2.circle(canvas, self.display_xy(node), 4 if node_id in self.entrances else 2,
                       color, -1)
        shop = self.shops[self.index]
        mapped_id = self.mappings.get(shop["id"])
        if mapped_id:
            nx, ny = self.display_xy(self.nodes[mapped_id])
            cv2.circle(canvas, (nx, ny), 12, YELLOW, 2)
            tx, ty = min(nx+12, max(0,self.dw-110)), max(74, ny-12)
            cv2.putText(canvas, mapped_id, (tx, ty), cv2.FONT_HERSHEY_SIMPLEX,
                        .45, YELLOW, 1, cv2.LINE_AA)
        # 60 px top overlay with current shop and progress.
        cv2.rectangle(canvas, (0, 0), (self.dw, 62), (35,35,35), -1)
        if self.searching:
            first_line = "FIND SHOP (ID / lot / name): " + self.search_text + "_"
        else:
            first_line = (f"{self.floor} {self.index+1}/{len(self.shops)} | "
                          f"{shop['id']} | {shop['lot_id']} | {shop['name']}")
        second_line = (f"Mapped {len(self.mappings)}/{len(self.shops)} | "
                       f"Node: {mapped_id or '-'} | F find, N/P browse, click assign, "
                       "U unmap, S save, Q quit")
        cv2.putText(canvas, first_line[:95], (7, 22), cv2.FONT_HERSHEY_SIMPLEX,
                    .49, WHITE, 1, cv2.LINE_AA)
        cv2.putText(canvas, second_line[:125], (7, 47), cv2.FONT_HERSHEY_SIMPLEX,
                    .39, WHITE, 1, cv2.LINE_AA)
        return canvas

    def run(self):
        print(f"\nMallPilot - Mapping {len(self.shops)} occupied {self.floor} shops to "
              f"{len(self.entrances)} store entrance nodes.")
        print("F = Find shop | N/P = Next/previous | Left-click = Map selected shop")
        print("U = Unmap shop | S = Save | Q = Save & quit | Esc = Cancel search")
        print("Grey dots = other nodes; red = unmapped entrances; cyan = mapped entrances.")
        if len(self.shops) > len(self.entrances):
            print(f"NOTE: {len(self.shops)} shops but only {len(self.entrances)} entrances. "
                  "Mapping all shops one-to-one requires more entrance nodes.")
        cv2.namedWindow(self.window, cv2.WINDOW_AUTOSIZE)
        cv2.setMouseCallback(self.window, self.on_mouse)
        while True:
            cv2.imshow(self.window, self.draw())
            key = cv2.waitKey(25) & 0xFF
            if self.searching:
                if key in (10, 13):  # Enter
                    self.find_shop(self.search_text)
                    self.search_text = ""
                    self.searching = False
                elif key == 27:
                    self.search_text = ""
                    self.searching = False
                    print("Search cancelled")
                elif key in (8, 127):
                    self.search_text = self.search_text[:-1]
                elif 32 <= key <= 126:
                    self.search_text += chr(key)
            elif key == ord("f"):
                self.searching = True
                self.search_text = ""
            elif key == ord("n"):
                self.index = (self.index + 1) % len(self.shops)
            elif key == ord("p"):
                self.index = (self.index - 1) % len(self.shops)
            elif key == ord("u"):
                self.unmap()
            elif key == ord("s"):
                self.save()
            elif key == ord("q"):
                self.save()
                break
            elif key == 27:
                print("No selection to cancel (use F to search).")
            try:
                if cv2.getWindowProperty(self.window, cv2.WND_PROP_VISIBLE) < 1:
                    self.save()
                    break
            except cv2.error:
                self.save()
                break
        cv2.destroyAllWindows()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--floor", choices=("GF", "1F"), default="GF")
    parser.add_argument("--graph", type=Path)
    parser.add_argument("--image", type=Path)
    parser.add_argument("--shops", type=Path)
    parser.add_argument("--mapping", type=Path)
    args = parser.parse_args()
    graph = args.graph or (ROOT / "data" / f"mall_graph_{args.floor}.json")
    image = args.image or (ROOT / "data" / ("gf_light_map.png" if args.floor == "GF" else "floor_1F.png"))
    shops = args.shops or (ROOT / "data" / "shops.json")
    mapping = args.mapping or (ROOT / "data" / f"store_node_map_{args.floor}.json")
    StoreMapper(args.floor, graph, image, shops, mapping).run()


if __name__ == "__main__":
    main()
