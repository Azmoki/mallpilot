"""Load the team's shops.json and separate store-to-graph mappings.

Do not add node_id to the shared shops.json. Keep floor-specific mappings in
store_node_map_GF.json / store_node_map_1F.json instead.
"""

import json
from pathlib import Path


class StoreDataManager:
    def __init__(self, shops_file, mapping_file=None, floor="GF"):
        self.floor = floor
        self.shops_file = Path(shops_file)
        self.mapping_file = Path(mapping_file) if mapping_file else None

        with self.shops_file.open("r", encoding="utf-8") as handle:
            all_shops = json.load(handle)
        if not isinstance(all_shops, list):
            raise ValueError("shops.json must contain a JSON list of shop objects")
        all_ids = [shop.get("id") for shop in all_shops]
        if any(not isinstance(shop_id, str) or not shop_id for shop_id in all_ids):
            raise ValueError("Each shop needs a nonempty string 'id'")
        if len(set(all_ids)) != len(all_ids):
            raise ValueError("Duplicate shop IDs detected in shops.json")

        self.shops = [shop for shop in all_shops
                      if shop.get("floor") == floor
                      and str(shop.get("status", "")).casefold() == "occupied"]
        self.by_id = {shop["id"].casefold(): shop for shop in self.shops}
        self.mappings = {}

        if self.mapping_file and self.mapping_file.exists():
            with self.mapping_file.open("r", encoding="utf-8") as handle:
                obj = json.load(handle)
            if not isinstance(obj, dict) or obj.get("floor") != floor:
                raise ValueError(f"Mapping file must have floor={floor!r}")
            node_map = obj.get("shop_nodes", {})
            if not isinstance(node_map, dict):
                raise ValueError("Mapping file 'shop_nodes' must be a JSON object")
            for shop_id, node_id in node_map.items():
                if shop_id.casefold() not in self.by_id:
                    raise ValueError(f"Mapping refers to unknown/non-occupied {floor} shop: {shop_id}")
                if not isinstance(node_id, str) or not node_id:
                    raise ValueError(f"Invalid mapped node ID for {shop_id}")
            if len(set(node_map.values())) < len(node_map):
                raise ValueError("More than one shop mapped to the same node. Resolve duplicates.")
            self.mappings = node_map

    def all_stores(self):
        """Only occupied stores on the requested floor, with optional node_id."""
        return [{**s, "node_id": self.mappings.get(s["id"])} for s in self.shops]

    def mapped_stores(self):
        return [s for s in self.all_stores() if s["node_id"]]

    def get(self, identifier):
        """Resolve by team shop ID, lot ID, any lot, or exact name."""
        key = str(identifier).strip().casefold()
        if not key:
            raise ValueError("Shop identifier cannot be empty")
        if key in self.by_id:
            record = self.by_id[key]
            return {**record, "node_id": self.mappings.get(record["id"])}

        matches = []
        for shop in self.shops:
            options = [shop.get("lot_id", ""), shop.get("primary_lot", ""),
                       shop.get("name", "")]
            options.extend(shop.get("lots") or [])
            if any(str(val).casefold() == key for val in options):
                matches.append(shop)
        if not matches:
            raise KeyError(f"No occupied {self.floor} shop matched {identifier!r}")
        if len(matches) != 1:
            raise ValueError(f"Ambiguous shop {identifier!r}: " + ", ".join(s["id"] for s in matches))
        record = matches[0]
        return {**record, "node_id": self.mappings.get(record["id"])}

    def validate_nodes(self, graph_nodes):
        """Return shop IDs with missing or non-store-entrance graph nodes."""
        lookup = graph_nodes if isinstance(graph_nodes, dict) else {
            node["id"]: node for node in graph_nodes
        }
        return [shop_id for shop_id, node_id in self.mappings.items()
                if node_id not in lookup or lookup[node_id].get("type") != "store_entrance"]
