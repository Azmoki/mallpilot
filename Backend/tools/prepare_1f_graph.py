"""ONE-TIME copy of a mislabelled FIRST-floor graph to consistent 1F IDs.

This NEVER modifies the original file. Run ONLY after verifying the floor-plan
image and graph are actually the FIRST floor (not the ground floor).

    python tools/prepare_1f_graph.py --confirm-first-floor
"""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "data" / "mall_graph_GF.json"
DEST = ROOT / "data" / "mall_graph_1F.json"


def migrate(data):
    ids = [n["id"] for n in data["nodes"]]
    if any(not x.startswith("GF_") for x in ids):
        raise ValueError("Expected legacy GF_ node IDs. No changes made.")
    mapping = {x: "1F_" + x[3:] for x in ids}
    out = json.loads(json.dumps(data))
    out["floor"] = "1F"
    for node in out["nodes"]:
        node["id"] = mapping[node["id"]]
        node["floor"] = "1F"
    for edge in out["edges"]:
        edge["from"] = mapping[edge["from"]]
        edge["to"] = mapping[edge["to"]]
    return out


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--confirm-first-floor", action="store_true", help="Confirm map is actually first floor")
    args = p.parse_args()
    if not args.confirm_first_floor:
        p.error("Verify the image is FIRST floor; then pass --confirm-first-floor")
    if DEST.exists():
        raise FileExistsError(f"{DEST} exists; refusing to overwrite it.")
    with SRC.open(encoding="utf-8") as f:
        data = json.load(f)
    output = migrate(data)
    with DEST.open("w", encoding="utf-8") as f:
        json.dump(output, f, indent=2, ensure_ascii=False)
    print(f"Created {DEST} with {len(output['nodes'])} nodes and {len(output['edges'])} edges.")
    print(f"Original remains unchanged: {SRC}")
    print("IMPORTANT: first-floor image must be copied/renamed to data/floor_1F.png without resizing or cropping.")

if __name__ == "__main__":
    main()
