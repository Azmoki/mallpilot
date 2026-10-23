r"""Basic smoke test of the running MallPilot FastAPI server.

Start FastAPI in another terminal first. From MallPilot-Backend root:
    .\.venv\Scripts\python.exe tools\test_api.py --start G13 --end G15
    .\.venv\Scripts\python.exe tools\test_api.py --start G52 --end G53
"""
import argparse
import json
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


def request_json(url, body=None):
    data = json.dumps(body).encode("utf-8") if body is not None else None
    request = Request(
        url,
        data=data,
        method="POST" if body is not None else "GET",
        headers={"Content-Type": "application/json"},
    )
    with urlopen(request, timeout=8) as response:
        return json.load(response)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--start", default="G13")
    parser.add_argument("--end", default="G15")
    parser.add_argument("--base", default="http://127.0.0.1:8000")
    args = parser.parse_args()
    base = args.base.rstrip("/")

    health = request_json(base + "/health")
    print("API health:", health)
    route = request_json(base + "/route", {
        "start_shop_id": args.start,
        "end_shop_id": args.end,
    })
    print(f"\n{route['start']['name']} -> {route['destination']['name']}")
    print("Path:", " -> ".join(p["node_id"] for p in route["path"]))
    print(f"Distance: {route['distance_px']} image pixels (not metres)")
    print("Route returned successfully via HTTP POST /route.")


if __name__ == "__main__":
    try:
        main()
    except HTTPError as exc:
        print(f"HTTP {exc.code}: {exc.read().decode('utf-8', errors='replace')}")
        raise SystemExit(1) from None
    except URLError as exc:
        print(f"Cannot reach the API: {exc}. Start uvicorn in another terminal.")
        raise SystemExit(1) from None
