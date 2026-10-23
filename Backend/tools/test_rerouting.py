r"""Simple local end-to-end corridor rerouting demonstration.

From project root, while Stage 9 server is running on port 8001:
 .\.venv\Scripts\python.exe tools\test_rerouting.py

Custom known graph edge and shops:
 .\.venv\Scripts\python.exe tools\test_rerouting.py --a GF_N083 --b GF_N085 --start shop_014 --end shop_028

The script ALWAYS reopens an edge it newly closed in a 'finally' block.
It will NOT reopen an edge that was already closed before this test.
"""

import argparse
import json
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


def call(base, method, endpoint, payload=None):
    body = None if payload is None else json.dumps(payload).encode("utf-8")
    request = Request(base + endpoint, data=body, method=method,
                      headers={"Content-Type": "application/json"})
    try:
        with urlopen(request, timeout=10) as response:
            return response.status, json.load(response)
    except HTTPError as exc:
        data = exc.read().decode("utf-8", errors="replace")
        try:
            data = json.loads(data)
        except json.JSONDecodeError:
            pass
        return exc.code, data


def summarize_route(label, status, result):
    if status != 200:
        print(f"{label}: HTTP {status} -> {result}")
    else:
        print(f"{label}: {result['distance_px']} px | " +
              " -> ".join(point["node_id"] for point in result["path"]))


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--base", default="http://127.0.0.1:8001")
    p.add_argument("--a", default="GF_N083", help="Node ID at one end of proposed closure")
    p.add_argument("--b", default="GF_N085", help="Node ID at other end")
    p.add_argument("--start", default="shop_014", help="Shop ID, lot, or exact name")
    p.add_argument("--end", default="shop_028", help="Destination shop")
    args = p.parse_args()
    try:
        _, health = call(args.base, "GET", "/health")
        print(f"Connected: {health.get('status')} ({health.get('floor')})")

        preview_request = {"from_node_id": args.a, "to_node_id": args.b,
                           "start_shop_id": args.start, "end_shop_id": args.end}
        code, preview = call(args.base, "POST", "/closures/preview", preview_request)
        if code != 200:
            raise RuntimeError(f"Preview HTTP {code}: {preview}")
        print("Edge preview:", args.a, "<->", args.b)
        print("Alternative available:", preview["alternative_available"])
        if preview["already_closed"]:
            print("Edge was already closed; leaving its previous state untouched.")
            return
        route_request = {"start_shop_id": args.start, "end_shop_id": args.end}
        code, result = call(args.base, "POST", "/route", route_request)
        summarize_route("Before closure", code, result)

        close_body = {"from_node_id": args.a, "to_node_id": args.b,
                      "reason": "Automatic local test (reopened afterward)"}
        code, closed = call(args.base, "POST", "/closures", close_body)
        if code != 200 or closed["status"] != "closed":
            raise RuntimeError(f"Could not close test edge: HTTP {code}: {closed}")
        try:
            code, result = call(args.base, "POST", "/route", route_request)
            summarize_route("After closure", code, result)
            if not preview["alternative_available"] and code == 409:
                print("No detour exists: HTTP 409 is expected. Try a corridor with an alternate path.")
        finally:
            code, reopened = call(args.base, "POST", "/closures/reopen", close_body)
            print(f"Cleanup: HTTP {code} | {reopened.get('status')}")

        code, result = call(args.base, "POST", "/route", route_request)
        summarize_route("After reopening", code, result)
    except (URLError, TimeoutError) as exc:
        raise SystemExit(f"Cannot contact the API: {exc}. Is uvicorn running on port 8001?") from exc


if __name__ == "__main__":
    main()
