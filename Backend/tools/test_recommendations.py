"""Test a running Stage 8 API via HTTP (no Flutter required).

Usage (from project root, with uvicorn api:app running on port 8001):
    .\.venv\Scripts\python.exe tools\test_recommendations.py
    .\.venv\Scripts\python.exe tools\test_recommendations.py --base-url http://127.0.0.1:8001
"""
import argparse
import json
import urllib.error
import urllib.request


def post(base_url, endpoint, payload):
    url = base_url.rstrip("/") + endpoint
    request = urllib.request.Request(
        url, data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"}, method="POST"
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response)
    except urllib.error.HTTPError as exc:
        raise SystemExit(f"HTTP {exc.code}: {exc.read().decode('utf-8')}") from exc
    except urllib.error.URLError as exc:
        raise SystemExit(f"Cannot reach {url}: {exc}") from exc


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", default="http://127.0.0.1:8001")
    parser.add_argument("--start", default="shop_012",
                        help="Mapped starting shop, default PUMA")
    parser.add_argument("--interests", nargs="+", default=["sportswear", "food"])
    parser.add_argument("--budget", type=float, default=200)
    parser.add_argument("--stops", type=int, default=3)
    parser.add_argument("--minutes", type=float, default=120)
    args = parser.parse_args()

    shared = {"interests": args.interests, "budget_rm": args.budget}
    r = post(args.base_url, "/recommend-shops", {**shared, "max_results": 8})
    print("\nTOP MATCHES:")
    for shop in r["recommendations"]:
        flag = "mapped" if shop["route_ready"] else "unmapped"
        print(f"  {shop['name']} ({shop['lot_id']}) [{flag}], score {shop['relevance_score']}")

    plan = post(args.base_url, "/recommend-journey", {
        **shared, "start_shop_id": args.start,
        "max_stops": args.stops, "time_limit_minutes": args.minutes,
        "mode": "visit_all",
    })
    print("\nJOURNEY STATUS:", plan["status"])
    if plan["journey"]:
        trip = plan["journey"]
        print("Visit order:", " -> ".join([trip["start"]["name"]] + [
            store["name"] for store in trip["visit_order"]]))
        print("Distance:", trip["total_distance_px"], "image pixels")
        print("Store visit time:", trip["total_visit_minutes"], "minutes")
        print("Time-budget status:", trip["budget_status"])
        print("Estimated walking time:", trip["estimated_walking_minutes"])
        print("Indicative minimum total price:", plan["candidate_minimum_price_total_rm"], "RM")
    else:
        print(plan["reason"])
    print("\nFULL JOURNEY RESPONSE:")
    print(json.dumps(plan, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
