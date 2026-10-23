"""Run on Windows when FastAPI is live, no third-party packages needed.
   py integration_tools/verify_backend.py http://127.0.0.1:8001
"""
import json
import sys
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError

BASE = (sys.argv[1] if len(sys.argv) > 1 else 'http://127.0.0.1:8001').rstrip('/')

def request(path, payload=None):
    data = json.dumps(payload).encode() if payload is not None else None
    req = Request(BASE + path, data=data, headers={'Content-Type': 'application/json'} if data else {})
    with urlopen(req, timeout=15) as response:
        return json.load(response)

try:
    health = request('/health')
    print('Health:', health)
    shops = request('/shops')
    by_id = {s['id']: s for s in shops['shops']}
    for id, name in [('shop_012','PUMA'), ('shop_014','SKECHERS'), ('shop_046',"JOHNNY'S"), ('shop_047','BURGER KING')]:
        assert by_id[id]['name'] == name, (id, by_id.get(id, {}))
    route = request('/route', {'start_shop_id': 'shop_012', 'end_shop_id': 'shop_014'})
    assert route['path'][0]['node_id'] == 'GF_N009'
    print('PUMA to SKECHERS:', route['distance_px'], 'px; points', len(route['path']))
    recs = request('/recommend-shops', {'query':'sportswear, food', 'max_results':6, 'mapped_only': True})
    print('Recommendations:', recs['count'])
    plan = request('/optimize-journey', {
        'start_shop_id':'shop_012','shop_ids':['shop_014','shop_046','shop_047'], 'mode':'visit_all'
    })
    print('Multi-stop order:', [s['name'] for s in plan['visit_order']])
    print('ALL BACKEND INTEGRATION REQUESTS PASSED')
except (AssertionError, KeyError, HTTPError, URLError, ValueError) as e:
    print('CHECK FAILED:', e)
    sys.exit(1)
