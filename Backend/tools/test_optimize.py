"""Call a running Stage 7 backend to test multi-stop journey optimisation.

    .\\.venv\\Scripts\\python.exe tools\\test_optimize.py --base-url http://127.0.0.1:8001

Before running: map every shop named in --shops to a GF store entrance.
"""
import argparse
import json
import urllib.error
import urllib.request


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", default="http://127.0.0.1:8001")
    parser.add_argument("--start", default="G13")
    parser.add_argument("--shops", nargs="+", default=["G15", "G03", "G39"])
    parser.add_argument("--minutes", type=float, default=120)
    parser.add_argument("--mode", choices=["visit_all", "fit_time"], default="visit_all")
    parser.add_argument("--meters-per-pixel", type=float)
    args = parser.parse_args()
    payload = {
        "start_shop_id": args.start,
        "shop_ids": args.shops,
        "time_limit_minutes": args.minutes,
        "mode": args.mode,
    }
    if args.meters_per_pixel is not None:
        payload["meters_per_pixel"] = args.meters_per_pixel
    url = args.base_url.rstrip("/") + "/optimize-journey"
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=25) as res:
            result = json.load(res)
    except urllib.error.HTTPError as exc:
        print(f"HTTP {exc.code}: {exc.read().decode('utf-8')}")
        raise SystemExit(1)
    except urllib.error.URLError as exc:
        raise SystemExit(f"Cannot reach {url}: {exc}")
    print("Visit order:", " -> ".join(
        [result["start"]["name"]] + [s["name"] for s in result["visit_order"]]
    ))
    print("Distance:", result["total_distance_px"], "image pixels")
    print("Store visit time:", result["total_visit_minutes"], "minutes")
    print("Time budget:", result["budget_status"])
    print("Full JSON:")
    print(json.dumps(result, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
